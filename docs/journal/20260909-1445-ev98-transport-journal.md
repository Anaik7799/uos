# EV98 bounded Zenoh transport — component review handoff

#fractal-l2 #fractal-l4 #fractal-l6 #zk-adr #zero-muda

Observed 2026-09-09 UTC. Source `14057e08112c1cd5d44297eac6a9c853e8287b7a`, parent `0a17bed584cefca57565ccdfe7705f22ccaae244`. Component execution passed; independent review remains pending. Authority **NONE**. Canonical Sa-plan `uos/ev98-peer-loop/20260909`, task `TRANSPORT`, worker `codex-ev98-transport`, attempt 1 remains executing.

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Provenance boundary](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md)

## 1. Scope & Trigger

The parent requested a supervised transport worker after independent peer-loop approval. The new worker connects the retained peer outbox to the existing Zenoh REST broker, using only a fresh owned test namespace. This task changes no production supervisor, existing broker key, live journal or admission ceiling. The parent owns later composition and release authority.

## 2. Pre-State Assessment

`PEER_LOOP` had been independently approved and completed. `TRANSPORT` was added as a separate task depending on it. Two preflight defects were refused and preserved: incomplete decision metadata, then incomplete source/dependency bindings. Corrected complete-plan preflight passed; attempt 1 was claimed at 14:05:33 UTC. Source and final execution were checked under synchronized active observations. The latest handoff observation passed at 14:45:04 UTC. Root reported workspace epoch 2, renewal sequence 1592, valid to approximately 15:32 UTC; the task lease expires earlier at 15:05:33 UTC.

## 3. Execution Detail

`mesh_zenoh_http` uses direct typed standard ERTS functions. Passive sockets read at most 4096 bytes per body operation. The parser header budget is 8192; the actual total wire-header upper bound is 8194 because the status-line CRLF adds two bytes. Individual header lines are bounded to 1024, bodies to 800000, and chunk count to 4096. Content length and chunk framing are exclusive; duplicate headers, signed numeric lengths, malformed framing, invalid UTF-8 and redirects are refused. There is no caller-supplied command, proxy, redirect target or arbitrary HTTP header. The precise accounting is preserved in `docs/reviews/20260909-1450-transport-header-bound-addendum.json`.

A disposable socket owner executes each request. An owner-death watchdog monitors the caller and child. Normal cleanup observes both child terminations and flushes the sole response after socket-owner DOWN. The network deadline is 500 ms for worker requests; cleanup observation allows another 300 ms. If termination is unconfirmed, the worker latches further I/O off while snapshot and shutdown remain available. This does not assert hard real-time scheduling or atomic watchdog installation at spawn.

`mesh_zenoh_transport` alternates a publish step with exact-key polling for one configured peer. It holds at most one pending publication, two bounded last-wire diagnostics, and bounded per-peer cursors. A run permits 256 publications per worker. Per-route keys are sequential under `uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/<fresh-run>/`. GET-before-PUT checks existing content; successful PUT is followed by exact readback. Known broker custody is committed as a pending phase before the fallible peer retirement report. Unknown report outcomes retry the exact frame; `NotOutstanding` reconciles already completed retirement without rewinding the route cursor.

Receive cursors advance only after successful peer application. Sender/destination labels and the decoded wire sender must agree with configured routing. The peer loop retains its strictly advancing remote-epoch watermark, so a replay cannot rearm a dead-man trip. Broker timestamps are parsed as metadata and do not become freshness authority.

## 4. Root Cause Analysis

The actual RED sequence identified distinct problems: unimplemented configuration; treating CRLF as two Gleam graphemes rather than two bytes; a one-sided gossip test that did not stimulate the advertised two-way exchange; custody rollback after an unknown retirement report; and ordinary retry after unknown HTTP cleanup. A live broker then returned `timestamp`, where the published REST example uses `time`; the closed parser refused that record and retained the frame. Both observed metadata spellings are now accepted without granting timestamp authority.

## 5. Fix Taxonomy

The changes add a typed I/O boundary, disposable process isolation, transactional publication phases, fail-closed cleanup state, and bounded decoding. The existing engine, codec, peer and dead-man source files are unchanged. Private fault variants delay peer replies, inject one receive unavailability, inject cleanup uncertainty, or initialize the publication counter at 255. They are explicitly synthetic test artifacts, not production source.

## 6. Patterns & Anti-Patterns Discovered

Broker custody and peer application are different observations. A successful write followed by an uncertain local report requires retained transaction state. A timeout return alone does not establish process cleanup. A read-before-write check is cooperative collision detection, not atomic compare-and-swap against another writer. The worker uses a standard OTP global term name to reject a second live worker for the same run/local identity in the test ERTS instance; no dynamic atom is created from the run string.

## 7. Verification Matrix

The immutable 23-input package compiled without warnings. Twelve transport groups passed, including real private HTTP sockets, two peer actors, failed publish retention, exact body boundary, ambiguous and malformed framing, deep/duplicate JSON refusal, timeout/socket closure, replay, readback retry, singleton construction and actual supervisor restart/controlled shutdown. Four private fault groups passed: delayed retirement reply, cleanup-unknown halt, unavailable receive retry, and publication quota boundary. Existing peer/codec checks passed in 85 groups. The actual owned broker roundtrip passed separately: **102 scoped groups total**, with no claim that this count represents full EV acceptance.

