# 20260907-1113-uos-agentic-infrastructure-reuse-and-placement — Agentic infrastructure reuse, placement and validation design

#fractal-l0 #fractal-l3 #fractal-l5 #zk-adr #zero-muda #tailscale-web

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

Created **2026-09-07T11:53:13Z** from the observed host clock. Chrony: system +0.345050 ms, leap Normal, reference time 11:44:10Z. This receipt concerns this host and instant; it does not establish fleet clock synchronization.
Base main: `f01d2531279ce078c5a28ea55550a3399af5ae0a`. Owner: Codex `01a07a68-b3b7-70f3-9e64-fac68a156c21`; review peer: AGY `e7bd3330-0401-4845-8510-78beeaca7b0d`, Herdr `w2:p5`.
Workspace: `/home/an/NAS-setup/uos/.uos-workspaces/codex-ainf-design`.
**Status: design and source review; production NOT_VERIFIED.** This addendum preserves the existing [docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.json](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.json) and its 21 requirements, 63 acceptance cases, 18 invariants and 17 aspects. It adds concrete implementation truth and placement; it does not silently re-ratify the system.

[Machine-readable matrix](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1113-uos-agentic-infrastructure-reuse-and-placement.json) · [Completion journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1113-agentic-infrastructure-reuse-review.md) · [Existing runtime reuse register](http://nas-1.tail55d152.ts.net:4100/files/governance/capability-inventory/20260907-0941-c3i-indrajaal-runtime-reuse.json)

## 1. Operator constraints and scope

The production implementation SHALL use Gleam/OTP and OCaml plus the existing UOS ecosystem. Existing ZigVM, Zenoh, bounded native crypto/storage, and the isolated MAX/Mojo boundary retain their canonical roles. No new foreign control plane is introduced. MirageOS is a deployment form for suitable OCaml code, not a replacement for OTP supervision.

External SPIFFE/SPIRE, OPA/Cedar, Arcade, NeMo, MCP integration products, Consul, NATS, Redis/Dragonfly, Qdrant, Neo4j, Letta, E2B/Firecracker, Temporal, LangGraph, LiteLLM/Portkey, Langfuse/Phoenix, ImmuDB and evaluation tools may inform contracts and serve as quarantined test oracles. No claim of complete API or semantic equivalence is made without a pinned conformance profile. Closed services contribute documented protocol behavior or authorized black-box tests, not presumed source availability.

No external source import, paid OpenRouter request, production deployment or restart was performed in this review. The coordinator journal was appended through its typed CLI; it was not regenerated.

## 2. Execution placement

| Runtime | Authoritative responsibilities | Boundary |
|---|---|---|
| Gleam/OTP | Root/domain supervision, agent lifecycle, workload/caller bindings, policy enforcement, leases, registry, MCP/Zenoh transports, queue bounds, approvals, routing, budget admission, clock collection and SDLC/SRE orchestration | Every effect checks current authorization, scope, candidate and lease at the executor. A model, board message, pane identity or peer review grants no effect authority. |
| Hermes OCaml supervised processes | Transactional evidence/checkpoints, canonical encoding/hashes, retrieval/ranking/graph closure, policy/reference oracles, bounded solvers, replay comparison, evaluation and calibrated forecasting | Blocking storage/network/solver work stays outside BEAM schedulers. OTP owns process lifecycle and deadlines. The store checks persistent fences transactionally. |
| Existing ZigVM | Fuel-bounded deterministic programs, descriptor-relative VFS primitives, virtual timers, local runtime naming and bounded runtime observation | A relative-directory API alone does not establish sandbox confinement. Add explicit traversal/symlink/root/resource policy at the admitted boundary. |
| Existing isolated MAX/Mojo/provider boundary | Real inference and embeddings once actual backend execution is established | Current synthetic Python outputs receive no inference credit. New orchestration remains in Gleam/OTP. |
| Optional MirageOS/Solo5 | Fixed-purpose DNS, ingress filtering, receipt verification or small metrics/forwarding leaf services after separate admission | Real target build, tender boot, network/TLS behavior, resource measurements, readiness and recovery receipts are mandatory. Current host library tests do not satisfy them. |

OTP supervision supplies lifecycle/restart mechanics; distributed recovery and durable workflow semantics need the explicit store/fence protocol below. [Erlang supervision principles](https://www.erlang.org/doc/system/sup_princ.html).

Mirage-compatible libraries cannot simply depend on Unix. Existing SQLite, shell/solver, process-spawning and GPU code therefore require separate host services or deliberate porting, not relabeling as unikernels. MIG-02 generic shell sandbox, MIG-05 ledger and MIG-07 solver are not automatic migration targets. [Mirage build and portability rules](https://mirage.io/docs/mirage-4).

## 3. All 21 capabilities: present code, reuse and remaining validation

“executed” below refers to specific prior slices or bounded observations. It is not a production verdict. “implemented” means substantive source exists; tests not rerun here remain unrun. “mapped” includes interfaces/prototypes without the complete behavior.

| ID / service | Source stage / existing UOS reuse | Owner | Observed limit |
|---|---|---|---|
| AINF-S01 — Workload identity | mapped; [apps/cepaf_gleam/src/cepaf_gleam/iam/supervisor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/iam/supervisor.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/iam/jwks_cache_actor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/iam/jwks_cache_actor.gleam) | Gleam/OTP; OCaml crypto verification service | IAM supervisor exists; several child actors are counters/shells. OIDC decodes payload without signature/audience checks; live SVID/mTLS unverified. |
| AINF-S02 — Dynamic authorization | implemented; [apps/cepaf_gleam/src/cepaf_gleam/auth/rbac.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/auth/rbac.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/rules/engine.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/rules/engine.gleam) | Gleam/OTP; Hermes OCaml policy oracle | Pure role/layer rules exist; resource/action/tenant/context policy and mandatory effect-adapter binding are incomplete. |
| AINF-S03 — Delegated authentication | mapped; [apps/cepaf_gleam/src/cepaf_gleam/auth/token_exchange.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/auth/token_exchange.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/iam/sts_token_cache_actor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/iam/sts_token_cache_actor.gleam) | Gleam/OTP; Existing isolated credential service | Token-exchange codec and STS surfaces exist; complete authenticated OBO exchange, scoped custody and revocation are unverified. |
| AINF-S04 — Secrets and credential leases | mapped; [apps/cepaf_gleam/src/cepaf_gleam/vault.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/vault.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/vault_supervisor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/vault_supervisor.gleam) | Gleam/OTP; Existing supervised crypto/storage boundary | vault.init/unseal/get/destroy/lease_renew are stubbed or return errors. Existing Ferriskey/vault native surfaces are acquisition candidates, not verified brokers. |
| AINF-S05 — Guardrails and tool validation | implemented; [apps/cepaf_gleam/src/cepaf_gleam/vault_pii_scrub.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/vault_pii_scrub.gleam)<br>[engines/hermes/modules/system_engg/agent_dispatch_hook.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/system_engg/agent_dispatch_hook.ml) | Gleam/OTP; Hermes OCaml validation/oracles | Secret-shape scrubber and Hermes NUL/SQL-pattern checks exist. request_guard.check constructs an all-passed grid; this is not observed safety. |
| AINF-S06 — Agent discovery and registry | executed; [apps/uos_swarm/src/uos_swarm/herdr.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/herdr.gleam)<br>[apps/uos_swarm/src/uos_swarm/session_binding.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/session_binding.gleam)<br>[apps/uos_swarm/src/uos_swarm/board_insights.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/board_insights.gleam) | Gleam/OTP; Hermes OCaml history | Actual Herdr discovery and session binding have execution receipts; static capabilities and observed pane identity do not establish authority or continuous health. |
| AINF-S07 — MCP gateway | executed; [apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam) | Gleam/OTP; Hermes OCaml evidence tools | JSON-RPC and stdio/error paths exercised; tool/path authorization, loaded native adapters and Zenoh transport security remain incomplete. |
| AINF-S08 — Message board and event bus | executed; [apps/uos_swarm/src/uos_swarm/board.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/board.gleam)<br>[apps/uos_swarm/src/uos_swarm/board_reader.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/board_reader.gleam)<br>[ops/zenoh/20260907-0450-uos-zenoh-router-1.json5](http://nas-1.tail55d152.ts.net:4100/files/ops/zenoh/20260907-0450-uos-zenoh-router-1.json5) | Gleam/OTP plus existing Zenoh; Hermes OCaml durable inbox/outbox | Existing Zenoh listener and durable board/session observations work; authenticated tenant transport and delivery semantics still need complete evidence. |
| AINF-S09 — Session scratchpad and cache | executed; [apps/uos_swarm/src/uos_swarm/session_sync.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/session_sync.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/substrate/beam_cache.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/substrate/beam_cache.gleam) | Gleam/OTP; Hermes OCaml durable checkpoints | Session journal/leases are exercised; context caches are partial, and cooperative leases do not fence arbitrary same-user commands. |
| AINF-S10 — Semantic retrieval and vector memory | implemented; [engines/hermes/modules/hermes_wiki/src/graph/wiki_similarity.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/src/graph/wiki_similarity.ml)<br>[apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam) | Hermes OCaml; Gleam/OTP query budgets; admitted inference boundary | Wiki TF-IDF/cosine and storage/query seams exist. MAX vectors are SHA-256 pseudo-embeddings; semantic ANN and tenant-aware retrieval are unverified. |
| AINF-S11 — Knowledge graphs and ontologies | implemented; [engines/hermes/modules/hermes_wiki/src/graph/wiki_graph.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/src/graph/wiki_graph.ml)<br>[apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam)<br>[apps/indrajaal_gleam/src/indrajaal/holon.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/indrajaal_gleam/src/indrajaal/holon.gleam) | Hermes OCaml; Gleam/OTP holon lifecycle | Wiki graph and pure ontology/holon structures exist; many catalogs are literal seeds and knowledge actors lose/reset state. |
| AINF-S12 — Context routing and compaction | implemented; [apps/cepaf_gleam/src/cepaf_gleam/ha/context_manager.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/context_manager.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/ha/workflow_compactor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/workflow_compactor.gleam) | Gleam/OTP; Hermes OCaml selection/compaction oracle | Tier and budget functions exist; L1-to-L2 demotion can overflow L2 and cache reads do not implement true LRU. End-to-end tokenizer bounds missing. |
| AINF-S13 — Untrusted execution and sandbox | mapped; [apps/cepaf_gleam/src/cepaf_gleam/harness/hermes_bionic_bridge.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/harness/hermes_bionic_bridge.gleam)<br>[engines/hermes/modules/hermes_dependability/dependability_process.mli](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_dependability/dependability_process.mli)<br>[engines/zigvm/build.zig](http://nas-1.tail55d152.ts.net:4100/files/engines/zigvm/build.zig) | Gleam/OTP controller plus existing ZigVM; Hermes OCaml verifier; optional admitted Mirage leaf | Bounded execution/VFS primitives and host Mirage library tests exist. Process owner prepare is intentionally unavailable; no admitted generic microVM sandbox. |
| AINF-S14 — Durable workflows | executed; [engines/hermes/modules/sa_plan/sa_plan_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/sa_plan_store.ml)<br>[apps/uos_swarm/src/uos_swarm/session_sync.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/session_sync.gleam) | Gleam/OTP; Hermes OCaml transactional store | Sa-plan WAL/inbox/outbox/fencing and session replay are exercised. sa_plan_temporal holds history in memory and cannot guarantee crash-safe external exactly-once effects. |
| AINF-S15 — Human approval | implemented; [apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam)<br>[engines/hermes/modules/sa_plan/guardian.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/guardian.ml) | Gleam/OTP; Hermes OCaml approval receipts | Approval FSM/UI and action-boundary kernels exist; some public approval functions accept untrusted caller IDs. Production executor binding missing. |
| AINF-S16 — Circuit breakers, loops and clocks | executed; [apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam)<br>[apps/uos_swarm/src/uos_swarm/clock_contract.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/clock_contract.gleam) | Gleam/OTP; Hermes OCaml trend analysis; ZigVM virtual timers | Pure breaker/freshness kernels and primary/backup clock observers exist and run. Per-trajectory enforcement and fleet clock provenance are incomplete. |
| AINF-S17 — Model gateway and cost-aware routing | implemented; [apps/uos_swarm/src/uos_swarm/openrouter_worker.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/openrouter_worker.gleam)<br>[apps/uos_swarm/src/uos_swarm/route.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/route.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_provider.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_provider.gleam)<br>[services/inference/max/max_worker.py](http://nas-1.tail55d152.ts.net:4100/files/services/inference/max/max_worker.py) | Gleam/OTP; Existing isolated inference/provider boundary; Hermes quality oracle | Bounded OpenRouter advisory path and routing policy exist; run_routed discards selected tier. MAX inference is synthetic; complete provider failover/cache path unverified. |
| AINF-S18 — Tracing and observability | executed; [apps/cepaf_gleam/src/cepaf_gleam/ha/trace_context.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/trace_context.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/ha/correlated_log.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/correlated_log.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/telemetry/exporter.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/telemetry/exporter.gleam)<br>[apps/cepaf_gleam/src/cepaf_gleam/ui/zenoh_otel.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ui/zenoh_otel.gleam)<br>[apps/uos_swarm/src/uos_swarm/board_insights.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/board_insights.gleam) | Gleam/OTP; Hermes OCaml causal analysis; existing telemetry backend when verified | Structured trace/log and board correlation exercised; exporter seam exists. No local OTLP 4317/4318 listener or backend acceptance established; some ingestion status is literal. |
| AINF-S19 — Atomic budgets and quotas | implemented; [apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam)<br>[apps/uos_swarm/src/uos_swarm/coord.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/coord.gleam)<br>[apps/uos_swarm/src/uos_swarm/route.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/route.gleam) | Gleam/OTP; Hermes OCaml transactional reservations | Per-request/free-only checks exist; route JSONL read-then-append is not atomic, and does not establish fleet spend control. |
| AINF-S20 — Audit and evidence ledger | executed; [engines/hermes/modules/hermes_harness/evidence_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/evidence_store.ml)<br>[engines/hermes/modules/sa_plan/sa_plan_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/sa_plan_store.ml) | Hermes OCaml; Gleam/OTP admitted event producer | SQLite/WAL evidence ingestion and idempotent replay exercised. Zig event_wal.flushLog is a no-op; hash chains alone do not prove tamper immunity. |
| AINF-S21 — Continuous evaluation and red teaming | implemented; [engines/hermes/modules/hermes_harness/test_parity_algebra.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/test_parity_algebra.ml)<br>[engines/hermes/modules/hermes_harness/test_parity_compare.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/test_parity_compare.ml)<br>[apps/cepaf_gleam/src/cepaf_gleam/testing/coverage_math.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/testing/coverage_math.gleam) | Hermes OCaml; Gleam/OTP CI orchestration; existing ZigVM harness | Parity/property/formal infrastructure exists; complete workload-specific trajectory and adversarial acceptance is not demonstrated. |

## 4. Reuse and acquisition decisions

Reuse canonical C3I/Indrajaal adaptations first. The source snapshot receipt explicitly has writers_quiesced=false and content_digest_verified=false; its path/size manifest hash is not a sanitized content snapshot hash. External source trees remain read-only until quiescence, pinned revision, sanitized content provenance, license review, adaptation, tests and two-key admission.

| Source family | High-value reuse | Restrictions |
|---|---|---|
| C3I Gleam/OTP | Pure RBAC/layer rules, real IAM supervisor topology, circuit breaker, context budget/tier kernels, MCP codecs, bounded OTLP exporter, actual transport adapters | Repair JWT verification, resource/tenant policy, stub provider bindings, cache bounds and authenticated effect paths. |
| Existing Ferriskey/vault code | Existing crypto/token/JWKS/STS/realm and storage seams in the current ecosystem | Audit signatures, audiences, schema, custody and failure behavior. Keep blocking DB/network work in supervised isolated processes; no new native control-plane authority. |
| Indrajaal | Holon/ontology vocabulary, UI state projection, actual Mist/Wisp transports and navigation | Static catalogs are seed data; unverified health is unknown. External Panoptic shell auto-restart behavior is not admitted control logic. |
| ZigVM kernel | prim_file, proc/dispatch, timer_wheel, registry, event_log and mcdc_tap | Preserve deterministic/fuel-bounded roles. event_wal.flushLog currently discards inputs and provides no persistence. |
| ZigVM harness OCaml evidence | replay_control / replay_control_laws; journal_bundle_digest, journal_bundle_transaction and journal_bundle_io; vsched; wiki_dep_sheaf; db_writer_lease | Adapt pure algebras/reference tests and bounded durable algorithms. Live scheduling/leases remain OTP-owned, evidence Hermes-owned. |
| ZigVM forecasting/context | Seeded statistical routines may inform Hermes advisory analysis; graph dependency closure can inform context selection | agent_cost_estimator, symbiosis_context_trimmer and ast_mutation_synthesizer are stubs; link-degree ranking is not outcome forecasting. No inference/forecast credit from filenames. |

External ZigVM locations are under `/home/an/dev/ver/zigvm/harness/` and `scripts/`, as read-only source locators. Canonical inert imports actually reside under `engines/hermes/modules/hermes_wiki/import/zigvm/code/`. The reuse skill's references to `engines/hermes/zigvm_legacy` and `docs/hermes/zigvm-overlap-map.md` are stale/absent on main and were not treated as implementation evidence.

Do not import external solver_sandbox.ml unchanged: synchronous stdout/stderr reads precede timeout enforcement, and memory/output/process-group bounds are missing. Do not promote the external MCP server's unbounded blocking stdio/TCP loop. Keep protocol algebra and independent fixtures; use bounded OTP transport.

AGY identified candidate `c660b3d35d5e688c8a987135e3f181acb2adc561`. Comparison with main shows this is an older Mirage candidate; the newer host benchmark and truthfulness corrections are already in main. Its code-presence claims do not establish new S10/S11/S13/S14/S16/S17 production functionality. The paths were inspected: zigvm_add_fractal_engine is a topology catalog, raga_cybernetic_synthesis contains literal music/stability data, max_inference_daemon is a codec/math seam, and tools/uos Mirage gates are not durable workflow execution. AGY acknowledged those scope corrections in op-agy-ack-corrections-1788782792. These sources already exist in main; no new full-service implementation was established by the older candidate.

## 5. Mandatory cross-service contracts

Every command SHALL carry typed tenant, initiating principal, workload identity, delegation reference, task/run/step IDs, tool/schema version, candidate, policy version, lease epoch, idempotency key, action digest, budget reservation and trace context. Credentials are opaque handles outside model context. Every observation carries provenance, UTC plus uncertainty/source, local monotonic time plus host/boot identity, and Lamport clock. Lamport time is not converted into a wall-clock offset.

Execution proceeds through typed proposal, authorization, budget reservation, durable intent/outbox, dispatch, observation and durable completion or reconciliation. Missing evidence fails closed. Required state changes and outbox publication are transactional. A single fenced Hermes service owns the local SQLite authority; remote workers use its bounded API, not a shared network-filesystem WAL. The durable-commit profile SHALL verify WAL mode, synchronous=FULL (or a documented stronger supported profile), successful commit/sync and the actual filesystem/storage guarantees. Checkpointing is separate maintenance; PRAGMA wal_checkpoint(PASSIVE) alone does not prove commit durability. [SQLite durability settings](https://www.sqlite.org/pragma.html#pragma_synchronous), [SQLite WAL constraints](https://www.sqlite.org/wal.html). Ambiguous external outcomes retain their reservation and enter reconciliation; they are not blindly retried.

Approvals are single-use, expiring and bound to approver authority, tenant, original action digest/arguments, candidate, policy and spend ceiling. A valid approval cannot override constitutional denials. Cancellation and policy/lease changes are rechecked before dispatch.

Spend uses integer smallest accounting units with explicit price version and uncertainty. A single transactional authority enforces spent + reserved <= cap across every authorized dispatcher. A local OTP mailbox or read-then-append JSONL ledger alone does not establish fleet atomicity. After crashes or provider timeouts, reserve liability until settlement is known.

Retrieval and semantic-cache keys include tenant, principal/authorization epoch, corpus and embedding/model version, policy and prompt/schema versions as applicable. Retrieved text and summaries remain untrusted data with source references. Compaction preserves pinned policy, task constraints and unresolved tool pairs; overflow denies admission rather than silently dropping them.

Decision records contain purpose, evidence, alternatives considered, selected action, constraints, uncertainty, predicted outcomes, verification plan and observed result. They contain reviewable summaries, not private chain-of-thought, secrets or unsubstantiated consciousness scores. Forecasts remain advisory and are evaluated with calibration/error metrics on observed outcomes.

SPIFFE-compatible workload identity requires actual credential/trust-bundle lifecycle and workload attestation; a session ID is not a substitute. [SPIFFE SVID lifecycle](https://spiffe.io/docs/latest/deploying/svids/). Delegation follows an explicit token-exchange/audience profile; token passthrough is forbidden by MCP security guidance. [OAuth token exchange](https://www.rfc-editor.org/rfc/rfc8693.html), [MCP security](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices).

Durability requires recorded nondeterministic inputs/results and effect idempotency or reconciliation. Temporal itself can retry activities after worker loss/timeouts, so its behavior must not be modeled as unconditional exactly-once external effects. [Temporal activity execution](https://docs.temporal.io/activity-execution).

## 6. Service acceptance and external-oracle use

Each row extends the three baseline AINF-Txx tests. Every test needs a candidate, invoked executable/toolchain, configuration/fixture digest, seed/bounds, exit status, independent oracle and preserved counterexample. Current acceptance status for the composed target is UNRUN.

| Service | Required focused acceptance |
|---|---|
| AINF-S01 | Reject forged signatures, wrong audience/issuer, expired or revoked identity and cross-workload credential reuse; exercise rotation under load. |
| AINF-S02 | Deny by default; prove effective rights are the intersection of user, agent, tenant and tool constraints; test policy changes during a queued action. |
| AINF-S03 | Exchange only for an authenticated principal and specific audience; reject confused-deputy, stale consent, scope escalation and token passthrough. |
| AINF-S04 | Verify issue/use/rotate/revoke/expire with real broker; search controlled outputs for canary secrets; deny use after lease expiry and on missing binding. |
| AINF-S05 | Use real schema/size/path/tenant checks and parameterized storage; test indirect injection, malformed payloads, missing evidence and redaction failures. |
| AINF-S06 | Replace/expire/restart peers; reject stale identity or capability receipts; prove discovery cannot grant a lease or authorize an effect. |
| AINF-S07 | Exercise actual clients, notifications, request IDs, bounded frames, tenant auth, replay, deadlines and unavailable adapters; refuse arbitrary path or unauthorized plan mutation. |
| AINF-S08 | Inject duplicates, reorder, loss, missing parents and reconnects; enforce tenant ACLs; prove idempotent consumption and bounded retry/dead-letter behavior. |
| AINF-S09 | Concurrent tenant isolation, bounded bytes/items/TTL and restart tests; keep approvals, quotas and effect completion outside volatile cache authority. |
| AINF-S10 | Compare ranking/filtering to independent golden fixtures; enforce ACLs before retrieval/reranking; test stale/deleted records, embedding/model version and recall/latency bounds. |
| AINF-S11 | Verify bounded closure, provenance, incremental updates, conflicting claims, tenant filtering and that graph conclusions never authorize effects. |
| AINF-S12 | Preserve pinned policy/constraints, unresolved tool pairs and provenance; enforce actual selected-model token budget after every demotion and compaction; fail if protected context cannot fit. |
| AINF-S13 | Adversarial traversal/symlink/network/CPU/RAM/output/fork tests, cancellation and uncertain-outcome recovery on real target; prove denied storage serial cannot be touched. |
| AINF-S14 | Crash before/after dispatch and receipt commit; recover durable intent; reuse idempotency keys or reconcile unknown effects; exercise timers, cancellation and explicit compensation. |
| AINF-S15 | Bind approver/tenant/action digest/candidate/policy/budget/expiry/nonce; reject tampering, replay, delayed approval after cancellation and unauthorized approvers. |
| AINF-S16 | Trip on budgets, repeated no-progress and deadlines; limit half-open probes; test wall jumps, reboot epochs, stale peers and Lamport receive=max(local,remote)+1. |
| AINF-S17 | Bind selected provider/model to dispatch; reserve before request, reconcile ambiguous result, test fallback/cancellation/cache ACL keys; verify real inference and measured model quality. |
| AINF-S18 | Send a known span through the real collector to queryable backend; prove context propagation, redaction, bounded buffering/drop counters and no control authority from logs. |
| AINF-S19 | Concurrent reservation/settlement/release must preserve spent+reserved<=cap; retain liability after timeout, reject negative charges and persist across crash/failover. |
| AINF-S20 | Commit canonical events durably; verify continuity, deletion/reordering/corruption, crash recovery, retention and independently anchored checkpoints; record summaries, not private reasoning/secrets. |
| AINF-S21 | Use held-out tasks, negative controls, semantic mutants, tool-side-effect checks and calibrated judges; bind all results to candidate, fixtures, models, seed and toolchain. |

Reference-oracle profiles SHALL be narrow and explicit:
- Identity/delegation: SPIFFE SVID and OAuth/MCP positive/negative protocol vectors; valid signatures, wrong audiences, expiry, rotation and revocation.
- Policy/guardrails: OPA/Cedar truth tables for the declared supported policy subset; adversarial fixtures and schema/redaction cases. Full Rego/Cedar compatibility is not implied.
- Messaging/cache/workflows: NATS/Redis/Temporal traces for defined ordering, TTL, retry, cancellation and crash cases, compared to independent UOS state machines.
- Retrieval/graph/compaction: Qdrant/Neo4j/Letta fixtures for specified filters, closure and memory behavior. Use an independent exact-search oracle before ANN optimizations; define recall and tenant leakage separately.
- Sandbox/Mirage: behavior observed on actual admitted targets; E2B/Firecracker observations may benchmark controls but cannot prove UOS isolation.
- Routing/telemetry/audit/evaluation: provider usage fixtures, OTLP roundtrips, hash/tamper controls and held-out agent trajectories. LLM judges and forecasts report uncertainty and cannot independently admit a service.

Vendor oracle binaries/source stay quarantined outside final runtime dependencies. Record source/license/revision and sanitize fixtures; do not copy secrets, live databases or model weights. No new oracle service was downloaded or run for this source-review slice.

## 7. Formal design across the canonical 17 aspects

Use Lean for invariant proofs; Quint for bounded concurrent state transitions and fairness/liveness assumptions; Gospel for OCaml interface contracts; isolated bounded SMT for decidable constraints; independent executable oracles for semantic equivalence. These methods address different properties. Compilation, a passing unit test or peer opinion does not discharge all of them. Existing carriers include [formal/lean/AgenticCoordination.lean](http://nas-1.tail55d152.ts.net:4100/files/formal/lean/AgenticCoordination.lean), [formal/lean/AgenticJournal.lean](http://nas-1.tail55d152.ts.net:4100/files/formal/lean/AgenticJournal.lean), [formal/lean/TwoLattice_STM.lean](http://nas-1.tail55d152.ts.net:4100/files/formal/lean/TwoLattice_STM.lean), [formal/lean/Traceability.lean](http://nas-1.tail55d152.ts.net:4100/files/formal/lean/Traceability.lean), [formal/quint/agentic_coordination.qnt](http://nas-1.tail55d152.ts.net:4100/files/formal/quint/agentic_coordination.qnt), [formal/quint/agentic_journal.qnt](http://nas-1.tail55d152.ts.net:4100/files/formal/quint/agentic_journal.qnt).

Required refinements include authorization intersection, persistent single-owner fencing, transactional budget conservation, approval nonce/digest binding, tenant non-interference, crash recovery, protected context conservation and distinct clock domains. Model bounds, fairness assumptions and source-to-model abstraction maps SHALL be explicit. Missing tools, timeout, stale receipts, unsupported syntax, sorry/Admitted/undeclared axioms remain nonpassing.

| Aspect | Gate / obligation | Current composed validation |
|---|---|---|
| AINF-A01 — Substrate & Hardware Storage Interlock | G-DRIVE-NVME: Reject the denied OS serial and prove filesystem/resource isolation at the service's execution and storage dependencies. | Runtime UNRUN; formal UNRUN |
| AINF-A02 — Standalone Jujutsu Monorepo Discipline | G-BOOT1-JJ: Bind code, schemas, policy, model and fixtures to a standalone JJ candidate plus source digests; serialize integration. | Runtime UNRUN; formal UNRUN |
| AINF-A03 — Zero-Muda Purity & Waste Elimination | G-ZERO-MUDA: Reuse admitted UOS carriers; scan dependencies and dispatch plans for barred engines and forbidden language placement. | Runtime UNRUN; formal UNRUN |
| AINF-A04 — Gleam/OTP 29 4-Domain Root Supervisor | G-OTP29-SUPER: Show the real service actor in a live domain tree; exercise restart tolerance, fencing, bounded queues and shutdown. | Runtime UNRUN; formal UNRUN |
| AINF-A05 — ZigVM Deterministic Engine & 8 VFS Laws | G-VFS-8LAWS: Trace deterministic work and file access to an admitted ZigVM/VFS boundary; demonstrate confinement or the explicit delegated boundary. | Runtime UNRUN; formal UNRUN |
| AINF-A06 — Hermes Formal Evidence, Gospel & Z3 | G-HERMES-EVID: Provide a typed contract, independent oracle and fresh bounded verifier receipt for the service revision. | Runtime UNRUN; formal UNRUN |
| AINF-A07 — Mathematical Authority & Conservation | G-LEAN4-MATH: Prove relevant authorization, budget, trace-coordinate and lease laws; establish projection equivalence without undeclared axioms. | Runtime UNRUN; formal UNRUN |
| AINF-A08 — Biosemiotic Cybernetics & Rocha Cut | G-ROCHA-SEMIOT: Show that proposals, retrieved text, model outputs and Rete facts cannot directly create dispatch authority. | Runtime UNRUN; formal UNRUN |
| AINF-A09 — Quarantined Modular MAX/Mojo Inference | G-MAX-INFER: Route any inference through an admitted isolated boundary; non-inference services prove no hidden inference or Python dispatch. | Runtime UNRUN; formal UNRUN |
| AINF-A10 — Zenoh OoZ & MoZ Mesh Telemetry Backplane | G-ZENOH-MESH: Test tenant namespace ACLs, authenticated routing, loss/retry/duplicate handling and observation/control separation. | Runtime UNRUN; formal UNRUN |
| AINF-A11 — AG-UI 32-Event SSE Stream Protocol | G-AGUI-32EVENT: Expose sanitized typed service events with authenticated subscription, bounded buffering and sequence-aware reconnection. | Runtime UNRUN; formal UNRUN |
| AINF-A12 — A2UI 233-Component Declarative Catalog | G-A2UI-CATALOG: Render typed catalog projections of capability, health, approval and evidence; no arbitrary model HTML or executable markup. | Runtime UNRUN; formal UNRUN |
| AINF-A13 — Penta-Stack Multi-Interface Accessibility | G-PENTA-STACK: Prove consistent authorized meaning across Lustre Web, Wisp API, ANSI TUI, AG-UI SSE and MoZ/Zenoh surfaces. | Runtime UNRUN; formal UNRUN |
| AINF-A14 — Universal Tailscale FQDN Web Navigation | G-TAILSCALE-WEB: Verify full FQDN discovery/docs/evidence links and authenticated navigation; Tailnet location alone is not authorization. | Runtime UNRUN; formal UNRUN |
| AINF-A15 — Comprehensive Verification Checklist | G-CHECKLIST: Render the 5-domain/18-checkpoint structure with current scoped receipts, truthful UNRUN states and uniform navigation. | Runtime UNRUN; formal UNRUN |
| AINF-A16 — Knowledge Management Triad (Wiki/ZK/Ont) | G-KM-TRIAD: Link the requirement, implementation, formal contract, scenario, evidence, wiki, ADR and ontology without dropping tenant ACLs. | Runtime UNRUN; formal UNRUN |
| AINF-A17 — Sa-Plan & Bionic Durable Workflows | G-SAPLAN-BIONIC: Track work and runtime steps through persistent leases, idempotency, cancellation, compensation and tested crash recovery. | Runtime UNRUN; formal UNRUN |

The machine artifact explicitly enumerates all **21 × 17 = 357** service/aspect cells. Each has runtime/formal UNRUN and no receipt until evidence is attached. Inapplicability needs an explicit, reviewed dependency-boundary justification, not a blanket pass. Prior passing slice receipts remain separately linked.

## 8. Implementation order and operational recovery

1. Repair trust boundaries: real JWT verification, bounded native/worker seams, explicit unknown states, required per-tool/resource authorization.
2. Populate and observe the OTP domain tree on the required OTP 29 runtime; preserve existing running services during deployment preparation. The prior runtime observation was OTP 27 and the inspected root entrypoint starts no children; the latest replacement web process has not been version-verified.
3. Complete durable store/fence/outbox/approval protocols; remove reliance on the no-op Zig WAL and in-memory Temporal-style wrapper.
4. Implement transactional reserve/settle/reconcile and bind chosen model/provider to actual dispatch; exercise actual inference with measured usage.
5. Harden registry/MCP/Zenoh/cache/context/knowledge paths and prove tenant isolation.
6. Establish end-to-end telemetry delivery and benchmark/evaluation admission, then select one small Mirage leaf based on measured need.

Every runtime rollout uses separately owned runtime:<service>, candidate-bound approval where required, backup readiness, drain/handoff, rollback criteria and fresh post-change observations. Primary/backup processes alone do not prove replication, partition fencing or seamless traffic transfer. Hot loading requires versioned state migration and bounded rollback evidence.

## 9. Evidence, peer review and limitations

Runtime inventory at 2026-09-07T11:46:02Z: main `f01d2531279c`; relevant inspected core sources match main; default workspace is behind it and was not rebased. Clock primary/backup active, PIDs 2678887/2670150, NRestarts=0. BEAM port 4100 PID2925584 and Zenoh8080 PID1689715 listened. No local 4317/4318 collector listener was found. Recheck at 12:07:04Z found web PID2959677 instead; Zenoh and both clock PIDs were unchanged with zero clock restarts. This review performed no service restart, and it does not infer the replacement process's version or deployment cause. Existing specification, reuse register and Mirage status endpoints returned HTTP200; this proves reachability only.

Prior [docs/journal/20260907-0941-c3i-indrajaal-reuse-implementation-journal.md](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-0941-c3i-indrajaal-reuse-implementation-journal.md) records actual coordination replay/WAL ingestion and MCP/board/log slices. Prior [docs/reviews/20260907-1150-mirage-sovereign-audit-receipt.json](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260907-1150-mirage-sovereign-audit-receipt.json) records host Mirage tests and explicit absence of Solo5 admission. Those tests were not rerun here and are not promoted to new composed-runtime evidence.

Actual AGY responses arrived via the durable coordinator from the discovered session: op-agy-send-ainf-1788781977 (initial review), op-agy-ack-c660-1788782177 (ledger/scope refinement), op-agy-ack-draft-1788782587 (actual 21-row/17-aspect draft review), and op-agy-ack-corrections-1788782792 (source-scope corrections). AGY accepts the placement and flags OTP29 wiring, transactional budgets, VFS traversal fencing and Mirage leaf confinement. Those obligations are retained explicitly.

The peer acceptance artifact was located and read at `/home/an/.gemini/antigravity-cli/brain/e7bd3330-0401-4845-8510-78beeaca7b0d/20260907-1355-uos-ainf-21-service-acceptance-suite.md`. It remains read-only evidence outside this package. Its all-green checklist, unsupported tri-sovereign consensus, stale test counts, misclassified retrieval/workflow claims and passive-checkpoint durability claim are rejected as verification credit. Later coordinator corrections supersede those claims for this design. Claude did not review this design in this slice. Neither the peer artifact nor a model ACK grants admission.

Document structural validation checks 21 unique services, 17 canonical aspects, all 357 unique service/aspect cells, baseline requirement/test references, current source paths, journal section order and 18-checkpoint structure. These checks validate the document package only. All 21 production verdicts remain NOT_VERIFIED.

## 10. Comprehensive verification checklist

The unchecked state below records production obligations conservatively; document metadata checks are described in the text and machine structure receipt.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] CHK-01-TIME — Observed host UTC and chrony receipt recorded.
- [ ] CHK-02-TAIL — Full Tailscale FQDN links; new workspace artifact serving remains pending integration.
- [ ] CHK-03-FRACT — Fractal and knowledge tags present.
- [ ] CHK-04-KM — Baseline specification, register, review and journal linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] CHK-05-MUDA — Final runtime constrained to admitted UOS ecosystem; full dependency gate UNRUN.
- [ ] CHK-06-GRAPH — Graph computations assigned to pure Gleam/Hermes; production gate UNRUN.
- [ ] CHK-07-DRIVE — No drive mutations; actual denied-serial production interlock UNRUN.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Design review does not establish UI acceptance; UNRUN.
- [ ] CHK-09-MATH — No invented information/quality metrics; mathematical thresholds UNRUN.
- [ ] CHK-10-9MOD — All nine production test modalities remain UNRUN for this design.
- [ ] CHK-11-REGR — Documentation structural checks only; production regression gate UNRUN.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Root wiring/OTP 29/restart evidence remains open.
- [ ] CHK-13-HERMES — Existing evidence store identified; new composed formal/runtime gate UNRUN.
- [ ] CHK-14-ZIGVM — Existing kernel retained; sandbox boundary gate UNRUN.
- [ ] CHK-15-MAX — Synthetic worker is not verified inference; UNRUN.
- [ ] CHK-16-OTEL — Log correlation exists; collector/backend acceptance UNRUN.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Actual AGY design review and corrections received; no production admission.
- [ ] CHK-18-JJ — Isolated standalone JJ workspace; no native Git commands or main move.

</details>

**Previous:** [docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md) · **Next:** [docs/journal/20260907-1113-agentic-infrastructure-reuse-review.md](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1113-agentic-infrastructure-reuse-review.md)

**UOS footer:** Reuse-first design; revision-bound evidence and two-key admission required. Workspace document links become available through canonical serving after integration; no mainline publication claimed.
