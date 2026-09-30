# Codex mainline merge planning journal

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l8 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Plan](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/superpowers/plans/20260908-1418-codex-mainline-consolidation-plan.md) · [Census](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/reviews/20260908-1418-codex-mainline-census.json) · [Validation](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/reviews/20260908-1418-codex-mainline-plan-validation.json) · [Journal](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/journal/20260908-1418-codex-mainline-merge-planning-journal.md)

Host-observed session opened 2026-09-08 14:39 UTC. Prefix 20260908-1418 uses assessment-start UTC hour and seconds (14:40:18). Validation receipts carry their own later UTC observations.

## 1. Scope & Trigger

Operator requested a plan to merge all Codex-managed code into mainline. This side-conversation task creates a complete observed census, dependency/risk-ordered plan and verification/recovery obligations. It does not execute the proposed integration or deploy services.

Canonical plan: `uos/codex-mainline-merge/20260908-1439`; task `PLAN`; worker `codex-merge-plan`; attempt 1. Session `codex-merge-plan-20260908-1439` owns only `/home/an/NAS-setup/uos/.uos-workspaces/codex-merge-plan-20260908-1439`. No subagents were used.

## 2. Pre-State Assessment

Pinned main `1be8029d72bc9530b1937564a37c555bd0b4b938` at JJ operation `3f75a63b43a634c3c3c7a09e90937fb187eabf3a126f6673d75a8668ae28d27544820b13673e5958cac431279445c77050938745109f09bb29329fe083d455aa`. The census found 72 source records (26 bookmarks, 46 workspaces), 66 distinct heads and 14 distinct non-empty commits outside main. Sixteen heads / 18 source records reach those outside commits. Existing source writers and unsnapshotted bytes were not frozen by this task.

Historical test/admission prose is not a fresh runtime result. The installed Sa-plan binary reports 0.3.0 while source advertises 0.4.0; task completion syntax differs. Source-bound authority verification is an explicit execution prerequisite.

## 3. Execution Detail

Read governing planning/risk/workspace skills and contracts. Registered this canonical planning task and logical coordinator session, recorded selection/risk, acquired only the own-workspace lease and sent scope/heartbeat observations.

Queried bookmarks, workspaces and ancestry at one immutable JJ operation. Compared all outside changes' touched paths against main, checked same-change variants and inspected affected authentication, release, manual UI and Mirage reviews/code. Captured full machine-readable records and raw listings.

Created the nine-stage plan M0–M8 as documentation only. No future execution tasks, Oban jobs, workflows, integrations or runtime work were dispatched. Structural checks cover 12 census/DAG/risk invariants. A Tailnet HTTP check returned the intended plan title and pinned main identifier; this is a document-content probe, not a GUI/browser test.

## 4. Root Cause Analysis

The main source of ambiguity is treating mutable bookmark names, shared change IDs and old test counts as evidence of code equivalence. Empty workspace tips can hide non-empty outside ancestors. Two same-change release variants differ substantially, including 253 historical evidence paths in one interdiff.

The manual executable/document variants have equivalent patches, but their receipts remain bound to older full candidates. Legacy NIF ABI failures and later green-suite claims require a common current provisioning baseline before deciding whether source or environment is responsible.

## 5. Fix Taxonomy

This change is planning/provenance documentation only. It introduces a pinned census, per-delta packet assignments, explicit semantic dispositions, ordinal risk ordering, a dependency DAG, stage-specific acceptance tests, safe landing/recovery rules and truthful completion criteria.

Setup required a local correction: workspace-add with ignore-working-copy left an incomplete own workspace. The base tree was restored only in that new workspace, its parent corrected, and only the own intermediate root change was abandoned. Main and peer workspaces were preserved.

## 6. Patterns & Anti-Patterns Discovered

Positive pattern: freeze source identity, compare semantic deltas, preserve historical evidence and verify the composed candidate before changing main. Negative patterns: blindly merge every named bookmark; assume shared change IDs imply equal patches; retag old receipts after reparenting; classify a fresh sibling's missing NIF as a source regression; treat an empty working tip as no work.

