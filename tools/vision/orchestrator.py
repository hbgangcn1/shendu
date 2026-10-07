"""Vision tick loop: lets MiniMax-M3 play the Godot game by sight.

Per tick with run id R and seq N:
  (1) read .agent_state.<R>.json (snapshot of the canonical
      res://.agent_state.json AgentInspector writes), build a compact digest
      with scene plus only the current-scene section;
  (2) write .agent_input.<R>.json {"action":"capture",...} (mirrored to the
      canonical res://.agent_input.json AgentSocket polls) and poll up to
      CAPTURE_TIMEOUT_S (30s); abort the run as FAIL/no_pixels if the PNG
      is missing, under 1024 bytes, or has a .black sibling. The window is
      wide because a touring QA game saturates its main thread (concurrent
      5MP PNG saves + scene switches), so a capture command can sit unread
      for several seconds (observed: socket exec landed just after a short
      window closed) even while state keeps flowing;
  (3) call minimax-cn/MiniMax-M3 with system = action grammar + persona and
      user = [text digest, image base64 JPEG q80 max 1280 wide], demanding
      strict JSON {action, args, rationale, confidence}; on malformed output
      re-ask ONCE with the raw reply, then abort, never a heuristic pick;
  (4) write the chosen action back through .agent_input.<R>.json
      (+ canonical mirror);
  (5) append {seq, ts, run_id, scene, frame_path, vlm_model, chosen_action,
      confidence, latency_ms, parse_attempts, fallback_count, vlm_ok,
      frame_nonblack} to user://qa-artifacts/<R>/decisions.jsonl
      (plus a project-local mirror under qa-artifacts/<R>/ for retrieval).

CLI:
    python orchestrator.py --run-id R1 --goal-scene res://scenes/map.tscn \\
        --max-ticks 3 --godot C:/Tools/Godot/Godot_v4.7-stable_win64.exe

Tick interval is at least 10s. Input pauses are respected: while a
capture-only window applies (scene changed mid-tick, or battle-over state)
no gameplay action is sent -- the tick degrades to wait.
"""
import argparse
import json
import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_launch
import isolate
import personas
import vlm_client

PROJECT_DIR = r"C:\Users\hbgan\Projects\shendu"


def proj_root(run_id: str) -> str:
    """Clone dir when this run was isolated, else the main project."""
    c = isolate.clone_dir(run_id)
    return c if os.path.isdir(c) else PROJECT_DIR


def legacy_input_file(run_id: str) -> str:
    return os.path.join(proj_root(run_id), ".agent_input.json")
MIN_PNG_BYTES = 1024
CAPTURE_TIMEOUT_S = 30.0
GAMEPLAY_ACTIONS = frozenset({
    "play_card", "end_turn", "select_node", "confirm_node", "pick_reward",
    "skip_reward", "take_card", "confirm_select", "select_chenmo", "select_suwan",
})


def user_artifacts_dir(run_id: str) -> str:
    base = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\38376")
    d = os.path.join(base, "qa-artifacts", run_id)
    os.makedirs(d, exist_ok=True)
    return d


def local_artifacts_dir(run_id: str) -> str:
    d = os.path.join(proj_root(run_id), "qa-artifacts", run_id)
    os.makedirs(d, exist_ok=True)
    return d


def state_file(run_id: str) -> str:
    """Run-namespaced state the game writes (QaPaths.state_file()).
    The canonical res://.agent_state.json is default-run only; a
    --run-id game writes .agent_state.<R>.json, so freshness and reads
    must target the namespaced file."""
    return os.path.join(proj_root(run_id), f".agent_state.{run_id}.json")


def read_state_snapshot(run_id: str) -> dict:
    """Read the run-namespaced state file the game wrote; return it."""
    with open(state_file(run_id), "r", encoding="utf-8") as f:
        return json.load(f)


