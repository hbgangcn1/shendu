"""Nightly unattended-loop entry point.

Real run (``python tools/loop/loop.py --once``):
  1. build a batch plan N=2 (novice,optimizer, map, max-ticks 3)
     via batch.build_plan
  2. run it via batch.run_batch
  3. read report.json plus both scorecards plus both decisions.jsonl
  4. call issues.build_contracts(...) by import (skip if absent)
  5. call critic.suggest(...) by import (skip if absent)
  6. call gates.check() by import, print GO or NOGO with reasons

``--dry-run`` prints every step it WOULD take with concrete paths
and commands and touches nothing (no Godot, no model calls, no files).
"""
import argparse
import datetime
import os
import sys

LOOP_DIR = os.path.dirname(os.path.abspath(__file__))
VISION_DIR = os.path.join(os.path.dirname(LOOP_DIR), "vision")
for _d in (LOOP_DIR, VISION_DIR):
    if _d not in sys.path:
        sys.path.insert(0, _d)

PROJECT_DIR = r"C:\Users\hbgan\Projects\shendu"
REPORTS_ROOT = os.path.join(PROJECT_DIR, "qa-reports")

PERSONAS = ["novice", "optimizer"]
GOAL_SCENE = "res://scenes/map.tscn"
MAX_TICKS = 3
N_RUNS = 2
GODOT_BIN = r"C:\Tools\Godot\Godot_v4.7-stable_win64.exe"
RUN_TIMEOUT_S = 1800.0


def _example_batch_id() -> str:
    return "loop-20261007-020000"


def _dry_run() -> int:
    batch_id = _example_batch_id()
    print("loop --dry-run: no side effects "
          "(no Godot, no model calls, no files written)")
    print("batch_id (example): %s" % batch_id)
    print()
    print("stage 1/6: build plan via batch.build_plan "
          "(N=%d, personas=%s, goal=%s, max-ticks=%d)" % (
              N_RUNS, ",".join(PERSONAS), GOAL_SCENE, MAX_TICKS))
    print("  would call: batch.build_plan(%r, %r, %r, %d, %d, %r)" % (
        batch_id, PERSONAS, GOAL_SCENE, MAX_TICKS, N_RUNS, GODOT_BIN))
    import isolate
    run_ids = ["%s-R%02d" % (batch_id, i + 1) for i in range(N_RUNS)]
    for i, run_id in enumerate(run_ids):
        paths = isolate.paths_for(run_id)
        persona = PERSONAS[i % len(PERSONAS)]
        cmd = [sys.executable,
               os.path.join(PROJECT_DIR, "tools", "vision",
                            "orchestrator.py"),
               "--run-id", run_id,
               "--goal-scene", GOAL_SCENE,
               "--max-ticks", str(MAX_TICKS),
               "--godot", GODOT_BIN,
               "--persona", persona]
        print("  run %d/%d: run_id=%s persona=%s" % (i + 1, N_RUNS, run_id,
                                                    persona))
        print("    clone_dir: %s" % paths["clone_dir"])
        print("    scorecard: %s" % paths["scorecard_path"])
        print("    decisions: %s" % paths["decisions_path"])
        print("    cmd: %s" % " ".join(cmd))
    print()
    print("stage 2/6: run batch via batch.run_batch")
    print("  would call: batch.run_batch(%r, plan, timeout_s=%.1f)" % (
        batch_id, RUN_TIMEOUT_S))
    print("  would spawn: python tools/vision/orchestrator.py "
          "per run (see stage 1 cmds), stagger 60s, timeout-kill and reap")
    print()
    report_path = os.path.join(REPORTS_ROOT, batch_id, "report.json")
    print("stage 3/6: read report + scorecards + decisions")
    print("  report: %s" % report_path)
    for run_id in run_ids:
        paths = isolate.paths_for(run_id)
        print("  scorecard[%s]: %s" % (run_id, paths["scorecard_path"]))
        print("  decisions[%s]: %s" % (run_id, paths["decisions_path"]))
    print("  would: json.load report.json, both scorecard.json, "
          "count lines in both decisions.jsonl")
    print()
    print("stage 4/6: issues.build_contracts(...) by import "
          "(tools/loop/issues.py, not written here)")
    print("  would: try: import issues "
          "-> issues.build_contracts(report, scorecards, decisions)")
    print("  would: except ImportError: print "
          "note 'issues module absent, skipping contract stage' and continue")
    print()
    print("stage 5/6: critic.suggest(...) by import "
          "(tools/loop/critic.py, not written here)")
    print("  would: try: import critic -> critic.suggest(contracts)")
    print("  would: except ImportError: print "
          "note 'critic module absent, skipping critic stage' and continue")
    print()
    print("stage 6/6: gates.check() by import "
          "(tools/loop/gates.py, not written here)")
    print("  would: try: import gates -> ok, reasons = gates.check(...)")
    print("  would: except ImportError: print "
          "note 'gates module absent, skipping gate stage' and continue")
    print("  would print: GO (commit allowed) "
          "or NOGO with reasons")
    print()
    print("dry-run done: touched nothing")
    return 0


