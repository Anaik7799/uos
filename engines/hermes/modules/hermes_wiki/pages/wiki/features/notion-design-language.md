---
id: hermes-imported-notion-design-language
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/features/notion-design-language.md
status: published
last_verified: 2026-07-29
verified_by: agent
---
# Notion design language — look, feel, and navigation cues

The visual/interaction grammar that makes Notion feel like Notion (distilled
from the product surface for [[skills--wiki-design--skill]]), each cue mapped
to our wiki: adopted, diverged, or candidate. #feature-db #design

## Canvas & typography

- **Content-first white canvas**: near-zero chrome; UI appears on hover/need.
  *Ours: adopted — sidebar + content, no toolbars.*
- **One friendly sans** (~16px, 1.5+ line height), bold scaled headings, no
  decorative fonts. *Ours: adopted (system sans, 15.5px/1.68).*
- **Generous whitespace**, max-width column (~900px) for measure. *Adopted.*
- **Subtle grey ink hierarchy** (primary/muted/dim) instead of rules and
  borders. *Adopted — our --ink/--mu/--dim variables.*
- **Emoji as first-class iconography** (page icons, callouts, buttons).
  *Ours: partial — inline emoji yes; page icons deliberately not.*

## Interaction grammar

- **"/" is the universal creator** — every block type one keystroke away.
  *Ours: N/A (authoring is markdown; the analog is knowing the syntax — a
  syntax cheat-sheet on the authoring form is a candidate cue).*
- **Hover-reveal affordances**: ⋮⋮ drag handle + "+" appear only on hover;
  nothing is permanent chrome. *Ours: adopted in spirit (edit affordance on
  authored notes only).*
- **Everything draggable** (blocks, pages, columns). *N/A — structure is
  textual; git is the mover.*
- **Pills & chips for metadata** (selects, people, relations). *Adopted —
  status/type badges, tag chips, grounded/community chips, MoC state pills.*
- **Popovers over navigations**: pickers/menus appear in place, the page
  never leaves. *Partial — our details/expanders; no JS popovers by design.*
- **⌘K Quick Find as the spine of navigation**. *Candidate cue — we have the
  search page; a keyboard-summoned overlay would complete it.*
- **Breadcrumbs always visible**; sidebar = persistent structural spine,
  collapsible groups, current-page highlight. *Adopted (breadcrumb header,
  grouped sidebar with `cur` highlight).*
- **Toggles/disclosure everywhere** (toggle blocks, database groups).
  *Partial — details for neighborhood; toggle blocks a recorded gap.*
- **Inline editing in place** (tables, properties). *Diverged — read surface
  + explicit etag-guarded forms; honesty over immediacy.*

## Color & state

- Accent color reserved for INTERACTIVE/positive (links, verified badge);
  red only for destructive/defeated; property colors are muted pastels.
  *Adopted — --ac teal for links/fresh/in, red for invalid/out/frozen-warn.*
- **State is always visible**: verified badges, lock badges, sync outlines.
  *Adopted and extended — draft/published, verified_by, grounded ⚖, MoC
  fresh/stale/frozen, overdue-review highlight.*

## Navigation model (the cues users learn)

Sidebar tree → breadcrumb → in-page anchors; ⌘K to jump; backlinks to walk
backwards; database views as saved lenses. *Ours mirrors it: grouped sidebar →
breadcrumb → heading anchors; search page; contextual backlinks; queries-as-
notes as the saved lenses — plus cues Notion lacks: prev/next reading order,
the graph page, serendipity, and the footer utility row (anomalies · query ·
timeline · currency).*

Part of the [[Feature database — Notion & Obsidian coverage]].