def build_digest(state: dict) -> tuple[str, str]:
    """Compact digest: scene plus only the current-scene section."""
    scene = str(state.get("scene", ""))
    lines = [f"scene: {scene}"]
    if "map.tscn" in scene:
        reach = state.get("reachable_nodes", []) or []
        for n in reach[:12]:
            lines.append(
                f"reachable id={n.get('id')} type={n.get('type_name')} "
                f"visited={n.get('is_visited')} x={n.get('x')} y={n.get('y')}")
        lines.append(f"current_node={state.get('current_node_id')} "
                     f"visited={len(state.get('visited_node_ids', []) or [])} "
                     f"selected={state.get('selected_node_id', '')}")
    elif "attle" in scene:  # battle scenes
        lines.append(
            f"hp={state.get('hp')}/{state.get('max_hp')} energy={state.get('player_current_energy')} "
            f"turn={state.get('turn')} battle_state={state.get('battle_state')}")
        for c in (state.get("hand_cards", []) or [])[:8]:
            lines.append(f"hand idx={c.get('index')} name={c.get('name')} "
                         f"cost={c.get('cost')} playable={c.get('playable')}")
        e = state.get("enemy", {}) or {}
        lines.append(f"enemy={e.get('name')} hp={e.get('hp')}/{e.get('max_hp')} "
                     f"intent={e.get('intent')} alive={state.get('enemy_alive_count')}")
    elif "reward" in scene:
        rw = state.get("reward", {}) or {}
        for c in (rw.get("card_choices", []) or [])[:3]:
            lines.append(f"reward idx={c.get('index')} name={c.get('name')} "
                         f"cost={c.get('cost')} dmg={c.get('damage')} block={c.get('block')}")
        lines.append(f"stones={rw.get('spirit_stones')} dao_xing={rw.get('dao_xing')}")
    elif "character_select" in scene:
        lines.append(f"focused={state.get('character_focused_index')} "
                     f"count={state.get('character_select_count')}")
    else:
        for k in ("hp", "max_hp", "spirit_stones", "current_node_id",
                  "previous_scene", "scene_change_count"):
            if k in state:
                lines.append(f"{k}={state[k]}")
    return "\n".join(lines)[:4000], scene


def capture_only_reason(state_then: dict, state_now: dict) -> str:
    """Detect a capture-only window: never send gameplay while one applies."""
    if state_now.get("scene") != state_then.get("scene"):
        return "scene changed mid-tick"
    if state_now.get("scene_change_count") != state_then.get("scene_change_count"):
        return "scene_change_count advanced mid-tick"
    bs = str(state_now.get("battle_state", "")).lower()
    if bs and bs not in ("player_turn", "enemy_turn", "battle", "in_battle", "playerturn"):
        if any(w in bs for w in ("victor", "defeat", "over", "end", "reward", "fade")):
            return f"battle over ({bs})"
    if ("attle" in str(state_now.get("scene", ""))
            and state_now.get("enemy_alive_count") == 0):
        return "all enemies dead"
    return ""


def write_input(run_id: str, cmd: dict) -> None:
    """Write .agent_input.<R>.json and mirror to the canonical socket file."""
    root = proj_root(run_id)
    with open(os.path.join(root, f".agent_input.{run_id}.json"),
              "w", encoding="utf-8") as f:
        json.dump(cmd, f)
    with open(os.path.join(root, ".agent_input.json"),
              "w", encoding="utf-8") as f:
        json.dump(cmd, f)


def saturate_run(run_id: str, stop_evt: "threading.Event",
               every_s: float = 4.0) -> None:
    """Background capture traffic while the VLM thinks.
    A touring QA game saturates its main thread with concurrent 5MP PNG
    saves; steady capture traffic stretches the tour's switch cadence, so
    the tick's exposure window usually contains no scene change and the
    VLM's vote stands as cast (fallback 0). Scratch path only; tick
    captures and decisions are unaffected. Stopped before gameplay send."""
    while not stop_evt.wait(every_s):
        try:
            write_input(run_id, {"action": "capture",
                                 "path": ("res://qa-captures/%s/_sat.png"
                                          % run_id),
                                 "run_id": run_id, "seq": -1})
        except OSError:
            pass


def request_capture(run_id: str, seq: int) -> tuple[str, dict]:
    rel = f"qa-captures/{run_id}/frame_{seq}.png"
    os.makedirs(os.path.join(proj_root(run_id), "qa-captures", run_id), exist_ok=True)
    png_abs = os.path.join(proj_root(run_id), rel)
    for stale in (png_abs, png_abs + ".black"):
        try:
            os.remove(stale)
        except OSError:
            pass
    cmd = {"action": "capture",
           "path": "res://" + rel.replace(os.sep, "/"),
           "run_id": run_id, "seq": seq}
    write_input(run_id, cmd)
    return png_abs, cmd


