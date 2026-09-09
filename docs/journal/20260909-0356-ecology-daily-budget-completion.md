---
title: Ecology daily budget component completion journal
observed_at: 2026-09-09T03:38:56Z
plan_id: uos/ecology-budget/20260909-0309
task_id: DAILY-BUDGET
worker: codex-ecology-supervision
attempt: 1
status: COMPONENT_TESTS_PASSED
runtime_admission: NOT_GRANTED
tags: [fractal-l2, fractal-l4, zk-adr, zero-muda]
---

# Ecology daily budget component completion journal

#fractal-l2 #fractal-l4 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0309-ecology-daily-budget-contract.md) · [Machine receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0356-ecology-daily-budget-completion.json) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0356-ecology-daily-budget-completion.md)

These are canonical navigation targets. This worker records component evidence and performs no publication, production ledger provisioning, network dispatch or deployment.

## 1. Scope & Trigger

The operator authorized paid OpenRouter use capped at $10 per UTC day. Root assigned a bounded durable reservation component with a pure Gleam admission policy, an OCaml SQLite evidence ledger, equivalent Mojo entry point and independent concurrent-process tests. The agreed initial business rule reserves $0.25 before every paid request and never refunds uncertain or unused liability. The task is Sa-plan `uos/ecology-budget/20260909-0309`, `DAILY-BUDGET`, worker `codex-ecology-supervision`, attempt 1.

## 2. Pre-State Assessment

The earlier free route and shared Jidoka service gates did not establish an aggregate paid budget. A post-call cost log alone cannot prevent concurrent requests from passing the same remaining-budget observation, and recreating missing state can erase prior liability. Root retains responsibility for the canonical path, exact task fence, provider verification, dispatch and final paid usage receipts.

## 3. Execution Detail

The initial immutable event-list interpretation passed 55 checks before SQLite was implemented. Both interpretations expose initialization, status observations and reservation through the same storage signature. A smart constructor validates exact paid model IDs, bounded ASCII call IDs, integer token/byte limits and conservative provider ceilings. The fixed maximum Kimi request has modeled liability of 116,736,000 nanodollars; it still reserves the full 250,000,000.

SQLite now commits each grant in one `BEGIN IMMEDIATE` transaction using STRICT tables, a globally unique call ID within that database, constant budget/amount checks and append-only update/delete/replacement protection. A schema and integrity check precede observations. Missing, corrupt, altered, oversized or symlink storage fails closed. Public time comes only from the host and is sampled after the transaction lock, preventing contention ordering from creating a false rollback. A real clock older than initialization or the latest accepted event is rejected.

Gleam admission receives the actual input and serialized body strings, derives their UTF-8 byte counts and verifies live provider prices against the approved ceiling. It creates an opaque reservation request and validates final usage against the specific admitted input/token bounds. The Mojo facade forwards the same bounded argv and stdin directly to the OCaml core without a shell or Python.

## 4. Root Cause Analysis

Budget safety requires a durable liability event before an independently authorized paid effect. Observing actual spending afterward is too late to arbitrate concurrent requests. Retry behavior is equally material: a lost response must preserve liability and cannot allow the same call ID to receive another dispatch grant.

The ledger therefore distinguishes reserved liability from actual spend, which remains null. The component can guarantee its cap only within one database. A system-wide $10/day claim requires every production paid caller to use root's single canonical binding; scratch databases do not establish this integration property.

## 5. Fix Taxonomy

This is a pre-dispatch reservation gate, append-only persistence interpreter, bounded pure policy and cross-language facade. The controls include atomic transactions, single-use call IDs, persisted clock ordering, fixed integer nanodollars, strict storage shape, explicit provisioning and independent reference comparison. No refund, optimizer, routing engine, persistent autonomous task scheduler or network call was added in this slice.

## 6. Patterns & Anti-Patterns Discovered

- Sample the clock after acquiring the reservation transaction, so queued contenders are ordered by their actual acceptance.
- Treat retries after uncertain responses as rejected duplicates, even across UTC days.
- Keep the actual provider body and byte counts bound by the dispatch owner; storage validation alone cannot prove a caller's asserted count.
- Provider catalog minima do not establish an available routing ceiling. DeepSeek Pro uses root's approved ZDR provider ceiling of 1320/3960 nano per input/output token.
- A per-database cap is not an aggregate cap over independent databases.
- Do not infer actual spend from reserved liability or refund it because a request failed locally.

