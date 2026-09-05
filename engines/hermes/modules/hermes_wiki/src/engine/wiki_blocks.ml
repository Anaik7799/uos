(* The remaining block-level dialect: nested lists, footnotes, admonition
   titles and block bodies, toggles, the in-page table of contents, and
   the two directive lints. See the mli for the six rows, the column-zero
   decision, the preservation law, and why the ToC law is computed rather
   than asserted.

   PURE: text in, structured value out. The only outside call is
   [Hermes_wiki.render_markdown] with an empty resolver, which is a
   function of its argument. *)

(* --------------------------------------------------------------- types *)

type kind =
  | Admonition of string
  | Toggle of string
  | Unrecognised of string

type fold = Plain | Open | Closed

type footnote = {
  fid : string;
  label : int;
  definition : string list;
  defined : bool;
  refs : int;
}

type toc_entry = { level : int; text : string; anchor : string }

type block = {
  name : string;
  kind : kind;
  colons : int;
  title : string;
  fold : fold;
  opener : string;
  closer : string option;
  body : node list;
  body_source : string list;
}

and node =
  | Text of string list
  | Fenced of string list
  | Toc_marker of string
  | Note_def of note_def
  | Block of block

and note_def = { did : string; dtext : string list; dsource : string list }

let kind_name = function
  | Admonition n -> n
  | Toggle n -> n
  | Unrecognised n -> n

type diagnostic =
  | Unclosed_block of string
  | Unrecognised_directive of string
  | Unused_directive of string
  | Undefined_footnote of string
  | Unreferenced_footnote of string
  | Duplicate_footnote of string
  | Toc_without_headings

let diagnostic_line = function
  | Unclosed_block n ->
      Printf.sprintf "block never closed, clamped at end of input: :::%s" n
  | Unrecognised_directive n ->
      Printf.sprintf "directive-like block in no vocabulary, preserved verbatim: :::%s" n
  | Unused_directive n ->
      Printf.sprintf "directive registered and used nowhere in this document: %s" n
  | Undefined_footnote id -> Printf.sprintf "footnote referenced with no definition: [^%s]" id
  | Unreferenced_footnote id -> Printf.sprintf "footnote defined and never referenced: [^%s]" id
  | Duplicate_footnote id ->
      Printf.sprintf "footnote defined more than once, first definition kept: [^%s]" id
  | Toc_without_headings -> "[TOC] on a page with no headings: the outline would be empty"

type t = { nodes : node list; notes : footnote list; diagnostics : diagnostic list }

(* --------------------------------------------------------------- lexis *)

let lines_of text = String.split_on_char '\n' text
let is_blank line = String.trim line = ""

let starts_with prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

(* Mirror of Hermes_wiki.is_fence, Wiki_ast.is_fence, Wiki_directive.is_fence
   and Wiki_transclude's: the SAME fence grammar in all of them, so a
   document cannot be fenced for one reader and open for another. *)
let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

let is_indented line =
  (not (is_blank line)) && String.length line > 0 && (line.[0] = ' ' || line.[0] = '\t')

(* COLUMNS, not characters: a tab advances to the next multiple of four,
   so `\t` and four spaces are one level and mixing them cannot invent a
   nesting level. Blank lines have no indentation to speak of, so they
   report 0 rather than their own width. *)
let indent_columns line =
  if is_blank line then 0
  else
    let n = String.length line in
    let rec go i col =
      if i >= n then col
      else
        match line.[i] with
        | ' ' -> go (i + 1) (col + 1)
        | '\t' -> go (i + 1) (col + (4 - (col mod 4)))
        | _ -> col
    in
    go 0 0

let is_id_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '-'

let dedup xs = List.rev (List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] xs)

(* [List.map] leaves evaluation order unspecified, which is a defect the
   moment the function is stateful — the slugger and the footnote
   numberer both are. Everything here maps LEFT TO RIGHT, on purpose. *)
let map_in_order f l = List.rev (List.fold_left (fun acc x -> f x :: acc) [] l)

let rec take n = function [] -> [] | l :: rest -> if n > 0 then l :: take (n - 1) rest else []
let rec drop n = function [] -> [] | _ :: rest as all -> if n > 0 then drop (n - 1) rest else all

