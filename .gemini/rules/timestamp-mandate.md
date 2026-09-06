---
trigger: always_on
---

# Mandatory YYYYMMDD-HHSS- Timestamp Rule Mandate

- **Authority:** Operator Explicit Directive & UOS Canonical Policy (`SC-TIME-001`, `DIR-TIME-001`, `INV-TIMESTAMP-001`)
- **Domain:** Spatiotemporal Ledgering & Document Ingestion
- **Status:** ACTIVE & ENFORCED

---

## 1. Operator Directive

Per explicit operator directive:
> **"all generated docs must have YYYYMMDD-HHSS- timestamp. mandatory rule, update all code, skills, agents.md"**

This directive formally and permanently resolves the prior unresolved divergence between Harness (`YYYYMMDD-HHSS`) and ZigVM (`YYYYMMDD-HHMMSS`). 
Effective immediately, the canonical UOS timestamp format for all generated documents, journals, handover notes, design specs, and reports is:

$$\mathbf{T}_{\text{doc}} = \mathtt{YYYYMMDD}\text{-}\mathtt{HHSS}\text{-}\langle\mathtt{descriptor}\rangle\mathtt{.md}$$

Where:
- `YYYY`: 4-digit civil calendar year (e.g., `2026`)
- `MM`: 2-digit calendar month (`01`–`12`)
- `DD`: 2-digit calendar day of month (`01`–`31`)
- `-`: Hyphen delimiter
- `HH`: 2-digit hour in UTC or synchronized host local time (`00`–`23`)
- `SS`: 2-digit seconds (`00`–`59`)
- `-`: Hyphen delimiter separating timestamp from descriptive kebab-case slug

Example:
`20260905-1725-codex-verification-and-timestamp-mandate-journal.md`

---

## 2. Invariants & Scope of Application

1. **Mandatory Document Prefix**:
   - All newly generated documentation in `docs/`, `docs/journal/`, `docs/handover/`, `docs/plans/`, and runtime artifact directories MUST be prefixed with `YYYYMMDD-HHSS-`.
   - Any document generator, agent script, task runner, or skill creating Markdown, HTML, or JSON reports must format filenames with this exact prefix.

2. **Immutable Historical Preservation**:
   - Historical artifacts and external snapshots (such as pre-existing C3I, ZigVM, or planning files) are preserved byte-for-byte in their historical identity.
   - Never rename immutable historical files retroactively. Historical lineage is tracked via content digest and source locator.

3. **Machine-Checked Enforcement**:
   - `tools/uos timestamp-check` validates compliance across generated documents.
   - `engines/hermes/modules/hermes_dependability/dependability_clock.ml` enforces the `YYYYMMDD-HHSS` calendar projection.
   - Continuous integration and admission gates reject any commit adding un-prefixed generated documentation.

4. **Multi-Agent Alignment**:
   - All autonomous agents (AGY, Claude, Codex) must strictly observe this naming rule when generating task journals, evidence summaries, or audit artifacts.
