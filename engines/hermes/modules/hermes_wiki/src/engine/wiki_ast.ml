(* HW.2.0.1 — the block carrier, made genuinely recursive.

   WHY THIS EXISTS. `Hermes_wiki.render_markdown` was a streaming line
   machine: it walked lines carrying `in_list`/`in_table`/`in_fence`,
   opened a tag on one line and closed it many lines later. That shape
   cannot express a block INSIDE a block, and the plan's §4.1 records the
   consequence — one type fact explains four apparently separate gaps
   (nested lists, admonitions that cannot hold code or lists, <details>,
   tabs) and gates six more (footnotes, block anchors, [TOC],
   literalinclude, productionlist, the 382-document ingest).

   So the parser is split from the renderer:

     parse  : string -> t                 (bytes to a typed document)
     render : t -> string                 (a document to markup)

   Ontology
     Carrier      `t` — a block list, where a block MAY contain blocks.
     Denotation   the rendered document.
     Operations   `parse`, `render`.
     Observations the rendered markup, compared to the oracle's.

   ORACLE vs FINAL (the zigvm discipline, R14). The ORACLE is the old
   streaming renderer, which produced every page of this wiki. Its
   behaviour — quirks included — is the specification. This is the FINAL
   encoding, admitted ONLY by observational equivalence over the whole
   real corpus (`test_wiki_ast`, plus the render baseline). The old
   implementation therefore STAYS as `render_line_machine`: not dead code,
   but the permanently-exercised specification. Deleting it would delete
   the specification.

   SCOPE OF THIS STEP. The BLOCK layer is now recursive; the INLINE layer
   is still a raw string handed to the caller's inline renderer. That is
   deliberate and sufficient: every feature this change unblocks needs
   block-in-block, none needs typed inlines. Typing the inline layer is a
   separate step and is not claimed here.

   QUIRKS DELIBERATELY PRESERVED, because equivalence is the bar and a
   "fix" here would silently change 169 published documents:
     - each `> ` line is its OWN blockquote; consecutive quote lines do
       not merge into one.
     - a heading needs a space after the hashes, and its level is capped
       at 4, so `#####` falls through to a paragraph.
     - a table separator row (`|---|`) is dropped and does not itself
       open a table.
     - a paragraph joins its lines with a single space.
     - an unterminated fence is closed at end of input.
   Each is pinned by a named check in `test_wiki_ast`, so changing any of
   them is a deliberate act with a failing law rather than an accident. *)

type block =
  | Inline_run of string
      (* raw inline source rendered WITHOUT a wrapping tag — what a list
         item and a blockquote body carry today. Distinct from [Para]
         because <li>x</li> and <p>x</p> are different bytes. *)
  | Para of string
  | Heading of { level : int; text : string }
  | Rule
  | Fence of { info : string; body : string list }
      (* HW.2.0.2: the info string (lang + meta) VERBATIM — the parser
         commits to no interpretation; lang_of_info decides at render. *)
  | List_block of { ordered : bool; start : int; content : list_content list }
  | Table of row list
  | Quote of block list  (* RECURSIVE — the point of the change *)
  | Callout of { header : Wiki_callout.header; body : block list }
      (* HW.2.3.1: a blockquote whose first line is `[!type]`. Grouped by
         a post-pass over the block list, so the line loop is untouched. *)

and list_content =
  | Item of item
  | Loose of block
      (* QUIRK, preserved: the oracle flushes a paragraph WITHOUT closing an
         open list, so the paragraph is emitted inside the <ul>. Malformed
         HTML, and the behaviour of every page published so far, so it is
         captured rather than silently corrected. *)

and item = { task : bool option; body : block list }  (* RECURSIVE *)
and row = { header : bool; cells : string list }

type t = block list

(* ------------------------------------------------------------- lexemes *)

let lines_of text = String.split_on_char '\n' text

let starts_with prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

let is_thematic_break line =
  let t = String.trim line in
  match String.length t with
  | 0 -> false
  | _ ->
      let c = t.[0] in
      (c = '-' || c = '*' || c = '_')
      && String.for_all (fun ch -> ch = c || ch = ' ') t
      && String.length (String.concat "" (String.split_on_char ' ' t)) >= 3

