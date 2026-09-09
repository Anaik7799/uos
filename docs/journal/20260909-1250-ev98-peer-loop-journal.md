# EV98 supervised peer loop — review handoff

#fractal-l2 #fractal-l4 #fractal-l6 #zk-adr #zero-muda

Observed 2026-09-09 UTC. Source candidate `ee6037cc8b2ce7f8eb0cda58a3e21f2ffbd66335`, parent `ef62623e847b515b6c58fd1ee7f02a94219c4276`. Status: executed component tests pass; independent review pending; authority **NONE**. Sa-plan `uos/ev98-peer-loop/20260909`, `PEER_LOOP`, worker `codex-ev98-peer-loop`, attempt 1 remains executing.

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Provenance boundary](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md)

## 1. Scope & Trigger

The parent requested a private supervised peer loop connecting the reviewed delta engine, closed wire codec and dead-man monitor. New modules retain routed frames and expose a typed API for a separate transport worker. This task starts no production supervisor and performs no network I/O. The admitted EV ceiling is unchanged.

## 2. Pre-State Assessment

The sealed base had a bounded pure engine, codec and freshness registry, but no actor joining these components into a retained outbound workflow. The root created the sibling workspace and reported coordinator lease epoch 1, sequence 1579. A new canonical child plan/task was created. The first risk artifact used the invalid state `pending`; preflight refused it. Actual Sa-plan state was observed as `available`, the corrected preflight passed, and attempt 1 was claimed. Source effects were performed under that task and the root workspace lease. The refused assessment and receipt remain preserved.

## 3. Execution Detail

`mesh_peer` owns opaque configuration and state. Configuration permits at most 16 distinct nonself peers. The engine's pending messages are drained only into a staged routed outbox; failed encoding or quota checks discard the proposed state, preserving the original engine and queue. Digests route to configured peers. Responses route to the configured identity whose routing ID equals the decoded sender. That equality is a routing check, not authentication.

The outbox retains at most 256 frames and 1 MiB of aggregate wire bytes; each frame also passes the 128 KiB codec limit. A report can retire only its exact lifetime, sequence and destination. Failed transport preserves the frame and ID. `TransportAccepted` describes caller-reported transport custody, not remote application delivery.

`mesh_peer_actor` exposes `start`, `supervised`, `gossip`, `receive_wire`, `record_worker`, `record_health`, `pull`, `report_delivery`, `snapshot`, `take_advisories` and `shutdown`. Clock functions call standard ERTS directly through typed Gleam declarations. A local origin converts ERTS monotonic time into nonnegative elapsed milliseconds; UTC microseconds feed the engine. A periodic message evaluates freshness even with a full outbox or invalid UTC, and reports the separate gossip refusal. No timer action dispatches an external effect.

## 4. Root Cause Analysis

There were three observed RED stages: an unsupported valid configuration, an actor that scheduled messages without evaluating freshness, and a UTC validity guard that suppressed monotonic freshness. The configuration contract was implemented; the actual timer callback was connected; and UTC rejection was moved into the independent gossip result. The latter two failures demonstrate why timer scheduling alone and a shared clock guard do not establish freshness behavior.

## 5. Fix Taxonomy

This is an additive supervision and state-composition change. Opaque constructors enforce state bounds. Transactional staging prevents partial queue transfer. A per-peer strictly advancing remote-epoch watermark controls activity; older or replayed wire data may still merge, but cannot rearm the dead-man monitor. Actor frame lifetimes use ERTS VM-local unique integers so reports from an earlier restarted actor do not retire its successor's frames.

## 6. Patterns & Anti-Patterns Discovered

Keep monotonic freshness independent of transport progress and UTC validity. Treat pull as observation rather than removal. Keep diagnostic current state even when advisory history overflows: 64 advisories are retained and an explicit saturating overflow count is returned. Avoid treating a successful actor start, a printed status label or router custody as proof of remote application delivery. A successful direct wire exchange is narrower than a multihost transport test.

## 7. Verification Matrix

The final immutable 19-file minimal package compiled without warnings. Ten pure-state groups, three real OTP groups and 72 existing codec/engine/freshness groups passed. The pure groups cover bounds, routing mismatch, malformed wire, exact delivery reporting, failed-send retention, replay, full queue, byte quota, encoding refusal, clock regression, advisory overflow and UTC-independent freshness. Actual OTP tests exchange worker and health state between two actors, exercise a real static supervisor and abnormal restart, reject an old-lifetime report, return retained state at controlled shutdown, and trip a peer while the outbox is full.

ERTS reported emulator version 17.0.5. Source and BEAM hashes, native invocation argv/output digests, three RED receipts and their source bytes, and 211 unchanged dependency files are recorded in `docs/reviews/20260909-1250-peer-verification.json`. Its SHA256 is `53060d643f31d5d2a5e34b6cab91436128e5a8bfb8a3154567c7d059a71e6955`. The process-killed supervisor report is an intentional recovery control; the whole runner exits 0 after the restart and shutdown assertions.

