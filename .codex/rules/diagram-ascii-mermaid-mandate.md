# Mandatory Diagram Source Rule (`SC-DIAGRAM-001`)

## Rule Specification

- **Contract ID**: `SC-DIAGRAM-001`
- **Specification ID**: `SPEC-DIAGRAM-ASCII-MERMAID-001`
- **Scope**: All documentation, journals, specifications, skills, and UI design artifacts across UOS fractal layers $L_0 \dots L_9$.
- **Enforcement**: Gate `G-DIAGRAM`, `tools/uos checklist`, and Tri-Sovereign Architecture Board.

## 1. Core Mandate

Per explicit operator directive, every newly authored or revised explanatory diagram MUST have **both editable ASCII and Mermaid source**:
1. **ASCII Source**: The human-readable fallback diagram, formatted in a fenced code block with identifier `text` or `ascii`.
2. **Mermaid Source**: The structured rendering source, formatted in a fenced code block with identifier `mermaid`.
3. **Semantic Parity**: Both ASCII and Mermaid sources MUST describe the exact same nodes, edges, labels, and hierarchical groupings.

## 2. Strict Prohibitions

1. Do NOT author explanatory diagrams solely as raster images (PNG, JPEG, WebP), SVG files, Graphviz/DOT files, presentation slides, or generated AI artwork.
2. Do NOT omit either the ASCII or the Mermaid representation in any explanatory diagram.
3. Screenshots, screen recordings/videos, and scientific measurement plots are observed test evidence, NOT explanatory diagrams, and MUST retain full provenance metadata.

## 3. Preservation of Historical Evidence

Historical originals from external trees (`/home/an/dev/ver/c3i`, `/home/an/dev/ver/zigvm`, `/home/an/dev/ver/harness-bionic`) are read-only evidence. Preserve historical files byte-for-byte; record nonconformance in typed namespaces without rewriting original external artifacts.

## 4. Machine enforcement (corrected 2026-09-13)

`G-DIAGRAM` is now implemented, at
`engines/hermes/modules/hermes_toolchain/diagram_check.ml` (pure core
`diagram_parity.ml`, 33 laws, 3 killed mutants). Before this date the gate was
named as enforcement in all four rule mirrors and **implemented nowhere**, while
`tools/journal_linter.ml` accepted a Markdown table as an ASCII diagram and
printed "dual diagram source parity verified".

Verdicts are five-valued and only `PASS` asserts verification: `FAIL` (no ASCII
source, a table standing in for one, or differing edge sets), `UNVERIFIED`
(box-art ASCII, or arrow lists with non-overlapping node vocabularies), `PASS`
(edge sets compared and equal).

Measured 2026-09-13 over 1,135 files: 2 verified, 338 UNVERIFIED, 129 FAILED,
666 carrying no mermaid block. The semantic parity requirement in §1.3 is
**not mechanically checkable for box-art ASCII**; see §7.3 of
`contracts/rules/20260912-0745-sc-journal-v3-anticipatory-contract.md` for the
three options and the open sovereign decision.

Run: `bash tools/diagram-check`
