---
title: Shared ecology service Jidoka completion journal
observed_at: 2026-09-09T02:56:57Z
plan_id: uos/ecology-jidoka/20260909-0241
task_id: JIDOKA
worker: codex-ecology-supervision
attempt: 1
status: SCOPED_TESTS_PASSED
runtime_admission: NOT_GRANTED
tags: [fractal-l2, fractal-l4, fractal-l6, zk-adr, zero-muda]
---

# Shared ecology service Jidoka completion journal

#fractal-l2 #fractal-l4 #fractal-l6 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Baseline journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0237-ecology-supervision-completion.md) · [Machine receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0257-ecology-jidoka-completion.json) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0257-ecology-jidoka-completion.md)

These are canonical navigation targets. Publication, live service observation and final candidate admission remain separate root-owned actions. This task creates no EV identifier.

## 1. Scope & Trigger

The operator made OpenRouter operation, fractal TPS and Jidoka an explicit priority. Root assigned shared MAX/OpenRouter Andon gates, bounded recovery probes, truthful shared-state presentation and failure-isolation tests. The work ran under canonical Sa-plan `uos/ecology-jidoka/20260909-0241`, task `JIDOKA`, worker `codex-ecology-supervision`, attempt 1. The previous supervision baseline and its evidence were preserved.

## 2. Pre-State Assessment

The baseline already provided one pending worker, deadlines, supervised restart, real outcomes, 26 local participant models and persistent read-only HTTP snapshots. A serious external backend failure was recorded but did not prevent the next model from dispatching to the same failed service. Startup and restart also lacked an explicit recovery requirement for those two external backends.

## 3. Execution Detail

A pure `andon` module now defines `Ready`, `Stopped` and `Recovering` for each of the two shared external capabilities. Every actor initialization starts both gates stopped with `startup_recovery_required`. Local heartbeat and bounded local computation start normally. Normal external requests require their service gate to be ready, and the legacy stateless holon helper refuses external dispatch so model requests use the shared actor path.

The typed in-VM `recover_service(subject, holon_id, capability, input, timeout_ms)` API admits one bounded actual probe while the service is stopped. Its matching worker result must be `Engaged` for the requested capability, carry the expected backend name and contain a nonempty parsed backend receipt. Only that result can move `Recovering` to `Ready`. No reset command or HTTP mutation endpoint was added.

Both HTML adapters and the swarm JSON expose phase, reason, failure count, recovery attempts/count, last failure and last recovery receipts. Browser refresh updates the shared service summary through text nodes. The server-rendered Indrajaal view escapes external error text.

## 4. Root Cause Analysis

The earlier isolation boundary protected actor liveness but treated repeated service attempts independently. That allowed every model to retry a known failed shared backend. Jidoka needs service-level state above per-request outcomes: the first serious defect stops that service for all hosted models, and an observed repair probe controls restart.

Starting stopped after every actor or VM restart prevents a crash from acting as a blind reset. This deliberately avoids globally persistent terms: failure history remains local to the actor epoch, and a fresh epoch visibly requires recovery instead of claiming that old readiness survived.

## 5. Fix Taxonomy

The slice combines a latched state machine, bounded work-in-progress, error classification, recovery evidence and explicit shared scope. Scheduling/caller rejections are request-local. Transport errors, HTTP failures, malformed backend receipts, policy refusals and unknown backend failures stop the affected shared service. Explicit malformed-receipt cases take precedence over the generic `invalid_` caller-input prefix.

## 6. Patterns & Anti-Patterns Discovered

- A healthy heartbeat does not imply that every backend is ready; expose these states separately.
- A rejected or malformed recovery result cannot earn readiness or successful-invocation credit.
- A busy slot, disabled model mask, invalid caller schema or rejected prompt cannot stop an otherwise ready shared backend.
- Preserve the prior failure receipt when a successful recovery restores service.
- Require recovery after restart; do not reopen by erasing the previous actor's state.
- Treat a capability gate as local runtime control, not Sa-plan task authority, deployment authority or a budget grant.

## 7. Verification Matrix

