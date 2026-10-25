---
name: otp-conformance-protocol
description: Run, extend, and interpret the ZigVM↔OTP conformance protocol (functional, performance, and scalability equivalence against the pinned OTP 30-rc oracle) without weakening its controls. Use when executing OTP30_PARITY_PLAN.md epochs, adding opcodes/BIFs/suites/benchmarks to coverage, triaging a DIVERGENT verdict, touching thresholds/baselines/ledgers, or re-pinning the OTP target.
---

# OTP Conformance Protocol

The real OTP runtime is the system-level oracle; the whole of zigvm is the
final encoding; the OCaml harness proves the homomorphism. This skill keeps
that proof honest.

## Ground documents

Read `OTP30_PARITY_PLAN.md` §1–§3 (pin, pillars, protocol) before any
conformance work, plus `DIVERGENCE_LOG.md` and the latest SQLite baseline.

## Rules

1. **The pin is the contract.** All verdicts are keyed by (pin SHA, host).
   Never compare or merge evidence across pins or hosts. Re-pinning is a
   deliberate slice: update `third_party/OTP30_PIN`, re-run `--verify-otp`,
   re-baseline, journal it.
2. **Verdicts only move up the lattice by fixing, never by relabeling.**
   `DIVERGENT → EQUIV` requires a `DIVERGENCE_LOG.md` entry with the same
   rigor as an EQUIVALENT mutant: the divergence, why it is intentional, and
   the law that still bounds it. `DIVERGENT → EQ` requires a code fix plus a
   green re-run.
3. **UNTESTED is visible, never silent.** Missing oracle, pre-SMP scale rows,
   policy-blocked suites (LA-7) are recorded as `UNTESTED(<reason>)` rows —
   never skipped, never dropped from the ledger.
4. **Ratchets never weaken.** EQ counts per pillar are monotone against the
   accepted baseline; `perf_thresholds` floors and scalability δ bands only
   tighten. Any decrease requires a plan amendment in
   `OTP30_PARITY_PLAN.md` (the harness checks the plan hash) and a journal
   entry.
5. **Totality before depth.** New opcodes/BIFs/suites enter the ledgers the
   moment the pin knows them (`--gen-ledgers` fails on unclassified rows);
   implementation then flips rows to EQ. Never hand-edit ledger rows.
6. **Measurement discipline.** Perf/scale rows follow the plan §2.2/§2.3
   protocol: same host, N=7, median, MAD-validity, host fingerprint recorded.
   A noisy run is re-run, never averaged.
7. **Baselines are accepted, not assumed.** Only `--accept-baseline` after a
   fully green `--conformance` run; cite the run id in the journal.
8. **Boundaries hold.** Harness stays OCaml; VM semantics stay Zig; Erlang
   fixture code (case printer, corpus, bench twins) lives under
   `fixtures/erl/`; standalone automation is OCaml-only under `scripts/`
   (`docs/OCAML_SCRIPTING_SOP.md`).
9. **Capability/Operability totality (the {C,O} axes).** A production-surface
   feature (socket/port/NIF/dist-transport/tracing/hot-load/release-boot) enters
   the `capability_ledger` the moment the pin's use-case matrix names it —
   classified `EQ`/`EQUIV`/`UNTESTED(reason)`/`ABSENT(sev)`, never silently
   omitted; `--gen-ledgers` fails on an unclassified production feature. A wired
   seam is admitted only by a whole-system differential/round-trip law vs real
   OTP-30 (RUNTIME-CAPABILITY-EQUIVALENCE), never by "compiles + returns
   plausibly." An introspection/metric BIF that can't return a true value returns
   `not_implemented`, NEVER a plausible constant (FM-OBS-1). Triage row 5:
   capability regression = a wired seam that stopped serving.
10. **Oracle determinism.** Perf/scale/differential samples SHOULD come from a
    bit-reproducible oracle run (`--record`/`--replay`,
    `docs/DETERMINISTIC_REPLAY_FRACTAL_ALGEBRA.md`); a divergence must be
    *replayable* before triage, not re-measured away (CTRL-REPLAY-ORACLE,
    extends Rule 6).
11. **Verify by exit code + `harness_runs.status`, never printed text**
    (CAST-12). A mode can print "every status OK" AND exit 1; a TSan run
    prints "tests passed" AND reports a data race. The verdict is `$?` plus
    the SQLite row (and for TSan the "data race" line), never the friendly
    summary line.
12. **A green suite is necessary-not-sufficient for CONCURRENCY relocations**
    (CTRL-SMP-INTERLEAVING). A lock-relocation slice additionally needs the
    `skills/smp-concurrency-slice` trust protocol (TSan + conservation
    drop-net + metamorphic law + the runtime order checker) — the gate alone
    inspects only the one interleaving that ran.

Governance: `docs/OTP30_PARITY_OPERATING_MODEL.md` (the operating model wiring
these into skills/SOPs/rules/STPA/FMEA/agents/harness-controls).

## Commands

```sh
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --conformance
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --verify-otp
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --gen-ledgers
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --run-erl-corpus
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --bench
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --accept-baseline
```

(All conformance modes shipped long ago — E0 is CLOSED. The canonical gate
`opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD"` is the
internal law gate; `--conformance` is a SEPARATE run that must be triggered on any
parity-surface change — see `docs/CLAUDE_HARNESS_SOP.md` for the lockstep rule that
keeps the `verdicts` ledger from drifting behind the code.)

## Triage flow for a red conformance run

1. Classify: functional (verdict rows), performance (floor), scalability
   (band), or ratchet regression.
2. For functional: reproduce the single case both sides
   (`--run-ct SUITE`/`--run-erl-corpus`), then superpowers:systematic-debugging;
   the fix lands as a normal algebraic slice (oracle, laws, mutants, docs).
3. For perf/scale: verify measurement validity first (MAD, host fingerprint),
   then profile; representation changes still require the module's
   homomorphism laws to stay green.
4. For ratchet regressions: the regression is the bug. Find the slice that
   lowered coverage; never re-baseline around it.
5. For a FLAKY/intermittent red (a green re-run does not clear it): a flaky gate
   is a **quotient leak** — the verdict depending on entropy the observation
   quotient claims to erase (random test `seed`, ASLR, heap layout). Capture the
   printed seed (it makes the red reproducible), then root-cause with
   superpowers:systematic-debugging. Beware the **observer effect**: `debug.print`
   / a rebuild reshuffles the layout and hides the bug — prefer a non-perturbing
   probe (gdb on the failing binary, a captured seed) and reason from the invariant.
   Fix by **constructive determinism** (make the entropy unobservable in the
   denotation — e.g. fixed zero-init storage, bounded static-length reads), NEVER
   by re-seeding to green (that admits `run(seed,aslr)` as the denotation instead of
   its quotient). Record a `CAST_LOG.md` entry (see CAST-17) + a fix slice; a red
   is a red until the fix, not the lucky side of the coin.

## Harness engine note (harness-P7)

The default gate is DAG-driven (incremental + parallel); ledger/corpus/bench
modes are unchanged sequential actions and their evidence semantics are
untouched — the ratchet reads verdicts exactly as before. `--sequential`
reproduces the pre-engine gate verbatim when comparing evidence across the
cutover.
