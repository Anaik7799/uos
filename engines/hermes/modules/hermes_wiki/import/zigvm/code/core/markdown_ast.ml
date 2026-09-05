(* markdown_ast — the wiki's markdown as a typed AST, and TyXML as its renderer.

   WHY THIS EXISTS. `Docs_wiki.render_markdown` is a streaming state machine: it
   walks lines carrying `in_ul`/`in_ol`/`in_bq`/`in_tbl`, opens a tag on one line
   and closes it many lines later, and every construct is string rewriting over
   already-escaped text. That shape cannot be converted to typed markup by
   swapping call sites — TyXML needs a tree — and it is where the last 39 raw
   markup sites of the programme live. So the parser is split from the renderer:

     parse  : string -> t          (bytes to a typed document)
     render : t -> Tyxml elements  (a document to markup that cannot be malformed)

   Ontology
     Carrier      `t` — a block list; blocks carry inline lists.
     Denotation   the rendered document.
     Operations   `parse`, `render`, `render_string`.
     Observations the rendered markup, compared to the oracle's.

   ORACLE vs FINAL. The ORACLE is the old streaming renderer, which has produced
   every page of this wiki for the programme's whole life; its behaviour, quirks
   included, is the specification. This is the FINAL encoding, admitted ONLY by
   observational equivalence to the oracle over the entire real corpus plus
   seeded fuzz (`markdown_ast_laws.ml`, and the corpus differential in the gate).
   The old implementation therefore STAYS — not as dead code, but as the
   permanently-exercised oracle. Deleting it would delete the specification.

   QUIRKS DELIBERATELY PRESERVED, because equivalence is the bar and a "fix"
   here would be a silent behaviour change on 1,600 published documents:
     - `[TOC]` scans every line matching a heading prefix, INCLUDING lines
       inside a code fence. It lists them.
     - a table separator row (`|---|`) does not itself open a table, so a
       separator directly after a list item leaves the list open.
     - `#####` (five hashes) is not a heading; it falls through to a paragraph.
     - a blockquote run joins its lines with a trailing space per line.
     - an ordered-list line needs a digit, then `.`, then a space; `10 items`
       is a paragraph.
   Each is pinned by a named BDD scenario, so a future change to any of them is
   a deliberate act with a failing law rather than an accident.

   AMENDED — the pure slugger. A sixth quirk used to sit in that list: heading
   anchors were computed by the pure `znorm`, so two identical headings received
   the SAME anchor and the second was unreachable by link (10 such collisions
   across 3 corpus documents). It was amended deliberately, by the
   `SCENARIO AMEND-SLUG-*` family in `markdown_ast_laws.ml`, which was written
   FAILING before the change landed.

   The amendment is narrow on purpose, because the three anchor sites are not
   interchangeable:
     - HEADING DECLARATIONS are disambiguated through `Slugger`.
     - WIKILINK FRAGMENTS (`[[Doc#Section]]`) still use `znorm`: they reference
       an anchor another document declared, computed without seeing it, so a
       suffix drawn from THIS document's history would point at nothing.
     - THE `[TOC]` SCAN still uses `znorm`, because its own quirk above means it
       matches heading prefixes inside code fences too — its sequence is not the
       heading sequence, and a shared counter would drift out of step. The
       observable behaviour is unchanged: a TOC entry for a repeated heading
       resolves to the first occurrence, exactly as it did when both shared one
       anchor.
   The first occurrence of any heading keeps the anchor it had before the
   amendment, so no existing link moves except into a previously unreachable
   duplicate. The residual hazard — a generated suffix capturing a slug a later
   heading would own — is documented in `slugger.ml`.

   Scope: parse and render only. No IO. Link resolution arrives as a `resolve`
   function, and the outlink/tag/typed-edge side effects the old renderer wrote
   into globals are returned as DATA (`refs`) instead. *)

module Th = Tyxml.Html

(* ---------- the AST ------------------------------------------------------- *)

type inline =
  | Text of string
  | Code of string
  | Strong of inline list
  | Em of inline list
  | Link of { href : string; body : inline list }
  (* display is an inline LIST, not a string: a link's visible text can carry
     emphasis (`[[x|… **CLOSED** …]]` occurs in the corpus), and a string field
     would flatten it back to plain text on the way out *)
  | Wiki of { target : string; anchor : string; display : inline list; rel : string }
  | Wiki_missing of { target : string; display : inline list }
  | Tag of string

type cell = { c_body : inline list }
type row = { r_cells : cell list; r_head : bool }

type block =
  | Heading of { level : int; id : string; body : inline list }
  | Para of { id : string option; body : inline list }
  | Hr
  (* the fence INFO STRING is carried, not discarded. CommonMark puts arbitrary
     text after the opening fence; its first token conventionally names the
     language and the rest is meta. Keeping it raw (rather than pre-split) means
     the parser commits to no interpretation — `lang_of_info` decides, and a
     future meta reader (line highlight, title) needs no carrier change. *)
  | Code_block of { info : string; body : string }
  | Ul of item list
  | Ol of inline list list
  | Blockquote of { callout : (string * string) option; body : inline list }
  | Table of row list
  | Toc of (int * string * inline list) list

