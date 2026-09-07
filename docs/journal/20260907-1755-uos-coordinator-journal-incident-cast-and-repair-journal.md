# 20260907-1755 — Coordinator journal incident: CAST analysis and repair

#fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #km-triad #rocha-semiotics #cybernetics #zero-muda #zk-adr #stamp-stpa

**UOS / Journal / Incident** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
**Live document:** [http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1755-uos-coordinator-journal-incident-cast-and-repair-journal.md](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1755-uos-coordinator-journal-incident-cast-and-repair-journal.md)
**Transclusions:** `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
**Records:** `generated/20260907-1734-uos-decision-record-coordinator-journal-repair.json` (repair), `generated/20260907-1747-uos-decision-record-coordinator-sqlite-store.json` (store) · **Tasks:** sa-plan `uos/claude-integration/20260907-1355` `COORD-JOURNAL-DB` (executing) · **Actor:** L0-fable (claude-fable-5-1)

## 1. Scope & Trigger
At 17:30:51Z my lease claim for the KM integration returned `journal sequence or digest mismatch; replay refused`. Every session_sync command for every session failed the same way. SC-4.2 of the STPA protocol: a red that implicates the evidence path gets a CAST entry before any rerun. This journal is that entry and the repair record.

## 2. Pre-State Assessment
Event journal `var/coordination/tri-agent/events`: 416 files. Last coordinator-written events: 411–413 (my Reports, 16:50Z). Events 414–416 carried operation ids of session 6e132c1c but were not produced by `session_sync_ffi:transact` (no lock, no replay). All 415 files 1–415 shared one mtime, 17:12:46.56Z, inside a 100 ms window. Event 1's `previous_digest` was `""`; the coordinator's genesis digest is the schema string `uos-session-sync/v1`. Event 416's `previous_digest` matched no event and its own digest did not match its body.

## 3. Execution Detail
1. Chain walk over `previous_digest` links: one break (416). Quarantined 416 into `events-quarantine/` with a note, byte-identical, under the repair record and operator consent. Replay still refused.
2. Per-event proxy `digest == sha256(compact body)`: 8 of my events flagged; deeper check showed the recorded digests equal the ASCII-escaped (`\uXXXX`) form, i.e. the whole journal had been re-serialized and re-signed by a foreign serializer.
3. Replay probe (escript calling `uos_swarm@session_sync:replay/1`) with prefix bisection: refused from event 1, because the genesis link had been emptied. Same result with the canonical workspace's older build, so not a library change on my side (`gleam_json` 3.1.0 both sides).
4. Wrote `session_sync.resign` (rebuild every event with `make_event` from genesis; content preserved; gaps and commands refused by `apply` fail closed) and the CLI verb `resign <root> <out_root>`; produced a re-signed journal in a scratch root: 415 events, replay OK (sequence 415, 5 sessions), 0 content differences against the foreign form, genesis link restored. Unit test added (600 uos_swarm tests).
5. The swap of the shared `events/` directory is blocked by my execution guard; handed the two-move command to the operator. Foreign form to be kept as `events-foreign-20260907T1712Z`.
6. Operator direction received: move the journal to SQLite with recomputed digests and a robust API and protocol → decision record 1747, task COORD-JOURNAL-DB, worker W-M dispatched with the fixed design (append-only rows, chain trigger, store-computed digests, typed API, CLI parity, protocol document, migration from the re-signed events).

## 4. Root Cause Analysis
- Why did every command fail? Replay is fail-closed on the digest chain; the chain's byte form and genesis link no longer matched the coordinator's canonicalization.
- Why did the chain change? A foreign writer (session 6e132c1c tooling; op ids `agy-*`) loaded all events, re-serialized them (ASCII-escaped, genesis link `""`), re-signed them with its own digest computation and wrote them back in place, then appended 414–416 in that form.
- Why could it? The journal is a plain directory of files; the transaction lock and the "immutable event already exists" guard only bind writers that use `session_sync_ffi`. Same-UID processes can rewrite anything (the module's own doc states this trust boundary).
- Why was it not caught earlier? The coordinator validates only on replay; nobody replayed between 17:12 and 17:30 (my last successful operation was 16:50Z).
- Why a foreign writer at all? AGY sessions integrated the coordinator into their own runtime instead of calling the CLI; the protocol never said "CLI only" in machine-checkable form.

## 5. Fix Taxonomy
Quarantine sidecar (416); canonical re-sign (`resign`); operator-executed directory swap; SQLite store with triggers (in progress); protocol document making the single writer path explicit; board convention of `evidence_grade`/`verified_by` (ETC-3) applied to every post about this incident.

## 6. Patterns & Anti-Patterns Discovered
DO: walk links, then self-consistency, then mtimes, then bisect with the real replay function. DO: rebuild from content with the writer's own canonicalization, never edit bytes by hand. AVOID: any tool that loads and re-dumps a signed journal. AVOID: assuming a link-valid chain is a valid chain.

## 7. Verification Matrix
| Check | Result |
|---|---|
| chain walk (prev links) after quarantine | 415 events, 0 breaks |
| replay of the in-place journal | refused from event 1 (both builds) |
| `resign` output replay | OK: sequence 415, 5 sessions, last digest `0be46857…` |
| content parity foreign vs re-signed | 0 differences over 415 events (`body` minus `previous_digest`) |
| unit test `resign_rebuilds_canonical_chain_from_foreign_form_test` | pass; suite 600 passed / 0 failures |
| shared journal swap | PENDING operator |

## 8. Files Modified
`apps/uos_swarm/src/uos_swarm/session_sync.gleam` (+`resign`); `apps/uos_swarm/src/session_sync_cli.gleam` (+`resign` verb); `apps/uos_swarm/test/session_sync_test.gleam` (+1 test); `generated/20260907-1734-…coordinator-journal-repair.json`; `generated/20260907-1747-…coordinator-sqlite-store.json`; this journal. Runtime files: `var/coordination/tri-agent/events-quarantine/0000000416.json` (+note); scratch `coord-resigned/events` awaiting the swap.

## 9. Architectural Observations
A digest chain in files protects against accidental corruption, not against a cooperating same-UID process that rewrites the whole chain. The protection has to live where the write happens: a database with append-only and chain triggers, and a single documented writer API. The operator's directive matches this analysis.

## 10. Remaining Gaps
- P0: shared journal swap (operator). Until then no session can claim a lease and main cannot move.
- P1: AGY's foreign writer must be named and stopped; the swarm must agree on "CLI or store API only".
- P1: SQLite store landing and cutover with peer acknowledgement (COORD-JOURNAL-DB).
- P2: a periodic replay/verify probe so a broken chain is detected within minutes, not on the next claim.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| events affected | 415 rewritten + 1 invalid append |
| content lost | 0 measured (415/415 bodies identical) |
| time fail-closed | from 17:12:46Z (rewrite) to the swap; detected 17:30:51Z |
| repair code | 1 function, 1 CLI verb, 1 test |
| remote tokens | 0 for the diagnosis (R0/R1); worker W-M R4 for the store |

## 12. STAMP & Constitutional Alignment
Hazards: H-3 (telemetry/evidence diverging from reality), L-3 (evidence contamination), L-6 (loss of execution authority through fragmented state). Constraints honored: SYNC-05 (nothing deleted; foreign form kept), SYNC-06 (fail-closed replay worked as designed), SYNC-12 (inspect before reclaim; unknown owners fail closed), the execution guard (shared-state moves handed to the operator). No runtime action taken.

## 13. Conclusion
The coordinator did its job: it refused a journal that was no longer its own. The content survived; the byte form and the signatures did not. The re-sign path restores the chain without inventing history, the swap is one operator command away, and the SQLite store moves the guarantee from convention into the database.

## Comprehensive verification checklist
Document checks and production gates have different evidence scopes; runtime items remain UNRUN for this journal.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Host-clock timestamp prefix.
- [x] **CHK-02-TAIL** — Full clickable Tailscale FQDN references.
- [x] **CHK-03-FRACT** — Fractal tags assigned.
- [x] **CHK-04-KM** — Records, task and transclusions cross-linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Not exercised.
- [ ] **CHK-06-GRAPH** — Not exercised.
- [ ] **CHK-07-DRIVE** — Not exercised.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Not exercised.
- [ ] **CHK-09-MATH** — Not exercised.
- [x] **CHK-10-9MOD** — Unit suite executed for the repair code (600/0).
- [ ] **CHK-11-REGR** — Not exercised.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [x] **CHK-12-GLEAM** — Coordinator replay and re-sign exercised in Gleam/OTP.
- [ ] **CHK-13-HERMES** — Not exercised.
- [ ] **CHK-14-ZIGVM** — Not exercised.
- [ ] **CHK-15-MAX** — Not exercised.
- [ ] **CHK-16-OTEL** — Not exercised.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Codex R5 requested on the repair and the store.
- [x] **CHK-18-JJ** — Authored with standalone JJ; no native Git mutations.

</details>

Navigation: [ZK Master MOC](http://nas-1.tail55d152.ts.net:4100/zk) · [Hermes Wiki Corpus Index](http://nas-1.tail55d152.ts.net:4100/wiki) · [Review Tome](http://nas-1.tail55d152.ts.net:4100/docs/docs/handover/20260905-1801-review-tome-consolidation-and-verification.md) · **Previous:** [Evidence-truth journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1655-uos-evidence-truth-checks-journal.md)
