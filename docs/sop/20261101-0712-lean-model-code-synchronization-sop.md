# 20261101-0712 — Lean Model and Code Synchronization SOP

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #stamp-stpa #km-triad #zero-muda #tailscale-web #checklist-nav

**Status: PROPOSED / NOT_ADMITTED.** This SOP specifies a future engineering and assurance process. It does not establish that synchronization, Lean gates, drift collectors, MCP enforcement, runtime refinement, release controls, or deployment optimization currently operate. No live cutover, runtime action, EV number, or system admission is claimed.

**Observed authoring clock:** `2026-11-01T07:00:12Z`; the host clock was checked with `chronyc tracking` (stratum 3; reference `2026-11-01T06:57:48Z`; system 0.000012086 seconds slow). Prefix `20261101-0712` follows the repository's `YYYYMMDD-HHSS` convention.

**Navigation:** [SOP source](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261101-0712-lean-model-code-synchronization-sop.md) · [SC-JOURNAL-v3 contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260912-0745-sc-journal-v3-anticipatory-contract.md) · [Gleam harness operation contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) · [all-agent symbiosis preflight SOP](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261031-1807-all-agent-symbiosis-preflight-tps-and-evolution-sop.md). These are intended locators; live serving was not checked.

## 1. Purpose and boundary

Require explicit, versioned mathematical models for the UOS ontology, structure, runtime behavior, and verification tests, with traceable correspondence to implementation code. Treat the correspondence as a hypothesis to establish at a specific candidate revision—not as a property conferred by this document, a green test count, a model name, or a policy statement.

The target covers all 17 system aspects, agents and MCP/admitted Zenoh interfaces, Sa-plan ownership, task and release lifecycles, effects, logs, evidence, security, cost, performance, recovery, and the tests used to make claims about them. Keep the model and code in the language and subsystem authorized for that work: Gleam/OTP owns control and authorization; Hermes OCaml provides bounded analysis and evidence mechanisms; Lean 4 or another admitted prover covers suitable mathematical properties; ZigVM and isolated inference remain behind their documented boundaries.

This SOP is **not** a deployment authorization. Sa-plan remains the sole task authority. Effects remain behind an authenticated, candidate-bound, effect-time Gleam/MCP fence or other specifically admitted ingress. Model output, model advice, an MCP catalog entry, a proof report, a test receipt, or a gate result cannot independently grant task, provider, release, or deployment authority. EV-93 remains the admitted ceiling; do not mint an EV number under this SOP.

## 2. Required model set

For each affected change, identify which model classes apply. Each class has an explicit owner, revision, scope, assumptions, trust boundaries, properties, and independent evidence. An unaffected class needs a written, reviewed applicability rationale; omission is not `N/A`.

1. **Ontology model:** typed concepts, agent/runtime/provider/model identities, capabilities, scopes, layers, authorities, evidence, lifecycle states, supported and unsupported edges. State whether the model is finite, open-world, or closed-world and define what absence means.
2. **Structural model:** modules, exported constructors/functions, call and data-flow edges, effect boundaries, actor ownership, interfaces, dependencies, build targets, configuration surfaces, generated artifacts, and deployment packages.
3. **Runtime model:** state transitions for tasks, leases, actors, child processes, evidence freshness, budgets/liabilities, clocks, cancellation, cleanup, retries, release, rollback, and unknown outcomes. Include ownership and ordering assumptions; distinguish sequential from distributed behavior.
4. **Test model:** fixtures, generators, test transitions, oracle(s), assumptions, coverage claim, reproducibility inputs, expected verdicts, and test-tool versions. Model which implementation behavior each test actually observes. A test demonstrates only the specified observation under its observed setup; by itself it does not mathematically prove the tested universal property or code/model equivalence.

### 2.1 Candidate-bound synchronization record

Every modeled implementation element MUST have a machine-readable record, stored with the candidate's verification artifacts. At minimum record:

