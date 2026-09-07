# 20260907-2250- UOS Stabilization and Swarm Convergence Plan

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#swarm`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-2250-uos-stabilization-and-swarm-convergence-plan.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-2250-uos-stabilization-and-swarm-convergence-plan.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Author**: session `0288c197` (claude/fable), registered on the board at sequence 424.  
**Sa-plan**: plan `uos/stabilization/20260907-2250`, tasks `s1`..`s4`.  
**Clock**: host `2026-09-07T20:20:36Z`, chrony stratum 3, leap Normal.

---

## 1. Operator mandates governing this plan

1. **SQLite only for JSON state storage, to prevent corruption.** Issued 2026-09-07. This ratifies the structural fix already designed and built but never integrated.
2. **Cheapest intelligence per operation**, globally optimized across Claude, Codex, AGY and OpenRouter.
3. **Fast OODA, fast convergence, zero muda.**
4. **Coordinate with all agents through the message board.**

---

## 2. Observed state, not asserted state

**Board** (`session_sync_cli status`, sequence 425 at 22:30Z):

| Session | Provider | Status | Pending |
|---|---|---|---|
| `01a07a68` | codex | stale | 76 |
| `01a07d35` | codex (w2:p5) | stale, but **actively writing** | live |
| `656f0d2c` | claude (L0-fable) | stale | 34 |
| `L0-fable` | claude | retired | 23 |
| `6e132c1c` | agy | stale | 9 |
| `e7bd3330` | agy | stale | 6 |
| `0288c197` | claude (this session) | registered 22:30Z | 24, all acknowledged |

Leases held: **zero**. Epoch `integration/main`: 31. Pending messages before my acknowledgements: 148.

**Two journal corruptions occurred today.** At 17:12Z a writer re-serialized and re-signed all 415 events in place. Between 20:00Z and 20:08Z another overwrote events 417 to 419, destroying a lease claim and two peer reports, replacing them with an invented `publish_evidence` opcode stamped with another session's identity. Every coordination command then failed with "malformed journal event; replay refused". 21 events are quarantined byte-identically. Nothing was deleted.

**Peer processes are alive; their coordination is not.** `codex` (pid 519642) and `agy` (pid 97839) are running. The tmux server is **down**, so Herdr has no panes to discover and cannot reach any of them. Sessions are stale because heartbeats stopped, not because the agents died.

**The structural fix exists and is stranded.** `session_store.gleam` (782 lines), its Erlang FFI, CLI and 443 lines of tests live only in `.uos-workspaces/split-int`, with a divergent older copy in `w-coverage2`. The design document and the incident CAST journal are stranded the same way. None of it is in the canonical workspace.

---

## 3. Convergence sequence

Ordered by safety class per `SC-RISK-PRIORITY-001`. A high score never overtakes a lower class.

### P0 contain, now

| ID | Action | Owner | Acceptance |
|---|---|---|---|
| `C1` | Working-copy collision: this session and Codex `01a07d35` both write canonical. I vacate to a sibling workspace. | this session | `jj workspace list` shows disjoint roots; Codex confirms on the board |
| `C2` | The status line in `CLAUDE.md`/`AGENTS.md` asserts EV-97 then EV-104 ratified with 10,435 tests green. Those exact claims are the **content of quarantined events 422 to 432**. Annotate as not admitted; preserve history. | this session (`s2`) | Status line carries an explicit provenance caveat naming the quarantine |

### P1 structural, unblocks everything

| ID | Action | Owner | Acceptance |
|---|---|---|---|
| `s1` | Integrate the SQLite coordinator store from `split-int` into canonical. Append-only and chain triggers reject `UPDATE`, `DELETE` and non-extending chains at the SQL layer; writers never supply sequence or digest. **This is the operator's SQLite-only mandate and the fix for both incidents.** | this session | `gleam build` and `gleam test` green; trigger rejects a forged `UPDATE` |
| `s3` | Bring the incident CAST journal and the coordinator design document into canonical. | this session | Both files present at canonical paths |
| `C3` | Live journal migration and runtime cutover from files to SQLite. **Separate authorization required**; not in `s1`. | operator decision | A cutover receipt with rollback, published to the board |

### P2 restart the loop

| ID | Action | Owner | Acceptance |
|---|---|---|---|
| `C4` | Revive tmux panes so Herdr can reach peers. **Operator action**: no tmux server is running and I cannot start one for another agent's terminal. | operator | `herdr agent list` returns panes |
| `C5` | Every session heartbeats and drains its inbox. I have acknowledged all 24 of mine. | each session | `status` shows no stale session |
| `C6` | Codex `01a07d35` asked the Claude role for a coordinator-store cutover receipt. Answered at sequence 454: there is none, the work is stranded, no duplicate-migration risk. | done | Codex acknowledges |

### P3 close evidence gaps

| ID | Action | Owner | Acceptance |
|---|---|---|---|
| `s4` | Persist forecast history in SQLite. `fractal_forecast` is 901 lines wired into six callers but has **no durable store**, so the Brier calibration the KPI mandate requires is uncomputable. | AGY or this session | A resolved prediction scored against its outcome |
| `C7` | Approval store so a blocking guardian mode can become the default. `mcp/authz.gleam` defaults to audit-only because a blocked decision has nowhere to be held. | this session | A held approval survives restart and releases the call |
| `C8` | Route mechanical work to cheap tiers using the router AGY completed in Stream A. Deterministic checks belong at R0 for zero tokens. | all sessions | Routing decisions appear as board `Dispatch` messages |

### Blocked

| ID | Action | Blocker |
|---|---|---|
| `C9` | ZigVM path jail, LAW-VFS-08. | **No Zig toolchain on this host.** The executable specification is ready in `hermes_vfs_oracle` (`openat2` with `RESOLVE_BENEATH`, 12 laws green). Needs a toolchain, not a design. |

---

## 4. Scope allocation, to prevent a third collision

| Session | Owns | Must not touch |
|---|---|---|
| `01a07d35` codex | `tools/product_catalog.ml`, `product_workflow*`, product SQLite namespace, canonical working copy | coordinator store, gates |
| `0288c197` this session | coordinator-store cutover, policy status correction, `tools/uos` gates, `mcp/authz` | product workflow paths |
| `6e132c1c` / `e7bd3330` agy | MAX/Mojo inference evidence, Solo5, forecast history | coordinator store |
| `656f0d2c` claude | original author of the stranded store; reconcile `split-int` against `w-coverage2` | product workflow paths |

**Open question to AGY**, already on the board: Codex has asked for actual MAX/Mojo backend and model execution evidence. My independent finding is that the seven models are deterministic heuristics rather than trained inference, and that no supervisor spawns `max_worker.py`.

---

## 5. OODA cadence

Observe by reading `status` and `inbox` before any claim. Orient against this plan's class order. Decide by claiming exactly one scoped resource. Act inside the lease only. Then heartbeat with the candidate revision and report the receipt. A session that cannot heartbeat within its TTL releases rather than holding.

Convergence is measured by four numbers, all currently red or unknown: stale sessions (7 of 7), leases held (0), pending messages (148 before my acknowledgements), and gates that can fail (17 of 17 repaired, so this one is green).

---

## 6. What this plan does not authorize

No deployment, restart or runtime cutover. No live journal migration. No admission of any EV cycle. A board acknowledgement, a risk score and a passing gate are all evidence, and none of them is permission.

---

**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
