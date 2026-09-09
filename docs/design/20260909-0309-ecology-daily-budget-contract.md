---
title: Ecology daily OpenRouter reservation contract
observed_at: 2026-09-09T03:04:09Z
plan_id: uos/ecology-budget/20260909-0309
task_id: DAILY-BUDGET
status: COMPONENT_TESTS_PASSED
runtime_admission: NOT_GRANTED
tags: [fractal-l2, fractal-l4, zk-adr, zero-muda]
---

# Ecology daily OpenRouter reservation contract

#fractal-l2 #fractal-l4 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0309-ecology-daily-budget-contract.md)

This contract implements the operator's explicit $10/day paid-model budget using a conservative $0.25 reservation per request, with no refunds. Root confirmed the business laws and the 4,096-token paid limit; the existing free route remains independently bounded at 512 tokens. The budget mechanism does not choose work, route needs, execute tasks or authorize deployment. Root reuses the existing need/class router.

## Observations and domain

| Concept | Category | Meaning and observation |
| --- | --- | --- |
| Nanodollars | Value object | Integer USD × 1,000,000,000; no floating-point ledger arithmetic |
| Request | Validated command | Unique bounded call ID, allowed model, output-token ceiling and input/body byte counts |
| Reservation | Append-only event | Exactly 250,000,000 nanodollars of liability held before a paid dispatch |
| UTC day | Clock value | Derived from the CLI's observed host clock, never supplied by the request |
| Daily liability | Observation | Sum of that ledger's reservation events for the current UTC day |
| Remaining budget | Observation | 10,000,000,000 minus daily reserved liability |
| Actual spend | Unknown observation | Null in this ledger; reservations are not measured invoices or actual cost |
| Ledger | Aggregate/interpreter | One canonical SQLite path, reused by every production paid adapter |

The global limit is only global when production uses one canonical database. The CLI reports its exact ledger path and does not claim exclusivity across independent files. Scratch databases are test fixtures. Root's adapter owns canonical-path binding, exact Sa-plan plan/task/worker/attempt checks and network dispatch.

## Pure policy and price bounds

Gleam validates model, UTF-8 input bytes (at most 16,384), full request-body bytes (at most 65,536), completion ceiling (1..4,096), a zero provider request fee and live prices no higher than the configured provider ceilings. A 2,048-token template allowance is added to input bytes. Integer upward-rounded prices make:

`worst_case = (input_bytes + 2048) × prompt_ceiling + max_tokens × completion_ceiling`

Admission requires `worst_case <= 250000000`. The maximum supported Kimi request reserves against 116,736,000 nanodollars of modeled worst-case cost, below the fixed reservation. The ledger repeats these integer bounds as defensive storage validation. Root's provider adapter separately verifies final usage and cost and prevents an unvalidated body/price from reaching network dispatch.

| Exact paid model | Prompt ceiling, nano/token | Completion ceiling, nano/token |
| --- | ---: | ---: |
| `z-ai/glm-5.3` | 1400 | 4400 |
| `moonshotai/kimi-k3` | 3000 | 15000 |
| `deepseek/deepseek-v4-pro-0813` | 1320 | 3960 |
| `deepseek/deepseek-v4-flash-0731` | 65 | 180 |
| `google/gemma-4-31b-it` | 90 | 340 |

These are the root-approved provider ceilings, not claims that catalog minima are available on every provider. In particular, DeepSeek Pro uses the approved ZDR provider ceiling, not its lower model-catalog minimum. Root owns the dated primary-source/provider evidence and routing constraints.

## Public command surface

`ecology_budget.ml init DB` provisions a previously absent ledger explicitly. `reserve DB` reads one JSON object from stdin containing exactly `call_id`, `model`, `max_tokens`, `input_bytes` and `body_bytes`. `status DB` is read-only. The adjacent Mojo facade forwards the same finite argv/stdin surface to the same OCaml core without shell or Python execution.

The call ID is 1..128 ASCII characters from letters, digits, period, hyphen, underscore and colon. Unknown fields, malformed JSON, oversized input and invalid model/token/byte bounds are rejected. A request cannot override clock, UTC day, budget or reservation amount.

A fresh committed reservation returns `status="reserved"` and `dispatch_authorized=true` for that call and ledger. Every duplicate, exhausted budget, missing/corrupt ledger, rollback or operational error returns false and an unsuccessful exit status. A lost/uncertain response does not refund liability: retrying its call ID is refused, preventing a second dispatch grant. An explicit successful budget reservation still grants no Sa-plan task or effect authority.

## Requirement-to-law map

| Law | Equation or rejection contract | Tests and discriminating defect |
| --- | --- | --- |
| B1 Cap preservation | Every accepted event preserves `0 <= daily_liability <= 10000000000` | Boundary 40/41, concurrent final-slot race; remove cap check |
| B2 Fixed liability | Accepted reserve adds exactly 250000000; no refund operation exists | Counterfactual actual-cost differences leave liability unchanged |
| B3 Single grant | A call ID can cause at most one accepted event across all days | Sequential/concurrent duplicate race; remove unique/duplicate guard |
| B4 Clock order | A clock observation older than initialization/latest accepted event is rejected | Rollback and next-day tests; ignore persisted timestamp |
| B5 Persistence/replay | Restarted status equals replay of committed reservations | Separate-process reopen and oracle/SQLite trace agreement |
| B6 Append-only | Existing metadata and reservations reject update/delete | Raw SQL falsifiers; remove triggers |
| B7 No missing-state recovery | Reserve/status cannot create a missing or corrupt ledger | Missing/truncated/schema-tampered file; implicit SQLite create |
| B8 Liability truth | Actual spend remains null; remaining equals limit minus liability | JSON observation checks; label liability as actual spend |
| B9 Bounds | Invalid request/time/resource bounds yield no event or grant | Negative constructors and exact UTF-8/token/price limits |
| B10 Atomicity | Parallel accepted reservations are observationally equivalent to some serial order | Actual independent-process race, `BEGIN IMMEDIATE` transaction |