| Field | Required content |
|---|---|
| Candidate identity | Standalone JJ change/commit and operation references; source-tree identity; exact source, model, test, and manifest hashes |
| Implementation element | Module path plus exported function, constructor, actor, configuration key, effect, build target, or artifact. If exact ownership is not yet known, use `UNMAPPED` and HOLD |
| Model element | Ontology ID, structural node/edge, runtime transition, or test-model element and exact file/hash |
| Property and invariant | Named proposition, pre/postcondition, safety invariant, liveness claim with assumptions, or explicit non-fit |
| Test/evidence | Test ID, exact command/tool identity, seed/input, exit/result, raw evidence path/hash, independent oracle, evidence grade and reviewer |
| Configuration/runtime | Dependency lock/manifest, compiler/prover/runtime versions, flags, allowlisted sanitized nonsecret environment/config metadata and its hash, and stage-specific artifact identity. Never hash, copy or record secret bytes, private keys, credentials or live stores; use an authorized nonsecret reference/version identifier when needed. During development/merge, an absent build/runtime MUST be `NOT_YET_BUILT`, never a runtime observation. Release validation may pin a package plus the runtime that validated it; a production-loaded artifact identity exists only after a separately authorized startup has actually observed it. |
| Context | L0–L9 coordinate and versioned crosswalk; one or more of the 17 aspects; Sa-plan task/scope where applicable |
| Assumptions/trust | Assumption ID, owner, observable basis, validity interval/freshness rule, boundary, failure response, and status |
| Status | `PASS_SCOPED`, `NOT_YET_BUILT`, `UNRUN`, `UNKNOWN`, `STALE`, `UNMAPPED`, `UNSUPPORTED`, `FAILED`, `QUARANTINED`, or justified `NOT_APPLICABLE`; none may be inferred from an omitted value |

A mapping is current only when its code, model, test, toolchain, sanitized allowlisted configuration metadata, dependencies and generated outputs bind to the same candidate and declared dependency closure. Never hash/copy secret bytes, keys, credentials or live stores. Separate source/package and validation-runtime pins from production-loaded identity: release validation may bind the first set; a production-loaded artifact pin is possible only after separately authorized startup and an actual observation. During development/merge, an artifact not yet built is explicitly `NOT_YET_BUILT` and conveys no runtime observation. A missing artifact at a stage that requires it, any other missing identity, unsupported edge, stale receipt, unresolved renaming, tool upgrade, changed assumption, untracked generated file or owner ambiguity invalidates the affected mapping and places dependent claims in `HOLD`. Preserve old records; supersede them with new candidate-bound records rather than rewriting history.

## 3. Mathematical obligations and technique fit

Use the smallest formal technique that matches the property and has an independent oracle. The repository's local `formal-technique-selection` guidance requires an independent oracle and honest non-fit boundaries. The existing `formal/lean/Traceability.lean`, `formal/lean/DevelopmentCoreGate.lean`, and `formal/lean/AgenticJournal.lean` are candidate models to inspect for applicability and current-revision correspondence; their presence does not prove that this SOP is implemented or that a current code revision is covered. Confirm the tool and dependency pins before claiming a command is runnable. The repository-local `/home/an/NAS-setup/uos/tools/lean` is a known Lean entry point; do not assume an unverified solver or runner exists.

For each Lean model:

- State theorem scope, data types, assumptions, and whether the result is propositionally meaningful for the actual system boundary. Separate an ontology satisfiability witness from a proof that every capability or runtime case is valid.
- Demonstrate non-vacuity with explicit satisfying witnesses for each claimed supported profile and a nonempty domain. Add contradiction/negative controls for prohibited capabilities, invalid authority, stale scope, and unsupported edges. Check that each negative control is actually false in the model for the intended reason.
- Prove required safety properties over every modeled reachable state, preferably by a base case plus inductive preservation. State the transition relation, state-space bounds, abstraction choices, and any omitted states.
- State liveness assumptions separately (fair scheduling, available dependencies, bounded response, trusted time, or eventual process termination). Do not infer liveness from an invariant or a finite successful trace.
- Reject `sorry`, `admit`, undeclared axioms, and accidental noncomputable assumptions for claims that require constructive/runtime correspondence. Emit and retain an axiom audit such as `#print axioms`; list standard axioms actually used, including `propext` or `Quot.sound` where relevant. Never claim “axiom free” from a build without reviewing the output.
- For SMT, restrict formulas to a documented decidable fragment. Independently evaluate SAT witnesses with the concrete reference evaluator; check UNSAT against an independent oracle or bounded exhaustive cases. A solver result is not its own oracle.
- For temporal/concurrent claims, select a repository-present model checker only after confirming its version and interface. If the selected technique cannot express or decide a property, record `UNSUPPORTED`/`UNRUN`; do not dress prose as a proof.

