---
name: journal-protocol
description: Mandatory 13-section journal entry protocol for building institutional knowledge. Enforces pattern recognition across sprints and ensures SC-SYNC-DOC-002 compliance.
---
# Journal Protocol Skill
This skill enforces the 13-section journal template mandated on 2026-03-27. No section may ever be omitted, regardless of work size.

# Mandatory Filename Timestamp Format
Per explicit operator mandate and `contracts/rules/timestamp-mandate.md`, every journal entry filename MUST be prefixed with `YYYYMMDD-HHSS-`:
```text
docs/journal/YYYYMMDD-HHSS-<kebab-case-title>.md
```
Where:
- `YYYY`: 4-digit calendar year (e.g. `2026`)
- `MM`: 2-digit month (`01`–`12`)
- `DD`: 2-digit day (`01`–`31`)
- `-`: Hyphen delimiter
- `HH`: 2-digit hour (`00`–`23`)
- `SS`: 2-digit seconds (`00`–`59`) — note: hour and seconds, with no minutes
- `-`: Hyphen delimiter before title slug

Example: `docs/journal/20260905-1725-task-completion-journal.md`.

# Mandatory Template Structure
Every journal entry MUST use the following headers:
1. **Scope & Trigger**: Why this work was initiated.
2. **Pre-State Assessment**: Quantified system state before.
3. **Execution Detail**: Wave/Phase breakdown.
4. **Root Cause Analysis**: Pattern-based 5-Why grouping.
5. **Fix Taxonomy**: Reusable fix patterns applied.
6. **Patterns & Anti-Patterns Discovered**: DOs and AVOIDances.
7. **Verification Matrix**: Compilation, tests, and spot-checks.
8. **Files Modified**: Detailed table with deltas.
9. **Architectural Observations**: System-level insights and diagrams.
10. **Remaining Gaps**: P0-P3 gap tracking.
11. **Metrics Summary**: Before/After delta tracking.
12. **STAMP & Constitutional Alignment**: Safety and directive validation.
13. **Conclusion**: 2-3 paragraph synthesis.

# Scaling Guide
- **Trivial (1-3 files)**: 1-2 lines per section.
- **Standard (4-15 files)**: Paragraphs for 2-5, full detail for 6-13.
- **Major (15+ files)**: Subsections per phase, full detail, and diagrams.

# Compliance
- **SC-SYNC-DOC-002**: Journal mandatory for every plan update.
- **SC-INST-001**: Institutional knowledge preserved via 13-section consistency.
- **SC-TIME-001 / DIR-TIME-001**: Mandatory `YYYYMMDD-HHSS-` filename timestamp prefix enforced.
