"""Windowed Godot launcher for the vision tick loop.

Gameplay boots the game NORMALLY (no -s flag): the -s SceneTree script
replaces the game instead of booting it, so it must never be used for
gameplay. -s usage stays only in the probe path (probe_capture.py).

Usage:
    from godot_launch import launch_windowed, kill_all_godot, is_godot_running
"""
import os
import subprocess
import time

PROJECT_DIR = r"C:\Users\hbgan\Projects\shendu"
GODOT_BIN = r"C:\Tools\Godot\Godot_v4.7-stable_win64.exe"


def launch_windowed(run_id: str, godot_bin: str = GODOT_BIN,
                    boot_wait_s: float = 10.0, goal_scene: str = "",
                    extra_args: list[str] | None = None) -> subprocess.Popen:
    """Launch the game windowed as a normal boot (NO -s). Returns Popen.

    Godot stdout/stderr go to tools/vision/godot_boot.log for diagnosis."""
    args = [godot_bin, "--path", PROJECT_DIR]
    if extra_args:
        args += list(extra_args)
    args += ["--", "--qa-auto-run", f"--run-id={run_id}",
             "--vision-run"]
    if goal_scene:
        args += [f"--goal-scene={goal_scene}"]
    print(f"launch: {' '.join(args)}", flush=True)
    log_path = os.path.join(PROJECT_DIR, "tools", "vision",
                            "godot_boot.log")
    log_fh = open(log_path, "w", encoding="utf-8", errors="replace")
    proc = subprocess.Popen(args, cwd=PROJECT_DIR,
                            stdout=log_fh, stderr=subprocess.STDOUT)
    proc._qa_log_fh = log_fh  # kept open for the game lifetime
    time.sleep(boot_wait_s)
    if proc.poll() is not None:
        raise RuntimeError(f"Godot exited during boot rc={proc.returncode}")
    return proc


def request_quit(proc: subprocess.Popen | None = None,
               run_id: str = "") -> None:
    """Ask a polite quit via the socket file, then kill; never orphan.
    Quit goes to the run-namespaced input (what AgentSocket polls) plus
    the canonical mirror."""
    if run_id:
        try:
            with open(os.path.join(
                    PROJECT_DIR, f".agent_input.{run_id}.json"),
                    "w", encoding="utf-8") as f:
                f.write('{"action":"quit"}')
        except OSError:
            pass
    try:
        with open(os.path.join(PROJECT_DIR, ".agent_input.json"), "w", encoding="utf-8") as f:
            f.write('{"action":"quit"}')
        time.sleep(1.5)
    except OSError:
        pass
    if proc is not None and proc.poll() is None:
        try:
            proc.kill()
        except OSError:
            pass
    if proc is not None:
        try:
            fh = getattr(proc, "_qa_log_fh", None)
            if fh is not None:
                fh.close()
        except OSError:
            pass
    kill_all_godot()


def kill_all_godot(godot_bin: str = GODOT_BIN) -> bool:
    """taskkill every Godot process. Returns True iff none remain."""
    exe = os.path.basename(godot_bin)
    subprocess.run(["taskkill", "/F", "/IM", exe], capture_output=True)
    time.sleep(1)
    r = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {exe}"],
                       capture_output=True, text=True)
    clean = exe.lower() not in r.stdout.lower()
    print(f"cleanup: {'no Godot process remains' if clean else r.stdout}", flush=True)
    return clean


def is_godot_running(godot_bin: str = GODOT_BIN) -> bool:
    exe = os.path.basename(godot_bin)
    r = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {exe}"],
                       capture_output=True, text=True)
    return exe.lower() in r.stdout.lower()
