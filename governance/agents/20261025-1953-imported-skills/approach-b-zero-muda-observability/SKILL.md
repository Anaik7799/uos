---
name: approach-b-zero-muda-observability
description: Govern fast functional algebraic Approach B execution with OCaml-only bounded parallelism, durable metrics, TUI/dashboard/OTEL observability, zero-muda controls, and fractal verification.
---

# Approach B: zero-muda observable execution

Approach B uses one immutable OCaml manifest, bounded dependency-safe fanout,
observational equivalence to a sequential oracle, and serialized durable
commit. Every effect is a typed interpretation; the algebraic core remains
pure and law governed.

## Hard rules

- Author implementation, automation, browser control and telemetry in OCaml.
- Make carrier, denotation, operations, observations, invariants, oracle,
  final interpretation and laws explicit at every fractal scale.
- Parallelize only independent dependency-ready work and compare the result to
  the sequential oracle before admission.
- Use durable leases and idempotency; never claim exactly-once external effects
  without proof.
- Every stage emits duration, budget, workers/threads, parallelism, process
  identifiers, input/output bytes, artifact count, complexity, cache state,
  dependency/lock waits, retries and terminal state.
- TUI, dashboard and OTEL are report-only observers. They never mint a gate
  verdict; the harness gate and readable evidence are authoritative.
- Zero muda rejects duplicate acquisition/rendering, unbounded polling,
  fabricated evidence and work with no requirement, control, test or evidence.
- Render timestamps as `YYYYMMDD-HHMMSS` after NTP validation. OTEL protocol
  timestamps remain Unix nanoseconds. Every journal has a validated Tailscale
  FQDN path.

## Fractal metric envelope

Use one associative metric carrier at L0 program, L1 subsystem, L2 slice, L3
stage, L4 process, L5 worker, L6 artifact, L7 page/component, L8 journal/ZK,
L9 evidence and L10 admission:

```text
Metric = { run_id; layer; plane; stage; process_id; worker_id; thread_count;
  parallelism; queued; active; completed; failed; retries; duration_ns;
  budget_ns; input_bytes; output_bytes; artifact_count; complexity; cache_hit;
  dependency_wait_ns; lock_wait_ns; otel_trace_id; timestamp }
```

Required views are throughput, p50/p95/p99 duration, budget variance, oracle
speedup, fanout efficiency, contention, bytes/artifact, complexity, failure,
retry and evidence coverage. The TUI shows stage, budget, worker lanes,
blockers, queue, cache and law/mutant verdict. The dashboard exposes the same
read-only observations; OTEL logs are structured and redacted by construction.

## Control and verification flow

```text
manifest -> validate/laws -> dependency scheduler -> bounded pure workers
  -> observational join -> serialized durable commit -> evidence observers
  -> TUI/dashboard/OTEL -> harness gate/admission
```

Use TDD red/green tests, BDD journeys, seeded properties, at least two named
mutants per new law, and typed OCaml Playwright for UI look-and-feel,
responsive/accessibility and evidence links. Apply STAMP/STPA/FMEA, ACH,
Admiralty, devil's-advocate and reality-check review at every scale. A budget
overrun changes telemetry and estimate; it never weakens a law.

## Acceptance

Require a green OCaml build, law/property/mutation evidence, oracle/parallel
homomorphism, UI evidence, safety packet, durable metric sample, no
unclassified residual, and exact-HEAD harness admission.

## Fractal FP atlas synchronization

For an atlas-governed diff, acquire the registry and source values once,
validate once, render eleven outputs once, and report validation duration,
surface/output counts, changed/unchanged counts, and bytes. A second warm run
must change zero bytes. Run `--selfcheck-fractal-fp-atlas` and `--wiki-audit`,
then record `phase:atlas_sync`; telemetry and the token are report-only, while
the exact-head gate remains authority.