(* ------------------------------------------------- HW.2.1.4 list markers

   The oracle's markers exactly (Wiki_ast.ordered_marker, task_marker), so
   a list this parser sees and the renderer does not is unrepresentable. *)

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

type marker = { m_ordered : bool; m_start : int; m_text : string }

let list_marker line =
  let s = String.trim line in
  if starts_with "- " s || starts_with "* " s then
    Some { m_ordered = false; m_start = 1; m_text = String.sub s 2 (String.length s - 2) }
  else
    match ordered_marker s with
    | Some (start, rest) -> Some { m_ordered = true; m_start = start; m_text = rest }
    | None -> None

let is_list_line line = list_marker line <> None

(* ------------------------------------------------- HW.2.1.4 the nesting

   A STACK OF COLUMNS. The first marker of a run opens level 1 whatever
   its column; a deeper column pushes; a shallower column pops until the
   top is at most that column, so a dedent of several levels at once
   lands where it dedented to. *)

type frame = {
  f_indent : int;
  f_ordered : bool;
  f_start : int;
  mutable f_items : Wiki_ast.item list;  (* reversed *)
}

let close_frame fr =
  Wiki_ast.List_block
    { ordered = fr.f_ordered;
      start = fr.f_start;
      content = List.rev_map (fun i -> Wiki_ast.Item i) fr.f_items }

