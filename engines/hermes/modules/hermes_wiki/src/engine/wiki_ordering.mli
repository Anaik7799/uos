(* HW.1.3.10–14 — the five frontmatter fields that decide how a corpus is
   ORDERED and LABELLED. They belong together because they are one
   question asked five ways: given a set of sibling documents, what order
   does a reader meet them in, and what are they called on the way?

   HW.1.3.11 `sidebar_position` — a TOTAL ORDER on siblings. Total is the
     word that matters: a partial order leaves ties broken by filesystem
     accident, which is the very thing the declared tree (HW.6.8.1)
     exists to remove. Documents without a position sort AFTER those with
     one, then by slug — deterministic, and never interleaved with the
     authored sequence.
   HW.1.3.12 `parse_number_prefixes` — the ALTERNATIVE ordering rule: a
     leading `03-` in a filename is a position and is stripped from the
     label. Explicit `sidebar_position` DOMINATES it, because one
     mechanism must win when both are present or ordering is a coin toss.
   HW.1.3.13 `sidebar_label` — label ?? title. A fallback, not an
     override: an absent label is not an empty label.
   HW.1.3.10 `keywords` — search-boost terms, which are ADDITIVE to the
     body's own terms and never a replacement, so declaring a keyword
     cannot hide a document from a search for its actual words.
   HW.1.3.14 pagination — next/prev over the ordered sequence, MUTUALLY
     INVERSE and ACYCLIC: next(a) = b iff prev(b) = a, and the ends are
     None rather than wrapping. A wrapping sequence has no last page, so
     a reader can never finish. *)

type entry = {
  slug : string;
  position : int option;   (* explicit, else derived from a number prefix *)
  label : string;          (* sidebar_label ?? title *)
  keywords : string list;  (* additive search terms *)
}

(* The number prefix rule: `03-the-gate` -> (Some 3, "the-gate"). Returns
   [(None, s)] unchanged when there is no prefix, so it is safe to apply
   to every slug. TOTAL.

   An ordinal is a SEQUENCE NUMBER and therefore short: at most
   [max_prefix_digits]. A longer leading run is a DATE or an identifier
   (`2026-08-09-notes`), and reading one as a position silently reorders
   a directory and collides every document sharing the year. Explicit
   `sidebar_position` carries no such bound. *)
val max_prefix_digits : int
val number_prefix : string -> int option * string

(* One entry per page, in the TOTAL order described above. *)
val ordered : Hermes_wiki.model -> entry list

(* Pagination over [ordered]. [None] at each end — the sequence does not
   wrap, because a wrapping sequence has no last page. *)
val next : entry list -> string -> string option
val prev : entry list -> string -> string option

(* Positions declared twice among siblings — a tie the author must break,
   reported rather than resolved by slug behind their back. *)
val position_conflicts : Hermes_wiki.model -> string list

(* HW.6.4.4 — pagination as a SURFACE. The functions above compute the
   relation; this renders it, and the two must not be allowed to drift:
   [nav_html] is defined over [next]/[prev] alone, so a rendered link
   that disagreed with the relation would be unrepresentable.

   At an end the nav emits NOTHING for that side — not a disabled
   control, not a link to the current page. A greyed-out "next" on the
   last page tells a reader there is more and there is not; an absent
   one tells them they have finished, which is true.

   Every href is the target's own URL, so a nav link resolves exactly
   when the page it names exists. The label is the entry's [label]
   (HW.1.3.13), so a page reached from the nav is called what the sidebar
   calls it — a reader following a link should land on the name they
   clicked. Text is escaped: a title carrying markup must not become
   markup here. *)
val nav_html : entry list -> string -> string

(* The slugs [nav_html] linked to, in emitted order — the observation
   that lets a test check the rendered nav against the relation rather
   than against itself. Empty at both ends of a one-page sequence. *)
val nav_targets : entry list -> string -> string list