and item = { i_body : inline list; i_todo : bool option }

(* an inline stream mid-parse: text still to be scanned, or an already-parsed
   node. Emphasis runs over this sequence so a span can cover a node or sit
   inside one — see the PASS ORDER note. *)
and seg = Raw of string | Node of inline

type t = block list

(* the side data the old renderer accumulated in global refs; returned instead *)
type refs = { outlinks : string list; tags : string list; typed : (string * string) list }

let empty_refs = { outlinks = []; tags = []; typed = [] }

(* ---------- shared helpers, byte-identical in intent to the oracle -------- *)

let starts p l = String.length l >= String.length p && String.sub l 0 (String.length p) = p

(* lowercase, non-alnum to '-', trailing '-' dropped — the anchor scheme *)
let znorm s =
  let b = Buffer.create (String.length s) in
  let dash = ref true in
  String.iter
    (fun c ->
      let c = Char.lowercase_ascii c in
      if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then (Buffer.add_char b c; dash := false)
      else if not !dash then (Buffer.add_char b '-'; dash := true))
    s;
  let r = Buffer.contents b in
  let n = String.length r in
  if n > 0 && r.[n - 1] = '-' then String.sub r 0 (n - 1) else r

(* the LANGUAGE of a fence info string: its first whitespace-delimited token,
   admitted only if it is `[A-Za-z0-9_+-]+`, and lowercased.

   WHY VALIDATE. The info string is corpus text, so it reaches an HTML class
   attribute. TyXML escapes attribute values, so this is NOT an injection seam
   and the validation is not a security control — it is a WELL-FORMEDNESS one:
   an unvalidated token would put arbitrary text (spaces, quotes, punctuation)
   into `class`, producing markup that is valid but meaningless. A rejected
   token degrades to exactly the info-less rendering, never to a broken class.

   TOTAL: every string maps to `Some lang` or `None`; there is no failure case. *)
let is_lang_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '+' || c = '-'

let lang_of_info (info : string) : string option =
  let n = String.length info in
  let rec stop i = if i >= n || info.[i] = ' ' || info.[i] = '\t' then i else stop (i + 1) in
  let tok = String.sub info 0 (stop 0) in
  if tok <> "" && String.for_all is_lang_char tok then Some (String.lowercase_ascii tok)
  else None

let parse_block_id (t : string) : string * string option =
  let re = Str.regexp " +\\^\\([A-Za-z0-9_-]+\\)$" in
  try
    ignore (Str.search_forward re t 0);
    let id = Str.matched_group 1 t in
    (Str.global_replace re "" t, Some id)
  with Not_found -> (t, None)

(* a markdown link target rewritten so internal .md links resolve to note pages *)
let rewrite_href ~resolve url =
  let sw p = starts p url in
  if sw "http://" || sw "https://" || sw "//" || sw "#" || sw "mailto:" || sw "/" then url
  else
    let path, anchor =
      match String.index_opt url '#' with
      | Some i -> (String.sub url 0 i, String.sub url i (String.length url - i))
      | None -> (url, "")
    in
    if String.length path >= 3 && String.lowercase_ascii (Filename.extension path) = ".md" then
      let base = Filename.remove_extension (Filename.basename path) in
      match resolve base with Some slug -> slug ^ ".html" ^ anchor | None -> url
    else url

(* ---------- inline parsing ------------------------------------------------ *)

(* Code spans are taken FIRST so their contents are never reinterpreted, exactly
   as the oracle does: it splits on the first backtick pair and recurses. *)
let rec parse_inline ~resolve (s : string) : inline list =
  match String.index_opt s '`' with
  | Some i -> (
      match String.index_from_opt s (i + 1) '`' with
      | Some j ->
          let before = String.sub s 0 i in
          let code = String.sub s (i + 1) (j - i - 1) in
          let after = String.sub s (j + 1) (String.length s - j - 1) in
          parse_no_code ~resolve before @ [ Code code ] @ parse_inline ~resolve after
      | None -> parse_no_code ~resolve s)
  | None -> parse_no_code ~resolve s

(* PASS ORDER, and it is the subtlest thing in this module.

   The oracle is a chain of string rewrites over ONE string: wiki links, then
   markdown links, then hashtags, then bold, then italic. Because each pass sees
   the OUTPUT of the previous one, `**bold [t](u) tail**` works — by the time the
   bold regex runs, the link is already an anchor, and `[^*]+` happily spans it.

   Parsing links into nodes first and running emphasis only inside the leftover
   text CANNOT reproduce that: the `**` markers end up in different segments and
   never match. The differential caught exactly this.

   So emphasis is detected FIRST here, on the raw text, and the CONTENT of each
   emphasis span is then parsed for wiki links, markdown links and tags — which
   yields the same tree the oracle's rewrite chain produces, without depending on
   regexes that match their own previous output. *)
