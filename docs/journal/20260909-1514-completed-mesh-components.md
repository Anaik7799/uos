# 20260909-1514 Completed mesh components and integration repairs

Observed UTC: **2026-09-09T15:52:14Z**. #fractal-l0 #fractal-l2 #fractal-l3 #fractal-l6 #zk-adr #zero-muda

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Provenance](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md). Private JJ evidence; live publication unverified.

## 1. Scope & Trigger

Continue all-EV verification using Gleam, OCaml or Mojo and no Bash. Close the bounded transport, causal synchronization and closed-recipe tasks, compose their evidence, and repair integration test coverage. The programme remains executing and EV94–109 remain NOT_ADMITTED.

## 2. Pre-State Assessment

The reviewed codec and peer layer lacked a network worker. Peer status could forget newer causal evidence. The recovery generator expected168 calls. Synthetic transport fault functions were named as normal EUnit tests, although their bodies required private mutated builds.

## 3. Execution Detail

The Gleam transport now performs bounded HTTP broker custody/readback and retained peer delivery. Independent checks covered framing, cancellation, delayed delivery replies, cleanup refusal, receive retries and publication quotas. Causal synchronization retains a monotone frontier for every registered peer. Root's unchanged stale-ACK and stale-Delta probes switched from failure to success. The closed OCaml recipe retains its original42 calls and adds25 codec plus9 causal cases; four designated compiled mutants fail as required. All three scoped tasks completed after independent reviews and current active observations.

Root composed the sources and ran115 distinct labels against an immutable private build. The timer fixture now checks that a stale ACK requiring recovery refuses at a full queue, while a covering ACK at the same old epoch cannot rearm a tripped heartbeat. A fresh real broker run observed six exact records, three publications and applications per actor, zero failures, and matching produced/consumed wire bytes. Both actors ran locally on NAS.

## 4. Root Cause Analysis

Successful socket publication and successful peer bookkeeping are separate transitions: retaining broker custody before a fallible report prevents cursor reuse. Causal clock equality alone forgets a previously observed remote frontier. Integration exposed a stale empty-clock ACK assumption and a fixed168-call generator. Actual EUnit discovery also selected four synthetic fault entrypoints, producing three failures; renaming those explicit entrypoints and adding a normal production test restored nonempty standard discovery. Initial evidence preparation refused relative filesets from another workspace before writing artifacts; explicitly rooted JJ filesets corrected that invocation.

## 5. Fix Taxonomy

Retained delivery state, queue-atomic causal observations, exact reviewed call-set hashing, regression-preserving fixture repair, ordinary test discovery, isolated fault entrypoints and immutable evidence composition. No runtime deployment or admission mutation occurred.

## 6. Patterns & Anti-Patterns Discovered

A final group count is not a proof of distinct properties. A normal test runner must be exercised in addition to manually selected mains. Fault-injected behavior requires explicit artifact identity. A same-length substitution or reordered test set must not silently pass a cardinality guard. A delayed approval does not extend a task lease; failed expiry transitions remain failures.

## 7. Verification Matrix

| Observation | Result | Boundary |
|---|---|---|
| Composed private build | Warning-free,115 labels passed | Peer, transport, codec, causal cases and independent probes |
| Fresh broker run | Six records; exact wire equality; zero failures | Two local actors, real NAS broker |
| Recovery runner | All177 ordered calls passed | Original168 plus9 reviewed causal calls |
| Generator controls |15 groups passed, independently repeated | Existing-path safety, links, exact membership/order and denominator refusal |
| Normal EUnit transport discovery | One production case passed | Its existing12-group main; nonempty discovery |
| Renamed fault fixtures | Four independently rebuilt cases passed | Explicit private synthetic variants |
| Closed producer recipe |76 positives, four designated mutants | Independently rebuilt OCaml producer and replayed bound ERTS artifacts |
| Full EV98 and all-EV admission | Not established | Formal refinement, multihost, production and sovereign requirements remain |

## 8. Files Modified

