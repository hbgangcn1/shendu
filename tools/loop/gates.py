"""Safety guardrails for the unattended loop.

Imported by tools/loop/loop.py stage 6/6::

    import gates
    ok, reasons = gates.check(report, scorecards, contracts, suggestions)

``check()`` returns ``(verdict, reasons)``. The verdict is True (GO,
commit allowed) only if ALL three gates pass:

1. compile gate: every ``.py`` file under ``tools/loop`` and
   ``tools/vision`` passes ``py_compile`` (syntax check only, nothing
   is imported or executed).
2. clean-tree gate: no changes outside the loop's own work areas
   (``tools/loop/``, ``tools/vision/``, ``docs/fix-history/``), ignored
   runtime dirs, or caller-named ``expected_paths``.
3. dispatch gate: the hard-gate FAIL set is a subset of the baseline
   FAIL set (committed HEAD ledger): no NEW failures. Standing FAILs
   never block by themselves.

The extra positional arguments passed by loop.py (report, scorecards,
contracts, suggestions) are accepted and ignored: the gates judge the
tree and the ledger, never the batch payload. Keyword overrides
(``repo_root``, ``status_path``) exist only for proof/fixture runs and
default to the real project paths.
"""
import json
import os
import py_compile
import subprocess

LOOP_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(os.path.dirname(LOOP_DIR))
DEFAULT_STATUS_PATH = os.path.join(
    PROJECT_DIR, "project", "hard_gates_status.json")

# Runtime output dirs whose drift never blocks a commit.
IGNORED_PREFIXES = (
    "qa-reports/",
    "clones/",
    ".godot/",
    "logs/",
    "tmp/",
    "__pycache__/",
    "qa-artifacts/",
    "qa-captures/",
    "qa-clones/",
    "qa-logs/",
)

# The loop's own work areas: new files here are the deliverable,
# not dirt. Everything else must be expected or clean.
ALLOWED_PREFIXES = (
    "tools/loop/",
    "tools/vision/",
    "docs/fix-history/",
)

COMPILE_DIRS = ("tools/loop", "tools/vision")


def _compile_gate(repo_root):
    """Return a list of reasons (empty means pass)."""
    reasons = []
    checked = 0
    for rel in COMPILE_DIRS:
        d = os.path.join(repo_root, *rel.split("/"))
        if not os.path.isdir(d):
            reasons.append("compile: missing directory %s" % rel)
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".py"):
                continue
            path = os.path.join(d, name)
            checked += 1
            try:
                py_compile.compile(path, doraise=True)
            except py_compile.PyCompileError as exc:
                reasons.append("compile: %s: %s" % (rel + "/" + name, exc))
    if checked == 0 and not reasons:
        reasons.append("compile: no .py files found under tools/loop")
    return reasons


def _porcelain_path(line):
    """Extract the tree path from a ``git status --porcelain`` line."""
    path = line[3:].strip().strip('"')
    if " -> " in path:  # rename/copy: judge the new path
        path = path.split(" -> ", 1)[1].strip().strip('"')
    return path


def _tree_gate(repo_root, expected_paths=()):
    """Return a list of reasons (empty means pass)."""
    import copy
    env = copy.copy(os.environ)
    env.update(GIT_TERMINAL_PROMPT="0",
               GIT_OPTIONAL_LOCKS="0",
               GIT_PAGER="cat",
               PAGER="cat")
    try:
        proc = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repo_root,
            stdin=subprocess.DEVNULL,  # never inherit a console handle
            capture_output=True,
            text=True,
            timeout=60,
            env=env,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return ["tree: git status failed: %s" % exc]
    if proc.returncode != 0:
        return ["tree: git status exited %d: %s" % (
            proc.returncode, proc.stderr.strip())]
    dirty = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        path = _porcelain_path(line)
        if "__pycache__" in path.split("/"):
            continue  # bytecode emitted by gate 1 itself, never a signal
        if path.startswith(tuple(IGNORED_PREFIXES)):
            continue
        if path.startswith(tuple(ALLOWED_PREFIXES)):
            continue  # the loop's own deliverable areas
        if path in set(expected_paths):
            continue  # contract-named intentional files
        dirty.append(line.strip())
    if dirty:
        reasons = ["tree: dirty (%d entr%s outside ignored dirs: %s)" % (
            len(dirty),
            "y" if len(dirty) == 1 else "ies",
            ", ".join(dirty[:5]),
        )]
        reasons.extend("tree: " + entry for entry in dirty[5:])
        return reasons
    return []


def _fail_ids(data):
    """Gate ids whose status is not PASS."""
    out = set()
    try:
        for r in data.get("results", []):
            if r.get("status") != "PASS":
                out.add(r.get("gate_id", "?"))
    except (AttributeError, TypeError):
        pass
    return out


def _baseline_fails(repo_root):
    """FAIL set from the committed ledger; None when unreadable."""
    try:
        proc = subprocess.run(
            ["git", "show", "HEAD:project/hard_gates_status.json"],
            cwd=repo_root, capture_output=True, text=True, timeout=60)
        if proc.returncode != 0:
            return None
        return _fail_ids(json.loads(proc.stdout))
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def _dispatch_gate(status_path, repo_root, baseline_fails=None):
    """Return a list of reasons (empty means pass)."""
    try:
        with open(status_path, encoding="utf-8") as f:
            data = json.load(f)
    except OSError as exc:
        return ["dispatch: cannot read %s: %s" % (status_path, exc)]
    except ValueError as exc:
        return ["dispatch: invalid JSON in %s: %s" % (status_path, exc)]
    summary = data.get("summary")
    if not isinstance(summary, dict):
        return ["dispatch: %s has no summary object" % status_path]
    current = _fail_ids(data)
    if baseline_fails is not None:
        base = set(baseline_fails)
    else:
        base = _baseline_fails(repo_root)
    if base is None:
        if summary.get("dispatch_blocked"):
            blockers = summary.get("critical_blockers") or []
            detail = ", ".join(blockers) if blockers else "no detail"
            return ["dispatch: no baseline and dispatch_blocked=true (%s)" % detail]
        return []
    new_fails = sorted(current - base)
    if new_fails:
        return ["dispatch: NEW hard-gate failures vs baseline: %s" % ", ".join(new_fails)]
    return []


def check(*args, repo_root=None, status_path=None, **kwargs):
    """Run all gates. Return ``(verdict, reasons)``.

    ``verdict`` is True (GO) only if every gate passes; otherwise False
    (NOGO) with one human-readable reason per failure.
    """
    root = repo_root or PROJECT_DIR
    status = status_path or DEFAULT_STATUS_PATH
    reasons = []
    reasons.extend(_compile_gate(root))
    reasons.extend(_tree_gate(root, kwargs.get("expected_paths", ())))
    reasons.extend(_dispatch_gate(status, root, kwargs.get("baseline_fails")))
    return (len(reasons) == 0, reasons)
