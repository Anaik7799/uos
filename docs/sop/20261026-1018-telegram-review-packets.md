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

- **Completed 2026-10-26 by `agy-review-e-20261026` with verdict APPROVE** (advisory review evidence, no admission): six packet laws VERIFIED at main 6a776b51, 205 tests over the ten named suites, seven hostile inputs; the verdict JSON is filed as governance evidence (`governance/planning/20261026-1434-agy-command-review-independent-verdict.json`) and in the Sa-plan task result.

- Candidate: `main` at or after e256791b (surface last changed in wave 6h, a985c3a1).
- Files: `src/cepaf_gleam/harness/telegram_commands.gleam`, `telegram_ingress_guard.gleam`, `telegram_read_adapters.gleam`, `telegram_action_adapters.gleam`, the dispatch arm in `telegram_service.gleam` (search `decode_input_media(raw_json)`), `telegram_verify_*.gleam` for `/verify`.
- Laws to verify: 77 catalog literals each answer from a module (coverage test); every mutation literal is denied at classify or previews without effect; `/verify` executes only under a signed verify packet inside a Sa-plan job claim with a receipt and answers `duplicate` on replay; captioned media is accepted with the caption as text and bare media is a `media_without_caption` tombstone; no reply fabricates success (INV-TGJ-04); no reply carries a token, file URL or raw backend text.
- Suites: `telegram_ingress_guard_test`, `telegram_commands_test`, `telegram_read_adapters_test`, `telegram_action_adapters_test`, `telegram_journey_security_test`, `telegram_journey_defence_test`, `telegram_journey_responder_test`, `telegram_journey_coverage_test`, `telegram_verify_service_test`, `telegram_service_e2e_test`.
- Evidence: journals 20261026-0230 (wave 5), 0640 (6a), 0728 (6b), 0936 (6h); specs `docs/design/20261026-0215-telegram-journey-*.md`; rule `contracts/rules/20261026-0220-telegram-journey-acceptance.md`.
- Known residuals the author recorded: V-06b, V-07, V-12 (wave 6b journal section 10); the media reply takes precedence over the caption directive by design.

## GATEWAY_REVIEW — "Verify Telegram gateway startup secrecy event routing and recovery"

- **Completed 2026-10-26 by `agy-review-g-20261026` with verdict APPROVE** (advisory review evidence, no admission): the packet laws VERIFIED at main 6a776b51, 94 tests over the six gateway suites, four hostile-input families (crashing `Send` carrying secret-shaped strings, adversarial channel spellings, queue boundary and status forgery, drain-state secrecy under `sys:get_state`); the verdict JSON is filed as governance evidence `governance/planning/20261026-1448-agy-gateway-review-independent-verdict.json`.

