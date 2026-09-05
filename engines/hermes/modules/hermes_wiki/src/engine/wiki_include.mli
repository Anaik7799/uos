(* HW.9.2.1 — `literalinclude`: a fenced block whose body is a SLICE OF A
   REAL FILE. The denotation IS the file, so a quoted snippet cannot
   drift from the code it quotes — the transclusion argument applied to
   source.

   PURE. The reader is INJECTED (`~read`), never called here, so the
   engine keeps its "build takes (path, content) pairs" contract and
   every law below is a unit test rather than a filesystem fixture.

   GRAMMAR, in the fence info string (HW.2.0.2 carries it verbatim):

     ```literalinclude PATH lines=3-7 start-after=MARK end-before=MARK dedent lang=ocaml emphasize=2,4

   Selectors compose: `lines` first, then the markers, then `dedent`.
   MARKERS ARE WHITESPACE-FREE TOKENS matched by SUBSTRING against a
   source line — a real limit, stated rather than hidden: a marker
   containing a space cannot be written in this grammar.

   An authored body is IGNORED: the file is the only source of truth. *)

type t = {
  path : string;
  lines : (int * int) option;   (* 1-based, inclusive *)
  start_after : string option;  (* exclusive of the matched line *)
  end_before : string option;   (* exclusive of the matched line *)
  dedent : bool;
  lang : string option;         (* explicit; else inferred from the extension *)
  emphasize : int list;         (* 1-based, relative to the SLICE *)
  bad : string list;            (* selectors that did not parse — [slice]
                                   REFUSES rather than widening *)
}

(* [None] unless the first info token is exactly "literalinclude" and a
   path follows. TOTAL: a malformed selector never raises — it is
   RECORDED in [bad] and refused by [slice], because ignoring it silently
   widened the window to the whole file. *)
val parse : string -> t option

(* Did the author ATTEMPT a directive? True whenever the first token is
   "literalinclude", including the forms [parse] rejects. A near-miss
   must be a named gap: falling through to the language branch renders
   the authored body — the stale hand-copy this feature abolishes. *)
val attempted : string -> bool

(* HW.2.6.6 — `emphasize=2,4` on ANY fence, not only an include. Sorted,
   deduped, positives only. TOTAL. *)
val emphasize_of_info : string -> int list

(* The language of an include: explicit `lang=` dominates; else inferred
   from the path extension; else None. *)
val lang_of : t -> string option

(* The slice, or a NAMED reason. An unmatched marker is an [Error] the
   caller must render visibly — never a silently empty block. *)
val slice : read:(string -> string option) -> t -> (string list, string) result

(* Common-prefix indent removal, over non-blank lines only. *)
val dedent_lines : string list -> string list
