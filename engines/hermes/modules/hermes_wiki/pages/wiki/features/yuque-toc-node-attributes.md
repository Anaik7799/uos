---
id: hermes-yuque-toc-node-attributes
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# TOC node attributes (editNode · url · open_window · visible) (Yuque)

#feature #src-yuque #area-structure #cov-gap

**Coverage**: ✗ gap — absent; we have no TOC data model at all

**Use cases**: Let one tree node be a document, an external link, or a hidden structural placeholder.

**Look & feel (reference)**: A node can point outside the base and open in a new window; `visible` hides it from the sidebar while keeping it in the tree.

**Navigation cues**: TOC editor per node.

**Hermes reading**: `visible` is Sphinx's `:hidden:` and `:orphan:` in one field, and `url` makes the tree able to hold non-documents. Worth taking wholesale if HW.6.8.1 is built.