The final broker run was `r1788965028743063-1`. Six exact readback bodies were recorded, including digest, complete worker/health delta, and acknowledgment in each direction. Both transport workers reported three custody retirements and three peer applications, with zero failures. The receiver observed `worker-owned-live` and health score `0.91`. Actual last stored and applied wire bytes compared equal and their SHA256 is bound in the review manifest. Both actors and workers were shut down after observation.

Primary evidence: `docs/reviews/20260909-1445-transport-verification.json`, SHA256 `1260c72e594cb804f3dc4766f7264cc94141b6311a28bbc2786824dc9b63421c`. It binds raw native argv/output receipts, production and fault BEAM hashes, source hashes, 211 unchanged dependency files, preserved RED source bytes, and all six broker readback digests. The native adapter reported ERTS 17.0.5. Delayed peer reply warnings and intentional supervisor-killed reports are retained as expected fault/recovery output.

## 8. Files Modified

New control modules: `apps/cepaf_gleam/src/cepaf_gleam/crdt/mesh_zenoh_http.gleam` and `mesh_zenoh_transport.gleam`. New tests: `apps/cepaf_gleam/test/mesh_zenoh_test.gleam` and the separately invoked `mesh_zenoh_live_test.gleam`. Six new OCaml staging/fault helpers live under `tools/ev_transport_*`. Timestamped risk portfolios, raw verification records, synthetic source records and this journal are additive. No compiler cache or BEAM binary was copied into repository source.

## 9. Architectural Observations

HTTP work occurs outside the main peer actor. The worker exposes `config`, `start`, `supervised`, `snapshot` and `shutdown`; the peer's typed pull/report/receive API remains the custody boundary. Normal worker shutdown is transient and does not trigger automatic restart. Snapshot exposes pending custody and bounded last stored/applied bytes for review. Parent composition can integrate the parallel SYNC_STATUS change without this transport branching on diagnostic synchronization labels.

## 10. Remaining Gaps

The successful test uses two actors in one ERTS VM and the existing broker reached through the Tailnet endpoint; it is not a multihost mesh test. Routing IDs, namespace ownership and readbacks do not authenticate producers. HTTP is plaintext inside the configured Tailnet. Cooperative checks do not prevent an external writer racing a PUT. In-memory cursors and retained frames are not durable across crashes; restart/recovery requires an explicitly fresh run and does not erase old records. All test run keys remain preserved, including refused-schema runs.

Mailbox demand must be bounded by callers. OS socket buffers, scheduler latency, complete dynamic-library closure and atomic cleanup during the child/watchdog installation window are not proven here. `CleanupUnconfirmed` means cleanup and late-response absence remain unknown, with I/O halted. Peer RPC timeouts retain unknown-outcome semantics; delayed peer reply messages are explicitly observed and discarded by the existing actor. Full formal refinement, cross-host operation, production integration, independent final approval and EV admission remain separate.

## 11. Metrics Summary

Observed: 12 transport groups, 4 synthetic fault groups, 85 baseline groups, 1 owned broker roundtrip; 23 immutable compiler inputs; 211 direct dependency files rehashed unchanged; five warning-free builds. Limits: 16 peers, 256 publication slots per worker/run, 256 receive slots per route, 1 pending frame plus 2 last-wire copies of at most 131072 bytes each. HTTP bounds and deadlines are stated in section 3. Worker tick interval is 20 ms, with one scheduled tick; control calls and supervised shutdown allow 4000 ms.

## 12. STAMP & Constitutional Alignment

Unsafe omission: transport failure must preserve the peer's retained frame and must not stop the independent peer freshness timer. Unsafe provision: a wrong route, ambiguous body, or unrelated report must not acquire or retire custody. Wrong timing: stale wire must not refresh peer health; unknown report outcomes must not roll a cursor backward. Excess duration: bounded child requests and observed cleanup constrain I/O; cleanup uncertainty closes further I/O. The Sa-plan task and workspace lease remain distinct effect fences, and observed component behavior does not grant admission.

<details><summary>Domain 1 — Metadata and navigation</summary>

- CHK-01 TIME: synchronized active observations and actual invocation times bound.
- CHK-02 TAIL: canonical FQDN links and endpoint; live document serving untested.
- CHK-03 FRACT: L2/L4/L6 scope tagged.
- CHK-04 KM: journal and evidence connected; no global index rewrite.

</details>
<details><summary>Domain 2 — Purity and storage safety</summary>

- CHK-05 MUDA: no prohibited dependency added; fleet scan not rerun.
- CHK-06 GRAPH: authored executable source is Gleam/OCaml; realized ERTS reused.
- CHK-07 DRIVE: no device/storage provisioning or destructive operation.

</details>
<details><summary>Domain 3 — Verification</summary>

- CHK-08 C1C8: scoped state/I/O/recovery tests; UI categories not applicable.
- CHK-09 MATH: bounds and counter falsifiers; no new theorem claimed.
- CHK-10 9MOD: actual owned broker exchange observed; multihost unrun.
- CHK-11 REGR: 85 existing peer/codec groups pass.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- CHK-12 GLEAM: supervised transport and actual peer application executed.
- CHK-13 HERMES: native risk/Sa-plan and SHA256 verification used.
- CHK-14 ZIGVM: no deterministic kernel change.
- CHK-15 MAX: no inference change.
- CHK-16 OTEL: bounded diagnostics and receipts; production telemetry unrun.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- CHK-17 SOV: final independent review pending; no admission granted.
- CHK-18 JJ: standalone sibling source and additive evidence descendant.

</details>

## 13. Conclusion

The source and observed evidence are ready for independent component review. `TRANSPORT` remains executing. The parent owns review disposition, composition, any task completion and later runtime authority.

UOS footer · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)
