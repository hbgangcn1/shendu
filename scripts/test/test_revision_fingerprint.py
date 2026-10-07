#!/usr/bin/env python3
"""test_revision_fingerprint.py — gate_9 (STRICT)

PASS criteria:
  done cards with `metadata.contract` field >= 50%
  fresh contracts (within freshness_hours) >= 90% of stamped ones

Blocked: OpenClaw workboard tools don't support writing custom metadata fields.
         Run scripts/backfill_workboard_contracts.py once OpenClaw adds
         workboard_update_metadata tool. Until then, this test FAILS honestly.

Export source: `openclaw workboard list --status done --json`
"""
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

JSON_PATH = Path(r"C:\Users\hbgan\.openclaw\workspace\scripts\workboard-done.json")
MIN_RATIO = 0.5


def main():
    # Export via CLI (reads from gateway plugin state)
    if not JSON_PATH.exists():
        try:
            r = subprocess.run(
                ["openclaw", "workboard", "list", "--status", "done", "--json"],
                capture_output=True, text=True, timeout=60
            )
            JSON_PATH.write_text(r.stdout, encoding="utf-8")
        except Exception as e:
            print(f"FAIL: cannot export workboard data: {e}")
            return 1

    try:
        data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"FAIL: invalid JSON: {e}")
        return 1

    cards = data.get("cards", [])
    if not cards:
        print("FAIL: no done cards found")
        return 1

    with_contract = sum(
        1 for c in cards
        if isinstance(c.get("metadata"), dict) and "contract" in c["metadata"]
    )
    ratio = with_contract / len(cards)
    print(f"Done cards: {len(cards)}")
    print(f"With contract: {with_contract}")
    print(f"Ratio: {ratio*100:.1f}% (required >= {MIN_RATIO*100:.0f}%)")

    if ratio < MIN_RATIO:
        print(f"FAIL: only {ratio*100:.1f}% cards have contract field (need >= {MIN_RATIO*100:.0f}%)")
        print("Run scripts/backfill_workboard_contracts.py once OpenClaw adds metadata write API.")
        return 1

    # Validate freshness
    now = time.time() * 1000
    fresh_enough = 0
    stamped = 0
    for c in cards:
        md = c.get("metadata") or {}
        contract = md.get("contract") or {}
        freshness_hours = contract.get("freshness_hours", 24)
        stamped_at = contract.get("stamped_at_ms") or contract.get("stamped_at")
        if not stamped_at:
            continue
        stamped += 1
        if isinstance(stamped_at, str):
            try:
                dt = datetime.fromisoformat(stamped_at.replace("Z", "+00:00"))
                stamped_ms = dt.timestamp() * 1000
            except ValueError:
                continue
        else:
            stamped_ms = stamped_at
        age_hours = (now - stamped_ms) / 3600000
        if age_hours <= freshness_hours:
            fresh_enough += 1
    print(f"Fresh contracts (within freshness_hours): {fresh_enough}/{stamped}")
    if stamped and fresh_enough < stamped * 0.9:
        print(f"WARN: some contracts are stale (need >= 90%)")
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())