def _once() -> int:
    import batch
    import isolate
    import json

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    batch_id = "loop-%s" % stamp
    print("loop --once: batch_id=%s" % batch_id)
    print("stage 1/6: build plan")
    plan = batch.build_plan(batch_id, PERSONAS, GOAL_SCENE,
                            MAX_TICKS, N_RUNS, GODOT_BIN)
    for item in plan:
        print("  run %s persona=%s clone=%s" % (
            item["run_id"], item["persona"], item["clone_dir"]))
    print("stage 2/6: run batch")
    results = batch.run_batch(batch_id, plan, RUN_TIMEOUT_S)
    report_path = batch.write_report(batch_id, results)
    print("  report: %s" % report_path)
    print("stage 3/6: read report + scorecards + decisions")
    with open(report_path, encoding="utf-8") as f:
        report = json.load(f)
    scorecards = []
    decisions_counts = {}
    for r in results:
        with open(r["scorecard_path"], encoding="utf-8") as f:
            scorecards.append(json.load(f))
        dec = isolate.paths_for(r["run_id"])["decisions_path"]
        with open(dec, encoding="utf-8") as f:
            decisions_counts[r["run_id"]] = sum(1 for _ in f)
    print("  report runs: %s" % report.get("run_ids"))
    print("  decisions line counts: %s" % decisions_counts)
    print("stage 4/6: issues.build_contracts")
    contracts = None
    try:
        import issues  # type: ignore
        contracts = issues.build_contracts(report, scorecards,
                                           decisions_counts)
        print("  contracts: %s" % contracts)
    except ImportError:
        print("  note: issues module absent, skipping contract stage")
    print("stage 5/6: critic.suggest")
    suggestions = None
    try:
        import critic  # type: ignore
        suggestions = critic.suggest(contracts)
        print("  suggestions: %s" % suggestions)
    except ImportError:
        print("  note: critic module absent, skipping critic stage")
    print("stage 6/6: gates.check")
    try:
        import gates  # type: ignore
        ok, reasons = gates.check(report, scorecards, contracts,
                                  suggestions)
    except ImportError:
        print("  note: gates module absent, skipping gate stage")
        ok, reasons = False, ["gates module absent"]
    if ok:
        print("GO (commit allowed)")
    else:
        print("NOGO:")
        for reason in reasons:
            print("  - %s" % reason)
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Nightly unattended-loop entry")
    ap.add_argument("--once", action="store_true",
                    help="run one full loop iteration")
    ap.add_argument("--dry-run", action="store_true",
                    help="print what --once would do; touch nothing")
    args = ap.parse_args(argv)
    if args.dry_run:
        return _dry_run()
    if args.once:
        return _once()
    ap.print_usage()
    print("hint: use --once for a real run, --dry-run to preview")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
