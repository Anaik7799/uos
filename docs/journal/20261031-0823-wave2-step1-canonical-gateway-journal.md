# Wave 2 Step 1 — canonical gateway wiring ledger

V01 remediation observation: 2026-10-31T10:02:55Z from the host UTC clock. NTP synchronization observation is unavailable because the sandbox denies the system bus. The original Step 1 record below is retained as historical evidence; current V01 notes supersede its completion and regression claims for this candidate.

Observed: 2026-10-31T08:37:23Z. Development evidence; system admission NOT_GRANTED.
Sa-plan: `uos/mcp-canonical-completion/20261031-0327-v2`, tasks `P01_VAULT_AND_FEATURE_RECEIPT_LEDGER` and `C02_GATEWAY_WIRING_POST_R07`.

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

## 1. Scope & Trigger

**V01 remediation round.** The operator authorized only twelve existing Gleam files, this existing journal and one summary receipt, with zero Jujutsu or Git commands. Scope covers H-01; M-01 through M-08, M-10, M-11; and L-01 through L-05, L-08, L-11, L-13, L-16, L-17 as explicitly enumerated in the request. No production authority, fresh task claim, external source admission or new EV identifier is inferred. The existing Sa-plan V01 review context remains the task locator; live Sa-plan mutations are outside this file fence.

Historical Step 1 record:

The operator requested subagent execution of P01 completion, C02 claim, six canonical gateway seams, comprehensive OTP29 regressions, and truthful digest receipts. Source changes remain in the codex sibling development workspace; no production release or VCS mutation is authorized. Formal Lean/Gospel gateways are UNRUN for this slice; no theorem or system admission is inferred from EUnit.

## 2. Pre-State Assessment

**V01 prior.** Source inspection confirmed actor receipts overriding disk, optional public grant pins, unqualified holds, missing hierarchical plan names, quadratic deduplication, broad secret-name rejection, and the system SQLite fallback. Baseline SHA-256 values were captured for all nine protected files before edits. The configured Nix profiles contain no SQLite entrypoint. A realized Nix SQLite 3.53.3 executable is bound only through temporary EUnit SQLite fixture profiles under /tmp; the production resolver remains unavailable if its configured entrypoints are absent. Kalman state and NTP offsets remain UNMEASURED.

Historical Step 1 record:

At 08:34Z P01 was executing on Pi attempt 1, C01 completed, and C02 available. The P01 lease exceeded the 300-second renewal threshold. Both portfolios retained a stale C02 blocked decision. The protected candidate identity source file had byte SHA `5f11b5f9dbc94f464370ff10887717e72fb0f9fde320228f908e4c84bc95a9fa`; the operator-provided `5fb7...1663` is its computed six-source candidate identity, observed directly under OTP29, not its file SHA. Kalman state prior is unmeasured; do not interpret task counts as runtime stability.

## 3. Execution Detail

**V01 RED to GREEN.** Three live-ledger falsifiers first failed on stale memory receipts. Eight ledger and vault probes failed on unavailable-tool promotion, ceiling drift, pin attribution, path normalization, ancestor traversal, item caps and redaction. Independent public-grant probes failed on missing pins, uppercase pins and unnormalized paths. Planning probes then failed on stale held leases, dependency discovery subprocess count, default zero schedules, missing plan names, NULL lifecycle state and journal-sidecar guard timing. The 2,000-ID performance case is an additional budget regression; it already met the budget before remediation and is not represented as an initial RED.

Disk now owns capabilities, receipts, completions and the ceiling; only actor intents merge after a clean reload. Grant pins require exact lowercase SHA-256 bytes, and an optional ledger pin binds authenticity to the loaded projection. A missing pinned ledger quarantines. A shared bounded reader caps allocation despite growth after the size check; the path guard traverses every existing ancestor to slash and refuses errors. Holds bind worker, attempt and a live lease without task foreign keys. Writes use one combined schema/dependency discovery plus one transactional subprocess. A numeric SQL clock sets default scheduling, names and fingerprints support canonical CLI parity, and a NULL state cannot authorize a transition. Backend configuration uses a typed variant plus a canonical-required check rather than a NUL key.

