# Resource controls — numeric and observation authority specification

Observed host time: 2026-09-07T20:15:29Z. Chrony stratum 3, absolute offset
0.000273143 seconds; uncertainty 0.017918853 seconds. Prefix 20260907-1906
records the task-start UTC hour/second stamp; it is not the document completion time.
Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Candidate documents are local and unpublished. Navigation references do not assert
that this candidate is served by the running site.

[Journal](../journal/20260907-1906-resource-controls-journal.md) · [Review evidence](../reviews/20260907-1906-resource-controls-review.json)

## Scope and evidence state

Parent source: 311d2b12368d65c9b0f27f3d6adca315b94bbc62.
Candidate change: lyytwturtnwqrvmnlwkyvvvqvymzrysm.
Own Sa-plan plan: uos/resource-controls/20260907-1906; task RESOURCE-CONTROLS;
worker codex-side-resource-controls; original attempt 1.

This specification closes malformed numeric acceptance and misleading operational
preflight tests. It preserves the existing private receipt boundary and describes
the missing upstream observation authority. Local validation is complete for the
listed source hashes. Independent review and operational admission remain absent.

## Numeric contract

Let N be requested bytes, A available bytes, M proportional margin, and
F = 536870912 bytes. Inputs are OCaml integers and IEEE binary64 floats.

1. R-NUM-01: N < 0, A < 0, nonfinite M, or M < 0 yields unmet.
2. R-NUM-02: For valid inputs, set K to the exact rational value of the
   binary64 result of 1. +. M. The proportional requirement is A >= N * K.
   No byte count is converted to floating point. This specifies binary64
   parameter semantics, not an exact decimal interpretation of the input margin.
3. R-NUM-03: Also require A >= N and A - N >= F. Subtraction occurs only
   after the first comparison, so it cannot wrap across the integer range.
4. R-NUM-04: The laws include min_int/max_int inputs, subnormal margins,
   zero bytes and one-byte threshold differences above 2^53.
5. R-NUM-05: All pure evaluate results have receipt_bound=false.
   A met model fact alone never satisfies an operational envelope.
6. R-NUM-06: An empty envelope is vacuously satisfied. The operational bridge
   always declares nonempty state requirements, so missing directories cannot
   turn its envelope into an empty success.

Implementation uses the already available Zarith Q arithmetic. Its integer
operands are bounded by machine integer width and binary64 exponent width;
no unbounded solver or external observation is introduced. The reference oracle
uses independent IEEE-bit decomposition and Z integer cross multiplication.

## Observation and effect contract

R-OBS-01: Resource_envelope.check remains private. Observation and
observation_receipt remain abstract, without a public constructor or injector.

R-OBS-02: check_one and nonempty preflight return Implemented_unavailable
while the controlled owner is absent. They perform no raw filesystem observation.

R-OBS-03: run_swarm_bridge_programme.preflight_state_path validates the exact
declared state path and requests its envelope through Resource_envelope. It must
report unavailable owner status consistently whether the state directory is
present or absent. It must not create the directory, open the state database,
change existing bytes, or create SQLite sidecars after that refusal.

R-OBS-04: Existing successful fixture materialization exercises store/bridge
logic only. It must not be reported as successful production preflight.

R-OBS-05: The preserved parent attempt-fencing contract continues to reject
stale task attempts, expiry equality and stale bridge completion. These tests
do not establish end-to-end remote effect atomicity.

## Required upstream implementation before sensing can be enabled

| Dependency | Current evidence | Required implementation and acceptance |
|---|---|---|
| Root/current authority | run_root_bootstrap.mli explicitly marks operational parts nonconstructible | Implement current five-owner, target/event/effect and fence carriers with negative capability-construction checks. |
| Resource target owner | ops_external_resource_target.ml exposes Implemented_unavailable | Consume a genuine root-issued target-owner part, verify currentness and seal bounded observations. |
| Observation receipt binding | Resource_envelope exports no injector | Add an owner-only carrier bound to resource identity, request, epoch, trusted observation time and finite validity. Reject replay or substitution. |
| Effect use and fencing | Resource checks are admission prerequisites only | Recheck the same opened target and current epoch at effect time; support cancellation, recovery and idempotent completion. |
| Operational verification | Current tests deliberately cover refusal | Exercise actual bounded sensing, expired/wrong-resource receipts, insufficient space, owner crash/restart and stale completion under isolated fixtures before runtime cutover. |
| Independent admission | No independent reviewer in this side session | Review exact source manifest, evidence, migration/caller compatibility and deployment plan separately. |