## 7. Verification Matrix

| Check | Observed result | Evidence |
| --- | --- | --- |
| Initial immutable oracle | PASS, 55 checks before SQLite implementation | `/tmp/uos-ecology-budget-oracle-2.log` |
| Native OCaml/SQLite suite | PASS, 398 checks | `/tmp/uos-ecology-budget-tests-final.log` |
| Shared storage laws | PASS, 47 per interpreter | Included in native suite |
| Seeded observational comparison | PASS, 128 trace steps / 256 observations, seed 20260909 | Included in native suite |
| Real eight-process final-slot race | Two grants and six exhausted denials; exactly $10 liability | Included in native suite |
| Real eight-process duplicate race | One grant and seven duplicate denials | Included in native suite |
| Law-targeted mutants | Three killed: removed cap, duplicate grant, ignored rollback | Included in native suite |
| Negative storage conformance | Expected compile failure when reserve operation is absent | Included in native suite |
| Gleam build / policy tests | PASS, six tests; OTP 29, ERTS 17.0.5 | `/tmp/uos-ecology-budget-core-build-final.log`, `/tmp/uos-ecology-budget-core-test-final.log` |
| OCaml/Mojo command equivalence | PASS, five cases / ten invocations | Included in final native/facade log |
| Final Sa-plan active observation | PASS, seven exact source files, 2026-09-09T03:38:56Z | `/tmp/uos-ecology-budget-active-final-receipt.json` |
| Canonical ledger, live paid request, production package | UNRUN by this worker; root-owned | No activation credit claimed |
| Lean/Quint theorem of this ledger | UNRUN | Bounded laws and tests are not theorem admission |

The negative cases include malformed/oversized JSON, extra or duplicate keys, invalid IDs/models/tokens/byte counts, raw SQL update/delete/replacement, invalid scalar types, missing/truncated/schema-altered files, symlink/WAL bounds, bounded SQLite contention and persisted future clocks. Separate processes verify restart persistence. The initial oracle run failed because the Unix package was not explicitly loaded; that failure was preserved and corrected before the oracle passed. The intentionally missing storage operation remains an expected compiler failure. The outer guardian emits a pre-existing OCaml automatic Unix-path deprecation notice; exit status and JSON comparison pass.

The final source assessment digest is `45a4329a48ee852ba581fe63e5e9faa5a46d6d9e7ca00a1af8aeefa521255229`. Chrony reported about 0.000980 seconds absolute offset. Compiler observations are OCaml 5.5.0, Gleam 1.16.0, SQLite 3.46.1 and Mojo 1.0.0 (ed45d567). The adjacent machine receipt embeds test logs and exact source hashes.

## 8. Files Modified

All implementation files are new in this task; existing actor, adapter, release and VCS state were not changed.

| Path | Purpose |
| --- | --- |
| `tools/ecology_budget.ml` | Typed request, initial oracle, SQLite interpreter and finite JSON CLI |
| `tools/ecology_budget.mojo` | Equivalent argv/stdin facade |
| `tools/validation/ecology_budget_test.ml` | Storage laws, seeded parity, negative cases, mutations and actual process races |
| `tools/validation/ecology_budget_check.ml` | Repeatable pinned native compilation, negative conformance and Mojo equivalence |
| `apps/cepaf_gleam/src/cepaf_gleam/ecology/daily_budget.gleam` | Pure request/price/usage policy |
| `apps/cepaf_gleam/test/ecology_daily_budget_test.gleam` | Six boundary and policy regressions |
| `docs/design/20260909-0309-ecology-daily-budget-contract.md` | Observations, laws, limits and driver handoff |

This journal and adjacent receipt complete the task record. Root owns grouping into the wider wiki/ZK/KM artifacts.

## 9. Architectural Observations

The policy and storage boundaries conform to the repository's language roles: pure Gleam decides admission; OCaml stores bounded authoritative reservation evidence; Mojo is an equivalent native facade. The budget grant does not authorize a Sa-plan task or deployment. A caller must fence its task, validate the actual body/provider price, reserve on the canonical path, confirm the fresh grant and fence again before its one dispatch.