let ordered_marker line =
  let n = String.length line in
  let i = ref 0 in
  while !i < n && line.[!i] >= '0' && line.[!i] <= '9' do
    incr i
  done;
  if !i = 0 || !i > 9 || !i + 1 >= n then None
  else if (line.[!i] = '.' || line.[!i] = ')') && line.[!i + 1] = ' ' then
    match int_of_string_opt (String.sub line 0 !i) with
    | Some start -> Some (start, String.sub line (!i + 2) (n - !i - 2))
    | None -> None
  else None

let task_marker item =
  if String.length item >= 4 && item.[0] = '[' && item.[2] = ']' && item.[3] = ' ' then
    match item.[1] with
    | ' ' -> Some (false, String.sub item 4 (String.length item - 4))
    | 'x' | 'X' -> Some (true, String.sub item 4 (String.length item - 4))
    | _ -> None
  else None

let table_cells trimmed =
  String.split_on_char '|' trimmed
  |> List.filter_map (fun c ->
         let c = String.trim c in
         if c = "" then None else Some c)

let is_separator_row cells =
  cells <> []
  && List.for_all (fun c -> String.for_all (fun ch -> ch = '-' || ch = ':') c) cells

(* --------------------------------------------------------------- parse *)

(* The LANGUAGE of a fence info string (mirror: markdown_ast). The info
   string is corpus text reaching an HTML class attribute; validation is
   WELL-FORMEDNESS, not a security control — a rejected token degrades to
   exactly the info-less rendering, never a broken class. TOTAL. *)
let is_lang_char c =
  (c >= 'a' && c <= 'z')
  || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9')
  || c = '_' || c = '+' || c = '-'

let lang_of_info (info : string) : string option =
  let n = String.length info in
  let rec stop i = if i >= n || info.[i] = ' ' || info.[i] = '\t' then i else stop (i + 1) in
  let tok = String.sub info 0 (stop 0) in
  if tok <> "" && String.for_all is_lang_char tok then Some (String.lowercase_ascii tok)
  else None

