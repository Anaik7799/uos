#!/usr/bin/env python3
"""
tools/post_codex_astra_coordination_intent.py — Post Tri-Agent Coordination Intent
Registers Codex Astra Mode's active claim on resolving the 15 real test failures in apps/cepaf_gleam.
Maintains hash-chain integrity in var/coordination/tri-agent/coordinator.sqlite3.
"""

import sqlite3
import hashlib
import json
import datetime

DB_COORD = "var/coordination/tri-agent/coordinator.sqlite3"
PLAN_ID = "uos/codex-astra-cepaf-gap-zero/20260919"
ACTOR = "L0-codex-gpt-6-astra"

def now_us():
    return int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1_000_000)

def get_boot_id():
    try:
        with open("/proc/sys/kernel/random/boot_id", "r") as f:
            return f.read().strip()
    except Exception:
        return "1cb3ba2d-5600-44d5-b2d4-a88abea6b365"

def get_host_id():
    try:
        with open("/etc/machine-id", "r") as f:
            return hashlib.sha256(f.read().strip().encode("utf-8")).hexdigest()
    except Exception:
        return "cd94f98268381d66d53599f7a786afebc88f0049dac3cab64cec563f77613cb7"

def main():
    conn_coord = sqlite3.connect(DB_COORD)
    cur_coord = conn_coord.cursor()

    cur_coord.execute("SELECT sequence, digest FROM events ORDER BY sequence DESC LIMIT 1")
    row = cur_coord.fetchone()
    if row is None:
        last_coord_seq = 0
        prev_coord_digest = "uos-session-sync/v1"
    else:
        last_coord_seq, prev_coord_digest = row

    host_id = get_host_id()
    boot_id = get_boot_id()

    last_coord_seq += 1
    op_id = "op-codex-astra-cepaf-gap-zero-intent"
    tick_us = now_us()
    utc_us = tick_us
    operation = "ratify_cycle"

    cmd_json = json.dumps({
        "action": "claim_gap_zero_resolution",
        "plan": PLAN_ID,
        "actor": ACTOR,
        "scope": "apps/cepaf_gleam 15 test failures"
    }, sort_keys=True)

    body_json = json.dumps({
        "title": "Codex Astra Sovereign Elimination of 15 Real Test Failures in apps/cepaf_gleam",
        "evidence": {
            "failures_to_resolve": 15,
            "total_suite_size": 11872,
            "target": "100% green pass in apps/cepaf_gleam (11,872/11,872)"
        }
    }, sort_keys=True)

    raw_c = f"{last_coord_seq}:{op_id}:{host_id}:{boot_id}:{tick_us}:{utc_us}:{operation}:{ACTOR}:{cmd_json}:{body_json}:{prev_coord_digest}"
    c_digest = hashlib.sha256(raw_c.encode("utf-8")).hexdigest()

    cur_coord.execute("""
        INSERT INTO events 
        (sequence, operation_id, host_id, boot_id, tick_us, utc_us, operation, actor, command_json, body_json, previous_digest, digest, inserted_utc_us)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (last_coord_seq, op_id, host_id, boot_id, tick_us, utc_us, operation, ACTOR, cmd_json, body_json, prev_coord_digest, c_digest, utc_us))

    conn_coord.commit()
    conn_coord.close()

    print(f"[PASS] Coordinator event {op_id} recorded at sequence {last_coord_seq} with digest {c_digest[:16]}...")

if __name__ == "__main__":
    main()