The existing guardian must close stdin and enforce an independent hard deadline. The ledger's cooperative monotonic check cannot interrupt a blocked read or an ongoing SQLite call. A suggested production bound is 5 seconds and 4 KiB output. The test driver uses a 20-second/8 KiB guardian allowance for each cold Mojo invocation, with no package installation or download.

## 10. Remaining Gaps

| Priority | Remaining boundary |
| --- | --- |
| P1 | Root must provision and pin one canonical ledger and exclude alternate production paid paths, including legacy cost logs. |
| P1 | Root must bind exact input/body/model/token/price, verify current Sa-plan authority and execute at most one paid POST per grant. |
| P1 | Actual provider usage/cost evaluation and production activation remain separate root-owned evidence. |
| P2 | Trusted owner permissions do not defend against hostile same-UID replacement, raw schema alteration or external copying of the database. |
| P2 | No formal theorem, power-loss injection or distributed multi-host reservation proof was run. |
| P2 | The append-only file is deliberately finite. Reaching storage limits fails closed; archival/pruning and refunds require a new contract. |

## 11. Metrics Summary

Per database: $10 daily reserved liability, $0.25 per grant, at most forty grants per UTC day. IDs are 1..128 permitted ASCII characters. Paid completion is 1..4096 tokens, input at most 16,384 UTF-8 bytes, serialized body at most 65,536 bytes and template allowance 2048 tokens. DB/WAL/SHM bounds are 32/8/1 MiB, busy timeout 1000 ms and cooperative lifetime 30 seconds. Final evidence comprises 398 native checks, six Gleam tests and five facade cases; initial oracle checks overlap the shared semantics and are not added into a misleading aggregate count.

## 12. STAMP & Constitutional Alignment

The absent-control case is a paid call without a committed grant. Unsafe control includes duplicate grants or non-atomic concurrent accounting. Wrong timing includes reused task authority, stale grants or backwards clocks. Excess duration includes hung storage/model calls and unsafe refunds after uncertain effects. The corresponding controls are canonical pre-reservation, unique IDs/immediate transactions, exact task fencing/persisted time and bounded workers with no refunds.

Preflight and final active source checks passed under the exact Sa-plan worker/attempt. The final check grants no task or release authority by itself. No production ledger, credential, network, deployed package, external source tree, storage device or VCS mutation was touched. No new EV identifier was minted; the EV-93 admitted ceiling remains unchanged.

<details>
<summary>Comprehensive verification checklist: 18 core checkpoints and provenance</summary>

| Domain | Actual scope |
| --- | --- |
| Metadata/navigation | CHK-01-TIME host/chrony; CHK-02-TAIL canonical FQDN targets; CHK-03-FRACT tags; CHK-04-KM contract/journal/receipt, grouping root-owned. |
| Purity/storage | CHK-05-MUDA no prohibited/new dependency; CHK-06-GRAPH no renderer; CHK-07-DRIVE no device action, hardware test UNRUN. |
| Tests/mathematics | CHK-08-C1C8 scoped tests; CHK-09-MATH oracle/laws, theorem UNRUN; CHK-10-9MOD logs/source hashes; CHK-11-REGR negative cases and three mutants. |
| Runtime/observability | CHK-12-GLEAM policy tests; CHK-13-HERMES OCaml evidence; CHK-14-ZIGVM kernel UNRUN; CHK-15-MAX Mojo facade only, model inference UNRUN; CHK-16-OTEL full trace integration UNRUN. |
| Governance/VCS | CHK-17-SOV NOT_ADMITTED; CHK-18-JJ no worker VCS mutation. |
| Provenance | CHK-PROV EV-93 ceiling retained. |

</details>

## 13. Conclusion

The budget component is implemented and independently tested against its immutable oracle, concurrent processes and negative storage/input cases. The fixed reservation, single-grant and no-refund rules are ready for root's canonical paid-dispatch integration. Component completion does not claim aggregate production activation, live model quality or system admission.

[Previous: Jidoka journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0257-ecology-jidoka-completion.md) · [Next: receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0356-ecology-daily-budget-completion.json)

UOS · `uos/ecology-budget/20260909-0309` · Component tested · NOT_ADMITTED
