| domain | id | control | enforcement | status |
|---|---|---|---|---|
| operational | OP-1 | Zenoh router systemd user unit | `ops/zenoh/20260907-0450-c3i-zenoh-router-1.service` | PRESENT |
| operational | OP-2 | Router reachable (REST) | `system_audit.probe` | UP |
| operational | OP-3 | Retry + dead-letter | `board.retry_undelivered (max 5)` | ENFORCED |
| operational | OP-4 | Heartbeat freshness + retirement | `coord.stale / coord.retire` | ENFORCED |
| operational | OP-5 | Jidoka / andon | `manager.step + tps.jidoka` | ENFORCED |
| security | SEC-1 | Hierarchical authority | `coord.authorize (kinds per layer)` | ENFORCED |
| security | SEC-2 | Design authority fable-only | `coord.authorize design_kinds` | ENFORCED |
| security | SEC-3 | Intent never executed (Rocha cut) | `coord.authorize + manager (no side effects)` | ENFORCED |
| security | SEC-4 | Capability default-deny | `agent_runtime.allowed` | ENFORCED |
| security | SEC-5 | Memory isolation per agent | `agent_runtime.remember/recall` | ENFORCED |
| security | SEC-6 | Per-sender SHA-256 chains | `board.validate` | ENFORCED |
| security | SEC-7 | Fenced single-writer leases | `coord.acquire/renew (epochs)` | ENFORCED |
| security | SEC-8 | Zero-trust dispatch interceptor (Hermes) | `engines/hermes/_build/default/modules/system_engg/run_agent_dispatch_hook.exe` | BINARY PRESENT |
| security | SEC-9 | Signed envelopes (HMAC-SHA256, key outside repo) | `board.sign / board.signature_ok` | ENFORCED |
| security | SEC-10 | Policy on absorbed messages | `coord.reconcile authorize_message` | ENFORCED |
| security | SEC-11 | ETS tables protected (owner-write) | `uos_tui_ffi.erl ets_open` | ENFORCED |
| observability | OBS-1 | W3C trace/span on every message | `telemetry + board.seal` | ENFORCED |
| observability | OBS-2 | Delivery record per transport | `board.deliver` | ENFORCED |
| observability | OBS-3 | Shared state on Zenoh | `coord.share_state uos/tui/state/*` | LIVE |
| observability | OBS-4 | System-wide 17-aspect audit | `system_audit.all_subjects` | ENFORCED |
| observability | OBS-5 | Usage accounting per agent and global | `coord.record_usage` | ENFORCED |
| formal | FRM-1 | Lean 4 proofs bound | `formal/lean/Traceability.lean,formal/lean/TwoLattice_STM.lean` | PRESENT |
| formal | FRM-2 | Quint model bound | `formal/quint/parity_frontier.qnt` | PRESENT |
| formal | FRM-3 | MAX daemon quarantined | `services/inference/max/max_worker.py` | PRESENT |
controls_ok=true
