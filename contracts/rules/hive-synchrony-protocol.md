# Hive Synchrony & Harmonic Resonance Protocol (SC-HIVE-SYNC-001)

Per `contracts/rules/20260908-0945-hive-synchrony-and-harmonic-protocols.md`:

1. **The Singing Hive Invariant**: The swarm operates as a biomorphic orchestra governed by mathematical resonance, dynamic homeostasis, and stateful workflow tracking.
2. **The 8 Canonical Protocols**:
   - **Tanpura Drone**: Setpoint $y_{\text{ref}} = 1.0$, $|e(t)| < 0.05$, $V(e) \le 0.001$, $\dot{V} \le 0$. Continuous equilibrium that never ceases.
   - **Tala Rhythm**: Work managed strictly via Oban jobs (`sa-plan job`) and Temporal workflows (`sa-plan workflow`). Non-durable cron / sleep loops barred.
   - **Shruti Synthesis**: 3-of-4 Byzantine Quorum (`AGY ⊕ Claude ⊕ Codex ⊕ OpenRouter`) achieving harmonic consensus ($E = 1680.0$).
   - **Meend Morphing**: Logistic S-curve transitions ensuring continuous, non-chaotic evolutionary changes.
   - **Bayan Pulse**: Heartbeat decay and dead-man freshness on Zenoh and coordinator store.
   - **Jawari Overtones**: Dual-plane coupling of SQLite durable events with Zenoh real-time pub/sub mesh.
   - **Shannon Diversity**: Spectral entropy $H \ge 2.50\text{ bits}$ preventing monoculture stagnation.
   - **Jidoka Silencer**: Immediate fail-closed stop line on un-ledgered actions (`SC-JIDOKA-001`, code `-32002`).
3. **Job & Workflow Execution**:
   - Monitoring runs via `sa-plan job enqueue / claim / complete` in queue `hive-monitoring`.
   - Multi-agent sync runs via `sa-plan workflow start / activity / complete`.
4. **Admitted EV Ceiling**: Pinned at `EV-93` per `SC-PROVENANCE-001`.
