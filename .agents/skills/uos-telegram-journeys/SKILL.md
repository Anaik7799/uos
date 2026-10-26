---
name: uos-telegram-journeys
description: Use when adding, changing, running or accepting Telegram operator journeys (security incident, defence/HA, critical responder), touching the Telegram command surface, or preparing a real-traffic Telegram run.
---

# 20261026-0220 — UOS Telegram journeys

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l9 #zk-adr #zero-muda #km-triad

[Source](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-telegram-journeys/skills/uos-telegram-journeys/SKILL.md) · [Contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0210-telegram-operator-journey-contract.md) · [Rule](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261026-0220-telegram-journey-acceptance.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20261026-0220-telegram-journeys-guide.md) · [Bindings](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-telegram-journeys/skills/uos-telegram-journeys/references/20261026-0220-superpowers-bindings.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

Created: 2026-10-26. Contract `SC-TELEGRAM-JOURNEY-001` (rule) over the [operator journey contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0210-telegram-operator-journey-contract.md). Process guidance; grants no authority and no admission. Sa-plan remains the sole execution authority.

## When to use

- Adding, renaming or removing a Telegram command literal or family (F1–F9).
- Changing `telegram_ingress_guard`, `telegram_read_adapters`, `telegram_action_adapters` or the service loop.
- Preparing, running or recording the TELEGRAM_E2E / TELEGRAM_ACCEPT evidence.
- Reviewing a landing that touches the Telegram command surface.

## The three use cases

| Use case | Operator | Outcome | Spec |
|---|---|---|---|
| Security incident | on-call security responder | detect, contain, preserve evidence, escalate, record | [spec](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0215-telegram-journey-security-incident.md) |
| Defence / high availability | SRE under degraded conditions | observe health, exercise safeguards, verify recovery, never fabricate state | [spec](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0215-telegram-journey-defence-ha.md) |
| Critical responder | field responder with a phone | fastest truthful situational picture, bounded actions behind approval, handover | [spec](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0215-telegram-journey-critical-responder.md) |

Across the set every family F1–F9 appears at least once and every one of the 77 command literals appears in at least one step.

## How to add a journey (or a step)

1. Start from the step, not the code (test-driven): write the table row first with the expected class.
2. A spec row has the contract's columns: Step, Persona action, Literal and args, Family, Expected class, Required fields (for example `confidence`, `backend`), Authority gate (none / allowlisted pair / approval roster / operator), Evidence kept (receipt digest, journal line), Failure meaning.
3. Expected reply class is exactly one of:
   `ok` (observation from a named backend, `confidence` observed or declared), `preview` (read-only ControlledAction preview), `denied` (typed refusal), `backend_unavailable` (truthful refusal naming the missing backend), `approval_required` (needs the signed `/approval propose|submit` flow).
   `executed` and `duplicate` are reachable only through the approval flow, never from a plain message. For `/verify` (wired in wave 6b per `docs/design/20261026-0150-telegram-verify-approval-execute-extension.md`) a plain message expects `backend_unavailable` ("Verification is not configured on this service") on an unconfigured service; `executed` and `duplicate` are expected only when the operator has configured `configure_verify` and a signed verify packet exists for that exact inbox request. The dispatcher-layer test arm for `/verify` is the service-owned preserved directive (no adapter may claim it).
   Since wave 6 `/simulate` is its own canonical (peer-mesh quorum grammar), so its steps expect `ok` from `cepaf_gleam/zenoh/peer_simulator`; a step that still expects the `/whatif` usage text is stale.
4. Never expect fabricated success. If the staged system cannot do the thing, expect `backend_unavailable` or `denied` and state in the runbook what real deployment must add.
5. Mirror the row in the dispatcher-layer test `test/telegram_journey_<usecase>_test.gleam`: `telegram_ingress_guard.classify_directive(text)`, then `telegram_read_adapters.route`, `telegram_action_adapters.route_preview`, or the historical arm expectation; assert the class and the required fields.
6. A new literal must appear in at least one step or the coverage test `test/telegram_journey_coverage_test.gleam` fails.
7. Add the real-traffic message, expected reply and pass/fail criterion to the matching runbook.

## Run the staged forms

Dispatcher-layer journeys and the coverage test, with the OTP 29 in-project toolchain (no host toolchain, no network):

```bash
cd apps/cepaf_gleam && bash -c 'export UOS_ROOT=/home/an/NAS-setup/uos; source $UOS_ROOT/tools/lib/uos-toolchain.sh; uos_env; gleam build --target erlang; PA=(); for d in build/dev/erlang/*/ebin; do PA+=(-pa $d); done; erl -noshell "${PA[@]}" -eval "eunit:test([telegram_journey_security_test,telegram_journey_defence_test,telegram_journey_responder_test,telegram_journey_coverage_test],[verbose]), halt()."'
```

- Run inside your own jj workspace, provisioned per the workspace isolation contract (copy `priv/*.so` first; an unprovisioned workspace reports artifact failures, not defects).
- The service-loop journeys (poll, dispatch, outbox) live in `telegram_service_e2e_test`; run that module for the journey's first steps where the harness supports them.
- Record the observed pass/fail counts and the candidate commit; a green staged run is development evidence only.

## Prepare a real-traffic run

An authorized human executes this; an agent prepares and never sends.

1. Use the staging bot only. The token stays in the reviewed private transport configuration, never in the repository, a prompt, a board message or a journal.
2. Allowlist exactly one operator user and one chat for the staging bot.
3. Leave the production bridge untouched: do not restart, reconfigure or share its token or chat.
4. Follow the runbook for the use case ([security](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261026-0215-telegram-real-traffic-journeys-security-runbook.md), [defence](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261026-0215-telegram-real-traffic-journeys-defence-runbook.md), [responder](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261026-0215-telegram-real-traffic-journeys-responder-runbook.md)): exact messages, expected replies, pass/fail per step.
5. The operator records the outcome and evidence references in Sa-plan under the programme task.

## What counts as evidence

| Counts | Does not count as a real Telegram pass |
|---|---|
| Operator-recorded Sa-plan evidence of a staging-bot run with the exact replies observed | A model reply or model summary |
| Staged journey tests green at a named candidate (as development evidence) | A board ACK or peer directive |
| Receipt digests and journal lines named in the spec's Evidence column | A passing dispatcher-layer test presented as a real run |
| Honest `UNRUN` / `NOT_ADMITTED` for anything not observed | A score, a lease, file presence or a hook firing |

A staged pass proves the dispatcher and staged service behave as specified. It is not a real Telegram user journey, not a release, not admission. EV ceiling 93; EV-94..109 NOT_ADMITTED.

## Media pipeline (wave 6c)

Media is not a journey step; it is four pure stages behind the download: `telegram_media_ref` (T1 parse) → `telegram_media_download` (T2, per-kind caps, redacted URLs) → `telegram_media_inspect` (T3, 64-byte magic-byte sniff, fixed allowlist, never `declared_mime`) → `telegram_media_store` (T4, content-addressed by the recomputed sha256, ceiling before write, tamper and expiry refusals, bounded `delete` and `reclaim_expired` with receipts) → `telegram_media_janitor` (supervised bounded actor running reclaim on a cadence, Jidoka pause after three errors). A captioned media message is accepted at ingress (caption as command text) and answered by the typed media reply from `telegram_media_intake` (wave 6h): `backend_unavailable` until a deployment binds a fetch transport (`telegram_media_transport.from_http`, wave 6i), `denied` on any stage refusal, `ok` only when stored under the recomputed digest; the caption directive is reported, never executed. A photo without a caption is a `media_without_caption` tombstone. `Accepted` from T3 narrows the type and is never "safe to open". Guide: [media pipeline](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20261026-0801-telegram-media-pipeline-guide.md).

## Review-fix waves (6k to 6o)

Every Telegram surface gets an advisory R2 review (a Sonnet reviewer, read-only, no claim) before its independent REVIEW task; the author answers the majors in a fix wave and records the residuals in the journal and in the packet at `docs/sop/20261026-1018-telegram-review-packets.md`. Lessons from those waves: a gate added at one dispatch entry is not a gate, every entry needs its own test (L-21); when a closed enumeration is introduced, land its completeness law in the same wave, because a grep is an enumeration with an assumption baked in (L-22, `mini_reason_code_completeness_test`); a capability injected at actor start is retained for the process lifetime, so pass a closure that may capture a secret per call and prove the state clean with `sys:get_state` rather than a lexical scan of reports (L-23, the gateway drain); two R4 workers on disjoint file sets, briefed with an explicit file list, an explicit no-formatter rule for never-formatted shared files and FROM/TO mutant records, integrate per file from their snapshotted commits without conflict (L-24, the media fixes); a checker whose status is printed but not gated is decoration, so the claim script refuses any preflight status but PASS and requires an active-check PASS after the claim (L-25, a claim made on HOLD in wave 6p). Media status after 6o: a truncated range is refused (`range_truncated`, `range_total_changed`, `size_mismatch`), file paths are allowlisted, orphans and malformed indexes are reclaimed after a grace period, and the janitor runs under its own Transient sub-supervisor.

## Independent reviews, source control and the vault NIF (waves 6p to 6v)

- **Independent reviewers (AGY) claim only from a still portfolio.** Land and mirror every Sa-plan claim and completion into the risk portfolio before launching a reviewer, point its preflight at the live portfolio path, keep author records blocked while a reviewer is between launch and claim, and ready one review at a time (equal scores hold both sides). COMMAND, MEDIA, GATEWAY and MINI_API were all completed this way on 2026-10-26 with APPROVE (L-29, L-30). A record that is ready while its true blocker is a human input (the staging token for TELEGRAM_E2E) holds every other claim; write the blocker into readiness instead (L-33).
- **Ask the VCS before ingesting from an external tree.** `jj --ignore-working-copy file list -r main | grep <name>` first: the vault NIF crate and its vendored RustyVault dependency were already tracked with better redactions than a fresh copy would carry (L-31). A secret scan that finds nothing exits 1 under `pipefail`; the no-match path must be the success path of the script (L-32).
- **The vault NIF (VF-01, closed in wave 6v).** `apps/cepaf_gleam/native/rusty_vault_nif` persists secrets as AES-256-GCM envelopes in sqlite, refuses a wrong key through an encrypted verifier row and keeps its audit trail append-only by trigger. Its laws live in three places by necessity: `cargo test` for the handle (rustler atoms cannot be created outside a BEAM), `test/rusty_vault_persistence_test.erl` for the atoms through the loaded library, and a three-process `erl` observation for the cross-BEAM form (L-34). NIF `String` arguments are Erlang binaries, never charlists. The Telegram secrets still use the durable file store (`uos_vault_file.erl`, `tools/uos_vault.ml`) until the review decides otherwise.
- **A residual that reads "caller obligation" has no caller until one is written.** The gateway staleness alarm (G-04) and the Mini App immune actor stayed open through nine reviews because each was a deployment-side component nobody owned; wave 6z closed both in the tree with laws and mutants: `gateway/telegram_gateway_ticker` (cadence, per-tick Send, `Stale` repeated while stale, `Cleared` once, `Unobserved` on a silent drain) with its start site `gateway_ticker_child`, and `immune/system.{registry_name,start_named,child_spec,lookup}` with `mini_runtime` discovering the actor by name. An actor other modules must find needs a fixed atom through an FFI, not `process.new_name`, which mints a fresh atom per call. When a plan's portfolio nears the checker's 1 MiB bound, open a new Sa-plan plan with its own portfolio (L-35) rather than growing it.
- **The operator step that unblocks the staging journeys** is still two commands: `tools/telegram-staging vault-put telegram/staging/bot_token` (token on stdin) and `tools/telegram-staging bootstrap <user_id> <chat_id>`.

## Bridge hygiene, browser verification and the responder credential (wave 7a)

- **Bridge secrets.** `tools/telegram_client.ml` hands curl its URL on stdin (`-K -`) and redacts every error string; after any restart run the two grep checks in `contracts/rules/20261026-1910-telegram-secret-hygiene-and-browser-verification.md` (both must print 0). Restart only under `runtime:telegram-bridge` with `tools/telegram-staging bridge-upgrade <workspace>` run from a workspace at main; it keeps a rollback copy.
- **Mini App in a real browser.** `tools/mini_app_browser_verify.exe --user-id <allowlisted id> --out /home/an/NAS-setup/uos/var/telegram-mini-verify/<run> --app-dir <workspace>/apps/cepaf_gleam --plan <plan id> --candidate <commit> --run-id <run> --require-zenoh-start` after `PUT {"command":"start"}` to `indrajaal/telegram/mini_app_verify/<run>/cmd`. It starts its own instance on 4190, serves the official Telegram script through `Fetch` interception, writes one PNG per page, a screencast mp4, negative cases and `receipt.json`, and publishes every page result to Zenoh. Run it from the operator terminal (`!` prefix): headless Chrome completes no URL load from the agent shell (L-38).
- **Why a free-text message gets the status reply.** `uos-cognitive-worker` answers `dispatch_directive_status_default` whenever `generate_conversational_response` errors; its journal says `OPENROUTER_API_KEY missing or invalid`. Provisioning the key is an operator act (INV-TGS-06); record the absence, do not search for a key.

## Comprehensive verification checklist

This is a process/document package. The entries below do not assert production conformance.
UNRUN and NOT_ADMITTED remain nonpassing; N/A must be justified for each actual change.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Timestamp prefix recorded (20261026-0220).
- [x] CHK-02-TAIL — Full Tailscale FQDN references provided; live delivery unverified.
- [x] CHK-03-FRACT — L0–L9 applicability tagged.
- [x] CHK-04-KM — Contract, specs, runbooks and wiki guide linked in this package.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Fleet dependency exclusion scan UNRUN.
- [ ] CHK-06-GRAPH — Runtime language/NIF conformance UNRUN.
- [ ] CHK-07-DRIVE — OS storage interlock execution UNRUN.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI categories UNRUN.
- [ ] CHK-09-MATH — Mathematical quality gates UNRUN.
- [ ] CHK-10-9MOD — Nine runtime test modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression monitoring UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Staged journey tests not run by this documentation package; UNRUN.
- [ ] CHK-13-HERMES — Mandatory enforcement NOT_IMPLEMENTED by this package.
- [ ] CHK-14-ZIGVM — Runtime kernel checks UNRUN.
- [ ] CHK-15-MAX — Actual inference checks UNRUN.
- [ ] CHK-16-OTEL — Runtime telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review/admission NOT_ADMITTED.
- [x] CHK-18-JJ — No native Git command used; standalone JJ workspace fable-w4 only.

</details>

<details><summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.
A real-traffic journey pass is recorded by an authorized human in Sa-plan; this package records none.

</details>

**UOS footer:** local skill adapter; `nas-1.tail55d152.ts.net:4100`; canonical execution state remains in Sa-plan; document evidence grants no system admission.
