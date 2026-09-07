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