- Candidate: `main` at or after the wave 6n landing (the advisory review of 6a's surface, `claude-subagent-gateway-review-20261026`, returned REQUEST_CHANGES with nine majors; 6n answers them).
- Files: `src/cepaf_gleam/gateway/telegram.gleam`, `telegram_gateway_outbox.gleam`, `telegram_gateway_drain.gleam`, `src/telegram_gateway_drain_ffi.erl`; `telegram_app.gleam.broken` is deliberately not compiled.
- Laws to verify: the gateway holds no credential and reports observed startup only (with the current Zenoh client `start` can only report `subscribed: False`; no event routing exists); the drain actor's state holds no `Send` closure (the Send is passed per `Tick`; verify with `sys:get_state`); a crashing Send is contained as `OutboxUncertain("send_crashed")` with its reason discarded; the request digest covers kind, chat, topic and text; an uncertain backlog refuses Notices at capacity and Criticals only at twice the capacity; `Delivered(id ≤ 0)` is never a delivery; `enqueue` reports `Unobserved(call_timeout|actor_unavailable)` distinctly from `Full`; the Telegram channel refusal is case- and whitespace-insensitive; a supervisor restart yields an EMPTY queue and the delivery ledger holds no gateway request (no recovery exists; stated, not solved).
- Suites: `telegram_gateway_test`, `telegram_gateway_outbox_test`, `telegram_gateway_drain_test`, `gateway_coverage_test`, `gateway_comprehensive_test`.
- Evidence: journals 20261026-0220 (wave 4), 0640 (6a), the 6m journal section 10 (the review's findings) and the 6n journal.
- **G-04 closed (residuals plan `uos/telegram-residuals/20261026-1752`, GATEWAY_TICKER):** `telegram_gateway_ticker` is a supervised ticker that drives the drain on a cadence with a Send built per tick, reads `Counters` after each tick and raises `Stale` (repeated while stale), `Cleared` (once) and `Unobserved` (silent drain) on a typed alarm sink; `telegram_service.gateway_ticker_child` is its start site beside `gateway_drain_child`; seven laws in `telegram_gateway_ticker_test`, two mutants killed (bound ignored; never cleared).
- Known residuals the author recorded: a quarter of the pending capacity is reserved for Criticals and the oldest uncertain observation is exposed in `Counters` (wave 6p); before the residuals plan no ticker in the tree consumed it, so the staleness alarm was a caller obligation (G-04, now closed above); any Subject holder may `Resolve` (G-05); no pre-send durable record, so a producer re-enqueue after a restart can send twice (G-06); Send runs synchronously inside the actor with no deadline of its own (G-07); the briefing's dead outbox queue (G-10); caller-supplied `now` (G-11); the broken app file (G-12); since wave 6q the service exposes a start site (`gateway_drain_child`, `gateway_send`, `gateway_tick`; `telegram_gateway_wiring_test` runs it under a supervisor through the fixture), but no production runner composes it yet (G-13).

## MEDIA_REVIEW — "Independently verify all adopted Telegram media cases and hostile inputs"

- **Completed 2026-10-26 by `agy-review-f2-20261026` with verdict APPROVE** (advisory review evidence, no admission): every packet law VERIFIED at main 6a776b51 with file and line evidence, 207 tests over the ten named suites, four hostile-input families (path traversal and NUL in `valid_file_path`, NUL caption and multi-kind ambiguity in `from_update`, mismatched bytes in `inspect`, a directory handed to `unlink_file`); the verdict JSON is filed as governance evidence `governance/planning/20261026-1448-agy-media-review-independent-verdict.json`.

- Candidate: `main` at or after the wave 6o landing (waves 6c to 6o; the advisory review of the lifecycle since 6d, `claude-subagent-media-review2-20261026`, returned REQUEST_CHANGES and 6o answers M2-01, M2-02, M2-03, M2-04, M2-07, M2-08 in part, M2-10 and M2-11).
- Files: `src/cepaf_gleam/harness/telegram_media_ref.gleam` (T1), `telegram_media_download.gleam` (T2), `telegram_media_inspect.gleam` (T3), `telegram_media_store.gleam` (T4, delete and reclaim), `telegram_media_intake.gleam`, `telegram_media_transport.gleam`, `telegram_http_client.gleam` (`get_file`, `fetch_file_range`), `src/cepaf_gleam/telegram/telegram_media_janitor.gleam`, the `configure_media` and media arm in `telegram_service.gleam`, `src/telegram_http_test_fixture.erl` (test only).
- Laws to verify: names derive only from the recomputed SHA-256; sender strings never reach a path; ceiling and digest checks precede any write; `get` re-hashes and refuses expired objects; delete removes index then bytes under `link_info`; reclaim is bounded with a receipt; inspection reads 64 bytes and never the declared mime; the transport contacts only the configured host, accepts only the configured token's URL prefix, fetches 4 MiB ranges and cross-checks `Content-Range`; the per-kind cap is enforced across chunks; the janitor pauses after three errors; the media reply is `ok` only with a stored digest.
- Suites: `telegram_media_ref_test`, `telegram_media_download_test`, `telegram_media_inspect_test`, `telegram_media_store_test`, `telegram_media_intake_test`, `telegram_media_transport_test` (hackney), `telegram_media_janitor_test`, the slice1 placement test, the e2e captioned-photo test.
- Evidence: journals 20261026-0750 (6c and 6d), 0826 (6e), 0847 (6f), 0903 (6g), 0936 (6h), 0953 (6i), the 6j journal; design `governance/planning/20261011-1354-claude-telegram-media-design.json`; the advisory R2 review of 6c recorded in the 6c journal section 4.
- Laws added in 6o: the transport keeps the first-seen `Content-Range` total, accepts a 416 only at `offset == total` (`range_truncated` otherwise), refuses a changed total (`range_total_changed`) and a total over 52 MiB before a second range; the download adapter refuses bytes that differ from the getFile size (`size_mismatch`) and stores nothing; `valid_file_path` is an allowlist (`[A-Za-z0-9._/-]`, no `..` segment); `usage_report` skips and names a malformed index instead of failing intake; `reclaim_orphans` removes `.tmp-` files, index-less `.bin` files and undecodable indexes older than a grace period (default ten minutes) within the same bound; the janitor runs under its own Transient sub-supervisor (intensity 10 / 60 s) so four kills in five seconds leave the Telegram service alive, a `Stop` is not restarted, three all-refused runs pause it, and history refusals are capped at 32 with a dropped count; `unlink_file` re-checks `link_info` and never removes a directory.
- Known residuals: the download adapter concatenates the body in memory up to the cap; the sender-declared size is not compared (fixtures declare sizes that differ from the bytes); closed in wave 6p: the per-kind cap reaches the transport before the first range, the adapter uses the shared allowlist, the clock is read after the download, the window is re-checked before the store effect (`WindowClosed`), unsupported refs round-trip and the caption bound is Telegram's 1024 characters with a 4096-byte ceiling; `delete` removes the index before the bytes, so a swap between probe and unlink leaves an orphan for `reclaim_orphans`; orphan unlinks do not fsync the shard directory; `MediaConfiguration` has no grace field (the service uses the default); concurrency is smoke-tested; since wave 6q the worker runner binds the transport when given `media_root` (`configure_media_http`) and the e2e test `e2e_captioned_photo_with_bound_transport_is_stored_test` shows a captioned photo stored and answered `ok` through the supervised runner; a production deployment still has to pass `media_root`.

## MINI_API_REVIEW — "Independently verify Mini App auth data actions and browser behavior"

- **Completed 2026-10-26 by `agy-review-h-20261026` with verdict APPROVE** (advisory review evidence, no admission): laws M-01 to M-04 VERIFIED at main 6a776b51 with file and line evidence, 244 tests over 19 `mini_*` and `telegram_mini*` suites, four hostile-input families (NUL, empty token, bad percent-encoding and overflowing or negative `auth_date` in `auth:validate`; wrong method, wrong content type, oversize body, query injection and a stalled observation clock in `handle_data`; SQL text and off-page actions in `mini_control:parse`; a non-running immune actor); M-05 browser behaviour recorded NOT_CHECKABLE by suites, as the packet states; the verdict JSON is filed as governance evidence `governance/planning/20261026-1437-agy-mini-api-review-independent-verdict.json`.

- Candidate: `main` at or after e256791b (surface last changed in wave 6a, 55d0f363).
- Files: `src/cepaf_gleam/telegram/auth.gleam`, `mini_api.gleam`, `mini_runtime.gleam`, `mini_control*.gleam`, `mini_alert*.gleam`, `mini_immune_observer.gleam`, the other `mini_*` observers and views.
- Laws to verify: initData validation (HMAC, freshness, allowlist, replay); every action route gated and recorded; every page answers declared or observed state or a typed reason (`immune_actor_not_running`, `backend_unavailable`), never a default; bounded observer calls.
- Suites: the `mini_*` and `telegram_mini*` test modules; browser behaviour needs a human or a driven browser and is NOT established by the suites.
- Evidence: journals 20261026-0220 (wave 4) and 0640 (6a).
- Known residuals: the immune actor was not started by any supervisor (closed in the residuals plan, IMMUNE_SUPERVISED: `immune/system` gains `registry_name`, `start_named`, `child_spec` and `lookup`, and `mini_runtime` discovers the actor by name at observation time, answering `immune_actor_not_running` only while no supervisor has it alive; two laws in `immune_system_supervised_test`, one mutant killed); browser verification not rerun.

## VAULT_NIF_REVIEW — "Independent review of the VF-01 fix in the vault NIF"

- **Completed 2026-10-26 by `agy-review-v-20261026` with verdict APPROVE** (advisory review evidence, no admission): V-LAW-01 to V-LAW-07 VERIFIED at main 5b4073e4 (persistence across two BEAMs run by the reviewer, wrong key, disk secrecy over 28 KB of file and WAL, audit triggers, stale and undecryptable reads, offline rebuild with 66/66 tests and a digest that differs only by debuginfo path strings, no barred dependency), 66 cargo and 75 eunit tests, eight hostile probes; probes 7 and 8 (empty name, NUL in name) were stored without refusal and are closed by VAULT_NIF_HARDEN in wave 6w (`invalid_name` at every entry point, pin 6db27c1e); the verdict JSON is filed as governance evidence `governance/planning/20261026-1528-agy-vault-nif-review-independent-verdict.json`.

- Candidate: `main` at or after the wave 6v landing (the crate last changed in wave 6v; before it the NIF kept its store in RAM and unsealed with any 32-byte key, finding VF-01 in the wave 6u journal and manifest).
- Files: `apps/cepaf_gleam/native/rusty_vault_nif/src/lib.rs` (entry points over the disk handle), `vault_handle.rs` (`unseal_verified`, `put_with_lease`, `get_latest_meta`, `destroy`, `lease_renew`, `audit_tail`), `sqlite_backend.rs` (`vault_meta`, append-only triggers, lease and audit queries), `crypto.rs` (AES-256-GCM envelope, unchanged), `apps/cepaf_gleam/test/rusty_vault_persistence_test.erl`, `apps/cepaf_gleam/priv/rusty_vault_nif.sha256` (pin 73be69d9, supersedes f5aaab89), the crate README.
- Laws to verify: persistence across fresh handles and across BEAMs; a wrong or wrong-length key is refused and the vault stays sealed while the right key still works; neither the secret bytes nor the master key reach the sqlite file or its WAL; the audit table refuses UPDATE and DELETE and records `key_established`, `unseal`, `put`, `get`, `seal`, `unseal_refused` in order and is readable while sealed; a stale row returns `ttl_expired` and an undecryptable row `decrypt_failed`, never a value; the pinned library is a build of the tracked crate; no Tongsuo or SM2/3/4 dependency.
- Suites: `cargo test --offline --locked` in the crate (66, nine of them `vf01_laws`); eunit `rusty_vault_persistence_test` (3), `vault_wiring_test`, `vault_migration_test`, `uos_vault_file_test`, `vault_kek_test`.
- Evidence: the wave 6u journal (finding), the wave 6v journal (closure, mutants, three-process observation), `governance/sources/20261026-1420-vault-source-control-verification-and-c3i-telegram-gateway-ingestion.json`.
- Known residuals the author recorded: the first unseal of an empty vault establishes the key (there is no separate init-with-key step), so an attacker who can write to an empty vault file first chooses its key; the audit row append is best-effort and not transactional with the row it describes; the lease id is stored in clear (it carries the secret name); the Telegram staging and production secrets still use the durable file store, not this NIF.

## VAULT_NIF_REVIEW2 — "Independent review of the wave 6w hardening" (plan `uos/telegram-vault/20261026-1530`)

- **Completed 2026-10-26 by `agy-review-v2-20261026` with verdict APPROVE** (advisory review evidence, no admission): V2-LAW-01 to V2-LAW-04 VERIFIED at main 96ab356f (name validation at all four entry points before disk; a bad-name row written directly with sqlite is neither read nor destroyed through the NIF, recorded as an administrative residual; the predecessor's seven laws re-checked including two-BEAM persistence; the installed library byte-identical to the pin), 67 cargo and 76 eunit tests, five new probes (512-byte name accepted and 513 refused, a spaces-only name accepted, a 1 MiB value round-trips, a NUL in a lease id answers `not_found`, 20 concurrent unseal/seal cycles from two BEAMs with `integrity_check` ok); the verdict JSON is filed as governance evidence `governance/planning/20261026-1629-agy-vault-nif-review2-independent-verdict.json`.
- Candidate: `main` at 96ab356f (wave 6w).
- Laws: V2-LAW-01 name validation; V2-LAW-02 pre-existing bad rows; V2-LAW-03 the predecessor's seven laws; V2-LAW-04 pin and provenance.
- Residual for the next hardening: a name made only of spaces is accepted (0x20 is not a control byte); whether blank names are refused is a contract decision, not a defect of the law as written.

## VAULT_NIF_REVIEW3 — "Adversarial security review of the vault NIF" (plan `uos/telegram-vault/20261026-1530`)

- **Completed 2026-10-26 by `agy-review-v3-20261026` with verdict APPROVE** (advisory review evidence, no admission): V3-LAW-01 to V3-LAW-06 VERIFIED at main 28d0d752. Durability: a put survived `kill -9` of its BEAM and was read by a fresh one. Four writers: 200 versions from four BEAMs, counts exact, `integrity_check` ok, no duplicate `(name, version)`. Poisoned state: a `vault_seal` between `require_active` and the master-key lock makes the `.expect("require_active guarantees Some")` panic inside the lock and poisons it; rustler traps the panic as `nif_panicked` and later calls answer `sealed` or `nif_panicked`, so no BEAM crash and no hang, but the handle is disabled by one race (closed by VAULT_NIF_HARDEN2). Verifier race: 10/10 two-process races on an empty file produced one winner and one `wrong_key`, `vault_meta` row count 1. Audit bypass: with direct sqlite access `DROP TRIGGER`, `UPDATE`, a past-timestamp `INSERT` and a table `RENAME` all succeed and `vault_audit_tail` returns the forged rows without notice (closed by the hash chain in VAULT_NIF_HARDEN2); `PRAGMA writable_schema` is refused by defensive mode. Zeroization: the 32 key bytes are present in NIF memory while unsealed and absent after `vault_seal`; the verdict JSON is filed as governance evidence `governance/planning/20261026-1637-agy-vault-nif-review3-independent-verdict.json`.
- Findings carried into VAULT_NIF_HARDEN2: the seal-vs-read race (FM-POISONED-KEY-MUTEX) and undetectable audit tampering (FM-AUDIT-TAMPER-UNDETECTED).

## VAULT_NIF_REVIEW4 — "Review of the wave 6x race and audit-chain closure" (plan `uos/telegram-vault/20261026-1530`)

- **Completed 2026-10-26 by `agy-review-v4-20261026` with verdict APPROVE** (advisory review evidence, no admission): V4-LAW-01 to V4-LAW-06 VERIFIED at main d75aa8f1. No poison: 30 s of 190,661 seal/unseal cycles against 4,960,940 reads and puts on one handle, every answer a typed tuple, zero `nif_panicked`, the handle serving afterwards. Chain under four writers: 200 versions, 207 chained rows, no two rows share a predecessor digest, the chain recomputes. Tamper-evidence: `DROP TRIGGER` plus `UPDATE` of row 3, a past-timestamp `INSERT`, a `DELETE` after dropping its trigger and a table rename each answered `audit_chain_broken` with the correct first id (or `storage_error` with the table missing). Pre-chain file: a vault created with the previous library (built at 28d0d752) migrates on open and its legacy rows are refused at id 1 while `kv_get` still works. The earlier laws hold; the installed library equals pin a5b63b75 and `Cargo.lock` changed only by the direct `blake2` dependency. 69 cargo and 77 eunit tests; the verdict JSON is filed as governance evidence `governance/planning/20261026-1643-agy-vault-nif-review4-independent-verdict.json`.
- Residual carried forward: a consistent rewrite of the whole chain is not detectable without a root digest kept outside the file (VAULT_NIF_HARDEN3).

## VAULT_NIF_REVIEW5 — "Review of the external-root primitive" (plan `uos/telegram-vault/20261026-1530`)

- **Completed 2026-10-26 by `agy-review-v5-20261026` with verdict APPROVE** (advisory review evidence, no admission): V5-LAW-01 to V5-LAW-06 VERIFIED at main 3556dae0. The head equals sqlite's last digest and row count, moves with every append, and is the same from a fresh handle and a fresh BEAM. Root verification answers the current head with `ok`, a stale head with `audit_root_mismatch` carrying both digests, and a broken chain with `audit_chain_broken`, never a root result. The reviewer performed the consistent full rewrite itself (dropped the trigger, changed row 3, recomputed all digests with `crypto:hash(blake2s, …)`): `vault_audit_tail` accepts the rewritten chain while `vault_audit_verify_root` against the pre-rewrite head fails closed. Truncation of the last row and replacement of the file with an older copy both answer `audit_root_mismatch`. Earlier laws re-run (103,795 seal cycles against 11,910,572 reads with zero panics). Pin ab61df88 equals the installed library; `Cargo.lock` unchanged from d75aa8f1; the Erlang stub exports both functions. 70 cargo and 78 eunit tests; the verdict JSON is filed as governance evidence `governance/planning/20261026-1710-agy-vault-nif-review5-independent-verdict.json`.
- **Root-keeper decision (recorded under VAULT_EVIDENCE3):** the chain head is written as a Sa-plan evidence row by the vault owner after each session, not as a file under `var/vault`, which shares the failure domain of the database and can be rolled back with it. The implementation belongs to the plan that adopts the NIF for live secrets; the Telegram secrets stay on the durable file store until then.

## Real-traffic status (2026-10-26, residuals plan REAL_TRAFFIC_OUTBOUND)

- **Observed working with real Telegram traffic:** the outbound gateway path (drain + ticker under a supervisor, token and chat id from the vault store inside the BEAM, one Critical and one Notice delivered through `api.telegram.org` to the operator chat: 2 enqueued, 2 delivered, 0 failed, 0 uncertain, no alarm; receipt `governance/planning/20261026-1734-claude-telegram-real-traffic-outbound-receipt.json`); the production bridge polling live with the vault-first token (0 `database is locked` lines since the wave 6t restart); `getMe` through the repaired client.
- **Staged only (bound transport or fixtures), pending real inbound traffic:** the command journeys (19 steps over 78 literals, 33 journey tests), the media intake (204 tests), the Mini App (172 tests), the service lifecycle (88 end-to-end scenarios). They need messages sent to the staging bot by the operator; the staging service is assembled and starts with two operator commands.
- Tool: `harness/telegram_real_traffic_probe` (`run/6`, `render_report/1`) is the real-traffic smoke for the outbound path; it is run on purpose under a Sa-plan task and never takes a chat id as an argument.

## TELEGRAM_E2E — "Verify complete staged Telegram operation and release readiness against current candidate"

- Actor: an authorized human with the staging bot only; the production bridge is never touched (INV-TGJ-05).
- Runbooks: `docs/sop/20261026-0215-telegram-real-traffic-journeys-security-runbook.md`, `...-defence-runbook.md`, `...-responder-runbook.md`; the media rows expect `backend_unavailable` until the staged service binds `configure_media(..., Some(telegram_media_transport.from_http(http_config)))`, then `ok` with a `sha256` for a captioned PNG.
- Record: each journey row's observed status, reply sha256 and UTC in Sa-plan as the task result; a model reply, board ACK or dispatcher test is not a real Telegram pass (INV-TGJ-03).
- Preconditions observed on 2026-10-26: no Telegram bridge is active on nas-1 (`uos-telegram-bridge` inactive) and no staging deployment is described in the tree; a staging service must be started from the worker runner with the staging bot token in its private configuration and, since wave 6q, `media_root` for the media rows.
- User-side clients (the operator acts as the allowlisted user; the bot-side `tools/telegram-client` cannot act as a user): Telegram Desktop 7.3.3 is installed on nas-1 as a snap; Telegram Web (`https://web.telegram.org`) in the installed Google Chrome 154; the Telegram mobile app; terminal clients not installed here and provisionable only through the pinned Nix inputs (`tdl`, `nchat`, `tgt`); the second, non-allowlisted account for the stranger rows needs a second client session.

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
