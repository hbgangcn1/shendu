#!/usr/bin/env python3
"""test_independent_review.py — gate_10 (STRICT)

PASS criteria:
  >= 2 agents configured in openclaw.json (maker + reviewer)
  recent done cards have explicit reviewer sessionKey (or subagent role field)

Currently BLOCKED: only 1 agent (main) in OpenClaw config.
Need >= 2 agents + sessions_spawn to support role field.
"""
import json
import sys
from pathlib import Path

CONFIG_PATH = Path(r"C:\Users\hbgan\.openclaw\openclaw.json")
JSON_PATH = Path(r"C:\Users\hbgan\.openclaw\workspace\scripts\workboard-done.json")
MIN_AGENTS = 2


def check_agents():
    if not CONFIG_PATH.exists():
        print(f"FAIL: config not found at {CONFIG_PATH}")
        return False, 0
    try:
        data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"FAIL: invalid config JSON: {e}")
        return False, 0

    agents = data.get("agents") or {}
    if isinstance(agents, dict):
        count = 1  # main always exists
        if "entries" in agents:
            count = len(agents["entries"])
        return count >= MIN_AGENTS, count
    return False, 0


def check_recent_sessions():
    if not JSON_PATH.exists():
        return 0, 0
    try:
        data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return 0, 0
    cards = data.get("cards", [])
    if not cards:
        return 0, 0
    with_reviewer = 0
    total_recent = min(20, len(cards))
    for c in cards[:total_recent]:
        md = c.get("metadata") or {}
        if "reviewer_session" in md or "review_session_id" in md or "reviewer_agent" in md:
            with_reviewer += 1
    return with_reviewer, total_recent


def main():
    agents_ok, agent_count = check_agents()
    print(f"Configured agents: {agent_count} (need >= {MIN_AGENTS})")
    if not agents_ok:
        print(f"FAIL: need >= {MIN_AGENTS} agents configured")
        print("Add reviewer agent to openclaw.json agents section:")
        print('  "entries": {"main": {...}, "reviewer": {...}}')
        print("Then implement sessions_spawn role field to dispatch subagents to specific agentId.")
        return 1

    reviewer_count, recent_count = check_recent_sessions()
    if recent_count == 0:
        print("SKIP: no recent done cards to verify")
        return 0
    print(f"Recent cards with reviewer session: {reviewer_count}/{recent_count}")
    if reviewer_count == 0:
        print(f"FAIL: no cards have explicit reviewer sessionKey")
        print("Need subagent workflow that spawns reviewer agent for verification phase.")
        return 1

    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())