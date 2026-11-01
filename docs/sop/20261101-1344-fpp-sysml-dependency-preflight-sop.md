# 20261101-1344 — FPP/SysML dependency preflight SOP

**Created:** 2026-11-01T13:13:44Z; a recent chrony observation reported normal synchronization.  
**Status:** TASK-SPECIFIC DRAFT; process guidance, not runtime enforcement or system admission.  
**Applies to:** FPP and SysML translation to Gleam/OTP and Lean; MCP, Zenoh, all applicable system messaging, persistence, toolchain provisioning, and real-agent integration.  
**Trigger:** Before a task claim or dispatch, before each affected effect, after a change in candidate, scope, owner, authority, evidence, environment or dependency, and before integration or release.  
**Decision at creation:** The complete work package is **BLOCKED**, with eligible repair/probe work determined independently. Re-observe every time-sensitive fact.

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zk-adr #zero-muda #tailscale-web

[Execution prompt](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1326-fpp-sysml-autonomous-fractal-execution-prompt.md) · [RCA and implementation handoff](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1224-fpp-sysml-fractal-rca-tps-implementation-handoff.md) · [Draft journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261101-1348-fpp-sysml-prompt-and-preflight-journal.md) · [UOS policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) · [Risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Risk checker contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1606-risk-checker-contract.md) · [Gleam harness contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) · [Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning) · [This SOP](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261101-1344-fpp-sysml-dependency-preflight-sop.md)

These are intended Tailnet locators. Publication, reciprocal KM registration and live readback of this draft are unverified. Existing knowledge references: [[wiki:20260905-1801-uos-zk-km-corpus-index]] and [[zk:20260905-1801-moc-uos-unified-master]].

## 1. Decision rule and inputs

The operator has authorized autonomous completion and comprehensive **task-scoped** development capabilities. Do not ask again for this already-provided scope. An operator instruction is not itself an issued technical credential, a fresh Sa-plan lease, an independent review, a successful effect or production admission. Honor actual platform and repository authority boundaries.

For each **specific slice and effect**, collect: desired outcome and source models; applicable requirements and acceptance tests; current Jujutsu revision and working-copy diff; Sa-plan plan/task/attempt and dependency DAG; actor, worker, session, workspace and host; risk portfolio; grant/review identity and expiry; toolchain and input closure; affected services, stores and agent endpoints; prior effect receipts; budgets; and required test and recovery evidence. Inventory the real system and add dependencies not named here. Use current observations and timestamps; an inventory of known dependencies does not prove that none are missing.

Assign each dependency one of **READY**, **BLOCKED**, **STALE**, **UNKNOWN**, or **N/A**. N/A requires a scoped rationale and reviewer; it is not a substitute for discovery. For every item record owner, source and candidate binding, observed time/expiry, discriminating check, evidence reference, required repair, downstream consumers and a concrete exit test. A dependency is READY only when its actual acceptance evidence is current and bound to the effect. Unknown, stale, absent, unsupported or failed evidence holds its consumers; a numerical score, model response, heartbeat or prior green result never waives this rule. Independently authorized repair tasks may proceed if their own dependencies and fences pass.

## 2. Fractal standard work: PREDICT → OBSERVE → ORIENT → DECIDE → ACT → VERIFY → REFLECT

1. **PREDICT:** State the candidate outcome, allowed effects, affected model elements, dependencies, evidence age, budget, failure impact and one falsifier. Establish a bounded time/resource limit and a stop condition.
2. **OBSERVE:** Verify the synchronized host clock; current harness exposure, KM health and top relevant precedents; canonical Sa-plan state and ownership; Jujutsu parent and preserved peer changes; exact tool paths/versions; service and agent health; and prior receipts. Record observation time and source. Use `knowledge_search` with limit 5 when the exposed API supports it, bounded `zk_transclude`, and only the top one or two needed source documents; record API limitations.
3. **ORIENT:** Separate observed facts, historical claims, source inference and unknowns. Identify the controller, control action, feedback and unsafe outcomes for every boundary. Trace consumers to actual prerequisites and inspect unresolved effects. Construct the relevant alternative hypotheses and the cheapest safe discriminating observation.
4. **DECIDE:** Apply safety, current authority, freshness and dependency readiness first. Assess all four STPA unsafe-control-action types and raw FMEA before ranking eligible work. Record the complete source-bound Sa-plan/risk scope, acceptance tests, uncertainty and residuals. Select and claim only an eligible task through Sa-plan.
5. **ACT:** Recheck exact worker, attempt, lease, grant, candidate and effect-time fence in the admitted Gleam harness before each bounded action. Use independently authorized, non-overlapping workspaces for real agents and preserve other work. Install packages only through repository-pinned Nix/devenv inputs with an allowed realized closure or configured Tailnet fetch path. Do not replay an unknown prior effect.
6. **VERIFY:** Bind tool output, test observations, formal statements/imports, negative cases, recovery results and independent review to the same candidate. Check the complete relevant route and original effect, not only a component version or endpoint heartbeat. A failed checker, unavailable input, timeout or unsupported language feature is not a pass.
7. **REFLECT:** Save a concise decision/evidence record, current task status and remaining dependencies through the authorized route. Complete the 13-section journal and reciprocal wiki/ZK/inventory records when appropriate; preserve failures. Reassess affected parent and child slices on any changed dependency.

