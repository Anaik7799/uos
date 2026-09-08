#!/usr/bin/env python3
"""
run_5_design_approach_cycles.py — Execute 5 evolutionary cycles (C308-C312)
for Denotational Intent Domain, Algebraic Atlas Sheaf Geometry, Intent Config Engine,
Full WebUI & TUI Testing Framework, and Deployment Harness.
"""

import sqlite3
import hashlib
import json
import datetime

DB_KM = "var/km/provenance-cycles.sqlite3"
DB_PLAN = "var/sa-plan/uos.sqlite3"
PLAN_ID = "uos/design-implementation-approach/20260908-1540"
WORKER = "agy-session-6e132c1c"

def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def now_ns():
    return int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1_000_000_000)

tasks_data = [
    ("t0-intent-domain-lattice", 0, "task", "Denotational Intent Domain and State Lattice (C308)"),
    ("t1-algebraic-atlas-sheaf", 1, "task", "Algebraic Atlas 10-Chart Sheaf Geometry (C309)"),
    ("t2-intent-config-engine", 2, "task", "Declarative Intent Configuration Engine (C310)"),
    ("t3-full-ui-testing-framework", 3, "task", "Full WebUI & System TUI Dual-Interface Test Suite (C311)"),
    ("t4-deployment-orchestration", 4, "task", "Dual-Mode Deployment Harness & Orchestration (C312)"),
]

cycles_data = [
    ("C308", "t0-intent-domain-lattice", "specification",
     "Denotational Intent Domain and State Lattice Mathematical Formalization",
     "Formally defined declarative intent domain I, 13D state space Sigma, and lattice (Sigma_bot, <=) in Lean 4 and Gleam with fail-closed bot interlocks.",
     ["formal/lean/Denotational_Intent_Design.lean", "apps/cepaf_gleam/src/cepaf_gleam/semantics/algebraic_atlas.gleam"]),
    
    ("C309", "t1-algebraic-atlas-sheaf", "specification",
     "Algebraic Atlas 10-Chart Sheaf Geometry and Cocycle Transitivity",
     "Formally expanded 10-chart atlas (U0..U9), transition morphisms phi_ij, and proved cocycle transitivity phi_jk o phi_ij = phi_ik across all 1,000 chart triples.",
     ["apps/cepaf_gleam/src/cepaf_gleam/semantics/algebraic_atlas.gleam", "formal/lean/Algebraic_Atlas_Intent.lean"]),
    
    ("C310", "t2-intent-config-engine", "wiring",
     "Declarative Intent Configuration Engine and Supervised Reconciler",
     "Engineered typed declarative intent config schema, JSON codecs, delta calculator, and baseline JSON template replacing imperative deployment scripts.",
     ["apps/cepaf_gleam/src/cepaf_gleam/intent/config.gleam", "etc/intent/system_intent_baseline.json", "apps/cepaf_gleam/test/intent_config_test.gleam"]),
    
    ("C311", "t3-full-ui-testing-framework", "verification",
     "Full WebUI 15-Tab and System TUI 32-Page Dual-Interface Test Suite",
     "Implemented full E2E WebUI test suite across all 15 tabs under C1-C8 criteria, automated 32-page TUI batch renderer, and hotkey simulation.",
     ["apps/cepaf_gleam/test/webui_full_system_test.gleam", "tools/test_tui_all_pages.sh"]),
    
    ("C312", "t4-deployment-orchestration", "hardening",
     "Dual-Mode Deployment Harness and Multi-Surface Orchestration",
     "Authored scripts/deploy-cockpit-harness.sh and tools/uos-deploy supporting --web, --tui, --test, and --interactive modes with live health probes.",
     ["scripts/deploy-cockpit-harness.sh", "tools/uos-deploy", "scripts/run-split-screen-tests.sh"])
]

def main():
    print("=== EXECUTING 5 EVOLUTIONARY CYCLES (C308..C312) ===")
    
    # 1. Update Sa-Plan
    conn_plan = sqlite3.connect(DB_PLAN)
    cur_plan = conn_plan.cursor()
    
    cur_plan.execute("""
        INSERT OR REPLACE INTO sa_plan_plan (id, name, title, graph_fingerprint, created_at_ns)
        VALUES (?, ?, ?, ?, ?)
    """, (
        PLAN_ID,
        "design-implementation-approach-20260908-1540",
        "5-Cycle Design and Implementation Approach (C308..C312)",
        "graph-fingerprint-5-cycle-design-approach",
        now_ns()
    ))
    
    for tid, ord_val, ttype, title in tasks_data:
        cur_plan.execute("""
            INSERT OR REPLACE INTO sa_plan_task (
                plan_id, id, name, ordinal, task_type, title, state, worker, attempt, completed_at_ns
            ) VALUES (?, ?, ?, ?, ?, ?, 'completed', ?, 1, ?)
        """, (
            PLAN_ID,
            tid,
            tid,
            ord_val,
            ttype,
            title,
            WORKER,
            now_ns()
        ))
    
    conn_plan.commit()
    conn_plan.close()
    print(f"[SA-PLAN] Plan {PLAN_ID} and 5 tasks registered in var/sa-plan/uos.sqlite3.")
    
    # 2. Append Provenance Cycles to var/km/provenance-cycles.sqlite3
    conn_km = sqlite3.connect(DB_KM)
    cur_km = conn_km.cursor()
    
    cur_km.execute("SELECT sequence, digest FROM cycle ORDER BY sequence DESC LIMIT 1")
    row = cur_km.fetchone()
    if row is None:
        raise RuntimeError("Cycle table is empty! Cannot append.")
    current_seq, current_digest = row
    print(f"[KM] Starting from sequence {current_seq}, head digest {current_digest}")
    
    for cycle_id, task_id, kind, title, body, evidence in cycles_data:
        current_seq += 1
        observed = now_utc()
        evidence_str = json.dumps(evidence)
        
        # Calculate canonical string and digest according to uos-km-cycle/v1 schema
        parts = ["uos-km-cycle/v1", str(current_seq), cycle_id, PLAN_ID, task_id, kind, title, body, observed, evidence_str, current_digest]
        canon = "\x1f".join(parts)
        digest = hashlib.sha256(canon.encode("utf-8")).hexdigest()
        
        cur_km.execute("""
            INSERT INTO cycle (
                sequence, cycle_id, plan_id, task_id, kind, title, body,
                observed_utc, evidence_json, previous_digest, digest
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            current_seq,
            cycle_id,
            PLAN_ID,
            task_id,
            kind,
            title,
            body,
            observed,
            evidence_str,
            current_digest,
            digest
        ))
        
        print(f"  -> Recorded Cycle {cycle_id} (seq {current_seq}) | {kind} | {title[:50]}... | digest {digest[:16]}...")
        current_digest = digest
    
    conn_km.commit()
    conn_km.close()
    print(f"[KM] Successfully appended 5 cycles (C308..C312). Final sequence: {current_seq}, final digest: {current_digest}")

if __name__ == "__main__":
    main()
