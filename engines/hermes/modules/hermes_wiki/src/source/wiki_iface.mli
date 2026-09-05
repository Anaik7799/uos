(* HW.9.1.2 — interface-comment extraction. The documented surface of an
   OCaml module, read from its `.mli` by STATIC PARSE, NEVER EVALUATION.

   THE LAW IS THE METHOD, not a performance note. Sphinx's autodoc
   IMPORTS the module to document it, which runs its top-level effects;
   this repository's build imports nothing (HW.9.1.1 is Excluded on
   exactly that ground). So the surface is recovered by reading text.
   The consequence is a real bound, stated rather than hidden: what is
   extracted is what the FILE says, not what the module means. A `val`
   produced by `include Foo` or a functor application is invisible here,
   because recovering it would require the compiler.

   PURE and TOTAL. The reader is injected; every malformed input yields a
   value, never an exception — this runs over author text.

   THE ENVELOPE, per the functional-envelope discipline. Each boundary is
   a law in the suite rather than a hope:
     nominal      a doc comment immediately above a `val`
     exhaustion   a file of many thousands of lines; deeply nested
                  comments; a comment larger than the rest of the file
     stuck        a `val` with no comment; a comment attached to nothing;
                  a file with no `val` at all
     anomaly      an unterminated comment; an opener inside a string literal;
                  a `val` inside a comment; CRLF; no trailing newline
   Nothing clamps to a wrong answer: an undocumented `val` is reported
   as undocumented, which is the fact HW.9.4.1's coverage census needs. *)

type item = {
  name : string;         (* the value's name, as written after `val` *)
  signature : string;    (* the type expression, whitespace-normalised *)
  doc : string;          (* the attached comment, "" when undocumented *)
  line : int;            (* 1-based line of the `val` — an address, so a
                            reader can go there *)
}

(* Every `val` a .mli declares, in SOURCE order (the authored order is
   the documented order). TOTAL over any input. *)
val items : string -> item list

(* A comment is ATTACHED to the `val` that follows it, allowing blank
   lines between. A comment followed by another comment attaches only
   the last one — the nearer text wins, which is how a reader reads. *)
val documented : item -> bool

(* HW.9.4.1's raw material: the undocumented names, in source order. On
   its own this is a FACT; the disclosure that turns it into a verdict
   belongs to that row. *)
val undocumented : string -> string list

(* Coverage as a fraction, for a census. [None] when the interface
   declares no values at all — 0/0 is not 100%, and reporting it as
   100% is how a coverage number learns to lie. *)
val coverage : string -> (int * int) option