Repeat the sequence for L0 governance/authority, L1 effects, L2 tools/components, L3 transactions, L4 services/models, L5 agents, L6 semantic integration/formal evidence, L7 federation/messaging, L8 concurrent evolution/integration, and L9 verification/admission. See the execution prompt for the detailed observed root-cause hypotheses and falsifiers at each layer.

## 3. Ordered preflight gates

### G0 — Establish scope and authoritative context

- Read the actual active policy and harness contract, relevant source/risk documents and current KM observations. Preserve the EV-93 admission ceiling; EV-94–109 and ADR-071–086 are not admission evidence, and do not mint an EV number.
- Verify the host clock and the repository revision. Inspect Sa-plan state and both the default and affected sibling workspaces without resetting, rebasing, deleting or overwriting other work. Track parent and candidate hashes separately.
- At the last observation the FPP plan was `uos/fpp-sysml-integration/20261101-0852`; the recovery plan was `uos/harness-build-recovery/20261101-0913`. Their previously observed active attempts had expired leases and stale risk. Confirm current state instead of assuming those facts remain current.
- The Sa-plan shell wrapper may build its binary if missing. Treat invocation and any build as effects subject to the currently admitted harness and scope; do not assume a nominal status command is always filesystem-read-only.

### G1 — Check the full dependency graph and risk

- Create or update actual task relationships through Sa-plan; record prerequisite IDs, owners, required outputs, proposed parallel work and rejection/repair paths. A missing node, cycle, absent owner or unresolved consumer blocks the affected task. Do not create a competing task queue or write the Sa-plan database directly.
- Use the repository-owned report-only checker with the actual complete portfolio and task. Its supported forms include `bash tools/risk-priority-check --preflight PORTFOLIO TASK` before claim and `bash tools/risk-priority-check --active-check PORTFOLIO TASK WORKER ATTEMPT` during an owned attempt. Use the contract's explicit reclaim or reviewed reclaim-set forms for expired attempts. `bash tools/risk-priority-check --all` applies for checker/policy changes and relevant CI. These commands are examples with placeholders, not a grant to bypass the harness.
- The wrapper builds in `${TMPDIR:-/tmp}`. A supported, authorized alternative temporary directory may be used for a report-only run, but does not repair quota, renew a lease or authorize an effect. HOLD, stale source-bound assessment, missing checker tools, failed clock or unresolved tie requires evidence repair; do not force-pass.
- Record raw severity, occurrence and detection difficulty per failure mode on the local 1–5 anchors; unknown occurrence remains unknown. Calculate `RPN = S × O × Det` and `F = max(S, rpn_band(RPN))`, then the local `C × T × F × Dep × I` only after eligibility. These are ordinal triage judgments, not measured probabilities. Record all four STPA cases: action omitted, unsafe action supplied, wrong time/order, and stopped too soon/continued too long. Bind the applicable 17-aspect evidence, controls, tests, counterevidence and residual risks.

### G2 — Establish effect authority, identity and containment

- Confirm the private development MCP route is actually connected to the intended issuer and session. Observe real worker/session/workspace identity and the reviewed grant's exact task IDs, candidate/path/action coverage, expiry and digest without disclosing secret material. Confirm the independent review and actual current lease. The public `uos-gleam` route alone is not proof of successor authority.
- Verify both allowed calls and refusal of missing, expired, mismatched or over-scope identities. If the implemented grant schema cannot express all required actions, Lean/Nix paths or identities, first repair and independently review the missing capability using an authorized bounded bootstrap task. Issue distinct bindings when the schema binds one worker/session/workspace per grant; retain the coherent full work-package scope.
- Preserve the old `FAILED_OR_UNVERIFIED` build result and related intent, process state and available manifests. Establish whether partial output and descendants exist; resolve only with operation-specific adjudication. A separately reviewed fresh task may continue in another workspace without replaying or clearing the original effect. Do not forge a review or change identifiers to defeat deduplication.