The new remediation fixtures use /tmp for SQLite test copies and fixture toolchains. Vault-only remediation fixtures use the existing application build tree and are cleaned by their tests. The inherited mandatory broad suites also perform non-SQLite temporary-directory probes; those definitions are outside the source allowlist. This prevents a blanket claim that every inherited test effect satisfied the temporary-file fence. The actual canonical database is read only as operator-authorized fixture input; MCP and CLI writes target copies. No package is fetched or installed. SQLite 3.53.3 exposed a command-line behavior difference: timeout setup now lives in the query script. Typed nonzero refusal output is decoded independently of version-specific rollback wording; timeout and uncertain success remain reconcile-first.

Historical Step 1 record:

Rebuilt the Pi package and observed 45/45 EUnit checks: ledger 33, feature acceptance 8, vault metadata 4. Refreshed both risk portfolios; P01 active-check passed, then canonical Sa-plan completed P01 attempt 1 with observed full digests. C02 preflight initially returned HOLD RP-SELECTION because its readiness remained blocked. Preserved both prior portfolios in `/tmp/20261031-0836-*.before`, repaired only the codex-owned C02 readiness/blocker/decision fields from observed completed dependencies and explicit post-R07 operator instruction, refreshed again, and obtained PREFLIGHT_PASS. Claimed C02 attempt 1, lease `1793439368549143510`, and obtained ACTIVE_OBSERVATION_PASS at 08:36:10Z.

Copied the five verified P01 files into the codex workspace and added bounded read-only `load_task_fence_row`. Automatic review rejected an `rm -rf` generated-directory cleanup with reason "rm -f style commands are not permitted. Use a safer approach". No command in that rejected shell call executed. Moved both generated C01 directories reversibly to `/tmp/20261031-0838-c02-generated-build-quarantine`; source files were preserved. Gateway and test subagents own separate files. Rete-UL invocation is UNRUN; consistency is checked through task fences and explicit receipts, without claiming runtime scheduler enforcement.

Expanded tests exposed a real replay defect: a cached in-memory feature intent could replay a previous success after the newly loaded disk ledger became quarantined. The gateway now checks the fresh feature ceiling before reservation or receipt replay, while retaining the pure actor handler. The first full fourteen-suite attempt then exposed an obsolete resilience test that accepted only `AvailableStore`; it now requires `MultiPlanStore` with the exact plan, one real row, executing state, worker, attempt, and per-plan counts. Its 0.25-second exclusive writer lock and completion budget remain intact; the focused suite then passed 29/29. Earlier failure logs are retained in `/tmp/uos-c02-final-eunit-20261031/attempt1/` and the replay RED logs are retained separately.

Further observed RED tests proved that reused read intent IDs could hide a vault seal/unavailability, new verified feature receipts, or updated canonical planning counts. An initial broad bypass of receipt retention fixed freshness but caused seven existing resilience failures involving durable receipts, ledger capacity, actor/transport matrices, and foreign candidate refusal. The final fix preserves reservation, idempotency, capacity checks, candidate validation, uncertain effects, and durable receipt bookkeeping, and recomputes only validated live read payloads for vault, feature, and planning families. All 27 wiring cases pass with the receipt-preserving implementation. Attempt 4's seven failures are preserved under `/tmp/uos-c02-final-eunit-20261031/attempt4/`; deliberately interrupted attempts 2/3 remain explicitly marked paused.

C02's risk evidence originally referred only to canonical-root adapter context and inaccurately described the sibling as empty. Added all nine changed codex Gleam files to C02's evidence list (15 files including six root context files), corrected its snapshot reference, and preserved the prior portfolio. The operator's refresh script remains unchanged; the scoped binding repair is reapplied after each refresh so the executing task names its actual tested source bytes.

The receipt-preserving implementation restored durable receipt, capacity, and foreign-candidate tests; four remaining actor/transport matrix failures were traced to the canonical preflight receipt aging past its 900-second limit, not a gateway regression. A fresh actual 31/31 preflight was observed at 2026-10-31T08:58:44Z. Its scoped Bash wrapper allowed only the pinned Jujutsu version, file-list and log queries, adding a fixed operation and `--ignore-working-copy`. Before/after records for all 12,776 Jujutsu operation/store/working-copy files and checker/resolver bytes were identical. Evidence: `/tmp/20261031-0900-c02-safe-preflight`; receipt SHA `f8a4c1e4985b63af689e71d45bd2b49cc0c66bf0b7a44fbd17005d9a74a404d2`. No VCS mutation command or implicit snapshot occurred.