The composed author changes add the transport, causal peer frontier and closed recipe expansion. Root changes the recovery generator and generated main, the peer timer fixture, the ordinary transport test entrypoint and four OCaml fault staging callers. This record preserves exact approvals, invocation receipts, source/dependency bindings and executed probe/driver source. Historical and quarantined evidence remains unchanged.

## 9. Architectural Observations

Gleam owns state transitions, supervision and socket workers. OCaml owns bounded native execution and evidence processing. Native erlexec and ocamlrun avoid shell launcher wrappers. The finite health algebra proof and component reviews do not establish full distributed-system refinement. The live coordinator still requires its separate proven cutover; documentary claims do not replace observed runtime state.

## 10. Remaining Gaps

Cross-host identity and incarnation recovery, durable peer clocks/outboxes, full mesh formal refinement, production startup and actual sovereign EV admission remain open. Cooperative GET-before-PUT is not atomic CAS against external writers. Mailbox demand must be bounded by trusted callers. Newly identified digest-validation, graph-integrity and remediation-accounting defects are being handled in separate Sa-plan tasks. Other EV UI/performance fields still contain synthetic claims requiring observed producers.

## 11. Metrics Summary

Three bounded component tasks completed in this stage. Relevant suites reported115 composed labels,177 recovery invocations,15 generator control groups,76 recipe positives and four recipe mutants. These overlap and are not a combined assurance score. New EV admissions: zero. Policy ceiling:93.

## 12. STAMP & Constitutional Alignment

Exact routing/custody and causal coverage constrain unsafe provision; retry retention constrains omission; monotone freshness and current task attempts constrain wrong timing; quotas, deadlines and cleanup halt constrain excessive duration. Task completion is narrower than runtime effect authority. Component evidence and observed AGY commentary do not authenticate every producer or grant sovereign admission. Standalone JJ sibling integration remains separate from integration/main and runtime service ownership.

## 13. Conclusion

The reviewed transport, synchronization and closed-recipe components are completed and composed. The integration defects are repaired with preserved failures and independent checks. Broader EV work continues without changing the admitted ceiling or minting new EV numbers.

## Comprehensive verification checklist

<details><summary>Domain1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Synchronized active observations and host UTC retained.
- [x] CHK-02-TAIL — Full Tailnet links supplied; publication unverified.
- [x] CHK-03-FRACT — Applicable fractal layers tagged.
- [x] CHK-04-KM — Evidence and governing provenance linked.

</details>
<details><summary>Domain2 — Purity and storage</summary>

- [x] CHK-05-MUDA — New code and orchestration use Gleam/OCaml, without Bash.
- [ ] CHK-06-GRAPH — Fleet purity review remains outside this stage.
- [ ] CHK-07-DRIVE — No hardware operation or new interlock test.

</details>
<details><summary>Domain3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8 — Complete release categories remain open.
- [ ] CHK-09-MATH — Full distributed-model refinement remains open.
- [ ] CHK-10-9MOD — Whole-capability acceptance remains open.
- [x] CHK-11-REGR — Relevant runtime, failure and discovery checks executed.

</details>
<details><summary>Domain4 — Runtime and observability</summary>

- [x] CHK-12-GLEAM — Actual OTP peers and transport executed.
- [x] CHK-13-HERMES — Native OCaml evidence and recipe checks executed.
- [ ] CHK-14-ZIGVM — Kernel acceptance outside this stage.
- [ ] CHK-15-MAX — Inference acceptance remains open.
- [ ] CHK-16-OTEL — Production telemetry correlation remains open.

</details>
<details><summary>Domain5 — Governance and VCS</summary>

- [ ] CHK-17-SOV — No sovereign EV admission is claimed.
- [x] CHK-18-JJ — Private standalone JJ composition; no Git mutation.

</details>
<details><summary>Domain6 — Provenance</summary>

Source revisions, independent reviews, exact task outcomes and failures are retained. Legacy claims and synthetic variants never become positive EV admission evidence.

</details>

[Component evidence](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1514-completed-mesh-components.json). UOS footer: programme executing; admission pending.
