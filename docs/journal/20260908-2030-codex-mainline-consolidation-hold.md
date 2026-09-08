# Codex source consolidation: candidate preserved, mainline held

Recorded UTC: 2026-09-08T20:23:30Z. Author: Codex, session `codex-merge-execute-20260908-1925`.
Plan: `uos/codex-mainline-merge/20260908-1925`. Scope: owned source integration and bounded verification.
Tags: #fractal-l4 #fractal-l7 #zk-adr #zero-muda #tailscale-web
Main: `1be8029d72bc9530b1937564a37c555bd0b4b938`.
Composed product source: `5bb3af799ae69dd56b39b1b702cc565276e61467`.
Review bookmark: `review/codex-mainline-consolidation-20260908-1925`; the subsequent evidence commit is documentation-only.
Canonical navigation: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk).
These navigation references do not assert live readiness or publication of this candidate.

## 1. Scope & Trigger

The operator authorized the existing Codex consolidation plan with “merge”. This execution assembled all known immutable Codex source packets in a sibling JJ workspace. It did not advance main, deploy, restart production, edit a peer workspace or authorize a new EV cycle. Mainline completion remains **HOLD**.

## 2. Pre-State Assessment

The original census contained 72 bookmark/workspace records, 66 unique heads and 14 nonempty changes outside pinned main. Execution added the already completed planning artifact: 74 records, 67 heads and 15 outside changes. Original source heads were rechecked without taking peer working-copy snapshots; none changed during this reconciliation. Unsnapshotted/untracked peer work remains UNKNOWN until owners confirm its disposition.

Baseline source builds and Sa-plan authority tests passed. The current OCaml NIF failed to load under the pinned OTP runtime: **12 failed, 1 passed, 0 skipped**. A read-only Tailnet identity observation returned HTTP 503 with `runtime_ready=false` and `application_admitted=false`. These are observed holds, independent of older green board reports.

## 3. Execution Detail

M0–M1 established the isolated workspace, current task-attempt authority and baseline. M2 reconciled the three auth commits and both historical independent review packets. Current routes were retained; the bounded body adapter now preserves the original connection for the existing homeostasis SSE handler. Fixture sockets use the NAS Tailnet FQDN.

M3 reconciled release/compatibility helpers and preserved the historical fifty-cycle archive and failure receipts. M4 added the restricted manual GUI listener and same-origin navigation, routed its requests through the shared bounded-framing adapter, added framing-rejection coverage and included its required Erlang fixture in unit preparation.

M5 retained Solo5 source provenance, the missing Mirage compatibility patch, independent historical findings, Lean/Quint models and the OCaml reference oracle. Main's Solo5 tool implementations were retained. The patch was not applied to the installed toolchain, and no physical tender or application migration was performed.

Thirteen of the original fourteen outside changes are ancestors of the composed source. The remaining change `83d5a7ca` has an empty JJ interdiff against main's `e73430f1`, so it is recorded as already covered rather than replayed. Historical evidence remains historical; fresh results have separate receipts.

## 4. Root Cause Analysis

The native ABI failure is concrete: artifact SHA-256 `cfa6ab0be38bc23dc288e8a017d66ffa767bf1fa18ccfb2d9e374a071072df30` requires GLIBC_2.42 symbols, while OTP 29.0.6 / ERTS 17.0.6 uses GLIBC 2.40. A different installed OTP build was not substituted to conceal the mismatch.

Source divergence also exposed a real integration mismatch: the auth adapter supplies `Request(BitArray)`, while the SSE endpoint needs `Request(Connection)`. Retaining the original connection only at the SSE boundary after bounded framing validation repaired compilation without removing the existing stream route.

An initial offline third-party dependency build could not resolve the rebar pc plugin. Existing verified third-party build caches were reused; UOS product sources were compiled in the owned workspace. This is not a hermetic dependency rebuild.

## 5. Fix Taxonomy

| Change | Purpose | Scope of evidence |
| --- | --- | --- |
| Auth framing and connection-preserving composition | Bound input and retain the current SSE interface | Web build, 6 auth tests, 42 framing oracle cases |
| Manual listener framing reuse and fixture inclusion | Prevent the auxiliary listener bypassing the shared request bounds | 128 unit tests, including new framing rejection assertions |
| Release archive/guard reconciliation | Retain truthful missing-data labels and historical failure evidence | 113 selfchecks, 7 focused tests, 26 archive controls |
| Mirage patch, provenance and reference models | Preserve source/evidence omitted from main | Finite reference correspondence and bounded temporal checks |
| Additive receipts and coverage | Make partial success and remaining holds reviewable | JSON manifests, source identities and exact retained output |

