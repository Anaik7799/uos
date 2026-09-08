# Codex mainline consolidation implementation plan

> Planning deliverable only. Use the repository's executing-plans process after execution is authorized and registered in Sa-plan. This side conversation does not dispatch other agents or activate merge, rollout, jobs or workflows.

**Goal:** Account for every observable Codex work stream and integrate its intended, verified code and preserved evidence into main without losing peer work or confusing historical test results with current clearance.

**Architecture:** Pin the complete source census, reconcile semantic deltas into an owned sibling, and validate the composed tree before a serialized main bookmark advance. Existing main content is the starting point; source heads and historical receipts remain preserved. Production promotion is a separate operation.

**Tech stack:** Standalone Jujutsu; Sa-plan/Hermes OCaml and SQLite; Gleam/OTP 29; repository release tooling in OCaml/Mojo; existing Nix/devenv provisioning; Mirage/Solo5 reference and host verification tools. No new implementation language, shell script, dependency or model service is proposed.

**Spec:** Operator request “create plan to merge all the codex managed code into mainline”; [workspace isolation](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-1030-workspace-isolation-contract.md), [risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md), [coordination](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-0653-tri-agent-coordination.md), [release assurance](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0551-release-assurance-sdlc-sre-sop.md) and canonical AGENTS.md.

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l8 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [This plan](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/superpowers/plans/20260908-1418-codex-mainline-consolidation-plan.md) · [Census](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/reviews/20260908-1418-codex-mainline-census.json) · [Journal](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/journal/20260908-1418-codex-mainline-merge-planning-journal.md)

Created in the host-observed planning session opened 2026-09-08 at 14:39 UTC. Prefix `20260908-1418` binds the assessment start 14:40:18 UTC (hour + seconds). Final validation carries its own observation time.

## 1. Scope, authority and constraints

- **Canonical Sa-plan:** `uos/codex-mainline-merge/20260908-1439`; only task `PLAN` is registered/executing for this request. M0–M8 below are a specification, not executable task state or a competing queue. Register them through Sa-plan only after execution authorization; no automatic enqueue on reading this document.
- **Planning owner:** `codex-merge-plan-20260908-1439`, worker `codex-merge-plan`; owned sibling `/home/an/NAS-setup/uos/.uos-workspaces/codex-merge-plan-20260908-1439`. Only its workspace lease is held. No integration/main or runtime lease has been claimed.
- **Pinned main:** `1be8029d72bc9530b1937564a37c555bd0b4b938`.
- **Pinned JJ operation:** `3f75a63b43a634c3c3c7a09e90937fb187eabf3a126f6673d75a8668ae28d27544820b13673e5958cac431279445c77050938745109f09bb29329fe083d455aa`.
- **Main may move:** refresh this census at M0 and recheck again before M7. A stored bookmark name is not an immutable source identity.
- Do not snapshot, rebase, split, abandon or describe another agent's change. Obtain owner-published frozen revisions and dirty/untracked manifests. Do not delete peer workspaces or erase divergent histories.
- Use standalone JJ only. No native Git commands, Bash scripts, broad restores, force updates or automatic rollback of shared operation history.
- No production service restart, cutover, DB migration, live task mutation by test fixtures, shared journal regeneration or shared Zenoh-key deletion.
- Provision packages through pinned Nix/devenv only. Reuse permitted OCaml/Mojo tooling. Bind OTP, ERTS, compiler, libc and NIF identities; a missing ignored .so in a fresh sibling is not a source regression.
- Use `nas-1.tail55d152.ts.net` and `vm-1.tail55d152.ts.net` for network operations, including private staging. Reserve a staging port through the existing coordinator; no hard-coded production listener takeover.
- All independent/tri-sovereign and two-key gates required by the affected contracts remain in force. A plan, peer ACK, formal model, forecast or board message grants no deployment or admission authority.
- Risk freshness, task attempt and monotonic ownership fencing are mandatory at each effect. The installed CLI/source discrepancy in §4 blocks automated merge execution until resolved.
- Preserve the current language boundaries, storage interlock, EV ceiling and historical provenance. No claim that all existing capabilities or all 17 aspects are verified follows from this plan.

## 2. Complete observed census

The pinned inventory contains **72 source records: 26 bookmarks and 46 Codex-named workspaces**, representing **66 distinct heads**. **16 heads / 18 source records** reach **14 distinct non-empty commits outside main ancestry**. Main has 473 ancestor commits in this snapshot. Thirteen of the 18 explicitly Codex-named bookmark heads are already in main ancestry; the other five need reconciliation.