The required Gleam formatting changed whitespace in copied P01 files; the final codex hashes are separate from P01's original source receipt. A session-created `erl_crash.dump` (observed mtime 2026-10-31T08:37:06.816280954Z, size 3,283,599 bytes) was moved without reading or hashing to `/tmp/uos-c02-final-eunit-20261031/20261031-0806-development-erl_crash.dump`.

## 4. Root Cause Analysis

**V01 ACH extension.** H1: disk projection was absent. H2: actor receipt merging retained obsolete evidence. A passing disk read followed by a downgrade that still returned exit zero disconfirms H1 and supports H2. Removing receipt merging makes downgrade and deletion immediately visible. For holds, H1: the new worker lease is invalid; H2: an old hold lacks an attempt fence. A live second-worker attempt and the old hold disconfirm H1; matching worker, attempt and lease removes the false block. For broad regression failures, H1: every failure is a source regression; H2: environment and absent inputs contribute. Direct loopback eperm and the absent fifteenth module disconfirm H1. These observations do not prove that every remaining broad failure is environmental.

Historical Step 1 record:

ACH disconfirmation matrix (0 = consistent, 1 = contradicted):

| Evidence | H1: C02 has an unfinished dependency | H2: risk readiness decision is stale |
|---|---:|---:|
| Canonical C01/P01 completed rows | 1 | 0 |
| Portfolio still says wait for C01/P01 | 1 | 0 |
| Narrow repair yields PREFLIGHT_PASS | 1 | 0 |

H2 explains the observed claim refusal. Separately, the candidate discrepancy was a namespace confusion between byte SHA and framed six-source identity; OTP29 `candidate_id.current()` disconfirms protected-file drift. P01 features digest in the supplied receipt was malformed; the source-derived full digest is recorded instead.

For replay safety, H1 "disk quarantine was not loaded" is contradicted by the actor's fresh quarantined projection; H2 "receipt replay bypassed the quarantine check" is supported by a previously successful intent returning success after disk corruption. Moving the pure ceiling veto before replay addresses H2. The adjacent freshness probes disconfirmed "a valid prefetch alone guarantees current output": old committed payload replay still hid fresh snapshots. Receipt retention and output replay must be separate decisions; final candidate checks retain safety while observations are recomputed. For the resilience fixture failure, unchanged canonical rows and a successful bounded writer disconfirm a lock-wait regression; the obsolete store-constructor pattern explains that distinct failure and was strengthened to verify actual row identity and totals.

## 5. Fix Taxonomy

**V01 classification.** Poka-Yoke: exact pins, normalized paths, canonical ceiling, unavailable-tool exclusion, item caps and explicit backend detection. Jidoka: corrupt or symlinked stores quarantine and missing runtime evidence refuses. Muda elimination: Set-based duplicate detection and combined dependency discovery. Fencing: hold rows represent one worker attempt during one live lease, allowing safe reclaim through another channel.

Historical Step 1 record:

Poka-Yoke: reuse bounded no-follow, read-only canonical SQLite query machinery for fence lookup. Jidoka: preserve HOLD and repair evidence before claiming. Muda elimination: remove generated isolated C01 packages from full-build discovery by reversible relocation. Source-bound verified projections replace fabricated completion rows; no authority is taken from JSON caller arguments.

## 6. Patterns & Anti-Patterns Discovered

**V01 Devil's Advocate.** Passing receipts must be deletable and downgradeable; a grant must remain revocable after an earlier successful mutation. Self-attested workspace bytes must not claim a SHA-pinned provenance. A secret prefix, bearer header or URL userinfo in audit and policy values must redact, while benign lowercase akia words and secret-readonly policy names remain visible. Falsifiers cover these distinctions rather than only successful reads. Missing test modules and denied sockets remain failures, never substituted or skipped to produce green counts.

Historical Step 1 record:

Preserve semantic candidate identity and byte identity as separate measurements. Refreshing timestamps cannot make a stale readiness decision true. Devil's Advocate falsifiers include duplicate-key grants, symlink ancestors, missing database rows, expired leases, completed task reuse, and malformed or quarantined feature ledgers. A passing development suite cannot establish production authority or independent V01 acceptance.

