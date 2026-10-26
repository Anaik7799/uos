# 20261026-0215 — Real-traffic journeys runbook: security incident (staging bot)

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda #tailscale-web #stamp-stpa

[This runbook](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261026-0215-telegram-real-traffic-journeys-security-runbook.md) · [Journey spec](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0215-telegram-journey-security-incident.md) · [Journey contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0210-telegram-operator-journey-contract.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

Transclusions: [[zk:20260905-1801-moc-uos-unified-master]] · [[wiki:20260905-1801-uos-zk-km-corpus-index]]

Contract `SC-TELEGRAM-JOURNEY-001`. This runbook is executed by an authorized human operator with the STAGING bot. A model or agent cannot run it or record its result. It grants no authority and no admission. EV ceiling 93; EV-94..109 NOT_ADMITTED.

## 1. Prerequisites

- The staging bot token exists only in the reviewed private transport configuration of the staging service. It is never typed into a chat, a ticket, this runbook or a shell history.
- Exactly the responder's (user id, chat id) pair is allowlisted. A second Telegram account (the stranger) is NOT allowlisted and has opened a chat with the staging bot (SEC-J1/S1 needs it).
- The production bridge, production allowlist and production services are untouched. The staging service points at staging state only. Confirm by reading the staging service's configured bot id before you start.
- Host clock synchronised (`chrony`); record the offset at start. Record UTC to the second for every step.
- Record the candidate under test: the Jujutsu commit id of the deployed staging build (`jj log -r @ --no-graph -T 'commit_id.short()'` in the integrator workspace).
- A Sa-plan task lease for this run is held by the operator under `uos/telegram-runtime/20261001-1150` before the first message is sent.
- Nothing here is destructive: all ControlledAction literals reach `route_preview` only. Do NOT submit a real approval receipt for any request created by these journeys on a staging service that is wired to real effects; SEC-J5/S9 is skipped unless the staging service has no effect authority.

## 2. Result vocabulary

| Result | Meaning |
|---|---|
| PASS | The reply class and every listed field/value match, and no failure condition is seen. |
| EXPECTED_UNAVAILABLE | The reply is the truthful `backend_unavailable` (or preview naming the unavailable path) listed for the step. This proves honesty, not capability. |
| FAIL | Any other class, a missing listed field, a success shape without a named source, or any failure condition in the step table. |
| SKIPPED | Not sent, with the stated reason. A skipped step is never a pass. |

A journey passes when it has no FAIL and no SKIPPED other than the planned ones named below. Fields may appear as JSON keys or as rendered `key: value` lines in the chat; the listed values must be identical.

## 3. Evidence to record for every step

1. UTC time sent and time the reply arrived.
2. The exact text sent.
3. SHA-256 of the reply text (hash the text copied from Telegram; do not store screenshots with identifiers).
4. Result (PASS, EXPECTED_UNAVAILABLE, FAIL, SKIPPED).
5. For ingress and attachment steps: confirmation that NO reply arrived, and the service's tombstone envelope digest if the operator can read it.

Never record the bot token, a signed approval receipt, or any key material. Record digests only.

## SEC-J1 — Suspicious ingress

Goal: Confirm that only the allowlisted responder reaches the command surface, characterise health, and preview a containment record without stopping anything.

| Step | Send exactly | Expected reply class and fields | Pass when | Fail when | Evidence |
|---|---|---|---|---|---|
| S1 | From the NON-allowlisted account send `/status`. | No reply to the sender. The update is tombstoned; nothing appears in the chat. | No reply of any kind arrives within 60 s. | Any reply to S means an allowlist breach (P0): stop the run and open an incident. | envelope digest in tombstone; no outbox row |
| S2 | `/nosuch` | A typed denial naming the unknown command. No success wording. | Reply matches the expected class and fields. | A success-shaped reply to an unknown literal. | reply text sha256 + UTC |
| S3 | (not sendable: Telegram clients cannot send U+0000) | n/a | SKIPPED (planned): covered by the dispatcher test only | n/a | note the skip |
| S4 | `/status` | service read: ok \| backend_unavailable; fields: status field; no success without a named source | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A health claim with no named observation source. | reply sha256 + UTC |
| S5 | `/peers` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Peer list fabricated while the mesh is unreachable. | reply sha256 + UTC |
| S6 | `/zenoh` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A topic summary that does not name its source. | reply sha256 + UTC |
| S7 | `/immune` | `status=backend_unavailable` with `backend`, `reason`, `backend=cepaf_gleam/immune/system` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | Any ok reply: the immune actor has no read-only snapshot message. | reply sha256 + UTC |
| S8 | `/rete watchdog=false,mesh_running=false` | service: evaluation reply; fields: status field; advice only | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A Rete result presented as an executed action. | reply sha256 + UTC |
| S9 | `/andon modular_max provider_failure` | `status=preview` with `confidence=simulated`, `effect_id`, `approval_required`, `authority=NONE` | Reply matches the expected class and fields. | process_signalled must be false; an executed status here is a defect. | reply sha256 + UTC; effect_id |

Steps that cannot reach a capability PASS until the named backend exists (they can only be EXPECTED_UNAVAILABLE):

- S7 `/immune`: Needs a read-only snapshot message on the immune system actor (cepaf_gleam/immune/system) so antibody state can be read synchronously.

## SEC-J2 — Credential-exposure scare

Goal: Triage a suspected credential exposure: check storage lock and knowledge, preview seal, rotation and audit export, and open an approval request without any key material being touched.

| Step | Send exactly | Expected reply class and fields | Pass when | Fail when | Evidence |
|---|---|---|---|---|---|
| S1 | `/search credential` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Search hits invented when the index is unreadable. | reply sha256 + UTC |
| S2 | `/nvme` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Any text implying the lock was changed. | reply sha256 + UTC |
| S3 | `/lockbox seal credential_exposure_suspected` | `status=preview` with `confidence=declared`, `effect_id`, `execute=unavailable:vault_kek`, `approval_required`, `authority=NONE` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | secret_material_read must be false; any 'sealed' wording is a defect. | reply sha256; effect_id |
| S4 | `/lockbox unseal credential_exposure_suspected` | `status=denied` with `reason` | Reply matches the expected class and fields. | An unseal preview: Telegram must offer seal only. | reply sha256 |
| S5 | `/rotate-keys 90 120` | `status=preview` with `confidence=declared`, `effect_id`, `policy_decision=overdue`, `execute` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | key_material_read must be false. | reply sha256; effect_id |
| S6 | `/export-audit event=get_failed_stale limit=100` | `status=preview` with `confidence=declared`, `effect_id`, `backend=unavailable:rusty_vault_nif`, `never_exported` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | never_exported must list secret_bytes; a digest list means a real export happened. | reply sha256; effect_id |
| S7 | `/approval` | service: ledger reply; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A request listed as approved without receipts. | reply sha256 + UTC |
| S8 | `/approval propose tg-4501` | service: ledger reply; fields: request state pending | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Proposal treated as approval; proposal alone grants nothing. | request id + reply sha256 |
| S9 | `/tool cancel_job_lease j1 -- credential_scare_hold` | service: approval-gated reply; fields: no cancellation record without approval | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A reply stating a lease was cancelled without a signed approval. | reply sha256 |

Steps that cannot reach a capability PASS until the named backend exists (they can only be EXPECTED_UNAVAILABLE):

- S3 `/lockbox seal credential_exposure_suspected`: execute unavailable: vault_kek
- S5 `/rotate-keys 90 120`: execute unavailable: vault_kek_rotation
- S6 `/export-audit event=get_failed_stale limit=100`: backend unavailable: rusty_vault_nif

## SEC-J3 — Hostile media attachment

Goal: Handle a photo, audio clip or document from an untrusted party: nothing is downloaded or interpreted, media-dependent commands refuse truthfully, and a sandbox sidecar is previewed.

| Step | Send exactly | Expected reply class and fields | Pass when | Fail when | Evidence |
|---|---|---|---|---|---|
| S1 | Send a harmless test photo with the caption `/status` (no other text). | A typed media reply (wave 6h): `status` is `backend_unavailable` with `reason=media_transport_not_configured` or `media_not_configured` on a staging service without a transport; `caption_directive` names what the caption asked and nothing from it executes; `declared_kind=photo`. With a bound transport the status is `denied` (inspection or store refusal) or `ok` with a `sha256`. | A reply arrives within 60 s with `capability=media.intake` and one of the three statuses; no image is described or acted on. | A reply that describes the image content, or `ok` without a `sha256`, or any execution of the caption directive. | reply sha256 + UTC; stored object digest when ok |
| S2 | `/rack-cv` | `status=backend_unavailable` with `backend`, `reason`, `backend=cepaf_gleam/harness/multimodal_features` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | Any ok reply: no vision backend exists. | reply sha256 + UTC |
| S3 | `/acoustic` | `status=backend_unavailable` with `backend`, `reason`, `backend=cepaf_gleam/services/max_inference_daemon` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | Any bearing or number in the reply. | reply sha256 + UTC |
| S4 | `/whiteboard` | `status=backend_unavailable` with `backend`, `reason`, `backend=cepaf_gleam/harness/telegram_collab.handle_whiteboard` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | Any synthesised code. | reply sha256 + UTC |
| S5 | `/babel` | `status=backend_unavailable` with `backend`, `reason`, `backend=cepaf_gleam/harness/telegram_collab.handle_babel` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | Any translated text. | reply sha256 + UTC |
| S6 | `/sidecar sandbox` | `status=preview` with `confidence=simulated`, `effect_id`, `runtime_mode=simulation_only`, `admission=unverified`, `backend=unavailable:mirage_unikernel_daemon` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | 'started' or 'booted' wording; nothing is started. | reply sha256; effect_id |
| S7 | `/verification` | A typed denial. | Reply matches the expected class and fields. | A verification result: the approval-execute extension is not wired for /verify. | reply sha256 |

Steps that cannot reach a capability PASS until the named backend exists (they can only be EXPECTED_UNAVAILABLE):

- S1 `photo`: Needs attachment intake: admit a file reference with size and type bounds, no automatic download, a quarantined scan path, and a typed reply naming what was and was not read (media design governance/planning/20261011-1354, MEDIA_IMPL).
- S2 `/rack-cv`: Needs a computer-vision backend (camera or ViT result) reachable from cepaf_gleam/harness/multimodal_features and the attachment intake path.
- S3 `/acoustic`: Needs an audio sample path and a running MAX daemon whose status the harness can observe.
- S4 `/whiteboard`: Needs an uploaded-photo intake and a vision model; the in-repo handler returns static text and is refused.
- S5 `/babel`: Needs a voice-stream intake and a translation model; the in-repo handler returns static text and is refused.
- S6 `/sidecar sandbox`: backend unavailable: mirage_unikernel_daemon
- S7 `/verification`: Needs the /verify approval-execute extension (20261026-0150) wired through classify and the service so a signed approval can bind a verification job; today classify denies the literal.

## SEC-J4 — Swarm and mesh anomaly

Goal: Assess a suspected mesh partition or rogue peer using observations and pure simulations, preview synthetic failure drills, and never claim live repair.

| Step | Send exactly | Expected reply class and fields | Pass when | Fail when | Evidence |
|---|---|---|---|---|---|
| S1 | `/mesh` | `status=ok` with `backend`, `observation`, `backend=cepaf_gleam/config/mesh_source` | Reply matches the expected class and fields. | Wording that confirms deployment: the read is declaration only. | reply sha256 + UTC |
| S2 | `/peers` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Peers listed while the mesh is unreachable. | reply sha256 + UTC |
| S3 | `/board` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Board messages invented. | reply sha256 + UTC |
| S4 | `/zenoh indrajaal/l0/const/andon/halt` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A wildcard topic being accepted. | reply sha256 + UTC |
| S5 | `/ha` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | HA claimed healthy with no named source. | reply sha256 + UTC |
| S6 | `/whatif zombie 100 200` | `status=ok` with `backend`, `observation`, `backend=cepaf_gleam/planning/sa_plan_simulator` | Reply matches the expected class and fields. | The reply must say synthetic task, not a live lease. | reply sha256 + UTC |
| S7 | `/whatif claim 5` | `status=ok` with `backend`, `observation`, `backend=cepaf_gleam/planning/sa_plan_simulator` | Reply matches the expected class and fields. | granted other than 1 contradicts the single-writer model. | reply sha256 + UTC |
| S8 | `/simulate n1:partitioned n2:nominal n3:nominal` | `status=denied` with `reason`, `command=/whatif` | Reply matches the expected class and fields. | An ok peer-quorum reply: today /simulate is catalogued as an alias of /whatif and its peer syntax is refused. | reply sha256 |
| S9 | `/chaos zenoh-network-partition` | `status=preview` with `confidence=declared`, `effect_id`, `real_effects=none`, `execute` | Reply matches the expected class and fields. | real_effects other than none. | reply sha256; effect_id |
| S10 | `/gameday packet-loss-moderate` | `status=preview` with `confidence=simulated`, `effect_id`, `real_effects=none` | Reply matches the expected class and fields. | real_effects other than none. | reply sha256; effect_id |
| S11 | `/resuscitate modular_max` | `status=preview` with `confidence=simulated`, `effect_id`, `approval_required`, `completion_requires=engaged_backend_probe_receipt` | Reply matches the expected class and fields. | process_restarted must be false. | reply sha256; effect_id |

Steps that cannot reach a capability PASS until the named backend exists (they can only be EXPECTED_UNAVAILABLE):

- S8 `/simulate n1:partitioned n2:nominal n3:nominal`: Needs the peer-quorum syntax routed to the simulation adapter: telegram_simulation_read_command implements /simulate node:mode, but the catalog canonicalises /simulate to /whatif so classify hands it the wrong grammar.

## SEC-J5 — Evidence export and escalation

Goal: Preserve evidence by reference, preview escalation and cockpit posture, and move the decision into the signed approval flow.

| Step | Send exactly | Expected reply class and fields | Pass when | Fail when | Evidence |
|---|---|---|---|---|---|
| S1 | `/repro tg-1` | `status=preview` with `confidence=declared`, `effect_id`, `effect=none`, `packet_contains` | Reply matches the expected class and fields. | executes_commands must be false; the task state is declared not_observed. | reply sha256; effect_id |
| S2 | `/bisect abc1 abc9 8` | `status=preview` with `confidence=simulated`, `effect_id`, `plan` | Reply matches the expected class and fields. | vcs_calls must be 0. | reply sha256; effect_id |
| S3 | `/rewind 3` | `status=preview` with `confidence=simulated`, `effect_id`, `replay_before_sha256`, `replay_after_sha256` | Reply matches the expected class and fields. | store_mutations must be 0. | reply sha256; effect_id |
| S4 | `/export-audit` | `status=preview` with `confidence=declared`, `effect_id`, `backend=unavailable:rusty_vault_nif` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | A reply carrying real digests. | reply sha256; effect_id |
| S5 | `/escalate 3600` | `status=preview` with `confidence=simulated`, `effect_id`, `staleness_level=dead`, `runbook_severity=P0`, `approval_required` | Reply matches the expected class and fields. | notification_sent must be false; nobody is paged. | reply sha256; effect_id |
| S6 | `/escalate 90` | `status=preview` with `confidence=simulated`, `effect_id`, `staleness_level=stale`, `runbook_severity=P2` | Reply matches the expected class and fields. | Severity not lower than S5. | reply sha256; effect_id |
| S7 | `/dark emergency` | `status=preview` with `confidence=declared`, `effect_id`, `target_mode=emergency`, `approval_required` | Reply matches the expected class and fields. | global_state_mutated must be false. | reply sha256; effect_id |
| S8 | `/approval propose tg-4502` | service: ledger reply; fields: request state pending | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Proposal treated as approval. | request id + reply sha256 |
| S9 | `/approval submit tg-4502 operator signed-receipt-placeholder` where the token is the approver's out-of-band signed receipt. SKIP unless staging has no effect authority. | service: ledger reply; fields: accepted only with a valid signed receipt | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A placeholder or unsigned token accepted. | request id + receipt digest (never the receipt) |

Steps that cannot reach a capability PASS until the named backend exists (they can only be EXPECTED_UNAVAILABLE):

- S4 `/export-audit`: backend unavailable: rusty_vault_nif

## SEC-J6 — Post-incident handover

Goal: Close the incident with a handover skeleton, open commitments, recent journals, the plan and cost position, and the cockpit link for the next shift.

| Step | Send exactly | Expected reply class and fields | Pass when | Fail when | Evidence |
|---|---|---|---|---|---|
| S1 | `/handover incident-20261026` | `status=preview` with `confidence=observed`, `effect_id`, `slug=incident-20261026`, `sections` | Reply matches the expected class and fields. | docs_directory_untouched must be true. | reply sha256; effect_id |
| S2 | `/handover` | `status=denied` with `reason` | Reply matches the expected class and fields. | A preview with an invented slug. | reply sha256 |
| S3 | `/commitments` | `status=preview` with `confidence=declared`, `effect_id`, `execute=backend_unavailable:cepaf_gleam/harness/telegram_task_command` | Result EXPECTED_UNAVAILABLE: reply matches exactly. | tasks_observed must be 0 here; a non-zero count with no observer is fabricated. | reply sha256; effect_id |
| S4 | `/postmortem` | `status=ok` with `backend`, `observation`, `backend=cepaf_gleam/harness/files (docs/journal)` | Reply matches the expected class and fields. | A post-mortem summary: only journal filenames are listed. | reply sha256 + UTC |
| S5 | `/retro 5` | `status=ok` with `backend`, `observation`, `backend=cepaf_gleam/harness/files (docs/journal)` | Reply matches the expected class and fields. | More than 5 entries. | reply sha256 + UTC |
| S6 | `/adr 1` | `status=ok` with `backend`, `observation`, `backend=cepaf_gleam/harness/files (docs/zk)` | Reply matches the expected class and fields. | found=false for ADR 1. | reply sha256 + UTC |
| S7 | `/plan` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Tasks listed with no observer. | reply sha256 + UTC |
| S8 | `/finops` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A cost figure with no ledger source. | reply sha256 + UTC |
| S9 | `/exec-brief` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A brief that cites evidence it did not read. | reply sha256 + UTC |
| S10 | `/messages` | service: memory reply; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | Messages from another chat appearing. | reply sha256 + UTC |
| S11 | `/cockpit` | service: static reference; fields: cockpit URL | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | A health claim in the reference reply. | reply sha256 |
| S12 | `/checklist` | service read: ok \| backend_unavailable; fields: status field | PASS if the reply is an ok that names its source; EXPECTED_UNAVAILABLE if it is a typed backend_unavailable naming the backend. | 18/18 claimed without a named source. | reply sha256 + UTC |

Steps that cannot reach a capability PASS until the named backend exists (they can only be EXPECTED_UNAVAILABLE):

- S3 `/commitments`: Needs the pinned Sa-plan observer configuration held by the service so open tasks can be read.

## 4. Steps that cannot pass until a named backend exists

| Step | Named backend or work item | Result recorded today |
|---|---|---|
| SEC-J1/S7 `/immune` | Needs a read-only snapshot message on the immune system actor (cepaf_gleam/immune/system) so antibody state can be read synchronously. | EXPECTED_UNAVAILABLE |
| SEC-J2/S3 `/lockbox seal credential_exposure_suspected` | execute unavailable: vault_kek | EXPECTED_UNAVAILABLE |
| SEC-J2/S5 `/rotate-keys 90 120` | execute unavailable: vault_kek_rotation | EXPECTED_UNAVAILABLE |
| SEC-J2/S6 `/export-audit event=get_failed_stale limit=100` | backend unavailable: rusty_vault_nif | EXPECTED_UNAVAILABLE |
| SEC-J3/S1 (photo with caption `/status`, no text field) | Intake exists (wave 6h): guard accepts the caption, the input row carries the declared reference, the service answers the typed media reply through download, inspection and the content-addressed store. Still unavailable until a deployment binds a fetch transport in configure_media; no production transport is in the tree. | EXPECTED_UNAVAILABLE |
| SEC-J3/S2 `/rack-cv` | Needs a computer-vision backend (camera or ViT result) reachable from cepaf_gleam/harness/multimodal_features and the attachment intake path. | EXPECTED_UNAVAILABLE |
| SEC-J3/S3 `/acoustic` | Needs an audio sample path and a running MAX daemon whose status the harness can observe. | EXPECTED_UNAVAILABLE |
| SEC-J3/S4 `/whiteboard` | Needs an uploaded-photo intake and a vision model; the in-repo handler returns static text and is refused. | EXPECTED_UNAVAILABLE |
| SEC-J3/S5 `/babel` | Needs a voice-stream intake and a translation model; the in-repo handler returns static text and is refused. | EXPECTED_UNAVAILABLE |
| SEC-J3/S6 `/sidecar sandbox` | backend unavailable: mirage_unikernel_daemon | EXPECTED_UNAVAILABLE |
| SEC-J3/S7 `/verification` | Needs the /verify approval-execute extension (20261026-0150) wired through classify and the service so a signed approval can bind a verification job; today classify denies the literal. | EXPECTED_UNAVAILABLE |
| SEC-J4/S8 `/simulate n1:partitioned n2:nominal n3:nominal` | Needs the peer-quorum syntax routed to the simulation adapter: telegram_simulation_read_command implements /simulate node:mode, but the catalog canonicalises /simulate to /whatif so classify hands it the wrong grammar. | EXPECTED_UNAVAILABLE |
| SEC-J5/S4 `/export-audit` | backend unavailable: rusty_vault_nif | EXPECTED_UNAVAILABLE |
| SEC-J6/S3 `/commitments` | Needs the pinned Sa-plan observer configuration held by the service so open tasks can be read. | EXPECTED_UNAVAILABLE |

A capability claim (for example 'the lockbox can be sealed from Telegram') is NOT supported by any of these. Only the truthful refusal is.

Service-executed arms (`/status`, `/peers`, `/zenoh`, `/rete`, `/search`, `/approval`, `/tool`, `/plan`, `/finops`, `/exec-brief`, `/messages`, `/cockpit`, `/checklist`, `/ha`, `/board`, `/nvme`) were asserted at classify shape only by the dispatcher test. Their real reply class is first observed in this run; if one returns `backend_unavailable` the result is EXPECTED_UNAVAILABLE only when the reply names the missing backend.

## 5. Sa-plan evidence line

After the run the operator, not an agent, records one line per journey as Sa-plan evidence on the leased task, using the operator's normal Sa-plan evidence path:

```text
SC-TELEGRAM-JOURNEY-001 journey=<SEC-J1..SEC-J6> plan=uos/telegram-runtime/20261001-1150 candidate=<jj commit id> bot=staging operator=<name> utc_start=<time> utc_end=<time> steps=<n> pass=<n> expected_unavailable=<n> fail=<n> skipped=<n> reply_digests=<path or list of sha256> authority=NONE admission=NONE
```

A run with any FAIL is recorded as such, with the step id and the reply digest; it is not retried silently. Fractal Jidoka applies: stop at the first FAIL that shows a success shape without a source, or any reply to the stranger, and open an incident.

## 6. After the run

- Withdraw any pending approval request created by SEC-J2/S8 and SEC-J5/S8 with `/approval withdraw <request id>`.
- Confirm no cancellation record exists for the job id used in SEC-J2/S9.
- Release the Sa-plan lease.
- Nothing in this run changes the EV ceiling or admits anything.

## Comprehensive verification checklist

Document-package checks only; the live run itself is UNRUN until an operator performs it.

<details>
<summary>Domains 1 to 5</summary>

- [x] **CHK-01-TIME**: Timestamp prefix 20261026-0215-.
- [x] **CHK-02-TAIL**: Tailnet links present.
- [x] **CHK-03-FRACT**: Fractal tags assigned.
- [x] **CHK-04-KM**: Transclusions and cross-links.
- [ ] **CHK-05-MUDA**: Scan UNRUN.
- [ ] **CHK-07-DRIVE**: No drive interaction; interlock test UNRUN.
- [ ] **CHK-10-9MOD**: Real-traffic run UNRUN.
- [ ] **CHK-17-SOV**: Operator run and independent review outstanding.
- [x] **CHK-18-JJ**: Standalone Jujutsu only.

</details>

[Journey spec](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0215-telegram-journey-security-incident.md) · [Contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0210-telegram-operator-journey-contract.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · operator evidence only; no admission.
