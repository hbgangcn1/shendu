"""Issue-contract writer: failing QA evidence -> fix tasks.

Reads scorecard JSON files; for every criterion with critical=true and
pass=false writes one contract JSON file <out_dir>/<criterion>_<scene>.json
(severity critical, failing frame path, run id, one-line suggestion naming
the scene file to inspect). Non-critical fails are aggregated into ONE
notes file. A fully-passing scorecard yields zero files.
"""
from __future__ import annotations

import json
import os

NOTES_FILENAME = "notes_minor.json"

_SCENE_FILE = {
    "battle": "scenes/battle_demo.tscn",
    "map": "scenes/map.tscn",
    "all": "scenes/map.tscn",
}


def _load_json(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _rubric_scene(criterion: str) -> str:
    """Look up the criterion's scene from visual_rubric.json; fallback 'all'."""
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        rp = os.path.join(here, "..", "vision", "visual_rubric.json")
        with open(rp, encoding="utf-8") as f:
            rubric = json.load(f)
        for c in rubric.get("criteria", []):
            if c.get("id") == criterion:
                return str(c.get("scene", "all"))
    except (OSError, ValueError):
        pass
    return "all"


def _scene_file(scene: str) -> str:
    return _SCENE_FILE.get(scene, "scenes/%s.tscn" % scene)


def _iter_results(card: dict):
    """Yield (criterion, passed, critical, frame) across card shapes."""
    run_id = card.get("run_id", "unknown")
    # Real shape: {"frames": [{"frame":..., "results":[...]}]}
    frames = card.get("frames")
    if isinstance(frames, list):
        for fr in frames:
            frame = fr.get("frame", "") if isinstance(fr, dict) else ""
            for r in (fr.get("results", []) if isinstance(fr, dict) else []):
                crit = r.get("id") or r.get("criterion") or r.get("name", "unknown")
                passed = r.get("pass", r.get("passed", True))
                yield crit, bool(passed), bool(r.get("critical", False)), frame, run_id
        return
    # Fallback shape: {"criteria":[...]} / {"checks":[...]}
    for key in ("criteria", "checks", "results"):
        items = card.get(key)
        if isinstance(items, list):
            for r in items:
                crit = r.get("id") or r.get("criterion") or r.get("name", "unknown")
                passed = r.get("pass", r.get("passed", r.get("result") != "FAIL"))
                critical = r.get("critical", r.get("severity") == "critical")
                frame = r.get("frame", card.get("frame", ""))
                yield crit, bool(passed), bool(critical), frame, run_id
            return


def _norm_inputs(scorecards, decisions_paths):
    """Accept paths or loaded dicts for both args."""
    cards = []
    for s in scorecards if isinstance(scorecards, (list, tuple)) else [scorecards]:
        if isinstance(s, dict):
            cards.append((s, "<inline>"))
        else:
            cards.append((_load_json(s), s))
    if decisions_paths is None:
        decs = [""] * len(cards)
    elif isinstance(decisions_paths, (list, tuple)):
        decs = list(decisions_paths) + [""] * (len(cards) - len(decisions_paths))
    elif isinstance(decisions_paths, dict):
        decs = [decisions_paths.get(c.get("run_id", ""), "") for c in
                [c for c, _ in cards]]
    else:
        decs = [decisions_paths] * len(cards)
    return cards, decs


def build_contracts(scorecards, decisions_paths=None, out_dir="."):
    """Write contracts for failing criteria. Returns list of file paths."""
    # Tolerate loop.py's (report, scorecards, decisions_counts) shape:
    # a report dict carries batch_id/run_ids; a scorecard never does.
    if isinstance(scorecards, dict) and ("batch_id" in scorecards
                                         or "run_ids" in scorecards):
        report = scorecards
        scorecards, decisions_paths = decisions_paths, out_dir
        out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "..", "..", "qa-reports",
                               str(report.get("batch_id", "loop-manual")),
                               "contracts")
    cards, decs = _norm_inputs(scorecards, decisions_paths)
    os.makedirs(out_dir, exist_ok=True)
    written: list = []
    minors: list = []
    for (card, card_path), dec in zip(cards, decs):
        run_id = card.get("run_id", "unknown")
        for criterion, passed, critical, frame, _rid in _iter_results(card):
            if passed:
                continue
            scene = _rubric_scene(criterion)
            if critical:
                cid = "%s_%s_%s" % (criterion, scene, run_id)
                contract = {
                    "id": cid,
                    "title": "Fix critical QA fail '%s' in run %s" % (criterion, run_id),
                    "severity": "critical",
                    "scene": scene,
                    "evidence": {
                        "scorecard": card_path,
                        "frame": frame,
                        "decisions": dec,
                    },
                    "suggestion": "Inspect %s for criterion '%s' failure (run %s)." % (
                        _scene_file(scene), criterion, run_id),
                    "status": "open",
                    "run_id": run_id,
                    "criterion": criterion,
                }
                fname = "%s_%s.json" % (criterion, scene)
                fpath = os.path.join(out_dir, fname)
                with open(fpath, "w", encoding="utf-8") as f:
                    json.dump(contract, f, indent=2)
                written.append(fpath)
            else:
                minors.append({
                    "id": "%s_%s_%s" % (criterion, scene, run_id),
                    "title": "Minor QA fail '%s' in run %s" % (criterion, run_id),
                    "severity": "minor",
                    "scene": scene,
                    "evidence": {
                        "scorecard": card_path,
                        "frame": frame,
                        "decisions": dec,
                    },
                    "suggestion": "Inspect %s for criterion '%s' failure (run %s)." % (
                        _scene_file(scene), criterion, run_id),
                    "status": "open",
                    "run_id": run_id,
                    "criterion": criterion,
                })
    if minors:
        npath = os.path.join(out_dir, NOTES_FILENAME)
        with open(npath, "w", encoding="utf-8") as f:
            json.dump(minors, f, indent=2)
        written.append(npath)
    return written


def count_contracts(out_dir="."):
    """Count contract JSON files in out_dir."""
    if not os.path.isdir(out_dir):
        return 0
    return sum(1 for f in os.listdir(out_dir) if f.endswith(".json"))
