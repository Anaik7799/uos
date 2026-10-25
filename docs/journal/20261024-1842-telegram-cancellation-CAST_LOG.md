# 20261024-1842 Telegram cancellation verification CAST

Tags: #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda

## Incident and containment
Observed 2026-10-24 during canonical COMMAND_IMPL6 development verification.
Pinned repository-local OCaml toolchain compiled the isolated candidate.
The existing Ops verification offload ran 12 Sa-plan suites: 10 passed,
test_sa_plan_durable and test_sa_plan_leases exited139 with segmentation faults.
Lease tests crashed before the new cancellation cases. Acceptance is HOLD.
Canonical production database and runtime were not used.

## Control structure and process-model drift
Hypothesis H1: the new cancellation record/API affects existing native behavior.
Hypothesis H2: repository-local compiler/library environment differs from the
previously working build. H3: existing SQLite/statement lifetime defect or suite
fixture concurrency. These remain hypotheses, not established root causes.

The dangerous state is a newly compiled store accepted from compile-only evidence.
The offload reported actual failing exit statuses and stopped acceptance.

## Investigation and falsifiers
Before any retry, compare unchanged baseline under the identical environment.
Inspect exact compiler/library identities and statement/database lifetime evidence.
Do not delete or weaken failing existing tests. Preserve receipts for each
distinct experiment and do not mistake unrelated passing suites for clearance.

## Baseline comparison

The unchanged source under the identical repository-local toolchain passed all12 suites in0.1s. This contradicts a general toolchain failure and narrows the fault to candidate changes or candidate build state. Next diagnostic captures the native crash stack without accepting a rerun as clearance.

## Native lifetime evidence

Crash stack: sqlite3_finalize via caml_sqlite3_stmt_finalize during Store.with_stmt cleanup. A later diagnostic completed, establishing intermittency. The pinned upstream sqlite3-ocaml5.4.1 source releases the OCaml runtime in finalize and close without rooting the argument. Inference: an argument last-used by the OCaml caller can be collected during that native call. The controlled repair uses Core.Gc.keep_alive after finalization and close. Existing assertions remain unchanged. This is not a package-wide audit.

[Upstream5.4.1 source](https://raw.githubusercontent.com/mmottl/sqlite3-ocaml/5.4.1/lib/sqlite3_stubs.c), caml_sqlite3_stmt_finalize and caml_sqlite3_close. No dependency bytes are imported or modified. Core gc.mli locally documents keep_alive as maintaining liveness at the call point.

## Controlled verification outcome

All12 Sa-plan suites pass after lifetime guards, under normal and small-heap GC settings. Three deterministic source mutants were killed by their predicted tests; original source bytes restored. Dedicated concurrent-GC probev1 reproduced a baseline SIGSEGV, but saturated candidate throughput and timedout30s (notPASS). Probev2 added2ms collector yielding;20lifecycles passed both versions. Probev3 increased this calibrated workload to1000lifecycles: baseline SIGSEGV after at least250; repaired source completed1000 in2.4s. A1000-lifecycle regression is now part of the lease suite. These results support the missing-root/lifetime cause; they do not establish correctness of every API in the dependency.

## Residuals and recovery
No runtime deployment or schema migration performed. All fixtures are isolated.
Restore verified source bytes after any mutation experiment. Closure requires
a cause supported by changed evidence and successful affected regression.

[Task plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

## Comprehensive verification checklist

Checks below are obligations, not blanket passing claims.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — Observe synchronized clock evidence and document prefix.
- [ ] **CHK-02-TAIL** — Verify full Tailnet links and actual serving status.
- [ ] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping.
- [ ] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Verify exclusions against the candidate dependencies.
- [ ] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes graph boundary.
- [ ] **CHK-07-DRIVE** — Preserve the denied OS serial and test real interlocks only in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Verify all applicable C1–C8 surfaces.
- [ ] **CHK-09-MATH** — Measure the four declared mathematical gates.
- [ ] **CHK-10-9MOD** — Apply relevant unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos checks.
- [ ] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Observe actual OTP control/supervision behavior.
- [ ] **CHK-13-HERMES** — Observe bounded analysis and authoritative evidence.
- [ ] **CHK-14-ZIGVM** — Verify deterministic execution and descriptor-relative VFS.
- [ ] **CHK-15-MAX** — Observe actual isolated inference when applicable.
- [ ] **CHK-16-OTEL** — Verify clock and nonzero trace/span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Obtain candidate-bound independent review and authorized admission.
- [ ] **CHK-18-JJ** — Preserve standalone JJ, source ownership and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.
