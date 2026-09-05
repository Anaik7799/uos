(* HW.3.5.1 — note transclusion: `![[Target]]` embeds a note's body where
   it is written, so a definition stated once appears everywhere it is
   needed and updates everywhere at once. In an evidence corpus a
   duplicated statement that has diverged is worse than no statement,
   because both copies look authoritative.

   THE LAW: THE EMBED DENOTES ITS SOURCE. The expansion is the target's
   bytes, so drift between an embed and its source is unrepresentable —
   the same argument literalinclude makes for code, made here for prose.

   EXPANSION HAPPENS AT BUILD, NOT AT RENDER, and that is a design choice
   worth stating. The renderers do not hold the corpus, so a render-time
   embed would need a second lookup path and the two renderers could
   disagree. Expanding text-to-text before either renderer sees it makes
   byte-equality FREE rather than something to test for.

   TERMINATION IS BY CONSTRUCTION. A target already on the current
   expansion path is not expanded again: the cycle is broken where it
   closes, and reported. Depth is additionally bounded, and the bound is
   REPORTED rather than silently applied — a truncated document that
   looks complete is the failure mode this feature could otherwise
   introduce (HW.3.5.3 owns the full depth discipline).

   A FAILED EMBED IS LOUD. An unresolvable target renders as a visible
   marker and is reported, never as an empty gap: silence would make a
   missing definition indistinguishable from a definition that says
   nothing. *)

type outcome = {
  text : string;             (* the expanded body *)
  embedded : string list;    (* target slugs actually expanded, sorted *)
  cycles : string list;      (* one line per cycle broken, sorted *)
  missing : string list;     (* one line per unresolvable target, sorted *)
  truncated : string list;   (* one line per expansion stopped by the depth bound *)
}

(* Default depth bound. Beyond this the embed is REPORTED and left
   unexpanded rather than followed. *)
val default_depth : int

(* [expand ~lookup ~self raw] replaces every `![[Target]]` in [raw].
   [lookup] maps a written target to (slug, body); [self] is the slug of
   the document being expanded, so a page embedding itself is a cycle at
   depth zero. TOTAL over author text. *)
val expand :
  ?depth:int -> lookup:(string -> (string * string) option) -> self:string -> string -> outcome

(* Whether a body contains any embed at all — cheap enough to skip the
   whole machinery for the overwhelming majority of documents. *)
val has_embed : string -> bool

(* HW.3.5.2 — BLOCK transclusion: `![[Note#^id]]` quotes ONE claim rather
   than its whole page. That distinction is the feature: embedding a
   page to cite a sentence drags in everything around it, and a reader
   cannot tell which part was meant.

   [block ~id body] is the paragraph or list item carrying `^id`, with
   the marker removed — the id addresses the block, it is not part of
   what the block says. [None] when the page declares no such id, which
   the caller must report rather than silently widening to the whole
   page: a citation that quietly quotes more than it claimed is worse
   than one that fails. *)
val block : id:string -> string -> string option
