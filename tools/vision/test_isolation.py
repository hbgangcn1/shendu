"""Isolation tests: no Godot, no model calls.

Asserts that for N=4 simulated runs all constructed frame/state/artifact
paths are unique and no path of one run is a prefix-collision of another.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import isolate

N = 4


def main() -> int:
    run_ids = ["sim-batch-R%02d" % (i + 1) for i in range(N)]
    assert len(set(run_ids)) == N, "run ids must be distinct"
    all_paths: list = []
    per_run: dict = {}
    for rid in run_ids:
        p = isolate.paths_for(rid)
        vals = [p["frame_path"], p["state_file"], p["input_file"],
                p["captures_dir"], p["artifacts_dir"],
                p["decisions_path"], p["scorecard_path"],
                p["clone_dir"], p["user_data_dir"]]
        per_run[rid] = vals
        all_paths.extend(vals)
    assert len(set(all_paths)) == len(all_paths), "paths must be unique across runs"
    for i, a in enumerate(run_ids):
        for b in run_ids:
            if a == b:
                continue
            for pa in per_run[a]:
                for pb in per_run[b]:
                    assert pa != pb, f"collision {pa}"
                    assert not pb.startswith(pa), f"prefix-collision {pa} < {pb}"
    print(f"isolation OK: {N} runs, {len(all_paths)} unique paths, no prefix collisions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