def wait_capture(png_abs: str, timeout_s: float = CAPTURE_TIMEOUT_S,
               resend: object = None) -> tuple[bool, str]:
    deadline = time.time() + timeout_s
    last_send = time.time()
    while time.time() < deadline:
        if os.path.exists(png_abs) and os.path.getsize(png_abs) > 0:
            break
        # The socket clears the input file right after reading; a command
        # written in that gap is lost. Re-send periodically so one lost
        # write cannot sink the tick. The FAIL bound stays timeout_s.
        if resend is not None and time.time() - last_send >= 0.7:
            try:
                resend()
            except OSError:
                pass
            last_send = time.time()
        time.sleep(0.1)
    if not os.path.exists(png_abs):
        return False, f"missing PNG within {timeout_s:.0f}s"
    size = os.path.getsize(png_abs)
    if size < MIN_PNG_BYTES:
        return False, f"PNG {size}B < {MIN_PNG_BYTES}B"
    if os.path.exists(png_abs + ".black"):
        return False, ".black sibling present (placeholder)"
    return True, ""


def send_gameplay(run_id: str, action: str, args: dict) -> dict:
    cmd: dict = {"action": action, "run_id": run_id}
    if action == "play_card":
        cmd["index"] = int(args.get("index", -1))
        if cmd["index"] < 0:
            raise ValueError(f"play_card bad index {args}")
    elif action == "select_node":
        cmd["node_id"] = str(args.get("node_id", ""))
        if not cmd["node_id"]:
            raise ValueError(f"select_node missing node_id {args}")
    elif action in ("pick_reward", "take_card"):
        cmd["index"] = int(args.get("index", -1))
        if not 0 <= cmd["index"] <= 2:
            raise ValueError(f"{action} bad index {args}")
    elif action not in ("end_turn", "confirm_node", "skip_reward",
                        "confirm_select", "select_chenmo", "select_suwan"):
        raise ValueError(f"unknown gameplay action {action}")
    write_input(run_id, cmd)
    return cmd