## 7. Verification Matrix

**V01 final verification observations.** All fifteen invocations used OTP 29, one fresh VM per suite, after formatting and an Erlang-target build. The three remediation suites pass 112/112. The aggregate has 287 passing and 11 failing tests; the absent fifteenth module cancels its invocation with zero tests. No skipped test or missing module is counted as passing.

| Suite | Passed | Failed | Result | Evidence |
|---|---:|---:|---|---|
| mcp_canonical_gateway_wiring_test | 33 | 0 | PASS | A1 observed |
| mcp_canonical_planning_store_test | 36 | 0 | PASS | A1 observed |
| mcp_vault_feature_ledger_test | 43 | 0 | PASS | A1 observed |
| mcp_live_cutover_wiring_test | 60 | 5 | FAIL | A1 observed |
| mcp_final_acceptance_test | 4 | 0 | PASS | A1 observed |
| mcp_feature_acceptance_test | 8 | 0 | PASS | A1 observed |
| mcp_admission_test | 5 | 0 | PASS | A1 observed |
| mcp_planning_write_test | 6 | 0 | PASS | A1 observed |
| mcp_schema_parity_wave2_test | 19 | 0 | PASS | A1 observed |
| harness_sa_plan_boundary_test | 8 | 0 | PASS | A1 observed |
| mcp_fractal_path_resilience_test | 10 | 1 | FAIL | A1 observed |
| mcp_resilience_bdd_test | 27 | 2 | FAIL | A1 observed |
| mcp_market_leader_json_protocol_test | 24 | 3 | FAIL | A1 observed |
| mcp_vault_metadata_test | 4 | 0 | PASS | A1 observed |
| mcp_json_otp29_guard_test | 0 | 0 | MISSING MODULE; CANCELLED | A1 observed |

The four live-cutover SSE failures and two BDD SSE failures directly report socket eperm. Fractal path and two market fixture cases report erofs when their hardcoded canonical-root artifacts are written. The market stdio child reports undef for the expected canonical-root gateway beam. The live HTTP assertion remains unresolved; its cause is not proved by the other environment failures. The fifteenth module has no source or beam in this workspace. Overall acceptance is HOLD, not PASS.

