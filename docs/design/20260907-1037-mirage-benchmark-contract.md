# Mirage library benchmark contract

#fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web

Created: 2026-09-07T10:40:37Z. Candidate under audit: 91eb7ebba529f7506369dc5d82738722579deac4. State: implemented and tested at source composition 0384a714bf5fe469b9c37accc58a11e98ba016a6. Deployment remains NOT_VERIFIED. [Audit and verification](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1150-mirage-sovereign-audit-and-benchmark.md).

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Mirage](http://nas-1.tail55d152.ts.net:4100/mirage) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist) · [Source](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1037-mirage-benchmark-contract.md)

## Scope and observations

The operator requested sovereign verification of MirageOS and a new feature. Add a bounded CLI benchmark over the existing Hermes in-memory block and Merkle key/value implementations. Reuse these kernels and the current CLI/catalog; add no broker, daemon, inference request, external source import or native kernel.

A run reports validated round trips, actual library-call counts, deterministic content checksums and measured process CPU seconds. Runtime scope is the host OCaml process. It supplies no Solo5 boot measurement, resident-RAM saving, TLS handshake evidence or certification.

## Semantic domain and glossary

| Concept | Kind | Observation and invariant |
|---|---|---|
| Configuration | Validated value | Iterations n in 1..10000; default 256 |
| Workload | Closed variant | Block round trip or key/value round trip |
| Work item | Pure planned operation | Slot i mod 16; payload of 512 copies of byte i mod 251 |
| Summary | Private observation | n completed round trips, 2n successful library calls, actual payload checksum |
| Measurement | Private observation | Summary and finite, nonnegative process CPU duration |
| Run | Bounded effect interpretation | Both workloads complete successfully or a typed error is returned |

Payload storage uses at most 16 slots of 512 bytes per workload. This bounds retained test payload, not OCaml heap size or process RSS. Setup, validation and process-CPU timing remain identified parts of the host benchmark. Benchmark output has no operational authority.

## Requirements and laws

| ID | Requirement and quantified law | Verification |
|---|---|---|
| MB-01 | Constructor accepts n iff 1 <= n <= 10000 | Boundary and negative constructor cases |
| MB-02 | Successful execution reports rounds=n and library_calls=2n | Shared oracle/native law suite |
| MB-03 | Every returned payload equals its planned payload byte-for-byte | Real write/read and set/get checks; corrupt-output negative control |
| MB-04 | Summary checksum equals the sum of bytes actually returned, using bounded Int64 arithmetic | Independent list oracle versus loop implementation; seeded runs |
| MB-05 | Repeating the same configuration preserves all semantic observations | Repetition law; duration deliberately excluded |
| MB-06 | Oracle and native interpretations agree on every summary observation | Twin seeded configurations over both workloads |
| MB-07 | Invalid or backwards/nonfinite CPU observations never become successful measurements | Injected clock failure controls |
| MB-08 | Zero measured CPU duration yields no computed throughput | Explicit absence instead of division by zero or fabricated zero |
| MB-09 | CLI rejects malformed, out-of-range or surplus benchmark arguments with nonzero exit | Actual subprocess checks |
| MB-10 | Catalog declares the feature's scope and bounds without altering deployment admission | Catalog and CLI schema checks |

Configuration construction, iteration observation, workload selection, execution, summary observation, measurement and JSON projection are covered above. No associativity claim is made about elapsed CPU measurements. Correctness and performance are separate observations.

## Interpretations and verification choice

Initial interpretation: a bounded list of planned indices, independently folded into expected counts and checksum. Final interpretation: a bounded loop invoking the existing block/KV APIs, checking each actual returned payload and accumulating its checksum. The equality obligation excludes timing and compares all semantic summary fields.

Use deterministic algebraic tests and independent negative controls for this finite workload. No solver or theorem prover is needed to label a host timing sample. Test seeds and limits, compiler/Dune versions, mutant outcomes and known kernel defects must be recorded with the implementation candidate. An audit finding or benchmark result never changes a migration to Admitted.

## Process and forecast

Decision summary: choose the operator's benchmark option because it yields measured evidence from existing kernels without adding a telemetry stack. The existing catalog's static savings and speedup numbers are declared estimates; they are not inputs to the measurements.

Expected behavior: supported workloads return bounded JSON with verified summaries; invalid inputs and broken kernels fail explicitly. Timing is machine-specific and no pass/fail performance threshold has been authorized. Rollback consists of reverting the isolated source candidate; live cockpit/router and observer services require no restart for this feature.

## Verification checklist

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- [x] CHK-01-TIME — Observed host timestamp used.
- [ ] CHK-02-TAIL — Full Tailscale FQDN links provided; new document serving awaits integration.
- [x] CHK-03-FRACT — Fractal tags present.
- [x] CHK-04-KM — Mirage, wiki, ZK and contract linked.

</details>
<details><summary>Domain 2 — Purity and storage safety</summary>

- [x] CHK-05-MUDA — Existing OCaml carriers selected; no new runtime dependency planned.
- [x] CHK-06-GRAPH — Dependency set unchanged; current-tree Zero-Muda gate passed.
- [x] CHK-07-DRIVE — Benchmark uses memory only; no disk allocation or OS storage mutation.

</details>
<details><summary>Domain 3 — Tests and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Feature presentation checks pending.
- [ ] CHK-09-MATH — Global quality metrics are not measured by this benchmark.
- [ ] CHK-10-9MOD — Law, negative and mutation checks passed; no nine-modality claim.
- [ ] CHK-11-REGR — Relevant Mirage regressions passed; full CEPAF baseline failures remain.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [ ] CHK-12-GLEAM — Existing actors are audited separately.
- [x] CHK-13-HERMES — Four native test actions and independent benchmark reviews passed.
- [ ] CHK-14-ZIGVM — No ZigVM admission change.
- [ ] CHK-15-MAX — No inference needed or measured.
- [ ] CHK-16-OTEL — Benchmark JSON does not imply collector delivery.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Candidate audit and production admission remain distinct.
- [x] CHK-18-JJ — Isolated standalone JJ workspace; native Git mutations prohibited.

</details>

Previous: [Mirage cockpit](http://nas-1.tail55d152.ts.net:4100/mirage) · Next: [Migration API](http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/candidates)

UOS footer: host-library measurements only; unknown deployment evidence remains unknown.
