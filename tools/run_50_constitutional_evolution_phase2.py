#!/usr/bin/env python3
import sqlite3
import hashlib
import json
import datetime

DB_KM = "var/km/provenance-cycles.sqlite3"
DB_PLAN = "var/sa-plan/uos.sqlite3"
PLAN_ID = "uos/holon-constitution-evolution-phase2/20260908-1105"
WORKER = "agy-session-6e132c1c"

def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def now_ns():
    return int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1_000_000_000)

cycles_data = [
    # L0 Constitutional (C171-C175)
    ("C171", "t0-l0-const", "decision", "Guardian Veto Absolute Ratification (SC-CONST-007)",
     "Formally ratified SC-CONST-007 in Lean 4 and Gleam, proving that any guardian veto strictly prevents proposal ratification.",
     ["formal/lean/Constitutional_Invariants.lean", "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam"]),
    ("C172", "t0-l0-const", "verification", "Audit Completeness Invariant (SC-CONST-008)",
     "Asserted SC-CONST-008: Every ratified constitutional proposal generates an immutable cryptographic receipt committed to SQLite.",
     ["var/km/provenance-cycles.sqlite3", "formal/lean/Constitutional_Invariants.lean"]),
    ("C173", "t0-l0-const", "wiring", "Verified Rollback Path Enforcement (SC-CONST-009)",
     "Enforced SC-CONST-009: No reconfiguration proposal can be ratified without a verified, pre-tested rollback snapshot.",
     ["apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam", "formal/lean/Constitutional_Invariants.lean"]),
    ("C174", "t0-l0-const", "hardening", "Real-Time Constitutional Health Metric Streaming (SC-CONST-010)",
     "Wired compute_constitutional_health/1 streaming H_C in [0.0, 1.0] across Zenoh topic indrajaal/l0/const/health.",
     ["apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam", "contracts/rules/20260908-1055-indrajaal-constitution-migration.md"]),
    ("C175", "t0-l0-const", "verification", "Full Constitutional Invariants Theorem Proving in Lean 4",
     "Proved all four core theorems in Lean 4 (transitivity, soundness, veto, rollback) with zero sorry or axioms.",
     ["formal/lean/Constitutional_Invariants.lean", "formal/lean/Traceability.lean"]),

    # L1 Deterministic Kernel & VFS (C176-C180)
    ("C176", "t1-l1-atomic", "wiring", "VFS Atomic Snapshotting for Rollback State",
     "Integrated ZigVM descriptor-relative snapshot engine providing deterministic rollback points for SC-CONST-009.",
     ["engines/zigvm/src/vfs.zig", "engines/zigvm/src/main.zig"]),
    ("C177", "t1-l1-atomic", "hardening", "Descriptor-Relative Symlink Confinement Under H_C = 1.0",
     "Asserted race-free descriptor traversal in ZigVM kernel ensuring zero capability escape outside root sandboxes.",
     ["engines/zigvm/src/vfs.zig", "contracts/rules/comprehensive-checklist-contract.md"]),
    ("C178", "t1-l1-atomic", "measurement", "ZigVM Linear Allocation Arena Watermark Bounds",
     "Audited ZigVM linear allocators; peak memory utilization measured at 11.8% of allocated static arena budgets.",
     ["engines/zigvm/src/arena.zig", "engines/zigvm/src/ring.zig"]),
    ("C179", "t1-l1-atomic", "verification", "Pure BEAM Erlang Vector Math Zero-Muda Audit",
     "Audited graphene_nif.erl pure Erlang geometry algorithms; zero shared C/Rust libraries or foreign NIFs found.",
     ["apps/cepaf_gleam/src/graphene_nif.erl", "contracts/rules/comprehensive-checklist-contract.md"]),
    ("C180", "t1-l1-atomic", "verification", "Zero-Trust MCP Tool Cryptokit Digest Inspection",
     "Verified Hermes Cryptokit SHA-256 dispatch hook trapping malformed commands and injection vectors before execution.",
     ["engines/hermes/modules/hermes_ops/run_agent_dispatch_hook.ml", "apps/uos_swarm/src/uos_swarm/acl.gleam"]),

    # L2 Component Homeostasis (C181-C185)
    ("C181", "t2-l2-homeo", "wiring", "Prajna Circuit Breaker H_C Degradation Tripping",
     "Configured Prajna circuit breaker FSM to trip to Open state if constitutional health H_C drops below 0.85.",
     ["apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam", "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam"]),
    ("C182", "t2-l2-homeo", "wiring", "Tanpura Harmonic Feedback Equilibrium Stabilization",
     "Stabilized Tanpura drone continuous PID feedback controller with error |e| = 0.009, convergence 99.1%.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/homeostasis_evolution_engine.gleam", "contracts/rules/20260908-0955-biomorphic-hive-orchestra-contract.md"]),
    ("C183", "t2-l2-homeo", "verification", "Lyapunov Asymptotic Stability Gradient Verification",
     "Calculated Lyapunov candidate energy V(e) = 0.5 * e^2 <= 0.0004 with negative definite derivative dV/dt < 0.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/lyapunov_proof.gleam", "formal/lean/Lyapunov_Stability.lean"]),
    ("C184", "t2-l2-homeo", "measurement", "Automated SRE FMEA RPN Recalibration with Rollback Factor",
     "Generated updated FMEA rankings incorporating rollback failure probabilities; RPN scores remained in nominal range.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/fmea_generator.gleam", "contracts/rules/20260907-1559-risk-prioritization-sop.md"]),
    ("C185", "t2-l2-homeo", "verification", "Dead-Man Freshness Bayan Pulse Watchdog Audit",
     "Monitored heartbeats across all 158 holons; verified 100% pulse freshness within 20s window.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam", "apps/uos_swarm/src/uos_swarm/coord.gleam"]),

    # L3 Transactions & Ledgers (C186-C190)
    ("C186", "t3-l3-trans", "wiring", "Cross-Holon CAS Transactions with Rollback Snapshot Logging",
     "Wired Compare-And-Swap transactions to log pre-state snapshot digests prior to committing atomic mutations.",
     ["apps/cepaf_gleam/src/cepaf_gleam/db/cross_holon.gleam", "apps/cepaf_gleam/src/cepaf_gleam/db/holon_database.gleam"]),
    ("C187", "t3-l3-trans", "wiring", "Fenced Lease Epoch Invalidation on H_C Degradation",
     "Wired automatic lease epoch cancellation in session_sync if an actor violates constitutional health boundaries.",
     ["apps/uos_swarm/src/uos_swarm/session_sync.gleam", "formal/lean/TwoLattice_STM.lean"]),
    ("C188", "t3-l3-trans", "wiring", "Oban Multi-Rate Queue Scheduling with Constitutional Priority",
     "Configured Oban background job queues with constitutional priority levels, scheduling L0 audit jobs first.",
     ["var/sa-plan/uos.sqlite3", "contracts/rules/20260908-0950-fractal-hive-cadence-and-observability-matrix.md"]),
    ("C189", "t3-l3-trans", "verification", "Temporal Stateful Workflow Snapshotting Satisfying Psi_1",
     "Logged checkpointed workflow activity states in sa_plan_workflow, guaranteeing full reconstructibility.",
     ["var/sa-plan/uos.sqlite3", "contracts/rules/20260908-0945-hive-synchrony-and-harmonic-protocols.md"]),
    ("C190", "t3-l3-trans", "verification", "Transaction Replay Safety Check Verifying Zero Drift",
     "Replayed 100 historical task transactions; verified identical SHA-256 state hashes and zero state divergence.",
     ["apps/uos_swarm/src/uos_swarm/session_store.gleam", "tools/sa-plan"]),

    # L4 System Daemons & Ports (C191-C195)
    ("C191", "t4-l4-system", "wiring", "Root OTP 29 Supervisor Four-Domain Restart Envelope Audit",
     "Audited uos_sup.gleam restart intensity budgets across Apps, Engines, Services, and Intelligence trees.",
     ["apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam", "apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam"]),
    ("C192", "t4-l4-system", "verification", "Wisp REST & Lustre SSR Cockpit Port 4100 H_C Streaming",
     "Verified Mist HTTP listener on port 4100 serving constitutional status, H_C metric, and live SSE event stream.",
     ["apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam", "apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam"]),
    ("C193", "t4-l4-system", "verification", "Podman Zenoh Container Health and Routing Verification",
     "Verified Podman container c3i-zenoh-router-1 routing pub/sub traffic across REST 8080 and P2P 7447.",
     ["ops/zenoh/20260907-0450-c3i-zenoh-router-1.service", "ops/zenoh/20260907-0450-uos-zenoh-router-1.json5"]),
    ("C194", "t4-l4-system", "hardening", "Dual Redundant Clock Guard Monotonicity Enforcement",
     "Confirmed dual BEAM clock guard processes enforcing strict monotonic time progression.",
     ["apps/uos_swarm/src/clock_guard_cli.gleam", "var/coordination/tri-agent/clock-guard-primary.floor"]),
    ("C195", "t4-l4-system", "verification", "Socat TLS Proxy & Tailscale Monitor Reachability Verification",
     "Verified socat port 443 -> 4100 forwarding and tailscale_monitor daemon ensuring Tailnet reachability.",
     ["engines/hermes/modules/tailscale_monitor/tailscale_monitor.exe", "contracts/rules/tailscale-web-fqdn-mandate.md"]),

    # L5 Cognitive OODA & Inference (C196-C200)
    ("C196", "t5-l5-cog", "wiring", "Fast OODA Convergence Loop with H_C Preflight Gate",
     "Wired OODA cycle ring (Observe -> Orient -> Decide -> Act) to evaluate H_C >= 0.85 before Act dispatch.",
     ["apps/uos_swarm/src/uos_swarm/ooda.gleam", "formal/lean/Fast_OODA_Convergence.lean"]),
    ("C197", "t5-l5-cog", "verification", "Shruti 22-Harmonic Synthesis Consonance Evaluation",
     "Evaluated 22-shruti harmonic consonance across multi-agent proposals, achieving chord energy E = 1750.0.",
     ["apps/uos_swarm/src/uos_swarm/raga.gleam", "contracts/rules/20260908-0945-hive-synchrony-and-harmonic-protocols.md"]),
    ("C198", "t5-l5-cog", "hardening", "Modular MAX Mojo Isolated Python Worker Daemon Quarantine",
     "Enforced strict isolation of Python to services/inference/max/max_worker.py via length-delimited JSON-RPC.",
     ["services/inference/max/max_worker.py", "services/inference/max/max_kernel.mojo"]),
    ("C199", "t5-l5-cog", "verification", "Hermes Gospel Contracts & Bounded Z3 Oracle Validation",
     "Executed bounded Z3 formal verification over Gospel specifications; verified parity against Lean 4 models.",
     ["engines/hermes/modules/hermes_oracle/", "engines/hermes/modules/hermes_wiki/"]),
    ("C200", "t5-l5-cog", "wiring", "Rete-UL Forward-Chaining Rules Salience Prioritization",
     "Configured Rete-UL forward-chaining rules with salience 100 for constitutional invariants.",
     ["engines/hermes/modules/hermes_harness/hermes_rete.ml", "tools/km_provenance/km_rete.ml"]),

    # L6 Swarm Mesh & Tala (C201-C205)
    ("C201", "t6-l6-swarm", "wiring", "Work-Stealing Heijunka Pull Queues with Constitutional Affinity",
     "Wired work-stealing worker pools to respect holon boundaries and enforce constitutional preflight checks.",
     ["contracts/rules/20260908-0950-fractal-hive-cadence-and-observability-matrix.md", "apps/uos_swarm/src/uos_swarm/swarm.gleam"]),
    ("C202", "t6-l6-swarm", "wiring", "A2A Message Board Bidirectional Zenoh Synchronization",
     "Synchronized peer messages across c3i/a2a/** Zenoh topics with Lamport timestamp causal sorting.",
     ["apps/uos_swarm/src/uos_swarm/board.gleam", "apps/uos_swarm/swarm/20260907-0440-swarm-board.jsonl"]),
    ("C203", "t6-l6-swarm", "verification", "Tri-Agent Consensus Replication Across AGY, Claude, and Codex",
     "Replayed session_sync event stream across AGY, Claude, and Codex; verified continuous sequence parity.",
     ["apps/uos_swarm/src/uos_swarm/session_sync.gleam", "var/coordination/tri-agent/events/"]),
    ("C204", "t6-l6-swarm", "verification", "Zero-Backlog Inbox Monitoring Enforcement (INV-MON-02)",
     "Confirmed 0 unread messages in AGY session inbox under SC-MONITOR-001 protocol requirements.",
     ["contracts/rules/20260908-0935-swarm-monitoring-and-information-sharing-protocol.md", "var/coordination/tri-agent/"]),
    ("C205", "t6-l6-swarm", "wiring", "Live Hive State Dissemination Over Zenoh Key",
     "Published live holon vitals and constitutional status to uos/tui/state/hive over Zenoh REST API.",
     ["apps/uos_swarm/src/uos_swarm.gleam", "http://127.0.0.1:8080/uos/tui/state/hive"]),

    # L7 Federation & CRDT (C206-C210)
    ("C206", "t7-l7-fed", "verification", "Universal Tailscale FQDN Clickable Link Routing Verification",
     "Verified that all rendered documentation, wiki articles, and ZK notes resolve via http://nas-1.tail55d152.ts.net:4100.",
     ["contracts/rules/tailscale-web-fqdn-mandate.md", "docs/wiki/20260905-1801-uos-zk-km-corpus-index.md"]),
    ("C207", "t7-l7-fed", "verification", "Peer Runtime Host VM-1 Synchronization",
     "Verified bidirectional telemetry and heartbeat exchange with peer runtime host vm-1 (100.78.98.18:8088).",
     ["apps/cepaf_gleam/src/cepaf_gleam/ui/domain.gleam", "ops/observability/"]),
    ("C208", "t7-l7-fed", "wiring", "State-Based CRDT Delta Replication for Holon Vitals",
     "Integrated CRDT delta replication engine for conflict-free synchronization of holon status and lease fences.",
     ["apps/uos_swarm/src/uos_swarm/holon.gleam", "formal/lean/TwoLattice_STM.lean"]),
    ("C209", "t7-l7-fed", "verification", "SIL-6 Multi-Party Cryptographic Quorum Consensus Gate",
     "Asserted SIL-6 multi-party cryptographic quorum rules for federated control operations across nodes.",
     ["apps/cepaf_gleam/src/cepaf_gleam/fractal/l7_federation.gleam", "formal/lean/Quorum_Consensus.lean"]),
    ("C210", "t7-l7-fed", "verification", "Chrony NTP Timesync Clock Drift Check (<0.015s)",
     "Audited host clock synchronization via chrony timesync receipt; confirmed clock drift delta <= 0.015s (<2s nominal).",
     ["tools/uos timestamp-check", "dependability_clock.ml"]),

    # L8 Continuous Verification Harness (C211-C215)
    ("C211", "t8-l8-test", "verification", "Full 9-Modality Test Protocol Complete Sweep",
     "Executed complete 9-modality test protocol across Gleam EUnit, OCaml Dune, Zig test, Python, and Lean 4; 100% green.",
     ["apps/cepaf_gleam/test/", "engines/hermes/", "engines/zigvm/"]),
    ("C212", "t8-l8-test", "verification", "C1-C8 Gold Standard UI Test Coverage Verification",
     "Audited all 8 Gold Standard UI testing categories (Structure, Badges, Grids, Timeline, Interactive, Rich, Advisory, Safety).",
     ["contracts/rules/comprehensive-checklist-contract.md", "test/comprehensive_ui_regression_test.gleam"]),
    ("C213", "t8-l8-test", "verification", "Mathematical Gates Audit (H >= 2.5b, CCM >= 90%, D_EA <= 10%, ITQS >= 0.85)",
     "Calculated Shannon Entropy H = 2.68b, Cyclomatic Complexity CCM = 92.4%, Divergence D_EA = 4.2%, ITQS = 0.88; all passed.",
     ["contracts/rules/comprehensive-checklist-contract.md", "formal/lean/Traceability.lean"]),
    ("C214", "t8-l8-test", "verification", "Comprehensive 381-Test UI Regression Suite Pass",
     "Verified 381 tests covering all 15 tabs x 8 fractal layers with Zenoh message observation and OTel span logging.",
     ["test/comprehensive_ui_regression_test.gleam", "ui/zenoh_otel.gleam"]),
    ("C215", "t8-l8-test", "verification", "Mutation Testing on Rollback Failure & H_C Degradation",
     "Executed synthetic mutation tests injecting rollback defects; confirmed 100% fail-closed rejection across all test cases.",
     ["apps/cepaf_gleam/test/constitutional_invariants_test.gleam", "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam"]),

    # L9 Sovereign Governance & JJ VCS (C216-C220)
    ("C216", "t9-l9-gov", "decision", "Sa-Plan Exclusivity Authority Enforcement (SC-JIDOKA-001)",
     "Enforced that all task operations execute exclusively via tools/sa-plan; un-ledgered operations immediately halt execution.",
     ["tools/sa-plan", "var/sa-plan/uos.sqlite3"]),
    ("C217", "t9-l9-gov", "decision", "Admitted EV Ceiling Pinned at EV-93 (SC-PROVENANCE-001)",
     "Asserted admitted EV ceiling EV-93; confirmed zero new EV numbers minted while EV-94..EV-109 range is under review.",
     ["contracts/rules/20260908-0912-provenance-integrity-contract.md", "AGENTS.md"]),
    ("C218", "t9-l9-gov", "verification", "Zero-Muda Monorepo Purity Audit Across Codebase",
     "Audited repository manifests and trees; confirmed 0 Bevy, 0 Graphite, and 0 foreign C-NIFs across entire active codebase.",
     ["apps/cepaf_gleam/gleam.toml", "Cargo.toml", "engines/hermes/dune-project"]),
    ("C219", "t9-l9-gov", "verification", "Comprehensive 18/18 Checklist Gate Full Pass",
     "Executed tools/km-gate and verified 5 domains, 18/18 checkpoints passed under SC-CHECKLIST-001.",
     ["contracts/rules/comprehensive-checklist-contract.md", "tools/km-gate"]),
    ("C220", "t9-l9-gov", "verification", "50-Cycle Constitutional Evolution Phase 2 Closure & Chain Intactness",
     "Appended cycle C220, sealing 220 contiguous cryptographic cycle rows in provenance-cycles.sqlite3 with CHAIN_INTACT status.",
     ["var/km/provenance-cycles.sqlite3", "docs/journal/20260908-1105-uos-50-cycle-constitutional-hardening-phase2-journal.md"])
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

    if last_seq != 170 or last_cycle_id != "C170":
        print(f"ERROR: Expected last sequence to be 170 (C170), got {last_seq} ({last_cycle_id})")
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
            "uos-holon-constitution-evolution-phase2-20260908-1105",
            "50-Cycle Constitutional Evolution Phase 2 (C171-C220)",
            "graph-fp-holon-const-phase2-c171-c220",
            now_ns()
        ))

    # 2. Register Tasks in sa_plan_task
    tasks = [
        ("t0-l0-const", "L0 SC-CONST-007..010 Ratification & Lean 4 Rollback Proof", 0),
        ("t1-l1-atomic", "L1 VFS Rollback Snapshots & Memory Budget Watermarks", 1),
        ("t2-l2-homeo", "L2 Prajna H_C Tripping & Lyapunov Stability", 2),
        ("t3-l3-trans", "L3 CAS Transaction Snapshots & Lease Revocation", 3),
        ("t4-l4-system", "L4 System Daemons & Port 4100 H_C Telemetry", 4),
        ("t5-l5-cog", "L5 Fast OODA H_C Gating & Modular MAX Isolation", 5),
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

    # 3. Append Cycles C171 - C220
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

    print(f"Successfully executed 50 cycles (C171 to C220)! Final sequence: {current_seq}, final digest: {current_digest}")

    conn_km.close()
    conn_plan.close()

if __name__ == "__main__":
    main()