For every modeled implementation operation, establish one of:

1. a source-to-model simulation/refinement relation whose preconditions, transitions, postconditions, effects, and errors are checked against the candidate implementation; or
2. a clearly bounded code-correspondence argument, supported by candidate-bound differential tests against an independent oracle and explicit residual risk.

The second option is preliminary, scoped observational evidence only. It MUST NOT be sufficient to assert complete semantic synchronization or deployed conformance. A whole-system “in sync” claim requires every applicable ontology, structural, runtime and test mapping, for pure and effectful implementation paths alike, to be complete and candidate-bound, with a proven simulation/refinement relation for each path's claimed semantic correspondence and stage-appropriate artifact binding where applicable. Effectful paths additionally require the relation to cover authorization and external effects. Any unresolved mapping, applicable path, refinement obligation or required artifact identity keeps the whole-system claim in `HOLD`. This target does not imply achieved coverage and does not prevent development work: implement and verify a bounded slice, report only its scoped observation, and keep unresolved system scope explicit. Mock-only tests, duplicated model logic, unbound source hashes, generated artifacts from different revisions, and matching success examples do not establish refinement. Preserve `UNKNOWN` and fail closed for the affected scope when the relationship is absent or stale.

## 4. Mapping coverage for the 17 system aspects

The following rows define minimum model/code/test/evidence obligations, not current implementation coverage. Candidate paths are source locations already identified by the ontology specification or canonical architecture; each real change still requires exact function/constructor/effect discovery and candidate hashes.

