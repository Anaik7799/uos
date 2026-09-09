# 20260909-0510 — Gleam harness bootstrap independent review

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #km-triad #tailscale-web

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Atlas projection](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-algebraic-atlas.json) · [Review receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0510-gleam-harness-bootstrap-independent-review.json) · [Artifact checks](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0510-gleam-harness-bootstrap-independent-review-checks.json) · [Prior evaluation review](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0331-ecology-evaluation-independent-review.md)

Status: independent source review complete; new harness implementation and operational acceptance remain with the parent. No system admission. Links are intended Tailnet locators; publication was not tested.

Sa-plan `uos/ecology-harness-bootstrap-review/20260909-0412`, task `BOOTREVIEW`, worker `codex-ecology-harness-bootstrap-review`, attempt 1. Preflight passed at 04:48:38Z; claim at 04:49:02Z; active observations passed at 04:49:03Z and 05:02:59Z. The last observed chrony stratum 3, absolute offset 0.000276445 seconds and uncertainty 0.017813564 seconds. Filename prefix follows the observed UTC hour/seconds at 2026-09-09T05:00:10Z. Source hashes were sampled around 05:02:20Z; these are observations of moving sources, not an atomic release candidate.

## 1. Scope & Trigger

The operator permitted a one-time development bootstrap after requiring agent operations to use MCP or Zenoh through a Gleam harness. The parent requested an independent review of its specification, algebraic atlas, paired diagrams and current MCP defects. This task owns only review and task artifacts. The parent owns reader, adapter and development-service implementation.

## 2. Pre-State Assessment

The specification explicitly reports SPECIFIED / NOT_IMPLEMENTED / NOT_ADMITTED. Its 26 requirements, 16 acceptance cases, 16 scenarios, six native-generation cases, ten fractal layers and 17-aspect impact table describe obligations. The JSON atlas currently contains 34 state labels and three diagram references; it is a requirement/scenario projection, not an installed per-capability service inventory.

The parent had observed a packaged MCP reader crash and a catalog without development edit/build/test services. Those parent runtime observations are distinct from this review's source evidence. No fresh connector session, model call, compiler fixture, server startup or production operation was executed by this reviewer.

## 3. Execution Detail

Applied repository risk and verification guidance, established a separate one-task assessment and claim, and inspected the full specification and all three ASCII/Mermaid source pairs. Compared legacy MCP authorization, framing, reader, Sa-plan bridge, mesh transport, inference projections and focused test source against the stated requirements. Read primary Gleam, OTP and Modular documentation for native-generation claims. Sent concrete findings and proposed acceptance gates to the parent during implementation.

When local bootstrap administration became authorized again, the earlier paused MCP discovery task was released through Sa-plan with `released=true`, attempt 1. It was not reported complete and no unverified MCP locator was promoted to an endpoint.

## 4. Root Cause Analysis

L1 representation mistakes can crash a nominally typed transport when an external function returns a different runtime shape. L3 task and effect identities diverge when an attempt is omitted or a new attempt resets deduplication. L4/L7 catalogs, payload identities and publication acknowledgements can be mistaken for authenticated execution. L5 measurements become misleading when heuristics and fixed constants are formatted like observed model results.

The architecture must preserve these distinctions in types, authority checks and receipts. The specification largely does so; the legacy source does not yet implement the full contract.

## 5. Fix Taxonomy

No implementation was edited by this reviewer. Later source reads confirm the parent changed the reader to `bit_array.to_string`; threaded a positive attempt through completion schema, decoder and literal CLI arguments; pinned the canonical Sa-plan database; used the existing bounded guardian with real exit status; and refused the six legacy mutators lacking transport-bound authority. Parent-reported reader RED/GREEN was not independently rerun here.

The specification now requires a stable logical effect ID across task attempts and explicitly tests lost replies, reclamation and cross-transport replay. Its three inline Mermaid closing fences are repaired. These are source-stage repairs; executed candidate evidence remains separate.

## 6. Patterns & Anti-Patterns Discovered

