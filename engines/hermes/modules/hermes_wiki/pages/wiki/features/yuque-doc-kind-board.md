---
id: hermes-yuque-doc-kind-board
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# 画板 Board (flowchart · architecture · mindmap) (Yuque)

#feature #src-yuque #area-kinds #cov-gap

**Coverage**: ✗ gap — Fork 1 covers server-side Mermaid/Graphviz (HW.7.5.1, HW.7.5.3); a freeform board is a deliberate non-goal (HW.7.6.1)

**Use cases**: Diagrams drawn rather than written.

**Look & feel (reference)**: Infinite canvas with shape palette and connectors.

**Navigation cues**: New → 画板.

**Hermes reading**: Splits cleanly for us: **generated** diagrams are wanted (they cannot drift from the model), **drawn** ones are not (they are not diffable).