None of these obligations is discharged by a board ACK, a priority score,
a caller-supplied Boolean, an unverified test summary or a synthetic observation.

## Verification and reproducibility

In the isolated candidate's engines/hermes directory, using OCaml 5.5.0,
Dune 3.23.1 and Zarith 1.14:

~~~sh
PATH=/home/an/dev/ver/zigvm/_opam/bin:$PATH dune build -j 1 \
  modules/hermes_harness/test_resource_envelope.exe \
  modules/system_engg/test_run_swarm_bridge_programme.exe \
  modules/sa_plan/test/test_sa_plan_leases.exe

_build/default/modules/hermes_harness/test_resource_envelope.exe
_build/default/modules/system_engg/test_run_swarm_bridge_programme.exe
_build/default/modules/sa_plan/test/test_sa_plan_leases.exe

PATH=/home/an/dev/ver/zigvm/_opam/bin:$PATH ocaml -I modules/hermes_ops \
  ../../tools/20260907-1906-resource-controls-mutations.ml \
  --dune /home/an/dev/ver/zigvm/_opam/bin/dune
~~~

Mutation execution is restricted to this named isolated workspace. It uses the
existing Ops_mutate runner with one-job, 30-second builds and 15-second tests,
restores exact source bytes and cleans its private fixtures. Rebuild the gold
executables after mutation testing before normal verification.

The reference comparisons cover 1,573 enumerated input combinations and 1,000
seeded samples (20260907 and 1906), within 4,343 resource assertions.
The bridge suite passes 23 checks. The inherited fencing suite passes 2,963
assertions. All eight targeted semantic mutants were killed with no voids.

A compile-positive control demonstrates the public evaluator is callable.
A separate compile-negative control rejects external creation of the private
receipt-bound record. This is a static capability boundary check, not proof
against malicious runtime memory corruption.

The normal full verifier discovers 309 suites but this isolated build contains
only three: 3 pass, 0 fail, 306 explicitly skipped. With --require-complete it
correctly exits 1. Full repository verification is incomplete.

## Verification checklist

Scope is this isolated source candidate. Unchecked items remain UNRUN or
NOT_ADMITTED; presence of this checklist does not imply 18/18 conformance.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Synchronized host observation and timestamp prefix recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN references supplied; candidate unpublished.
- [x] CHK-03-FRACT — Applicable fractal and ZK tags supplied.
- [x] CHK-04-KM — Specification, journal and machine-readable evidence linked.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Whole-fleet exclusion/dependency scan UNRUN.
- [ ] CHK-06-GRAPH — Whole-runtime NIF conformance UNRUN; candidate uses existing OCaml/Zarith.
- [ ] CHK-07-DRIVE — Hardware storage interlock execution UNRUN; no storage provisioning performed.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Complete UI/test categories UNRUN.
- [ ] CHK-09-MATH — Independent bounded oracle passed; Lean/Quint and four mathematical admission gates UNRUN.
- [ ] CHK-10-9MOD — Three available test executables passed; full nine-modality protocol UNRUN.
- [ ] CHK-11-REGR — Live UI regression monitoring UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Production supervision/cutover UNRUN.
- [ ] CHK-13-HERMES — Numeric and refusal-path tests passed; operational observation owner unavailable.
- [ ] CHK-14-ZIGVM — Runtime kernel verification UNRUN.
- [ ] CHK-15-MAX — Live trained MAX/Mojo inference not verified.
- [ ] CHK-16-OTEL — End-to-end trace/outcome correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review and system admission NOT_ADMITTED.
- [x] CHK-18-JJ — Isolated Jujutsu candidate, own Sa-plan task; no native Git, mainline merge or runtime restart.

</details>