| # / aspect | Candidate implementation/interface boundary to inventory | Model obligation | Required evidence and status rule |
|---|---|---|---|
| 1. Substrate/storage | Append-only evidence stores, Sa-plan storage, resource ledger, filesystem, protected host OS/storage hardware interlocks, and `engines/zigvm` VFS as applicable | Durability, ownership, capacity, crash/recovery, hardware protection, no accidental cross-scope writes | Candidate-bound store/VFS/interlock contracts and recovery evidence; absent real persistence/interlock evidence => `UNRUN` |
| 2. JJ | Standalone `.jj/` workspace, change and operation identity, file add/delete/rename diff | Candidate ancestry, exact write set, immutable evidence references | `jj status`/diff/operation references bound to candidate; never substitute Git mutation |
| 3. Purity/provenance | Source manifests, dependency/build manifests, import and generated-file paths | Allowed language/dependency boundary and provenance conservation | Candidate dependency/source scan plus sanitized provenance; no inherited historical totals |
| 4. OTP supervision | `apps/cepaf_gleam` supervisors, agent lifecycle and owned child processes | State/ownership, restart, lease, cancellation, capacity and cleanup transitions | Actual OTP/ERTS observations bound to exact release; actor source alone is not runtime evidence |
| 5. ZigVM/VFS | `engines/zigvm` kernel and descriptor-relative VFS interfaces | Deterministic execution, path/authority bounds and resource limits | Pinned Zig/toolchain and ABI evidence where affected; otherwise justified scoped `NOT_APPLICABLE` |
| 6. Hermes evidence | `engines/hermes` Gospel, solver, oracle, receipt and evidence-store interfaces | Evidence status, provenance, append/reconciliation invariants | Exact tool/receipt hashes and independent oracle checks; no model self-attestation |
| 7. Mathematics | `formal/lean`, Gospel, bounded SMT or other verified formal path | Ontology consistency, invariants, arithmetic/resource bounds, temporal claims | Audited theorem/solver output, assumptions, standard axioms and witness/negative controls |
| 8. Feedback/authority | Sa-plan, `harness/admission.gleam`, `harness/operations.gleam`, effect-time MCP ingress | Permission predicates, freshness, veto order, UNKNOWN and rollback behavior | Scoped allow/deny evidence at effect boundary; documentation-only rule => not enforcement |
| 9. Isolated inference | `services/inference/max`, model/runtime/provider adapters and cost evidence | Identity separation, usage/liability, timeout/unknown, bounded resource behavior | Attributable provider/model/runtime receipt where authorized; no cost estimate as observed billing |
| 10. Mesh/observability | Admitted Zenoh, MCP, OTel and health/coverage collectors | Identity, clock domain, trace continuity, freshness and missing-data semantics | Fresh authenticated collector observations; missing/stale status is `UNKNOWN` |
| 11. Agent events | `harness/agent_ecology.gleam`, `agy_dispatch.gleam`, `successor_mcp.gleam`, coordinator/event ingress as applicable | Message identity/order, idempotency, replay, state and ownership | Source and runtime event evidence bound to task/candidate; board ACK is not effect proof |
| 12. Declarative UI | Relevant Lustre/web/TUI state projection and command/event boundary | Read projection, command authority, stale view and validation | UI/backend parity and accessibility evidence; UI cannot write around controller |
| 13. Multi-interface/accessibility | MCP/API, CLI, web, TUI and assistive navigation surfaces affected by the change | Semantic equivalence, authentication and consistent errors | Per-interface candidate-bound conformance and accessibility evidence; do not infer from one surface |
| 14. Tailnet navigation | Document/dashboard route and file-serving handler | Canonical path-to-URL and served-byte identity | Live serving check after separate authorization; intended FQDN link is not publication evidence |
| 15. Verification checklist | `SC-CHECKLIST-001`, journal linter and applicable gate/check tools | Applicability and truth conditions for every check | Exact command/version/output and scoped result; `PASS` cannot be inferred from checklist presence |
| 16. KM triad | Hermes wiki, ZK MOC and capability inventory/index | Reciprocal IDs/links, transclusion and canonical source relation | Local structural checks plus separately authorized live KM freshness/parity observation |
| 17. Durable execution | Sa-plan task/lease, Oban/Temporal or other admitted job/workflow boundaries | Claims, attempts, expiry, completion, retries, compensation and authority | Canonical Sa-plan receipt and effect-time fence; never write a parallel task authority |

For any affected row, require a typed link from implementation element to model node/property, test oracle, and evidence receipt. Record `UNMAPPED` if a specific function/effect owner is not known. Do not report the table complete merely because each aspect has a prose entry.

## 5. Source and journal synchronization

Inventory changes on every candidate, not only edits to `.gleam`/`.lean`: additions, deletions, renames, generated files, macros/code generation, interface schemas, configuration, feature flags, dependencies/lockfiles, compiler/prover versions, build scripts, release manifests, packaged artifacts, startup parameters, runtime configuration, and ownership or permission changes. Derive affected mappings from the actual JJ candidate diff and dependency/call graph. Recompute the impact closure; mark all dependent model/test/evidence records stale until rebound.

Every candidate change journal MUST retain the exact 13 SC-JOURNAL-v3 headings and explicitly bind the following content. The seven engines are mandatory epistemic roles, not assertions that specific software engines are currently running:

