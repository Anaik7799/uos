# EV-02 candidate staging and bounded TOML repair

1. **Scope & Trigger** — Repair independent findings that foreign TOML tables were attributed to directives and mapping ran against mutable workspace policy inputs.
2. **Pre-State Assessment** — Immutable 1e2f28 was held by the independent reviewer; the stale-header parser and four-file-only binding were preserved.
3. **Execution Detail** — The reader now uses Outside, InDirective, and ForeignTable states. Every table header ends directive collection. The runner reads a bounded input closure from the candidate commit and stages only candidate regular-file bytes in a private directory.
4. **Root Cause Analysis** — Directive capture continued across a subsequent foreign table. The runner validated its implementation while the observed superset and mirror bodies came from the working tree.
5. **Fix Taxonomy** — Typed section-state parsing; bounded immutable closure staging; typed symlink HOLD; strict raw-LF JSON.
6. **Patterns & Anti-Patterns Discovered** — A foreign table can be safely retained without granting it directive meaning. A symlink must remain a typed unbound HOLD, never be followed or copied as regular content.
7. **Verification Matrix** — Parser fixture controls 12/12 PASS; harness controls 8/8 PASS; candidate suite /tmp/ev02-governance-harness-2056/summary.json is valid:true; strict summary parser /tmp/ev02_strict_summary.ml PASS.
8. **Files Modified** — tools/ev02_governance/directive_mapping_gate.ml and tools/ev02_governance/run_checks.ml.
9. **Architectural Observations** — Candidate input bindings record every staged regular source path, digest, byte count and kind. Four candidate symlink mirror entries are retained as UNSTAGED_HOLD; mapping reports the resulting surface deficiency.
10. **Remaining Gaps** — This is not full TOML compliance. Semantics for 37 metadata-only directives and historical lineage remain HOLD. The stage only contains the finite amendment-derived closure. Independent replay and all EV admission authority remain open.
11. **Metrics Summary** — Maximum 64 rule files, 258 staged inputs, 1 MiB per input, 16 MiB mapping aggregate; observed candidate run has three valid report rows.
12. **STAMP & Constitutional Alignment** — Invalid table syntax, duplicate IDs, duplicate foreign table headers, multiline values, symlinks, missing and unbound inputs fail closed or report HOLD. Authority remains REPORT_ONLY and admission NOT_GRANTED.
13. **Conclusion** — Source d68c9a305a38bdd88aa640b594e4459480d09226 is review-ready with ACTIVE_PASS at 2026-09-09T20:56:37Z and assessment 15f74916838656bb918d71a66447e0c890f227a68cc0e1792a6b6ae94bf6fa48.
