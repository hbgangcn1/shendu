"""Design-feedback critic: playtest data -> gameplay/design suggestions.

Deterministic only: no model calls, no network, no randomness.
Reads decision records (orchestrator decisions.jsonl shape) plus a
rubric scorecard and returns structured suggestions.

Decision record fields consumed (all optional, tolerant of missing keys):
  seq | tick          - tick sequence number
  scene               - scene name/id for the tick
  chosen_action | action - action taken this tick
  fallback_count      - parse-fallback count for the tick
  hp | player_hp | hp_after | player_hp_after - HP sample for the tick
  hp_before / player_hp_before - explicit before-value for the tick
  battle | battle_id   - battle grouping key (falls back to scene runs)
  progress            - explicit progress flag (False = non-progress tick)

Scorecard shapes consumed:
  {"frames": [{"frame": ..., "results": [{"id","pass","critical"}]}]}
  {"criteria" | "checks" | "results": [{"id","pass","critical"}]}
"""
from __future__ import annotations

AREAS = ("pacing", "balance", "clarity", "difficulty", "variety")

WAIT_ACTIONS = {"wait", "noop", "pass", "hold"}
NON_PROGRESS_ACTIONS = {"wait", "noop", "pass", "hold", "inspect", "look", "observe"}

WAIT_RATIO_THRESHOLD = 0.5
HP_DROP_FRACTION = 0.5
STUCK_RUN_LENGTH = 3


def _seq(rec: dict, idx: int) -> int:
    for key in ("seq", "tick", "tick_seq", "n"):
        val = rec.get(key)
        if isinstance(val, bool):
            continue
        if isinstance(val, (int, float)):
            return int(val)
    return idx + 1


def _action(rec: dict) -> str:
    for key in ("chosen_action", "action", "cmd", "decision"):
        val = rec.get(key)
        if isinstance(val, dict):
            for sub in ("action", "name", "cmd"):
                if isinstance(val.get(sub), str):
                    return str(val[sub]).strip().lower()
        if isinstance(val, str) and val.strip():
            return val.strip().lower()
    return ""


def _scene(rec: dict) -> str:
    for key in ("scene", "scene_id", "goal_scene"):
        val = rec.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return "unknown"


def _fallback(rec: dict) -> int:
    for key in ("fallback_count", "fallbacks", "parse_attempts_extra"):
        val = rec.get(key)
        if isinstance(val, bool):
            continue
        if isinstance(val, (int, float)) and int(val) > 0:
            return int(val)
    if rec.get("fallback") is True:
        return 1
    return 0


def _hp(rec: dict) -> float | None:
    for key in ("hp_after", "player_hp_after", "hp", "player_hp", "hp_now"):
        val = rec.get(key)
        if isinstance(val, bool):
            continue
        if isinstance(val, (int, float)):
            return float(val)
    return None


def _hp_before(rec: dict) -> float | None:
    for key in ("hp_before", "player_hp_before"):
        val = rec.get(key)
        if isinstance(val, bool):
            continue
        if isinstance(val, (int, float)):
            return float(val)
    return None


def _is_non_progress(rec: dict) -> bool:
    if rec.get("progress") is False:
        return True
    return _action(rec) in NON_PROGRESS_ACTIONS


def _iter_scorecard_results(scorecard: dict):
    """Yield (criterion_id, passed, critical, frame) across card shapes."""
    frames = scorecard.get("frames")
    if isinstance(frames, list):
        for fr in frames:
            if not isinstance(fr, dict):
                continue
            frame = str(fr.get("frame", fr.get("frame_path", "")))
            for r in fr.get("results", []) or []:
                if not isinstance(r, dict):
                    continue
                crit = r.get("id") or r.get("criterion") or r.get("name", "unknown")
                passed = r.get("pass", r.get("passed", True))
                yield str(crit), bool(passed), bool(r.get("critical", False)), frame
        return
    for key in ("criteria", "checks", "results"):
        items = scorecard.get(key)
        if isinstance(items, list):
            for r in items:
                if not isinstance(r, dict):
                    continue
                crit = r.get("id") or r.get("criterion") or r.get("name", "unknown")
                passed = r.get("pass", r.get("passed", r.get("result") != "FAIL"))
                frame = str(r.get("frame", scorecard.get("frame", "")))
                yield str(crit), bool(passed), bool(r.get("critical", False)), frame


