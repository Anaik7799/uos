# 20261026-1018 — Telegram review packets for the open independent tasks

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda #km-triad #tailscale-web

[This document](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261026-1018-telegram-review-packets.md) · [Wave 6 close](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261026-1009-claude-telegram-wave6-close-kpi-handover.md) · [KPI ledger](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261026-0639-claude-telegram-wave-kpi-ledger.json) · [Journeys guide](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20261026-0220-telegram-journeys-guide.md) · [Media guide](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20261026-0801-telegram-media-pipeline-guide.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

Transclusions: `[[zk:20260905-1801-moc-uos-unified-master]]` · `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

Plan `uos/telegram-runtime/20261001-1150`. Author session `claude-fable-l0-35600f5c` wrote the candidates below and MUST NOT claim these tasks; a reviewer session claims one through Sa-plan (`tools/sa-plan task claim <reviewer> uos/telegram-runtime/20261001-1150 <lease_ns> <TASK>`) after `bash tools/risk-priority-check --preflight`, reads the candidate at the named commit, runs the named suites on the pinned OTP 29 toolchain, and completes with a verdict and findings. A verdict is evidence for RELEASE and ADMISSION; it is not admission. EV ceiling 93; EV-94..109 NOT_ADMITTED.

Toolchain and runner (every packet):

```bash
cd /home/an/NAS-setup/uos && export UOS_ROOT=/home/an/NAS-setup/uos && source tools/lib/uos-toolchain.sh && uos_env
cd apps/cepaf_gleam && gleam build --target erlang
# full suite (about ten minutes; the gleam runner starts hackney, which the fixture suites need):
gleam test --target erlang
# one module with hackney started (never cite a bare-erl module run as the suite result):
PA=(); for d in build/dev/erlang/*/ebin; do PA+=(-pa $d); done
erl -noshell "${PA[@]}" -eval 'application:ensure_all_started(hackney), eunit:test([<module>],[verbose]), halt().'
```

## COMMAND_REVIEW — "Independently verify command ownership guard backends conversation and refusals"

- Candidate: `main` at or after e256791b (surface last changed in wave 6h, a985c3a1).
- Files: `src/cepaf_gleam/harness/telegram_commands.gleam`, `telegram_ingress_guard.gleam`, `telegram_read_adapters.gleam`, `telegram_action_adapters.gleam`, the dispatch arm in `telegram_service.gleam` (search `decode_input_media(raw_json)`), `telegram_verify_*.gleam` for `/verify`.
- Laws to verify: 77 catalog literals each answer from a module (coverage test); every mutation literal is denied at classify or previews without effect; `/verify` executes only under a signed verify packet inside a Sa-plan job claim with a receipt and answers `duplicate` on replay; captioned media is accepted with the caption as text and bare media is a `media_without_caption` tombstone; no reply fabricates success (INV-TGJ-04); no reply carries a token, file URL or raw backend text.
- Suites: `telegram_ingress_guard_test`, `telegram_commands_test`, `telegram_read_adapters_test`, `telegram_action_adapters_test`, `telegram_journey_security_test`, `telegram_journey_defence_test`, `telegram_journey_responder_test`, `telegram_journey_coverage_test`, `telegram_verify_service_test`, `telegram_service_e2e_test`.
- Evidence: journals 20261026-0230 (wave 5), 0640 (6a), 0728 (6b), 0936 (6h); specs `docs/design/20261026-0215-telegram-journey-*.md`; rule `contracts/rules/20261026-0220-telegram-journey-acceptance.md`.
- Known residuals the author recorded: V-06b, V-07, V-12 (wave 6b journal section 10); the media reply takes precedence over the caption directive by design.

## GATEWAY_REVIEW — "Verify Telegram gateway startup secrecy event routing and recovery"

- Candidate: `main` at or after the wave 6n landing (the advisory review of 6a's surface, `claude-subagent-gateway-review-20261026`, returned REQUEST_CHANGES with nine majors; 6n answers them).
- Files: `src/cepaf_gleam/gateway/telegram.gleam`, `telegram_gateway_outbox.gleam`, `telegram_gateway_drain.gleam`, `src/telegram_gateway_drain_ffi.erl`; `telegram_app.gleam.broken` is deliberately not compiled.
- Laws to verify: the gateway holds no credential and reports observed startup only (with the current Zenoh client `start` can only report `subscribed: False`; no event routing exists); the drain actor's state holds no `Send` closure (the Send is passed per `Tick`; verify with `sys:get_state`); a crashing Send is contained as `OutboxUncertain("send_crashed")` with its reason discarded; the request digest covers kind, chat, topic and text; an uncertain backlog refuses Notices at capacity and Criticals only at twice the capacity; `Delivered(id ≤ 0)` is never a delivery; `enqueue` reports `Unobserved(call_timeout|actor_unavailable)` distinctly from `Full`; the Telegram channel refusal is case- and whitespace-insensitive; a supervisor restart yields an EMPTY queue and the delivery ledger holds no gateway request (no recovery exists; stated, not solved).
- Suites: `telegram_gateway_test`, `telegram_gateway_outbox_test`, `telegram_gateway_drain_test`, `gateway_coverage_test`, `gateway_comprehensive_test`.
- Evidence: journals 20261026-0220 (wave 4), 0640 (6a), the 6m journal section 10 (the review's findings) and the 6n journal.
- Known residuals the author recorded: a quarter of the pending capacity is reserved for Criticals and the oldest uncertain observation is exposed in `Counters` (wave 6p), but no ticker in the tree consumes it, so the staleness alarm is a caller obligation (G-04); any Subject holder may `Resolve` (G-05); no pre-send durable record, so a producer re-enqueue after a restart can send twice (G-06); Send runs synchronously inside the actor with no deadline of its own (G-07); the briefing's dead outbox queue (G-10); caller-supplied `now` (G-11); the broken app file (G-12); no start site exists for the gateway in the tree (G-13).

## MEDIA_REVIEW — "Independently verify all adopted Telegram media cases and hostile inputs"

- Candidate: `main` at or after the wave 6o landing (waves 6c to 6o; the advisory review of the lifecycle since 6d, `claude-subagent-media-review2-20261026`, returned REQUEST_CHANGES and 6o answers M2-01, M2-02, M2-03, M2-04, M2-07, M2-08 in part, M2-10 and M2-11).
- Files: `src/cepaf_gleam/harness/telegram_media_ref.gleam` (T1), `telegram_media_download.gleam` (T2), `telegram_media_inspect.gleam` (T3), `telegram_media_store.gleam` (T4, delete and reclaim), `telegram_media_intake.gleam`, `telegram_media_transport.gleam`, `telegram_http_client.gleam` (`get_file`, `fetch_file_range`), `src/cepaf_gleam/telegram/telegram_media_janitor.gleam`, the `configure_media` and media arm in `telegram_service.gleam`, `src/telegram_http_test_fixture.erl` (test only).
- Laws to verify: names derive only from the recomputed SHA-256; sender strings never reach a path; ceiling and digest checks precede any write; `get` re-hashes and refuses expired objects; delete removes index then bytes under `link_info`; reclaim is bounded with a receipt; inspection reads 64 bytes and never the declared mime; the transport contacts only the configured host, accepts only the configured token's URL prefix, fetches 4 MiB ranges and cross-checks `Content-Range`; the per-kind cap is enforced across chunks; the janitor pauses after three errors; the media reply is `ok` only with a stored digest.
- Suites: `telegram_media_ref_test`, `telegram_media_download_test`, `telegram_media_inspect_test`, `telegram_media_store_test`, `telegram_media_intake_test`, `telegram_media_transport_test` (hackney), `telegram_media_janitor_test`, the slice1 placement test, the e2e captioned-photo test.
- Evidence: journals 20261026-0750 (6c and 6d), 0826 (6e), 0847 (6f), 0903 (6g), 0936 (6h), 0953 (6i), the 6j journal; design `governance/planning/20261011-1354-claude-telegram-media-design.json`; the advisory R2 review of 6c recorded in the 6c journal section 4.
- Laws added in 6o: the transport keeps the first-seen `Content-Range` total, accepts a 416 only at `offset == total` (`range_truncated` otherwise), refuses a changed total (`range_total_changed`) and a total over 52 MiB before a second range; the download adapter refuses bytes that differ from the getFile size (`size_mismatch`) and stores nothing; `valid_file_path` is an allowlist (`[A-Za-z0-9._/-]`, no `..` segment); `usage_report` skips and names a malformed index instead of failing intake; `reclaim_orphans` removes `.tmp-` files, index-less `.bin` files and undecodable indexes older than a grace period (default ten minutes) within the same bound; the janitor runs under its own Transient sub-supervisor (intensity 10 / 60 s) so four kills in five seconds leave the Telegram service alive, a `Stop` is not restarted, three all-refused runs pause it, and history refusals are capped at 32 with a dropped count; `unlink_file` re-checks `link_info` and never removes a directory.
- Known residuals: the download adapter concatenates the body in memory up to the cap; the sender-declared size is not compared (fixtures declare sizes that differ from the bytes); closed in wave 6p: the per-kind cap reaches the transport before the first range, the adapter uses the shared allowlist, the clock is read after the download, the window is re-checked before the store effect (`WindowClosed`), unsupported refs round-trip and the caption bound is Telegram's 1024 characters with a 4096-byte ceiling; `delete` removes the index before the bytes, so a swap between probe and unlink leaves an orphan for `reclaim_orphans`; orphan unlinks do not fsync the shard directory; `MediaConfiguration` has no grace field (the service uses the default); concurrency is smoke-tested; no staged service binds the transport.

## MINI_API_REVIEW — "Independently verify Mini App auth data actions and browser behavior"

- Candidate: `main` at or after e256791b (surface last changed in wave 6a, 55d0f363).
- Files: `src/cepaf_gleam/telegram/auth.gleam`, `mini_api.gleam`, `mini_runtime.gleam`, `mini_control*.gleam`, `mini_alert*.gleam`, `mini_immune_observer.gleam`, the other `mini_*` observers and views.
- Laws to verify: initData validation (HMAC, freshness, allowlist, replay); every action route gated and recorded; every page answers declared or observed state or a typed reason (`immune_actor_not_running`, `backend_unavailable`), never a default; bounded observer calls.
- Suites: the `mini_*` and `telegram_mini*` test modules; browser behaviour needs a human or a driven browser and is NOT established by the suites.
- Evidence: journals 20261026-0220 (wave 4) and 0640 (6a).
- Known residuals: the immune actor is not started by any supervisor; browser verification not rerun.

## TELEGRAM_E2E — "Verify complete staged Telegram operation and release readiness against current candidate"

- Actor: an authorized human with the staging bot only; the production bridge is never touched (INV-TGJ-05).
- Runbooks: `docs/sop/20261026-0215-telegram-real-traffic-journeys-security-runbook.md`, `...-defence-runbook.md`, `...-responder-runbook.md`; the media rows expect `backend_unavailable` until the staged service binds `configure_media(..., Some(telegram_media_transport.from_http(http_config)))`, then `ok` with a `sha256` for a captioned PNG.
- Record: each journey row's observed status, reply sha256 and UTC in Sa-plan as the task result; a model reply, board ACK or dispatcher test is not a real Telegram pass (INV-TGJ-03).

## Comprehensive verification checklist

This is a process document; it asserts no runtime conformance.

<details><summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] CHK-01-TIME — Prefix `20261026-1018-` from the host UTC clock.
- [ ] CHK-02-TAIL — Tailnet links provided; serving not re-verified.
- [x] CHK-03-FRACT — L0, L3, L4, L6, L9 assigned.
- [x] CHK-04-KM — MOC and corpus index transcluded; journals, guides and rule linked.

</details>
<details><summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] CHK-05-MUDA — No code; no dependencies.
- [ ] CHK-06-GRAPH — Not evaluated.
- [ ] CHK-07-DRIVE — Not in scope.

</details>
<details><summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Not evaluated.
- [ ] CHK-09-MATH — Not measured.
- [ ] CHK-10-9MOD — Suites named per packet; UNRUN by this document.
- [ ] CHK-11-REGR — UNRUN by this document.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — UNRUN by this document.
- [ ] CHK-13-HERMES — Not exercised.
- [ ] CHK-14-ZIGVM — Not exercised.
- [ ] CHK-15-MAX — Not applicable.
- [ ] CHK-16-OTEL — Not evaluated.

</details>
<details><summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — These packets exist because the reviews are outstanding.
- [x] CHK-18-JJ — Standalone jj; author workspace only.

</details>
<details><summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; a review packet grants no claim and no admission.