The [machine census](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/reviews/20260908-1418-codex-mainline-census.json) contains every record, full commit/change IDs, empty-tip status, parents, outside ancestry, changed paths and same-change variants on main. The raw [bookmark](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/reviews/20260908-1418-codex-mainline-bookmarks.txt) and [workspace](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-merge-plan-20260908-1439/docs/reviews/20260908-1418-codex-mainline-workspaces.txt) listings preserve the snapshot source. All 46 workspaces are included even when the current tip is empty.

**Coverage limits:** names establish association, not sole authorship. The eight candidate bookmarks need owner confirmation. Unregistered or abandoned-unreferenced changes, unsnapshotted/untracked bytes and work created after this operation require owner attestations and an execution refresh. Seven historical Codex-related tag bookmarks are retained as references in the raw list, not treated as independent integration candidates. The new planning workspace itself postdates the census and must be added at M0. “All Codex code merged” is prohibited while any of these boundaries remains unresolved.

| Bookmark | Pinned head | Ancestry observation |
|---|---|---|
| `candidate/auth-ingress` | `6b033f37` | Reconcile 1 outside ancestor(s) |
| `candidate/auth-ingress-framing` | `5b1146ea` | Reconcile 2 outside ancestor(s) |
| `candidate/auth-ingress-framing-v2` | `acfe752c` | Reconcile 3 outside ancestor(s) |
| `candidate/auth-oidc-ed25519` | `91933857` | No non-empty outside ancestors |
| `candidate/mirage-metrics-prep` | `8cf4cbec` | No non-empty outside ancestors |
| `candidate/runtime-loopback` | `dc12e531` | No non-empty outside ancestors |
| `candidate/runtime-staging-evidence` | `607aa506` | No non-empty outside ancestors |
| `candidate/solo5-0.13.0` | `aea32296` | Reconcile 1 outside ancestor(s) |
| `integration/codex-ainf-reuse-design` | `614ffbd9` (divergent) | No non-empty outside ancestors |
| `integration/codex-mirage-audit` | `b04e4cd9` | No non-empty outside ancestors |
| `integration/codex-mirage-tenders-review` | `4ddc56b5` | No non-empty outside ancestors |
| `integration/codex-session-handover-adr-017` | `520f96c1` | No non-empty outside ancestors |
| `integration/codex-verified-timestamp-mandate` | `c7173316` | No non-empty outside ancestors |
| `integration/codex-web-runtime-identity` | `f734f8fb` | No non-empty outside ancestors |
| `review/codex-homeostasis-release-20260908-0551` | `83d5a7ca` (divergent) | Reconcile 1 outside ancestor(s) |
| `review/codex-manual-ui` | `c5a0d3e6` (divergent) | Reconcile 4 outside ancestor(s) |
| `review/codex-manual-ui-executable` | `2be0d18d` (divergent) | Reconcile 3 outside ancestor(s) |
| `review/codex-side-hive-fencing-20260907-1854` | `311d2b12` | No non-empty outside ancestors |
| `review/codex-side-homeostasis-20260908-0045` | `bf136217` | No non-empty outside ancestors |
| `review/codex-side-interface-skills-20260907-2312` | `efbaea22` | No non-empty outside ancestors |
| `review/codex-side-resource-controls-20260907-1906` | `c502fbd2` | No non-empty outside ancestors |
| `review/codex-unification-20260908-0753` | `9bbc5217` | No non-empty outside ancestors |
| `review/codex-unification-50` | `6d15a6d3` | Reconcile 2 outside ancestor(s) |
| `review/codex-unification-50-merge-held` | `8b320ef9` | Reconcile 1 outside ancestor(s) |
| `review/codex-unification-50-tested` | `c65ad8e2` (divergent) | No non-empty outside ancestors |
| `review/codex-unification-merge-20260908-0835` | `cd503010` | No non-empty outside ancestors |

### Outside changes and owning packet

Counts below are **own-patch touched paths / those paths differing from current main**, not missing-feature counts. Current main may legitimately supersede a differing path. Every unique delta needs a reviewed disposition.