**BR-01, P1 — Effect identity across attempts: repaired in specification.** Deduplicating only by intent plus attempt would allow a reclaimed attempt to repeat an uncertain external effect. The revised requirement keeps a logical effect identity independent of authority attempts and reconciles prior effects and liabilities. Falsifier: lose the reply after commit/POST, reclaim, and replay through the other transport; a second effect must not occur.

**BR-02, P1 — Authorization: contained for six legacy mutators; finite service pending.** Legacy authz accepts actor identity from request data and defaults to AuditOnly. Rate state is process-local, not a global caller identity. The added unconditional refusal prevents the six declared mutations from using those claims as authority. The new service still needs authenticated transport binding, current task/attempt/epoch/environment checks and an explicit finite effect scope.

**BR-03, P1 — Sa-plan adapter: repaired in source.** The initial bridge joined untrusted arguments into a shell command, its FFI reported stdout success without checking child status, and completion omitted the required attempt. The revised bridge uses literal argv, a canonical database override, bounded guardian execution and typed nonzero-exit failure. Real command tests must cover metacharacters, empty/invalid attempts, wrong ownership, nonzero exit and missing executable.

**BR-04, P1 — File and frame bounds: representation repaired; confinement remains open.** The old identity FFI declared a binary as Result and is removed. Legacy file reads still use whole-file `file:read_file`; path denial is lexical substring matching and does not confine symlink aliases to an authorized root. The stdio size check runs after `io:get_line` has accumulated the line. Safe synthetic alias, traversal, UTF-8, oversize and partial-line/deadline tests are required; no secret file need be accessed. The development harness must not inherit this unrestricted reader.

**BR-05, P1 — Zenoh transport parity: open in reviewed source.** The MoZ client uses `indrajaal/l5/cog/mcp/req` and `/res`; the bridge subscribes to `indrajaal/mcp/request/` and publishes `/response/`. The bridge ignores subscription failure, stores but does not use its node ID, and dispatches malformed topics as unknown/unknown. Its client leaves response correlation to callers and appends pending entries without a removal/deadline path. Test two bridges, one addressed request, duplicate and late replies, disconnected subscriptions, malformed topics and pending limits before claiming equivalent effect semantics.

**BR-06, P2 — Inference labels: heuristic source, not measured ML.** The AST adapter constructs a daemon description but runs pure substring checks. Fixed similarity 0.94, dimension 128 and latency 15 are not measured inference. Its legacy STPA path handles only UCA-1/UCA-2 patterns and uses 1..10 severity plus SIL labels; it does not implement canonical four-UCA/FMEA evidence. An initial concern about a pre-authorization external inference call was withdrawn after the full function was read: no such external call was demonstrated.

**BR-07, P2 — Atlas and bootstrap completion: concrete schema/gates proposed.** Requirement references and state strings do not provide capability denotations, state owners or deployed availability. The bootstrap exception needs an explicit end receipt and declared finite scope. The recommendations below separate that milestone from full atlas, failover, native compiler and admission work.

