# 20260921-0631 — MAX client declarations and compatibility counterevidence

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

**UOS / Journal / Inference inventory** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Created: 2026-09-21T06:47:31Z, observed source-workflow origin. **DEVELOPMENT ONLY; t1 INCOMPLETE; NOT_ADMITTED.**
[Census](http://nas-1.tail55d152.ts.net:4100/files/governance/capability-inventory/20260921-0631-system-feature-inference-census.json) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260921-0631-system-feature-inference-evidence.json) · [Risk](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260921-0338-execution-optimization-risk.json) · [Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20260920-1438-hive-swarm-mcp-recovery-plan.md)

## 1. Scope & Trigger

Continue canonical Sa-plan t1-tracker, attempt2, under workflow uos/system-mcp-features/20260919-1642/t1-inference/20260921-0631. User requires all-system MCP coverage and real coordination; a finite client-method source was missing from the tracker. Scope is pure declarations, wire preservation and source counterevidence, not backend implementation or runtime admission. No worker execution, package installation, alias enablement, production action or canonical inventory import.

## 2. Pre-State Assessment

The completed interface checkpoint represented848records, not848working services. MAX client has13request encoders and12response decoders, but no transport implementation in that module. The worker accepts27names in16dispatch groups; four client names are absent. Separate ecology worker exposes linear_softmax. The old contract lists eight methods and requires some fields at top level that the client nests under params. Kalman state prior remains qualitative; no calibrated model is claimed.

## 3. Execution Detail

Captured exact13pre-refactor request bytes from existing compiled Gleam builders. Added a finite Method sum type, all_methods and total method_name observation; existing builders now consume it without changing their wire format. The MaxClient census reads this same declaration source with exact app-manifest/client-file pins and13ID fingerprint. It emits CLIENT_METHOD_DECLARED_TRANSPORT_UNVERIFIED, no inferred MCP endpoints, and unknown owner, holon, dependencies and layers.

The aggregate census conserves861records across12source sets and15shards. A private Sa-plan SQLite roundtrip preserves all13client declarations as unmapped. Existing connected MCP read_file returns the exact250197-byte census artifact. This is artifact delivery, not a new tool call, canonical import or inference operation.

## 4. Root Cause Analysis

| ACH hypothesis | Diagnostic evidence | Disconfirmation |
|---|---|---|
| H1: Presence of a MAX worker establishes client compatibility | Four client method names are not accepted; contract has different shapes | Disconfirmed by source inspection |
| H2: Renaming to existing aliases repairs support | Source-pinned aliases return placeholder success objects rejected by typed decoders | Disconfirmed by structure tests, not worker execution |
| H3: Decoder success proves real execution | Synthetic complete structures with fixture-only status decode successfully | Disconfirmed; decoding is structural |
| H4: Any negative decoder test is trustworthy | Missing latency or malformed JSON can falsely explain refusal | Controlled by parsed common envelope and positive counterfixtures |
| H5: Typed float decoder accepts integer JSON fixtures | Counterfixture run produced35PASS/1FAIL on integer tokens | Disconfirmed; fixture corrected to decimal tokens, production decoder unchanged |

Missing transport, unsupported methods and hard-coded worker responses are separate defects. This slice records them rather than hiding them with aliases or invented schema compatibility.

## 5. Fix Taxonomy

Poka-Yoke: finite constructors, one method-name interpretation shared by builders, exact ID/body pins, frozen wire hash and valid negative controls. Jidoka: explicit ACTIVE_OBSERVATION_PASS checks before final validation; no authority or worker invocation inferred. Muda: reuse existing typed builders, catalog algebra and Sa-plan storage rather than a parallel scheduler or mock backend.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate and Popperian falsification exercise missing/modified source files, missing bindings, duplicate bodies, wrong counts/fingerprints and source permutation. Five ID shapes across all13builders preserve JSON escaping and method identity, including Unicode and NUL. This pure serialization test is not permission to send those payloads through any effect boundary.

Worker-source placeholder objects are reconstructed with their actual latency envelope, parsed as valid JSON, and rejected by all four typed decoders. Four synthetic complete counterfixtures demonstrate structural success only. The first positive fixture incorrectly serialized float fields as integers; the failure and repair are retained. Source reviewers are internal advisory participants, not external sovereign identities.

## 7. Verification Matrix

Admiralty B2 denotes bounded local development evidence corroborated by independent source review. It does not satisfy production admission.

| Check | Result | Scope |
|---|---|---|
| Getter RED |2failed/1passed|Empty method declaration stub; golden old wire remained passing|
| Census RED |2failed/4passed|Unimplemented MaxClient source|
| Counterfixture setup |35passed/1failed, then corrected|Strict float-token fixture mismatch; no production change|
| Final focused suite |36passed/0failed|7inference,9census,8interfaces,12existingMAX tests|
| Actual13record DB persistence |PASS9.617s|Private Sa-plan fixture, unmapped declarations|
| Final full regression |11,983passed/0failed, exit0; /tmp/uos-inference-regression.VdgpBJ|Pinned Gleam1.16.0/OTP29;300second bound|
| Connected MCP read_file |PASS exact250197bytes|Artifact only|
| Format check |PASS|Census and changed test files; no whole-file legacy reformat|
| Journal lint |10/10 PASS|Mechanical structure, not execution of seven engines|
| Worker/transport/production/formal admission |UNRUN|No authority amplification|

The prior interface checkpoint's shared-source HOLD and mistaken post-HOLD batch remain preserved in its journal; they are not erased by these later passes. No new HOLD was bypassed in final validation.

## 8. Files Modified

Production changes are max_inference_daemon.gleam and system_feature_census.gleam. system_feature_inference_test.gleam is new; census/store tests extend source conservation and real private persistence. Risk, census, evidence, journal and plan remain Sa-plan projections.

Candidate 230abfa79f901fb45fe99e45a8ab48ed99d457ea2318f3d8f53a47b436cb2be8 binds46selected source/test/catalog/supporting-evidence files. Exact preimage is retained in the census. This is not a JJ revision, complete source tree or authenticated build. No VCS mutation; existing unrelated work is preserved. Worker and contract files were read and hashed, not edited.

## 9. Architectural Observations

Method is a finite algebra with a total name observation. Actual wire encoders and source-bound feature projection interpret it, compared with independent pre-refactor wire bytes and a separate exact name list. No combinator or process semantics are invented for this finite declaration set. Source pin and shard laws remain those of the existing feature algebra.

Five actual app entrypoint paths are source-bound separately, not counted as running actors or complete services. In particular indrajaal_gleam constructs a holon value, not evidence of a running actor. Seven existing inference MCP handlers use the Gleam inference API rather than this worker transport. Similar names do not prove a commuting runtime diagram. Gospel/Lean/sheaf-wide consistency remains unverified for this candidate.

## 10. Remaining Gaps

Worker method and response compatibility, contract shape drift, typed output/refusal schemas, real MAX transport, request correlation, semantic validation and trusted probe receipts remain open. modalities has no dedicated decoder. Separate ecology linear_softmax is source evidence only, not newly counted as a client method.

Full service/app/native/engine/control inventory and canonical task-scoped import remain incomplete. Actual Claude/AGY membership and ACKs, coordinator recovery, hive workflow, end-to-end acceptance and independent release still gate the overall objective. Private fixtures, source hashes and passing component tests do not satisfy these obligations.

## 11. Metrics Summary

Added13client-method records:861total,12source sets,15shards;87MCPinput schemas remain declared and zero output/refusal schemas established. There are no13newMCPtools. The semantic feature count and global runtime availability remain unknown.

One writer plus one bounded read-only reviewer; no paid inference or new package. Correlated tests are not independent Bayesian Beta-Binomial trials; calibrated posterior, half-life decay and Lyapunov dV/dt < 0 remain NOT_ESTABLISHED. Journal references to seven engines are obligations, not execution claims.

## 12. STAMP & Constitutional Alignment

Four UCAs: absent methods hide gaps; unsupported aliases could provide unsafe success; stale bindings can misstate readiness; unbounded or continued execution can outlive authority. This slice conserves identities, preserves negative evidence, uses exact source pins and bounded private tests, and never invokes the worker.

Safety/dependency eligibility precedes C×T×F×Dep×I. Existing t1 P1/3125 and false-coverage S5/O3/Det4,RPN60 estimates remain analyst judgments. Sa-plan owns task/workflow state; source/build/peer authority remains separate. EV ceiling93 and EV94..109 NOT_ADMITTED remain unchanged. No protected-storage action.

## 13. Conclusion

The tracker now represents all13current typed client builders without claiming compatible backend or MCP usability. Canonical dashboard at2026-09-21T06:57:05Z shows2/20completed,1executing,17blocked,0unknown. The overall goal and t1 remain active.

Forecast: conditional on unchanged candidate and pinned toolchain, p=0.95 that the first rerun of24pure inference/census/interface checks before2026-09-22T08:00:00Z passes. Any failure or missing test falsifies it. Outcome and Brier score (p-outcome)^2 are PENDING; no calibrated production probability is asserted.

### Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Observed host/chrony time and workflow-origin prefix.
- [x] CHK-02-TAIL — Full Tailnet links supplied; live webpage serving not inferred.
- [x] CHK-03-FRACT — L0–L9 applicability retained.
- [x] CHK-04-KM — Census, plan, risk, evidence and journal linked; corpus-wide sync pending.

</details>
<details><summary>Domain 2 — Purity and storage safety</summary>

- [x] CHK-05-MUDA — No new dependency/runtime; fleet exclusion audit not rerun.
- [x] CHK-06-GRAPH — Pure Gleam declarations; native boundary unchanged this slice.
- [x] CHK-07-DRIVE — Private fixture DB only; protected storage untouched.

</details>
<details><summary>Domain 3 — Tests and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full-system surfaces UNRUN.
- [ ] CHK-09-MATH — Four mathematical gates UNRUN for this candidate.
- [x] CHK-10-9MOD — Scoped unit, source-negative, wire-oracle and persistence checks observed.
- [x] CHK-11-REGR — Final results and failures retained in verification matrix.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [ ] CHK-12-GLEAM — Production supervision/authority unverified.
- [ ] CHK-13-HERMES — Invocation-specific formal admission pending.
- [ ] CHK-14-ZIGVM — Kernel/VFS acceptance outside this slice.
- [ ] CHK-15-MAX — Inference startup/probes not performed.
- [ ] CHK-16-OTEL — End-to-end trace correlation pending.

</details>
<details><summary>Domain 5 — Governance</summary>

- [ ] CHK-17-SOV — Independent release/admission pending.
- [x] CHK-18-JJ — Standalone JJ preserved, no VCS mutation.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV ceiling93; EV94..109 NOT_ADMITTED. Source claims, wire parity, task ownership and effect authority remain distinct.

</details>


[Previous: harness interfaces](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260921-0633-system-feature-interfaces.md) · [Next: canonical plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20260920-1438-hive-swarm-mcp-recovery-plan.md)

UOS footer: source declarations and local tests are not runtime or system admission.
