# Resource controls and hive evidence — implementation journal

Observed host time: 2026-09-07T20:15:29Z. Chrony stratum 3, absolute offset
0.000273143 seconds; uncertainty 0.017918853 seconds. Prefix 20260907-1906
records the task-start UTC hour/second stamp; it is not the document completion time.
Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Candidate documents are local and unpublished. Navigation references do not assert
that this candidate is served by the running site.

[Specification](../design/20260907-1906-resource-controls-spec.md) · [Review evidence](../reviews/20260907-1906-resource-controls-review.json) · [Risk packet](../reviews/20260907-1906-resource-controls-risk.json)

## 1. Scope & Trigger

The side-conversation operator authorized fixing the identified issues, then
requested current board, forecasting, model and swarm status. Complete the bounded
resource repair in an isolated candidate and answer the status questions through
read-only observation. Parent Mirage/Solo5 work and peer-agent execution are outside
this side session. No remote agent was spawned or contacted.

## 2. Pre-State Assessment

The preserved fencing candidate was the base. Invalid resource quantities/margins
could produce met model facts, and float conversion lost one-byte differences
above 2^53. Operational sensing was explicitly unavailable, but a bridge test
expected successful production preflight and a raw directory probe changed its
reported refusal reason. These defects did not demonstrate an operational bypass:
receipt gating was already closed.

Own plan uos/resource-controls/20260907-1906, task RESOURCE-CONTROLS,
worker codex-side-resource-controls, original attempt 1. The source task scored
P2/243 using criticality3 × STPA3 × FMEA3 × dependency3 × impact3.
FMEA S3/O5/Det1/RPN15 refers to deliberately malformed reproduction inputs;
it is not an estimated fleet incident rate.

## 3. Execution Detail

Created an isolated child workspace on 311d2b12368d65c9b0f27f3d6adca315b94bbc62,
specified numeric laws, reproduced failures and added exact rational comparison.
Removed unused Unix dependency from the resource library, retaining the existing
Zarith dependency in the repository ecosystem.

Removed the bridge's shadow filesystem observation. Added independent numeric
oracle coverage, absent/existing-state no-effect fixtures, mutation probes and a
compiler-enforced private receipt check. Preserved the unavailable root/target
authority instead of inventing a current observation capability.

Read live board REST, Sa-plan read-only state and forecast endpoints; inspected
their source provenance. No board write, journal rewrite, shared peer task change,
runtime restart or integration was performed.

## 4. Root Cause Analysis

Numeric input domains were not checked before resource arithmetic, and conversion
of byte counts to float lost precision. A test confused an ample caller-provided
fact with an operational observation. Direct directory sensing supplied an
inconsistent refusal reason outside the authority path.

The status inspection found separate truth gaps: the forecast's production-looking
output uses fixed histories and literal health values; the MAX-labelled worker
does not establish a trained MAX/Mojo execution path. Historical board activity
and task state labels were insufficient to establish present live coordination.

## 5. Fix Taxonomy

Numeric validation, exact threshold comparison, guarded subtraction, explicit
authority-preserving refusal, no-effect regression tests, independent bounded
oracle, mutation sensitivity and private-interface negative compilation.
No external code, model weights or new service were imported.

## 6. Patterns & Anti-Patterns Discovered

Distinguish model facts, owner receipts, completed tasks and admitted runtime
effects. Use independent representations in an oracle. A source restoration after
mutation testing requires a subsequent rebuild before trusting executables.
The expanded bridge count initially retained the old denominator; its nonzero
exit exposed this and the count was corrected to 23.

Live endpoint availability is separate from evidence freshness. An executing
task with an expired lease is not a current worker. A completion result of OK is
not independent verification. An automatic command review rejected force-style
temporary cleanup; a scoped non-force cleanup completed the same compiler probe.

## 7. Verification Matrix