(* The fence opener's text after the backticks, trimmed — "" when bare. *)
let fence_info_of_line line =
  let t = String.trim line in
  let n = String.length t in
  let rec past i = if i < n && t.[i] = '`' then past (i + 1) else i in
  String.trim (String.sub t (past 0) (n - past 0))

let rec fences_of_blocks blocks =
  List.concat_map
    (function
      | Fence { info; body } -> [ (info, body) ]
      | Quote inner -> fences_of_blocks inner
      | List_block { content; _ } ->
          List.concat_map
            (function Loose b -> fences_of_blocks [ b ] | Item _ -> [])
            content
      | _ -> [])
    blocks

let fences (doc : t) : (string * string list) list = fences_of_blocks doc

(* HW.2.3.1 — group a callout out of the per-line quotes the loop
   produced. Done as a POST-PASS so the line loop, and therefore every
   existing blockquote in the corpus, is untouched: only a quote whose
   first line is `[!type]` starts a group. The body text is RE-PARSED, so
   a callout may hold lists, fences and nested callouts — which is what
   made this row wait on the recursive carrier. *)
let rec group_callouts ~parse blocks =
  match blocks with
  | Quote [ Inline_run head ] :: rest when Wiki_callout.parse_header head <> None ->
      let header = Option.get (Wiki_callout.parse_header head) in
      let rec take acc = function
        | Quote [ Inline_run l ] :: more when Wiki_callout.parse_header l = None ->
            take (l :: acc) more
        | remaining -> (List.rev acc, remaining)
      in
      let body_lines, tail = take [] rest in
      let body = parse (String.concat "\n" body_lines) in
      Callout { header; body } :: group_callouts ~parse tail
  | b :: rest -> b :: group_callouts ~parse rest
  | [] -> []

(* ONE fence emitter for BOTH renderers (the block_anchor_split
   discipline): the open tag from the language, `<mark>` on the
   1-based emphasized lines (HW.2.6.6), the body escaped. Byte-equality
   between the AST path and the line machine holds BY CONSTRUCTION. *)
let fence_html ~escape ?lang ?(emphasize = []) body =
  let b = Buffer.create 256 in
  (* The class attribute is the ONE place author text reaches markup
     unescaped, so the charset check belongs HERE, at the sink — not only
     in lang_of_info, which two other paths (an include's `lang=` and the
     document's `highlight:`) bypass entirely. An invalid token degrades
     to exactly the info-less rendering, which is the contract. *)
  let valid l = l <> "" && String.for_all is_lang_char l in
  (match lang with
  | Some l when valid l ->
      Buffer.add_string b (Printf.sprintf "<pre><code class=\"language-%s\">" l)
  | Some _ | None -> Buffer.add_string b "<pre><code>");
  List.iteri
    (fun i line ->
      let escaped = escape line in
      let marked =
        if List.mem (i + 1) emphasize then "<mark>" ^ escaped ^ "</mark>" else escaped
      in
      Buffer.add_string b (marked ^ "\n"))
    body;
  Buffer.add_string b "</code></pre>\n";
  Buffer.contents b

(* HW.9.2.1 — an include renders its SLICE; a failure renders VISIBLY.
   The dual of the denotation law: silence is the one outcome this
   feature exists to prevent, so the reason lands in the page itself. *)
let include_html ~escape ~resolve (d : Wiki_include.t) =
  match resolve d with
  | Ok body ->
      fence_html ~escape ?lang:(Wiki_include.lang_of d) ~emphasize:d.Wiki_include.emphasize body
  | Error reason ->
      fence_html ~escape ~lang:"text"
        [ Printf.sprintf "literalinclude unresolved: %s (%s)" d.Wiki_include.path reason ]
let fence_infos (doc : t) : string list = List.map fst (fences doc)

let rec parse markdown : t =
  let blocks = ref [] in
  let emit b = blocks := b :: !blocks in
  (* open accumulators, mirroring the line machine's state exactly *)
  let para = Buffer.create 128 in
  let fence : string list ref = ref [] in
  let fence_info = ref "" in
  let in_fence = ref false in
  let list_content : list_content list ref = ref [] in
  let table_rows : row list ref = ref [] in
  (* The oracle emits to one buffer in stream order, so a block produced
     while a list is OPEN lands inside the <ul>. [emit_block] reproduces
     that: route into the open list, else to the top level. *)
  let list_kind : (bool * int) option ref = ref None in
  let emit_block b =
    if !list_kind <> None then list_content := Loose b :: !list_content else emit b
  in
  let flush_para () =
    if Buffer.length para > 0 then (
      emit_block (Para (Buffer.contents para));
      Buffer.clear para)
  in
  let close_list () =
    match !list_kind with
    | Some (ordered, start) ->
        emit (List_block { ordered; start; content = List.rev !list_content });
        list_content := [];
        list_kind := None
    | None -> ()
  in
  let close_table () =
    if !table_rows <> [] then (
      emit (Table (List.rev !table_rows));
      table_rows := [])
  in
  let close_fence () =
    if !in_fence then (
      emit (Fence { info = !fence_info; body = List.rev !fence });
      fence := [];
      fence_info := "";
      in_fence := false)
  in
  List.iter
    (fun line ->
      if !in_fence then if is_fence line then close_fence () else fence := line :: !fence
      else if is_fence line then (
        flush_para ();
        close_list ();
        close_table ();
        fence_info := fence_info_of_line line;
        in_fence := true)
      else
        let trimmed = String.trim line in
        if starts_with "#" trimmed && String.contains trimmed ' ' then (
          flush_para ();
          close_list ();
          close_table ();
          let level = ref 0 in
          while !level < String.length trimmed && trimmed.[!level] = '#' do
            incr level
          done;
          let level = min !level 4 in
          emit
            (Heading
               { level; text = String.trim (String.sub trimmed level (String.length trimmed - level)) }))
        else if is_thematic_break trimmed then (
          flush_para ();
          close_list ();
          close_table ();
          emit Rule)
        else if starts_with "- " trimmed || starts_with "* " trimmed then (
          flush_para ();
          close_table ();
          (match !list_kind with Some (true, _) -> close_list () | _ -> ());
          if !list_kind = None then list_kind := Some (false, 1);
          let content = String.sub trimmed 2 (String.length trimmed - 2) in
          match task_marker content with
          | Some (checked, rest) ->
              list_content := Item { task = Some checked; body = [ Inline_run rest ] } :: !list_content
          | None -> list_content := Item { task = None; body = [ Inline_run content ] } :: !list_content)
        else
          match ordered_marker trimmed with
          | Some (start, rest) ->
              flush_para ();
              close_table ();
              (* QUIRK, preserved: the oracle computes the start attribute
                 BEFORE closing a list of the other kind, so an ordered list
                 that directly follows a bullet list loses its start number.
                 Reproduced by capturing openness first. *)
              let was_open = !list_kind <> None in
              (match !list_kind with Some (false, _) -> close_list () | _ -> ());
              if !list_kind = None then
                list_kind := Some (true, if was_open then 1 else start);
              list_content := Item { task = None; body = [ Inline_run rest ] } :: !list_content
          | None ->
              if starts_with "|" trimmed then (
                flush_para ();
                close_list ();
                let cells = table_cells trimmed in
                if not (is_separator_row cells) then
                  table_rows := { header = !table_rows = []; cells } :: !table_rows)
              else if starts_with "> " trimmed then (
                flush_para ();
                close_list ();
                close_table ();
                emit (Quote [ Inline_run (String.sub trimmed 2 (String.length trimmed - 2)) ]))
              else if trimmed = "" then (
                flush_para ();
                close_list ();
                close_table ())
              else (
                if Buffer.length para > 0 then Buffer.add_char para ' ';
                Buffer.add_string para line))
    (lines_of markdown);
  flush_para ();
  close_list ();
  close_table ();
  close_fence ();
  (* HW.2.3.1 IS NOT WIRED IN YET, DELIBERATELY. `group_callouts` and the
     `Callout` emitter are complete and tested, but the LINE MACHINE
     cannot group consecutive quote lines — it is a streaming `List.iter`
     with no lookahead — so enabling grouping here would make the two
     renderers disagree the moment anyone wrote `> [!note]`. The oracle
     law would then fail with a confusing message instead of the feature
     working. The remaining step is to give the line machine an indexed
     walk so it can consume a group and delegate to this layer. Until
     then the pass is the identity, and both renderers emit per-line
     blockquotes exactly as they always have. *)
  group_callouts ~parse (List.rev !blocks)

(* -------------------------------------------------------------- render

   A catamorphism over the block tree. [inline] renders a raw inline run,
   [anchor] is the document's stateful slugger, and [escape] escapes fence
   bodies — all supplied by the caller, so this module stays free of the
   link resolver and the corpus. *)

(* HW.3.3.1 — the block-anchor marker. Alphabet [A-Za-z0-9-], the id is
   kept WITH the ^ (namespace disjoint from heading slugs by construction),
   and a marker needs preceding text: a bare "^id" line is a paragraph. *)
let block_anchor_split line =
  let is_id_char c =
    c = '-' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  in
  let rstrip s =
    let stop = ref (String.length s) in
    while !stop > 0 && (s.[!stop - 1] = ' ' || s.[!stop - 1] = '\t') do decr stop done;
    String.sub s 0 !stop
  in
  let trimmed = rstrip line in
  let n = String.length trimmed in
  match String.rindex_opt trimmed ' ' with
  | Some sp when sp + 1 < n && trimmed.[sp + 1] = '^' ->
      let id = String.sub trimmed (sp + 2) (n - sp - 2) in
      let text = rstrip (String.sub trimmed 0 sp) in
      if id <> "" && String.for_all is_id_char id && text <> "" then (text, Some ("^" ^ id))
      else (line, None)
  | _ -> (line, None)

let render ?(resolve_include = fun (d : Wiki_include.t) ->
      Error (Printf.sprintf "no source reader injected for %s" d.Wiki_include.path))
    ?default_lang ~inline ~anchor ~escape (doc : t) =
  let buffer = Buffer.create 4096 in
  let rec block b =
    match b with
    | Inline_run s -> Buffer.add_string buffer (inline s)
    | Para s -> (
        match block_anchor_split s with
        | text, Some a -> Buffer.add_string buffer ("<p id=\"" ^ a ^ "\">" ^ inline text ^ "</p>\n")
        | _, None -> Buffer.add_string buffer ("<p>" ^ inline s ^ "</p>\n"))
    | Heading { level; text } ->
        Buffer.add_string buffer
          (Printf.sprintf "<h%d id=\"%s\">%s</h%d>\n" level (anchor text) (inline text) level)
    | Rule -> Buffer.add_string buffer "<hr />\n"
    | Fence { info; body } -> (
        (* HW.9.2.1 first: a literalinclude's info is a DIRECTIVE, so its
           first token must never be read as a language. *)
        match Wiki_include.parse info with
        | Some d -> Buffer.add_string buffer (include_html ~escape ~resolve:resolve_include d)
        | None when Wiki_include.attempted info ->
            (* a near-miss directive must NOT fall through to the language
               branch: that renders the authored body, which is exactly
               the stale hand-copy this feature exists to abolish *)
            Buffer.add_string buffer
              (fence_html ~escape ~lang:"text"
                 [ Printf.sprintf "literalinclude unresolved: malformed directive (%s)" info ])
        | None ->
            let lang =
              match lang_of_info info with Some l -> Some l | None -> default_lang
            in
            Buffer.add_string buffer
              (fence_html ~escape ?lang ~emphasize:(Wiki_include.emphasize_of_info info) body))
    | List_block { ordered; start; content } ->
        let tag = if ordered then "ol" else "ul" in
        let attrs = if ordered && start <> 1 then Printf.sprintf " start=\"%d\"" start else "" in
        Buffer.add_string buffer (Printf.sprintf "<%s%s>\n" tag attrs);
        List.iter
          (function
            | Item { task; body } ->
                let body, anchor_attr =
                  match body with
                  | [ Inline_run s ] -> (
                      match block_anchor_split s with
                      | text, Some a -> ([ Inline_run text ], Printf.sprintf " id=\"%s\"" a)
                      | _ -> (body, ""))
                  | _ -> (body, "")
                in
                (match task with
                | Some checked ->
                    Buffer.add_string buffer
                      (Printf.sprintf "<li class=\"task\"%s><input type=\"checkbox\" disabled%s /> "
                         anchor_attr
                         (if checked then " checked" else ""))
                | None -> Buffer.add_string buffer (Printf.sprintf "<li%s>" anchor_attr));
                List.iter block body;
                Buffer.add_string buffer "</li>\n"
            | Loose b -> block b)
          content;
        Buffer.add_string buffer (Printf.sprintf "</%s>\n" tag)
    | Table rows ->
        Buffer.add_string buffer "<table>\n";
        List.iter
          (fun { header; cells } ->
            let tag = if header then "th" else "td" in
            Buffer.add_string buffer "<tr>";
            List.iter
              (fun c -> Buffer.add_string buffer (Printf.sprintf "<%s>%s</%s>" tag (inline c) tag))
              cells;
            Buffer.add_string buffer "</tr>\n")
          rows
        ;
        Buffer.add_string buffer "</table>\n"
    | Quote body ->
        Buffer.add_string buffer "<blockquote>";
        List.iter block body;
        Buffer.add_string buffer "</blockquote>\n"
    | Callout { header; body } ->
        (* one emitter, both renderers — the body is rendered first, then
           handed over as bytes, so this function never parses markdown *)
        let inner = Buffer.create 256 in
        let saved = Buffer.contents buffer in
        Buffer.clear buffer;
        List.iter block body;
        Buffer.add_string inner (Buffer.contents buffer);
        Buffer.clear buffer;
        Buffer.add_string buffer saved;
        Buffer.add_string buffer
          (Wiki_callout.html ~escape ~inline header ~body:(Buffer.contents inner))
  in
  List.iter block doc;
  Buffer.contents buffer

(* ---------------------------------------------------------- observation *)

let rec depth_block = function
  | Quote body -> 1 + depth_blocks body
  | List_block { content; _ } ->
      1
      + List.fold_left
          (fun m -> function Item i -> max m (depth_blocks i.body) | Loose b -> max m (depth_block b))
          0 content
  | _ -> 1

and depth_blocks bs = List.fold_left (fun m b -> max m (depth_block b)) 0 bs

let depth doc = depth_blocks doc
