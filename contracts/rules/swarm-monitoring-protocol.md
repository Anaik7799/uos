# Swarm Monitoring & Information Sharing Protocol (SC-MONITOR-001)

Per `contracts/rules/20260908-0935-swarm-monitoring-and-information-sharing-protocol.md`:

1. **5-Minute Monitoring Rhythm**: All monitoring agents (AGY, Claude, Codex, OpenRouter) must poll the coordinator message board (`session_sync_cli`) and inspect Zenoh channels every 5 minutes.
2. **Inbound Zero-Backlog Law (INV-MON-02)**: Every inbound message must be acknowledged with `session_sync_cli ack` within the monitoring cycle. Unacknowledged backlog must remain 0.
3. **Dynamic Homeostasis Invariant (INV-MON-01)**: System homeostasis must never be compromised.
   - Setpoint tracking error $|e(t)| < 0.05$.
   - Convergence ratio $\ge 95.0\%$.
   - Lyapunov energy $V(e) \le 0.001$, $\dot{V} \le 0$.
   - Prior to claiming tasks or applying mutations, verify `/api/v1/homeostasis`. If violated, trigger an immediate Andon Stop Line (`SC-JIDOKA-001`) and focus exclusively on stabilization.
4. **Dual-Plane Information Sharing**:
   - Plane 1: Durable SQLite Coordinator Store (`var/coordination/tri-agent/events.sqlite3` via `session_sync_cli`).
   - Plane 2: Zenoh Pub/Sub Mesh (`indrajaal/l2/health/homeostasis`, `indrajaal/l0/const/monitoring_protocol`, `c3i/a2a/*`).
5. **Cost-Minimal Task Forking**:
   - Decompose tasks into bounded analytical/advisory slices.
   - Delegate to OpenRouter Free tier (`google/gemma-4-31b-it:free`, `nvidia/nemotron-3.5-lightning:free`) or micro-cost models (`gemini-2.5-flash-lite`, `gpt-4.1-nano` with $\le 512$ tokens, $\le \$0.02$ budget ceiling per `SYNC-09`).
   - Synthesis and formal verification remain local under two-key evidence.
6. **Provenance & Admitted EV Ceiling**:
   - Admitted EV ceiling pinned to `EV-93` (`SC-PROVENANCE-001`). No unvetted cycles minted.