def suggest(decisions: list, scorecard: dict, persona_id: str) -> list:
    """Turn playtest data into design suggestions.

    Args:
        decisions: list of per-tick decision dicts (JSON-decoded).
        scorecard: rubric scorecard dict.
        persona_id: persona whose session produced the data (informational).

    Returns:
        List of {area, observation, evidence, proposal}; area is one of
        pacing, balance, clarity, difficulty, variety. Deterministic.
    """
    decisions = list(decisions or [])
    scorecard = dict(scorecard or {})
    persona = str(persona_id or "unknown")
    out: list = []

    # Rule 1: wait_ratio over 0.5 -> pacing suggestion citing wait ticks.
    if decisions:
        wait_seqs = [_seq(r, i) for i, r in enumerate(decisions)
                     if _action(r) in WAIT_ACTIONS]
        ratio = len(wait_seqs) / len(decisions)
        if ratio > WAIT_RATIO_THRESHOLD:
            out.append({
                "area": "pacing",
                "observation": (
                    "Session for persona '%s' stalled: %d of %d ticks "
                    "(%.0f%%) were waits, over the %.0f%% pacing budget." % (
                        persona, len(wait_seqs), len(decisions),
                        ratio * 100, WAIT_RATIO_THRESHOLD * 100)),
                "evidence": "wait_ratio=%.2f; wait tick seqs=%s of %d total" % (
                    round(ratio, 2), wait_seqs, len(decisions)),
                "proposal": ("Tighten pacing: shorten the idle/capture window or "
                             "add a mid-wait prompt so waits resolve faster; "
                             "re-run and expect wait_ratio under 0.5."),
            })

    # Rule 2: any fallback_count above 0 -> clarity suggestion citing tick.
    for i, rec in enumerate(decisions):
        n = _fallback(rec)
        if n > 0:
            out.append({
                "area": "clarity",
                "observation": (
                    "Model output needed %d fallback parse(s) at tick seq %d "
                    "(persona '%s'); the action grammar or frame was unclear." % (
                        n, _seq(rec, i), persona)),
                "evidence": "tick seq %d fallback_count=%d action=%r scene=%r" % (
                    _seq(rec, i), n, _action(rec) or "?", _scene(rec)),
                "proposal": ("Clarify the decision surface: tighten the action "
                             "grammar example and check HUD legibility at tick "
                             "seq %d, then re-run with zero fallbacks." % _seq(rec, i)),
            })
            break  # one clarity suggestion per session is enough

    # Rule 3: hp drops over 50 percent in one battle -> balance suggestion.
    if decisions:
        # Group HP samples by battle key; fall back to scene runs of battle
        # scenes, else the whole session as one group.
        groups: dict = {}
        order: list = []
        for i, rec in enumerate(decisions):
            key = rec.get("battle", rec.get("battle_id"))
            if key is None:
                scene = _scene(rec).lower()
                key = "battle-group" if "battle" in scene else "session"
            key = str(key)
            if key not in groups:
                groups[key] = []
                order.append(key)
            hp = _hp(rec)
            if hp is not None:
                groups[key].append((_seq(rec, i), hp))
            before = _hp_before(rec)
            if before is not None:
                groups[key].append((_seq(rec, i), before))
        for key in order:
            samples = sorted(groups[key], key=lambda t: t[0])
            if len(samples) < 2:
                continue
            peak = max(v for _, v in samples)
            trough = min(v for _, v in samples)
            if peak > 0 and (peak - trough) / peak > HP_DROP_FRACTION:
                peak_seq = next(s for s, v in samples if v == peak)
                trough_seq = next(s for s, v in samples if v == trough)
                out.append({
                    "area": "balance",
                    "observation": (
                        "HP collapsed %.0f%% in one battle group %r "
                        "(%.0f -> %.0f): a single encounter removes over half "
                        "the health bar." % (
                            (peak - trough) / peak * 100, key, peak, trough)),
                    "evidence": "battle group %r hp seq %d=%.0f -> seq %d=%.0f (drop %.0f%%)" % (
                        key, peak_seq, peak, trough_seq, trough,
                        (peak - trough) / peak * 100),
                    "proposal": ("Soften enemy burst in that encounter (lower "
                                 "per-hit damage or add a telegraphed defend "
                                 "window) so one battle costs under 50% HP."),
                })
                break

    # Rule 4: three consecutive same-scene non-progress ticks -> variety.
    run: list = []
    for i, rec in enumerate(decisions):
        if _is_non_progress(rec):
            run.append((i, rec))
        else:
            run = []
        if len(run) >= STUCK_RUN_LENGTH:
            window = run[-STUCK_RUN_LENGTH:]
            scenes = {_scene(r) for _, r in window}
            if len(scenes) == 1:
                seqs = [_seq(r, i) for i, r in window]
                acts = [_action(r) or "?" for _, r in window]
                out.append({
                    "area": "variety",
                    "observation": (
                        "Ticks %s sat in scene %r repeating non-progress "
                        "actions (%s): the loop offers nothing new to do." % (
                            seqs, next(iter(scenes)), ", ".join(acts))),
                    "evidence": "consecutive same-scene non-progress tick seqs=%s scene=%r actions=%s" % (
                        seqs, next(iter(scenes)), acts),
                    "proposal": ("Add variety to that stretch: a roaming event, "
                                 "alternate objective, or contextual hint so "
                                 "three idle ticks cannot all look alike."),
                })
                break

    # Rule 5: a critical rubric FAIL -> suggestion pointing at the frame.
    for crit, passed, critical, frame in _iter_scorecard_results(scorecard):
        if critical and not passed:
            out.append({
                "area": "difficulty",
                "observation": (
                    "Critical rubric FAIL on %r for persona '%s': the frame "
                    "is unplayable, which blocks any difficulty curve." % (
                        crit, persona)),
                "evidence": "criterion=%r critical=True pass=False frame=%r" % (
                    crit, frame or "?"),
                "proposal": ("Fix rendering/legibility for %r first (see frame "
                             "%s), then re-score before tuning difficulty." % (
                                 crit, frame or "?")),
            })
            break  # one pointer per scorecard is enough

    return out
