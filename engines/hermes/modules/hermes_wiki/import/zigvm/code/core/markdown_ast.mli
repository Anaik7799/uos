(** markdown_ast — the wiki's markdown as a typed AST, and TyXML as its renderer.

    This interface is the module's CONTRACT. It exists because the contract used
    to live only in a doc-comment, and prose cannot be executed. The [(*@ ... *)]
    blocks below are GOSPEL specifications: they are type-checked against these
    signatures, so a specification cannot silently drift from the value it
    describes, and `ortac` can compile them into runtime assertions and a
    generated qcheck-stm suite.

    ORACLE vs FINAL. The ORACLE is the old streaming renderer in [Docs_wiki],
    which has produced every page of this wiki for the programme's whole life;
    its behaviour, quirks included, IS the specification. This module is the
    FINAL encoding, admitted ONLY by observational equivalence to that oracle
    over the entire real corpus plus seeded fuzz. Nothing in this interface may
    be read as a licence to "fix" the oracle: a divergence is a defect in this
    module until a quirk-list amendment says otherwise.

    THE FIVE PINNED QUIRKS, restated here because they are contract, not
    trivia. Each is deliberate and each is pinned by a named BDD scenario:
    - [\[TOC\]] scans every line matching a heading prefix, INCLUDING lines
      inside a code fence, and lists them.
    - a table separator row does not itself open a table, so a separator
      directly after a list item leaves the list open.
    - five hashes is not a heading; it falls through to a paragraph.
    - a blockquote run joins its lines with a trailing space per line.
    - an ordered-list line needs a digit, then '.', then a space, so
      "10 items" is a paragraph.

    SCOPE. Parse and render only; no IO. Link resolution arrives as a [resolve]
    function, and the outlink/tag/typed-edge side effects the old renderer wrote
    into globals are returned as DATA ([refs]) instead. *)

(** {1 Carrier} *)

type inline =
  | Text of string
  | Code of string
  | Strong of inline list
  | Em of inline list
  | Link of { href : string; body : inline list }
      (** a link's visible text is an inline LIST, not a string: it can carry
          emphasis, and a string field would flatten it back to plain text *)
  | Wiki of { target : string; anchor : string; display : inline list; rel : string }
  | Wiki_missing of { target : string; display : inline list }
  | Tag of string

type cell = { c_body : inline list }
type row = { r_cells : cell list; r_head : bool }

type block =
  | Heading of { level : int; id : string; body : inline list }
  | Para of { id : string option; body : inline list }
  | Hr
  | Code_block of { info : string; body : string }
      (** the fence INFO STRING is carried RAW, not pre-split: the parser
          commits to no interpretation, so a future meta reader (line
          highlight, title) needs no carrier change *)
  | Ul of item list
  | Ol of inline list list
  | Blockquote of { callout : (string * string) option; body : inline list }
  | Table of row list
  | Toc of (int * string * inline list) list

and item = { i_body : inline list; i_todo : bool option }

type t = block list
(** A document. NOTE the structural ceiling: no block constructor contains a
    [block], so this carrier is [List (Block (List Inline))] — a polynomial
    functor applied once, depth exactly 2 — and [render] is therefore a
    two-level walk rather than a catamorphism. That single fact is why nested
    lists flatten and why collapsible blocks and tabs are unrepresentable. *)

type refs = { outlinks : string list; tags : string list; typed : (string * string) list }
(** The side data the old renderer accumulated in global refs, returned as a
    value instead. *)

val empty_refs : refs
(*@ ensures empty_refs.outlinks = [] /\ empty_refs.tags = [] /\ empty_refs.typed = [] *)

(** {1 Anchors} *)

val znorm : string -> string
(** The anchor scheme: lowercase, every non-alphanumeric run becomes one '-',
    trailing '-' dropped.

    THIS FUNCTION IS PURE, AND THAT IS A KNOWN LIMITATION, not an oversight: it
    cannot disambiguate two headings with the same text, which is why the corpus
    carries anchor collisions. Making it collision-free requires threading state
    and is a deliberate quirk-list amendment, because it changes published
    output. *)
(*@ r = znorm s
    pure *)

(** {1 Parsing} *)

val lang_of_info : string -> string option
(** The LANGUAGE of a fence info string: its first whitespace-delimited token,
    admitted only if it matches [A-Za-z0-9_+-]+, lowercased.

    The validation is a WELL-FORMEDNESS control, NOT a security one: TyXML
    escapes attribute values, so an unvalidated token is not an injection seam —
    it would merely put spaces and punctuation into a class attribute, producing
    markup that is valid but meaningless. A rejected token degrades to exactly
    the info-less rendering, never to broken markup. *)
(*@ r = lang_of_info info
    pure *)

val parse : string -> t
(** [parse md] with no link resolution. Total: every input yields a document,
    because a hang or an exception on corpus text would be a gate failure. *)
(*@ doc = parse md
    pure *)

val parse_with_resolve : resolve:(string -> string option) -> string -> t
(** [parse_with_resolve ~resolve md]. [resolve] maps a wikilink target to its
    resolved href, returning [None] for an unresolvable target — which becomes
    [Wiki_missing], never a silently dropped link. *)

val refs_of : t -> refs
(** Extract outlinks, tags and typed edges from an already-parsed document. *)
(*@ r = refs_of doc
    pure *)

val of_markdown : resolve:(string -> string option) -> string -> t * refs
(** Parse and extract references in one pass. *)

(** {1 Rendering} *)

val render_string : resolve:(string -> string option) -> t -> string
(** Render a document to HTML text through TyXML.

    TyXML enforces the HTML content model AT COMPILE TIME, which is the whole
    reason this module exists: the renderer cannot emit anchor-in-anchor or any
    other content-model violation, because such markup does not typecheck. The
    output is therefore well-formed by construction, not by validation. *)