No native ABI repair, production cutover or claimed independent approval is part of these fixes.

## 6. Patterns & Anti-Patterns Discovered

Use immutable source identities and per-packet reconciliation. A bookmark name, successful compilation, historical green count or author rerun of an independently written test suite does not establish independent approval of a new composition.

Preserve negative evidence and distinguish reference-model agreement from implementation refinement. Reject stale task attempts and stale workspace heartbeats; one stale-heartbeat check stopped before mutation and was followed by an explicit heartbeat and renewed workspace lease.

Decision summary: retain the complete source candidate and hold main until the actual blockers are cleared. The alternative of advancing main on scoped successes would leave known ABI failures and unreviewed composition. This is a reviewable engineering rationale, not a record of private model reasoning.

## 7. Verification Matrix

| Stage | Fresh observed result | Limit |
| --- | --- | --- |
| M1 Sa-plan source build / CLI / durability | PASS; CLI version 0.4.0; lease tests 2,955 assertions and 729 bounded oracle traces | Isolated temporary databases, not a canonical DB corruption exercise |
| M1 product source builds | cepaf_gleam, web and uos_swarm PASS | Existing third-party compiled cache reused; 31 locked Hex archives checked |
| M1 native ABI | **FAIL: 12 failed, 1 passed** | Mainline blocker; not waived |
| M2 auth | 6/6 PASS; independent-authored framing oracle 42/42 PASS | Author executed; no new independent composed-candidate review |
| M3 release | 113 checks PASS; focused compatibility 7/7 PASS | Does not clear broad native suite |
| M3 archive | 50 historical records verified; 26 positive/negative controls PASS | These are not 50 newly executed evolutionary cycles |
| M4 manual UI | Web build PASS; 128 unit tests PASS; 338 transition parity cases | Shared-backend frontend parity, not an independent proof or browser acceptance |
| M5 Lean / OCaml | 13 theorems and 25 examples compile; 31,104 cases agree, 0 disagreements | Finite declared universe; no implementation refinement theorem |
| M5 Quint | Typecheck and 7 lifecycle tests PASS; two seeded 1,000-trace samples without violations | Bounded sampling, not exhaustive exploration or liveness proof |
| M5 negative controls | Sticky-freshness and omitted-virtio mutants both rejected with invariant violations | Expected exit 1 is a passing negative control, separate from the ABI failure |
| M6 final GUI/SSE/TUI, manual acceptance and composed full suite | **UNRUN / HOLD** | Fresh final-candidate evidence and independent review required |
| M7 mainline update / M8 closure | **NOT EXECUTED** | No integration/main or runtime lease acquired |

Do not sum overlapping counts into a system-wide passing total. Incremental receipts identify the source under test; this journal does not claim every test was rerun at the final composition.

Twenty logs and synthetic counterexamples (194,533 bytes) are retained under `docs/evidence/20260908-2030-codex-merge`, with SHA-256 manifest. The reproducible 1.36 MB Lean CSV remains an ignored artifact with its digest and regeneration command recorded. Models and oracles are tracked.

## 8. Files Modified

At composed source `5bb3af79`, the delta from main is 347 paths: 332 additions and 15 modifications, with no deletions. Most additions preserve historical evidence; 33 paths are code, tools, formal models or a compatibility patch. The exact list and fourteen-change coverage are in `docs/reviews/20260908-2030-codex-merge-coverage.json`.

Wave receipts are `docs/reviews/20260908-1915-codex-merge-{baseline,auth,release,manual-ui}.json`; Mirage verification is `docs/reviews/20260908-2030-codex-merge-mirage.json`. This final stage adds receipts, retained logs and this journal only. No binaries, live databases, caches or model weights were added to tracked source.

## 9. Architectural Observations

