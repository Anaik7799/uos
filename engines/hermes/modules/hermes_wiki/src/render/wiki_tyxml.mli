(* Typed page generation with TyXML: views return elements, so markup
   that cannot be malformed replaces string concatenation. This is the
   WIKI_PIPELINE §5 representation choice — a document, not a string.

   [to_string] is the shim that lets the existing string-based exporter
   and its 33 tests keep working while views migrate one at a time. *)

type element = Html_types.flow5 Tyxml.Html.elt

val to_string : element -> string
val page_to_string : title:string -> element list -> string

(* The shared shell: header, nav, footer — the same chrome every page
   carries today, now typed. *)
val shell : title:string -> element list -> Tyxml.Html.doc

(* Building blocks, typed. Each mirrors a construct site_build.ml builds
   as a string today. *)
val kpi_card : value:string -> label:string -> element
val kpi_band : (string * string) list -> element
val card : href:string -> title:string -> subtitle:string -> element
val grid : element list -> element
val section : string -> element list -> element list
val table : headers:string list -> rows:string list list -> element

(* Escaping is by CONSTRUCTION here: text is a typed node, never spliced
   into markup. This function exists only to prove that in a test. *)
val text_node : string -> element