### G3 — Prove the toolchain and probe integrity

- Inventory exact pinned source/version, build input, license/provenance, executable path, hash, architecture and closure for compiler/linker, OTP/ERTS/erlc/escript, rebar3, Gleam, Lean/Lake, Z3 where required, native ABI, Nix/devenv and official or independently qualified FPP/SysML tools. Version output alone does not establish usable behavior or official conformance.
- Run applicable toolchain preflight only through the authorized path, with bounded time and verified writable scratch space. Validate the generated input files are complete before interpreting compiler, escript or solver output. Observe an actual C compile and link, Erlang artifact, escript result, satisfiable Z3 control, Lean kernel execution and the cold task-bound esqlite/build path; separately capture stdout, stderr, actual exit status and generated artifacts. The checks may be distributed across valid tasks and need not run for an unrelated slice.
- A recent advisory run reported 4/31 failures: erlc exit 1, escript exit 127, Z3 empty output, and no `.beam`. The missing-artifact branch in `tools/preflight` prints `erlc exited 0` whenever the artifact is absent, regardless of the compiler exit. Probe truncation or quota is a hypothesis, not an established cause; verify input bytes, scratch storage and real return codes before assigning blame. Keep a failed result until a valid new observation supersedes its scope.
- A historical original workspace lacked `cc`; an isolated candidate profile exposed Nix GCC 15.3.0. Bind and test the actual selected candidate rather than assuming that candidate is merged or the host compiler satisfies repository provisioning policy. `--offline` alone does not prevent all fixed-output fetches.

**Upstream reference inputs, not installed or admitted artifacts:**

