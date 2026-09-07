# 20260907-2250- Journal: Coordinator Incident Evidence Brought Into Canonical

`#fractal-l0` `#fractal-l3` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-incident-evidence-integration-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-incident-evidence-integration-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Plan**: [stabilization and swarm convergence plan](http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-2250-uos-stabilization-and-swarm-convergence-plan.md)  
**Clock**: host `2026-09-07T20:50:21Z`. **Sa-plan**: task `s3-incident-evidence-integration`, P2, score 162, worker session `0288c197`.

## 1. Scope & Trigger
Convergence plan item `s3`. The coordinator SQLite design document and the incident CAST journal existed only in sibling workspaces. Scope: copy both into canonical docs. No code.

## 2. Pre-State Assessment
The quarantine notes cite both documents by canonical path, but neither existed there. The design document had two copies: `split-int` at 275 lines revised 21:54Z, and `w-coverage2` at 274 lines revised 20:21Z. The incident journal was byte-identical across all three sibling workspaces.

## 3. Execution Detail
Compared the two design-document copies rather than assuming the newer was better. The one-line delta is substantive: `split-int` documents a **fourth** trigger, `events_no_replace`, and PRAGMA read-back verification, both traced to review `wf_5f54e14c-28b`. Chose `split-int`, consistent with the source chosen for the code in `s1`. Copied both documents.

Then verified the documentation against the integrated code rather than trusting it, including running the specific attack the new trigger exists to stop.

## 4. Root Cause Analysis
Sibling jj workspaces let a session produce evidence that is invisible to canonical readers. Both journal corruptions happened after the fix and its documentation already existed, in a workspace nobody else read.

## 5. Fix Taxonomy
Evidence relocation. Two file copies, no edits.

## 6. Patterns & Anti-Patterns Discovered
Pattern: when two copies of a document differ, read the diff. Here the one-line delta was the difference between documenting three triggers and four, and the fourth closes a real hole. Anti-pattern: incident records citing canonical paths that do not exist.

## 7. Verification Matrix
| Check | Result |
|---|---|
| Design document in canonical | 275 lines, `43865c1f7146` |
| Incident journal in canonical | 125 lines, `793e91fc79b2`, identical in all three sibling copies |
| Triggers documented versus triggers in code | 4 documented, 4 present: `events_no_update`, `events_no_delete`, `events_chain`, `events_no_replace` |
| **Falsifier**: `INSERT OR REPLACE` reusing a stored sequence | refused, "an insert may not reuse a stored sequence, operation_id or digest" |
| Row count before and after that attempt | 468 and 468, unchanged |

## 8. Files Modified
| File | Change |
|---|---|
| `docs/design/20260907-1750-uos-coordinator-sqlite-store-protocol.md` | New in canonical, from split-int |
| `docs/journal/20260907-1755-uos-coordinator-journal-incident-cast-and-repair-journal.md` | New in canonical, from split-int |

## 9. Architectural Observations
The `events_no_replace` trigger exists because SQLite fires DELETE triggers for the implicit delete inside `INSERT OR REPLACE` only when `recursive_triggers` is ON, and its default is OFF. An append-only table protected only by `events_no_delete` is therefore not append-only. That is a subtle enough trap to be worth the canonical documentation this task moved.

## 10. Remaining Gaps
The divergent `w-coverage2` copies of both the store and the document remain unreconciled with their authors. Live journal migration and runtime cutover still require separate authorization.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| Documents integrated | 2 |
| Triggers verified present | 4 of 4 |
| Falsifiers run and refused | 1, with row count unchanged |
| Lines edited in the copied documents | 0 |

## 12. STAMP & Constitutional Alignment
Loss L-3 evidence contamination. UCA "not provided" (incident evidence unreachable at its cited path) is closed. Documentation was verified against code rather than accepted, which is the two-key discipline applied to a documentation task. Lease held; preflight and active-check passed; no Git inside UOS.

## 13. Conclusion
The incident record and the protocol that prevents a recurrence are now where their own citations say they are, and the fourth trigger they document is present and provably effective.

---
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
