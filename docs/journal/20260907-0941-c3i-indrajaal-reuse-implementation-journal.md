# C3I and Indrajaal reuse — implementation and evidence journal

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #zk-adr #zero-muda #tailscale-web

**Created:** 2026-09-07T09:26:41Z. **Updated:** 2026-09-07T10:25:59Z. **Status:** development implementation with two live read-only observers; production admission is outstanding.

[UOS cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

[Rendered/source document](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-0941-c3i-indrajaal-reuse-implementation-journal.md) · [Machine reuse register](http://nas-1.tail55d152.ts.net:4100/files/governance/capability-inventory/20260907-0941-c3i-indrajaal-runtime-reuse.json). Both links returned HTTP 200 with matching document/register content after mainline integration on 2026-09-07; updated content is verified again after the final handoff.

## 1. Scope & Trigger

The operator repeatedly directed maximum reuse of C3I and Indrajaal infrastructure for the UOS hive, parallel SDLC/SRE, clocks, message-board insights, forecasting, and continuous evolution. This implementation uses the existing UOS carriers identified in the [17-aspect formal specification](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md). The machine register maps all 21 infrastructure services; it records source locations, execution evidence, candidates, and remaining bindings.

The intended result is one coordinated system using existing services. A service declaration, module name, test fixture, or successful board delivery does not establish a live production capability.

## 2. Pre-State Assessment

Mainline at the recorded observation was a55c81fc62201184761a7ee3776c7bafa9c4331a. Its preserved ancestry includes C01 session durability, C02 Hermes ingestion, C03 live Herdr binding, C07 formal journal models, and the clock-contract/board-insights candidates. Claude retains integration ownership. The default workspace and external trees are shared and may advance independently.

NAS had the Indrajaal cockpit listening on 4100 and the existing Zenoh router on 8080. Neither NAS nor the previously inspected VM-1 service inventory established an OTLP collector. Fresh NAS curl and Erlang socket probes returned connection refusal on 4318. The obsolete c3i-zenoh-router.service was repeatedly failing, while the separate c3i-zenoh-router-1 container served traffic. Its observed restart count was 42,897; the incident was sent to Claude without stopping the live router.

A fresh isolated invocation of the existing uos_sup.start_root_supervisor returned a running supervisor with **children []**. The four-domain topology exists as a specification, but this entry point does not instantiate it.

## 3. Execution Detail

| Concern | Existing carrier retained | Small implementation delta |
|---|---|---|
| Discovery and coordination | Herdr, UOS board, session_sync | Bound actual pane/session observations; durable task/resource epochs; bounded board reader and report |
| Messaging | Existing C3I Zenoh service on 8080 | Read-only bounded fresh projection; no new message broker |
| Durable work/evidence | Hermes Sa-Plan WAL and journal algebra | Typed Gleam observation export and native OCaml ingestion |
| Telemetry | C3I trace_context, correlated_log, exporter and Zenoh OTel modules | Correct trace IDs/timestamps/topics, propagate errors, join board and log evidence |
| MCP | Existing C3I MCP dispatcher and tool schemas | Remove unbound advertisements, stop manufactured success, validate runtime availability |
| Runtime evolution | C3I OTP release/hot-loading patterns and UOS leases | Typed readiness, candidate/digest checks, warm backup, drain/handoff/rollback model |
| Clock monitoring | Existing host chrony and UOS clock contract | Bounded supervised Gleam observers, per-instance persistent Lamport floors |
| Presentation | Existing Indrajaal cockpit and C3I Wisp router | Reuse existing views/routes; no independent dashboard stack |
| Memory and prediction | C3I context_manager, token_budget, workflow_compactor, forecasting_engine, capacity_forecast | Reuse candidates mapped; full prediction and policy integration remains outstanding |

The native end-to-end check exported **57 real coordination journal events**, independently recomputed all 57 payload hashes in Hermes, ingested them into a temporary WAL store, and reopened it for replay. The first event retained Hermes sequence 1 with replayed=true. Delivering sequence 2 to an empty store produced reconciliation_required/sequence_gap and exit 2. No observation completed a task or authorized a deployment.

Board reporting consumed the real local ledger and a structured-log sample produced with the corrected C3I tracing code. It found the exact message/trace association for message 1788772514555609-5ec49e2541504f39 and trace d47e9aa1b2be007c78ad11a1e509f46e. It deduplicated 205 repeated rows, rejected no malformed rows in that capture, retained the historical missing-parent diagnostic, and did not infer collector/backend success.

## 4. Root Cause Analysis

Several operational gaps were hidden by declarative or fallback behavior. MCP handlers manufactured successful gate/bridge outcomes; an unavailable native module supplied zero counts; the HTTP catalog and telemetry status contained literal values. The parent MCP correction passed its focused tests, but an independent runtime probe found the native-fallback and I/O-error cases. Those findings produced a separate corrective child instead of expanding the meaning of the earlier test receipt.

The first clock persistence adapter attempted to open a directory without Erlang's directory flag. On this host it returned eisdir, which the adapter swallowed. The correction opens [read,raw,directory] and propagates open, sync, and close errors. Clock monitoring also needs fresh current state while limiting repeated diagnostic history; coalescing must not make an observer appear fresh using an old timestamp.

## 5. Fix Taxonomy

These are adapter, authority-boundary, observability, and durability fixes over existing carriers. Existing behavior is reused where its contract and observed result agree. A reused component with a failed probe stays nonpassing.

External C3I/Indrajaal sources remain read-only evidence. The [source receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260907-0604-vm1-c3i-indrajaal-sanitized-snapshot-receipt.json) records active writers and a path/size manifest, not a verified content snapshot. This change imports no external files, secrets, live databases, caches, or model weights.

## 6. Patterns & Anti-Patterns Discovered

- Reuse service ownership and data contracts as well as code. A second broker, workflow database, or dashboard would duplicate existing UOS responsibilities.
- Preserve candidate ancestry and independent evidence. Integration does not upgrade a development candidate to admitted.
- Compare explicit message and trace identifiers; a shared trace is an association, not proof that an action succeeded.
- Distinguish wall time, boot-monotonic time, Lamport counters, source-reference age, and observation age.
- Keep unknown values explicit. Missing heartbeats, missing native bindings, and an absent collector are not zero activity.
- Keep current health fresh while coalescing repeated diagnostic history. Silence is not a positive health receipt.

## 7. Verification Matrix

| Check | Observed result | Boundary |
|---|---|---|
| 21-service reuse-register paths | All referenced paths exist | Inventory only |
| C02 Gleam/Hermes canonical hashes | 57/57 equal | Captured journal and pinned candidate pair |
| C02 WAL ingest and replay | 57 accepted; replay reused sequence | Temporary store, no production task mutation |
| C02 sequence gap | Reconciliation and exit 2 | Negative control |
| Board/log correlation | One explicit message+trace match | Structured log only |
| Telemetry repair | 88 focused tests passed | Collector/backend delivery still unproved |
| MCP parent | Four focused tests passed | Independent review found additional runtime gaps |
| MCP runtime corrective child | Nine focused tests passed | Missing-NIF path exercised; loaded-NIF path unavailable |
| MCP final integration at be5c2c70 | 29 focused tests passed; full suite 10,003 passed | Same 164 distinct failing test identities as baseline; zero new failures; native positive path UNRUN |
| Clock provenance adapter f0a9d7e6 | 505 swarm tests and build passed; real Zenoh/chrony canary executed | Foreign and missing provenance remain UNKNOWN; no remote NTP receipt |
| Live evolution merged at 94ed6c2e | 519 swarm tests passed on the composed clock tree | Development readiness/handoff model; full traffic handoff unbound |
| C04/C05 and KPI integration repair d6557335 | Reproduced exactly three failures; 557 tests passed after fixture correction | Real canonical workspace fixture; production fences unchanged |
| Telemetry route follow-on 8180c736 | Build/check and three compiled focused route tests passed | Static protocol identity restored; unobserved metrics stay null |
| Strict board-validation child e0b50cdc | 38 focused tests; real missing/malformed inputs exit 1 | Explicit empty-file status conveys no hive health |
| Clock persistence | Real directory-sync probe corrected | Power-loss behavior is not proved by this probe |
| Existing root supervisor | Started with zero children | Live construction gap confirmed |

Test counts belong to their respective candidate packages and are not additive system coverage.

## 8. Files Modified

This journal, the timestamped machine reuse register, and ops/observability/20260907-0941-uos-clock-guard@.service are the delta in codex-reuse-ops. Component implementation is isolated in the referenced JJ candidates. An in-progress child must not replace a frozen parent receipt silently.

The clock rollout uses candidate **98936f9e961e5b909c0e8445123b705aedb669a5**, exported once into UOS var/releases and checked against manifest SHA-256 **83e9915a41781efd1d1b4890b1869833d337827286a1357e9c198e0b45f57f99**. The unit validates this manifest at startup. Both units were enabled and started under the explicit operator instruction and current runtime:uos-clock-observers cooperative lease epoch 1. The action/rollback receipt is private runtime data at var/operations/20260907-0941-clock-observers-start.json.

At 09:44:18Z, primary PID **2600550** and backup PID **2600547** were active with zero restarts. Each had its own mode-0600 floor at 215. Both reported fresh chrony observations (offset 1225 microseconds; uncertainty 20174 microseconds). Both remained unhealthy because board-domain evidence is not verified. The old cockpit PID 4060345 and router PID 1689715 were unchanged. These are independent clock observers, not a completed failover deployment of the entire UOS application.

The subsequent clock-provenance rollout uses **f0a9d7e6732c6b8a3722f75797a35e5dc1a4efd8**, integrated by Claude at **d916ac66528f9fb6884344934b96a207fbecffa4**. The pinned release manifest is **0b14fb665dfc5e7360f216c19908864be104b5ea914ed4b53607816c8cbe9359**. The adapter consumes the existing digest-bound host, boot_id and boot_us payload fields and binds actor sessions only through explicit, unique board: references. It never compares a foreign boot counter with the local counter or treats local NTP evidence as a remote clock receipt.

Backup was updated first and produced a fresh report while the original primary continued running. Primary was updated only after that check. At **10:06:04Z**, primary PID **2678887** and backup PID **2670150** were enabled and active, both running from the f0a9 release with zero automatic restarts. Their separate durable floors retained 221; samples reported approximately 1.5 ms local system offset and 20.3 ms uncertainty. Reports remained degraded with 217 findings, dominated by missing legacy event provenance; this count does not mean 217 faulty clocks. The bounded response exposed 64 findings and counted 153 omitted findings. Existing cockpit and router PIDs remained unchanged.

The cooperative epoch-2 check rejected the first primary-update attempt because the session heartbeat was stale, before any primary mutation. After fresh Herdr identity observation and heartbeat, the same epoch was successfully rechecked and the primary update proceeded. The prepared/completed action, decision summary, forecast and rollback receipt is var/operations/20260907-1000-clock-provenance-rollout.json. The previous release and both floors are retained. This provides actual continuous observer coverage, with full-system traffic handoff still unimplemented.

The MCP follow-on **4eabfc34fea9d0a96317fff4c759d8b3141a2c73** preserves the parent fixes and adds real stdio verification: five input messages yielded four parseable JSON responses, no response to the notification, preserved numeric/string IDs, and explicit missing-NIF/file errors. Diagnostics stayed on stderr. The line-size check bounds decoding after the IO read; it does not prove bounded initial line allocation.

The final MCP test child **88fe4fa8edd8b8c4dbc893e6c3fa8498b79f919f** replaces three legacy success expectations with runtime-dependent assertions: missing native code requires explicit UNAVAILABLE and no fabricated counts; available native code requires the typed response schema. Claude integrated the complete chain at **be5c2c70cf82b905f3f4e8674ac683b0d666d9d4** under integration lease epoch 14. The candidate preserved all parents. The combined gate passed 198 library tests, 502 swarm tests, and 29 focused MCP tests; the full CEPaF run had 10,003 passes and exactly the same set of 164 distinct failing test identities as baseline. The attribution set size is not an aggregate failure-event count. Source integration is distinct from exposure through a running MCP endpoint.

The C04/C05/KPI seam repair **d65573354bb619e8c94a63b28c45efcd4e5c1a3e** preserves parents 94ed6c2e and 4e6632fc. Investigation disproved the initial directory-creation hypothesis: C01 canonicalizes the registered workspace before journal I/O, and three action tests used nonexistent /uos. The tests now use the existing canonical workspace fixture. Only the test file changed; current-state, freshness and effect fences are unchanged. The telemetry child **8180c73608373b00b46f7836af71f50ce6f40de7** restores static OpenTelemetry/OTLP identity on the existing status route while keeping unobserved counts and log level null and collector/backend states unknown. Integration receipts must remain distinct from these candidate test receipts.

The strict board-validation child **e0b50cdce6fdb08e945984a119f4214c25893a5e** repairs a confirmed false-positive path: the old CLI reported a missing file as a valid empty board. The validation command now reuses the bounded board reader, rejects malformed rows and conflicting duplicate digests, and exits 1 for input or chain failures. An actual empty file reports EMPTY with no hive-health inference. The existing legacy board still validates with its explicit causal gap/fork records. No history is rewritten by validation.

## 9. Architectural Observations

The following preserves the canonical 17 aspects. It records relevant evidence and remaining obligations instead of inventing another aspect taxonomy.

| Aspect | Evidence or remaining obligation |
|---|---|
| A01 Substrate & Hardware Storage Interlock | No storage allocation or wipe performed; production interlock gate UNRUN for this slice |
| A02 Standalone Jujutsu Monorepo Discipline | Isolated JJ workspaces and candidate-preserving integration observed |
| A03 Zero-Muda Purity & Waste Elimination | Existing carriers mapped; no alternative broker/workflow/UI stack introduced |
| A04 Gleam/OTP 29 4-Domain Root Supervisor | Supervised observer candidates tested; existing root starts empty; full domain wiring UNRUN |
| A05 ZigVM Deterministic Engine & 8 VFS Laws | Existing engine retained; no new VFS admission evidence |
| A06 Hermes Formal Evidence, Gospel & Z3 | Native ingestion/hash/replay executed; broader solver/effect composition remains UNRUN |
| A07 Mathematical Authority & Conservation | C07 journal proofs/models retained with their original bounds; no blanket proof of these adapters |
| A08 Biosemiotic Cybernetics & Rocha Cut | Board/report observations carry no execution or deployment authority |
| A09 Quarantined Modular MAX/Mojo Inference | These deterministic reads/tests need no model request or new Python runtime |
| A10 Zenoh OoZ & MoZ Mesh Telemetry Backplane | Existing 8080 router observed; full authenticated tenant ACL composition remains UNRUN |
| A11 AG-UI 32-Event SSE Stream Protocol | Existing carrier retained; new authenticated stream binding UNRUN |
| A12 A2UI 233-Component Declarative Catalog | Existing presentation carrier retained; new view conformance UNRUN |
| A13 Penta-Stack Multi-Interface Accessibility | Gleam JSON/text reports executed; five-interface semantic parity UNRUN |
| A14 Universal Tailscale FQDN Web Navigation | Journal and reuse register served HTTP 200 with matching content after integration |
| A15 Comprehensive Verification Checklist | Eighteen scoped checkpoints below; production gates remain explicit |
| A16 Knowledge Management Triad (Wiki/ZK/Ont) | Existing formal spec/source receipt/reuse register linked; full live ontology propagation pending |
| A17 Sa-Plan & Bionic Durable Workflows | Real WAL observation path reused; task completion, release and compensation authority remain separate |

The existing C3I forecast fold, capacity model, and Bayesian helpers are reusable pieces, not evidence of full ZigVM prediction-system integration. The observed stan_worker directory description is not a running CmdStan service. Forecasts must identify inputs, horizon, assumptions, uncertainty, and later observed outcome. Intelligence/capability KPIs may measure outcomes and calibration; consciousness remains **UNESTABLISHED**, without a synthetic numeric score.

## 10. Remaining Gaps

Full integration still needs authenticated actor/host/boot provenance beyond the current digest-bound local metadata; independent remote clock receipts; continuous peer heartbeats; populated root-domain supervision; admitted effect executors; all-surface status projection; and real collector/backend delivery. Both read-only observers now report these gaps continuously. They do not promote a workload or modify runtime traffic. The default workspace retains AGY's active changes; Claude owns mainline integration.

AGY resolved the pre-existing shared-board conflict before consuming Codex's pause request. Codex therefore did not write the shared file. A private copy of the original conflict bytes has SHA-256 **4b1cad0acfa5902958024e69262dfa857934bf7d7a3ae4cb1aa9cb7f23397a43** in var/operations/20260907-1010-board-conflict. Strict parsing recovered 249 rows and 233 unique message IDs with no conflicting digests. Comparison against AGY's resolution found every original id/digest retained, plus explicit fork record 1788775922984571-d90d18dfe74c0517. Two older delivery-state row versions were absent from the resolved projection; their original bytes remain in the private capture. The resolved board validated as 234 messages, with three gaps and five forks recorded explicitly, and JJ reported no remaining conflict. These counts describe that capture; later peer appends may advance it.

Claude then merged that board with the integration ledger at **12469f6365e3**, retaining every message id/digest and adding three explicit fork records exposed by the combined history. Both copies validated at 240 messages, three gaps and eight fork records. The default workspace was synchronized with the merged board and its unrelated AGY changes preserved. Historical causal gaps stay documented; merging does not recreate lost events.

The existing telemetry exporter is the integration point if a collector is provisioned. Collector pipelines need explicit receivers/exporters and can be configuration-validated using the official tool. [OpenTelemetry configuration](https://opentelemetry.io/docs/collector/configuration/). No collector was installed by the evidence checks recorded here.

## 11. Metrics Summary

Measured: 21 service mappings; 57 cross-language event matches; one correlated log sample; 205 duplicate ledger rows deduplicated in the captured report. Host chrony at 09:21:33Z reported Normal leap state and approximately 805 microseconds system offset.

The 10:20:27Z recheck found both updated observers still active with zero restarts, unchanged cockpit/router PIDs, fresh reports, and durable observed Lamport floor 226. Local offsets were 1991/1950 microseconds, with uncertainty 18605/18648 microseconds. The rollout behavior forecast was observed, but its 180-second horizon was missed: both first reports from the new release were available after 243.37 seconds. The private operation receipt records this miss instead of scoring it as a successful timing prediction; no calibrated probability was supplied.

Not measured: fleet-wide token spend, cheapest-provider optimum, forecast calibration improvement, consciousness, full 17-aspect completion, production availability SLO, and all-surface semantic coverage. Unknown cost or evidence does not become zero.

## 12. STAMP & Constitutional Alignment

Authority remains with canonical UOS policy and the operator. Sa-Plan task state, cooperative resource leases, signed-board exchange, evidence ingestion, and runtime release authorization have distinct meanings. New work preserves the current cockpit/router, shared journal history, source lineage, and denied storage serial 25503L801736.

The observer runtime lease was released with journal sequence 108 after rollout. Five actual Claude integration/rollout messages were acknowledged through typed coordinator commands at sequences 117–121; prompt delivery alone was not counted as acknowledgement. Herdr temporarily reported the root session blocked, so its heartbeat was refused; no replacement heartbeat or runtime mutation bypassed that refusal. Once Herdr again reported the actual session working, the heartbeat and acknowledgements succeeded.

Decision summary: retain existing C3I/Indrajaal carriers; correct their observed boundary defects; introduce narrow typed adapters for missing behavior; use local deterministic verification first. This choice reduces integration surfaces while preserving explicit failure states. The principal risk is mistaking an available module or a successful test package for a deployed, authenticated service. Fresh runtime probes and candidate-bound receipts address that risk.

## 13. Conclusion

The reuse register and the observed implementation results provide a concrete handoff. The development candidates improve coordination, evidence, clock checks, and reporting. This artifact preserves candidate-level test receipts and actual runtime observations; the integrator's final composed-revision record owns the subsequent main move and combined gate. Full production admission is outstanding and must use the composed candidate's actual runtime and formal evidence.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] CHK-01-TIME — Observed host UTC and chrony evidence recorded.
- [x] CHK-02-TAIL — Full FQDN links served HTTP 200 with matching journal/register content.
- [x] CHK-03-FRACT — Fractal and knowledge tags provided.
- [x] CHK-04-KM — Formal spec, source receipt, journal and machine register linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] CHK-05-MUDA — Reuse inventory adds no alternative runtime dependency.
- [ ] CHK-06-GRAPH — Whole-system graph/dependency gate not rerun.
- [ ] CHK-07-DRIVE — No storage mutation; production interlock gate not rerun.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — New full UI conformance not exercised.
- [ ] CHK-09-MATH — Four global quality metrics not measured.
- [ ] CHK-10-9MOD — Focused runtime/unit/formal evidence is not all nine modalities.
- [ ] CHK-11-REGR — Full UI regression/monitoring not rerun.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Observer candidate tests pass; four-domain root construction remains open.
- [x] CHK-13-HERMES — Scoped native hash/WAL/replay and gap controls executed.
- [ ] CHK-14-ZIGVM — No new VFS or deterministic runtime admission.
- [ ] CHK-15-MAX — No inference needed; production inference gate not exercised.
- [ ] CHK-16-OTEL — Structured log correlation executed; collector/backend acceptance not established.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Composed runtime/formal admission remains outstanding.
- [x] CHK-18-JJ — Standalone JJ workspaces; root did not move main or use Git mutations.

</details>

**Previous:** [17-aspect specification](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md) · **Next:** [Shared swarm runbook](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-0653-uos-tri-agent-swarm-operations.md)

**UOS footer:** Scoped development evidence; unknown and unrun obligations remain nonpassing.
