---
name: tyxml-conversion
description: Convert a hand-rolled HTML generator to typed TyXML markup — the recipe, the probed API details, the seven traps that cost real time, and the ratchet that makes progress a checkable claim
---

# Converting an HTML generator to TyXML

The goal is not tidiness. It is that **malformed markup becomes
unconstructible and escaping stops being a call anyone can forget.** A
converted module that still needs an escaper has not moved the guarantee.

Progress is measured, not asserted: `LAW HTML-GENERATOR-RATCHET`
(`typed_html_laws` in `harness/zigvm_harness.ml`) counts raw markup sites
across every generator, prints a per-module breakdown on each
`--verify-formal`, and **may fall, never rise**. Each conversion must move the
ceiling down by its own count, or the claim is not true.

## The recipe

1. **Survey before converting.** `grep -c '"<' <file>` per module, and read
   enough to see whether the sites are *page furniture* or a *streaming
   parser* (see "When NOT to convert").
2. Add `tyxml` to the module's library in `harness/dune`.
3. `module H = Tyxml.Html` (+ `module S = Tyxml.Svg` if there is SVG). In files
   that already use `S`/`H`, alias as `Th`/`Ts` instead.
4. Build the page as a **value**, render once at the end:
   `Format.asprintf "%a" (H.pp ()) doc` (or `H.pp_elt ()` for a fragment).
5. **Delete the module's escaper.** If `esc`/`html_escape`/`e` still has
   callers, the conversion is incomplete. Its absence is the evidence.
6. Write **laws** for the rendered output (see below), then **≥2 mutants**.
7. Drop the ratchet ceiling to the new measured total. Gate, commit, record.

## The seven traps (each cost real time)

1. **`H.style [H.txt css]` ESCAPES its content.** A child selector `.bar>span`
   emits as `.bar&gt;span` and the rule silently stops matching — the page
   still renders and still passes a link check. Use `H.Unsafe.data css` for
   static stylesheets (a compile-time constant, never data) and write a
   `CSS-VERBATIM` law so nobody "tidies" it back.
2. **`S.g [] [children]` is two positional lists** — `?a` is optional, so
   write `S.g [children]`. Same for any `star` element.
3. **`Unsafe.string_attrib` escapes its VALUE**, byte-identically to a typed
   attribute; it only bypasses attribute-NAME modelling. There is no way to
   emit a raw attribute value in TyXML at all. A mutant swapping one for the
   other is EQUIVALENT — the realistic regression is a return to string
   concatenation, so mutate *that* instead.
4. **A line-range splice that omits the tail silently deletes code.** Splice
   against `wc -l`, not against the region you are thinking about.
5. **TyXML emits `xmlns="http://www.w3.org/1999/xhtml"`** on `<html>`. Inert,
   but it trips any law phrased as "no `https?://` anywhere". Phrase
   self-containment as *no RESOURCE reference resolves off-host*, which is what
   the project's `HTML-SELF-CONTAINED` lint rule actually enforces.
6. **A mutant that fails to build, or a `sed` that fails to match, prints
   nothing** — which a FAIL-only grep reads as SURVIVED. Check for a PASS
   count, not an absence of failures. This has bitten four times.
7. **Warning-as-error on unused bindings**: deleting the escaper's last caller
   turns the escaper into an error inside a function, and a `(** … *)` after a
   `type` line trips warning 50.

## Laws to write for every converted generator

**Put the laws in a LIBRARY module, never in the `test_*.ml` itself.** This is
the single most important instruction on this page, and an earlier version of
it was wrong. `harness/dune` declares no `(test …)` stanza and no `runtest`
alias, and the gate never execs a test binary — its formal stage calls law
functions that live in libraries. A law suite written inside an
`(executable …)` therefore runs only when a human types its name, which for a
regression guard means it does not run. Two suites sat in exactly that state
until a mutant that should have died survived a full gate.

The shape: a module `X_laws.ml` inside the library that already holds the
generator, exposing `run : unit -> (string * bool) list` — returning verdicts
rather than printing or exiting, so each caller decides what a failure means.
Then TWO callers: the `test_*.exe` driver for the dev loop, and the gate's
`typed_html_laws` registry. Copy from `harness/wiki_render_laws.ml` and
`harness/slo_render_laws.ml`; the drivers show the thin shape.

Register the suite in the `Render_suite` variant in `typed_html_laws`. The
match is exhaustive, so a constructor nobody dispatches is a compile error —
that is the mechanism, not the discipline.

The laws themselves:

| Law | What it pins |
|---|---|
| `ESCAPING` | a hostile payload never appears VERBATIM in the output |
| `GUARD NON-VACUOUS` | the hostile fields are RENDERED, not dropped |
| `CSS-VERBATIM` | static CSS survives unescaped (trap 1) |
| `SELF-CONTAINED` | no `src`/`href` resolves off-host (trap 5) |
| `WELL-FORMED` | standards-mode doctype and a closed document |
| `STRUCTURE` | every section a reader depends on is present |

**State the law so it cannot pass vacuously.** Three attempts at one escaping
law passed while a mutant injected: a disjunction satisfied by any `&quot;` on
the page, then an attribute reader returning `""` when the value began with a
quote. The version that works needs no parsing — *if the payload appears
verbatim, it was not escaped*. Each failed version was cleverer than
necessary, and the cleverness is where the vacuity hid.

**Make the fixture hostile in EVERY operator-supplied field.** A sample whose
comment claims that while five fields hold benign placeholders lets a real
mutant survive.

## When NOT to convert

- **A streaming parser.** `docs_wiki.ml`'s markdown renderer keeps `in_ul`,
  `in_ol`, `in_bq`, `in_tbl` because it opens a tag on one line and closes it
  many lines later. TyXML wants a tree; converting means restructuring the
  parser to build one. That is a redesign, not a call-site swap — do it as its
  own slice with its own laws, or leave it and say so.
- **A JS-runtime host shell.** `/vega`, `/vegalite`, `/grid` are `<script>`
  bodies with generated JSON interpolated into JavaScript. TyXML types the
  shell and does NOTHING for JSON-into-JS, which is a different escaping
  problem with a different fix. Converting moves the ratchet without moving
  the risk — say that rather than banking the number.

## Seams, and how to retire them

A converted page that must embed an unconverted fragment uses
`Unsafe.data`. **Name every such seam in the source.** In `docs_wiki.ml` the
typed entry point `page_frame_elts` takes ELEMENTS, so a converted caller has
no seam at all, while the string-taking `page_frame` remains for the rest; the
string version dies when its last caller converts. Put the migration in the
TYPES, not in a comment that has to be kept true.

## Remaining work (live count in the gate output)

Run `--verify-formal` and read the `raw-HTML generator:` lines. As of the last
recorded cycle: `docs_wiki.ml` 206 (≈167 furniture + 39 streaming parser),
`zigvm_harness.ml` 108, `agent_workers.ml` 26, plus seven smaller modules.
Take the largest FURNITURE cluster first; the counts are printed sorted.