| Journal section | Model/code synchronization record | SC-JOURNAL-v3 engine(s) |
|---|---|---|
| 1. Scope & Trigger | Candidate, affected aspects/layers, trust boundaries, Sa-plan/risk scope | Engine 5 — formal scope |
| 2. Pre-State Assessment | Prior code/model/test/toolchain hashes, freshness, assumptions and evidence age | Engine 7 — forecast baseline |
| 3. Execution Detail | Exact edits, mapping rows, commands, outputs and receipts | Engine 6 — Rete-UL invariant consistency (role required; running engine not assumed) |
| 4. Root Cause Analysis | Competing hypotheses and disconfirming evidence; incident vs prospective gap | Engine 1 — ACH |
| 5. Fix Taxonomy | Structural prevention, containment, recovery, reuse and waste avoided | Engine 6 — Rete-UL fix/invariant alignment (role required; running engine not assumed) |
| 6. Patterns & Anti-Patterns | Counterexamples, negative controls, misuse and falsifiers | Engine 4 — Devil's Advocate/red team |
| 7. Verification Matrix | Property/model/test/evidence map, tool pins, bounds, grade, result and residuals | Engine 2 — Admiralty; Engine 5 — formal |
| 8. Files Modified | Exact JJ write set including add/delete/rename/generated artifacts | Engine 6 — Rete-UL provenance consistency (role required; running engine not assumed) |
| 9. Architectural Observations | Code/model relationship, assumptions, unsupported edges and abstraction gaps | Engine 5 — formal consistency |
| 10. Remaining Gaps | Every HOLD/UNKNOWN/STALE/UNRUN/UNMAPPED item and owner | Engine 4 — falsification |
| 11. Metrics Summary | Measured cost, latency, throughput, reliability, denominator and calibration | Engine 3 — Bayesian/decay; no fabricated Lyapunov values |
| 12. STAMP & Constitutional Alignment | Hazards, safety constraints, controller, feedback, all four UCA types and FMEA residuals | Engine 6 — Rete-UL control-loop invariant (role required; running engine not assumed) |
| 13. Conclusion | Scoped conclusion and precommitted falsifiable forecast/horizon/Brier rule | Engine 7 — forecast |

Use the journal linter as a structural check only. Its pass does not establish model correctness, source synchronization, runtime enforcement, or system admission. If an engine, metric, source, or gate is unavailable, record the exact limitation and status; do not create synthetic passing evidence.

## 6. Risk, tests, metrics and feedback

Before implementation or release, record raw FMEA severity, occurrence, and detection as ordinal values only where the approved scale and evidence justify them. Otherwise use `UNKNOWN`; do not calculate a composite score or imply calibration. Record hazards and system-level safety constraints, controllers/responsibilities, feedback channels, and all four unsafe-control-action types: required control action not provided; unsafe action provided; correct action at wrong time/order; and action stopped too soon or applied too long. Include actual candidate examples and disconfirming evidence. Use RCA/ACH for observed incidents, with competing hypotheses and evidence; do not write a cause as fact when evidence only supports a prospective risk.

Test properties as well as product properties. Each test should define an independent oracle, input domain, expected verdict, bounds, toolchain, reproducibility, and the implementation path it observes. Validate positive witnesses, negative/contradictory controls, boundary behavior, stale/unknown status, and explicit coverage assumptions. Keep deterministic unit/property checks, BDD journeys, fuzzing, authorized isolated failure simulation, recovery, performance and soak tests as separate evidence scopes. Never run destructive or live-environment testing under this SOP; any specialized failure scenario needs its own authorized isolated plan. Test count, timing, or green status does not prove test adequacy or refinement.

Performance and cost claims require a declared workload, baseline, candidate revision, environment, collector, sample count, uncertainty interval, resource/cost source and success threshold. Report measured values separately from model-derived bounds. Forecast probability and resolution criteria before observing outcomes; compute Brier scores only after the specified horizon and retain calibration population and denominator. Do not silently change baselines, thresholds, samples, or metrics. Feedback may adjust only typed, pre-authorized parameters within their recorded range; stale/unknown telemetry blocks scale-up and cannot increase privilege, budget, or release authority.

## 7. Gate sequence

These are proposed admission stages. Until a corresponding owner, implementation, current evidence and independent review exist, each gate is documentation only and must be reported `UNIMPLEMENTED`.

### 7.1 Change gate — isolated development

1. Bind task and authorized scope through Sa-plan before task mutation or effect work. Record repository/JJ baseline, source owners, exact toolchain, dependency, configuration and runtime package pins.
2. Compare the complete candidate diff for additions/deletions/renames, generated source, interfaces, flags, dependencies, build/release/startup files, and ownership/effect changes. Create/update the model-mapping impact closure; no file class may be silently ignored.
3. Produce or update the four model classes and map every changed effect/function/constructor to model element, invariant, test, independent oracle and evidence artifact. Unsupported/missing cells => `HOLD`.
4. Run only scoped development validation that is authorized and safe: compilation, relevant unit/property/BDD checks, appropriate formal proofs and independent witness/negative-control evaluation. Pin every invocation to the exact candidate and preserve failures.
5. Reconcile formal source/model hashes, axiom/assumption audits, runtime/package hashes and test evidence. A mismatch or stale/UNKNOWN required dependency blocks the affected operation; repair the evidence before proceeding.