and parse_no_code ~resolve (s : string) : inline list =
  (* Links/tags first — matching the oracle's order — then emphasis ACROSS the
     resulting segment list. The corpus proved both naive orders wrong:

       links first, emphasis inside each leftover text
         breaks `**bold [t](u) tail**` — the markers land in different segments

       emphasis first, links inside each span
         breaks `[[x|... **CLOSED** ]]` — the markers inside a link's DISPLAY
         split the brackets, and the link stops resolving (a real corpus line)

     The oracle has neither problem because its later regexes run over a string
     in which earlier products are already inert markup — an emphasis span can
     therefore cover an anchor, and can equally sit inside an anchor's text. The
     model that reproduces both is emphasis over the SEQUENCE: flatten segments
     to a string in which a node contributes its display text, match there, and
     then either descend into a node (the match sits inside it) or wrap a run of
     segments (the match covers them). *)
  emphasize (parse_links_segments ~resolve s)

(* the segment list: parsed nodes interleaved with the raw text between them *)
and parse_links_segments ~resolve (s : string) : seg list =
  List.map
    (function Text t -> Raw t | node -> Node node)
    (parse_links ~resolve s)

and display_of = function
  | Text t -> t
  | Code c -> c
  | Wiki { display; _ } | Wiki_missing { display; _ } ->
      String.concat "" (List.map display_of display)
  | Tag t -> "#" ^ t
  | Link { body; _ } -> String.concat "" (List.map display_of body)
  | Strong k | Em k -> String.concat "" (List.map display_of k)

(* rebuild a node with new inline content in its display position *)
and with_body node body =
  match node with
  | Link l -> Link { l with body }
  | Wiki w -> Wiki { w with display = body }
  | Wiki_missing w -> Wiki_missing { w with display = body }
  | other -> other

