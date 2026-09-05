---
id: hermes-imported-html-algebra
status: published
type: reference
generated: false
migrated_from: zigvm/docs/design/HTML_ALGEBRA.md
---
# The algebra of HTML markup

The specification of record for the markup layer of `harness/doc_lint.ml`. It
is the sibling of `TABLE_ALGEBRA.md` and follows the same shape: ontology,
signature, semantic domain, oracle and final encodings, laws, verification
regime, scope limits. Every law is executable in `doc_lint_laws`
(`--verify-formal`, hence the canonical gate).

It exists for the same reason: the HTML rules were substring scans, and **bytes
are not markup**. A scan for `<html` counts the one inside a comment, inside a
`<script>`, and inside an attribute value. A scan that walks to the next `>` to
find a tag's end stops early on a `>` inside a quoted value. A scan for one
exact spelling of a remote script tag misses the extra-whitespace form, the
uppercase form, the single-quoted form and the protocol-relative one. None of
those is fixable by tuning the needles.

## 1 · Ontology

| Term | Definition | In code |
|---|---|---|
| **Document** | the byte string being linted | `doc.content` |
| **Token** | a doctype, start tag, end tag, comment, or run of text | `html_tok_kind` |
| **Span** | a token's byte offset and length; every byte belongs to exactly one | `h_off`, `h_len` |
| **Element name** | the ASCII-lowercased tag name | `HK_start (name, …)` |
| **Attribute** | a name and its value, with the quoting already resolved | `(string * string) list` |
| **Self-closing** | a start tag written `<x/>` | the `bool` in `HK_start` |
| **Void element** | an element with no content and no end tag (`br`, `img`, …) | `html_void` |
| **Optional-end element** | an element whose end tag the spec permits to be omitted (`p`, `li`, `tr`, …) | `html_optional_end` |
| **Raw-text element** | an element whose content is text, not markup (`script`, `style`, `textarea`, `title`) | `html_raw_text` |
| **Open set** | the stack of elements begun and not yet ended | (in `HTML-TAG-BALANCE`) |
| **Resource attribute** | an attribute that makes the page fetch something at render time | `html_resource_attr` |
| **Remote value** | a value beginning `http://`, `https://` or `//` | `html_remote_value` |
| **Provenance** | Authored or Generated — which standard applies | `doc.generated` |

## 2 · Signature

```text
  html_tokenize       : Document -> Token list
  html_tok_source     : Document -> Token -> string
  html_starts         : Token list -> (Token * name * attrs * self_closing) list
  html_remote_value   : string -> bool
  html_resource_attr  : name -> attr -> attrs -> bool
  css_remote_urls     : string -> bool
```

## 3 · Semantic domain

A **Document denotes its token sequence.** Every rule is a predicate over that
sequence rather than over bytes, which is what makes comments, raw text and
attribute values opaque by construction instead of by special-casing.

The **open set** denotes nesting: start tags push, end tags pop to their match.
An element left on the stack at end of input was never closed. This is why
counting cannot substitute — `<main>…</main><main>` and `<main><main>…</main>`
have identical counts and different meanings.

A **resource attribute with a remote value** denotes a network fetch at render
time. That is the archival property the journal contract needs, and it is not a
conformance question: a remote script is perfectly valid HTML, so no external
checker will ever report it.

## 4 · Oracle and final encoding

The oracle is **round-trip conservation**, not a twin implementation:

```text
  concat (map source (tokenize d)) = d          and spans are contiguous from 0
```

A second hand-written tokenizer would share its author's misconceptions about
HTML — the same wrong idea about where a quoted value ends would appear in
both, and they would agree while both being wrong. Byte-exact reconstruction
cannot fail that way, because the reference is the document itself. Any token
boundary error shows up immediately as a lost or duplicated byte.

Conservation is checked on every enumerated fragment sequence and every fuzzed
document, not only on curated examples.

## 5 · Laws