The initial interpretation is an immutable event-list oracle. SQLite is the persistent interpretation. Shared laws and bounded deterministic traces compare public observations rather than internal representation. Environmental/schema failures are explicit interpreter rejections. Request ordering is not commutative at the cap; no such law is claimed.

## Effect and storage boundary

The OCaml ledger uses an immediate SQLite transaction for observation and append, a unique call-ID key, constant amount/budget checks and append-only triggers. It rejects missing/invalid schema, corrupt storage, clock rollback and unknown failures. Public clocks come only from the host. SQLite persistence is not a substitute for secure ownership of the canonical path; the service operator remains responsible for its filesystem and credentials.

The default reservation wastes some budget deliberately: at most forty paid requests can be granted in one UTC day. A timed-out request keeps its reservation. Adding refunds, smaller exact reservations or cross-ledger federation requires a new contract and tests. This slice performs no network calls.

## Component verification and driver handoff

The immutable oracle passed 55 initial checks before the SQLite interpretation was implemented. Final validation passed 398 native OCaml checks, including 47 shared laws per interpreter, 128 deterministic differential steps with seed `20260909`, two actual eight-process races and three killed behavioral mutants. A missing required storage operation fails compilation. Six Gleam tests pass on OTP 29/ERTS 17.0.5. Five CLI cases agree through the native Mojo facade and direct OCaml entry point; only observed clock and scratch-ledger path are normalized for comparison.

Repeat the OCaml/SQLite/Mojo checks from the repository root using `ocaml tools/validation/ecology_budget_check.ml /tmp/UNIQUE-FRESH-DIRECTORY`. The test driver uses only existing repository-pinned OCaml and the realized MAX/Mojo environment with `--no-install --frozen`. It does not initialize the production ledger.

The production driver must first validate actual input/body bytes and live provider price through `daily_budget.admit`, use a stable unique call ID, verify the current exact Sa-plan worker/attempt, and invoke `reserve` on its one canonical path through the existing bounded process guardian. A suggested ledger bound is 5,000 milliseconds and 4,096 output bytes. The JSON input must be followed by EOF. Verify exit status zero, `status="reserved"`, `dispatch_authorized=true`, the exact ledger path/call ID and fixed budget constants. Recheck the task fence before dispatching the same admitted immutable model/body/token request once. A lost response cannot be retried for another grant. `daily_budget.validate_usage` checks the returned usage against the specific admitted byte/token bounds; it performs no refund.

The CLI's success receipt reports `daily_reserved_nanodollars`, `remaining_nanodollars`, `reservation_count`, the observed UTC day/time, `actual_spend_nanodollars=null`, `refunds_supported=false`, `budget_scope="this_database_only"` and `task_authority=false`. Status never grants dispatch. Failure exits unsuccessfully and reports `dispatch_authorized=false`; missing/corrupt files are never created or repaired by reserve/status.

SQLite uses STRICT tables, exact source-owned schema validation, integrity checking, append-only/replacement/cap/clock triggers, a 1,000 ms busy timeout and a fresh immediate transaction per reservation. Files are bounded at 32 MiB for the main DB, 8 MiB for WAL and 1 MiB for SHM. A monotonic 30-second cooperative operation deadline and the caller's independent process guardian bound work; the cooperative check alone cannot interrupt blocked stdin or an in-progress SQLite call. Ledger and sidecar symlinks are refused. Hostile same-user filesystem/schema modification remains outside the trusted canonical-path owner boundary.

Canonical provisioning, final paid adapter binding, live network calls and aggregate-budget activation remain root-owned and are not established by these scratch-database tests.

<details>
<summary>Comprehensive verification checklist: component scope and explicit unknowns</summary>

| Domain | Checkpoint scope |
| --- | --- |
| Metadata/navigation | CHK-01-TIME host evidence; CHK-02-TAIL FQDN links; CHK-03-FRACT tags; CHK-04-KM contract and timestamped completion receipt. |
| Purity/storage | CHK-05-MUDA no new prohibited dependency; CHK-06-GRAPH no renderer dependency; CHK-07-DRIVE hardware test UNRUN, no storage-device action. |
| Tests/mathematics | CHK-08-C1C8 scoped 398 native/6 Gleam/5 facade checks; CHK-09-MATH oracle/laws pass, no theorem admission; CHK-10-9MOD logs and source hashes; CHK-11-REGR three mutants and negative storage/input cases pass. |
| Runtime/observability | CHK-12-GLEAM pure policy; CHK-13-HERMES OCaml ledger; CHK-14-ZIGVM kernel test UNRUN; CHK-15-MAX no inference in this slice; CHK-16-OTEL full trace correlation UNRUN. |
| Governance/VCS | CHK-17-SOV NOT_ADMITTED; CHK-18-JJ no worker VCS mutation. |
| Provenance | CHK-PROV EV-93 ceiling retained; no new EV number. |

</details>

[Previous: Jidoka journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0257-ecology-jidoka-completion.md) · [Next: planning](http://nas-1.tail55d152.ts.net:4100/planning)

UOS · Sa-plan `uos/ecology-budget/20260909-0309` · Component-tested contract, not release admission