(* A closed child hangs off its parent's MOST RECENT item. A parent with
   no item yet cannot arise from the walk below, but a synthetic empty
   item is still the answer rather than a dropped subtree: losing an
   author's list is the failure this module exists to avoid. *)
let attach_to_parent parent child =
  match parent.f_items with
  | it :: rest ->
      parent.f_items <- { it with Wiki_ast.body = it.Wiki_ast.body @ [ child ] } :: rest
  | [] -> parent.f_items <- [ { Wiki_ast.task = None; body = [ child ] } ]

let rec append_text bs text =
  match bs with
  | [ Wiki_ast.Inline_run s ] ->
      [ Wiki_ast.Inline_run (if s = "" then text else s ^ " " ^ text) ]
  | b :: rest -> b :: append_text rest text
  | [] -> [ Wiki_ast.Inline_run text ]

let build_run lines =
  let out = ref [] in
  let stack = ref [] in
  let pop_one () =
    match !stack with
    | fr :: rest -> (
        stack := rest;
        let b = close_frame fr in
        match rest with p :: _ -> attach_to_parent p b | [] -> out := b :: !out)
    | [] -> ()
  in
  let rec pop_until col =
    match !stack with fr :: _ when col < fr.f_indent -> pop_one (); pop_until col | _ -> ()
  in
  let add_item fr m =
    let task, text =
      match task_marker m.m_text with
      | Some (checked, rest) -> (Some checked, rest)
      | None -> (None, m.m_text)
    in
    fr.f_items <- { Wiki_ast.task; body = [ Wiki_ast.Inline_run text ] } :: fr.f_items
  in
  let push col m =
    let fr = { f_indent = col; f_ordered = m.m_ordered; f_start = m.m_start; f_items = [] } in
    stack := fr :: !stack;
    add_item fr m
  in
  let continue_item text =
    match !stack with
    | fr :: _ -> (
        match fr.f_items with
        | it :: rest ->
            fr.f_items <- { it with Wiki_ast.body = append_text it.Wiki_ast.body text } :: rest
        | [] -> ())
    | [] -> ()
  in
  List.iter
    (fun line ->
      match list_marker line with
      | Some m -> (
          let col = indent_columns line in
          pop_until col;
          match !stack with
          | fr :: _ when col = fr.f_indent && fr.f_ordered <> m.m_ordered ->
              (* the oracle's rule: a bullet run and a numbered run never
                 merge into one malformed list *)
              pop_one ();
              push col m
          | fr :: _ when col = fr.f_indent -> add_item fr m
          | _ :: _ -> push col m
          | [] -> push col m)
      | None -> continue_item (String.trim line))
    lines;
  while !stack <> [] do
    pop_one ()
  done;
  List.rev !out

let parse_lists text =
  let out = ref [] in
  let plain = ref [] in
  let run = ref [] in
  let in_fence = ref false in
  let flush_plain () =
    if !plain <> [] then begin
      out := List.rev_append (Wiki_ast.parse (String.concat "\n" (List.rev !plain))) !out;
      plain := []
    end
  in
  let flush_run () =
    if !run <> [] then begin
      out := List.rev_append (build_run (List.rev !run)) !out;
      run := []
    end
  in
  List.iter
    (fun line ->
      if !in_fence then begin
        plain := line :: !plain;
        if is_fence line then in_fence := false
      end
      else if is_fence line then begin
        flush_run ();
        plain := line :: !plain;
        in_fence := true
      end
      else if is_list_line line then begin
        flush_plain ();
        run := line :: !run
      end
      else if !run <> [] && is_indented line then run := line :: !run
      else begin
        flush_run ();
        plain := line :: !plain
      end)
    (lines_of text);
  flush_run ();
  flush_plain ();
  List.rev !out

let rec list_depth_block = function
  | Wiki_ast.List_block { content; _ } ->
      1
      + List.fold_left
          (fun m c ->
            match c with
            | Wiki_ast.Item i -> max m (list_depth_blocks i.Wiki_ast.body)
            | Wiki_ast.Loose b -> max m (list_depth_block b))
          0 content
  | Wiki_ast.Quote body -> list_depth_blocks body
  | Wiki_ast.Callout { body; _ } -> list_depth_blocks body
  | Wiki_ast.Inline_run _ | Wiki_ast.Para _ | Wiki_ast.Heading _ | Wiki_ast.Rule
  | Wiki_ast.Fence _ | Wiki_ast.Table _ ->
      0

and list_depth_blocks bs = List.fold_left (fun m b -> max m (list_depth_block b)) 0 bs

let list_depth = list_depth_blocks

(* The same number read off the SOURCE, with no tree: the high-water mark
   of the column stack. Independent of [build_run], which is the only
   reason the equality is a law rather than a tautology. *)
let source_list_depth text =
  let best = ref 0 and stack = ref [] and in_fence = ref false in
  List.iter
    (fun line ->
      if !in_fence then (if is_fence line then in_fence := false)
      else if is_fence line then begin
        stack := [];
        in_fence := true
      end
      else
        match list_marker line with
        | Some _ ->
            let col = indent_columns line in
            let rec pop () =
              match !stack with c :: rest when col < c -> stack := rest; pop () | _ -> ()
            in
            pop ();
            (match !stack with c :: _ when c = col -> () | _ -> stack := col :: !stack);
            if List.length !stack > !best then best := List.length !stack
        | None -> if not (is_indented line) then stack := [])
    (lines_of text);
  !best

(* ---------------------------------------------- the colon block grammar *)

let toggle_names = [ "details"; "toggle" ]

let builtin_directives =
  [ "note"; "abstract"; "info"; "todo"; "tip"; "success"; "question"; "warning"; "failure";
    "danger"; "bug"; "example"; "quote" ]
  @ toggle_names

let kind_of_name name =
  let lower = String.lowercase_ascii name in
  if List.mem lower toggle_names then Toggle lower
  else
    match Wiki_callout.kind_of_string lower with
    | Wiki_callout.Unknown _ -> Unrecognised name
    | ( Wiki_callout.Note | Wiki_callout.Abstract | Wiki_callout.Info | Wiki_callout.Todo
      | Wiki_callout.Tip | Wiki_callout.Success | Wiki_callout.Question | Wiki_callout.Warning
      | Wiki_callout.Failure | Wiki_callout.Danger | Wiki_callout.Bug | Wiki_callout.Example
      | Wiki_callout.Quote ) as k ->
        Admonition (Wiki_callout.kind_name k)

(* A toggle exists to HIDE something, so it is closed unless the author
   opened it; an admonition exists to be SEEN, so it is plain unless the
   author asked for a disclosure. *)
let default_fold kind written =
  match written with
  | Open | Closed -> written
  | Plain -> ( match kind with Toggle _ -> Closed | Admonition _ | Unrecognised _ -> Plain)

(* `:::name[+|-] [title]` at COLUMN ZERO. The column-zero rule is what
   excludes an inline-backticked copy: a marker preceded by a backtick is
   not at column zero. *)
let colon_opener line =
  let n = String.length line in
  let rec colons i = if i < n && line.[i] = ':' then colons (i + 1) else i in
  let c = colons 0 in
  if c < 3 then None
  else
    let rec ident i = if i < n && is_id_char line.[i] then ident (i + 1) else i in
    let e = ident c in
    if e = c then None
    else if not (e >= n || line.[e] = ' ' || line.[e] = '\t' || line.[e] = '+' || line.[e] = '[')
    then None
    else
      let raw_name = String.sub line c (e - c) in
      (* `-` is both an ident character and the fold suffix; a TRAILING
         one is the suffix, an interior one is part of the name, so
         `:::note-` folds and `:::my-block` does not lose its word. *)
      let trailing_dash = String.length raw_name > 1 && raw_name.[String.length raw_name - 1] = '-' in
      let name =
        if trailing_dash then String.sub raw_name 0 (String.length raw_name - 1) else raw_name
      in
      let rest = String.sub line e (n - e) in
      let fold, rest =
        if trailing_dash then (Closed, rest)
        else if String.length rest > 0 && rest.[0] = '+' then
          (Open, String.sub rest 1 (String.length rest - 1))
        else (Plain, rest)
      in
      let title = String.trim rest in
      let title =
        if String.length title >= 2 && title.[0] = '[' && title.[String.length title - 1] = ']'
        then String.trim (String.sub title 1 (String.length title - 2))
        else title
      in
      let k = kind_of_name name in
      Some (c, name, k, default_fold k fold, title)

(* A closer is a colon-ONLY line at column zero. Its count must be at
   least the opener's, which is exactly what lets an outer `::::` block
   contain an inner `:::` one. *)
let colon_closer line =
  let n = String.length line in
  let rec colons i = if i < n && line.[i] = ':' then colons (i + 1) else i in
  let c = colons 0 in
  if c >= 3 && String.trim (String.sub line c (n - c)) = "" then Some c else None

(* The body, up to the first eligible closer. Fenced regions inside are
   SKIPPED: a ``` fence containing `:::` describes the grammar. An
   opener with no closer clamps at end of input (mirror: Wiki_ast closes
   an unterminated fence at EOF) and every line is still returned. *)
let scan_block c lines =
  let rec go acc in_fence = function
    | [] -> (List.rev acc, None, [])
    | l :: rest ->
        if in_fence then go (l :: acc) (not (is_fence l)) rest
        else if is_fence l then go (l :: acc) true rest
        else (
          match colon_closer l with
          | Some k when k >= c -> (List.rev acc, Some l, rest)
          | Some _ | None -> go (l :: acc) false rest)
  in
  go [] false lines

(* ------------------------------------------------ HW.2.1.11 definitions *)

(* `[^id]: text` at COLUMN ZERO. *)
let footnote_def_line line =
  let n = String.length line in
  if n < 5 || line.[0] <> '[' || line.[1] <> '^' then None
  else
    let rec idend i = if i < n && is_id_char line.[i] then idend (i + 1) else i in
    let e = idend 2 in
    if e = 2 || e + 1 >= n || line.[e] <> ']' || line.[e + 1] <> ':' then None
    else Some (String.sub line 2 (e - 2), String.trim (String.sub line (e + 2) (n - e - 2)))

(* The continuation: every following line up to and including the last
   INDENTED one before a non-blank line at column zero. Blank lines do
   not terminate it (mirror: Wiki_directive.scan_body). *)
let scan_body lines =
  let rec go i last = function
    | [] -> last
    | l :: rest ->
        if is_blank l then go (i + 1) last rest
        else if is_indented l then go (i + 1) i rest
        else last
  in
  go 0 (-1) lines

let dedent_body raw =
  let indent =
    List.fold_left (fun acc l -> if is_blank l then acc else min acc (indent_columns l)) max_int raw
  in
  let indent = if indent = max_int then 0 else indent in
  map_in_order
    (fun l ->
      if is_blank l then ""
      else
        let n = String.length l in
        let rec cut i col = if i < n && col < indent then
            cut (i + 1) (match l.[i] with '\t' -> col + (4 - (col mod 4)) | _ -> col + 1)
          else i
        in
        let i = cut 0 0 in
        String.sub l i (n - i))
    raw

let is_toc_line line =
  let t = String.trim line in
  t = "[TOC]" || t = "[toc]"

(* ---------------------------------------------------------------- parse *)

let rec parse_nodes lines =
  let nodes = ref [] and run = ref [] in
  let flush () =
    if !run <> [] then begin
      nodes := Text (List.rev !run) :: !nodes;
      run := []
    end
  in
  let emit n =
    flush ();
    nodes := n :: !nodes
  in
  let rec go = function
    | [] -> ()
    | line :: rest ->
        if is_fence line then begin
          let rec close acc = function
            | [] -> (List.rev acc, [])
            | l :: r when is_fence l -> (List.rev (l :: acc), r)
            | l :: r -> close (l :: acc) r
          in
          let fenced, after = close [ line ] rest in
          emit (Fenced fenced);
          go after
        end
        else
          match colon_opener line with
          | Some (c, name, k, fold, title) ->
              let body_source, closer, after = scan_block c rest in
              emit
                (Block
                   { name; kind = k; colons = c; title; fold; opener = line; closer;
                     body = parse_nodes body_source; body_source });
              go after
          | None -> (
              match footnote_def_line line with
              | Some (id, first) ->
                  let last = scan_body rest in
                  let raw = if last < 0 then [] else take (last + 1) rest in
                  emit
                    (Note_def
                       { did = id; dtext = first :: dedent_body raw; dsource = line :: raw });
                  go (if last < 0 then rest else drop (last + 1) rest)
              | None ->
                  if is_toc_line line then begin
                    emit (Toc_marker line);
                    go rest
                  end
                  else begin
                    run := line :: !run;
                    go rest
                  end)
  in
  go lines;
  flush ();
  List.rev !nodes

let rec source_of_node = function
  | Text ls -> ls
  | Fenced ls -> ls
  | Toc_marker l -> [ l ]
  | Note_def d -> d.dsource
  | Block b ->
      (b.opener :: List.concat_map source_of_node b.body)
      @ (match b.closer with Some c -> [ c ] | None -> [])

let source_lines t = List.concat_map source_of_node t.nodes

let rec blocks_of_node = function
  | Block b -> b :: List.concat_map blocks_of_node b.body
  | Text _ | Fenced _ | Toc_marker _ | Note_def _ -> []

let all_blocks t = List.concat_map blocks_of_node t.nodes

let blocks t =
  List.filter_map
    (function Block b -> Some b | Text _ | Fenced _ | Toc_marker _ | Note_def _ -> None)
    t.nodes

let body_blocks b = parse_lists (String.concat "\n" b.body_source)

(* ---------------------------------------------- HW.2.1.11 the reference

   Fence-awareness is structural (a fenced region is a [Fenced] node and
   contributes no text); inline backticks are excluded HERE, per line,
   which is the same limit every other scanner in this engine carries. *)

let rec text_lines_of_node = function
  | Text ls -> ls
  | Block b -> List.concat_map text_lines_of_node b.body
  | Fenced _ | Toc_marker _ | Note_def _ -> []

let refs_of_line line =
  let n = String.length line in
  let out = ref [] and i = ref 0 and in_code = ref false in
  while !i < n do
    if line.[!i] = '`' then begin
      in_code := not !in_code;
      incr i
    end
    else if (not !in_code) && line.[!i] = '[' && !i + 1 < n && line.[!i + 1] = '^' then begin
      let j = ref (!i + 2) in
      while !j < n && is_id_char line.[!j] do
        incr j
      done;
      if !j > !i + 2 && !j < n && line.[!j] = ']' then begin
        let is_def = !i = 0 && !j + 1 < n && line.[!j + 1] = ':' in
        if not is_def then out := String.sub line (!i + 2) (!j - !i - 2) :: !out;
        i := !j + 1
      end
      else i := !j
    end
    else incr i
  done;
  List.rev !out

let rec defs_of_node = function
  | Note_def d -> [ d ]
  | Block b -> List.concat_map defs_of_node b.body
  | Text _ | Fenced _ | Toc_marker _ -> []

(* ORDER IS BY FIRST REFERENCE. Moving a definition to the bottom of the
   file must not renumber the page, so the definition list is consulted
   only for CONTENT, never for position. *)
let collect_notes nodes =
  let defs = List.concat_map defs_of_node nodes in
  let refs = List.concat_map (fun n -> List.concat_map refs_of_line (text_lines_of_node n)) nodes in
  let order = dedup refs in
  let count id = List.length (List.filter (fun r -> r = id) refs) in
  let notes =
    List.rev
      (snd
         (List.fold_left
            (fun (i, acc) id ->
              let d = List.find_opt (fun d -> d.did = id) defs in
              ( i + 1,
                { fid = id;
                  label = i;
                  definition = (match d with Some d -> d.dtext | None -> []);
                  defined = d <> None;
                  refs = count id }
                :: acc ))
            (1, []) order))
  in
  (notes, defs)

(* ------------------------------------------------------ HW.2.3.5 the toc *)

(* MIRROR of Hermes_wiki.make_slugger, including the detail that matters:
   the generated candidate is CLAIMED and the base counter MOVES, so
   `a`, `a-1`, `a` yields `a`, `a-1`, `a-2` and never a second `a-1`. A
   ToC computed with a plain slugify would collide on the second heading
   of the same name and link to the first. *)
let make_slugger () =
  let seen : (string, int) Hashtbl.t = Hashtbl.create 32 in
  fun text ->
    let base =
      let s = Hermes_wiki.slugify text in
      if s = "" then "section" else s
    in
    match Hashtbl.find_opt seen base with
    | None ->
        Hashtbl.replace seen base 0;
        base
    | Some n ->
        let rec next k =
          let candidate = Printf.sprintf "%s-%d" base k in
          if Hashtbl.mem seen candidate then next (k + 1)
          else begin
            Hashtbl.replace seen base k;
            Hashtbl.replace seen candidate 0;
            candidate
          end
        in
        next (n + 1)

(* The heading sequence in the order [Wiki_ast.render] walks it — inside
   a quote, a callout and a list item too, because the renderer anchors
   those. Any other order would desynchronise the slugger. *)
let rec headings_of_block = function
  | Wiki_ast.Heading { level; text } -> [ (level, text) ]
  | Wiki_ast.Quote body -> headings_of_blocks body
  | Wiki_ast.Callout { body; _ } -> headings_of_blocks body
  | Wiki_ast.List_block { content; _ } ->
      List.concat_map
        (function
          | Wiki_ast.Item i -> headings_of_blocks i.Wiki_ast.body
          | Wiki_ast.Loose b -> headings_of_block b)
        content
  | Wiki_ast.Inline_run _ | Wiki_ast.Para _ | Wiki_ast.Rule | Wiki_ast.Fence _ | Wiki_ast.Table _ ->
      []

and headings_of_blocks bs = List.concat_map headings_of_block bs

let headings text = headings_of_blocks (Wiki_ast.parse text)

let toc text =
  let slug = make_slugger () in
  map_in_order (fun (level, t) -> { level; text = t; anchor = slug t }) (headings text)

let rec has_marker_node = function
  | Toc_marker _ -> true
  | Block b -> List.exists has_marker_node b.body
  | Text _ | Fenced _ | Note_def _ -> false

let toc_html ~escape entries =
  let b = Buffer.create 256 in
  Buffer.add_string b "<nav class=\"toc\">\n<ul>\n";
  List.iter
    (fun e ->
      Buffer.add_string b
        (Printf.sprintf "<li class=\"toc-l%d\"><a href=\"#%s\">%s</a></li>\n" e.level e.anchor
           (escape e.text)))
    entries;
  Buffer.add_string b "</ul>\n</nav>\n";
  Buffer.contents b

(* Attribute values, scanned out of markup. Used to CHECK the two link
   laws against real render output rather than to assert them. *)
let attr_values needle html =
  let nn = String.length needle and n = String.length html in
  let out = ref [] and i = ref 0 in
  while !i + nn <= n do
    if String.sub html !i nn = needle then begin
      let j = ref (!i + nn) in
      while !j < n && html.[!j] <> '"' do
        incr j
      done;
      out := String.sub html (!i + nn) (!j - !i - nn) :: !out;
      i := !j + 1
    end
    else incr i
  done;
  List.rev !out

let ids_of_html html = attr_values "id=\"" html
let fragments_of_html html = attr_values "href=\"#" html
let emitted_ids text = ids_of_html (Hermes_wiki.render_markdown ~resolve:(fun _ -> None) text)

let toc_resolves text =
  let ids = emitted_ids text in
  List.for_all (fun e -> List.mem e.anchor ids) (toc text)

(* ------------------------------------------------- HW.2.1.11 the pairing *)

let note_anchor id = "fn-" ^ id
let ref_anchor id n = if n <= 1 then "fnref-" ^ id else Printf.sprintf "fnref-%s-%d" id n

(* The marker substituter, stateful across the whole document because the
   n-th reference to an id needs its own anchor. *)
let ref_substituter notes =
  let counts : (string, int) Hashtbl.t = Hashtbl.create 8 in
  fun line ->
    let n = String.length line in
    let out = Buffer.create (n + 32) in
    let i = ref 0 and in_code = ref false in
    while !i < n do
      if line.[!i] = '`' then begin
        in_code := not !in_code;
        Buffer.add_char out '`';
        incr i
      end
      else if (not !in_code) && line.[!i] = '[' && !i + 1 < n && line.[!i + 1] = '^' then begin
        let j = ref (!i + 2) in
        while !j < n && is_id_char line.[!j] do
          incr j
        done;
        let id = String.sub line (!i + 2) (!j - !i - 2) in
        let is_def = !i = 0 && !j + 1 < n && line.[!j + 1] = ':' in
        let note =
          if !j > !i + 2 && !j < n && line.[!j] = ']' && not is_def then
            List.find_opt (fun f -> f.fid = id) notes
          else None
        in
        match note with
        | Some f ->
            let k = match Hashtbl.find_opt counts id with Some k -> k + 1 | None -> 1 in
            Hashtbl.replace counts id k;
            Buffer.add_string out
              (Printf.sprintf "<sup class=\"footnote-ref\" id=\"%s\"><a href=\"#%s\">%d</a></sup>"
                 (ref_anchor id k) (note_anchor id) f.label);
            i := !j + 1
        | None ->
            Buffer.add_char out line.[!i];
            incr i
      end
      else begin
        Buffer.add_char out line.[!i];
        incr i
      end
    done;
    Buffer.contents out

(* An UNDEFINED reference still renders, still links, and lands on a note
   that says the definition is missing. Silence would make a missing note
   indistinguishable from a note that says nothing. *)
let footnotes_html ~inline notes =
  match notes with
  | [] -> ""
  | _ :: _ ->
      let b = Buffer.create 512 in
      Buffer.add_string b "<section class=\"footnotes\">\n<ol>\n";
      List.iter
        (fun f ->
          Buffer.add_string b (Printf.sprintf "<li id=\"%s\">\n<p>" (note_anchor f.fid));
          (if f.defined then
             Buffer.add_string b
               (inline (String.concat " " (List.filter (fun l -> String.trim l <> "") f.definition)))
           else
             Buffer.add_string b (Printf.sprintf "footnote definition missing: %s" f.fid));
          for k = 1 to f.refs do
            Buffer.add_string b
              (Printf.sprintf " <a class=\"footnote-back\" href=\"#%s\">&#8617;</a>"
                 (ref_anchor f.fid k))
          done;
          Buffer.add_string b "</p>\n</li>\n")
        notes;
      Buffer.add_string b "</ol>\n</section>\n";
      Buffer.contents b

(* ---------------------------------------------------------- diagnostics *)

let footnote_diagnostics notes defs =
  let undefined =
    List.filter_map (fun f -> if f.defined then None else Some (Undefined_footnote f.fid)) notes
  in
  let referenced = List.map (fun f -> f.fid) notes in
  let unreferenced =
    List.filter_map
      (fun id -> if List.mem id referenced then None else Some (Unreferenced_footnote id))
      (dedup (List.map (fun d -> d.did) defs))
  in
  let duplicates =
    let ids = List.map (fun d -> d.did) defs in
    List.filter_map
      (fun id -> if List.length (List.filter (fun x -> x = id) ids) > 1 then Some (Duplicate_footnote id) else None)
      (dedup ids)
  in
  undefined @ unreferenced @ duplicates

let unrecognised_diagnostics ~registered bs =
  dedup
    (List.filter_map
       (fun b ->
         match b.kind with
         | Unrecognised n ->
             if List.mem (String.lowercase_ascii b.name) registered then None
             else Some (Unrecognised_directive n)
         | Admonition _ | Toggle _ -> None)
       bs)

let lint ?(registered = []) t =
  let reg = List.map String.lowercase_ascii registered in
  let bs = all_blocks t in
  let used = dedup (List.map (fun b -> String.lowercase_ascii b.name) bs) in
  let unused =
    List.filter_map
      (fun r -> if List.mem (String.lowercase_ascii r) used then None else Some (Unused_directive r))
      registered
  in
  unrecognised_diagnostics ~registered:reg bs @ unused

let parse text =
  let nodes = parse_nodes (lines_of text) in
  let notes, defs = collect_notes nodes in
  let t0 = { nodes; notes; diagnostics = [] } in
  let unclosed =
    List.filter_map (fun b -> if b.closer = None then Some (Unclosed_block b.name) else None)
      (all_blocks t0)
  in
  let toc_gap =
    if List.exists has_marker_node nodes && headings text = [] then [ Toc_without_headings ] else []
  in
  { t0 with
    diagnostics =
      unclosed @ unrecognised_diagnostics ~registered:[] (all_blocks t0)
      @ footnote_diagnostics notes defs @ toc_gap }

let has_toc_marker text = List.exists has_marker_node (parse text).nodes

(* -------------------------------------------------------------- render *)

let callout_header (b : block) =
  { Wiki_callout.kind = Wiki_callout.kind_of_string (kind_name b.kind);
    title = b.title;
    fold =
      (match b.fold with
      | Plain -> Wiki_callout.Plain
      | Open -> Wiki_callout.Expanded
      | Closed -> Wiki_callout.Collapsed) }

let html ?(hide_toc = false) ~inline ~escape text =
  let t = parse text in
  let entries = toc text in
  let anchor = make_slugger () in
  let subst = ref_substituter t.notes in
  let buf = Buffer.create (String.length text * 2) in
  let render_md md = Wiki_ast.render ~inline ~anchor ~escape (parse_lists md) in
  let rec node = function
    | Text ls -> Buffer.add_string buf (render_md (String.concat "\n" (map_in_order subst ls)))
    | Fenced ls -> Buffer.add_string buf (render_md (String.concat "\n" ls))
    (* HW.1.3.15: the ONLY thing the flag changes. The slugger has
       already been threaded through the heading walk, so anchors are
       unaffected by construction rather than by care. *)
    | Toc_marker _ -> if not hide_toc then Buffer.add_string buf (toc_html ~escape entries)
    | Note_def _ -> ()
    | Block b ->
        (* the body is rendered FIRST and handed over as bytes, so the
           shared emitter never parses markdown (Wiki_ast's discipline) *)
        let saved = Buffer.contents buf in
        Buffer.clear buf;
        List.iter node b.body;
        let inner = Buffer.contents buf in
        Buffer.clear buf;
        Buffer.add_string buf saved;
        Buffer.add_string buf (Wiki_callout.html ~escape ~inline (callout_header b) ~body:inner)
  in
  List.iter node t.nodes;
  Buffer.add_string buf (footnotes_html ~inline t.notes);
  Buffer.contents buf

let footnote_links_resolve text =
  let h = html ~inline:(fun s -> s) ~escape:(fun s -> s) text in
  let ids = ids_of_html h in
  let notes = (parse text).notes in
  List.for_all
    (fun f -> not (starts_with "fn-" f || starts_with "fnref-" f) || List.mem f ids)
    (fragments_of_html h)
  && List.for_all
       (fun n ->
         List.mem (note_anchor n.fid) ids
         && List.for_all (fun k -> List.mem (ref_anchor n.fid k) ids)
              (List.init n.refs (fun k -> k + 1)))
       notes