The machine-readable [V01 summary receipt](http://nas-1.tail55d152.ts.net:4100/files/var/harness/20261031-0940-wave2-v01-remediation-summary.json) records all fifteen requested suites separately, including failures, cancellation and missing-module status. Only directly observed passing invocations receive A1. The older fourteen-suite results below belong to Step 1 and do not establish V01 acceptance.

Historical Step 1 record:

Admiralty grades denote directly observed local evidence, not sovereign admission.

| Observation | Result | Grade / evidence |
|---|---|---|
| Pi package build, target Erlang | PASS, exit 0 | A1, `/tmp/uos-p01-rebuild-20261031.log` |
| Pi OTP29 ledger/feature/vault suites | PASS, 45/45 | A1, `/tmp/uos-p01-eunit-20261031.log` |
| P01 active-check and completion | PASS, attempt 1 completed | A1, canonical Sa-plan row and command receipt |
| C02 initial preflight | HOLD, preserved | A1, RP-SELECTION observation |
| C02 repaired preflight and active-check | PASS, executing attempt 1 | A1, canonical Sa-plan and checker output |
| Candidate semantic identity | PASS, expected six-source SHA | A1, OTP29 `candidate_id.current()` observation |
| Full codex package, target Erlang | PASS, exit 0, zero errors | A1, `/tmp/uos-c02-final-package-build-20261031-v5.log` |
| Final fourteen OTP29 suites | PASS, 271/271, zero failures | A1, `/tmp/uos-c02-final-eunit-20261031/*.log` |
| Nine source/test hashes after tests | PASS, all equal pre-build manifest | A1, `/tmp/uos-c02-final-tested-source.sha256` |
| Final C02 risk active-check | PASS, 15 source-bound evidence files | A1, `/tmp/uos-c02-final-risk-active.json`, observed 2026-10-31T09:02:06Z |
| C02 canonical completion | PASS, attempt 1 completed | A1, Sa-plan receipt observed 2026-10-31T09:02:49Z |
| Actual refreshed toolchain preflight | PASS, 31/31, no VCS changes | A1, `/tmp/20261031-0900-c02-safe-preflight` |
| Lean/Gospel, production, independent V01 | UNRUN / NOT_ADMITTED | No passing claim |

Final suite counts: canonical gateway wiring 27; canonical planning store 25; vault/feature ledger 33; live cutover wiring 65; final acceptance 4; feature acceptance 8; admission 5; planning write 6; schema parity wave 2 19; harness Sa-plan boundary 8; fractal path resilience 11; resilience BDD 29; market leader JSON protocol 27; vault metadata 4. The optional `mcp_json_otp29_guard_test` module does not exist; the existing four-case vault metadata suite is explicitly the fourteenth suite.

Final active-check initially held when evidence observation at 09:01:29Z postdated the assessment at 09:01:28Z. Preserved that refusal in `/tmp/uos-c02-final-risk-active-hold-before-timestamp-alignment.json`; re-observed the source and assessment together, retaining the existing expiry, then obtained the 15-file passing check. After canonical completion, both portfolios were refreshed again and C02's accurate source reference/digests were rebound. This repairs chronology rather than bypassing the freshness gate.

## 8. Files Modified

**V01 files.** Only the operator's twelve Gleam files and this journal receive source edits, plus the requested [summary receipt](http://nas-1.tail55d152.ts.net:4100/files/var/harness/20261031-0940-wave2-v01-remediation-summary.json). The thirteen Wave 2 digests exclude the summary itself to avoid a circular self-hash. All nine protected-file digests are recomputed against the captured baseline. Build and disposable fixture artifacts are generated solely for the requested verification. No Jujutsu or Git command executes in this round. Fence deviation: before the resolver fix, inherited SQLite setup and one direct read-only diagnostic invoked /usr/bin/sqlite3. Their canonical-database reads failed with unable-to-open errors; no canonical database write was made. The Nix-only restriction was not fully respected during that initial investigation. Subsequent SQLite runs use only the isolated Nix fixture profile; the forbidden production fallback has been removed.

Historical Step 1 record:

Development files: `mcp/adapters/{vault_metadata,vault_backend,features,feature_receipt_ledger,canonical_planning_store}.gleam`, `mcp/runtime_gateway.gleam`, `test/mcp_vault_feature_ledger_test.gleam`, `test/mcp_canonical_gateway_wiring_test.gleam`, and the constructor expectation in `test/mcp_resilience_bdd_test.gleam`, plus this journal. Canonical root changes are restricted to the selected risk portfolios, fresh actual preflight evidence, and Sa-plan state via its CLI. Protected harness admission, tools, candidate identity source, and six identity inputs remain unchanged. No `jj` or `git` mutation command has run; scoped read-only pinned-operation preflight queries ran with `--ignore-working-copy` and unchanged VCS state proved by before/after observations.

The final digest/count/state manifest is `var/harness/20261031-0909-wave2-step1-summary.json` in the codex sibling workspace. It records all nine changed Gleam hashes, this journal's hash, actual per-suite counts, source-bound risk receipt, protected identities, original P01 source receipts, and canonical task states.

## 9. Architectural Observations

**V01 evidence flow.** Gleam owns validation and policy. SQLite remains the canonical planning backend; a feature ledger is a workspace assertion unless its exact bytes verify against a supplied SHA pin. Pinning establishes byte integrity rather than sovereign admission. The paired editable sources below have identical node labels and edges and contain no parentheses.

```ascii
[Public call] --> [Path guard]
[Path guard] --> [Bounded read]
[Bounded read] --> [SHA pin]
[SHA pin] --> [Disk projection]
[Disk projection] --> [Actor intent merge]
[Actor intent merge] --> [Feature response]
```

```mermaid
flowchart TD
  A[Public call] --> B[Path guard]
  B[Path guard] --> C[Bounded read]
  C[Bounded read] --> D[SHA pin]
  D[SHA pin] --> E[Disk projection]
  E[Disk projection] --> F[Actor intent merge]
  F[Actor intent merge] --> G[Feature response]
```

[[wiki:20260907-1559-risk-prioritization-guide]]
[[zk:20260907-1559-adr-risk-prioritization]]

[Wiki reference](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1559-risk-prioritization-guide.md) and [ZK reference](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1559-adr-risk-prioritization.md) are locators; live transclusion serving is UNRUN.

Historical Step 1 record:

The ingress caller performs bounded disk/SQLite observations before sending the resolved snapshot to the OTP state actor. Pure read/verification authority decisions do not require grant I/O. Canonical SQLite remains the durable task authority; feature completion additionally requires verified evidence. Sheaf/presheaf consistency and categorical proofs are UNRUN; the concrete interface invariant is that request context and route grant use the same observed fence.

## 10. Remaining Gaps

**V01 remaining gaps.** The all-fifteen zero-failure condition is NOT_SATISFIED. The sandbox denies loopback socket creation with eperm; the requested mcp_json_otp29_guard_test source and beam are absent, and the file fence prohibits adding an unlisted suite. The real Nix profiles also lack SQLite, so production canonical access correctly fails closed pending operator restoration. Some broad cases require live canonical preflight/runtime evidence; none is refreshed or fabricated here. Every broad failure is retained by name in the summary, and remaining failures require investigation in an appropriately authorized runtime before acceptance.

Historical Step 1 record:

The full package and all selected suites now pass. The literal operator-supplied candidate file SHA comparison remains false: actual byte SHA `5f11b5f9dbc94f464370ff10887717e72fb0f9fde320228f908e4c84bc95a9fa` is unchanged, while computed six-source identity `sha256:5fb7a77609e9f41f8368fc5a761435dec6519736a00f4642d6e986ca3e8e1663` matches the supplied identity. Both are disclosed separately, with no source alteration to fabricate a match. The absent optional JSON guard suite is transparently replaced by the existing vault metadata suite. Independent V01, production authority, formal invocation and release remain outside this task. Red Team probes demonstrate refusal on invalid authority and immediate live metadata/projection updates, including reused read intent IDs.

## 11. Metrics Summary

**V01 metrics.** Three scoped suites: 112 passed, zero failed. All fifteen invocations: 287 passed, 11 failed, zero skipped tests, one absent-module cancellation; ten suites pass, four contain failures and one cannot load. The 2,000-ID loader test passed its 500 ms bound. The planning CLI parity probe passed exact total 1 and completed 1, including hold, release, completion, job and workflow operations against a copied database. Diagnostic Bayesian prior Beta 1,1 is not a reliability certificate: correlated tests do not justify independent operational probabilities. Evidence half-life is one hour and any source change invalidates candidate-bound results. Runtime Lyapunov energy and dV/dt remain UNMEASURED, so no stability theorem is claimed. Timing and exact suite outcomes belong to this invocation, not the historical Step 1 sample.

Historical Step 1 record:

P01 and C02 both completed attempt 1; V01 remains available for independent acceptance. P01's component run passed 45/45; the final codex run passed 271/271 across 14 suites. Nine changed Gleam files are bound to the unchanged pre-build hash manifest and fifteen risk evidence files bind root context plus codex source. Bayesian diagnostic model for the P01 component sample (not a reliability certification): Beta(1,1) plus 45 passing bounded checks gives Beta(46,1); mean 46/47, subject to correlated tests and no independence claim. Evidence half-life for this diagnostic estimate is one hour and is invalidated by any changed tested byte. Lyapunov runtime energy and dV/dt are UNMEASURED; no stability claim is made. The governance blocker count decreased from one stale readiness condition to zero at claim time; this is a workflow observation, not a physical stability proof.

## 12. STAMP & Constitutional Alignment

**V01 risk and STAMP.** Raw FMEA modes: stale evidence S5 O4 D4; unpinned authority S5 O3 D4; stale hold S4 O3 D3; secret leakage S5 O3 D4; path escape S5 O3 D4. Authority and readiness constraints precede ranking. All four UCA types apply: needed revocation omitted; unsafe observation or mutation supplied; stale grant or hold used in the wrong order; expired authority used too long. Acceptance requires immediate disk changes, exact pins, live attempt fences, redaction, canonical CLI parity and honest regression accounting. Residual risks include sandbox-limited broad evidence, unchecked filesystem race resistance beyond bounded reads and prechecks, missing production toolchain entrypoints and absent formal invocation. No force-pass, release, integration or admission is performed.

Historical Step 1 record:

All four UCA types are considered: missing authority refuses action; unsafe authority cannot be supplied by caller JSON; wrong-order work remains dependency-gated; excessive-duration ownership is bounded by live leases and task fences. Zero-Muda: 0 Bevy, 0 Graphite; no dependency was added. Storage interlocks are untouched and the hardware serial remains redacted as `[REDACTED_SYSTEM_OS_SERIAL]`. EV ceiling remains 93; EV94–109 remain NOT_ADMITTED. Source edits are development-only; no deployment, journal admission, or VCS mutation is inferred.

## 13. Conclusion

**V01 conclusion.** Scoped remediation is source-implemented and subjected to the recorded RED/GREEN probes. The requested aggregate acceptance remains blocked until all fifteen real suites pass. This journal and its mechanical gates do not grant release or sovereign acceptance.

V01 forecast precommitment observed at 2026-10-31T10:06:09Z: p = 0.99 that both final journal gates pass and all nine protected SHA-256 values match their initial baseline before Horizon 2026-10-31T10:30:00Z. Falsification is any unresolved gate failure or protected-byte mismatch at that horizon. Observed outcome o = 1: both gates passed and the nine protected byte digests matched at the final verification observation before the horizon; Brier score B = 0.0001.. The three scoped suites have already passed; the separate all-fifteen acceptance remains unsatisfied.

Historical Step 1 record:

P01 and C02 are canonically completed with fresh observed source-bound evidence. All six requested gateway seams are implemented; the final full package build and fourteen OTP29 suites pass. Candidate byte identity and computed identity are reported separately, and all immutable baseline files remain unchanged. No production or independent acceptance is asserted.

Forecast precommitment at 2026-10-31T08:37:23Z: p = 0.80 that the full codex package builds and the selected fourteen OTP29 suites pass with zero failures before Horizon 2026-10-31T09:30:00Z. Falsification: any full-build error or selected-suite failure left unresolved at the horizon. Both conditions were observed by 2026-10-31T09:02:06Z, so outcome o = 1 and Brier score B = (0.80 - 1)^2 = 0.04. Preserved RED observations explain the repairs; they are not rewritten as initial success.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — host UTC observed, clock checker passed.
- [x] CHK-02-TAIL — full FQDN links included; live serving UNRUN.
- [x] CHK-03-FRACT — layers and scope tagged.
- [x] CHK-04-KM — wiki/ZK/cockpit locators included; publication UNRUN.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [x] CHK-05-MUDA — no dependency addition; 0 Bevy, 0 Graphite.
- [x] CHK-06-GRAPH — Gleam code only; no foreign NIF introduced.
- [x] CHK-07-DRIVE — storage changes outside scope; interlock untouched.

</details>
<details><summary>Domain 3 — Testing and math</summary>

- [x] CHK-08-C1C8 — full package and selected regression/authority/live-ingress checks observed; unrelated UI modalities outside scope.
- [ ] CHK-09-MATH — formal/math engines UNRUN.
- [x] CHK-10-9MOD — selected component, integration, BDD, resilience and failure probes observed; 271/271 final checks.
- [ ] CHK-11-REGR — live UI regression outside scope.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [x] CHK-12-GLEAM — OTP29 component and full selected actor tests observed.
- [x] CHK-13-HERMES — canonical Sa-plan CLI and risk checker observed.
- [ ] CHK-14-ZIGVM — runtime engine unchanged; invocation UNRUN.
- [ ] CHK-15-MAX — inference unchanged; invocation UNRUN.
- [ ] CHK-16-OTEL — telemetry validation UNRUN.

</details>
<details><summary>Domain 5 — Governance and VCS</summary>

- [ ] CHK-17-SOV — independent V01 and sovereign admission pending.
- [x] CHK-18-JJ — no VCS mutation command executed; pinned-operation read-only queries observed, VCS state unchanged, sibling workspace retained.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV ceiling 93 preserved; no EV number created. Digest namespaces are disclosed separately. This ledger is local development evidence.

</details>

[Previous: governing harness contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) · [Next: Planning](http://nas-1.tail55d152.ts.net:4100/planning)

UOS footer: observed development evidence; no production or sovereign admission.
