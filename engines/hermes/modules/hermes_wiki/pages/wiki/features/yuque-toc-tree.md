---
id: hermes-yuque-toc-tree
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# 目录 Explicit TOC tree (Yuque)

#feature #src-yuque #area-structure #cov-gap

**Coverage**: ✗ gap — our navigation is derived from directories and corpus order; there is no authored tree

**Use cases**: Author the reading order and hierarchy independently of where files live.

**Look & feel (reference)**: A draggable tree in the base sidebar; nodes may be documents, links or headings.

**Navigation cues**: Drag to reorder; right-click to add a node.

**Hermes reading**: Converges with Sphinx's toctree (HW.6.8.1) but stores the tree as **data with per-node attributes**, which Sphinx does not. Strictly richer.