and emphasize (segs : seg list) : inline list =
  let strong_re = Str.regexp "\\*\\*\\([^*]+\\)\\*\\*" in
  let em_re = Str.regexp "\\*\\([^* ][^*]*\\)\\*" in
  let rec pass re wrap segs =
    (* flat text + a map from flat offset to the segment that owns it *)
    let buf = Buffer.create 128 in
    let owner = ref [] in
    List.iteri
      (fun idx seg ->
        let t = match seg with Raw t -> t | Node n -> display_of n in
        String.iter (fun c -> Buffer.add_char buf c; owner := idx :: !owner) t)
      segs;
    let flat = Buffer.contents buf in
    let owner = Array.of_list (List.rev !owner) in
    (* segment start offsets, so a match can be cut at a segment boundary *)
    let starts = Array.make (List.length segs) 0 in
    let acc = ref 0 in
    List.iteri
      (fun idx seg ->
        starts.(idx) <- !acc;
        acc := !acc + String.length (match seg with Raw t -> t | Node n -> display_of n))
      segs;
    match (try Some (Str.search_forward re flat 0) with Not_found -> None) with
    | None -> List.concat_map (fun s -> match s with Raw t -> [ Text t ] | Node n -> [ n ]) segs
    | Some mstart ->
        let mstop = Str.match_end () in
        let gstart = Str.group_beginning 1 and gstop = Str.group_end 1 in
        if gstop <= gstart || mstop > Array.length owner then
          List.concat_map (fun s -> match s with Raw t -> [ Text t ] | Node n -> [ n ]) segs
        else
          let owner_at k = owner.(k) in
          let o_first = owner_at mstart and o_last = owner_at (mstop - 1) in
          let seg_arr = Array.of_list segs in
          let is_node i = match seg_arr.(i) with Node _ -> true | Raw _ -> false in
          if o_first = o_last && is_node o_first then begin
            (* the whole match sits INSIDE one node's display: descend *)
            let node = match seg_arr.(o_first) with Node n -> n | Raw _ -> assert false in
            let inner_off = starts.(o_first) in
            let d = display_of node in
            let sub a b = String.sub d a (b - a) in
            let rebuilt =
              pass re wrap
                [ Raw (sub 0 (mstart - inner_off));
                  Node (wrap [ Text (sub (gstart - inner_off) (gstop - inner_off)) ]);
                  Raw (sub (mstop - inner_off) (String.length d)) ]
            in
            let before = Array.to_list (Array.sub seg_arr 0 o_first) in
            let after =
              Array.to_list (Array.sub seg_arr (o_first + 1) (Array.length seg_arr - o_first - 1))
            in
            pass re wrap
              (before @ [ Node (with_body node rebuilt) ] @ after)
          end
          else if
            (* a node only PARTIALLY covered would be ill-nested: the oracle
               produces invalid HTML there and TyXML cannot. Leave it literal
               and let the enumerated divergence report it. *)
            (is_node o_first && starts.(o_first) < mstart)
            || (is_node o_last && starts.(o_last) + String.length (display_of
                  (match seg_arr.(o_last) with Node n -> n | Raw _ -> assert false)) > mstop)
          then List.concat_map (fun s -> match s with Raw t -> [ Text t ] | Node n -> [ n ]) segs
          else begin
            (* the match COVERS a run of segments: split the two ends and wrap *)
            let cut_prefix i off =
              match seg_arr.(i) with
              | Raw t -> [ Raw (String.sub t 0 (off - starts.(i))) ]
              | Node _ -> []
            in
            let cut_suffix i off =
              match seg_arr.(i) with
              | Raw t ->
                  let k = off - starts.(i) in
                  [ Raw (String.sub t k (String.length t - k)) ]
              | Node _ -> []
            in
            let inside =
              List.filteri (fun i _ -> i > o_first && i < o_last) segs
              |> fun mid ->
              (match seg_arr.(o_first) with
               | Raw t ->
                   let a = gstart - starts.(o_first) in
                   let b = min (String.length t) (gstop - starts.(o_first)) in
                   if a < b then [ Raw (String.sub t a (b - a)) ] else []
               | Node n -> [ Node n ])
              @ mid
              @
              if o_last = o_first then []
              else
                match seg_arr.(o_last) with
                | Raw t ->
                    let b = gstop - starts.(o_last) in
                    if b > 0 then [ Raw (String.sub t 0 b) ] else []
                | Node n -> [ Node n ]
            in
            let before =
              Array.to_list (Array.sub seg_arr 0 o_first) @ cut_prefix o_first mstart
            in
            let after =
              cut_suffix o_last mstop
              @ Array.to_list (Array.sub seg_arr (o_last + 1) (Array.length seg_arr - o_last - 1))
            in
            pass re wrap before @ [ wrap (pass re wrap inside) ] @ pass re wrap after
          end
  in
  (* strong over the sequence, then italic over the result — the oracle's order,
     and italic sees a sequence in which the strong markers are already gone *)
  let after_strong = pass strong_re (fun k -> Strong k) segs in
  pass em_re (fun k -> Em k) (List.map (function Text t -> Raw t | n -> Node n) after_strong)

and parse_links ~resolve (s : string) : inline list =
  (* pass 1: [[wiki]] links, split into segments *)
  let wiki_re = Str.regexp "\\[\\[\\([^]|]+\\)\\(|\\([^]]+\\)\\)?\\]\\]" in
  let segments = ref [] in
  let pos = ref 0 in
  let n = String.length s in
  let continue = ref true in
  while !continue do
    match (try Some (Str.search_forward wiki_re s !pos) with Not_found -> None) with
    | None ->
        if !pos < n then segments := `Raw (String.sub s !pos (n - !pos)) :: !segments;
        continue := false
    | Some at ->
        let raw_target = Str.matched_group 1 s in
        let explicit = try Some (Str.matched_group 3 s) with Not_found -> None in
        let stop = Str.match_end () in
        if at > !pos then segments := `Raw (String.sub s !pos (at - !pos)) :: !segments;
        let base, anchor =
          match String.index_opt raw_target '#' with
          | Some i ->
              let b = String.trim (String.sub raw_target 0 i) in
              let a = String.sub raw_target (i + 1) (String.length raw_target - i - 1) in
              (b, "#" ^ (if String.length a > 0 && a.[0] = '^' then a else znorm a))
          | None -> (raw_target, "")
        in
        let disp = match explicit with Some d -> d | None -> base in
        (match resolve base with
         | Some slug ->
             (* an @-prefixed display is a TYPED semantic edge, not a label *)
             let display, rel =
               if String.length disp > 0 && disp.[0] = '@' then
                 (base, String.trim (String.sub disp 1 (String.length disp - 1)))
               else (disp, "")
             in
             segments := `Wiki (Wiki { target = slug; anchor; display = [ Text display ]; rel }) :: !segments
         | None -> segments := `Wiki (Wiki_missing { target = base; display = [ Text disp ] }) :: !segments);
        pos := stop
  done;
  let segments = List.rev !segments in
  (* passes 2-5 apply only to RAW segments; a parsed wiki link is opaque *)
  List.concat_map
    (function `Wiki w -> [ w ] | `Raw r -> parse_after_wiki ~resolve r)
    segments

and parse_after_wiki ~resolve (s : string) : inline list =
  (* pass 2: [text](url) *)
  let re = Str.regexp "\\[\\([^]]*\\)\\](\\([^)]*\\))" in
  let out = ref [] and pos = ref 0 and n = String.length s and continue = ref true in
  while !continue do
    match (try Some (Str.search_forward re s !pos) with Not_found -> None) with
    | None ->
        if !pos < n then out := `Raw (String.sub s !pos (n - !pos)) :: !out;
        continue := false
    | Some at ->
        let text = Str.matched_group 1 s and url = Str.matched_group 2 s in
        let stop = Str.match_end () in
        if at > !pos then out := `Raw (String.sub s !pos (at - !pos)) :: !out;
        out :=
          `Node (Link { href = rewrite_href ~resolve url; body = [ Text text ] }) :: !out;
        pos := stop
  done;
  List.concat_map
    (function `Node x -> [ x ] | `Raw r -> parse_tags r)
    (List.rev !out)

(* pass 3: #hashtags — lowercase word tags only, preceded by start, space or '(' *)
and parse_tags (s : string) : inline list =
  let re = Str.regexp "\\(^\\|[ (]\\)#\\([a-z][a-z0-9_-]+\\)" in
  let out = ref [] and pos = ref 0 and n = String.length s and continue = ref true in
  while !continue do
    match (try Some (Str.search_forward re s !pos) with Not_found -> None) with
    | None ->
        if !pos < n then out := `Raw (String.sub s !pos (n - !pos)) :: !out;
        continue := false
    | Some at ->
        let pre = Str.matched_group 1 s and tag = Str.matched_group 2 s in
        let stop = Str.match_end () in
        if at > !pos then out := `Raw (String.sub s !pos (at - !pos)) :: !out;
        if pre <> "" then out := `Raw pre :: !out;
        out := `Node (Tag tag) :: !out;
        pos := stop
  done;
  List.concat_map (function `Node x -> [ x ] | `Raw r -> [ Text r ]) (List.rev !out)


(* ---------- block parsing ------------------------------------------------- *)

(* HEADING IDS ARE DISAMBIGUATED — the amended quirk.

   `znorm` is pure and therefore cannot tell two identical headings apart, so
   the second was unreachable by link. The slugger carries the emission history
   of THIS document and appends the smallest unused suffix on a collision.

   An author-pinned block id (`^name`) bypasses the slugger entirely: it is a
   deliberate, stable name and rewriting it would defeat its purpose. It also
   cannot collide with a generated slug, because pinned ids keep their `^`
   prefix and generated ones never have it.

   ONLY DECLARATIONS go through here. Wikilink fragments and the [TOC] scan
   still use `znorm` — see the amendment note in `markdown_ast_laws.ml` for
   why making either stateful would be wrong rather than merely different. *)
let heading_of ~slugger ~resolve level text =
  let text, bid = parse_block_id text in
  let id =
    match bid with Some i -> "^" ^ i | None -> Slugger.slug slugger text
  in
  Heading { level; id; body = parse_inline ~resolve text }

let para_of ~resolve text =
  match parse_block_id text with
  | text, Some id -> Para { id = Some ("^" ^ id); body = parse_inline ~resolve text }
  | text, None -> Para { id = None; body = parse_inline ~resolve text }

(* the TOC scan, quirks included: it matches heading PREFIXES over every line of
   the document, code fences not excluded, and recomputes the true level from
   any extra leading hashes the prefix match left behind *)
let toc_entries ~resolve lines =
  List.filter_map
    (fun line ->
      let lt = String.trim line in
      let h n pfx =
        if starts pfx lt then
          Some (n, String.sub lt (String.length pfx) (String.length lt - String.length pfx))
        else None
      in
      match h 1 "# " with
      | Some x -> Some x
      | None -> (
          match h 2 "## " with
          | Some x -> Some x
          | None -> ( match h 3 "### " with Some x -> Some x | None -> h 4 "#### ")))
    lines
  |> List.map (fun (lvl, text) ->
         let rec hashes i = if i < String.length text && text.[i] = '#' then hashes (i + 1) else i in
         let extra = hashes 0 in
         let lvl = min (lvl + extra) 4 in
         let text = String.trim (String.sub text extra (String.length text - extra)) in
         let text, bid = parse_block_id text in
         let anchor = match bid with Some id -> "^" ^ id | None -> znorm text in
         (lvl, anchor, parse_no_code ~resolve text))

let parse_with_resolve ~resolve (md : string) : t =
  (* One slugger PER DOCUMENT. Anchors are only required to be unique within
     the page that declares them, and a shared instance would make a document's
     anchors depend on which other documents had been parsed first — the same
     text would render differently in a full run and in a single-file run. *)
  let slugger = Slugger.create () in
  let lines = String.split_on_char '\n' md in
  let out = ref [] in
  let emit b = out := b :: !out in
  (* open-block accumulators, mirroring the oracle's mutable state *)
  let ul = ref [] and ol = ref [] and bq = ref None and tbl = ref [] in
  let tbl_head = ref true in
  let code = ref None in
  let close_lists () =
    if !ul <> [] then (emit (Ul (List.rev !ul)); ul := []);
    if !ol <> [] then (emit (Ol (List.rev !ol)); ol := []);
    (match !bq with
     | Some (callout, parts) ->
         emit (Blockquote { callout; body = List.concat (List.rev parts) });
         bq := None
     | None -> ());
    if !tbl <> [] then (emit (Table (List.rev !tbl)); tbl := []; tbl_head := true)
  in
  List.iter
    (fun raw ->
      let t = String.trim raw in
      match !code with
      | Some (info, acc) when not (starts "```" t) -> code := Some (info, raw :: acc)
      | Some (info, acc) ->
          (* the CLOSING fence's own trailing text is discarded, as CommonMark
             says: only the opening fence carries an info string *)
          emit (Code_block { info; body = String.concat "\n" (List.rev acc) ^ "\n" });
          code := None
      | None ->
          if starts "```" t then
            (close_lists ();
             code := Some (String.trim (String.sub t 3 (String.length t - 3)), []))
          else if t = "" then close_lists ()
          else if t = "---" || t = "***" || t = "___" then (close_lists (); emit Hr)
          else if starts "#### " t then
            (close_lists (); emit (heading_of ~slugger ~resolve 4 (String.sub t 5 (String.length t - 5))))
          else if starts "### " t then
            (close_lists (); emit (heading_of ~slugger ~resolve 3 (String.sub t 4 (String.length t - 4))))
          else if starts "## " t then
            (close_lists (); emit (heading_of ~slugger ~resolve 2 (String.sub t 3 (String.length t - 3))))
          else if starts "# " t then
            (close_lists (); emit (heading_of ~slugger ~resolve 1 (String.sub t 2 (String.length t - 2))))
          else if t = "[TOC]" then begin
            close_lists ();
            let es = toc_entries ~resolve lines in
            if es <> [] then emit (Toc es)
          end
          else if starts "> " t then begin
            let content = String.sub t 2 (String.length t - 2) in
            match !bq with
            (* each quote line contributes its inlines PLUS a trailing space,
               exactly as the oracle's `inline content ^ " "` does *)
            | Some (callout, parts) ->
                bq := Some (callout, (parse_inline ~resolve content @ [ Text " " ]) :: parts)
            | None ->
                close_lists ();
                let cre = Str.regexp "^\\[!\\([a-z]+\\)\\] *" in
                if Str.string_match cre content 0 then begin
                  let ty = Str.matched_group 1 content in
                  let rest = Str.string_after content (Str.match_end ()) in
                  let icon =
                    match ty with
                    | "warning" | "danger" | "caution" -> "\226\154\160"
                    | "tip" | "hint" -> "\240\159\146\161"
                    | "info" | "note" -> "\240\159\147\140"
                    | "quote" | "cite" -> "\226\157\157"
                    | _ -> "\240\159\147\140"
                  in
                  bq :=
                    Some
                      ( Some (ty, icon),
                        if String.trim rest = "" then [] else [ parse_inline ~resolve rest @ [ Text " " ] ] )
                end
                else bq := Some (None, [ parse_inline ~resolve content @ [ Text " " ] ])
          end
          else if starts "- " t || starts "* " t then begin
            if !ul = [] then close_lists ();
            let item = String.sub t 2 (String.length t - 2) in
            if starts "[ ] " item then
              ul :=
                { i_body = parse_inline ~resolve (String.sub item 4 (String.length item - 4));
                  i_todo = Some false }
                :: !ul
            else if starts "[x] " item || starts "[X] " item then
              ul :=
                { i_body = parse_inline ~resolve (String.sub item 4 (String.length item - 4));
                  i_todo = Some true }
                :: !ul
            else ul := { i_body = parse_inline ~resolve item; i_todo = None } :: !ul
          end
          else if
            String.length t >= 3 && t.[0] >= '0' && t.[0] <= '9'
            && (t.[1] = '.' || (t.[1] >= '0' && t.[1] <= '9'))
          then begin
            match String.index_opt t ' ' with
            | Some sp when sp >= 2 && t.[sp - 1] = '.' ->
                if !ol = [] then close_lists ();
                ol := parse_inline ~resolve (String.sub t (sp + 1) (String.length t - sp - 1)) :: !ol
            | _ -> close_lists (); emit (para_of ~resolve t)
          end
          else if starts "|" t && String.length t > 1 then begin
            let cells = String.split_on_char '|' t in
            let cells = match cells with _ :: rest -> rest | [] -> [] in
            let cells = match List.rev cells with "" :: r -> List.rev r | _ -> cells in
            let is_sep =
              List.for_all
                (fun c ->
                  let c = String.trim c in
                  c <> "" && String.for_all (fun ch -> ch = '-' || ch = ':' || ch = ' ') c)
                cells
            in
            (* QUIRK PRESERVED: a separator row does not open a table, so a
               separator directly after a list item leaves the list open. *)
            if is_sep then tbl_head := false
            else begin
              if !tbl = [] then (close_lists (); tbl_head := true);
              tbl :=
                { r_cells = List.map (fun c -> { c_body = parse_inline ~resolve (String.trim c) }) cells;
                  r_head = !tbl_head }
                :: !tbl
            end
          end
          else (close_lists (); emit (para_of ~resolve t)))
    lines;
  (* an UNCLOSED fence at end of input still emits its block — quirk preserved,
     and it now keeps its info string like any other *)
  (match !code with
   | Some (info, acc) -> emit (Code_block { info; body = String.concat "\n" (List.rev acc) ^ "\n" })
   | None -> ());
  close_lists ();
  List.rev !out

let parse (md : string) : t = parse_with_resolve ~resolve:(fun _ -> None) md

(* ---------- the collected references ------------------------------------- *)

let refs_of (doc : t) : refs =
  let outlinks = ref [] and tags = ref [] and typed = ref [] in
  let rec inl = function
    | Wiki { target; rel; _ } ->
        outlinks := target :: !outlinks;
        if rel <> "" then typed := (target, rel) :: !typed
    | Tag t -> tags := t :: !tags
    | Strong k | Em k -> List.iter inl k
    | Link { body; _ } -> List.iter inl body
    | Text _ | Code _ | Wiki_missing _ -> ()
  in
  let blk = function
    | Heading { body; _ } | Para { body; _ } | Blockquote { body; _ } -> List.iter inl body
    | Ul items -> List.iter (fun i -> List.iter inl i.i_body) items
    | Ol items -> List.iter (List.iter inl) items
    | Table rows ->
        List.iter (fun r -> List.iter (fun c -> List.iter inl c.c_body) r.r_cells) rows
    | Toc es -> List.iter (fun (_, _, b) -> List.iter inl b) es
    | Hr | Code_block _ -> ()
  in
  List.iter blk doc;
  { outlinks = !outlinks; tags = !tags; typed = !typed }

(* ---------- rendering ---------------------------------------------------- *)

(* An anchor's children must be NON-INTERACTIVE — TyXML refuses to nest an
   anchor inside an anchor, and it is right to: the HTML content model forbids
   it and a browser would silently restructure the document. A link body only
   ever comes from `parse_emphasis`, which produces Text/Strong/Em and nothing
   else, so this function is total over the data that actually occurs; the
   interactive constructors degrade to their visible text rather than being
   dropped, which keeps rendering TOTAL for a hand-built AST too. *)
let rec render_ni (i : inline) : Html_types.phrasing_without_interactive Th.elt list =
  match i with
  | Text s -> [ Th.txt s ]
  | Code s -> [ Th.code [ Th.txt s ] ]
  | Strong k -> [ Th.strong (List.concat_map render_ni k) ]
  | Em k -> [ Th.em (List.concat_map render_ni k) ]
  | Link { body; _ } -> List.concat_map render_ni body
  | Wiki { display; _ } | Wiki_missing { display; _ } -> List.concat_map render_ni display
  | Tag t -> [ Th.txt ("#" ^ t) ]

(* CLOSED return type, deliberately. A `let rec` cannot keep an open row — the
   recursive call fixes it — so the type is pinned to `phrasing` here and
   COERCED at the use sites that accept a wider content model. `+'a elt` is
   covariant, which is what makes the coercion sound rather than a cast. *)
let rec render_inline (i : inline) : Html_types.phrasing Th.elt list =
  match i with
  | Text s -> [ Th.txt s ]
  | Code s -> [ Th.code [ Th.txt s ] ]
  | Strong k -> [ Th.strong (List.concat_map render_inline k) ]
  | Em k -> [ Th.em (List.concat_map render_inline k) ]
  | Link { href; body } -> [ Th.a ~a:[ Th.a_href href ] (List.concat_map render_ni body) ]
  | Wiki { target; anchor; display; rel } ->
      Th.a
        ~a:[ Th.a_class [ "zettel" ]; Th.a_href (target ^ ".html" ^ anchor) ]
        (List.concat_map render_ni display)
      :: (if rel = "" then []
          else
            [ Th.span
                ~a:[ Th.a_class [ "zk-rel" ]; Th.a_title "typed relation" ]
                [ Th.txt rel ] ])
  | Wiki_missing { target; display } ->
      [ Th.a
          ~a:[ Th.a_class [ "zettel"; "missing" ]; Th.a_title ("unresolved note: " ^ target) ]
          (List.concat_map render_ni display) ]
  | Tag t ->
      [ Th.a
          ~a:[ Th.a_class [ "zk-tag" ]; Th.a_href ("tags.html#" ^ t) ]
          [ Th.txt ("#" ^ t) ] ]



(* the two coercions the content model needs: phrasing as-is, and phrasing
   widened to flow5 for li / td / th, which accept blocks as well *)
let inl_p k : Html_types.phrasing Th.elt list = List.concat_map render_inline k

let render_ni_all k : Html_types.phrasing_without_interactive Th.elt list =
  List.concat_map render_ni k
let inl_f k : Html_types.flow5 Th.elt list = (inl_p k :> Html_types.flow5 Th.elt list)

(* NO INLINE HANDLER. The site's own Content-Security-Policy is
   `default-src 'none'; script-src 'self'` (wiki_content_security_policy_generator),
   which carries no `unsafe-inline` and therefore forbids `on*=` attributes. An
   onclick here would be emitted once PER CODE BLOCK — thousands of violations
   across the generated corpus, which is held to the Error lint tier with no
   ratchet. The behaviour lives in the same-origin `/docs/wiki.js` instead, which
   `script-src 'self'` permits, and binds by event delegation on `.cb-copy`. The
   markup stays inert: a page served without the script degrades to a button that
   does nothing visible rather than a broken one. *)

(* A code block renders in one of three shapes:

     mermaid   -> <pre class="mermaid">SOURCE</pre>
                  bare, because the mermaid runtime replaces the element's own
                  text content with an SVG; a <code> wrapper or a copy button
                  inside it would be destroyed on render.
     lang       -> <div class="cb" data-lang=L><button/><pre><code class="language-L">
     no lang    -> <div class="cb"><button/><pre><code>

   The `language-` prefix is the highlight.js/Prism/Docusaurus convention, so the
   markup is already correct for any highlighter added later.

   BLAST RADIUS, stated honestly: the wrapper div is emitted for EVERY non-mermaid
   block, so this changes the rendering of all 1122 fenced blocks in `docs/`, not
   only the 470 that carry an info string. That is why the corpus baseline is
   regenerated with this slice under a visible `regen:` disclosure. The
   CONSERVATIVITY law pins the part that did NOT change: the <pre><code> core of
   an info-less block is byte-identical to what it was. *)
let render_code_block (info : string) (body : string) : [> Html_types.flow5 ] Th.elt list =
  match lang_of_info info with
  | Some "mermaid" -> [ Th.pre ~a:[ Th.a_class [ "mermaid" ] ] [ Th.txt body ] ]
  | lang ->
      let cls = match lang with Some l -> [ Th.a_class [ "language-" ^ l ] ] | None -> [] in
      let data = match lang with Some l -> [ Th.a_user_data "lang" l ] | None -> [] in
      [ Th.div
          ~a:(Th.a_class [ "cb" ] :: data)
          [ Th.button
              ~a:
                [ Th.a_class [ "cb-copy" ]; Th.a_button_type `Button;
                  (* the wiki carried ONE aria attribute before this slice; a new
                     interactive control must not widen that gap *)
                  Th.a_aria "label" [ "Copy code" ] ]
              [ Th.txt "Copy" ];
            Th.pre [ Th.code ~a:cls [ Th.txt body ] ] ] ]

let render_block (b : block) : [> Html_types.flow5 ] Th.elt list =
  match b with
  | Heading { level; id; body } ->
      let h =
        match level with
        | 1 -> Th.h1
        | 2 -> Th.h2
        | 3 -> Th.h3
        | _ -> Th.h4
      in
      [ h ~a:[ Th.a_id id ] (inl_p body) ]
  | Para { id; body } ->
      let a = match id with Some i -> [ Th.a_id i ] | None -> [] in
      [ Th.p ~a (inl_p body) ]
  | Hr -> [ Th.hr () ]
  | Code_block { info; body } -> render_code_block info body
  | Ul items ->
      [ Th.ul
          (List.map
             (fun it ->
               match it.i_todo with
               | None -> Th.li (inl_f it.i_body)
               | Some checked ->
                   Th.li
                     ~a:[ Th.a_class [ "todo" ] ]
                     (Th.input
                        ~a:
                          ([ Th.a_input_type `Checkbox; Th.a_disabled () ]
                          @ if checked then [ Th.a_checked () ] else [])
                        ()
                      :: Th.txt " "
                      :: inl_f it.i_body))
             items) ]
  | Ol items -> [ Th.ol (List.map (fun b -> Th.li (inl_f b)) items) ]
  | Blockquote { callout; body } ->
      (* the oracle joins quote lines with a trailing space each; the body is
         already the concatenation, so a single space separator matches *)
      let content = inl_p body in
      (* NO paragraph wrapper: the oracle writes the joined inline run directly
         into the blockquote. Adding a `<p>` would be tidier HTML and a
         behaviour change on every quoted block in the corpus. *)
      [ (match callout with
         | None -> Th.blockquote (content :> Html_types.flow5 Th.elt list)
         | Some (ty, icon) ->
             Th.blockquote
               ~a:[ Th.a_class [ "callout"; "co-" ^ ty ] ]
               (Th.div ~a:[ Th.a_class [ "co-t" ] ] [ Th.txt (icon ^ " " ^ ty) ]
                :: (content :> Html_types.flow5 Th.elt list))) ]
  | Table rows ->
      [ Th.div
          ~a:[ Th.a_class [ "tw" ] ]
          [ Th.table
              (List.map
                 (fun r ->
                   Th.tr
                     (List.map
                        (fun c ->
                          if r.r_head then Th.th (inl_f c.c_body)
                          else Th.td (inl_f c.c_body))
                        r.r_cells))
                 rows) ] ]
  | Toc es ->
      [ Th.nav
          ~a:[ Th.a_class [ "toc" ] ]
          (List.map
             (fun (lvl, anchor, body) ->
               Th.a
                 ~a:
                   [ Th.a_class [ Printf.sprintf "toc-l%d" lvl ]; Th.a_href ("#" ^ anchor) ]
                 (* DELIBERATE, DISCLOSED DIVERGENCE. The oracle renders TOC
                    entry text through the full inline pipeline, so a heading
                    containing a wiki link produces an anchor NESTED inside the
                    TOC anchor — invalid HTML that a browser silently
                    restructures. TyXML makes that unconstructible, so the
                    entry renders the link's visible text instead. Strictly
                    better, and the corpus differential says whether any real
                    document reaches it. *)
                 (render_ni_all body :> Html_types.flow5_without_interactive Th.elt list))
             es) ]

let render (doc : t) : [> Html_types.flow5 ] Th.elt list = List.concat_map render_block doc

let render_string ~resolve (md_or_doc : t) : string =
  ignore resolve;
  String.concat ""
    (List.map (fun e -> Format.asprintf "%a" (Th.pp_elt ()) e) (render md_or_doc))

(* the entry point the wiki will use once equivalence is admitted: parse with
   the live resolver, render to elements, and hand back the references the
   caller needs for the link graph *)
let of_markdown ~resolve (md : string) : t * refs =
  let doc = parse_with_resolve ~resolve md in
  (doc, refs_of doc)