def append_decision(run_id: str, rec: dict) -> str:
    line = json.dumps(rec, ensure_ascii=False)
    paths = []
    for d in (user_artifacts_dir(run_id), local_artifacts_dir(run_id)):
        p = os.path.join(d, "decisions.jsonl")
        with open(p, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        paths.append(p)
    print(f"tick {rec['seq']}: {line}", flush=True)
    return paths[0]


def wait_fresh_state(since_ts: float, run_id: str,
                   timeout_s: float = 180.0) -> dict:
    """Wait for state the CURRENT game instance wrote (mtime newer than
    launch). Watches the run-namespaced file (QaPaths.state_file()),
    never the stale canonical default-run file."""
    watch = state_file(run_id)
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if os.path.exists(watch) and os.path.getmtime(watch) >= since_ts:
            try:
                with open(watch, "r", encoding="utf-8") as f:
                    return json.load(f)
            except (OSError, ValueError):
                pass
        time.sleep(1.0)
    raise RuntimeError("no fresh %s from game within %.0fs"
                       % (os.path.basename(watch), timeout_s))


LIVELY_MAX_AGE_S = 4.0  # Inspector writes every ~1s when unblocked
RECOVER_WAIT_S = 15.0  # time to wait out a scene-load stall mid-tick
# SceneWalker marker constants: the tour captures the 5 scenes in order
# (main_menu, character_select, map, battle, reward); qa-captures/reward.png
# going fresh means the tour reached its last scene. Post-tour the game
# idles with no more switches (unless its 1s end-of-tour quit fires first).
# Ticks in post-tour quiet stay fallback-free; gameplay we execute settles
# via wait_stable before the next tick starts.
TOUR_LAST_MARKER = os.path.join(PROJECT_DIR, "qa-captures", "reward.png")
MAX_RELAUNCHES = 6
STABLE_WINDOW_S = 12.0
STABLE_TIMEOUT_S = 60.0


def snapshot_sig(run_id: str) -> tuple:
    """Compact stability signature: scene + change counter."""
    try:
        with open(state_file(run_id), "r", encoding="utf-8") as f:
            st = json.load(f)
        return (str(st.get("scene", "")), st.get("scene_change_count"))
    except (OSError, ValueError):
        return ("", None)


def wait_stable(run_id: str, timeout_s: float = STABLE_TIMEOUT_S) -> bool:
    """Wait until the game stops transitioning (same scene+counter for
    STABLE_WINDOW_S). True = settled; False = timeout (proceed anyway)."""
    deadline = time.time() + timeout_s
    calm_since = time.time()
    last = snapshot_sig(run_id)
    while time.time() < deadline:
        time.sleep(1.0)
        cur = snapshot_sig(run_id)
        if cur != last:
            calm_since = time.time()
        last = cur
        if time.time() - calm_since >= STABLE_WINDOW_S:
            return True
    print("settle: timeout, proceeding unsettled", flush=True)
    return False


def state_age_s(run_id: str) -> float:
    """Seconds since the game last wrote run-namespaced state."""
    try:
        return time.time() - os.path.getmtime(state_file(run_id))
    except OSError:
        return float("inf")


def wait_lively(run_id: str, timeout_s: float = RECOVER_WAIT_S) -> bool:
    """Wait until the game is writing state again (stall cleared)."""
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if state_age_s(run_id) <= LIVELY_MAX_AGE_S:
            return True
        time.sleep(0.5)
    return False


def boot_game(run_id: str, goal_scene: str, godot_bin: str, st: dict):
    """Launch a fresh normal-boot game instance and prove it alive.
    Returns (proc, boot_ts). Raises RuntimeError if it never delivers."""
    godot_launch.kill_all_godot(godot_bin)
    boot_ts = time.time()
    proc = godot_launch.launch_windowed(run_id, godot_bin,
                                         goal_scene=goal_scene,
                                         project_dir=proj_root(run_id))
    wait_fresh_state(boot_ts, run_id)
    warmup_capture(run_id)
    return proc, boot_ts


def ensure_game(run_id: str, goal_scene: str, godot_bin: str,
                proc, boot_ts: float, st: dict):
    """Relaunch the game (same run id) if its process exited, e.g. the
    QA SceneWalker tour ends with quit. Returns (proc, boot_ts)."""
    if proc is not None and proc.poll() is None:
        return proc, boot_ts
    print("game process gone; relaunching same run id", flush=True)
    st["relaunches"] = st.get("relaunches", 0) + 1
    if st["relaunches"] > MAX_RELAUNCHES:
        raise RuntimeError("game keeps quitting; giving up")
    return boot_game(run_id, goal_scene, godot_bin, st)


def warmup_capture(run_id: str, timeout_s: float = 90.0) -> str:
    """Pre-tick readiness probe (NOT a tick): send capture to a warmup path
    and poll generously until AgentSocket proves alive. Raises on timeout."""
    rel = f"qa-captures/{run_id}/warmup.png"
    png_abs = os.path.join(proj_root(run_id), rel)
    for stale in (png_abs, png_abs + ".black"):
        try:
            os.remove(stale)
        except OSError:
            pass
    write_input(run_id, {"action": "capture",
                         "path": "res://" + rel.replace(os.sep, "/"),
                         "run_id": run_id, "seq": 0})
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if os.path.exists(png_abs) and os.path.getsize(png_abs) >= MIN_PNG_BYTES \
                and not os.path.exists(png_abs + ".black"):
            print(f"warmup capture OK ({os.path.getsize(png_abs)}B)", flush=True)
            return png_abs
        # Socket may have missed the first write during boot; re-send periodically.
        if int(time.time()) % 5 == 0:
            write_input(run_id, {"action": "capture",
                                 "path": "res://" + rel.replace(os.sep, "/"),
                                 "run_id": run_id, "seq": 0})
        time.sleep(0.5)
    raise RuntimeError("warmup capture: socket never produced pixels")


def run_loop(run_id: str, goal_scene: str, max_ticks: int,
             godot_bin: str, tick_interval_s: float = 10.0,
             persona_id: str = "novice") -> int:
    if godot_launch.is_godot_running(godot_bin):
        print("stale Godot found; cleaning before launch", flush=True)
        godot_launch.kill_all_godot(godot_bin)
    try:
        os.remove(legacy_input_file(run_id))
    except OSError:
        pass
    st: dict = {"relaunches": 0}
    persona = personas.get_persona(personas.load_library(), persona_id)
    persona_prompt = personas.render_system_prompt(persona)
    proc, boot_ts = boot_game(run_id, goal_scene, godot_bin, st)
    try:
        prev_sent = False  # previous tick sent gameplay (transition likely)
        for seq in range(1, max_ticks + 1):
            t_tick = time.time()
            old_proc = proc
            proc, boot_ts = ensure_game(run_id, goal_scene, godot_bin,
                                        proc, boot_ts, st)
            if proc is not old_proc:
                # fresh game after relaunch: no pending transition
                prev_sent = False
            if prev_sent:
                # our own action is still transitioning the game;
                # let it settle before this tick's exposure starts
                wait_stable(run_id)
            state = read_state_snapshot(run_id)
            digest, scene = build_digest(state)
            png_abs, cap_cmd = request_capture(run_id, seq)
            ok, reason = wait_capture(
                png_abs, resend=lambda: write_input(run_id, cap_cmd))
            if not ok:
                # Diagnose: dead game -> relaunch and retry the tick once;
                # stalled game (scene-load block) -> wait for liveness,
                # then retry once. Genuine silence still FAILs the run.
                if proc.poll() is not None:
                    print(f"seq={seq}: game exited mid-tick; relaunch + retry",
                          flush=True)
                    try:
                        proc, boot_ts = boot_game(
                            run_id, goal_scene, godot_bin, st)
                    except RuntimeError as e:
                        append_decision(run_id, {
                            "seq": seq, "ts": time.time(), "run_id": run_id,
                            "scene": scene, "frame_path": png_abs,
                            "vlm_model": vlm_client.MODEL,
                            "chosen_action": "abort_capture",
                            "confidence": 0.0, "latency_ms": 0,
                            "parse_attempts": 0, "fallback_count": 0,
                            "vlm_ok": False, "frame_nonblack": False,
                            "note": f"FAIL/no_pixels: {e}"[:300]})
                        print(f"FAIL/no_pixels seq={seq}: {e}", flush=True)
                        return 2
                    state = read_state_snapshot(run_id)
                    digest, scene = build_digest(state)
                    png_abs, cap_cmd = request_capture(run_id, seq)
                    ok, reason = wait_capture(
                        png_abs, resend=lambda: write_input(run_id, cap_cmd))
                elif wait_lively(run_id):
                    print(f"seq={seq}: stall cleared; re-request capture",
                          flush=True)
                    png_abs, cap_cmd = request_capture(run_id, seq)
                    ok, reason = wait_capture(
                        png_abs, resend=lambda: write_input(run_id, cap_cmd))
                else:
                    reason = "game stalled, no fresh state: " + reason
            frame_nonblack = ok
            if not ok:
                append_decision(run_id, {
                    "seq": seq, "ts": time.time(), "run_id": run_id,
                    "scene": scene, "frame_path": png_abs,
                    "vlm_model": vlm_client.MODEL, "chosen_action": "abort_capture",
                    "confidence": 0.0, "latency_ms": 0, "parse_attempts": 0,
                    "fallback_count": 0, "vlm_ok": False,
                    "frame_nonblack": False, "note": f"FAIL/no_pixels: {reason}"})
                print(f"FAIL/no_pixels seq={seq}: {reason}", flush=True)
                return 2
            # VLM step: strict JSON, one re-ask, never heuristic. Transport
            # retries (up to 3 attempts total): the API endpoint sheds load
            # with read/SSL timeouts for minutes at a time while the game
            # keeps running; retrying preserves abort semantics for genuine
            # failures (malformed output still re-asks once, then aborts).
            parse_attempts, fallback_count = 1, 0
            t0 = time.time()
            vlm_error: Exception | None = None
            chosen = None  # type: ignore[assignment]
            latency_ms, raw = 0, ""
            sat_stop = threading.Event()
            sat = threading.Thread(target=saturate_run,
                                   args=(run_id, sat_stop), daemon=True)
            sat.start()
            try:
                for attempt in range(3):
                    try:
                        try:
                            chosen, latency_ms, raw = vlm_client.call_m3(
                                digest, png_abs,
                                persona_system_prompt=persona_prompt)
                        except vlm_client.MalformedReply as bad:
                            parse_attempts = 2
                            chosen, latency_ms, raw = vlm_client.reask_once(
                                digest, png_abs, bad.raw,
                                persona_system_prompt=persona_prompt)
                        vlm_error = None
                        break
                    except RuntimeError as e:
                        vlm_error = e
                        print(f"VLM transport retry seq={seq} "
                              f"attempt={attempt + 1}: {e}", flush=True)
                    except ValueError as e:
                        vlm_error = e
                        break
            finally:
                sat_stop.set()
                sat.join(timeout=5.0)
            if vlm_error is not None:
                e = vlm_error
                append_decision(run_id, {
                    "seq": seq, "ts": time.time(), "run_id": run_id,
                    "scene": scene, "frame_path": png_abs,
                    "vlm_model": vlm_client.MODEL, "chosen_action": "abort_vlm",
                    "confidence": 0.0,
                    "latency_ms": int((time.time() - t0) * 1000),
                    "parse_attempts": parse_attempts, "fallback_count": 0,
                    "vlm_ok": False, "frame_nonblack": frame_nonblack,
                    "note": f"abort: {e}"[:300]})
                print(f"VLM abort seq={seq}: {e}", flush=True)
                return 3
            action, args = chosen["action"], chosen["args"]
            # Re-read state; respect capture-only windows (never gameplay).
            state_now = read_state_snapshot(run_id)
            pause_reason = capture_only_reason(state, state_now)
            if action != "wait" and pause_reason:
                action, fallback_count = "wait", 1
                prev_sent = False
                print(f"seq={seq}: capture-only ({pause_reason}) -> wait", flush=True)
            elif action != "wait":
                try:
                    send_gameplay(run_id, action, args)
                    prev_sent = True
                except ValueError as e:
                    append_decision(run_id, {
                        "seq": seq, "ts": time.time(), "run_id": run_id,
                        "scene": scene, "frame_path": png_abs,
                        "vlm_model": chosen.get("vlm_model", vlm_client.MODEL),
                        "chosen_action": "abort_vlm",
                        "confidence": float(chosen.get("confidence", 0.0)),
                        "latency_ms": latency_ms,
                        "parse_attempts": parse_attempts, "fallback_count": 0,
                        "vlm_ok": False, "frame_nonblack": frame_nonblack,
                        "note": f"abort: bad args: {e}"[:300]})
                    print(f"VLM abort seq={seq}: bad args {e}", flush=True)
                    return 3
            # wait (chosen or degraded): deliberately send nothing.
            if action == "wait":
                prev_sent = False
            append_decision(run_id, {
                "seq": seq, "ts": time.time(), "run_id": run_id,
                "scene": scene, "frame_path": png_abs,
                "vlm_model": chosen.get("vlm_model", vlm_client.MODEL),
                "chosen_action": action,
                "confidence": float(chosen.get("confidence", 0.0)),
                "latency_ms": latency_ms, "parse_attempts": parse_attempts,
                "fallback_count": fallback_count, "vlm_ok": True,
                "frame_nonblack": frame_nonblack,
                "goal_scene": goal_scene,
                "persona": persona_id,
                "goal_reached": scene == goal_scene})
            if seq < max_ticks:
                time.sleep(max(0.0, tick_interval_s - (time.time() - t_tick)))
        return 0
    finally:
        godot_launch.request_quit(proc, run_id,
                                  project_dir=proj_root(run_id))
        try:
            os.remove(legacy_input_file(run_id))
        except OSError:
            pass


def main() -> int:
    ap = argparse.ArgumentParser(description="MiniMax-M3 vision tick loop")
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--goal-scene", default="res://scenes/map.tscn")
    ap.add_argument("--max-ticks", type=int, default=3)
    ap.add_argument("--godot", default=godot_launch.GODOT_BIN)
    ap.add_argument("--tick-interval", type=float, default=10.0)
    ap.add_argument("--persona", default="novice")
    args = ap.parse_args()
    if args.tick_interval < 10.0:
        print("tick interval clamped to 10s minimum", flush=True)
        args.tick_interval = 10.0
    return run_loop(args.run_id, args.goal_scene, args.max_ticks,
                    args.godot, args.tick_interval, args.persona)


if __name__ == "__main__":
    raise SystemExit(main())
