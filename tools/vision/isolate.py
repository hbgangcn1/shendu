"""Per-run project clones for parallel vision batches.

Each run gets its own clone directory so frames, state files, and
artifacts never collide. Assets are symlinked (fallback: copy) to
keep clones cheap.
"""
import os
import shutil

PROJECT_DIR = r"C:\Users\hbgan\Projects\shendu"
CLONES_ROOT = os.path.join(PROJECT_DIR, "qa-clones")
REPORTS_ROOT = os.path.join(PROJECT_DIR, "qa-reports")

SKIP_NAMES = {".godot", "qa-captures", "qa-artifacts"}
SKIP_TOP_FILES = {".agent_state.json", ".agent_input.json"}


def _check_run_id(run_id: str) -> str:
    if not run_id or not all(c.isalnum() or c in ("-", "_") for c in run_id):
        raise ValueError(f"bad run_id {run_id!r}")
    return run_id


def clone_dir(run_id: str) -> str:
    return os.path.join(CLONES_ROOT, _check_run_id(run_id))


def paths_for(run_id: str) -> dict:
    """Paths namespaced to one run. Used by batch.py and tests."""
    _check_run_id(run_id)
    cdir = clone_dir(run_id)
    captures = os.path.join(cdir, "qa-captures", run_id)
    artifacts = os.path.join(cdir, "qa-artifacts", run_id)
    return {
        "run_id": run_id,
        "clone_dir": cdir,
        "user_data_dir": os.path.join(cdir, "user-data-%s" % run_id),
        "frame_path": os.path.join(captures, "frame_1.png"),
        "state_file": os.path.join(cdir, ".agent_state.%s.json" % run_id),
        "input_file": os.path.join(cdir, ".agent_input.%s.json" % run_id),
        "captures_dir": captures,
        "artifacts_dir": artifacts,
        "decisions_path": os.path.join(artifacts, "decisions.jsonl"),
        "scorecard_path": os.path.join(artifacts, "scorecard.json"),
    }


def _ignore(src: str, names: list) -> set:
    out = set()
    if os.path.abspath(src) == os.path.abspath(PROJECT_DIR):
        for n in names:
            if n in SKIP_NAMES or n in SKIP_TOP_FILES:
                out.add(n)
            elif n.startswith(".agent_state.") or n.startswith(".agent_input."):
                out.add(n)
            elif n in ("qa-clones", "qa-reports"):
                out.add(n)
    return out


GODOT_BIN = os.environ.get("GODOT_BIN", r"C:\Tools\Godot\Godot_v4.7-stable_win64.exe")


def build_clone(run_id: str) -> dict:
    """Copy project into a per-run clone; symlink (or copy) assets."""
    paths = paths_for(run_id)
    cdir = paths["clone_dir"]
    if os.path.exists(cdir):
        shutil.rmtree(cdir)
    os.makedirs(CLONES_ROOT, exist_ok=True)
    shutil.copytree(PROJECT_DIR, cdir, ignore=_ignore,
                    ignore_dangling_symlinks=True)
    src_assets = os.path.join(PROJECT_DIR, "assets")
    dst_assets = os.path.join(cdir, "assets")
    if os.path.isdir(src_assets) and not os.path.exists(dst_assets):
        try:
            os.symlink(src_assets, dst_assets, target_is_directory=True)
        except OSError:
            shutil.copytree(src_assets, dst_assets)
    os.makedirs(paths["captures_dir"], exist_ok=True)
    os.makedirs(paths["artifacts_dir"], exist_ok=True)
    os.makedirs(paths["user_data_dir"], exist_ok=True)
    # 2026-10-08: clones skip .godot, so global class cache + imports are
    # missing and the game boot fails (MapNode unresolvable, rc=1).
    # Regenerate with one headless --import before any gameplay launch.
    import subprocess
    imp = subprocess.run([GODOT_BIN, "--headless", "--path", cdir, "--import"],
                         capture_output=True, text=True, timeout=300)
    if imp.returncode != 0:
        raise RuntimeError(f"clone import failed rc={imp.returncode}: {imp.stderr[-500:]}")
    return paths