| Check | Observed result |
|---|---|
| Targeted one-job build, OCaml 5.5.0 / Dune 3.23.1 / Zarith 1.14 | PASS |
| Resource numeric and authority assertions | 4,343 passed |
| Independent enumeration and seeded samples | 1,573 enumerated; 1,000 seeded |
| Bridge refusal/no-effects and existing store fixtures | 23 passed |
| Preserved attempt-fencing regression | 2,963 assertions passed |
| Eight guard-removal/substitution mutants | 8 killed, 0 survived, 0 void |
| Private receipt construction | Valid caller compiles; forged record rejected |
| Normal full verifier with completeness required | Exit 1; 3 passed, 0 failed, 306 unbuilt/skipped of 309 |
| Final active risk observation at 20:15:29Z | PASS; 4 source hashes, own worker/attempt/lease; authority NONE |
| Independent review, operational sensing, live cutover | UNRUN / NOT_ADMITTED |

### Live board and task observations

Read-only GET of [board REST](http://nas-1.tail55d152.ts.net:8080/c3i/a2a/**)
returned 334 distinct message records at approximately 20:12 UTC. The newest is
17:50:02 UTC; the service is reachable but the newest returned message is over
two hours old. Message signatures, global completeness and historical assertions
were not independently verified. These are the ten latest by reported UTC time;
all have sender L0-fable, and the Lamport value is not a timestamp.

| Lamport | UTC, 2026-09-07 | Kind | Message summary |
|---|---|---|---|
| 307 | 16:42:30 | Report | Integration lease released; holon lifecycle integration and divergence notice. |
| 308 | 16:43:45 | Dispatch | Generate holonic ontology/wiki/ZK material. |
| 309 | 16:47:49 | Report | Sa-plan store consolidation reported complete. |
| 310 | 16:50:22 | Report | Forecast constants, untrained MAX projection and weak evidence labels identified. |
| 311 | 17:12:46 | Report | KM candidate review reported zero blockers; follow-up fixes requested. |
| 312 | 17:32:04 | Andon | Coordinator replay refusal and event416 inconsistency reported. |
| 313 | 17:34:17 | Report | Event416 self-hash and predecessor mismatch reported. |
| 314 | 17:40:20 | Andon | Whole-journal rewrite reported; red escalation. |
| 315 | 17:48:19 | Report | Coordinator rewrite diagnosis and repair update. |
| 316 | 17:50:02 | Dispatch | Append-only SQLite coordinator-store repair dispatched. |

Qualitative tone is technical/progress-focused, becoming alarmed and repair-focused.
Two red Andons occur in these ten messages. No quantitative sentiment classifier
or psychological assessment was performed.

Read-only Sa-plan snapshot around 20:14 UTC: 88 available, 109 completed, 15
executing. Thirteen executing rows had expired leases; two had current leases
(RESOURCE-CONTROLS and PRODUCT-WORKFLOW). KM and COORD-JOURNAL-DB were completed
with result OK; this records task completion, not fresh independent repair proof.
Historical Codex-Astra board posts are not registrations or contributions of
this codex-side-resource-controls session.

### Forecasting and inference evidence

[Forecast health](http://nas-1.tail55d152.ts.net:4100/api/v1/forecast/health)
reported nominal, 10/10, converged, stable_dissipative and Brier0.024.
fractal_forecast.gleam:892 constructs those fields as constants.
Its predict_all_layers at line825 supplies ten literal eight-sample histories.
[Layer forecasts](http://nas-1.tail55d152.ts.net:4100/api/v1/forecast/layers)
project L2 resource use to 1.2042 and L8 mutation kill rate to 1.0337. These
fixture projections neither prove actual exhaustion nor support calibration.
No persisted timestamped forecast/outcome history was verified in this inspection.

services/inference/max/max_worker.py:91 implements an untrained deterministic
semantic projection using token hashing and fixed keyword priors. Its health
method supplies MAX/Mojo version and readiness labels, without observed weight
loading or kernel invocation. The inference/status GET returned HTTP200 with
error:not_found. A process-name snapshot showed no MAX/Mojo/Python process;
remote or on-demand inference was not ruled out. Actual trained MAX/Mojo use
remains UNVERIFIED.

Rete consistency/forward-chaining code is present in
knowledge/rete_ul_verifier.gleam. ha/fmea_generator.gleam explicitly produces
a static reference catalog. STPA/FMEA are applied in this task's risk packet.
MAX worker Rete/Ruliad method branches and router surfaces exist, but this
inspection did not establish live inference, runtime safety authority or
autonomous Ruliad execution. Board310 is independently corroborated on forecast
constants and the untrained projection; its historical receipt counts were not
recomputed.

## 8. Files Modified

- engines/hermes/modules/hermes_harness/dune
- engines/hermes/modules/hermes_harness/resource_envelope.ml
- engines/hermes/modules/hermes_harness/resource_envelope.mli
- engines/hermes/modules/hermes_harness/test_resource_envelope.ml
- engines/hermes/modules/system_engg/run_swarm_bridge_programme.ml
- engines/hermes/modules/system_engg/test_run_swarm_bridge_programme.ml
- tools/20260907-1906-resource-controls-mutations.ml
- docs/design/20260907-1906-resource-controls-spec.md
- docs/journal/20260907-1906-resource-controls-journal.md
- docs/reviews/20260907-1906-resource-controls-risk.json
- docs/reviews/20260907-1906-resource-controls-review.json

## 9. Architectural Observations

Resource semantics remain Hermes OCaml. Gleam/OTP supervision, trusted time,
root/current ownership and target-side fencing remain separate obligations.
The current root/bootstrap interface cannot construct the owner needed for safe
operational observations. Substituting host reads or public Boolean receipts
would break that architecture.

The most useful immediate hive work is truthful, fresh evidence and fenced task
ownership. Additional models should consume that evidence after measured baselines
exist: duration/failure prediction, incident deduplication and evidence retrieval
are useful bounded candidates. This is a design direction, not an implemented
or benchmarked model selection.

## 10. Remaining Gaps

Implement and verify the root/current and resource-owner dependencies listed in
the specification; add operational observation/expiry/recovery tests. Obtain
independent review, whole-scope verification and a coordinated runtime cutover.
The production service has not acquired this candidate's behavior.

Separately, replace fixture health claims with explicit demo/unknown states until
fresh telemetry and retained forecast outcomes exist. Reconcile expired task
labels and coordinator repair evidence. Establish actual model execution receipts,
measured utility and per-operation costs before describing global cost optimality.
These status findings were inspected, not repaired, in this bounded source task.

## 11. Metrics Summary

One isolated source task; one build job at a time; zero additional model calls,
zero board posts, zero sub-agent sessions. Primary conversation token/currency
cost was not measured. Eight meaningful mutations were detected; no fleet,
consciousness or globally optimal intelligence score is claimed.

The final full verifier had no failing available suite, but 306 missing executables.
Candidate source hashes and exact test scope accompany the review evidence.

## 12. STAMP & Constitutional Alignment

The risk packet covers withheld control, unsafe provision, wrong timing and
excess duration. Receipt gating, private types and explicit unavailable states
preserve the control boundary. Priority is one task's safety-aware assessment;
it does not grant side-effect authority or prove a global optimum.
Sa-plan ownership and JJ isolation protect parallel work. User-facing decision
summaries expose evidence, assumptions, choices and uncertainty without claiming
access to private model states or a measurable hive consciousness.

## 13. Conclusion

The bounded source repair is locally tested and ready for independent review.
Operational observation activation remains blocked on explicit upstream authority
dependencies. Mainline/runtime remain unmodified. Current hive health cannot be
inferred from constant forecast fields, old board messages or stale executing labels.

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