**BR-08, P2 — Native lifecycle and document rendering.** Native generation is correctly scoped as proposed compiler work, with a bounded typed IR, reference evaluation, exact discrete/error semantics, explicit numeric tolerances and rejection of unsupported effects. Add a Mojo hosted-runtime initialization/lifetime contract to native adapter acceptance. Current documentation describes C-ABI exports and shared libraries, but hosted runtime-dependent code needs initialization and the runtime has no shutdown API. These are current documentation facts, not observations of the installed pin. [Mojo compilation](https://mojolang.org/docs/tools/compilation/), [MAX custom operations](https://max.modular.com/develop/custom-ops/). The specification's checklist is still a regular table in the reviewed bytes; canonical expandable rendering remains to be demonstrated.

The specification correctly limits standard Gleam targets to Erlang and JavaScript and recognizes that external declarations do not validate runtime representations. It also defaults unpredictable native work to an isolated service; direct NIF admission requires exact bounded evidence. [Gleam configuration](https://gleam.run/documentation/gleam-toml-reference/), [Gleam externals](https://gleam.run/documentation/externals/), [OTP NIF API](https://www.erlang.org/doc/apps/erts/erl_nif.html).

## 7. Verification Matrix

All 17 canonical aspects were considered against the release SOP. Entries below describe this review's scope, never a 17/17 operational pass.

| Aspect | Source review and remaining evidence |
|---|---|
| A01 Substrate and hardware storage interlock | Preservation required; no device operation or interlock test performed. |
| A02 Standalone Jujutsu | Ownership/candidate requirements present; this review makes no VCS mutation or candidate snapshot. |
| A03 Zero-Muda and provenance | No dependency installation or external ingestion; full source/history gate unrun. |
| A04 Gleam/OTP 29 root supervision | Required ownership is clear; new development supervision/restart evidence pending. |
| A05 ZigVM deterministic engine and VFS | Contracted backend specified; descriptor confinement and VFS laws unrun. |
| A06 Hermes formal evidence | Bounded adapter source observed; Gospel/Z3 and actual command acceptance remain separate. |
| A07 Mathematical authority | Invocation-specific failures and conservation required; normative text is not proof. |
| A08 Biosemiotic cybernetics and observation/effect boundary | Denotation separates advice from effects; legacy heuristic labels need truthful status. |
| A09 Modular inference | Isolated execution and centralized budget specified; no new harness inference call tested. |
| A10 Zenoh mesh | Concrete prefix, targeting, correlation and pending-state defects remain. |
| A11 AG-UI event protocol | Receipt/lifecycle requirements present; full event delivery and durable outbox unrun. |
| A12 A2UI declarative catalog | Projection authority is clear; catalog coverage and actual rendering unrun. |
| A13 Multi-interface access | Shared semantics required; authenticated parity across clients not demonstrated. |
| A14 Tailnet navigation | Full FQDN locators supplied; new service/publication reachability untested here. |
| A15 Verification checklist | Scope/freshness requirements present; full runtime checklist and expandable spec view pending. |
| A16 Wiki/ZK/ontology knowledge triad | Grouped artifacts required; parent owns publication/index reconciliation. |
| A17 Sa-plan and durable workflows | Own canonical claim observed; bridge attempt/argv repaired in source; execution/recovery tests pending. |

Twenty artifact consistency checks passed for the written journal and JSON: section/checkpoint coverage, task identity, explicit non-admission, typed proposal counts and source/hash bindings. These checks do not test application behavior.

The three editable diagram pairs were read for matching nodes, edges and labels. The current inline fences are syntactically separated. Markdown rendering and Mermaid execution were not run.

## 8. Files Modified

Only this journal, its adjacent JSON receipt, the artifact-check JSON and temporary review/risk artifacts were authored. Existing source, specification, atlas, diagrams, global settings, production services and VCS were unchanged by this reviewer. The receipt binds 28 inspected regular source/evidence paths; hashes do not certify a frozen candidate.

## 9. Architectural Observations

Development/production and primary/standby are correctly modeled as independent roles. A backup host may run an isolated development node and a separate pinned production standby. A two-instance arrangement must stop development and restore the verified production release before claiming standby readiness. The specification correctly rejects ambiguous two-node writer leadership and an old binary as sufficient rollback evidence.

A typed capability atlas entry should declare the following groups. Missing evidence must be explicit Unknown/Unsupported, not an empty field interpreted as success.

| Group | Proposed typed fields |
|---|---|
| Identity and denotation | Capability ID/version; input/output/error types; algebra and laws; refinement relation. |
| Effects and authority | Pure/read/reserve/write effect class; finite resource scope; authenticated principal; task, attempt, lease, epoch and environment predicate. |
| Activation and ownership | Dependencies, activation/deactivation conditions, state owner, supervisor and restart limits. |
| Execution and availability roles | Independent development/production and primary/standby policy; allowed transitions and fences. |
| Recoverable state | Writer, schema, durability, replication/checkpoint, restoration, sensitivity, retention and recovery test for each item. |
| Bounds and time | Work, memory, output and concurrency limits; clock domains, synchronization uncertainty, evidence age and deadline. |
| Backend and ABI | Allowed harness-selected backends, realized toolchains, source/artifact digests, codecs, runtime initialization/lifetime and ownership. |
| Transport and effects | Schema, target, trace/correlation IDs, stable logical effect ID, retry/replay rules and unknown-effect reconciliation. |
| Model constraints | Privacy class, endpoint eligibility, reservation authority, token/body/price bounds and uncertainty. |
| Evidence and coverage | Requirement/scenario/aspect references; availability/activation/executed/verified/admitted distinctions; candidate, observation time, falsifiers and recovery receipts. |

## 10. Remaining Gaps

Proposed finite BootstrapReady acceptance:

1. The actual MCP connector is registered against the development Gleam endpoint, which reports the exact build and implemented finite tools.
2. One representative authorized task completes entirely connector → Gleam harness → selected backend → typed receipt, with trace, candidate and canonical task binding.
3. Safe bounded reads work; traversal, aliases, invalid UTF-8, oversize and partial-input/deadline controls fail safely.
4. Claim/completion attempts and effect-time task/worker/lease/epoch/environment checks are exercised; stale, wrong and anonymous authority is refused.
5. Arguments remain literal; missing tools, child failure, timeout and invalid output produce non-passing receipts.
6. Unknown tools and legacy/unscoped mutations are refused; callers cannot select unrestricted commands or backend effects.
7. Reply loss and replay cannot duplicate a logical effect; uncertain effects retain liabilities and require reconciliation.
8. Development isolation, resource/clock checks and the absence of production effects are observed at the applicable effect boundaries.
9. Any unexercised transport is explicitly unavailable. Full MCP/Zenoh readiness requires equivalent envelopes plus targeting, correlation, duplicate/loss and bounded-pending tests.
10. Record the successful finite gate and the end of the one-time direct-tool exception, then route further work through MCP/Zenoh. H16 client bypass interception remains explicit; full replication, native generation and system admission are separate obligations.

No new endpoint or full system readiness is certified by this review. The parent is implementing the finite service concurrently.

## 11. Metrics Summary

Reviewed 26 specification requirements, 16 acceptance cases, 16 scenarios, six native-generation cases, ten fractal layers, 17 aspects, three diagram pairs and 28 hashed source/evidence files. Reported eight grouped findings, including four P1 areas still requiring finite-service or transport evidence after source repairs. No builds, model calls, server starts, paid spend, global configuration edits, production operations or VCS mutations were performed by this reviewer. Primary documentation was fetched read-only.

## 12. STAMP & Constitutional Alignment

The review control action is to report source-bound gaps without granting runtime or release authority. UCA not-provided: omit a necessary boundary failure; unsafe-provided: declare a catalog or source repair operational; wrong-timing: approve against moving or stale evidence; wrong-duration: continue direct tools after bootstrap completion or retain an expired task. Controls are bounded independent review, early findings, exact task attempts, fresh risk observations, explicit evidence states and the BootstrapReady end receipt.

Raw review FMEA: severity 4, occurrence 3, detection difficulty 3, RPN 36, band 4. These are analyst estimates, not failure measurements. Criticality 4 × STPA 4 × FMEA band 4 × dependency 4 × impact 3 = 768, P1, after authority/readiness constraints. The score grants no effect authority. No new EV identifier is minted; admission above EV-93 remains outside this review.

## 13. Conclusion

The specification is a useful normative starting point with credible native-generation and development/standby boundaries. Source inspection found concrete legacy defects; several are now repaired or contained in source. The new finite harness still needs its own executed, task-bound BootstrapReady evidence. The atlas fields and falsifiers above give the next implementation a reviewable completion boundary.

<details><summary>Verification checklist — five domains, 18 checkpoints</summary>

| Domain | Checkpoints | Review scope |
|---|---|---|
| Metadata and navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Host/risk clock observed; timestamp, tags and full links present; publication pending. |
| Purity and storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | Read-only source review; no installs, foreign code ingestion or device operations; full gates unrun. |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Scoped source and artifact checks only; no broad suite or formal/runtime admission. |
| Runtime and observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | Requirement/implementation distinctions recorded; new harness execution pending. |
| Governance and JJ | CHK-17-SOV, CHK-18-JJ | Separate canonical task; independent findings; no VCS mutation or admission. |

</details>

UOS footer: source review and recommendations; runtime and sovereign admission remain separate.
