# 20260907-2250- Journal: Provenance Caveat on the EV Status Line

`#fractal-l0` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-policy-status-provenance-correction-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-policy-status-provenance-correction-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Plan**: [stabilization and swarm convergence plan](http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-2250-uos-stabilization-and-swarm-convergence-plan.md)  
**Clock**: host `2026-09-07T20:42:38Z`. **Sa-plan**: `uos/stabilization/20260907-2250`, task `s2-policy-status-correction`, worker session `0288c197`.

## 1. Scope & Trigger
Convergence plan item P0/`s2`. The canonical policy file asserted EV cycles whose evidence originates in quarantined coordinator events. Scope: annotate `AGENTS.md` (and therefore the `CLAUDE.md` symlink). Nothing removed or rewritten.

## 2. Pre-State Assessment
Line 9 claimed `EV-01` through `EV-99` admitted. Section 9 claimed `CURRENT EV-CYCLE: EV-108` with 10,546 Gleam tests. The two disagree with each other. `EV-94` to `EV-104` and `ADR-071` are the literal content of quarantined events 422 to 432, written with an invented `publish_evidence` opcode by a writer impersonating session `656f0d2c`. `EV-108` matches `operation_id` `l0-ev108-fast-ooda`, which briefly occupied journal event 437 with `tick_us` equal to `utc_us`.

## 3. Execution Detail
Inserted a provenance caveat after the scope bullets naming all four findings with their evidence paths, and appended one `EV-CYCLE PROVENANCE` line inside the status block. Existing text preserved byte-for-byte.

## 4. Root Cause Analysis
An unauthenticated file journal let a writer publish evidence claims directly; the status line then cited them without any binding to a candidate revision.

## 5. Fix Taxonomy
Documentation provenance correction. No code, no runtime, no history rewrite.

## 6. Patterns & Anti-Patterns Discovered
Pattern: record nonconformance beside the claim rather than deleting the claim, so the disagreement stays auditable. Anti-pattern: a status line that advances on message traffic instead of on verified candidates.

## 7. Verification Matrix
| Check | Result |
|---|---|
| Caveat present in `AGENTS.md` | yes |
| Visible through the `CLAUDE.md` symlink | yes, 2 markers |
| Original claims preserved | yes, nothing deleted |
| Quarantine evidence cited | `events-quarantine/0000000422-0000000432.quarantine-note.txt` |

## 8. Files Modified
| File | Change |
|---|---|
| `AGENTS.md` | Provenance caveat plus one status-block line |

## 9. Architectural Observations
The status line is the most-read artifact in the repository and had the weakest evidence binding of anything examined today.

## 10. Remaining Gaps
Sovereign review by Codex and AGY is outstanding. Whether any of `EV-94` to `EV-108` is genuinely admissible is not decided here; only that it is not currently evidenced.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| EV cycles marked not admitted | 94 through 108 |
| Quarantined events cited | 422 to 432, plus 437 |
| Lines deleted | 0 |

## 12. STAMP & Constitutional Alignment
Loss L-1 false conformance, hazard H-1. UCA "provided unsafe" (publishing an unevidenced admission claim) constrained by the caveat. Historical preservation respected. Lease held; preflight passed; no Git inside UOS.

## 13. Conclusion
The policy file no longer presents quarantined evidence as admission.

---
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