## 8. Files Modified

Only new task-owned files were added: `apps/cepaf_gleam/src/cepaf_gleam/crdt/mesh_peer.gleam`, `mesh_peer_actor.gleam`, `apps/cepaf_gleam/test/mesh_peer_test.gleam`, `mesh_peer_actor_test.gleam`, `tools/ev_peer_stage.ml`, timestamped risk assessments, this journal and timestamped review receipts. Existing delta, codec, dead-man and supervisor sources are unchanged. No live coordinator, runtime, ledger or historical event was rewritten.

## 9. Architectural Observations

The actor performs bounded local computation and exposes a pull/report boundary for a supervised transport worker. Pure peer state permits deterministic refusal and replay tests without a network. Current engine/freshness views are readable copies; callers cannot construct or mutate the enclosing opaque state. Controlled shutdown returns the retained view for an explicit caller-owned handoff. Transient supervision restarts abnormal failures but does not undo a normal requested shutdown.

## 10. Remaining Gaps

Transport, sender authentication, persistence, production integration and independent review remain outside this handoff. In-memory frames are not durable across an abnormal actor or VM crash. Lifetime IDs distinguish actors within this ERTS VM; they are not a persistent global incarnation identity. An RPC timeout returns `ActorUnavailable` with an unknown operation outcome; callers must not interpret it as proof that a mutation was refused. Callers must bound mailbox demand, and late replies/untrusted raw Erlang messages are outside the opaque-state bounds. A failed caller may lose a controlled-shutdown handoff. Advisory overflow is explicit but is not complete event history. There is no hard real-time, complete reproducible OTP closure, formal refinement or EV-admission claim. The parallel SYNC_STATUS repair remains parent-coordinated; this new peer layer does not branch on status labels.

## 11. Metrics Summary

Observed: 10 pure groups, 3 OTP groups and 72 existing groups; zero final test failures; zero final compiler warnings; 19 immutable compiler inputs; 211 dependency files unchanged. Limits: 16 peers, 256 retained frames, 1 MiB aggregate wire bytes, 128 KiB per frame, 64 retained advisories, 1 second actor-call and startup deadlines, and 1 second supervised worker shutdown allowance. Timer and heartbeat configuration is bounded to 1–60,000 ms, with at most 100 missed intervals. No network operation or admission record was generated.

## 12. STAMP & Constitutional Alignment

Unsafe omission: queue pressure must not suppress freshness. Unsafe provision: a wrong route/report must not acquire custody of another frame. Wrong timing: stale remote epochs must not reset a trip. Excess duration: work is confined to bounded state, supervised actors, native command deadlines and active Sa-plan/workspace authority. Advisory dead-man actions do not dispatch effects. This handoff advances implemented/built/executed/passed evidence only; independent verification and admission remain separate.

<details><summary>Domain 1 — Metadata and navigation</summary>

- CHK-01 TIME: PASS — host UTC and synchronized active-risk receipt recorded.
- CHK-02 TAIL: links use canonical FQDN; live document serving was not tested.
- CHK-03 FRACT: L2/L4/L6 scope tagged.
- CHK-04 KM: journal and evidence references provided; no global index rewrite.

</details>
<details><summary>Domain 2 — Purity and storage safety</summary>

- CHK-05 MUDA: no prohibited dependency or runtime added; fleet scan not rerun.
- CHK-06 GRAPH: new executable source is Gleam/OCaml; existing realized ERTS reused.
- CHK-07 DRIVE: N/A — no storage allocation or device operation.

</details>
<details><summary>Domain 3 — Verification</summary>

- CHK-08 C1C8: scoped component/OTP checks recorded; UI categories N/A.
- CHK-09 MATH: bounded state assertions only; no new formal theorem claimed.
- CHK-10 9MOD: actual local actor exchange observed; multihost/network modes unrun.
- CHK-11 REGR: 72 existing focused regression groups pass.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- CHK-12 GLEAM: actor, timer, restart and shutdown behavior observed locally.
- CHK-13 HERMES: native Sa-plan/risk controls used; no production policy cutover.
- CHK-14 ZIGVM: N/A — no engine change.
- CHK-15 MAX: N/A — no inference change.
- CHK-16 OTEL: typed diagnostics and evidence only; production telemetry unrun.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- CHK-17 SOV: independent review pending; authority NONE and EV ceiling unchanged.
- CHK-18 JJ: isolated standalone JJ candidate and additive evidence descendant.

</details>

## 13. Conclusion

The frozen peer-loop candidate is ready for independent review. `PEER_LOOP` remains executing; the root owns integration, later transport wiring and any eventual task completion. No live startup or EV admission is authorized by this journal.

UOS footer · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)
