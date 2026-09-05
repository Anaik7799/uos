---
name: docs-design
description: Use when authoring or rendering documentation pages (guides, references, the docs/ tree, journals) — GitBook-style docs design. Covers grouped left-nav sections, right-side on-this-page TOC, prev/next paging, readable typography, and the rule that every doc page is 2-way navigable.
---

# Docs design — GitBook as the reference

Documentation is **read linearly and searched non-linearly**, so it needs both a
reading path and a map. The reference model is GitBook: a grouped left sidebar, an
"on this page" table of contents, bottom prev/next paging, and clean, dense-but-
readable typography. Apply this to `docs/*.md`, the journals, and any docs
renderer (`harness/docs_wiki.ml`).

## The non-negotiable: 2-way navigability

**Every doc page has a forward path and a way back.** GitBook does this with:

1. a **grouped left sidebar** (sections → pages), current page highlighted —
   the non-linear map (any → any);
2. **prev / next** controls at the bottom — the linear reading path (page ↔ page);
3. **breadcrumbs** at the top linking upward to the section and index;
4. an **on-this-page TOC** (the H2/H3 outline) for long pages — intra-page nav.

If a reader can enter a page but not continue or return, the docs are broken.

## GitBook principles to apply

- **Sections are the spine.** Group pages into named sections (mirror the
  `docs/<subdir>/` structure); order within a section is the reading order that
  drives prev/next.
- **Readable measure + type scale.** ~65–75ch line length, a clear H1→H4 scale,
  real hierarchy. Body prose in a comfortable sans; code in mono.
- **Code blocks are first-class.** Fenced blocks with a distinct ground, inline
  `code` for identifiers, horizontal scroll (never wrap) for wide lines.
- **Tables for reference, prose for concepts.** Use tables for option/field/verdict
  matrices; keep conceptual explanation in short paragraphs and callouts.
- **Blockquotes as callouts.** A `>` block is a note/warning — visually distinct,
  used sparingly for the thing the reader must not miss.
- **Escape everything.** A docs renderer must HTML-escape all source text and
  never let a `<`/`&` in prose or a fenced block inject markup (totality +
  injection-safety is a law in `docs_wiki.ml`).
- **Stable slugs + deep links.** A page's URL is `docs/<slug>`; keep slugs stable
  so links don't rot. Every heading should be linkable.
- **What you generate is held to the strict standard.** Output from a generator
  carries Generated provenance, and every lint finding on a generated artifact
  is an `Error` — no ratchet, no exception (`docs/design/HTML_ALGEBRA.md` §7).
  A renderer must therefore emit a leading doctype, a `lang`, a `title`, closed
  elements, terminated comments, no duplicated attribute, no remote runtime
  asset, and no whitespace inside a `data:` URI. A defect a browser absorbs is
  still a bug in the generator, because it reproduces across every page it
  emits. Tables the renderer emits need a delimiter row of the same arity as
  the header (`docs/design/TABLE_ALGEBRA.md`).

## In this repo

- `harness/docs_wiki.ml` renders every tracked `docs/*.md` (guides + journals) to
  HTML with the grouped sidebar, breadcrumb, and prev/next — a pure Model → View
  generator with a `selftest` law (headers/lists/tables/blockquote/code all emit
  their tags; raw `<` is escaped; an unclosed fence still renders).
- Serve live at `/docs`; write the static site with `--docs-wiki DIR`.
- Journals count as docs — they are rendered and navigable like any other page,
  fully integrated with the wiki (`/docs ↔ /wiki`).

## Checklist before shipping a doc page

- [ ] in the correct sidebar section, highlighted when current
- [ ] breadcrumb + prev/next present (2-way nav); long pages have a TOC
- [ ] code fenced + escaped; identifiers in inline code; wide content scrolls
- [ ] reference data in tables, concepts in short prose + callouts
- [ ] stable slug; cross-references are real links; no dead ends
