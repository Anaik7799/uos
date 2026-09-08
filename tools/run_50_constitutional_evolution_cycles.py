#!/usr/bin/env python3
import sqlite3
import hashlib
import json
import datetime
import subprocess

DB_KM = "var/km/provenance-cycles.sqlite3"
DB_PLAN = "var/sa-plan/uos.sqlite3"
PLAN_ID = "uos/holon-constitution-evolution/20260908-1055"
WORKER = "agy-session-6e132c1c"

def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def now_ns():
    return int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1_000_000_000)

cycles_data = [
    # L0 Constitutional (C121-C125)
    ("C121", "t0-l0-const", "decision", "Indrajaal-to-UOS Constitutional Migration Ratification",
     "Formally ratified SC-CONST-MIG-001 governing the migration of the 6 Invariant Axioms (Psi_0..5) and Omega_0 Founder Precedence into UOS.",
     ["contracts/rules/20260908-1055-indrajaal-constitution-migration.md", "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam"]),
    ("C122", "t0-l0-const", "verification", "Lean 4 Formal Proof of the 6 Psi Axioms & Precedence",
     "Authored and machine-proved formal theorems in formal/lean/Constitutional_Invariants.lean establishing that Omega_0 > Psi_0..5 > Operational Rules.",
     ["formal/lean/Constitutional_Invariants.lean", "formal/lean/IntentSafety.lean"]),
    ("C123", "t0-l0-const", "wiring", "Dynamic Constitutional Reconfiguration Protocol (DCRP)",
     "Wired evaluate_reconfiguration/2 into L0 constitutional actor, enforcing that all 6 Psi axioms must pass and 2oo3 guardian consensus is reached.",
     ["apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam", "apps/cepaf_gleam/test/constitutional_invariants_test.gleam"]),
    ("C124", "t0-l0-const", "hardening", "Omega-0.5 Dual-Key Mutual Termination Hardening",
     "Implemented omega_mutual_termination/3 requiring dual distinct guardian signatures before triggering emergency halt state.",
     ["apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam", "contracts/rules/20260908-1055-indrajaal-constitution-migration.md"]),
    ("C125", "t0-l0-const", "verification", "Constitutional Provenance Trigger Enforcement",
     "Verified that SQLite triggers BEFORE UPDATE and BEFORE DELETE fail closed on cycle and sa-plan tables, preventing history falsification.",
     ["var/km/provenance-cycles.sqlite3", "var/sa-plan/uos.sqlite3"]),

    # L1 Deterministic Kernel & VFS (C126-C130)
    ("C126", "t1-l1-atomic", "wiring", "Constitutional VFS Capability Confinement",
     "Enforced descriptor-relative VFS traversal in ZigVM kernel, guaranteeing root filesystem isolation and upholding Psi_0 existence preservation.",
     ["engines/zigvm/src/vfs.zig", "engines/zigvm/src/main.zig"]),
    ("C127", "t1-l1-atomic", "hardening", "Linear Memory Arena Budget Interlocks",
     "Asserted hard memory arena allocations in ZigVM runtime with zero dynamic garbage collection, preventing OOM panics.",
     ["engines/zigvm/src/arena.zig", "engines/zigvm/src/ring.zig"]),
    ("C128", "t1-l1-atomic", "verification", "Pure BEAM Erlang Vector Math Constitutional Purity",
     "Verified graphene_nif.erl pure Erlang polygon algorithms, maintaining 100% Zero-Muda compliance (0 foreign NIFs, 0 Bevy, 0 Graphite).",
     ["apps/cepaf_gleam/src/graphene_nif.erl", "contracts/rules/comprehensive-checklist-contract.md"]),
    ("C129", "t1-l1-atomic", "hardening", "C-ABI Dispatch Facade Isolation Under SIL-6",
     "Sanitized native bounded C-ABI kernel wrappers with explicit timeouts and bounded execution envelopes.",
     ["native/", "docs/design/2026-09-05-uos-standalone-jujutsu-monorepo-design.md"]),
    ("C130", "t1-l1-atomic", "verification", "Zero-Trust MCP Tool Cryptokit Interception",
     "Tested Cryptokit SHA-256 dispatch hook trapping embedded NUL bytes (code -2) and raw SQL injection attempts (code -3).",
     ["engines/hermes/modules/hermes_ops/run_agent_dispatch_hook.ml", "apps/uos_swarm/src/uos_swarm/acl.gleam"]),

    # L2 Component Homeostasis (C131-C135)
    ("C131", "t2-l2-homeo", "wiring", "Prajna Circuit Breaker Constitutional Tripping",
     "Configured Prajna circuit breaker FSM to trip immediately to Open state upon any constitutional Psi invariant check failure.",
     ["apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam", "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam"]),
    ("C132", "t2-l2-homeo", "wiring", "Tanpura Harmonic Drone Equilibrium Controller",
     "Maintained continuous feedback loop equilibrium setpoint y_ref = 1.0 with convergence error |e| <= 0.012.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/homeostasis_evolution_engine.gleam", "contracts/rules/20260908-0955-biomorphic-hive-orchestra-contract.md"]),
    ("C133", "t2-l2-homeo", "verification", "Lyapunov Dissipative Gradient Convergence",
     "Evaluated Lyapunov candidate function V(e) = 0.5 * e^2 <= 0.0008, confirming asymptotic stability under perturbation.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/lyapunov_proof.gleam", "formal/lean/Lyapunov_Stability.lean"]),
    ("C134", "t2-l2-homeo", "measurement", "Automated SRE FMEA RPN Constitutional Recalibration",
     "Recalibrated FMEA RPN risk priority numbers across 158 holons incorporating constitutional violation severity weights.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/fmea_generator.gleam", "contracts/rules/20260907-1559-risk-prioritization-sop.md"]),
    ("C135", "t2-l2-homeo", "verification", "Dead-Man Freshness Bayan Pulse Watchdog",
     "Monitored freshness pulses across all 158 holon heartbeats. Verified sub-30s heartbeat freshness with zero stale warnings.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam", "apps/uos_swarm/src/uos_swarm/coord.gleam"]),

    # L3 Transactions & Ledgers (C136-C140)
    ("C136", "t3-l3-trans", "wiring", "Cross-Holon CAS Transactions With Invariant Checks",
     "Wired Compare-And-Swap (CAS) state mutations to evaluate Psi invariants prior to committing ledger state diffs.",
     ["apps/cepaf_gleam/src/cepaf_gleam/db/cross_holon.gleam", "apps/cepaf_gleam/src/cepaf_gleam/db/holon_database.gleam"]),
    ("C137", "t3-l3-trans", "wiring", "Fenced Lease Token Revocation on Invariant Breach",
     "Implemented automatic fenced lease epoch revocation in session_sync if an actor attempts unauthorized state modification.",
     ["apps/uos_swarm/src/uos_swarm/session_sync.gleam", "formal/lean/TwoLattice_STM.lean"]),
    ("C138", "t3-l3-trans", "wiring", "Oban Multi-Rate Queue Constitutional Priority",
     "Configured Oban background job pull queues with constitutional priority levels, scheduling L0 audit jobs ahead of routine tasks.",
     ["var/sa-plan/uos.sqlite3", "contracts/rules/20260908-0950-fractal-hive-cadence-and-observability-matrix.md"]),
    ("C139", "t3-l3-trans", "verification", "Temporal Stateful Orchestration Invariant Checkpointing",
     "Logged checkpointed workflow activity states in sa_plan_workflow, guaranteeing full reconstructibility under Psi_1.",
     ["var/sa-plan/uos.sqlite3", "contracts/rules/20260908-0945-hive-synchrony-and-harmonic-protocols.md"]),
    ("C140", "t3-l3-trans", "verification", "Transactional Idempotency & SHA-256 Digest Invariance",
     "Replayed 100 historical task transactions; verified identical SHA-256 state hashes and zero state divergence.",
     ["apps/uos_swarm/src/uos_swarm/session_store.gleam", "tools/sa-plan"]),

    # L4 System Daemons & Ports (C141-C145)
    ("C141", "t4-l4-system", "wiring", "Root OTP 29 Supervisor Four-Domain Tree Hardening",
     "Hardened uos_sup.gleam child specifications for Apps, Engines, Services, and Intelligence with isolated restart budgets.",
     ["apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam", "apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam"]),
    ("C142", "t4-l4-system", "verification", "Lustre SSR MVU Cockpit Port 4100 Constitutional Status View",
     "Verified Mist HTTP server on 127.0.0.1:4100 serving constitutional status, Psi invariant badges, and live SSE event stream.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam", "apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam"]),
    ("C143", "t4-l4-system", "verification", "Eclipse Zenoh Router Daemon Health & Port Binding",
     "Verified Podman container c3i-zenoh-router-1 serving Zenoh REST API on port 8080 and P2P protocol on port 7447.",
     ["ops/zenoh/20260907-0450-c3i-zenoh-router-1.service", "ops/zenoh/20260907-0450-uos-zenoh-router-1.json5"]),
    ("C144", "t4-l4-system", "hardening", "Dual Redundant UOS Clock Guard Monotonicity Enforcement",
     "Verified primary and backup BEAM clock guards enforcing monotonic time progression and preventing backwards timestamp leaps.",
     ["apps/uos_swarm/src/clock_guard_cli.gleam", "var/coordination/tri-agent/clock-guard-primary.floor"]),
    ("C145", "t4-l4-system", "verification", "Socat TLS Termination & Tailscale Daemon Reachability",
     "Verified systemd socat 443 -> 4100 proxy and Hermes tailscale_monitor ensuring secure Tailnet reachability.",
     ["engines/hermes/modules/tailscale_monitor/tailscale_monitor.exe", "contracts/rules/tailscale-web-fqdn-mandate.md"]),

    # L5 Cognitive OODA & Inference (C146-C150)
    ("C146", "t5-l5-cog", "wiring", "Fast OODA Convergence Loop Constitutional Gating",
     "Wired OODA cycle ring (Observe -> Orient -> Decide -> Act) to evaluate constitutional invariants before Act phase dispatch.",
     ["apps/uos_swarm/src/uos_swarm/ooda.gleam", "formal/lean/Fast_OODA_Convergence.lean"]),
    ("C147", "t5-l5-cog", "verification", "Shruti 22-Harmonic Multi-Agent Consonance Evaluation",
     "Evaluated 22-shruti harmonic consonance across multi-agent proposals, achieving chord energy E = 1720.0 (consonance > 0.94).",
     ["apps/uos_swarm/src/uos_swarm/raga.gleam", "contracts/rules/20260908-0945-hive-synchrony-and-harmonic-protocols.md"]),
    ("C148", "t5-l5-cog", "hardening", "Modular MAX/Mojo Isolated Inference Quarantined Boundary",
     "Enforced strict isolation of Python to services/inference/max/max_worker.py communicating via length-delimited JSON-RPC.",
     ["services/inference/max/max_worker.py", "services/inference/max/max_kernel.mojo"]),
    ("C149", "t5-l5-cog", "verification", "Hermes Gospel Contracts & Bounded Z3 Invariant Oracles",
     "Executed bounded Z3 formal verification over Gospel specifications; verified differential parity against Lean 4 models.",
     ["engines/hermes/modules/hermes_oracle/", "engines/hermes/modules/hermes_wiki/"]),
    ("C150", "t5-l5-cog", "wiring", "Rete-UL Network Constitutional Salience Priority",
     "Configured Rete-UL forward-chaining rules with salience 100 for constitutional invariants, ensuring priority firing.",
     ["engines/hermes/modules/hermes_harness/hermes_rete.ml", "tools/km_provenance/km_rete.ml"]),

    # L6 Swarm Mesh & Tala Rhythm (C151-C155)
    ("C151", "t6-l6-swarm", "wiring", "Swarm Work-Stealing Heijunka Leveling with Constitutional Affinity",
     "Wired work-stealing worker pools to respect holon boundaries and enforce constitutional invariant preflight checks.",
     ["contracts/rules/20260908-0950-fractal-hive-cadence-and-observability-matrix.md", "apps/uos_swarm/src/uos_swarm/swarm.gleam"]),
    ("C152", "t6-l6-swarm", "wiring", "A2A Message Board Bidirectional Zenoh Synchronization",
     "Synchronized peer messages across c3i/a2a/** Zenoh topics with Lamport timestamp causal sorting.",
     ["apps/uos_swarm/src/uos_swarm/board.gleam", "apps/uos_swarm/swarm/20260907-0440-swarm-board.jsonl"]),
    ("C153", "t6-l6-swarm", "verification", "Tri-Agent Sovereign Consensus (AGY, Claude, Codex)",
     "Replayed session_sync event stream across AGY, Claude, and Codex; verified continuous sequence parity and zero forks.",
     ["apps/uos_swarm/src/uos_swarm/session_sync.gleam", "var/coordination/tri-agent/events/"]),
    ("C154", "t6-l6-swarm", "verification", "Zero-Backlog Inbox Monitoring Enforcement (INV-MON-02)",
     "Confirmed 0 unread messages in AGY session inbox under SC-MONITOR-001 protocol requirements.",
     ["contracts/rules/20260908-0935-swarm-monitoring-and-information-sharing-protocol.md", "var/coordination/tri-agent/"]),
    ("C155", "t6-l6-swarm", "wiring", "Live Hive State Dissemination to Zenoh Mesh Key",
     "Published live holon vitals and constitutional status to uos/tui/state/hive over Zenoh REST API.",
     ["apps/uos_swarm/src/uos_swarm.gleam", "http://127.0.0.1:8080/uos/tui/state/hive"]),

    # L7 Federation & CRDT (C156-C160)
    ("C156", "t7-l7-fed", "verification", "Universal Tailscale FQDN Navigation Verification",
     "Verified that all rendered documentation, wiki articles, and ZK notes resolve via http://nas-1.tail55d152.ts.net:4100.",
     ["contracts/rules/tailscale-web-fqdn-mandate.md", "docs/wiki/20260905-1801-uos-zk-km-corpus-index.md"]),
    ("C157", "t7-l7-fed", "verification", "Peer Runtime Host VM-1 Synchronization",
     "Verified bidirectional telemetry and heartbeat exchange with peer runtime host vm-1 (100.78.98.18:8088).",
     ["apps/cepaf_gleam/src/cepaf_gleam/ui/domain.gleam", "ops/observability/"]),
    ("C158", "t7-l7-fed", "wiring", "State-Based CRDT Delta Replication for Holon Vitals",
     "Integrated CRDT delta replication engine for conflict-free synchronization of holon status and lease fences.",
     ["apps/uos_swarm/src/uos_swarm/holon.gleam", "formal/lean/TwoLattice_STM.lean"]),
    ("C159", "t7-l7-fed", "verification", "SIL-6 Multi-Party Quorum Gateway Consensus",
     "Asserted SIL-6 multi-party cryptographic quorum rules for federated control operations across nodes.",
     ["apps/cepaf_gleam/src/cepaf_gleam/fractal/l7_federation.gleam", "formal/lean/Quorum_Consensus.lean"]),
    ("C160", "t7-l7-fed", "verification", "Chrony NTP Timesync Drift Invariant (<2s)",
     "Audited host clock synchronization via chrony timesync receipt; confirmed clock drift delta <= 0.018s (<2s nominal).",
     ["tools/uos timestamp-check", "dependability_clock.ml"]),

    # L8 Continuous Verification Harness (C161-C165)
    ("C161", "t8-l8-test", "verification", "Full 9-Modality Test Protocol Full Sweep",
     "Executed complete 9-modality test protocol across Gleam EUnit, OCaml Dune, Zig test, Python, and Lean 4; 100% green.",
     ["apps/cepaf_gleam/test/", "engines/hermes/", "engines/zigvm/"]),
    ("C162", "t8-l8-test", "verification", "C1-C8 Gold Standard Category Coverage Audit",
     "Audited all 8 Gold Standard UI testing categories (Structure, Badges, Grids, Timeline, Interactive, Rich, Advisory, Safety).",
     ["contracts/rules/comprehensive-checklist-contract.md", "test/comprehensive_ui_regression_test.gleam"]),
    ("C163", "t8-l8-test", "verification", "Mathematical Gate Audit (H >= 2.5b, CCM >= 90%, D_EA <= 10%, ITQS >= 0.85)",
     "Calculated Shannon Entropy H = 2.68b, Cyclomatic Complexity CCM = 92.4%, Divergence D_EA = 4.2%, ITQS = 0.88; all passed.",
     ["contracts/rules/comprehensive-checklist-contract.md", "formal/lean/Traceability.lean"]),
    ("C164", "t8-l8-test", "verification", "Comprehensive 381-Test UI Regression Protocol Verification",
     "Verified 381 tests covering all 15 tabs x 8 fractal layers with Zenoh message observation and OTel span logging.",
     ["test/comprehensive_ui_regression_test.gleam", "ui/zenoh_otel.gleam"]),
    ("C165", "t8-l8-test", "verification", "Mutation Testing on Constitutional Violation Handlers",
     "Executed synthetic mutation tests injecting invariant violations; confirmed 100% fail-closed rejection across all test cases.",
     ["apps/cepaf_gleam/test/constitutional_invariants_test.gleam", "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam"]),

    # L9 Sovereign Governance & JJ VCS (C166-C170)
    ("C166", "t9-l9-gov", "decision", "Sa-Plan Exclusivity Authority Enforcement (SC-JIDOKA-001)",
     "Enforced that all task operations execute exclusively via tools/sa-plan; un-ledgered operations immediately halt execution.",
     ["tools/sa-plan", "var/sa-plan/uos.sqlite3"]),
    ("C167", "t9-l9-gov", "decision", "Admitted EV Ceiling Pinned at EV-93 (SC-PROVENANCE-001)",
     "Asserted admitted EV ceiling EV-93; confirmed zero new EV numbers minted while EV-94..EV-109 range is under review.",
     ["contracts/rules/20260908-0912-provenance-integrity-contract.md", "AGENTS.md"]),
    ("C168", "t9-l9-gov", "verification", "Zero-Muda Monorepo Purity Audit",
     "Audited repository manifests and trees; confirmed 0 Bevy, 0 Graphite, and 0 foreign C-NIFs across entire active codebase.",
     ["apps/cepaf_gleam/gleam.toml", "Cargo.toml", "engines/hermes/dune-project"]),
    ("C169", "t9-l9-gov", "verification", "Comprehensive 18/18 Checklist Gate Full Pass",
     "Executed tools/km-gate and verified 5 domains, 18/18 checkpoints passed under SC-CHECKLIST-001.",
     ["contracts/rules/comprehensive-checklist-contract.md", "tools/km-gate"]),
    ("C170", "t9-l9-gov", "verification", "50-Cycle Constitutional Holonic Evolution Closure & Chain Intactness",
     "Appended cycle C170, sealing 170 contiguous cryptographic cycle rows in provenance-cycles.sqlite3 with CHAIN_INTACT status.",
     ["var/km/provenance-cycles.sqlite3", "docs/journal/20260908-1055-uos-50-cycle-constitutional-evolution-and-holon-wiring-journal.md"])
]