| Check | Result | Final receipt |
| --- | --- | --- |
| Core build | PASS, 1.78 s | `/tmp/uos-ecology-jidoka-build-final.log` |
| Core scoped EUnit | PASS, 81 tests: baseline 66, eight Andon tests, seven strict external-adapter tests | `/tmp/uos-ecology-jidoka-tests-final.log` |
| Web build | PASS, 2.69 s | `/tmp/uos-ecology-jidoka-web-build-final.log` |
| Web tests | PASS, six tests including external error HTML escaping | `/tmp/uos-ecology-jidoka-web-tests-final.log` |
| Compiled browser-script harness | PASS, seven scenarios including stopped-to-ready presentation | `/tmp/uos-ecology-jidoka-refresh-test.log` |
| Final active source observation | PASS, nine files, 2026-09-09T02:57:51Z | `/tmp/uos-ecology-jidoka-active-final-receipt.json` |
| Actual browser, packaged candidate and deployed service | UNRUN by this worker; root-owned follow-up | No delegated browser/deployment credit claimed |
| Formal theorem or temporal-model proof of this new gate | UNRUN | Typed code and tests are not proof admission |

The Andon tests cover shared stop with no further backend I/O, continued other-capability/local work, failed recovery, valid recovery with retained failure receipt, malformed engaged responses, request-local bad input and masking, one recovery worker with continuing heartbeat, timeout containment and supervised restart requiring a new probe. The taxonomy test also verifies that an unpaired recovery receipt cannot clear a stopped gate.

The final assessment SHA-256 is `bb16bac5b5485efd5f51e9afd9e5d7e6ebfd10b6adffa0c4d30b2fc6b82c3a96`. Chrony reported an absolute offset of approximately 0.000108 seconds. The adjacent machine receipt embeds logs and exact source hashes. Earlier decoder-API and missing-record-field compilation failures remain in the evidence; they were corrected and rebuilt before passing tests. Sandbox attempts held when the host clock daemon was inaccessible; authorized host observations passed without a force override.

Root separately reported a real free OpenRouter Fin response with zero reported/actual cost and nonempty final advice, then integrated Fin defaults, credential fallback and sequential startup probes. Those backend/provider observations belong to root's receipt, not the injected-worker tests counted here. The final builds include those stable root-owned sources.

## 8. Files Modified

Exact source bytes are listed in the machine receipt; this table attributes only the delegated edits.

| Relative path | Change |
| --- | --- |
| `apps/cepaf_gleam/src/cepaf_gleam/ecology/andon.gleam` | Pure shared service phase, error classification and bounded receipt state |
| `apps/cepaf_gleam/src/cepaf_gleam/ecology/living_swarm_actor.gleam` | Normal dispatch gate, typed recovery API and checked outcome transitions |
| `apps/cepaf_gleam/src/cepaf_gleam/ecology/living_swarm.gleam` | Shared Andon state/JSON and required actor path for external model dispatch |
| `apps/cepaf_gleam/test/ecology_andon_test.gleam` | Eight failure/recovery and containment regressions |
| `apps/cepaf_gleam/src/cepaf_gleam/ui/ecology_refresh.gleam` | Live service phase/reason summary through text nodes |
| `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam` | Shared Andon presentation in the common shell |
| `apps/cepaf_gleam/test/ecology_runtime_router_test.gleam` | Initial stopped-state rendering assertion |
| `apps/indrajaal_gleam_web/src/indrajaal/ecology_http.gleam` | Visible, escaped service status |
| `apps/indrajaal_gleam_web/test/ecology_http_test.gleam` | External error text escaping and visible phase regression |

Root owns changes to the free router, external error taxonomy, credentials and startup service, and owns final package/deployment fencing. No root-owned source was edited by this worker.

## 9. Architectural Observations

The new state belongs to the one shared ecology actor, so all 26 hosted participant models consult the same service gates. The two external services stop independently. Their normal dispatch and recovery requests share the existing one-worker budget; a busy request cannot spawn a second worker or count as a backend defect.