### 7.2 Merge gate — candidate integration

1. Use standalone JJ only. Bind base, candidate, operation and full changed-path manifest. Recompute model/test impact against the integrated candidate; do not copy a green result from a prior revision.
2. Require all applicable mappings resolved, formal and test evidence fresh, no unresolved `sorry`/`admit`/axiom, all standard axioms declared, failed cases retained, journal complete, risk review current, and independent candidate-bound verification.
3. Serialize integration gates and respect ownership/delegation boundaries. A merge approval is not release, task completion, production or deployment authority.
4. Missing/unsupported/not-applicable-without-rationale cells, compiler/prover drift, unowned generated code, or changed package/config hashes => `HOLD`; no force-pass or EV mint.

### 7.3 Release gate — exact artifact

1. Rebind source, models, proofs, tests, dependencies, configuration, build flags, generated artifacts, compiler/prover versions, release package and operator-approved release state to one immutable candidate and artifact hash set.
2. Independently verify the model assumptions, proof scope, implementation mapping, security boundary, permissions, supported capabilities and rollback/reconciliation plan. Require scoped FMEA/STPA/RCA, all applicable 17-aspect evidence, journal and checklist, with residual risk explicitly accepted by the authorized owner.
3. Require observed backend behavior and performance/cost evidence for any empirical claim. Model arithmetic and finite abstraction results remain labeled as such.
4. Require separate human/authorized state and release authority. No SOP, linter, Lean result, peer ACK or model response itself authorizes deployment.

### 7.4 Startup and runtime drift gate

1. At startup, attest the loaded binary/package, model/proof/test mapping, dependencies, configuration, flags, identity, authority source, time/freshness, and required collectors against the release record. Report the exact runtime identity and hashes.
2. An eventual drift monitor compares source/release/runtime configuration and artifact identity, toolchain and dependency records, current policy version, freshness windows and active interfaces with the admitted mapping. Only call it active after unique collectors, coverage, failure semantics and effect-time behavior are independently observed.
3. On mismatch or missing/stale evidence, block new effects in the affected scope, including effects from previously authorized tasks; do not grandfather them through stale evidence. Already-in-flight work requires separately authorized, scoped containment or recovery. Preserve unknown liabilities and capacity reservations while resolving it. Do not issue an unapproved global shutdown, revoke unrelated leases, kill unrelated processes, cancel unrelated Sa-plan work or mutate release state. Escalate to the authorized controller/operator and record a HOLD/UNKNOWN event.
4. Rollback or recovery is itself an effect: it requires the correct authority, scope, idempotency, current artifact, recovery preconditions and evidence. Reconcile actual process state, durable task/effect record and billing/liability before releasing capacity or retrying. If cleanup or outcome is unknown, retain the reservation/liability and block duplicate effects until a separately authorized, evidence-backed resolution.

## 8. Acceptance checklist

A model/code synchronization slice is ready for independent review only when all applicable items are checked with evidence:

- [ ] The exact JJ candidate, source and generated-file diff, toolchain, dependencies, configuration and artifact identities are pinned.
- [ ] All affected system aspects and L0–L9 coordinates have explicit, versioned mappings or reviewed scoped non-applicability rationales.
- [ ] Every changed implementation function/constructor/effect and test is mapped to a model property and independent oracle; no mapping is omitted.
- [ ] Ontology claims include nonempty witnesses and meaningful negative controls; runtime claims include bounded/reachable safety properties and declared liveness assumptions.
- [ ] Formal output has no `sorry`, `admit`, undeclared assumptions or hidden standard axioms; solver results have independent witness/oracle checks.
- [ ] Refinement is proved or correspondence is explicitly bounded, differential, candidate-bound and not called equivalence.
- [ ] Test models document test assumptions, oracle independence, coverage limits, deterministic reproduction and failure evidence.
- [ ] FMEA/STPA/ACH, uncertainty, evidence freshness, residual risks, performance/cost claims and any forecast are honest and scoped.
- [ ] All 13 journal sections and seven engine roles are represented; structural linter output is not treated as semantic proof.
- [ ] No required item remains `UNKNOWN`, `STALE`, `UNRUN`, `UNMAPPED`, `UNSUPPORTED` or unexplained `NOT_APPLICABLE`; otherwise status remains `HOLD`.
- [ ] An independent reviewer verifies the same candidate and evidence bundle; separate release/startup authorization remains required.
- [ ] No new EV is minted; EV-93 ceiling and provenance restrictions remain respected.