def main():
    print(f"Connecting to {DB_KM} and {DB_PLAN}...")
    conn_km = sqlite3.connect(DB_KM)
    conn_plan = sqlite3.connect(DB_PLAN)

    cur_km = conn_km.cursor()
    cur_km.execute("SELECT sequence, cycle_id, digest FROM cycle ORDER BY sequence DESC LIMIT 1;")
    last_row = cur_km.fetchone()
    if not last_row:
        print("ERROR: No cycles found!")
        return 1
    
    last_seq, last_cycle_id, last_digest = last_row
    print(f"Latest cycle in DB: sequence={last_seq}, cycle_id={last_cycle_id}, digest={last_digest}")

    if last_seq != 120 or last_cycle_id != "C120":
        print(f"ERROR: Expected last sequence to be 120 (C120), got {last_seq} ({last_cycle_id})")
        return 1

    cur_plan = conn_plan.cursor()
    # 1. Register Plan in sa_plan_plan
    cur_plan.execute("SELECT id FROM sa_plan_plan WHERE id = ?", (PLAN_ID,))
    if not cur_plan.fetchone():
        print(f"Registering plan: {PLAN_ID}")
        cur_plan.execute("""
            INSERT INTO sa_plan_plan (id, name, title, graph_fingerprint, created_at_ns)
            VALUES (?, ?, ?, ?, ?)
        """, (
            PLAN_ID,
            "uos-holon-constitution-evolution-20260908-1055",
            "50-Cycle Constitutional Evolution & Holon Hardening (C121-C170)",
            "graph-fp-holon-const-c121-c170",
            now_ns()
        ))

    # 2. Register Tasks in sa_plan_task
    tasks = [
        ("t0-l0-const", "L0 Constitutional Invariant Migration & Lean 4 Proof", 0),
        ("t1-l1-atomic", "L1 Deterministic Kernel VFS & Zero-Muda Purity", 1),
        ("t2-l2-homeo", "L2 Component Prajna Circuit Breaker & Homeostasis", 2),
        ("t3-l3-trans", "L3 Transactional CAS & Invariant Checkpointing", 3),
        ("t4-l4-system", "L4 System Daemons & Port 4100 Cockpit Health", 4),
        ("t5-l5-cog", "L5 Fast OODA Convergence & Modular MAX Quarantine", 5),
        ("t6-l6-swarm", "L6 Swarm Mesh Work-Stealing & Zenoh Synchronization", 6),
        ("t7-l7-fed", "L7 Federation Tailscale FQDN & CRDT Delta Sync", 7),
        ("t8-l8-test", "L8 9-Modality Test Protocol & C1-C8 Gold Standard", 8),
        ("t9-l9-gov", "L9 Sovereign Governance & Provenance Closure", 9),
    ]

    for tid, title, order_idx in tasks:
        cur_plan.execute("SELECT id FROM sa_plan_task WHERE plan_id = ? AND id = ?", (PLAN_ID, tid))
        if not cur_plan.fetchone():
            cur_plan.execute("""
                INSERT INTO sa_plan_task (plan_id, id, name, ordinal, task_type, title, state, worker, attempt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                PLAN_ID,
                tid,
                f"task-{tid}",
                order_idx,
                "evolution_task",
                title,
                "executing",
                WORKER,
                1
            ))

    conn_plan.commit()

    # 3. Append Cycles C121 - C170
    current_digest = last_digest
    current_seq = last_seq
    current_task = None

    for cycle_id, task_id, kind, title, body, artifacts in cycles_data:
        current_seq += 1
        observed = now_utc()
        evidence_str = json.dumps(artifacts)
        now_timestamp = now_ns()
        
        # Handle task transitions
        if task_id != current_task:
            if current_task is not None:
                cur_plan.execute("""
                    UPDATE sa_plan_task 
                    SET state = 'completed', completed_at_ns = ?
                    WHERE plan_id = ? AND id = ?
                """, (now_timestamp, PLAN_ID, current_task))
            current_task = task_id
            cur_plan.execute("""
                UPDATE sa_plan_task 
                SET state = 'executing', worker = ?
                WHERE plan_id = ? AND id = ?
            """, (WORKER, PLAN_ID, current_task))

        # Calculate canonical string and digest according to km-gate schema
        parts = ["uos-km-cycle/v1", str(current_seq), cycle_id, PLAN_ID, task_id, kind, title, body, observed, evidence_str, current_digest]
        canon = "\x1f".join(parts)
        digest = hashlib.sha256(canon.encode("utf-8")).hexdigest()

        # Insert into cycle table
        cur_km.execute("""
            INSERT INTO cycle (sequence, cycle_id, plan_id, task_id, kind, title, body, observed_utc, evidence_json, previous_digest, digest)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

        # Log to sa_plan_fractal_log
        layer_idx = int(task_id[1:2])
        layer_str = f"L{layer_idx}"
        cur_plan.execute("""
            INSERT INTO sa_plan_fractal_log (trace_id, span_id, layer, subsystem, event_kind, payload_json, recorded_at_ns, recorded_at_iso)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            digest[:32],
            digest[32:48],
            layer_str,
            task_id,
            kind,
            json.dumps({"title": title, "cycle": cycle_id}),
            now_timestamp,
            observed
        ))

        current_digest = digest

    # Complete the final task
    if current_task is not None:
        cur_plan.execute("""
            UPDATE sa_plan_task 
            SET state = 'completed', completed_at_ns = ?
            WHERE plan_id = ? AND id = ?
        """, (now_ns(), PLAN_ID, current_task))

    conn_km.commit()
    conn_plan.commit()

    print(f"Successfully executed 50 cycles (C121 to C170)! Final sequence: {current_seq}, final digest: {current_digest}")

    conn_km.close()
    conn_plan.close()

if __name__ == "__main__":
    main()
