"""Parallel batch orchestration for vision test runs.

Spawns one orchestrator.py per per-run project clone (see isolate.py)
with a distinct --run-id. Supervises with timeout-kill and reap, then
writes qa-reports/<batch_id>/report.json.
"""
import argparse
import json
import os
import subprocess
import sys
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import isolate
import rubric_scorer

PROJECT_DIR = isolate.PROJECT_DIR
ORCHESTRATOR = os.path.join(PROJECT_DIR, "tools", "vision", "orchestrator.py")
MAX_N = 4
# Stagger instance starts by 60s: observed 2026-10-07 endpoint throttling
# under bursts (VLM transport read/SSL timeouts for minutes); 15s was not
# enough spacing between concurrent VLM callers.
STAGGER_S = 60.0
RUN_TIMEOUT_S = 1800.0


def _check_n(n: int) -> int:
    if not 1 <= n <= MAX_N:
        raise ValueError(f"--n must be 1..{MAX_N}, got {n}")
    return n


def build_plan(batch_id: str, personas: list, goal_scene: str,
               max_ticks: int, n: int, godot: str) -> list:
    plan = []
    for i in range(n):
        run_id = "%s-R%02d" % (batch_id, i + 1)
        paths = isolate.paths_for(run_id)
        persona = personas[i % len(personas)]
        cmd = [sys.executable, ORCHESTRATOR,
               "--run-id", run_id,
               "--goal-scene", goal_scene,
               "--max-ticks", str(max_ticks),
               "--godot", godot,
               "--persona", persona]
        plan.append({"run_id": run_id, "persona": persona,
                     "clone_dir": paths["clone_dir"],
                     "scorecard_path": paths["scorecard_path"],
                     "cmd": cmd})
    return plan


def run_batch(batch_id: str, plan: list, timeout_s: float) -> list:
    procs: list = []
    for item in plan:
        isolate.build_clone(item["run_id"])
        if procs:
            # See STAGGER_S comment above: 60s, not 15s.
            time.sleep(STAGGER_S)
        p = subprocess.Popen(item["cmd"], cwd=item["clone_dir"])
        procs.append((item, p, time.time()))
    results = []
    for item, p, started in procs:
        remain = max(1.0, timeout_s - (time.time() - started))
        try:
            rc = p.wait(timeout=remain)
        except subprocess.TimeoutExpired:
            p.kill()
            rc = p.wait()
        results.append({"run_id": item["run_id"],
                        "scorecard_path": item["scorecard_path"],
                        "exit_code": rc})
        _write_scorecard(item)
    return results


def _write_scorecard(item: dict) -> str:
    """Deterministic offline scoring over the run's decision frames.
    No model calls: safe under endpoint throttling."""
    paths = isolate.paths_for(item["run_id"])
    frames = sorted(f for f in os.listdir(paths["captures_dir"])
                    if f.startswith("frame_") and f.endswith(".png"))
    scored = [rubric_scorer.score_frame(
        os.path.join(paths["captures_dir"], f), None) for f in frames]
    crit = [c for fr in scored for c in fr["results"] if c["critical"]]
    verdict = bool(crit) and all(c["pass"] for c in crit)
    card = {"run_id": item["run_id"], "frames": scored,
            "verdict": verdict}
    os.makedirs(os.path.dirname(item["scorecard_path"]), exist_ok=True)
    with open(item["scorecard_path"], "w", encoding="utf-8") as f:
        json.dump(card, f, indent=2)
    return item["scorecard_path"]


def write_report(batch_id: str, results: list) -> str:
    report = {"batch_id": batch_id,
              "run_ids": [r["run_id"] for r in results],
              "scorecards": [r["scorecard_path"] for r in results],
              "exit_codes": [r["exit_code"] for r in results]}
    assert len(set(report["run_ids"])) == len(results)
    assert len(report["scorecards"]) == len(results)
    assert len(report["exit_codes"]) == len(results)
    d = os.path.join(PROJECT_DIR, "qa-reports", batch_id)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "report.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description="Parallel vision batch runner")
    ap.add_argument("--personas", default="novice")
    ap.add_argument("--goal-scene", default="res://scenes/map.tscn")
    ap.add_argument("--max-ticks", type=int, default=3)
    ap.add_argument("--n", type=int, default=2)
    ap.add_argument("--godot", default=r"C:\Tools\Godot\Godot_v4.7-stable_win64.exe")
    ap.add_argument("--batch-id", default="")
    ap.add_argument("--timeout", type=float, default=RUN_TIMEOUT_S)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    _check_n(args.n)
    personas = [p.strip() for p in args.personas.split(",") if p.strip()]
    if not personas:
        raise ValueError("--personas must be a non-empty comma list")
    batch_id = args.batch_id or ("batch-%s" % uuid.uuid4().hex[:8])
    plan = build_plan(batch_id, personas, args.goal_scene,
                      args.max_ticks, args.n, args.godot)
    if args.dry_run:
        print("batch plan %s: N=%d stagger=%.0fs (60s: 2026-10-07 throttling)" % (
            batch_id, args.n, STAGGER_S))
        for i, item in enumerate(plan):
            print("--- run %d/%d ---" % (i + 1, len(plan)))
            print("run_id: %s" % item["run_id"])
            print("persona: %s" % item["persona"])
            print("clone_dir: %s" % item["clone_dir"])
            print("scorecard: %s" % item["scorecard_path"])
            print("cmd: %s" % " ".join(item["cmd"]))
            if i < len(plan) - 1:
                print("stagger: wait %.0fs before next start" % STAGGER_S)
        print("dry-run: nothing spawned, no clones built")
        return 0
    results = run_batch(batch_id, plan, args.timeout)
    path = write_report(batch_id, results)
    print("batch %s done: report %s" % (batch_id, path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