## 9. Phased implementation plan

1. **Inventory only:** establish a revision-bound source/module/effect/dependency/config map for the 17 aspects; record owners, unknowns and current gate/collector presence. Do not claim complete coverage from documentation.
2. **Formal baseline:** select technique per property; validate candidate ontology satisfiability and non-vacuity, negative controls, runtime transition invariants, assumption/axiom reports, and independent oracles. Reuse existing model files only after checking current hashes and semantic applicability.
3. **One vertical slice:** choose one bounded, non-destructive capability from ontology through Gleam/MCP boundary, Sa-plan fence, test oracle, receipt, journal and runtime observation. Compare the actual implementation trace with its model; keep unsupported paths explicit.
4. **Report-only impact tooling:** derive invalidation from JJ diffs and manifests; report missing/stale links and verify mapping consistency without granting action authority. Measure false negatives/positives against a separately built fixture corpus.
5. **Authorized gate rollout:** after independent review, add narrow development/change gates with explicit owner and rollback. Observe bypass/refusal behavior before considering merge/release gates. Integrate release/startup drift checks only after artifact attestation, safe scoping and recovery are verified.
6. **Staged activation:** consider production only after separate release/state approvals, independent candidate-bound verification, startup/rollback evidence, required 17-aspect coverage and live observable enforcement. Ratchet scope one validated slice at a time.

## 10. Success criteria and falsifiers

**Success for a slice:** every changed effect has a fresh, typed, candidate-bound code→model→property→test→independent-evidence path; proof/test assumptions and omissions are explicit; negative controls detect intentionally invalid model inputs; permitted traces agree within the declared refinement bound; stale or unsupported scopes hold before effect; rollback/reconciliation is authorized and evidenced; and an independent reviewer can reproduce the bounded claim from retained artifacts.

**Falsifiers:** a source/config/dependency/build change does not invalidate the mapping; a test passes without exercising the named implementation path; an unexplained constructor divergence appears within the declared validity/refinement relation (while intentional over-approximation may admit additional abstract states); a claimed ontology constraint lacks a modeled element or required satisfying witness; proof relies on hidden axioms; a solver witness fails independent evaluation; stale evidence still permits effect; a runtime artifact differs from its accepted pin; drift monitoring misses a required surface; or rollback changes unrelated state. Any falsifier returns the affected scope to `HOLD` and requires RCA/ACH and evidence repair. Passing one gate never implies all other aspects or lifecycle stages pass.

## 11. Current status and limits

This SOP was authored as a proposed policy artifact only. No source code, Lean model, gate, runtime collector, test, service, provider, task, database, Sa-plan plan, release artifact or production setting was changed by authoring it. This new file is a JJ working-tree change; no integration/main bookmark moved, and no production, release or live effect occurred. No live publication or enforcement was checked. Existing model files and receipts are candidate evidence only and must be revalidated against the exact future implementation revision. Formal theorem counts, model sizes, test totals, cost samples and performance figures are never portable across candidates without explicit hash and scope matching.

Local references for future applicability checks include `formal/lean/Traceability.lean`, `formal/lean/DevelopmentCoreGate.lean`, `formal/lean/AgenticJournal.lean`, `apps/cepaf_gleam/src/cepaf_gleam/harness/agent_capabilities.gleam`, `harness/admission.gleam`, `harness/operations.gleam`, `harness/successor_mcp.gleam`, and the corresponding `tools/ecology_budget.ml` / `tools/ecology_process.ml` boundaries. These paths identify candidate source material; they are not claims that their semantics are current, synchronized, runnable as gates, or production admitted.