A final risk-check invocation initially supplied the plan ID where the CLI expects a task ID. It correctly returned HOLD. The actual usage was inspected; using task PLAN produced ACTIVE_OBSERVATION_PASS. A stale coordinator heartbeat also blocked a lease check; heartbeat renewal preceded a successful own-fence check. No dependent mutation was performed between either rejection and its resolution.

## 7. Verification Matrix

| Check | Observed result | Scope/limit |
|---|---|---|
| Immutable JJ census and outside-ancestor union | 72 records, 66 heads, 14 outside non-empty changes | Owner-dirty/unregistered work still needs M0 evidence |
| Same-change path comparison | Differences preserved in census | Difference is not automatically a regression |
| Manual source/docs interdiff | Both empty | Patch equivalence only, no new runtime receipt |
| Plan structure/DAG/risk arithmetic | 12 checks passed | Does not validate code behavior or authorize integration |
| Native risk active check | ACTIVE_OBSERVATION_PASS at 15:01:18 UTC | Report-only observation; authority NONE |
| Own workspace lease check | Epoch 1 / correct session observed at boot-us 332215170000 | Cooperative fence observation, not an executed effect |
| Host time check | Chrony stratum 3, absolute offset about 0.000215 seconds | UTC, monotonic and Lamport fields remain distinct |
| Tailnet plan content | HTTP 200, intended title and main identifier present | Not a browser, GUI, TUI or staging-runtime regression test |
| Source/runtime integration | NOT_RUN | Only a plan was requested |
| Independent final merge review | NOT_RUN | Required in future M6 before M7 |

Exact data, commands, failures and corrected checks are retained in the validation record. Final source status and hashes are recorded after artifact creation.

## 8. Files Modified

Only new files in the owned sibling:

- `docs/superpowers/plans/20260908-1418-codex-mainline-consolidation-plan.md`
- `docs/reviews/20260908-1418-codex-mainline-census.json`
- `docs/reviews/20260908-1418-codex-mainline-bookmarks.txt`
- `docs/reviews/20260908-1418-codex-mainline-workspaces.txt`
- `docs/reviews/20260908-1418-codex-merge-plan-active-risk.json`
- `docs/reviews/20260908-1418-codex-mainline-plan-validation.json`
- `docs/journal/20260908-1418-codex-mainline-merge-planning-journal.md`

Canonical runtime administrative changes are limited to this task's Sa-plan records and its own coordinator registration, lease, heartbeats and compact report. No application source, peer revision, deployed package, live service or main pointer was intentionally modified.

## 9. Architectural Observations

Ancestry coverage, patch equivalence, behavior preservation, formal evidence, runtime execution and admission are separate relations. A complete consolidation needs all applicable relations, not a bookmark-count reduction.

The current checklist contract adds six provenance checks to the original 18; the plan retains all 24 as obligations. The 17-aspect matrix records what future evidence is required rather than borrowing historical green badges. Sa-plan remains the sole execution authority; the JSON DAG is a non-executable specification.

## 10. Remaining Gaps

Owner-frozen dirty work, unregistered/abandoned work attribution, current Sa-plan binary/source equivalence, common ABI baseline, four source-packet reconciliations, fresh auth/manual/runtime/Mirage tests and final independent review remain outstanding. All eight historical S13 findings need candidate-specific disposition.

No whole-system stabilization, production update, clock repair, swarm launch or merge is claimed. No further work is authorized by merely opening this plan.

## 11. Metrics Summary

72 source records; 26 bookmarks; 46 workspaces; 66 heads; 16 heads / 18 records with outside non-empty ancestry; 14 unique outside changes; four source packets; nine proposed stages; 12 structural checks passed. Zero subagents, native Git commands, new packages, code merges or runtime cutovers.

Planning risk score: 4 × 4 × 4 × 4 × 4 = 1024, P1. Stage priorities are separately documented, including FMEA severity floors; they are ordinal analyst judgments, not calibrated forecasts or global cost-optimum claims.

## 12. STAMP & Constitutional Alignment

Controller: planner now, authorized integrator at execution. Unsafe actions considered: omit needed source preservation, provide an unverified main update, act after source/ownership changes, or hold/write beyond a valid lease. Controls: immutable census, source disposition ledger, candidate-bound gates, own-workspace rules, fresh task/fence checks and serialized main movement.