| Exact commit prefix (full ID in census) | Packet | Change | Touched / different |
|---|---|---|---|
| `c5a0d3e6` | M4 | docs(testing): add manual GUI/TUI guide and candidate-bound verification receipts | 13 / 13 |
| `2be0d18d` | M4 | feat(testing): add restricted Tailnet manual UI listener and keep navigation on its origin | 8 / 8 |
| `6d15a6d3` | M3 | docs(assurance): close fifty verified focuses with explicit ABI and integration holds | 21 / 21 |
| `fb71b4ca` | M3 | fix(guard): enforce JSON key contracts and add fifty-focus release assurance | 275 / 263 |
| `83d5a7ca` | M3 | fix(release): add native parity checks, truthful runtime identity and SDLC/SRE assurance | 63 / 4 |
| `e081c209` | M5 | work: Solo5 0.13.0 candidate frozen for independent review | 3 / 1 |
| `aea32296` | M5 | feat(mirage): pin Solo5 0.13.0 and verify current host toolchain | 5 / 5 |
| `b9d48617` | M5 | review(mirage): record producer and consumer source blockers at canonical snapshot | 2 / 2 |
| `595a3c83` | M2 | review(auth): approve bounded framing and fixed-reader follow-up | 3 / 3 |
| `acfe752c` | M2 | fix(auth): reject unsupported request expectations before read | 2 / 2 |
| `5b1146ea` | M2 | fix(auth): bound HTTP request framing before body ingestion | 4 / 4 |
| `6b033f37` | M2 | fix(auth): route real HTTP ingress through authenticated Wisp handler | 4 / 4 |
| `b9c99841` | M2 | review(auth): verify ingress adapter and reject unbounded body reader | 3 / 3 |
| `7621d5df` | M5 | formal(mirage): verify receipt admission reference and preserve independent review evidence | 12 / 12 |

### Reconciliation decisions established by inspection

1. **Release variants:** `83d5a7ca` and in-main `e73430f1` share a change ID. Of 63 touched paths, only AGENTS.md, `ops/release/flake.nix`, `tools/release_process.ml` and the release runbook still differ. Review those deltas individually; do not replace current policy with its older version.
2. **Fifty-cycle variants:** `fb71b4ca` and in-main `c65ad8e2` share a change ID but their interdiff changes 263 paths: 253 evidence paths and 10 code/tool paths. Main lacks `tools/evolution_archive.ml` and `tools/homeostasis_compat_check.ml`. Preserve the omitted historical archive and reconcile the TUI/tests/release/browser tooling against current main.
3. **Manual UI variants:** executable `517252df824c487ee80e61dfb4dec0fc139ec086` → `2be0d18d` and docs `1bf746c973b152fa78592432c7ba24bc2719452a` → `c5a0d3e6` have empty interdiffs. That establishes equivalent patches, not equivalent parent trees or fresh test results. The retained manual package still identifies the original executable candidate; keep that identity and rebuild for a new candidate.
4. **Solo5 overlap:** two of three paths in `e081c209` are byte-identical to main. The missing path is `ops/mirage/patches/mirage-4.11.2-solo5-0.13.patch`. Retain already-covered tool implementations while checking the earlier toolchain pin and provenance artifacts.
5. **Empty held merges:** `8b320ef9` and empty workspace tips do not prove absence of work. Their non-empty ancestor closure is represented in the 14-change table. Do not integrate an empty merge merely to make bookmark counts fall.

## 3. Prioritization and execution DAG

Apply class, authorization, evidence and dependency readiness before **C × STPA(T) × FMEA(F) × Dependency × Impact**. Ratings are local ordinal judgments, not probabilities or certified risk levels. “FEMA” is interpreted as FMEA. No active unsafe effect was established by this planning inspection, so no current P0 incident is asserted.

S/O/Det are severity / occurrence / detection difficulty. O=3 means credible exposure under expected integration faults, not an invented frequency. F=max(S, local RPN band). The census includes each stage's failure mode, control and acceptance conditions. Reassess at activation; current values expire as execution assessments.

| ID | Deliverable | Dependencies | Own class | C × T × F × Dep × I | S/O/Det; RPN; F |
|---|---|---|---|---|---|
| M0 | Freeze census, provenance and source ownership | None | P1 | 4 × 4 × 5 × 5 × 4 = 1600 | 5/3/3; 45; F5 |
| M1 | Establish authoritative tooling and common build baseline | M0 | P1 | 4 × 4 × 5 × 5 × 4 = 1600 | 5/3/3; 45; F5 |
| M2 | Reconcile authenticated ingress and bounded framing as one repaired unit | M1 | P1 | 4 × 4 × 5 × 4 × 4 = 1280 | 5/3/3; 45; F5 |
| M3 | Reconcile release assurance and preserve missing evidence | M1 | P1 | 4 × 4 × 4 × 4 × 4 = 1024 | 4/3/3; 36; F4 |
| M4 | Integrate manual GUI/TUI testing with authenticated release path | M2, M3 | P2 | 3 × 3 × 4 × 4 × 4 = 576 | 4/3/2; 24; F4 |
| M5 | Reconcile Solo5 source provenance, receipt validation and formal evidence | M1 | P1 | 4 × 4 × 5 × 3 × 3 = 720 | 5/3/3; 45; F5 |
| M6 | Compose final candidate and complete independent verification | M2, M3, M4, M5 | P1 | 4 × 4 × 5 × 4 × 5 = 1600 | 5/3/3; 45; F5 |
| M7 | Land verified source under serialized integration authority | M6 | P1 | 4 × 4 × 5 × 4 × 5 = 1600 | 5/3/3; 45; F5 |
| M8 | Close coverage, synchronize references and publish handoff | M7 | P2 | 3 × 3 × 4 × 2 × 4 = 288 | 4/3/2; 24; F4 |