## 12. Governance

Follow canonical AGENTS policy, SC-HARNESS-MCP-001, SC-SA-PLAN-001, SC-JIDOKA-001, SC-JOURNAL-v3, SC-DIAGRAM-001, applicable risk contracts, standalone JJ rules and the relevant release assurance SOP. Imported/global skills and external source trees are not UOS authority. Preserve historical text and failed evidence; add timestamped corrections rather than rewriting a result's history. Keep provider/model/runtime identities separate and never invoke an external model as an implicit verification step. Direct review remains an operator-authorized external/provider effect only when the needed MCP interface is unavailable, with possible cost recorded as observed or `UNKNOWN`; it conveys no task, runtime, release, or deployment authority.

UOS footer: this proposed process does not establish runtime enforcement or system admission. No EV number is assigned; EV-93 remains the admitted ceiling.

[[wiki:20260905-1801-uos-zk-km-corpus-index]] · [[zk:20260905-1801-moc-uos-unified-master]]

## 13. Scoped six-domain checklist (this draft only)

These entries report only this document's local scope. They do not inherit historical green claims or establish repository-wide status. `UNRUN` means no check was executed; `UNKNOWN` means evidence/applicability is unresolved.

| Domain / IDs | Scoped status |
|---|---|
| Domain 1 — CHK-01-TIME | Prefix `20261101-0712` and observed authoring time are present in this draft; independent timestamp linter **UNRUN**. |
| CHK-02-TAIL | Intended FQDN locator is present; live serving/link verification **UNRUN**. |
| CHK-03-FRACT | L0–L9 tags are present; tag correctness review **UNRUN**. |
| CHK-04-KM | Wiki/MOC transclusion identifiers are present; reciprocal index/writeback **UNRUN**. |
| Domain 2 — CHK-05-MUDA | No source/dependency change in this authoring task; full purity scan **UNRUN**. |
| CHK-06-GRAPH | No NIF/runtime audit performed; **UNKNOWN/UNRUN**. |
| CHK-07-DRIVE | No drive action performed; host interlock status **UNKNOWN**, verification **UNRUN**. |
| Domain 3 — CHK-08-C1C8 | Applicability and UI evidence **UNKNOWN/UNRUN**. |
| CHK-09-MATH | This prose draft was not proved; artifact-specific formal checks **UNRUN**. |
| CHK-10-9MOD | No modality suite run; **UNRUN**. |
| CHK-11-REGR | No regression suite run; **UNRUN**. |
| Domain 4 — CHK-12-GLEAM | No Gleam/OTP runtime observation; **UNKNOWN/UNRUN**. |
| CHK-13-HERMES | No Hermes invocation/runtime observation; **UNKNOWN/UNRUN**. |
| CHK-14-ZIGVM | No ZigVM runtime observation; **UNKNOWN/UNRUN**. |
| CHK-15-MAX | No inference service observation; **UNKNOWN/UNRUN**. |
| CHK-16-OTEL | No live trace/collector observation; **UNKNOWN/UNRUN**. |
| Domain 5 — CHK-17-SOV | Independent sovereign review/admission **UNRUN**. |
| CHK-18-JJ | No mainline/integration movement or native Git mutation was part of this authoring scope; full repository JJ-purity verification **UNRUN**. |
| Domain 6 — CHK-19-CEIL | Draft acknowledges EV-93 ceiling; repository-wide claim audit **UNRUN**. |
| CHK-20-INDEX | Corpus completeness/reconciliation **UNRUN**. |
| CHK-21-PRESERVE | No historical source edit intended; byte-comparison verification **UNRUN**. |
| CHK-22-CHAIN | Coordinator chain verification **UNRUN**. |
| CHK-23-NOMINT | No EV minted by this documentation task; broader ledger check **UNRUN**. |
| CHK-24-FAILCLOSED | Runtime metric-path fail-closed behavior **UNKNOWN/UNRUN**. |

Checklist source: [`SC-CHECKLIST-001` — intended URL, live serving unverified](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/comprehensive-checklist-contract.md). This scoped table records status; it does not claim a global checklist pass.
