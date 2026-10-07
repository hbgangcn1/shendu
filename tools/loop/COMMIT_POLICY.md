# Commit Policy — Unattended Loop (Shendu)

`tools/loop/gates.py` `check()` returns `(verdict, reasons)`.
The verdict controls every commit below. No gate override exists in the
loop; bypassing a NOGO requires Robert's explicit approval.

## Rules

1. **Conventional commit message.** Every loop commit uses
   `<type>(<scope>): <subject>` with an optional body and footer, per
   AGENTS.md (`feat`, `fix`, `test`, `refactor`, `docs`, `style`).
   Example: `fix(vision): retry scorecard write on lock timeout`.
2. **One commit per loop iteration.** A single `--once` run produces at
   most one commit containing exactly that iteration's changes. Never
   bundle multiple iterations, and never commit mid-iteration.
3. **NEVER push to remote.** The loop may commit locally only. Pushing,
   publishing, or releasing is out of scope for the unattended loop —
   no `git push`, no tags, no releases.
4. **NOGO means no commit plus a notify report.** If `check()` returns
   `(False, reasons)`, the loop must not commit. It writes the reasons
   to that iteration's notify report (under `qa-reports/<batch-id>/`)
   so the next review sees exactly which gate failed and why.
5. **Robert owns the final release decision.** Only a human (Robert)
   decides what ships: which local commits are kept, rebased, or
   dropped, and when anything is pushed or released.

## Gate summary

GO (commit allowed) only if all three pass:

| # | Gate | Check |
|---|------|-------|
| 1 | compile | `py_compile` over `tools/loop` and `tools/vision` |
| 2 | clean tree | `git status --porcelain` clean apart from ignored runtime dirs (`qa-reports/`, `clones/`, `.godot/`, `logs/`, `tmp/`, `__pycache__/`) |
| 3 | dispatch | `project/hard_gates_status.json` summary has `dispatch_blocked: false` |