| Aspect | Assessment for this merge |
| --- | --- |
| A01 Substrate / storage | No storage mutation; native ABI remains failed |
| A02 Jujutsu | Owned sibling; source preservation and ancestry checked; main unchanged |
| A03 Zero-Muda | No new service/dependency selection; imported content is existing UOS source; full admission scan pending |
| A04 Gleam / OTP29 | Source builds pass; observed native load failure prevents whole-runtime clearance |
| A05 ZigVM / VFS | Kernel source unchanged; no fresh full kernel verification |
| A06 Hermes / Gospel / Z3 | Sa-plan and OCaml oracle checks pass within bounds; full Hermes/Gospel/Z3 obligations unrun |
| A07 Mathematical authority | Lean reference and Quint checks pass within declared bounds; implementation refinement absent |
| A08 Observation / authority separation | UNKNOWN/HOLD and negative receipts preserved; no observation grants action authority |
| A09 MAX / Mojo | Existing release frontend parity exercised; no inference model or new Python role installed |
| A10 Zenoh | No live keys changed or publication performed; board reporting is separate |
| A11 AG-UI / SSE | Connection-preserving composition compiled; fresh live SSE reconnect/update verification pending |
| A12 Component catalog | Existing components retained; full catalog/browser closure unrun |
| A13 GUI / TUI / accessibility | Scoped unit/parity pass; fresh visual, keyboard, accessibility and manual acceptance pending |
| A14 Tailnet navigation | Socket fixtures use NAS FQDN; full page/link validation pending |
| A15 Checklist | 24 current obligations retained below; no 24/24 passing claim |
| A16 KM triad | Additive journal/provenance retained; wiki/ZK live projection publication pending mainline admission |
| A17 Sa-plan | Native task attempts and own coordinator fences used; M6–M8 remain pending |

The empty root `.git` directory predates this execution. JJ reports its backend at `.jj/repo/store/git`; no root Git HEAD/config/objects were observed. The directory was left untouched. No native Git commands were run.

## 10. Remaining Gaps

1. **P1 — Native ABI consistency:** rebuild the affected native artifact and dependency closure against the pinned Nix/OTP runtime. Re-run both load/execute positive controls and native failure controls; then run the composed regression gate.
2. **P1 — Source and review authority:** obtain owner confirmation of frozen/pending work and an independent review of the exact composed candidate. Board silence does not count as ACK.
3. **P1 — Final behavior:** exercise current GUI/TUI real and fixture modes, browser/SSE update/reconnect behavior and manual acceptance over Tailnet; check current Mirage producer/consumer behavior against preserved adversarial findings.
4. **Dependent landing:** after M6 passes, claim integration/main, recheck main and source identities, and perform the serialized JJ bookmark update under M7. Any source repair requires new revision-bound receipts. M8 handles post-landing coverage and knowledge publication.

The product source candidate is ready to inspect, not admitted. The existing planning tasks retain these dependencies; no duplicate dispatch authority or broad repair swarm was created.

## 11. Metrics Summary

Known-source coverage: 13 ancestry inclusions plus 1 patch-equivalent disposition, across 14 original outside changes. Original head drift observed: 0. Source-owner freeze ACKs and independent composed review observed: 0.

Execution used one worker, bounded processes and existing toolchains; paid model calls, installs, source-tree imports from external authorities, production mutations and native Git commands: 0. No probability of successful landing is asserted: the known ABI failure dominates the next decision, and missing review/runtime evidence prevents a calibrated success estimate.

Observed clock: NTP enabled and synchronized. The final active-risk check reported approximately 0.000194 seconds absolute NTP offset with approximately 0.0167 seconds uncertainty. These clock measurements, monotonic durations and coordinator sequence numbers are distinct quantities.

## 12. STAMP & Constitutional Alignment

Unsafe control actions include advancing main with a failed ABI, treating a model proof as physical implementation evidence, bypassing a lease after heartbeat expiry, and silently dropping source/evidence during conflict resolution. Controls are a gated mainline transition, immutable identities, bounded negative tests, owner/independent review and additive coverage records.

The criticality × STPA × FMEA × dependency × impact portfolio governed execution order through the native active checker. M5 score was 720 within this declared plan; this is an analyst assessment, not a proven global optimum. The complete portfolio and current task observations are retained. The checker grants no runtime or deployment authority.

The repository's [branch-finishing skill](http://nas-1.tail55d152.ts.net:4100/files/.codex/skills/finishing-a-development-branch/SKILL.md) states: “If tests fail, report the failures and stop”. Accordingly, the known native failure blocks final mainline movement. The operator already authorized the merge; a second permission request is not the missing gate.

## 13. Conclusion

All known immutable source packets have a preserved consolidation disposition. Main remains at `1be8029d72bc9530b1937564a37c555bd0b4b938`. The review candidate and evidence are retained in the owned workspace; final verification, independent review and mainline landing remain held. No cleanup of peer workspaces or source bookmarks is authorized by this completion record.

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