The architecture remains a trusted in-VM model API. It is not a distributed authorization boundary or a claim that all external processes have been integrated. Existing raw capability ports remain implementation adapters; model-level external dispatch uses the actor. Root's service startup performs actual sequential recovery calls before reporting the observed external states.

## 10. Remaining Gaps

| Priority | Remaining scope |
| --- | --- |
| P1 | Final packaged-byte tests, actual browser interaction, live autonomous service observation and deployment are root-owned. |
| P1 | The 26 participants remain local models; external holon bindings are absent. |
| P2 | Gate/failure history resets with the actor; readiness also resets to recovery-required, preserving stop safety but not old receipts. |
| P2 | New Andon formal proof is UNRUN; scoped tests do not satisfy system admission. |
| P2 | Typed recovery invokes a configured backend but does not authorize coding tasks, paid inference, deployment or other effects. |
| P3 | Error classification is a documented string-prefix contract with explicit malformed-backend overrides; future adapters must preserve it or add typed classification. |

## 11. Metrics Summary

Two shared service gates each retain one last failure and one last recovery receipt, plus counters. The existing global outcome history remains capped at 128. There is still one pending worker and a maximum 30-second backend deadline. Startup and every restart require probes. Final checks comprise 81 core tests, six web tests and seven browser-script scenarios; these are separate checks, not proof of distributed fleet autonomy.

## 12. STAMP & Constitutional Alignment

Absent recovery evidence leaves service stopped. Unsafe backend results latch the stop. Wrong timing is controlled by the pending-worker token and `Recovering` phase. Excess duration is controlled by the monitored worker deadline. Request-local rejection avoids turning benign caller defects into a fleet-wide stop; serious defects remain shared per service.

Sa-plan is the sole task authority. Preflight and active-check observations were performed under the exact worker/attempt. Source and build writes froze before release handoff. No VCS mutation, deployment, secret provisioning, paid inference, external source ingestion, storage action or new EV number was performed by this worker. Application admission remains not granted.

<details>
<summary>Comprehensive verification checklist: 18 core checkpoints and provenance</summary>

| Domain | Actual scope |
| --- | --- |
| 1. Metadata/navigation | CHK-01-TIME: host clock observed; CHK-02-TAIL: canonical FQDN links; CHK-03-FRACT: tagged local layers; CHK-04-KM: journal/receipt, grouped wiki/ZK remains root-owned. |
| 2. Purity/storage | CHK-05-MUDA: no new prohibited dependency; CHK-06-GRAPH: text/HTML update only; CHK-07-DRIVE: no storage action, hardware test UNRUN. |
| 3. Tests/mathematics | CHK-08-C1C8: focused scope only; CHK-09-MATH: new gate proof UNRUN; CHK-10-9MOD: logs and source hashes attached; CHK-11-REGR: negative cases retained, continuous fleet check UNRUN. |
| 4. Runtime/observability | CHK-12-GLEAM: OTP 29 compile/tests; CHK-13-HERMES: source-bound risk checker observed; CHK-14-ZIGVM: kernel test UNRUN; CHK-15-MAX: root-owned actual backend evidence; CHK-16-OTEL: full trace correlation UNRUN. |
| 5. Governance/VCS | CHK-17-SOV: NOT_ADMITTED; CHK-18-JJ: root owns revision binding, no delegated VCS mutation. |
| 6. Provenance | CHK-PROV: EV-93 ceiling retained and no new EV identifier. |

</details>

## 13. Conclusion

The delegated Jidoka slice now stops a faulty shared external service, preserves local actor liveness, and requires an actual bounded recovery observation before reopening. Tests observed model-wide stop enforcement, strict recovery transitions, request-local containment, restart behavior and truthful presentation.

The implementation, journal and machine receipt are ready for root's final release workflow. The earlier baseline remains preserved. New provider, package, browser and deployed-runtime observations must remain separately attributed and candidate-bound.

[Previous: baseline journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0237-ecology-supervision-completion.md) · [Next: machine receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0257-ecology-jidoka-completion.json) · [Source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0257-ecology-jidoka-completion.md)

UOS · `/home/an/NAS-setup/uos` · `uos/ecology-jidoka/20260909-0241` · NOT_ADMITTED
