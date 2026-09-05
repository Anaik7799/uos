(* HW.2.0.1 — the recursive block carrier. See wiki_ast.ml for the
   ontology, the oracle/final discipline, and the preserved quirks.

   Law (plan §8.0.2): the carrier admits a block inside a block, so
   `render` is a catamorphism rather than a two-level walk; and the FINAL
   encoding is admitted only by observational equivalence to the streaming
   oracle over the whole corpus. *)

type block =
  | Inline_run of string
      (* raw inline source rendered with NO wrapping tag — a list item or
         blockquote body. Distinct from [Para]: <li>x</li> and <p>x</p>
         are different bytes. *)
  | Para of string
  | Heading of { level : int; text : string }
  | Rule
  | Fence of { info : string; body : string list }
      (* HW.2.0.2: info (lang + meta) verbatim; lang_of_info interprets *)
  | List_block of { ordered : bool; start : int; content : list_content list }
  | Table of row list
  | Quote of block list
  | Callout of { header : Wiki_callout.header; body : block list }

and list_content =
  | Item of item
  | Loose of block

and item = { task : bool option; body : block list }
and row = { header : bool; cells : string list }

type t = block list

val parse : string -> t

(* HW.2.0.2 — every fence of a document as (info, body), source order,
   info VERBATIM: `parse o print = id` on the info string. *)
val fences : t -> (string * string list) list

val fence_infos : t -> string list

(* The LANGUAGE of a fence info string: its first whitespace-delimited
   token, admitted only if [A-Za-z0-9_+-]+, lowercased (mirror:
   markdown_ast.lang_of_info). A rejected token degrades to exactly the
   info-less rendering, never a broken class. TOTAL. *)
val lang_of_info : string -> string option

(* The opener line's text after the backticks, trimmed — "" when bare.
   Exported so the line machine reads the SAME grammar. *)
val fence_info_of_line : string -> string

(* [inline] renders a raw inline run, [anchor] is the document's stateful
   heading slugger, [escape] escapes a fence line. Supplied by the caller
   so this module needs neither the link resolver nor the corpus. *)
(* ONE fence emitter for BOTH renderers: language class, `<mark>` on the
   1-based emphasized lines (HW.2.6.6), body escaped. *)
val fence_html :
  escape:(string -> string) -> ?lang:string -> ?emphasize:int list -> string list -> string

(* HW.9.2.1 — an include's slice, or a VISIBLE failure carrying its
   reason. Never an empty block. *)
val include_html :
  escape:(string -> string) ->
  resolve:(Wiki_include.t -> (string list, string) result) ->
  Wiki_include.t ->
  string

(* [resolve_include] supplies HW.9.2.1's slices; its default resolves
   NOTHING, so an un-injected include fails closed and says so.
   [default_lang] is HW.2.6.7 — a fence's own language dominates it. *)
val render :
  ?resolve_include:(Wiki_include.t -> (string list, string) result) ->
  ?default_lang:string ->
  inline:(string -> string) ->
  anchor:(string -> string) ->
  escape:(string -> string) ->
  t ->
  string

(* Nesting depth of the block tree: 1 for a flat document. The observation
   that distinguishes this carrier from the depth-2 one it replaces — a
   document with a block inside a block reports 2 or more. *)
val depth : t -> int

(* HW.3.3.1 — the block-anchor marker: a trailing " ^id" on a paragraph or
   tight list item, alphabet [A-Za-z0-9-] (narrower than Slug), id kept
   WITH the ^ so the namespace is disjoint from heading anchors by
   construction. Returns the text without the marker and the id, or the
   line untouched. Both renderers use THIS function — equality by
   construction, not by luck. *)
val block_anchor_split : string -> string * string option
