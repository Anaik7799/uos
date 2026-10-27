# Development hive bootstrap and verification

Observed intake: 2026-10-27T05:03:32Z. Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Source](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-0532-hive-development-bootstrap.md)

Canonical execution authority: `uos/hive-development/20261027-0532` in Sa-plan. This document is a projection, not a task queue. The Telegram programme remains `uos/telegram-fractal-tests/20261027-0312`; its full scope is preserved.

## Authority and exit

The operator answered the pending bounded development-bootstrap request with “full access. setup full development environment and services. understand system sop, processes and rules. use all of them. setup up full hive”. This authorizes the scoped local bootstrap necessary to establish reviewed harness execution. Production release, destructive storage effects, external source ingestion and real Telegram messages remain separate effects. Preserve the five existing uncommitted root additions.

Direct bootstrap ends after candidate-bound initialized MCP clock/status/read/write/build/test, authority refusal, claim and release evidence, plus independent review. It does not remain open to bypass an inconvenient harness refusal. An unknown effect is reconciled before retry. Per-task finite grants follow; no fabricated identity, reviewer vote, admission or expired-grant reuse.

## What, why, where, how and when

| Sa-plan task | Required outcome | Dependency / timing |
|---|---|---|
| BOOTSTRAP | Synchronized clock, pinned toolchain, resource and service inventory; finite grant proposal and independent review packet | First; direct bootstrap scoped above |
| GRANT_REVIEW | Independent peer verifies exact proposal, source/control identities, bounds and canonical review result | After BOOTSTRAP |
| MCP_ACTIVATE | Initialized successor MCP; claim, clock, scoped read/write, build/test, negative authority controls and terminal release | After GRANT_REVIEW |
| AGENT_PARITY | UOS-local rules/skills/hooks/configuration agree; actual agent identity, delivery and ACK evidence | After MCP_ACTIVATE; disjoint changes |
| SERVICE_VERIFY | Development OTP services, native libraries and dependencies exercised; honest availability and failure reporting | After MCP_ACTIVATE; isolated stores and ports |
| HIVE_VERIFY | Independent cross-agent task exchange, restart/recovery and runtime acceptance | After AGENT_PARITY and SERVICE_VERIFY |

The bootstrap grant covers MCP_ACTIVATE only. New source/configuration scopes require further reviewed grants. Fixed time/resource bounds precede execution. Priority is safety and readiness, then C×T×F×dependency×impact; operator utility×FMEA×criticality×STPA×operational-use remains supplementary and cannot waive controls.

## Observed starting state and counterevidence

- Pinned toolchain preflight: 31 checks passed; OTP 29 / ERTS 17.0.5 / Gleam 1.16.0. Chrony synchronized, stratum 3, Normal, absolute offset below 1 ms.
- Main source baseline: `73df20c4c9a67e76b670cdddc4e53e8d1379925e`; root working change `pkyvxzuzrqyouyvnrvxpmzrmxnpmzskm`. No native Git operation.
- Four configured native MCP tools; standard initialized stdio advertises 53 tools, twelve declarations unavailable. Successor MCP refuses `grant_path_missing`; project development entry is disabled.
- Actual AGY process at pane w4:p4, conversation `78478741-67b5-4c1e-8857-7a6dc948d10f`, returned individual quota exhausted, about 74 hours until reset. No successful advisory work or ACK is credited. Claude review is a separate available provider, never disguised as AGY.
- AGY CLI reports modes `accept-edits`, `auto`, `plan`; effort `low`, `medium`, `high`, `xhigh`, `max`. Current model list includes Gemini 4 Argon low/medium/high and Gemini 3.8 Flash low/medium/high, plus non-Google choices. Availability list does not establish usable quota or price. Prefer Flash medium for bounded mechanical work and Argon for complex review only after quota/correctness evidence; no optimum is claimed.
- Seven named core user services active; 164 failed matching units include many historical test units. Presence and active state do not prove behavior. No cleanup or restart performed.
- Ten native `.so` paths found in application priv; loaded ABI, bounds and behavior remain capability-specific obligations.
- C3I native system source has false-confidence risks: `Up` is treated as healthy; absent immune source defaults nominal; topic count can be constant 12; absent verification evidence can become cached 266/266. These are defects to cover with independent regression oracles, not health acceptance evidence.
- Imported Codex symbiosis guidance resolves to a local historical import and references five missing files. Adapt locally without modifying imported originals or external trees.

## Verification and rollback

BOOTSTRAP receipts are under `var/harness/20261027-0532-hive/`; risk portfolio is `var/harness/20261027-0532-hive-current-risk.json`. Native successor tests are development evidence, not operational acceptance. Every service and NIF needs identity, fresh behavior, bounded failure/recovery, and explicit unavailable states. Every actual agent needs session identity, permitted task, delivery receipt and independent ACK. A model result or health string cannot close the hive.

Restore only owned configuration backups if activation fails; terminate only owned development processes; preserve all failing receipts and canonical state. Do not reset shared journals, delete shared Zenoh namespaces, clear unrelated failures or restart production to obtain a green result. EV ceiling stays 93. Complete Telegram verification still requires TDD red/green provenance, BDD and property oracles, real service journeys, human staging evidence, measured load and recovery.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME: synchronized host timestamp observed.
- [x] CHK-02-TAIL: canonical FQDN links provided; serving verification pending.
- [x] CHK-03-FRACT: layer tags provided.
- [x] CHK-04-KM: plan and journal linked; further KM publication pending.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [ ] CHK-05-MUDA: complete dependency scan pending.
- [ ] CHK-06-GRAPH: runtime native-boundary evidence pending.
- [ ] CHK-07-DRIVE: physical storage unchanged; safety tests pending.

</details>
<details><summary>Domain 3 — Test evidence</summary>

- [ ] CHK-08-C1C8: UI coverage pending.
- [ ] CHK-09-MATH: mathematical gates pending.
- [ ] CHK-10-9MOD: complete test modalities pending.
- [ ] CHK-11-REGR: runtime regression campaign pending.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [ ] CHK-12-GLEAM: successor activation pending.
- [ ] CHK-13-HERMES: independent behavioral evidence pending.
- [ ] CHK-14-ZIGVM: kernel interoperability pending.
- [ ] CHK-15-MAX: inference service verification pending.
- [ ] CHK-16-OTEL: cross-service correlation pending.

</details>
<details><summary>Domain 5 — Governance</summary>

- [ ] CHK-17-SOV: independent review pending; no global admission.
- [x] CHK-18-JJ: standalone JJ observed; unrelated edits preserved.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV-93 ceiling retained; EV-94..109 NOT_ADMITTED. No new EV identifier.

</details>

[Previous: Telegram plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-0312-telegram-fractal-test-plan.md) · [Next: journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0532-hive-development-bootstrap-journal.md)

UOS footer: scoped development setup; Sa-plan owns status; system acceptance incomplete.
