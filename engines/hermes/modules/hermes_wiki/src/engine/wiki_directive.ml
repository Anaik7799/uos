(* The Sphinx directive family. See the mli for the six rows, the
   column-zero `.. name::` decision, the preservation law, and why
   HW.2.6.2's law is negative. Pure: text in, structured value out. *)

(* ------------------------------------------------------------- the six *)

type kind =
  | Seealso
  | Rubric
  | Productionlist
  | Only
  | Authorship of string
  | Unknown of string

(* Written as data rather than a match so the vocabulary is readable at
   a glance and countable by a test (mirror: Wiki_callout.vocabulary). *)
let vocabulary = [ (Seealso, "seealso"); (Rubric, "rubric");
                   (Productionlist, "productionlist"); (Only, "only") ]

let authorship_roles = [ "sectionauthor"; "moduleauthor"; "codeauthor" ]

let kind_of_name s =
  let lower = String.lowercase_ascii (String.trim s) in
  match List.find_opt (fun (_, n) -> n = lower) vocabulary with
  | Some (k, _) -> k
  | None -> if List.mem lower authorship_roles then Authorship lower else Unknown (String.trim s)

let kind_name = function
  | Authorship s -> s
  | Unknown s -> s
  | (Seealso | Rubric | Productionlist | Only) as k -> (
      match List.find_opt (fun (k', _) -> k' = k) vocabulary with
      | Some (_, n) -> n
      | None -> "")

type directive = {
  kind : kind;
  name : string;
  argument : string;
  fields : (string * string) list;
  body : string list;
  source : string list;
}

type node =
  | Text of string list
  | Heading of { level : int; text : string; source : string }
  | Fenced of string list
  | Block of directive

type diagnostic =
  | Unknown_directive of string
  | Missing_argument of string
  | Decorative_seealso of string
  | Undefined_production of string * string
  | Malformed_production of string
  | Undeclared_tag of string
  | Malformed_condition of string
  | Docinfo_conflict of string

let diagnostic_line = function
  | Unknown_directive n -> Printf.sprintf "unknown directive preserved verbatim: .. %s::" n
  | Missing_argument n -> Printf.sprintf "directive written bare, argument required: .. %s::" n
  | Decorative_seealso l ->
      Printf.sprintf "seealso links nowhere (decoration, not a cross-reference): %s" l
  | Undefined_production (g, n) ->
      Printf.sprintf "production reference undefined in grammar %s: %s"
        (if g = "" then "(unnamed)" else g) n
  | Malformed_production l -> Printf.sprintf "productionlist line is not `name: definition`: %s" l
  | Undeclared_tag t -> Printf.sprintf "only: tag neither declared nor active, evaluates false: %s" t
  | Malformed_condition e ->
      Printf.sprintf "only: expression does not parse, content excluded: %s"
        (if e = "" then "(empty)" else e)
  | Docinfo_conflict f -> Printf.sprintf "docinfo field also declared in frontmatter: %s" f

type t = {
  frontmatter : string list;
  preamble : string list;
  docinfo : (string * string) list;
  docinfo_source : string list;
  nodes : node list;
  excluded : (string * string list) list;
  diagnostics : diagnostic list;
}

type production = { grammar : string; pname : string; definition : string; refs : string list }

(* --------------------------------------------------------------- lexis *)

let lines_of text = String.split_on_char '\n' text

(* Mirror of Hermes_wiki.is_fence and Wiki_transclude.is_fence: the same
   fence grammar in all three, so a document cannot be fenced for one
   reader and open for another. *)
let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

let is_blank line = String.trim line = ""
let is_indented line = String.length line > 0 && (line.[0] = ' ' || line.[0] = '\t')

let indent_of line =
  let n = String.length line in
  let rec go i = if i < n && (line.[i] = ' ' || line.[i] = '\t') then go (i + 1) else i in
  go 0

let drop_indent k line =
  let n = String.length line in
  if n <= k then "" else String.sub line k (n - k)

let strip_blank_edges ls =
  let rec front = function l :: rest when is_blank l -> front rest | rest -> rest in
  List.rev (front (List.rev (front ls)))

let ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '-' || c = '.'

(* THE MARKER, at column zero. `.. name:: argument`. Not trimmed first:
   an indented copy is a directive BODY line, and a copy preceded by a
   backtick is prose about the grammar (the mli's inline-code case). *)
let marker_of_line line =
  let n = String.length line in
  if n < 5 || line.[0] <> '.' || line.[1] <> '.' || line.[2] <> ' ' then None
  else
    let rec find i =
      if i + 2 > n then None
      else if line.[i] = ':' && line.[i + 1] = ':' then Some i
      else find (i + 1)
    in
    match find 3 with
    | None -> None
    | Some i ->
        let name = String.trim (String.sub line 3 (i - 3)) in
        if name = "" || not (String.for_all ident_char name) then None
        else
          let argument = String.trim (drop_indent (i + 2) line) in
          Some (name, argument)

let heading_of_line line =
  let n = String.length line in
  let rec hashes i = if i < n && line.[i] = '#' then hashes (i + 1) else i in
  let k = hashes 0 in
  if k >= 1 && k <= 6 && k < n && (line.[k] = ' ' || line.[k] = '\t') then
    Some (k, String.trim (drop_indent k line))
  else None

(* A field-list line, `:name: value`. The closing colon must be followed
   by a space or end of line, which is what keeps an RST inline role —
   `:doc:`target`` — from being read as a field. Names lowercased
   (docinfo keys are identities, not prose); values verbatim. *)
let field_of_line line =
  let n = String.length line in
  if n < 3 || line.[0] <> ':' then None
  else
    let rec find i =
      if i >= n then None else if line.[i] = ':' then Some i else find (i + 1)
    in
    match find 1 with
    | None -> None
    | Some j ->
        let name = String.sub line 1 (j - 1) in
        let ok_char c =
          (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
          || c = '_' || c = '-' || c = ' '
        in
        if String.trim name = "" || not (String.for_all ok_char name) then None
        else if j + 1 < n && line.[j + 1] <> ' ' && line.[j + 1] <> '\t' then None
        else
          Some
            ( String.lowercase_ascii (String.trim name),
              String.trim (drop_indent (j + 1) line) )

let leading_fields ls =
  let rec go acc = function
    | l :: rest -> (
        match field_of_line l with
        | Some kv -> go (kv :: acc) rest
        | None -> (List.rev acc, l :: rest))
    | [] -> (List.rev acc, [])
  in
  go [] ls

(* -------------------------------------------------------------- parsing *)

(* One pass with an explicit cursor over the line list (mirror: the
   Hermes_wiki line machine and Wiki_ast.parse). Every input line lands
   in exactly one node, verbatim — that is the preservation law, and it
   is why the body scan records [source] separately from the de-indented
   [body] it also computes. *)

(* The body of a directive: every following line up to, and including,
   the last INDENTED line before a non-blank line at column zero. Blank
   lines do NOT terminate a body; an unterminated body clamps to end of
   input (mirror: Wiki_ast closes an unterminated fence at EOF). *)
let scan_body lines =
  let rec go i last = function
    | [] -> last
    | l :: rest ->
        if is_blank l then go (i + 1) last rest
        else if is_indented l then go (i + 1) i rest
        else last
  in
  go 0 (-1) lines

let rec take n = function
  | [] -> []
  | l :: rest -> if n > 0 then l :: take (n - 1) rest else []

let rec drop n = function
  | [] -> []
  | _ :: rest as all -> if n > 0 then drop (n - 1) rest else all

let directive_of ~name ~argument ~marker ~raw_body =
  let body_indent =
    List.fold_left
      (fun acc l -> if is_blank l then acc else min acc (indent_of l))
      max_int raw_body
  in
  let body_indent = if body_indent = max_int then 0 else body_indent in
  let dedented = List.map (fun l -> if is_blank l then "" else drop_indent body_indent l) raw_body in
  let fields, rest = leading_fields (strip_blank_edges dedented) in
  { kind = kind_of_name name;
    name;
    argument;
    fields;
    body = strip_blank_edges rest;
    source = marker :: raw_body }

let parse_nodes lines =
  let nodes = ref [] and run = ref [] in
  let flush () = if !run <> [] then (nodes := Text (List.rev !run) :: !nodes; run := []) in
  let emit n = flush (); nodes := n :: !nodes in
  let rec go lines =
    match lines with
    | [] -> ()
    | line :: rest ->
        if is_fence line then begin
          (* the fenced region is INERT: a directive inside it is an
             example of the grammar, not a use of it *)
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
          match marker_of_line line with
          | Some (name, argument) ->
              let last = scan_body rest in
              let raw_body = if last < 0 then [] else take (last + 1) rest in
              emit (Block (directive_of ~name ~argument ~marker:line ~raw_body));
              go (if last < 0 then rest else drop (last + 1) rest)
          | None -> (
              match heading_of_line line with
              | Some (level, text) ->
                  emit (Heading { level; text; source = line });
                  go rest
              | None ->
                  run := line :: !run;
                  go rest)
  in
  go lines;
  flush ();
  List.rev !nodes

(* ---------------------------------------------------- productions (2.6.4) *)

(* The `backticked` names a definition references. A QUALIFIED ref
   (`other:name`) addresses a grammar this document may not hold and is
   out of scope by declaration, not by accident. *)
let refs_of_definition def =
  let n = String.length def in
  let out = ref [] in
  let i = ref 0 in
  while !i < n do
    if def.[!i] = '`' then begin
      let j = ref (!i + 1) in
      while !j < n && def.[!j] <> '`' do incr j done;
      if !j < n then begin
        let tok = String.trim (String.sub def (!i + 1) (!j - !i - 1)) in
        if tok <> "" && not (String.contains tok ':') then out := tok :: !out;
        i := !j + 1
      end
      else i := n
    end
    else incr i
  done;
  List.rev !out

(* Productions of one block, plus its malformed lines. A line still
   indented after de-indentation continues the previous definition. *)
let productions_of_directive d =
  let acc = ref [] and bad = ref [] in
  List.iter
    (fun line ->
      if is_blank line then ()
      else if is_indented line then
        match !acc with
        | p :: rest -> acc := { p with definition = p.definition ^ " " ^ String.trim line } :: rest
        | [] -> bad := line :: !bad
      else
        match String.index_opt line ':' with
        | Some j when j > 0 ->
            acc :=
              { grammar = d.argument;
                pname = String.trim (String.sub line 0 j);
                definition = String.trim (drop_indent (j + 1) line);
                refs = [] }
              :: !acc
        | Some _ | None -> bad := line :: !bad)
    d.body;
  ( List.rev_map (fun p -> { p with refs = refs_of_definition p.definition }) !acc,
    List.rev !bad )

let block_directives nodes =
  List.filter_map
    (function
      | Block d -> Some d
      | Text _ | Heading _ | Fenced _ -> None)
    nodes

let productions_of_nodes nodes =
  List.concat_map
    (fun d ->
      match d.kind with
      | Productionlist -> fst (productions_of_directive d)
      | Seealso | Rubric | Only | Authorship _ | Unknown _ -> [])
    (block_directives nodes)

let undefined_of_nodes nodes =
  let all = productions_of_nodes nodes in
  let defined g name = List.exists (fun p -> p.grammar = g && p.pname = name) all in
  List.concat_map
    (fun p -> List.filter_map (fun r -> if defined p.grammar r then None else Some (p.grammar, r))
                p.refs)
    all
  |> List.sort_uniq compare

(* -------------------------------------------------------- edges (2.6.1) *)

(* The SAME extraction Hermes_wiki uses for page.outlinks — fence- and
   inline-code-aware payloads, then slugify o strip_fragment — so a
   seealso edge is a page outlink by construction and the two cannot
   drift. Reuse, not a second implementation. *)
let targets_of_body body =
  Hermes_wiki.raw_link_targets (String.concat "\n" body)
  |> List.map (fun t -> Hermes_wiki.slugify (Hermes_wiki.strip_fragment t))
  |> List.filter (fun t -> t <> "")

let dedup xs =
  List.rev (List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] xs)

(* The ARGUMENT counts as an entry too: `.. seealso:: [[alpha]]` is the
   one-line form an author reaches for, and reading only the body would
   make it render, link nowhere, and be reported as decoration. *)
let seealso_targets d = targets_of_body (d.argument :: d.body)

let edges_of_nodes ~source nodes =
  List.concat_map
    (fun d ->
      match d.kind with
      | Seealso -> seealso_targets d
      | Rubric | Productionlist | Only | Authorship _ | Unknown _ -> [])
    (block_directives nodes)
  |> dedup
  |> List.map (fun t -> (source, t))

(* ----------------------------------------------------------- diagnostics *)

let analyse ~frontmatter ~docinfo nodes =
  let of_docinfo =
    List.filter_map
      (fun (k, _) -> if List.mem k frontmatter then Some (Docinfo_conflict k) else None)
      docinfo
  in
  let of_directives =
    List.concat_map
      (fun d ->
        let bare = if d.argument = "" then [ Missing_argument d.name ] else [] in
        match d.kind with
        | Seealso ->
            if seealso_targets d = [] then
              [ Decorative_seealso
                  (match List.filter (fun l -> not (is_blank l)) (d.argument :: d.body) with
                  | l :: _ -> l
                  | [] -> "") ]
            else []
        | Rubric | Only -> bare
        | Productionlist -> bare @ List.map (fun l -> Malformed_production l)
                                     (snd (productions_of_directive d))
        | Authorship _ -> bare
        | Unknown n -> [ Unknown_directive n ])
      (block_directives nodes)
  in
  let of_productions =
    List.map (fun (g, n) -> Undefined_production (g, n)) (undefined_of_nodes nodes)
  in
  of_docinfo @ of_directives @ of_productions

(* ---------------------------------------------------------------- parse *)

let split_preamble lines =
  match lines with
  | first :: rest when String.trim first = "---" ->
      let rec go acc = function
        | [] -> (None, lines)
        | l :: r when String.trim l = "---" -> (Some (List.rev (l :: acc)), r)
        | l :: r -> go (l :: acc) r
      in
      let taken, after = go [ first ] rest in
      (match taken with Some block -> (block, after) | None -> ([], lines))
  | [] | _ :: _ -> ([], lines)

let preamble_keys block =
  List.filter_map
    (fun l ->
      if String.trim l = "---" then None
      else
        match String.index_opt l ':' with
        | Some j when j > 0 && not (is_indented l) ->
            Some (String.lowercase_ascii (String.trim (String.sub l 0 j)))
        | Some _ | None -> None)
    block

let parse ?(frontmatter = []) text =
  let all = lines_of text in
  let preamble, rest = split_preamble all in
  let fm =
    List.sort_uniq compare (List.map String.lowercase_ascii frontmatter @ preamble_keys preamble)
  in
  (* DOCINFO is a document-leading construct: the field run at the top of
     the body, and nowhere else. It is MOVED out of the node list, so it
     cannot render twice; docinfo_source keeps its bytes. *)
  let docinfo, body = leading_fields rest in
  let docinfo_source = take (List.length docinfo) rest in
  let nodes = parse_nodes body in
  { frontmatter = fm;
    preamble;
    docinfo;
    docinfo_source;
    nodes;
    excluded = [];
    diagnostics = analyse ~frontmatter:fm ~docinfo nodes }

let source_of_node = function
  | Text ls -> ls
  | Heading { source; _ } -> [ source ]
  | Fenced ls -> ls
  | Block d -> d.source

let source_lines t = t.preamble @ t.docinfo_source @ List.concat_map source_of_node t.nodes
let directives t = block_directives t.nodes

(* ---------------------------------------------- only: the tag expression *)

exception Bad_condition

let tokens_of s =
  let buf = Buffer.create 16 and out = ref [] in
  let flush () =
    if Buffer.length buf > 0 then (out := Buffer.contents buf :: !out; Buffer.clear buf)
  in
  String.iter
    (fun c ->
      match c with
      | '(' | ')' -> flush (); out := String.make 1 c :: !out
      | ' ' | '\t' -> flush ()
      | c -> Buffer.add_char buf c)
    s;
  flush ();
  List.rev !out

let is_tag t =
  t <> "" && t <> "and" && t <> "or" && t <> "not" && String.for_all ident_char t

(* Sphinx's grammar: tags, `and`, `or`, `not`, parentheses. Every tag is
   looked up even when the value is already decided — an undeclared tag
   must be REPORTED whatever the outcome, or a build could switch on a
   vocabulary nobody wrote down. *)
let eval_condition ~universe ~active expr =
  let seen = ref [] in
  let rec p_expr ts =
    let v, ts = p_term ts in
    match ts with
    | "or" :: rest -> let v2, ts2 = p_expr rest in (v || v2, ts2)
    | [] | _ :: _ -> (v, ts)
  and p_term ts =
    let v, ts = p_factor ts in
    match ts with
    | "and" :: rest -> let v2, ts2 = p_term rest in (v && v2, ts2)
    | [] | _ :: _ -> (v, ts)
  and p_factor ts =
    match ts with
    | "not" :: rest -> let v, ts2 = p_factor rest in (not v, ts2)
    | "(" :: rest -> (
        let v, ts2 = p_expr rest in
        match ts2 with ")" :: r -> (v, r) | [] | _ :: _ -> raise Bad_condition)
    | t :: rest when is_tag t ->
        if not (List.mem t universe) then seen := t :: !seen;
        (List.mem t active, rest)
    | [] | _ :: _ -> raise Bad_condition
  in
  match p_expr (tokens_of expr) with
  | v, [] -> (Some v, List.rev !seen)
  | _, _ :: _ -> (None, List.rev !seen)
  | exception Bad_condition -> (None, List.rev !seen)

let rec select_nodes ~universe ~active nodes =
  List.fold_left
    (fun (ns, ex, dg) node ->
      match node with
      | Text _ | Heading _ | Fenced _ -> (node :: ns, ex, dg)
      | Block d -> (
          match d.kind with
          | Seealso | Rubric | Productionlist | Authorship _ | Unknown _ -> (node :: ns, ex, dg)
          | Only ->
              let verdict, undeclared = eval_condition ~universe ~active d.argument in
              let dg = dg @ List.map (fun t -> Undeclared_tag t) undeclared in
              (match verdict with
              | Some true ->
                  (* NESTS: the kept body is parsed and selected in turn,
                     and spliced, so a heading inside a kept conditional
                     is a heading of this build *)
                  let inner, ex2, dg2 = select_nodes ~universe ~active (parse_nodes d.body) in
                  (List.rev_append inner ns, ex @ ex2, dg @ dg2)
              | Some false ->
                  (ns, ex @ [ (d.argument, d.source) ], dg)
              | None ->
                  (ns, ex @ [ (d.argument, d.source) ], dg @ [ Malformed_condition d.argument ]))))
    ([], [], []) nodes
  |> fun (ns, ex, dg) -> (List.rev ns, ex, dg)

let select ~declared ~active t =
  let universe = List.sort_uniq compare (declared @ active) in
  let nodes, excluded, dg = select_nodes ~universe ~active t.nodes in
  { t with
    nodes;
    excluded = t.excluded @ excluded;
    diagnostics = analyse ~frontmatter:t.frontmatter ~docinfo:t.docinfo nodes @ dg }

let excluded_lines t = List.fold_left (fun n (_, ls) -> n + List.length ls) 0 t.excluded

(* ------------------------------------------------------------ observations *)

let edges ~source t = edges_of_nodes ~source t.nodes

let rubrics t =
  List.filter_map
    (fun d ->
      match d.kind with
      | Rubric -> Some d.argument
      | Seealso | Productionlist | Only | Authorship _ | Unknown _ -> None)
    (directives t)

(* Headings ONLY. A rubric is a label, not a destination; an authorship
   line is a byline. Neither is navigable, so neither is here. *)
let toc t =
  List.filter_map
    (function
      | Heading { level; text; _ } -> Some (level, text, Hermes_wiki.slugify text)
      | Text _ | Fenced _ | Block _ -> None)
    t.nodes

let anchors t = List.map (fun (_, _, a) -> a) (toc t)
let productions t = productions_of_nodes t.nodes
let undefined_productions t = undefined_of_nodes t.nodes

let authorship t =
  List.filter_map
    (fun d ->
      match d.kind with
      | Authorship role -> Some (role, d.argument)
      | Seealso | Rubric | Productionlist | Only | Unknown _ -> None)
    (directives t)
