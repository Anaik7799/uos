# 20261026-0215 — Telegram real-traffic journeys: critical responder runbook

#fractal-l0 #fractal-l3 #fractal-l5 #fractal-l6 #zk-adr #zero-muda #km-triad #tailscale-web

[This document](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261026-0215-telegram-real-traffic-journeys-responder-runbook.md) · [Journey contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0210-telegram-operator-journey-contract.md) · [Persona language](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-2205-uos-telegram-user-centric-usecases-spec.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

Transclusions: [[zk:20260905-1801-moc-uos-unified-master]] · [[wiki:20260905-1801-uos-zk-km-corpus-index]]

Contract ID: `SC-TELEGRAM-JOURNEY-001`. Spec: [journey specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0215-telegram-journey-critical-responder.md). Audience: an authorized human operator. A model or agent cannot perform this run or record its result.

## 1. Purpose

Run the six critical-responder journeys (R1 to R6, 103 messages) against the **staging** bot and record, step by step, what the service actually answered. A step passes only when the observed reply fits the expected class. A truthful refusal where the spec expects one is a pass. A truthful gap where the spec expects an observation is recorded as `GAP(<backend>)`, never as a pass.

## 2. Prerequisites (all must hold before the first message)

- [ ] **Staging bot only.** The bot username is the staging bot and differs from the production bot `@c3i_talk_bot`. The production bridge is not started, stopped, reconfigured or messaged.
- [ ] **Token placement.** The staging bot token exists only in the reviewed private transport configuration. It is never pasted into this runbook, a chat, a ticket, a screenshot or the evidence directory.
- [ ] **Allowlist.** The staging service allowlist contains exactly the operator's (chat id, user id) pair. Messages from any other pair are rejected by the guard, and that is the expected behavior.
- [ ] **Service up on a named candidate.** Record the candidate commit id the staging service was built from.
- [ ] **Sa-plan claim held** for the verification task under plan `uos/telegram-runtime/20261001-1150`; the operator, not an agent, records the outcome.
- [ ] **Conversation limits** configured (free tier, bounded request count and timeout) if R6.1 to R6.3 are to reach the model. If conversation is disabled those steps answer `backend_unavailable`; record that.
- [ ] **No destructive messages.** Do not send `/memory clear`, `/memory reset`, `/approval submit`, or any `/tool cancel_job_lease`. These are outside this runbook.

## 3. Stop conditions (fail-closed Andon)

Stop the run, record the step, and raise the incident through Sa-plan if any of these occurs:

1. A reply says a plain message **executed** an action (status `executed`, `duplicate`, a restart, a halt, a merge, a seal, an export written).
2. A preview reports `process_signalled`, `process_restarted`, `global_state_mutated`, `notification_sent`, `migrated`, `secret_material_read` or `key_material_read` as **true**.
3. A reply from an `unavailable` sensor (`/immune`, `/rack-cv`, `/acoustic`, `/radar`, `/pacing`, `/whiteboard`, `/babel`) contains a measurement, detection or schedule.
4. `/verify`, `/verification` or `/voice-roll-call` is accepted rather than refused.
5. Any reply contains a token, key, secret or the root-drive serial.
6. The staging bot answers a message from a pair that is not on the allowlist.

## 4. Recording

Create an evidence directory chosen by the operator under the canonical `var/` tree (absolute path, never workspace-relative). For each step store: the exact text sent, the reply text verbatim, the Telegram message id, the sha256 of the reply text, the UTC time, and the result code. Legend: **E1** reply text and message id; **E2** E1 plus sha256; **E3** E2 plus `effect_id` for previews.

Result codes: `PASS`, `GAP(<backend>)` (truthful typed failure where an observation was expected), `FAIL`.

## 5. Step sheets

Send each message exactly as written, as a separate message, and wait for the reply before the next. Placeholders: `<TASK_ID>` is a task id taken from the R2.1 `/plan` reply; `<REQUEST_ID>` is a pending request id from R4.1, or `tg-123` when none is pending (the expected reply is then a typed not-found style answer, never an execution).

### R1 First 60 seconds

| Id | Send exactly | Pass when | Fail when | Evidence | Result |
|---|---|---|---|---|---|
| R1.1 | `/start` | class `ok`: classify Preserved(/help); reference text lists the catalog | Empty or non-catalog reply means the static reference path is broken; the responder has no map. | E2 | [ ] |
| R1.2 | `/help` | class `ok`: classify Preserved(/help); reply contains `/status` | Same as /start; help must not claim every listed command is ready (it says some are being completed). | E2 | [ ] |
| R1.3 | `/cockpit` | class `ok`: classify Preserved(/cockpit); reply contains the Tailscale cockpit URL | Missing or non-FQDN link: the responder cannot escalate to the big screen. | E2 | [ ] |
| R1.4 | `/status` | class `ok*`: classify DirectReadTool(query_system_health); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | A reply that claims health without naming what was probed is a fabricated state. | E1 | [ ] |
| R1.5 | `/health` | class `ok*`: classify DirectReadTool(query_system_health); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Alias must give the same tool; a different verdict means alias drift. | E1 | [ ] |
| R1.6 | `/ha` | class `ok*`: classify DirectReadTool(query_ha); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Cluster failover must stay reported as unverified, never as healthy. | E1 | [ ] |
| R1.7 | `/doctor` | class `ok*`: classify DirectReadTool(query_doctor); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | A live-pass claim without runtime evidence violates two-key verification. | E1 | [ ] |
| R1.8 | `/ev` | class `ok*`: classify DirectReadTool(query_doctor); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Alias must resolve to the doctor read. | E1 | [ ] |
| R1.9 | `/checklist` | class `ok*`: classify DirectReadTool(query_checklist); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Candidate records are not gate execution; a reply that says gates passed is wrong. | E1 | [ ] |
| R1.10 | `/aspects` | class `ok*`: classify Preserved(/aspects, [""]); service verification arm; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Reply must be configured candidate records, not a gate run. | E1 | [ ] |
| R1.11 | `/aspects A99` | class `denied`: classify DeniedMutation(/aspects); usage names A01 through A17 | A99 accepted would mean unbounded scope selection. | E1 | [ ] |
| R1.12 | `/exec-brief` | class `ok*`: classify DirectReadTool(query_exec_brief); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Must state it covers the configured plan only, not global health. | E1 | [ ] |
| R1.13 | `/sutra` | class `ok*`: classify DirectReadTool(query_matrix_versions); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Today /sutra answers observed Matrix client API versions; any other content is invention. | E1 | [ ] |
| R1.14 | `/status now` | class `denied`: classify DeniedMutation(query_system_health): read arguments must be absent | Accepting free text on a read tool would let arguments widen scope. | E1 | [ ] |
| R1.15 | `/fakecmd` | class `denied`: classify UnknownDirective(/fakecmd) | An unknown literal must be refused by name, never guessed. | E1 | [ ] |

### R2 Situational picture and field sensors

| Id | Send exactly | Pass when | Fail when | Evidence | Result |
|---|---|---|---|---|---|
| R2.1 | `/plan` | class `ok*`: classify DirectReadTool(query_saplan); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Observer failure must surface as a typed failure object, not an empty plan. | E1 | [ ] |
| R2.2 | `/tasks` | class `ok*`: classify DirectReadTool(query_saplan); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Alias must equal /plan. | E1 | [ ] |
| R2.3 | `/task <TASK_ID>` | class `ok*`: classify Preserved(/task, ["t1"]); service task arm; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Recorded state is a snapshot; a reply that implies a live lease is wrong. | E1 | [ ] |
| R2.4 | `/task` | class `denied`: classify DeniedMutation(/task): usage `/task <task_id>` | Must refuse; no default task may be invented. | E1 | [ ] |
| R2.5 | `/board` | class `ok*`: classify DirectReadTool(query_board); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Counts only; message bodies must not be fabricated. | E1 | [ ] |
| R2.6 | `/peers` | class `ok*`: classify DirectReadTool(query_peers); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Heartbeat observations only; absence is not proof of death. | E1 | [ ] |
| R2.7 | `/zenoh` | class `ok*`: classify Preserved(/zenoh, [""]); service zenoh arm; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Topic reads only for explicitly granted user and chat. | E1 | [ ] |
| R2.8 | `/zenoh https://example.invalid` | class `denied`: classify DeniedMutation(/zenoh): URLs and wildcards refused | A URL accepted as topic would be an SSRF-shaped hole. | E1 | [ ] |
| R2.9 | `/mesh` | class `ok (backend_unavailable if the declared mesh config is invalid)`: status ok, command, backend=`cepaf_gleam/config/mesh_source`, observation with `deployment_confirmed:false`; backend_unavailable is recorded as GAP(host input) | `deployment_confirmed` must stay false: this is configuration, never deployment evidence. | E2 | [ ] |
| R2.10 | `/storage` | class `ok*`: classify DirectReadTool(query_storage); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | The root-OS drive interlock stays asserted by policy; a read cannot change it. | E1 | [ ] |
| R2.11 | `/nvme` | class `ok*`: classify DirectReadTool(query_storage); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Alias must equal /storage. | E1 | [ ] |
| R2.12 | `/ecology` | class `ok*`: classify DirectReadTool(query_ecology); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Service health stays unverified. | E1 | [ ] |
| R2.13 | `/finops` | class `ok*`: classify DirectReadTool(query_finops); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Actual spend stays unknown; only reserved liability is reported. | E1 | [ ] |
| R2.14 | `/budget` | class `ok*`: classify DirectReadTool(query_finops); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Alias must equal /finops. | E1 | [ ] |
| R2.15 | `/zigvm` | class `ok*`: classify DirectReadTool(query_zigvm_version); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Version only; evaluation is not integrated. | E1 | [ ] |
| R2.16 | `/inference` | class `ok`: status ok, command, backend=`cepaf_gleam/ui/lustre/inference_tier`, observation with `live_status:not_observed` | `live_status` must be `not_observed`; the read lists configuration, no model was called. | E2 | [ ] |
| R2.17 | `/inference now` | class `denied`: status denied, command, reason `Usage: /inference (takes no arguments)` | Arguments to a no-argument read are refused. | E1 | [ ] |
| R2.18 | `/immune` | class `backend_unavailable`: status backend_unavailable, command, backend=`cepaf_gleam/immune/system`, reason | An ok here would be a fabricated state: the immune system is an actor with no snapshot message. | E2 | [ ] |
| R2.19 | `/rack-cv` | class `backend_unavailable`: status backend_unavailable, command, backend=`cepaf_gleam/harness/multimodal_features`, reason | No vision backend exists; any detection would be invented. | E2 | [ ] |
| R2.20 | `/acoustic` | class `backend_unavailable`: status backend_unavailable, command, backend=`cepaf_gleam/services/max_inference_daemon`, reason | No audio sample or MAX daemon is observable; any bearing would be invented. | E2 | [ ] |
| R2.21 | `/acoustic-hud` | class `ok`: status ok, command, backend=`cepaf_gleam/knowledge/raga_cybernetic_synthesis`, observation with `live_sensor:not_observed` | This is a self-audit of the shruti tables; `live_sensor` must read not_observed. | E2 | [ ] |
| R2.22 | `/radar` | class `backend_unavailable`: status backend_unavailable, command, backend=`cepaf_gleam/ui/lustre/biosemiotics_radar`, reason | The radar is fixed constants today; presenting them as telemetry would be false. | E2 | [ ] |
| R2.23 | `/pacing` | class `backend_unavailable`: status backend_unavailable, command, backend=`cepaf_gleam/harness/telegram_creative`, reason | No typing-cadence source exists; canned text is refused. | E2 | [ ] |
| R2.24 | `/pacing nap` | class `backend_unavailable`: same as /pacing; argument `nap` accepted but changes nothing | Accepting the argument must not unlock a canned answer. | E2 | [ ] |

### R3 Knowledge in the field and what-if

| Id | Send exactly | Pass when | Fail when | Evidence | Result |
|---|---|---|---|---|---|
| R3.1 | `/wiki homeostasis` | class `ok*`: classify Preserved(/knowledge, ["wiki","homeostasis"]); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Must report observed documents only. | E1 | [ ] |
| R3.2 | `/zk adr` | class `ok*`: classify Preserved(/knowledge, ["zk","adr"]); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Same. | E1 | [ ] |
| R3.3 | `/km provenance` | class `ok*`: classify Preserved(/knowledge, ["all","provenance"]); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Same. | E1 | [ ] |
| R3.4 | `/search lease` | class `ok*`: classify Preserved(/search, ["lease"]); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Searches the configured plan only; scope overrides refused. | E1 | [ ] |
| R3.5 | `/adr` | class `ok (backend_unavailable if docs/zk is unreadable)`: status ok, command, backend=`cepaf_gleam/harness/files (docs/zk)`, observation with `adr_files` and `highest_number`; backend_unavailable is recorded as GAP(host input) | Count must come from the directory read, not a constant. | E2 | [ ] |
| R3.6 | `/adr 10` | class `ok (backend_unavailable if docs/zk is unreadable)`: status ok, observation with `number`, `found`, `title`, `first_lines`; backend_unavailable is recorded as GAP(host input) | Title and first lines come from the file; `found:false` is a valid truthful answer for a missing number. | E2 | [ ] |
| R3.7 | `/adr ten` | class `denied`: status denied, reason `Usage: /adr [number 1-999]` | Non-numeric input is refused. | E1 | [ ] |
| R3.8 | `/blast-radius cepaf_gleam/harness/telegram_service` | class `ok*`: classify Preserved(/blast-radius, ["cepaf_gleam@harness@telegram_service"]); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Static compiled dependencies only; never a live impact claim. | E1 | [ ] |
| R3.9 | `/blast-radius` | class `denied`: classify DeniedMutation(/blast-radius): exact module or path required | No default module may be chosen. | E1 | [ ] |
| R3.10 | `/whatif claim 3` | class `ok`: status ok, observation `kind:pure_simulation`, `subject` says synthetic task, `granted:1`, `rejected:2` | The subject must say synthetic; this is never the live plan. | E2 | [ ] |
| R3.11 | `/whatif retry 3` | class `ok`: status ok, observation `scenario:oban_retry_backoff`, steps end in `dead` | Backoff steps are simulated; must say synthetic job. | E2 | [ ] |
| R3.12 | `/whatif zombie 100 200` | class `ok`: status ok, observation `scenario:zombie_lease_reaper`, `reaped:true` | Synthetic lease only. | E2 | [ ] |
| R3.13 | `/whatif claim 99` | class `denied`: status denied, reason is the /whatif usage text | Out-of-range values are refused, not clamped. | E1 | [ ] |
| R3.14 | `/simulate a:nominal b:degraded` | class `denied`: status denied, command `/whatif` (alias collapse), reason is the /whatif usage text | DEFECT RECORDED: /simulate canonicalizes to /whatif at classify, so its peer-mesh grammar is unreachable and the reply is the /whatif usage. A success here would mean the alias was fixed; update the journey then. | E1 | [ ] |
| R3.15 | `/canvas a:1,2,3 b:4,5,6` | class `ok`: status ok, observation `subject` says caller-supplied elements, `element_count:2`, `split_replicas_merge_converged` | Subject must say not the live canvas. | E2 | [ ] |
| R3.16 | `/canvas` | class `denied`: status denied, reason is the /canvas usage text | Empty canvas is refused. | E1 | [ ] |
| R3.17 | `/whiteboard` | class `backend_unavailable`: status backend_unavailable, backend=`cepaf_gleam/harness/telegram_collab.handle_whiteboard`, reason | Needs photo upload and a vision model; code from nowhere would be invention. | E2 | [ ] |
| R3.18 | `/babel` | class `backend_unavailable`: status backend_unavailable, backend=`cepaf_gleam/harness/telegram_collab.handle_babel`, reason | Needs a voice stream and a translation model. | E2 | [ ] |

### R4 Bounded action behind approval

| Id | Send exactly | Pass when | Fail when | Evidence | Result |
|---|---|---|---|---|---|
| R4.1 | `/approval` | class `ok*`: classify Preserved(/approval, []); service approval-status arm; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | An empty list is a valid answer; a fabricated request is not. | E1 | [ ] |
| R4.2 | `/approval approve tg-123` | class `denied`: classify DeniedMutation(/approval): unsigned approve text cannot authorize | If this ever parses as approval, the signed-receipt boundary is broken. | E1 | [ ] |
| R4.3 | `/approval propose <REQUEST_ID>` | class `ok*`: classify Preserved(/approval_manage, ["propose","tg-123"]); approval dispatch; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Proposing unknown ids must yield a typed not-found style reply, never an execution. | E1 | [ ] |
| R4.4 | `/approval propose bad` | class `denied`: classify DeniedMutation(/approval): invalid request identifier | Bad ids are refused at the guard. | E1 | [ ] |
| R4.5 | `/tool help` | class `ok*`: classify Preserved(/tool_help, []); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Help text must list only read tools plus the approval flow. | E1 | [ ] |
| R4.6 | `/action help` | class `ok*`: classify Preserved(/tool_help, []); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Alias must equal /tool. | E1 | [ ] |
| R4.7 | `/tool query_peers` | class `ok*`: classify DirectReadTool(query_peers); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Tool form and slash form must select the same read. | E1 | [ ] |
| R4.8 | `/tool shell ls` | class `denied`: classify DeniedMutation(/tool): tool unavailable | No shell tool exists; acceptance would be a critical hole. | E1 | [ ] |
| R4.9 | `/andon` | class `denied`: status denied, reason is the /andon usage text | Bare action must teach the grammar, not stop anything. | E1 | [ ] |
| R4.10 | `/andon modular_max watchdog_stall` | class `preview`: status preview, effect_id, confidence=simulated, `approval_required:true`, `process_signalled:false`, `authority:NONE` | `process_signalled` must stay false: nothing is stopped. | E3 | [ ] |
| R4.11 | `/escalate 120` | class `preview`: status preview, effect_id, confidence=simulated, `notification_sent:false` | `notification_sent` must stay false. | E3 | [ ] |
| R4.12 | `/escalate 99999` | class `denied`: status denied, reason `age_out_of_range` | Out-of-range values are refused. | E1 | [ ] |
| R4.13 | `/dark dim` | class `preview`: status preview, effect_id, confidence=declared, `global_state_mutated:false` | `global_state_mutated` must stay false; the state source is declared, not the running cockpit. | E3 | [ ] |
| R4.14 | `/resuscitate modular_max` | class `preview`: status preview, effect_id, confidence=simulated, `process_restarted:false` | No restart happens; completion needs an engaged-backend probe receipt. | E3 | [ ] |
| R4.15 | `/chaos sa-plan-daemon-kill` | class `preview`: status preview, effect_id, confidence=declared, `real_effects:none` | `real_effects` must read none. | E3 | [ ] |
| R4.16 | `/gameday worker-oom` | class `preview`: status preview, effect_id, confidence=simulated, `real_effects:none` | Pure simulation only. | E3 | [ ] |
| R4.17 | `/lockbox seal credential_suspected` | class `preview`: status preview, effect_id, confidence=declared, `secret_material_read:false`, `execute:unavailable:vault_kek` | Sealing must not run; the vault is not read. | E3 | [ ] |
| R4.18 | `/rotate-keys 90 40` | class `preview`: status preview, effect_id, confidence=declared, `key_material_read:false`, `policy_decision` | Declared inputs only; no key is read. | E3 | [ ] |
| R4.19 | `/sidecar ingress` | class `preview`: status preview, effect_id, confidence=simulated, `runtime_observation:unknown`, backend `unavailable:mirage_unikernel_daemon` | Nothing boots; runtime state must read unknown. | E3 | [ ] |
| R4.20 | `/rewind 5` | class `preview`: status preview, effect_id, confidence=simulated, `store_mutations:0` | The history is declared; no live store is read. | E3 | [ ] |
| R4.21 | `/repro task-1` | class `preview`: status preview, effect_id, confidence=declared, `executes_commands:false` | Task state must read not_observed in the preview. | E3 | [ ] |
| R4.22 | `/bisect abcd ef01` | class `preview`: status preview, effect_id, confidence=simulated, `vcs_calls:0` | No VCS call is made; outcome is assumed. | E3 | [ ] |
| R4.23 | `/merge zkuzwnup` | class `backend_unavailable`: status backend_unavailable (inside the preview object), effect_id, backend=`integration_lease`, `requires`, `vcs_mutation:false` | A plain preview here would hide that no integration lease can be read. | E2 | [ ] |
| R4.24 | `/migrate MIG-02-SANDBOX discovered` | class `preview`: status preview, effect_id, confidence=simulated, `migrated:false`, `admission:unverified` | `migrated` must stay false. | E3 | [ ] |
| R4.25 | `/eco-schedule jobs=5` | class `preview`: status preview, effect_id, confidence=simulated, `jobs_scheduled` | No job is enqueued. | E3 | [ ] |
| R4.26 | `/pair-voice alpha` | class `preview`: status preview, effect_id, confidence=declared, `pipeline_active:false` | Nothing opens. | E3 | [ ] |
| R4.27 | `/pair-voice Alpha` | class `denied`: status denied, reason is the /pair-voice usage text | Uppercase is refused. | E1 | [ ] |
| R4.28 | `/verify` | class `denied`: classify DeniedMutation(/verify): action not implemented for a plain message | Denied by design: verification needs the approval flow (see 20261026-0150), not a plain message. An executed reply here is a boundary breach. | E1 | [ ] |
| R4.29 | `/verification` | class `denied`: classify DeniedMutation(/verify) (alias of /verify) | Same as /verify; the alias resolves to the same canonical literal. | E1 | [ ] |
| R4.30 | `/voice-roll-call` | class `denied`: classify DeniedMutation(/voice-roll-call) | Denied by design: the media design forbids an unauthenticated path from offering to authenticate a constitutional vote; the adapter stays an unrouted candidate. | E1 | [ ] |

### R5 Handover and memory

| Id | Send exactly | Pass when | Fail when | Evidence | Result |
|---|---|---|---|---|---|
| R5.1 | `/handover` | class `denied`: status denied, reason is the /handover usage text | Bare action must teach the slug grammar. | E1 | [ ] |
| R5.2 | `/handover shift-a` | class `preview`: status preview, effect_id, confidence=observed, `sections:13`, `docs_directory_untouched:true` | Nothing is written by the preview; the file name carries the host clock so it is not asserted. | E3 | [ ] |
| R5.3 | `/commitments` | class `preview`: status preview, effect_id, confidence=declared, `execute:backend_unavailable:...telegram_task_command` | `tasks_observed` must be 0 here: open tasks need the service observer configuration. | E3 | [ ] |
| R5.4 | `/export-audit limit=10` | class `preview`: status preview, effect_id, confidence=declared, `never_exported` lists secret_bytes, backend `unavailable:rusty_vault_nif` | No export file is written; secrets are never listed as exportable. | E3 | [ ] |
| R5.5 | `/memory` | class `ok*`: classify Preserved(/memory, []); memory dispatch; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Status only; clearing history (`/memory clear`) is not exercised. | E1 | [ ] |
| R5.6 | `/history` | class `ok*`: classify Preserved(/messages, []); memory dispatch; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Alias must resolve to /messages. | E1 | [ ] |
| R5.7 | `/messages` | class `ok*`: classify Preserved(/messages, []); memory dispatch; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Same. | E1 | [ ] |
| R5.8 | `/retro` | class `ok (backend_unavailable if docs/journal is unreadable)`: status ok, backend=`cepaf_gleam/harness/files (docs/journal)`, observation `newest` filenames, note says no retro registry exists; backend_unavailable is recorded as GAP(host input) | The note must state there is no retro registry; filenames only. | E2 | [ ] |
| R5.9 | `/retro 3` | class `ok (backend_unavailable if docs/journal is unreadable)`: status ok, `newest` has at most 3 entries; backend_unavailable is recorded as GAP(host input) | More than the limit means the bound is broken. | E2 | [ ] |
| R5.10 | `/postmortem` | class `ok (backend_unavailable if docs/journal is unreadable)`: status ok, `keyword:postmortem`, `keyword_matches`; backend_unavailable is recorded as GAP(host input) | Match count is a filename scan, not an incident record. | E2 | [ ] |
| R5.11 | `/postmortem 0` | class `denied`: status denied, reason `Usage: /postmortem [count 1-20]` | Zero is refused. | E1 | [ ] |

### R6 Conversation fallback

| Id | Send exactly | Pass when | Fail when | Evidence | Result |
|---|---|---|---|---|---|
| R6.1 | `the pump room is flooding, what should I check first` | class `ok*`: classify Preserved(conversational, [text]); conversation path (or backend_unavailable when the conversation model is disabled); the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Advice is advisory; it must not claim an observation or an executed action. | E1 | [ ] |
| R6.2 | `/agy summarize the open risks` | class `ok*`: classify Preserved(/agy, [text]); conversation path; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Same; the model never gains effect authority. | E1 | [ ] |
| R6.3 | `/socratic why did the lease expire` | class `ok*`: classify Preserved(/socratic, [topic]); conversation path; the reply is an observation that names its source, or a typed failure naming the missing backend (record GAP) | Questions only; no invented root cause. | E1 | [ ] |
| R6.4 | `/socratic` | class `denied`: classify DeniedMutation(/socratic): topic of 1 to 2048 bytes required | Empty topic refused. | E1 | [ ] |
| R6.5 | `/AGY hello` | class `denied`: classify UnknownDirective(/AGY) | Literals are case-exact; a guess would be silent aliasing. | E1 | [ ] |

## 6. Steps that cannot pass until a named backend exists

These steps are expected to return `backend_unavailable` (or, for the previews, to state that execution is unavailable). Recording them as `PASS` means the refusal was truthful. They become capability passes only when the named backend exists and the spec row is changed.

| Step | Named backend that must exist first |
|---|---|
| R2.18 `/immune` | `cepaf_gleam/immune/system`: A read-only snapshot message on the immune actor, exposed through a supervised synchronous reader with a bounded reply. |
| R2.19 `/rack-cv` | `cepaf_gleam/harness/multimodal_features`: A camera ingest path and a computer-vision model call through the isolated MAX tier, with a typed result reader. |
| R2.20 `/acoustic` | `cepaf_gleam/services/max_inference_daemon`: An audio sample ingress and a running MAX daemon exposing `infer_audio`, plus a bounded bearing kernel. |
| R2.22 `/radar` | `cepaf_gleam/ui/lustre/biosemiotics_radar`: A live telemetry feed replacing the fixed constants, with freshness and source fields. |
| R2.23 `/pacing` | `cepaf_gleam/harness/telegram_creative`: A typing-cadence or session-telemetry source with consent and retention rules. |
| R2.24 `/pacing nap` | `cepaf_gleam/harness/telegram_creative`: Same as /pacing; the `nap` argument needs a real schedule source, not canned text. |
| R3.17 `/whiteboard` | `cepaf_gleam/harness/telegram_collab.handle_whiteboard`: Photo upload (media ingress is currently unsupported), a vision model, and a reviewed code-synthesis step. |
| R3.18 `/babel` | `cepaf_gleam/harness/telegram_collab.handle_babel`: A voice stream and a translation model behind the isolated inference tier. |
| R4.23 `/merge zkuzwnup` | `integration_lease`: A reader for the held `integration/main` lease and green build/test evidence at the new tip; execution only through the signed approval flow. |
| R4.17 `/lockbox seal credential_suspected` (execute leg) | `vault_kek`: An opened vault and production authority; sealing runs only after signed approval. |
| R4.18 `/rotate-keys 90 40` (execute leg) | `vault_kek_rotation`: An opened vault and production authority; rotation is operator-gated (re-seal-tpm). |
| R5.4 `/export-audit limit=10` (execute leg) | `rusty_vault_nif`: A loaded vault NIF and an evidence directory; the export writes metadata only. |
| R4.19 `/sidecar ingress` (execute leg) | `mirage_unikernel_daemon`: A supervised unikernel daemon and Solo5 toolchain evidence. |
| R5.3 `/commitments` (execute leg) | `cepaf_gleam/harness/telegram_task_command`: The pinned Sa-plan observer configuration held by the service. |
| R3.14 `/simulate a:nominal b:degraded` | The classify alias for `/simulate` must stop collapsing into `/whatif` before the peer-mesh simulation can answer. |
| R4.28 `/verify`, R4.29 `/verification` | The signed approval-execute extension (design 20261026-0150) wired for plain-message verification. Denial is the correct answer until then. |
| R4.30 `/voice-roll-call` | An authenticated surface for the biometric arm. Denial is the correct and intended answer today. |

## 7. Sa-plan evidence line

The operator records exactly one line per run in Sa-plan (task evidence under plan `uos/telegram-runtime/20261001-1150`), after the run, with real values:

```text
TELEGRAM-JOURNEY-RESPONDER-REAL-TRAFFIC run=<UTC-iso> operator=<name> bot=<staging-username> candidate=<commit_id> journeys=R1..R6 steps=103 pass=<n> gap=<n> fail=<n> stopped=<yes|no> evidence_dir=<absolute path> reply_digests=<sha256 of the digest manifest>
```

A run with any `FAIL` or `stopped=yes` is recorded as such and is not a pass. A passing run grants no release or admission: it is the TELEGRAM_E2E acceptance input only. EV ceiling 93; EV-94..109 NOT_ADMITTED.

## 8. After the run

1. Remove nothing from the service; leave stored state for the next reviewer.
2. Confirm no production bridge activity occurred during the run window.
3. Rotate nothing and paste nothing: the token never left the reviewed private configuration.
4. File the evidence directory path and the digest manifest hash in the Sa-plan line above.

## Comprehensive verification checklist

Checks below are obligations for this runbook package, not blanket passing claims. Runtime, formal and sovereign obligations remain UNRUN.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — `20261026-0215` prefix on the file name.
- [x] **CHK-02-TAIL** — Full Tailscale FQDN links; serving status unverified.
- [x] **CHK-03-FRACT** — L0, L3, L5, L6 tags assigned.
- [ ] **CHK-04-KM** — Cross-links to wiki, ZK and journal to be reconciled by the integrator.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Not exercised by this package.
- [ ] **CHK-06-GRAPH** — Not exercised by this package.
- [ ] **CHK-07-DRIVE** — Not exercised; no storage command can act from a plain message.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — UNRUN.
- [ ] **CHK-09-MATH** — UNRUN.
- [ ] **CHK-10-9MOD** — Dispatcher-layer journey tests only; other modalities UNRUN.
- [ ] **CHK-11-REGR** — UNRUN.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Dispatcher functions observed; no OTP supervision observed.
- [ ] **CHK-13-HERMES** — UNRUN.
- [ ] **CHK-14-ZIGVM** — UNRUN.
- [ ] **CHK-15-MAX** — UNRUN; `/inference` lists configuration only.
- [ ] **CHK-16-OTEL** — UNRUN.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent review outstanding.
- [x] **CHK-18-JJ** — Authored in a sibling jj workspace; no native Git used.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: journey specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0215-telegram-journey-critical-responder.md) · [Contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0210-telegram-operator-journey-contract.md)

UOS footer: `nas-1.tail55d152.ts.net:4100` · document evidence grants no system admission. Sa-plan remains the sole execution authority.