M6/M7 urgency propagates to their actual unfinished prerequisites without changing DAG eligibility. At M1 completion, the preferred first code packet is M2 authentication; M3 and M5 follow once eligible. M4 depends on both M2 and M3. M6 waits for every code packet. Source preparation could be independent in a separately authorized main-thread plan, but this side conversation dispatches no agents.

Use one integration writer, one bounded check job at a time by default, and existing tools before model advice. Only broaden tests for changed scope, failures or unresolved concerns. Repeated loops without a new hypothesis/evidence need a stop-and-reassess. The scores are provisional under ±1 sensitivity; use a cheap discriminating check when it can change the safe next action.

## 4. M0–M1: source freeze and trustworthy baseline

**Owners:** future registered integrator and each source owner; independent authority reviewer. No owner is assigned by this document on another agent's behalf.

**Inputs:** census, pinned main, live Sa-plan/coordinator records, raw listings and current local policies.

**Output:** refreshed immutable census and source disposition ledger; verified task/lease/toolchain receipt; baseline build/test receipt.

- [ ] Register exact task IDs M0–M8 and dependencies through the canonical Sa-plan interface only when execution begins. Each job/workflow must carry parent plan/task/attempt, risk reference, revision, budget and effect scope. Use idempotent IDs; reconcile existing entries before creation.
- [ ] Verify the installed Sa-plan executable against source `engines/hermes/modules/sa_plan/test/sa_plan_main.ml`. The installed binary advertises **0.3.0**, source **0.4.0**; old completion lacks the source's attempt argument. Do not assume new fencing behavior is deployed. Build the current CLI in an owned isolated build directory; exercise `test_sa_plan_leases.ml` and stale/wrong/expired attempt negative cases before using it to dispatch.
- [ ] Verify plan lookup/listing and exact task claim semantics against the canonical DB through supported interfaces. The observed old `plan list` output is not reliable evidence of all canonical plans; never create a second authority from that output.
- [ ] Refresh JJ operation, main, all bookmarks and workspaces. Compare to this census. Obtain owner-published committed/snapshotted revisions plus dirty/untracked manifests for every source stream. Do not inspect secret bytes or copy DB/WAL/SHM, model weights or compiler caches into evidence.
- [ ] For every delta assign one of: ALREADY_COVERED (main commit/path proof), PATCH_EQUIVALENT (interdiff proof plus later integrated tests), SUPERSEDED (reviewed replacement behavior and tests), SELECTED (packet/new owned commit), or BLOCKED (owner/evidence/gate). No branch is removed solely because its name looks historical.
- [ ] Record an immutable pre-integration main reference and owned integration workspace. Reserve integration/main only for the final serialized landing, not for a long planning/test session.
- [ ] Check NTP and boot identity, task attempt, monotonic leases, free space, test budgets and source hashes. Preserve system UTC and Lamport causality as separate observations.
- [ ] Establish the same permitted Nix/devenv toolchain and native ABI on baseline and candidate: OTP 29, ERTS 17-series compatible identity, Gleam/OCaml/Dune, libc/NIF digest, lock files and package provenance. Rebuild only affected native artifacts with explicit ABI evidence; do not blindly copy all .so files.
- [ ] Run candidate-bound baseline checks for `apps/cepaf_gleam`, `apps/indrajaal_gleam_web`, `apps/uos_swarm` and affected Hermes targets under resource limits. Capture exit status, diagnostics, real failing tests and missing provisioned artifacts separately.

