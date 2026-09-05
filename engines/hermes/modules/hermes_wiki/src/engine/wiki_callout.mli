(* HW.2.3.1 — callouts / admonitions, in the Obsidian `> [!type]` form.

   THE DIALECT DECISION (plan section 8.2, adopted). Two vendor dialects
   exist and one had to be chosen. Obsidian's wins on three grounds: it
   DEGRADES to a plain blockquote in any conforming renderer, so an
   un-rendered callout is still readable; it is a blockquote prefix, so
   it composes with the parser we already have instead of adding a fence
   class; and the imported corpus already writes it.

   THE VOCABULARY IS CLOSED, AND AN UNKNOWN TYPE IS PRESERVED, NEVER
   COERCED. Thirteen types with aliases, matched case-insensitively. An
   unrecognised type keeps its text and is reported as an anomaly —
   exactly the discipline the discourse vocabulary uses, and for the same
   reason: silently rewriting `[!warnign]` to `note` would turn an
   author's typo into a warning nobody sees.

   ARBITRARY BLOCK CONTENT is the point, and the reason this row waited
   on the recursive carrier (HW.2.0.1): a callout body may hold lists,
   code fences and nested callouts.

   BOTH RENDERERS SHARE THIS EMITTER. The AST path and the line machine
   each detect the header and delegate here, so their bytes cannot
   diverge — the same discipline as the fence emitter. *)

type kind =
  | Note | Abstract | Info | Todo | Tip | Success | Question
  | Warning | Failure | Danger | Bug | Example | Quote
  | Unknown of string  (* preserved verbatim, reported, never coerced *)

type fold =
  | Plain      (* no suffix: not foldable *)
  | Expanded   (* `+`: <details open> *)
  | Collapsed  (* `-`: <details> *)

type header = { kind : kind; title : string; fold : fold }

(* The canonical type for a written name, case-insensitively, resolving
   aliases (`tldr` -> abstract, `hint` -> tip, `error` -> danger, …). An
   unrecognised name becomes [Unknown] carrying the original text. *)
val kind_of_string : string -> kind

(* The canonical lowercase name, used for the CSS class. [Unknown] keeps
   the author's spelling so the page shows what was written. *)
val kind_name : kind -> string

(* [Some header] iff the line is a callout header: `[!type]`, optionally
   `+`/`-`, optionally followed by a title. The `>` prefix must already
   be stripped. TOTAL — this runs over author text. *)
val parse_header : string -> header option

(* The rendered callout. [body] is already-rendered HTML for the block
   content, so this function never parses markdown — one emitter, one
   set of bytes, both renderers. *)
val html : escape:(string -> string) -> inline:(string -> string) -> header -> body:string -> string