Formal/model/board observations remain advisory; none grants side effects. Historical source and failed evidence are preserved. No new EV is minted. Storage interlock, language boundaries, Tailnet navigation and existing admission rules remain in scope for future verification.

## 13. Conclusion

A reviewable plan and pinned census are prepared for the next authorized integration session. The intended execution is source freeze and trustworthy tooling, bounded authentication/release/manual UI/Mirage reconciliation, full composed verification, serialized main landing and documented synchronization. Main and production remain outside this planning task's mutation scope.

<details>
<summary>Verification obligations — 5 original domains / 18 checkpoints, plus the current provenance domain / 6 checkpoints</summary>

These checkboxes are execution obligations, not assertions that the system is green. The pinned checklist contract has expanded to 24 items; retain the original 18 and the additional six. Historical counts and badges are not fresh receipts.

**Domain 1 — Metadata, timestamp and navigation**
- [ ] CHK-01-TIME: Observed UTC and timestamp-prefix validation; distinguish NTP offset, duration and Lamport order.
- [ ] CHK-02-TAIL: Actual Tailnet FQDN links resolve to intended content, including the staging origin.
- [ ] CHK-03-FRACT: Correct L0–L9 scope tags, without padding tags to manufacture entropy.
- [ ] CHK-04-KM: Wiki/ZK references and backlinks are resolved against the observed corpus.

**Domain 2 — Purity and storage**
- [ ] CHK-05-MUDA: No prohibited Bevy/Graphite source or dependencies introduced.
- [ ] CHK-06-GRAPH: Preserve pure BEAM/Hermes mathematics and existing native boundaries.
- [ ] CHK-07-DRIVE: Storage interlock unchanged; no host storage allocation or wipe in this plan.

**Domain 3 — Testing**
- [ ] CHK-08-C1C8: Applicable C1–C8 UI categories have candidate-bound evidence.
- [ ] CHK-09-MATH: Required entropy, coverage, trajectory and quality measures report truthful inputs and outcomes; no invented passing numbers.
- [ ] CHK-10-9MOD: Required unit/system/TDD/BDD/performance/scalability/property/fuzz/chaos obligations mapped; unavailable checks remain blocked.
- [ ] CHK-11-REGR: GUI/TUI regression scope and 30-second update observations verified for changed surfaces; old counts do not substitute.

**Domain 4 — Runtime and observability**
- [ ] CHK-12-GLEAM: OTP 29/ERTS identity, supervision, restart limits and routing verified.
- [ ] CHK-13-HERMES: OCaml evidence, bounded formal workers and storage behavior verified for affected boundaries.
- [ ] CHK-14-ZIGVM: Deterministic kernel/VFS boundaries preserved with explicit affected-scope evidence.
- [ ] CHK-15-MAX: MAX/Mojo/Python confinement and release-tool parity preserved; no new unsupervised inference role.
- [ ] CHK-16-OTEL: Fresh UTC, trace/span, identity, errors and stale observations propagate truthfully.

**Domain 5 — Review and version control**
- [ ] CHK-17-SOV: Required independent/peer reviews reference exact candidate and evidence; an ACK alone is insufficient.
- [ ] CHK-18-JJ: Standalone JJ, own-workspace discipline, serialized main update and required gates verified.

**Domain 6 — Provenance and admission**
- [ ] CHK-19-CEIL: Respect observed EV ceiling 93; no higher admission claim without authority.
- [ ] CHK-20-INDEX: Census and KM completeness measured against pinned input sets.
- [ ] CHK-21-PRESERVE: Historical/quarantine evidence preserved byte-for-byte with additive annotations.
- [ ] CHK-22-CHAIN: Canonical append-only chain and corruption rejection verified through supported native interfaces.
- [ ] CHK-23-NOMINT: No new EV numbers minted by this merge.
- [ ] CHK-24-FAILCLOSED: Missing tools, stale evidence or failed kernels yield UNKNOWN/HOLD/FAIL, never synthetic health.

</details>