**Tokenizer:**

| Law | Statement |
|---|---|
| `HTML-CONSERVATION` | Token spans partition the document: reconstruction is byte-identical and spans are contiguous from offset 0. |
| `HTML-COMMENT-OPAQUE` | Markup inside a comment is not markup. |
| `HTML-RAWTEXT-OPAQUE` | A tag inside `script`/`style`/`textarea`/`title` is not markup. |
| `HTML-ATTR-VALUE-OPAQUE` | A `>` inside a quoted attribute value does not end the tag. |
| `HTML-FUZZ-TOTALITY` / `HTML-FUZZ-CONSERVATION` | No adversarial input raises or loses a byte. |

**Structure:**

| Law | Statement |
|---|---|
| `HTML-COUNTING-IS-NOT-BALANCE` | Two opens and two closes can still be unbalanced; the stack reports it and a counter cannot. |
| optional-end tolerance | Omitting a `p`/`li`/`tr` end tag is not a defect — every renderer closes it. |
| void tolerance | A void element and a self-closing tag never enter the open set. |

**Self-containment** — one law per spelling the needle list missed: extra
whitespace, uppercase, unquoted, protocol-relative, CSS `@import`, CSS
`@font-face`, plus the two negatives that matter (an `<a href>` to a website is
navigation and must not fire; a relative asset must not fire).

## 6 · Verification regime

| Method | What it does | Scale |
|---|---|---|
| **BDD** | Given/when/then per rule, positive and negative. | 30 scenarios |
| **Property** | Conservation, opacity, counting-is-not-balance. | 8 laws |
| **Ruliological** | Every sequence of markup fragments up to length 4 over an 11-symbol alphabet — chosen so tag, comment, raw text, quoted-value and bare-delimiter states all interact — checked for conservation and totality. | 16,000+ documents |
| **Probabilistic** | Generated valid pages must yield nothing (precision); a page with one injected defect of a randomly chosen kind must yield that defect (recall). | 400 trials |
| **Fuzz** | Adversarial markup-shaped bytes, checked for totality and conservation. | 600 documents |

**Mutants**: `MUT-LINT-14` (quoted attribute values disabled), `MUT-LINT-15`
(raw text disabled), `MUT-LINT-16` (end-tag-required predicate falsified) — all
killed. See `MUTATION_LOG.md`.

## 7 · The two-tier standard

Inherited unchanged from the table algebra: an authored page is held to what a
renderer does with it, and **every finding on a generated artifact is an
`Error`**, no ratchet, no exception. The tolerances above — omitted optional end
tags, self-closing syntax, unquoted attribute values — are exactly the
constructs browsers handle correctly, so they are acceptable in authored pages
and still strict when we emit them ourselves.

The tolerance stops at content loss. `HTML-TAG-BALANCE`,
`HTML-COMMENT-UNCLOSED` and `HTML-DATA-URI-INTACT` fire regardless of
provenance, because each one makes the page silently drop content that the
source still shows.

## 8 · Scope limits

Stated so this is never mistaken for a conformance checker or a parser:

- **A tokenizer, not a parser.** No tree, no insertion modes, no adoption
  agency, no foreign-content integration points, no implied tags beyond the
  optional-end tolerance. Misnesting (`<b><i></b></i>`) is reported as an
  unclosed element, which is what it costs in practice, not as a tree repair.
- **No entity resolution.** `&amp;` is text. Nothing here depends on decoded
  values.
- **No content model.** Whether a `<figcaption>` may sit in a `<div>` is the
  W3C Nu checker's job and is documented as such in `LINT_BENCHMARK.md`.
- **No CSS or JavaScript parsing.** `css_remote_urls` scans for `url(` and
  `@import` and nothing else; a remote URL assembled at runtime by script is
  not detectable and is not claimed.
- **Attribute names are compared ASCII-lowercased**, which matches HTML for
  ASCII names and is not claimed for anything else.