- [NASA FPP compiler documentation](https://github.com/nasa/fpp/blob/main/compiler/README.adoc) lists actual compiler tools and, on its moving `main` at this observation, sbt and JDK 25 as build prerequisites. The documented tool list includes `fpp-check`; it does not list `fpp-to-xml` or `fpp-to-json` there. Select a real compatible release/commit, then pin and qualify that version's full build closure; do not invent CLI names or assume an upstream moving branch is the repository's pin.
- [OMG SysML specifications](https://www.omg.org/sysml/) distinguish v1 and v2. The [SysML v2 release repository](https://github.com/Systems-Modeling/SysML-v2-Release) identifies KerML, the SysML model libraries and a pilot/reference implementation; determine the applicable inputs, interface, license and transitive build/runtime closure for the chosen version.
- [MCP transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) and [Zenoh protocol entities](https://spec.zenoh.io/spec/1.0.0/concepts/entities.html) are comparison references. Pin the versions actually supported by each endpoint and qualify authentication, adapter behavior and persistence separately. A Zenoh storage entity is a distinct higher-level subscriber/queryable role, not an automatic property of each publication.
- Use the [Gleam documentation](https://gleam.run/documentation/) and [Lean language reference](https://lean-lang.org/doc/reference/latest/) for the versions selected in the repository toolchain. None of these external links authorizes ingestion, establishes tool availability or replaces a pinned two-key review.

### G4 — Qualify models, semantics and persistence

- Inventory model sources, FPP/SysML language versions, reference grammars, supported and unsupported constructs, generated/intermediate representations and source-to-target traceability. Pin or qualify official tools and run representative positive, negative and differential fixtures. A missing tool on PATH is not proof that it is absent elsewhere.
- For each requirement, port, connection, actor, state machine and persistence operation, identify its Gleam type/owner and Lean proposition. Include duplicates, dangling references, direction/type mismatches, unsupported syntax and initialization failures. Trace failure back to source location; nonempty verification labels are not evidence.
- Before calling a save durable, verify the actual supervised owner, commit boundary, idempotency key, concurrency policy, readback and restart. Inject bounded failures before/after commit and during lost acknowledgement. Distinguish accepted, committed, failed and unknown outcomes; message delivery alone is not a storage commit.
- For Lean, record exact theorem statements, source/import closure, approved axioms, toolchain and replay commands; use an independently tested audit that rejects `sorry`, unsupported axioms and false-pass paths. Bind proofs and executable conformance fixtures to the same candidate.

### G5 — Qualify messaging, agents and trust

- Discover all applicable actor mailboxes, event buses, MCP tools/resources/prompts, Zenoh topics, storage/outbox paths and actual agent CLIs/APIs. Build a source-to-destination capability matrix: identity, authentication, authorization, schema/version, correlation, ordering, delivery/acknowledgement semantics, idempotency, timeouts, cancellation, backpressure, limits and persistence/replay. Mark absent or unsupported adapters explicitly.
- Verify the real subscriber/owner and exchange uniquely correlated messages end to end, including denial, disconnect, duplicate, restart and recovery cases. Endpoint reachability or a heartbeat is insufficient. MCP is a client/server interface and Zenoh is a transport; neither automatically controls every agent without an applicable adapter and authority.
- Verify actual Pi, AGY/Argon, Claude and Codex session identities, availability, task binding, non-overlapping scope and supported request/status/result/cancel/start/stop paths. Respect existing running work; do not impersonate an agent or blindly answer another session's pending approval. Bound concurrency and provider cost; reconcile the available usage information before a paid route.
- Inspect current ZLP source and historical claims as a candidate, not automatically as the deployed route. Verify native ABI, supervision, resource limits and fault recovery. In particular, an exposed OS-process-kill operation requires explicit scope and isolated test targets. The ZLP build script's local temporary-directory change does not establish a general `/tmp` quota fix.
- Record authenticated endpoint identities, credential origin/expiry/revocation and secret-safe diagnostics. Negative tests must cover unauthorized and cross-identity operations. Never copy tokens, private keys or credentials into prompts, logs, evidence or source control.

### G6 — Integrate, review and close

- Re-observe and serialize the current Jujutsu integration point. The shared parent was `80e5ec1d` at the last observation and incorporated candidate `8dea1463`; this is a moving observation, not proof that a runtime runs that source. Preserve peer modifications and rebind candidate-specific evidence after any parent change.
- Run the relevant unit, property, integration, differential, failure, recovery, timeout and performance checks on the exact candidate; test negative authority and unsupported-model cases. Distinguish planned, unrun, failed, stale, source-present, executed, verified and admitted. Record the independent review and both fresh runtime and machine-verifiable formal evidence for each claimed capability.
- Update Sa-plan, a 13-section task journal, reciprocal wiki/ZK references and the inventory as authorized. Complete the applicable six-domain/18-core-check plus provenance requirements. Live Tailnet publication/readback, release, production cutover and system admission require the independently applicable authority and evidence.

## 4. Dependency register and acceptance checklist

Use this table as a minimum. The operator/worker must expand it from the actual architecture, software bill of materials, source models, service catalog and candidate diff; absence from this table is not evidence of non-applicability. For each row attach owner, exact source/candidate, age/expiry, checks, consumer and a repair task.

| ID | Dependency to observe | READY only when |
|---|---|---|
| D01 | Operator scope | Full task scope is recorded and unambiguous; machine authority is handled separately. |
| D02 | Sa-plan and risk | Current task DAG, assessments, preflight, worker/attempt and unexpired lease pass for this effect. |
| D03 | Original unknown effect | Operation-specific adjudication resolves it, or a distinct authorized non-replay task uses isolated state while the original remains held. |
| D04 | Private MCP and issuer | The actual successor route, trusted issuer and session binding are observed. |
| D05 | Grant capability | Independently reviewed per-identity grants cover every required path/action/task and deny expiry, mismatch and over-scope. |
| D06 | Core toolchain | Exact pinned closure compiles, links and supports the bounded cold task build. |
| D07 | Reference tools | Qualified FPP/SysML versions, provenance and differential fixtures are available and pass. |
| D08 | Domain behavior | Candidate-bound valid/invalid model and actor startup regressions pass. |
| D09 | Durable storage | Commit/readback, idempotency, restart and fault/ambiguous outcome tests pass. |
| D10 | Lean integrity | Exact statements, imports, axioms, kernel replay and shared fixtures are candidate-bound. |
| D11 | Zenoh and messaging | Actual subscriber, addressed delivery and required failure/recovery semantics are demonstrated. |
| D12 | Agent sessions and budgets | Real named identities, supported operations, grants, availability and bounded usage are observed. |
| D13 | Scratch and containment | Real quota/capacity, owned temporary space, worker cleanup and process bounds are proven. |
| D14 | Integration and release | Exact current revision, serialized merge, independent review and required release evidence are bound. |
| D15 | ZLP candidate | Actual route choice, supervision, native ABI, safe process controls, runtime identity and failure tests are verified. |
| D16 | Preflight correctness | Probe inputs and actual tool exit/output/artifacts are valid; four recent failures are discriminated and resolved for the target environment. |
| D17 | Translation coverage | Dialect, model-to-IR-to-Gleam-to-Lean mappings and unsupported cases have reviewed fixtures and traceability. |
| D18 | Security boundaries | Endpoint identity, scoped credentials, expiry/revocation and unauthorized/cross-identity negative tests pass. |
| D19 | Complete messaging inventory | Every applicable source, destination, adapter and behavior is identified and evidenced, or a supported exclusion is documented. |

Record example, using actual supported Sa-plan/evidence interfaces rather than creating a competing authority:

| Field | Required value |
|---|---|
| Slice and effect | Plan/task/attempt, intended effect, dependency edges and current owner |
| Identity and fence | Real actor/session/worker/workspace, grant/review references, expiry, lease and effect-time result |
| Candidate | Jujutsu revision, relevant working-copy digest and input/toolchain hashes |
| Dependency result | ID and status; source, observed time, freshness, owner, check, outcome and evidence locator |
| Risk | Four UCAs, raw S/O/Det, uncertainty, local ranking, 17-aspect references and acceptance criteria |
| Repair and verification | Bounded repair task, retry/stop rule, negative and recovery tests, independent reviewer, residual risks |

## 5. Release decision and current exceptions

An individual slice becomes implementation-ready only when every dependency applicable to that slice has fresh READY evidence and its own effect-time fence passes. The complete work package is ready only when this is true for every required slice. An independently scoped repair can be ready while another slice is blocked; it does not clear that slice. Re-run affected checks on changes to a model, tool input, parent revision, runtime, agent identity, grant, lease, endpoint, budget or risk. Preserve the previous result and explain what changed.

At this draft's last observation, the private development route and comprehensive reviewed task grants were unavailable, old Sa-plan attempts were expired/stale, the original build effect was unresolved, the live Zenoh subscriber was stopped, FPP/SysML reference-tool qualification was unverified, and a newer toolchain preflight reported four failed checks. The 19-entry register and execution prompt define what must be done to resolve these conditions; they do not claim the conditions are already cleared.

## Comprehensive verification checklist

These entries describe this SOP draft and do not assert implementation or runtime completion.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Creation timestamp and recent synchronization observation recorded.
- [ ] CHK-02-TAIL — Verify live Tailnet publication and byte identity after authorized cutover.
- [x] CHK-03-FRACT — All ten fractal layers and their preflight method are identified.
- [ ] CHK-04-KM — Register reciprocal wiki, ZK, inventory and journal references.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Verify dependency exclusions on the actual candidate.
- [ ] CHK-06-GRAPH — Verify applicable language and native-kernel boundaries.
- [ ] CHK-07-DRIVE — Verify applicable storage interlocks without affecting protected devices.

</details>
<details><summary>Domain 3 — Tests and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Run applicable C1–C8 checks.
- [ ] CHK-09-MATH — Evaluate the applicable mathematical gates.
- [ ] CHK-10-9MOD — Run applicable test modalities.
- [ ] CHK-11-REGR — Bind regression results to the implementation candidate.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Verify OTP supervision and fencing.
- [ ] CHK-13-HERMES — Verify bounded evidence and analysis.
- [ ] CHK-14-ZIGVM — Verify the deterministic kernel where affected.
- [ ] CHK-15-MAX — Verify inference isolation where affected.
- [ ] CHK-16-OTEL — Bind actual clock and trace evidence.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Obtain applicable independent review and effect authority.
- [ ] CHK-18-JJ — Reconcile the final Jujutsu candidate and Sa-plan receipts.

</details>
<details><summary>Domain 6 — Provenance extension</summary>

- [x] The SOP preserves the EV-93 ceiling and rejects EV-94–109 / ADR-071–086 as admission evidence.
- [ ] Verify final provenance and live publication before claiming completion.

</details>

[Previous: execution prompt](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1326-fpp-sysml-autonomous-fractal-execution-prompt.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Next: RCA and implementation handoff](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1224-fpp-sysml-fractal-rca-tps-implementation-handoff.md).

UOS footer: this SOP is a draft dependency-checking procedure; it grants no execution, deployment or system admission.