**Known competing evidence:** an older 50-cycle journal reports 12 NIF ABI failures (GLIBC 2.42 versus the OTP environment's libc 2.40); later mainline journals claim a fully green broad suite. Neither is a fresh result for this proposed candidate. If baseline itself fails, create a bounded canonical repair/probe, preserve the failure, and block M6/M7. Do not silently waive the gate or count unavailable tests as passing.

## 5. M2: authentication as one complete repaired boundary

**Source:** `6b033f37 → 5b1146ea → acfe752c`; historical negative review `b9c99841`; positive bounded review `595a3c83`.

**Reconcile paths:** `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam`; `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam`; `apps/indrajaal_gleam_web/src/indrajaal_web_ffi.erl`; `apps/indrajaal_gleam_web/test/auth_ingress_test.gleam` and `auth_ingress_test_ffi.erl`; `tools/verification/oidc/auth_ingress_independent_review.erl` and `auth_framing_independent_review.erl`; associated review/evidence files in the census.

- [ ] Start from current main and inventory every current route. Preserve new direct routes while adapting the authenticated Wisp ingress; do not replace the entire newer entry module with the older source.
- [ ] Integrate the three commits' intended behavior together. The first revision alone has the historically rejected unbounded reader and must never become an approved intermediate main.
- [ ] Preserve both reviews under their original candidate identities. Run the six historical supplied scenarios and 42 independent scenarios freshly, after adapting isolated test transport to the allowed Tailnet FQDN and current APIs.
- [ ] Assert fixed-length body limit 65,536 bytes; over-limit 413; invalid UTF-8 400; duplicate/comma/signed/invalid Content-Length 400; unsupported Transfer-Encoding or conflicting framing 400; unsupported Expect 417 before a body read.
- [ ] Assert exactly the declared bytes are consumed, trailing bytes remain untouched, one monotonic five-second deadline covers all partial progress, and stalled reads return 408.
- [ ] Assert actual authentication before protected effects, HEAD body suppression, required response headers, no static-auth fallback in OIDC mode, and invalid bodies rejected before persistence. Use isolated fixture DBs, not the canonical live task store.
- [ ] Add current-router integration coverage for new direct routes and public/protected classification. Explicitly evaluate upstream header/prebuffer limits, concurrency limits, TLS ingress and protocol support; historical approval did not establish those properties.
- [ ] Obtain independent review of the final adapter and live isolated ingress behavior. Missing protocol coverage is recorded as a bounded unsupported behavior or a release blocker, never an untested claim.

**Acceptance:** repaired adapter, current routes and authentication agree; malformed input cannot bypass bounds or policy; current exact-tree tests pass. If integration fails, retain the candidate and receipts, repair in the owned child and rerun affected gates; main stays unchanged.

## 6. M3: release assurance and historical evidence conservation

**Source:** `83d5a7ca` versus `e73430f1`; `fb71b4ca` versus `c65ad8e2`; follow-up `6d15a6d3`.

**Reconcile paths:** `tools/release_process.ml`, `tools/release_process.mojo`, `ops/release/flake.nix`, `tools/evolution_archive.ml`, `tools/homeostasis_compat_check.ml`, `tools/evolution_media_receipt.ml`, `tools/validation/release_browser_capture.ml`, `apps/cepaf_gleam/src/cepaf_gleam/ui/tui/homeostasis_evolution_view.gleam`, affected tests listed in the census, release runbook and 50-cycle evidence archive.

- [ ] Compare both same-change variants at hunk and behavior level. Keep current applicable AGENTS.md rules and newer release improvements; create small owned reconciliation changes instead of replaying an old whole tree.
- [ ] Restore missing legitimate historical evidence from exact JJ source objects, preserving original timestamps, candidate IDs, failed outcomes and archive manifests. Validate digest/record references; label historical tests as historical.
- [ ] Reconcile the archive/compatibility/media receipt tools with current JSON schemas and commands. Reject missing/truncated/corrupt files, key-contract violations and fabricated media duration. Preserve negative evidence and provenance.
- [ ] Exercise release lifecycle laws: observe is effect-free; failed or stale evidence cannot advance; repeated checks are idempotent; identity changes invalidate receipts; missing OTP/ERTS/NIF state is UNKNOWN or failed, not healthy.
- [ ] Run the existing OCaml release tool's selftest, runtime-check, unit, build, verify, package-faults and parity paths with isolated artifacts and bounded execution. Inspect current command help/source first; record actual commands and versions.
- [ ] Exercise Mojo/OCaml functional parity on the same frozen input fixtures and compare normalized structured results, errors and exit codes. A Mojo wrapper delegating to OCaml is shared functionality, not an independent implementation or independent proof. No Python provisioning outside Nix/devenv.
- [ ] Link preserved archives, guide, forecasts and decision records additively into the current wiki/ZK indexes. Do not rewrite shared live journals or manufacture new EV admission.

**Acceptance:** all 63-path and 275-path source patch deltas plus the 21-path follow-up have reviewed coverage dispositions. Missing evidence is accounted for without restoring obsolete behavior. New release checks pass on the reconciled tree; historical receipts retain their original scope.

## 7. M4: executable manual GUI/TUI testing and guide

**Source:** `2be0d18d` and `c5a0d3e6`; interdiff-equivalent original candidates are recorded in §2.

**Paths:** `apps/indrajaal_gleam_web/src/indrajaal/manual_test.gleam`, `src/indrajaal/homeostasis_http.gleam`, `test/manual_test_test.gleam`, Lustre `homeostasis_evolution_hud.gleam`, `tools/release_process.ml`, `tools/validation/homeostasis_browser_check.ml`, `docs/guides/20260908-1234-manual-gui-tui-testing.md` and its journal/evidence.

- [ ] Reconcile the restricted manual listener and same-origin navigation after M2/M3. Bind candidate revision into the release package and observed UI/API identity.
- [ ] Reserve an isolated runtime lease and Tailnet FQDN port with an expiry. Use fixture data for mutation tests and read-only real-data probes; make modes visible and prevent test controls from writing live state.
- [ ] Run current manual listener unit/negative tests, then exercise manual-web, smoke-manual and browser-manual commands from their reconciled implementation. Invalid package, wrong revision, occupied port and missing dependencies must fail explicitly.
- [ ] In a real browser verify intended content rather than only HTTP 200: navigation stays on the test origin, controls operate, live data and SSE advance, disconnect/stale/error states remain visible, and console/network failures are captured.
- [ ] Capture at least 30 seconds for every changed page/component's update behavior, with declared scope and content identity. Validate the media contains changing frames and the intended page; a video file alone does not prove correct updates.
- [ ] Exercise TUI fixture and read-only real-data modes, resize, keyboard navigation, refresh, stream loss and shutdown; assert terminal restoration and matching statuses across TUI/GUI/API.
- [ ] Have a human follow the guide's exact FQDN commands/links against the candidate release. Record observer, package revision, mode, expected/actual behavior and failures. An agent browser receipt does not count as that human receipt.

**Acceptance:** instructions, executable listener, package identity and UI behavior agree on the new integrated build. Do not relabel the existing manual package's `517252df...` receipt as a `2be0d18d...` or main result.

## 8. M5: Solo5/Mirage provenance and receipt integrity

**Source:** `aea32296`, `e081c209`, `b9d48617`, `7621d5df`.

**Paths:** `ops/mirage/patches/mirage-4.11.2-solo5-0.13.patch`; `tools/verification/solo5_toolchain.ml`; `tools/verification/mirage_guest_toolchain.ml`; source pins under `governance/sources/20260907-*`; Mirage OCaml/Gleam producer/consumer code; `formal/lean/MirageReceiptAdmission.lean`; `formal/quint/mirage_receipt_admission.qnt`; `tools/verification/mirage/`; historical reviews and generated evidence in the census.

- [ ] Preserve main's byte-identical tool implementations where already covered; reconcile source pins and missing patch without silently changing the installed toolchain.
- [ ] Re-evaluate the eight historical S13 findings on the actual candidate. Record each as reproduced, fixed-with-proof, superseded-with-proof or blocked; the old review is a checklist of obligations, not a present-day verdict.
- [ ] **S13-01/02:** one strict typed receipt/context validator across OCaml, Gleam and gates; fabricated/stale/future/malformed receipts and implicit verified defaults rejected.
- [ ] **S13-03/04:** before/after guest, tender and exact QEMU executable digest binding; pins actually used; controlled environment and host/boot/candidate identity compared.
- [ ] **S13-05:** bounded complete output and monotonic timeout; read failure/truncation distinguished from EOF; exceptions and leader exit reap the owned process tree.
- [ ] **S13-06/07:** exact target-specific success and SSP outcomes; no substring or legacy-version fallback; admission gates consume the same validated receipt, not an ELF magic check.
- [ ] **S13-08:** mandatory positive controls and implementation-boundary adversarial tests; missing artifacts are BLOCKED, never optional success.
- [ ] Rerun Lean/Quint/reference checks with pinned tools and explicit finite bounds. Historical evidence describes 13 theorems, 25 examples, 31,104 finite cases, seven lifecycle checks and 2,000 sampled traces at max 25 steps; verify actual current commands/results instead of repeating these counts as fresh. Missing tools, undeclared axioms, sorry, timeout or unrun v2 fixtures fail the applicable gate.
- [ ] Run bounded physical host tests only under the appropriate isolated runtime task/lease, with exact source/artifact receipt. Verify hvt/spt/virtio target semantics, timer behavior and expected SSP aborts; reject receipt tampering and wrong host/context.
- [ ] Keep physical tender execution, formal reference-model properties, implementation correspondence and actual MIG application migration as separate evidence states. Tender hello/time/SSP tests do not prove application migration or RAM savings. Verify reported application savings from actual migrated service measurements.

**Acceptance:** all intended source/provenance deltas are conserved; mandatory producer/consumer, reference and physical gates pass at the integrated candidate. If additional code repairs are needed, register bounded Sa-plan children before work. A formal reference model alone does not discharge implementation refinement or runtime isolation claims.

## 9. M6: composed candidate, 17 aspects and evidence algebra

Freeze a candidate only after every selected packet and conflict resolution is present. Build once from that exact source and pinned provisioning; run appropriate broad regression plus required boundary tests. Any subsequent source or dependency change invalidates affected receipts and requires re-verification.

Let `Candidate = (commit_id, tree_identity, toolchain_digest, artifact_digest)`.
Let `Receipt = (candidate, command, input_digests, tool_versions, observed_utc, monotonic_duration, outcome, scope)`.
Let `Coverage(source_delta) = target_commit + reviewed_behavior_or_supersession + tests + historical_evidence_locator`.

Required laws:

- **Source conservation:** every inventoried delta has exactly one primary disposition and an evidence-backed target or explicit blocker. Duplicate workspace references do not count as distinct implementations.
- **No false clearance:** `UNKNOWN | STALE | UNRUN | FAILED ≠ PASSED`; missing receipt fields fail validation.
- **Authority separation:** observations, board ACKs, forecasts and model results cannot create task, runtime or integration authority.
- **Evidence binding:** changing candidate, artifact, toolchain or relevant inputs invalidates affected checks.
- **Safe landing:** `advance(main,candidate)` requires a current task attempt, valid integration fence, exact expected main base, verified descendant candidate, complete required receipts and independent approval.
- **Idempotence:** retrying a read/check does not replay effects; retrying a landed operation recognizes its recorded result.
- **Historical integrity:** new evidence may supersede a claim explicitly; it never changes the original receipt's candidate or outcome.

These are plan obligations, not new formal proofs. Implement missing checkers only if the current repository lacks the gate, through a bounded registered task with positive and negative controls.

| Aspect | Required integration evidence |
|---|---|
| A01 Substrate & Hardware Storage Interlock | Host resources and hard-denied drive invariant; no storage mutation. |
| A02 Standalone Jujutsu Monorepo Discipline | Exact operation/commit census, own changes, preserved peer history, serialized landing. |
| A03 Zero-Muda Purity & Waste Elimination | Dependency/source exclusion scan; no duplicate deployed role or copied caches. |
| A04 Gleam/OTP29 4-Domain Root Supervisor | Actual OTP/ERTS identity, supervised startup, readiness and bounded restarts. |
| A05 ZigVM Deterministic Engine & 8 VFS Laws | Changed-scope VFS/kernel conformance or explicit reviewed unchanged-scope evidence. |
| A06 Hermes Formal Evidence, Gospel & Z3 | Bounded workers, parser/error paths and relevant executable contracts. |
| A07 Mathematical Authority & Conservation | Receipt/source conservation, temporal checks, no unproved admission claims. |
| A08 Biosemiotic Cybernetics & Rocha Cut | Observation/advice remain separate from authority and effect execution. |
| A09 Quarantined Modular MAX/Mojo Inference | Existing language/process boundaries and release-tool parity; no inference deployment implied. |
| A10 Zenoh OoZ & MoZ Mesh Telemetry Backplane | Additive own-key events, identity/digest/readback and stale/disconnect behavior. |
| A11 AG-UI 32-Event SSE Stream Protocol | Current framing, event identity/order, reconnect and live update tests. |
| A12 A2UI 233-Component Declarative Catalog | Changed component/catalog references and data-mode contracts; historical count is not coverage. |
| A13 Penta-Stack Multi-Interface Accessibility | GUI/TUI/API parity, keyboard/resize/accessibility and manual journeys. |
| A14 Universal Tailscale FQDN Web Navigation | Real intended-content tests for links, private stage and same-origin navigation. |
| A15 Comprehensive Verification Checklist | Original 18 plus six provenance checks mapped to actual evidence/holds. |
| A16 Knowledge Management Triad (Wiki/ZK/Ontology) | Complete additive indexes, source backlinks and preserved historical evidence. |
| A17 Sa-Plan & Bionic Durable Workflows | Exact task-attempt lease/fence and corruption/retry/rollback tests; no duplicate queue. |

**Exit review:** independent reviewer checks the exact composed tree, source coverage, conflict resolutions, auth boundary, main runtime identity, package artifacts and all required aspect receipts. The approval identifies scope and remaining non-applicable obligations. A required failed/unknown gate blocks landing. No new runtime/admission claim is made merely by integrating documentation.

## 10. M7: serialized mainline landing and recovery

This is the only stage allowed to move main. It requires a separately activated canonical task and integration/main ownership. The current PLAN task cannot perform it.

- [ ] Confirm the frozen candidate is a descendant of the expected current main and has no unresolved conflicts. Freeze the approved tree and receipt manifest after tests.
- [ ] Obtain required peer acknowledgements of exact candidate and source dispositions, then acquire/recheck the integration/main lease and task-attempt fence immediately before movement.
- [ ] Re-read main and compare it to the expected base. If it has changed, stop landing, reconcile current main into a new owned candidate and rerun affected/composed gates. Never force main back to the old base.
- [ ] After all checks, advance main using the supported JJ bookmark command from the owned workspace. Record before/after commit IDs and operation. A JJ command by itself is not an atomic policy CAS; serialization requires the coordinator fence and cooperative writer contract.
- [ ] Read back main, tree identity and receipt digest. If interrupted, inspect those identities before retrying. Do not rerun the mutation blindly.
- [ ] Leave deployed packages and running primary/backup services unchanged. Production release/cutover requires its own task, runtime lease, approval and recovery evidence.

**Recovery before landing:** keep main unchanged, preserve the failed owned candidate and diagnostics, create a scoped repair; abandon only disposable own changes if appropriate.

**Recovery after landing:** halt further integration, observe current main and publish the discrepancy. Prepare a new reviewed compensating change on current main if correction is needed. Do not reset shared main, undo global JJ operations, delete evidence or rewrite peers. If production is already failing, use the separately authorized runtime recovery runbook; source planning is not a runtime rollback command.

**Owner-local JJ method:** create an owned child on current main; apply only reviewed source deltas/new evidence paths from pinned commits. For existing files perform three-way semantic reconciliation. Preserve original heads. Use read-only `jj diff` / `jj interdiff` and exact source IDs; do not use bulk whole-tree restore or blindly merge every historical bookmark.

## 11. M8: handoff, synchronization and completion

- [ ] Attach exact source, artifact, test and independent-review manifests to canonical task completion. Complete by the current verified Sa-plan attempt-aware API, not an assumed old CLI syntax.
- [ ] Publish compact board reports with source→main mapping, remaining holds, ownership and evidence links; read back the emitted records. Publish only own namespaced Zenoh summaries and verify readback if that interface is used. Do not modify peer keys or regenerate live journals.
- [ ] Update wiki, KM, ZK and source catalogs additively. Keep old journal contents and candidate receipts unchanged.
- [ ] Re-run the complete census and collect owner ACKs that dirty/new work since M0 is accounted for. Include this plan's own documentation change. A source record is complete only with a reviewed terminal disposition.
- [ ] Give peers explicit new main ID and read-only update instructions; let each owner update its own workspace. Bookmark cleanup is optional and requires confirmed coverage/owner consent.
- [ ] Release own leases, finish the 13-section journal and record cost/test duration. Mark the plan complete only when no unique intended Codex delta remains unaccounted or BLOCKED.

**Definition of done:** 100% of the refreshed scoped source records have reviewed coverage; all selected code and evidence are present or explicitly superseded with behavior/tests; the exact integrated candidate has passed every required gate and independent review; main points to that candidate; no peer history, deployed service or live data was changed outside its own authority.

If unique work remains blocked, report partial integration and the blockers. Do not rename that outcome “all merged.”

## 12. Planning verification, decision summary and current holds

**Verified during planning:** immutable JJ census; complete outside-ancestor union; same-change variants and touched-path comparison; two empty manual interdiffs; workspace isolation; canonical PLAN registration/attempt; native risk preflight/active check. Structural validation of this plan is recorded separately.

**Not performed:** source integration, auth/runtime/GUI/TUI/physical tender tests, toolchain installation, independent merge approval, production deployment or peer-workspace synchronization. Their current status for this proposed composition is NOT_RUN.

**Current holds:** owner-frozen dirty work not collected; source-to-binary Sa-plan behavior discrepancy; no fresh common ABI baseline; 14 outside commits not reconciled; eight historical Mirage review obligations not reverified on the proposed composition; no final integrated candidate exists.

**Decision:** preserve intended behavior and provenance through selective reconciliation. Already-integrated work gets coverage evidence; divergent variants get semantic review; unresolved safety or source-coverage conditions block landing. This avoids duplicate integration and makes omitted evidence visible.

**Forecast:** four coherent source packets should bound most known reconciliation work. Confidence is qualitative because owner-dirty work and baseline behavior remain unknown. The forecast is falsified by new unique heads, new source conflicts or a baseline/security/receipt failure. Track remaining unaccounted deltas, failing mandatory gates, source/evidence mismatches, integration queue age and observed check cost. Do not infer a completion date or global cost optimum from these counts.

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
