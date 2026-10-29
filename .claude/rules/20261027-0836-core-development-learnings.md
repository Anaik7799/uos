# 20261027-0836 — Core development learnings

- **Contract ID**: `SC-LEARN-001`
- **Domain**: Agent operating discipline for the Gleam harness, Sa-plan authority and evidence integrity
- **Authority**: operator directive 2026-10-27 ("update and add rules, skills, superpoers, plugins, agents etc based on learnings")
- **Tailscale FQDN**: [http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261027-0836-core-development-learnings.md](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261027-0836-core-development-learnings.md)
- **Status**: ACTIVE reference guidance. Grants no effect authority and no admission. Client adoption is **UNRUN**.

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #km-triad #tailscale-web

Transclusions: `[[zk:20260905-1801-moc-uos-unified-master]]` · `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

**Navigation:** [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist) · [Bindings](http://nas-1.tail55d152.ts.net:4100/files/governance/agents/20261027-0836-learning-bindings.md) · [Superpowers bindings](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md)

**Public evidence baseline, inspectable by a human.** Journals: [receipt-core](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-receipt-core-journal.md) · [mcp-core](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-mcp-core-journal.md) · [core-recovery-resume](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-core-recovery-resume-journal.md) · [core-control-review](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-core-control-review-journal.md). Reviews: [receipt-core peer](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-0745-receipt-core-peer-review.json) · [mcp-core peer](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-0745-mcp-core-peer-review.json) · [guidance grant review v2](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-0836-guidance-grant-review-v2.json).

## 0. What kind of document this is

The items below are **normative instructions motivated by observations**, not a list of facts. Each one cites a refusal, receipt or measured digest observed in this repository on 2026-10-27; the citation is the motivation, while the instruction itself is a judgement about how to work and could be revised by better evidence. Where a statement is purely factual, such as a decoder's type or a byte cap, it is marked as observed. This document installs nothing, loads nothing and enforces nothing.

## 1. Four states, never collapsed

`L-01`. Specification, model proof, runtime observation and admission are four different claims. A rule file is specification. A Lean theorem under declared assumptions proves something about a model, not about the running system. A green receipt is a runtime observation at one candidate. Admission requires two keys plus authority. `UNRUN`, `UNKNOWN`, `STALE` and `NOT_ADMITTED` remain nonpassing.

`L-02`. When the graph a model was built over changes, **recheck the model's closure and minimality claims** — do not conclude that its theorems became false. Theorems proved under declared assumptions remain proved under those assumptions; what lapses is the claim that the closure still covers the current graph. *Observed:* the 13-node closure was frozen on a 27-task graph, and both the 28th task (`GUIDANCE_REBIND`, an audit repair) and this guidance grant's mandatory review authority fall outside it. Report such a model as frozen and pending closure recheck, never as current functionality or current optimality.

## 2. Canary the core before ordinary changes

`L-03`. Verify the control surface itself before using it for ordinary work, with an isolated recovery path prepared. *Observed:* a grant that pins control modules is correct for reproducibility and simultaneously makes a fix to a control module unobservable by the process serving under it — `RECEIPT_FIX` attempt 1 produced a correct repair that only a later, separately granted activation could observe.

## 3. Evidence inputs are typed and bounded

`L-04`. Keep evidence JSON compact and within the observed 262144-byte `files.max_bytes` cap. *Observed:* a pretty-printed 295864-byte risk portfolio refused `attach` with `attachment_outcome_unknown:regular_single_link_file_bound`, deterministically and before any effect. When compacting, prove value equality with `jq -S -c` digests on both files rather than asserting it.

`L-05`. Use each field's actual type and precision. Three distinct cases, all observed, and precision is **not** banned globally:

| Field | Required form |
|---|---|
| grant `expires_utc_us` | decimal **string** of integral microseconds. The same value as a JSON number refuses at startup with `grant_decode` (`admission.gleam:200` decodes a string). |
| risk `ready_since`, `observed_at` | whole-second canonical UTC. |
| clock-observation UTC | **may validly carry fractional seconds**; do not strip or reject that precision. |

## 4. Retained bytes versus full bytes

`L-06`. A bounded diagnostic must publish the retained bytes, a digest **of those retained bytes**, the byte count on both sides of the bound, and an explicit statement of the relation. *Observed:* before repair the only digest hashed bytes the receipt did not contain — 8192 retained bytes digesting to `e019941e…` while the record claimed `5055476a…`. A full-output digest stays useful metadata but verifies nothing present on a truncated record. Disclose truncation; the dropped prefix remains unrecoverable, so a diagnostic whose signal lies in the prefix is still lost.

## 5. Fences, heartbeats and leases are three different things

`L-07`. Heartbeat immediately before each effect phase rather than waiting for staleness; *observed:* a write refused mid-task with `refused: session heartbeat is stale`. The three renewal scopes are distinct, as the receipt itself shows:

| Mechanism | What it renews |
|---|---|
| native coordinator heartbeat | the coordinator **session** only |
| `harness_heartbeat` with a task attached | the coordinator session **and** the active coordinator **task-lease**, via a `renew` on the task resource; the receipt carries `coordinator_renewal` |
| Sa-plan task lease | **not renewed by either.** The same receipt reports `sa_plan_renewal` as `NOT_IMPLEMENTED_RELEASE_AND_RECLAIM_BEFORE_EXPIRY` and exposes `sa_plan_lease_until_ns` |

With no task attached, `harness_heartbeat` returns the bare session heartbeat without the wrapper, so a reader expecting the wrapped shape sees absent fields rather than a failure.

## 6. Unknown outcomes reconcile, with an operation-specific oracle

`L-08`. Keep the stable logical effect identity for status lookup and reconciliation. While its outcome is unresolved, do **not** redispatch it or mint a new intent or grant to evade the stop line. The reconciliation oracle must be **specific to the operation attempted**. An unchanged source map is **not** sufficient evidence of no effect for any operation: even a byte-identical rewrite can carry side effects, such as mtime changes and whatever watchers or downstream readers consume them, and it says nothing about network, service or other physical effects. *Observed:* the known-no-effect verdict for a refused source write rested on the refusal occurring **pre-dispatch, before the file primitive was reached**, together with a terminal receipt naming `write_scope_refused`. That pre-dispatch fact is the evidence; the digest comparison was corroboration, not proof. `harness_reconcile` quarantines a dangling intent rather than resolving it. Never force-pass, and never represent a failure as a pass.

`L-09`. A **quarantined unknown is not retryable**: reconcile it to a known outcome first. Once an outcome is known, retry is governed by the actual policy and budget controls that apply, not by any fixed count — no blanket retry allowance is stated here or anywhere in source. This scopes retry of an unresolved effect and is **not** a ban on negative coverage: all required negative cases are preserved and expected. Isolate effectful fault cases with a planned recovery path, and prefer read-class or claim-class refusals where they test the same guard, because *observed:* a correctly refused out-of-scope write still records an `effect_unverified` receipt, trips the stop line, blocks later probes and clears the active execution.

## 7. Completion is a checked packet

`L-10`. *Observed:* `operations.finish` validates a **flat top-level** binding set and rejects nested equivalents as absent. The full set is `schema` exactly `uos.harness-task-verification.v1`, `plan`, `task`, `attempt`, `candidate_sha256`, `build_receipt_sha256`, `test_receipt_sha256`, `verdict` exactly `VERIFIED`, and `peer_review_path`/`peer_review_sha256` plus `formal_evidence_path`/`formal_evidence_sha256`, each review file re-verified against its digest. Run `tools/journal-check` and `tools/diagram-check` before `finish`, not after: a 13-section journal still failed on a missing `ACH` token and on box-art ASCII the diagram checker cannot verify.

Qualifier fields beside the bindings keep a claim precise; they **never** justify asserting `VERIFIED` when required scope is unfinished. If scope remains open the honest path is a partial artifact with its own non-`VERIFIED` verdict plus a release, not a completion packet.

## 8. Budgets, reuse and honest identity

`L-11`. Treat soft cost or size targets as drafting guidance, not safety gates, and do not spend cycles trimming below one when the real limit is elsewhere. Reuse existing tasks, receipts and evidence by reference instead of regenerating narrative or re-running solvers. Claim no global token, reliability or optimality optimum: no comparable cost and capability measurement supports one.

**Additive correction notice, recorded 2026-10-27 (`L-11`).** Two completed journals of this day state quantitative reliability claims that are **not admissible reliability evidence**: [`20261027-0745-receipt-core-journal.md`](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-receipt-core-journal.md) (sha256 `e0f35c15907fd862de50c4318f773343ed4c3123a1822e7064da9b1cb76a0bbd`) claims a 0.85 to 0.97 Bayesian posterior and `dV/dt <= 0` although its own V went 0 to 1 to 0; [`20261027-0745-mcp-core-journal.md`](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-mcp-core-journal.md) (sha256 `e7da6ab32cdd85757767bc205af9adfc74a12af0a9123baa83cf22762df40aeb`) claims 0.90 to 0.96 on a qualitative "unlikely" with no calibrated likelihood. In both cases there is no likelihood function, no data model and no independence argument, and scope qualifiers do not repair that. **No alternative posterior is offered**, because none can be computed without a data and likelihood model. Those journals' bytes are preserved unchanged and are outside this grant's write paths; this notice is additive and rewrites nothing. The raw evidence in both remains valid: the 84-test results, the source and receipt digests, and the replay observation.

`L-12`. Report provider identity and quota truthfully. A quota-blocked provider is recorded as blocked; never impersonate another agent, and never assert a Google or client success that was not observed. Report capability counts with their states — currently 65 declared, 53 unprobed, 12 unavailable, admission unknown — and refresh them before relying on them.

## 9. Limits of this contract

Reference guidance only. It installs nothing and enforces nothing; no plugin, hook or client is shown to have adopted it, so adoption is **UNRUN**. The natively connected 4-tool read-only surface **can read** this file; that establishes readability, not active client adoption.

The private reviewed harness **advertises 13 scoped tools**. The core workflow among them has been exercised — claim, attach, read, write, build, test, reconcile, release, finish, heartbeat, status — but **not all 13 are fully verified**, and exposure is not verification.

One **unprobed scope gap**, recorded for `PLANNING_MCP` and not worked around: `harness_assess` validates every assessment record path against the grant via `assessment_paths_allowed` (`operations.gleam:627`, called at `:678`). A full-portfolio assessment references `governance/planning/20261027-0634-hive-development-readiness-plan.json`, which exists (71312 bytes) but is **absent from this grant's read paths**, so such a call would be rejected. No `harness_assess` run was attempted, so this is a scope and configuration gap inferred from source, **not an observed failed run**, and nothing here is or should be bypassed. If a normal assessment mutation is not possible within an approved scope, report the gap rather than forcing the API.

Sa-plan remains the sole execution authority. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV number minted.


## 2026-10-29 — Fast-OODA Reconciliation: Lease Renewal, 15-Tool Successor Harness, Immutable Nix Backend, and Agentic Code Resilience (L-13..L-17)

Observed at `2026-10-29T07:45:00Z` under `SC-AGENTIC-RESILIENCE-001`. Prior `2026-10-27` observations `L-01`..`L-12` remain historical receipts; the following items record the current candidate truth on `main`:

- **L-13 (Supersedes L-06 release-and-reclaim workaround)** — Three-scope lease renewal is implemented in `apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam` (`renew_task` / `--task-renew`) and wired into `harness_heartbeat`, renewing the Sa-plan task lease, coordinator task lease, and coordinator workspace lease together (verified by 8/8 live MCP renewal proof `var/harness/20261028-2041-mcp-own-task-renewal-proof.json` and completed `uos/development-harness/lease-renewal/20261028-1317` `ACCEPT`).
- **L-14 (Supersedes L-10 13-tool count)** — The task-scoped successor development harness (`successor_mcp.gleam`, `operations.gleam`) advertises **15 scoped tools**: `harness_plan_intent`, `harness_status`, `harness_clock`, `harness_heartbeat`, `harness_claim`, `harness_attach`, `harness_release`, `harness_read_file`, `harness_client_mcp_config`, `harness_write_file`, `harness_build`, `harness_test`, `harness_assess`, `harness_finish`, and `harness_reconcile`. Total dispatch completeness is enforced by `every_declared_operation_has_schema_and_client_mcp_config_is_routed_test`.
- **L-15 (Immutable Host Nix CLI Backend)** — `native_backend.gleam` and `harness_native_backend_ffi.erl` validate `candidate_binding.native_backend` (`mode: "host_immutable_nix"`, `store_path: "/nix/store/mmycwn1v7bvpjgl0hxvbazxrqwjwn335-uos-sa-plan-main-cfe06ec3"`, 42,344,784 B, SHA-256 `cfe06ec3e54a6cca54e59d8f521d8ae903f0c8e4703c1d447fcf3fff5534cf91`, `0555` root-owned, `/nix` and `/nix/store` ancestor checks) with an atomic node-local CAS registry (`Absent -> Pending -> Ready | Failed`) that poisons on failure and forbids silent fallback.
- **L-16 (28 Compiled Control Modules & 44 Source Files)** — `admission.control_modules` pins **28 compiled BEAM modules** plus `control_dependencies = ["tools/ecology_process.ml"]` across **44 source files** (`harness_pre_attach_assessment_test`, `harness_successor_test`).
- **L-17 (Tri-Agent Fast-OODA & Token-Optimized Execution)** — Overall supervision runs on `gemini-4-argon` (`pi-agy`), mechanical/merge/test execution on `codex` (`gpt-6-luna`, `reasoning_effort=low`), and independent adversarial review on `claude` (`claude-opus-5`, `--effort low --tools Read`), merging verified isolated sibling workspaces frequently to `main` under serialized `integration/main` coordinator epochs.

## Comprehensive verification checklist

Checks below are obligations for work governed by this contract, not blanket passing claims for it. This is a documentation package: runtime items are **unchecked** because this document executes nothing.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — `YYYYMMDD-HHSS-` prefix present; host clock observed 2026-10-27.
- [x] **CHK-02-TAIL** — Full Tailnet links provided above; live serving status not asserted here.
- [x] **CHK-03-FRACT** — L0, L1, L3, L4, L9 tags assigned to the layers this contract governs.
- [x] **CHK-04-KM** — ZK and wiki transclusions plus journal and review links resolve to existing artifacts.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Dependency exclusion scan UNRUN by this package; no dependency introduced.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary UNRUN here.
- [ ] **CHK-07-DRIVE** — OS storage interlock execution UNRUN; no host serial appears in this document.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — UI categories not applicable to this package; UNRUN.
- [ ] **CHK-09-MATH** — The four mathematical gates UNRUN here.
- [ ] **CHK-10-9MOD** — Nine test modalities UNRUN here.
- [ ] **CHK-11-REGR** — UI regression monitoring UNRUN here.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Supervision behaviour not observed by this package; the cited refusals are harness observations recorded in the linked journals.
- [ ] **CHK-13-HERMES** — Bounded analysis and evidence ledger behaviour UNRUN here.
- [ ] **CHK-14-ZIGVM** — Deterministic kernel and VFS UNRUN here.
- [ ] **CHK-15-MAX** — Isolated inference UNRUN here.
- [ ] **CHK-16-OTEL** — Runtime telemetry correlation UNRUN here.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent review of this document is OUTSTANDING; NOT_ADMITTED.
- [x] **CHK-18-JJ** — Authored under standalone JJ discipline; no native Git mutation used.

</details>

<details>
<summary>Domain 6 — Provenance and admission integrity</summary>

- [x] **CHK-19-CEIL** — EV ceiling 93 stated; EV-94..109 marked NOT_ADMITTED; no EV claim made.
- [ ] **CHK-20-INDEX** — KM index enumeration of this new record UNRUN.
- [x] **CHK-21-PRESERVE** — Additive only; no historical artifact rewritten, and the v1 grant failure is preserved.
- [ ] **CHK-22-CHAIN** — Cycle-chain verification UNRUN by this package.
- [x] **CHK-23-NOMINT** — No new EV number minted.
- [ ] **CHK-24-FAILCLOSED** — Metric-path fail-closed runtime behavior UNRUN in this documentation scope; no passing claim.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this contract grants no admission.
