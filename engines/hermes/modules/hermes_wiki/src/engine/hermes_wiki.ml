(* The Hermes wiki/ZK core. See hermes_wiki.mli. Ported shape from the
   zigvm docs_wiki model (R14): frontmatter -> meta, fence-aware link and
   tag extraction, contextual backlinks with the fst back_ctx == backlinks
   law, a line-machine markdown renderer with visibly-missing wikilinks.

   Laws imported from the zigvm WIKI_PIPELINE spec: the corpus is what git
   tracks (§3), the resolver registers four keys per note (§4), mentions
   are unlinked title occurrences (§4 pass 3), heading anchors are
   stateful per document and local (§6), and the frontmatter control panel
   carries decay signals (§6c). *)

type meta = {
  id : string;
  status : string;
  ntype : string;
  last_verified : string;
  verified_by : string;
  next_review : string;
  has_frontmatter : bool;
  allow_example_links : bool;
  generated : bool;
  migrated_from : string option;
  (* PKM schema, docs/hermes/specs/2026-08-09-pkm-longterm-architecture.md §3:
     two NEW AXES beside the discourse type and editorial status, plus the
     archival fields. Absent = "" or [] — honest defaults, never fabricated. *)
  aliases : string list;     (* additional resolver keys (HW.1.2.7) *)
  ktype : string;            (* artifact role: atomic | moc | source | journal *)
  maturity : string;         (* seed | incubating | evergreen | archived *)
  domain : string;           (* single controlled term *)
  topics : string list;      (* granular document-level tags *)
  links : string list;       (* DECLARED parent/child UIDs only — I3: the
                                body graph stays derived, never stored *)
  created : string;          (* R16: read from git/env, never invented *)
  visibility : string;       (* HW.1.4.1: draft | unlisted | listed; "" = unset *)
  orphan : bool;             (* HW.6.8.2: a disclosed entry point *)
  default_role : string;     (* HW.2.7.2: bare-`span` meaning; "code" = identity *)
  (* HW.1.3.10–13 — how a corpus is ORDERED and LABELLED. Read here so
     one frontmatter parser stays the only one; the laws live in
     Wiki_ordering. *)
  hide_toc : bool;           (* HW.1.3.15: PRESENTATION only — suppresses the
                                contents nav and NOTHING else *)
  keywords : string list;    (* HW.1.3.10: search terms ADDITIVE to the body's *)
  sidebar_position : int option;  (* HW.1.3.11; a malformed value is None *)
  sidebar_label : string;    (* HW.1.3.13: a fallback for the title, "" = unset *)
  slug_claim : string;       (* HW.1.2.6: a DECLARED slug, "" = unset *)
  description : string;      (* HW.1.3.9: declared summary, "" = unset *)
}

type page = {
  path : string;
  slug : string;
  title : string;
  group : string;
  meta : meta;
  html : string;
  outlinks : string list;
  mentions : string list;
  typed : (string * string) list;
  tags : string list;
  headings : (int * string * string) list;
  backlinks : string list;
  back_ctx : (string * string) list;
  frag_refs : (string * string) list;
  raw : string;
}

type model = {
  pages : page list;
  anomalies : string list;
  include_failures : string list;  (* HW.9.2.1, computed under build's reader *)
}

(* --------------------------------------------------------------- helpers *)

let slugify text =
  let lower = String.lowercase_ascii text in
  let buffer = Buffer.create (String.length lower) in
  String.iter
    (fun c ->
      if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_' then
        Buffer.add_char buffer c
      else if Buffer.length buffer > 0 && Buffer.nth buffer (Buffer.length buffer - 1) <> '-'
      then Buffer.add_char buffer '-')
    lower;
  let s = Buffer.contents buffer in
  let s =
    if String.length s > 0 && s.[String.length s - 1] = '-' then
      String.sub s 0 (String.length s - 1)
    else s
  in
  if String.length s > 0 && s.[0] = '-' then String.sub s 1 (String.length s - 1) else s

let escape_html text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string buffer "&amp;"
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;"
      | '"' -> Buffer.add_string buffer "&quot;"
      | c -> Buffer.add_char buffer c)
    text;
  Buffer.contents buffer

let lines_of text = String.split_on_char '\n' text

let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

let starts_with prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

(* Code is not prose (note_ref mask_code, mirrored): inline `spans` are
   blanked BEFORE reference extraction, offsets preserved, so a document
   quoting the grammar makes no phantom edge. Per-line pairing by the
   recorded zigvm decision — global pairing inverts on any unmatched
   backtick; the REAL limit (a span crossing a line break leaks) is
   pinned by test C4 rather than assumed away. *)
let mask_inline_spans line =
  let b = Bytes.of_string line in
  let n = Bytes.length b in
  let i = ref 0 in
  while !i < n do
    if Bytes.get b !i = '`' then begin
      let j = ref (!i + 1) in
      while !j < n && Bytes.get b !j <> '`' do incr j done;
      if !j < n then begin
        for k = !i to !j do Bytes.set b k ' ' done;
        i := !j + 1
      end
      else i := n
    end
    else incr i
  done;
  Bytes.to_string b

(* The collecting twin of [mask_inline_spans]: the CONTENTS of paired
   single-backtick spans, per-line pairing, same alphabet of decisions. *)
let line_span_contents line =
  let n = String.length line in
  let out = ref [] in
  let i = ref 0 in
  while !i < n do
    if line.[!i] = '`' then begin
      let j = ref (!i + 1) in
      while !j < n && line.[!j] <> '`' do incr j done;
      if !j < n then begin
        out := String.sub line (!i + 1) (!j - !i - 1) :: !out;
        i := !j + 1
      end
      else i := n
    end
    else incr i
  done;
  List.rev !out

let wikilink_payloads line =
  let rec go i acc =
    match String.index_from_opt line i '[' with
    | Some j when j + 1 < String.length line && line.[j + 1] = '[' -> (
        let rec close k =
          if k + 1 < String.length line then
            if line.[k] = ']' && line.[k + 1] = ']' then Some k else close (k + 1)
          else None
        in
        match close (j + 2) with
        | Some k -> go (k + 2) (String.sub line (j + 2) (k - j - 2) :: acc)
        | None -> List.rev acc)
    | Some j -> go (j + 1) acc
    | None -> List.rev acc
  in
  go 0 []

(* A #fragment addresses a section INSIDE a target; the graph edge is to
   the document, so the fragment is stripped when extracting links. *)
let strip_fragment target =
  match String.index_opt target '#' with
  | Some i when i > 0 -> String.sub target 0 i
  | _ -> target

(* The fragment half of the same split, [None] when the target addresses a
   whole document. HW.3.4.3 needs it: a [[Doc#Section]] whose document
   resolves but whose section does not is a DIFFERENT defect from a dead
   link, because it has a different fix. *)
let fragment_of target =
  match String.index_opt target '#' with
  | Some i when i > 0 && i + 1 < String.length target ->
      Some (String.sub target (i + 1) (String.length target - i - 1))
  | _ -> None

(* Percent-decoding, so `[[Doc#Real%20Section]]` and `[[Doc#Real Section]]`
   are the same reference. Sphinx's brokenLinks accepts both spellings; a
   validator that accepted only one would report a false defect on the
   other. An invalid escape is left verbatim rather than raising — this
   runs over author input. *)
let percent_decode s =
  let hex c =
    match c with
    | '0' .. '9' -> Some (Char.code c - Char.code '0')
    | 'a' .. 'f' -> Some (Char.code c - Char.code 'a' + 10)
    | 'A' .. 'F' -> Some (Char.code c - Char.code 'A' + 10)
    | _ -> None
  in
  let buffer = Buffer.create (String.length s) in
  let i = ref 0 in
  while !i < String.length s do
    (match (s.[!i], !i + 2 < String.length s) with
    | '%', true -> (
        match (hex s.[!i + 1], hex s.[!i + 2]) with
        | Some hi, Some lo ->
            Buffer.add_char buffer (Char.chr ((hi * 16) + lo));
            i := !i + 2
        | _ -> Buffer.add_char buffer s.[!i])
    | c, _ -> Buffer.add_char buffer c);
    incr i
  done;
  Buffer.contents buffer

(* CommonMark 4.1 — three or more of the same -, * or _, spaces allowed
   between. Deliberately NOT applied to the frontmatter delimiter: that is
   stripped before the body reaches the renderer, so the two uses of `---`
   never compete. *)
let is_thematic_break line =
  let t = String.trim line in
  match String.length t with
  | 0 -> false
  | _ ->
      let c = t.[0] in
      (c = '-' || c = '*' || c = '_')
      && String.for_all (fun ch -> ch = c || ch = ' ') t
      && String.length (String.concat "" (String.split_on_char ' ' t)) >= 3

(* CommonMark 5.2 — digits, then `.` or `)`, then a space. `10 items` is a
   paragraph, because the delimiter is not optional. *)
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

(* GFM 5.3 — a task list item is a list item whose content begins with
   `[ ]` or `[x]` followed by a space. *)
let task_marker item =
  if String.length item >= 4 && item.[0] = '[' && item.[2] = ']' && item.[3] = ' ' then
    match item.[1] with
    | ' ' -> Some (false, String.sub item 4 (String.length item - 4))
    | 'x' | 'X' -> Some (true, String.sub item 4 (String.length item - 4))
    | _ -> None
  else None

(* HW.3.7.1: ONE payload grammar (Wiki_ref) for extraction and BOTH
   renderers — the block_anchor_split discipline, one scale up. The
   (target, rel) shape is unchanged; role prefixes and the `!` opt-out
   are stripped by the shared grammar. *)
let split_payload payload =
  let r = Wiki_ref.parse payload in
  (r.Wiki_ref.target, r.Wiki_ref.rel)

let tags_of_line line =
  if starts_with "#" (String.trim line) then []
  else begin
    let n = String.length line in
    let rec go i acc =
      if i >= n then List.rev acc
      else if
        line.[i] = '#'
        && (i = 0 || line.[i - 1] = ' ' || line.[i - 1] = '\t')
        && i + 1 < n
        && (let c = line.[i + 1] in
            (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
      then begin
        let j = ref (i + 1) in
        while
          !j < n
          && (let c = line.[!j] in
              (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
              || (c >= '0' && c <= '9') || c = '-' || c = '_')
        do
          incr j
        done;
        go !j (String.lowercase_ascii (String.sub line (i + 1) (!j - i - 1)) :: acc)
      end
      else go (i + 1) acc
    in
    go 0 []
  end

(* ----------------------------------------------------------- frontmatter *)

let parse_frontmatter content =
  match lines_of content with
  | "---" :: rest -> (
      let rec split acc = function
        | "---" :: body -> Some (List.rev acc, body)
        | line :: more -> split (line :: acc) more
        | [] -> None
      in
      match split [] rest with
      | None -> ([], content)
      | Some (header, body) ->
          let fields =
            List.filter_map
              (fun line ->
                match String.index_opt line ':' with
                | Some i ->
                    Some
                      ( String.trim (String.sub line 0 i),
                        String.trim (String.sub line (i + 1) (String.length line - i - 1)) )
                | None -> None)
              header
          in
          (fields, String.concat "\n" body))
  | _ -> ([], content)

(* An inline YAML list: [a, "b c", d]. Unquotes items; a bare scalar is a
   one-item list, so `topics: pkm` and `topics: [pkm]` agree. Total. *)
let parse_inline_list value =
  let unquote s =
    let s = String.trim s in
    let n = String.length s in
    if n >= 2 && ((s.[0] = '"' && s.[n - 1] = '"') || (s.[0] = '\'' && s.[n - 1] = '\''))
    then String.sub s 1 (n - 2)
    else s
  in
  let v = String.trim value in
  let body =
    let n = String.length v in
    if n >= 2 && v.[0] = '[' && v.[n - 1] = ']' then String.sub v 1 (n - 2) else v
  in
  String.split_on_char ',' body
  |> List.map unquote
  |> List.filter (fun s -> s <> "")

let meta_of ?(has_frontmatter = false) fields slug =
  let get key = List.assoc_opt key fields in
  let text key = match get key with Some v -> v | None -> "" in
  let list key = match get key with Some v -> parse_inline_list v | None -> [] in
  { id = (match get "id" with Some v when v <> "" -> v | _ -> "hermes-" ^ slug);
    status = (match get "status" with Some v when v <> "" -> v | _ -> "published");
    ntype = (match get "type" with Some v when v <> "" -> v | _ -> "note");
    last_verified = text "last_verified";
    verified_by = text "verified_by";
    next_review = text "next_review";
    has_frontmatter;
    allow_example_links = get "allow_example_links" = Some "true";
    generated = get "generated" = Some "true";
    migrated_from = get "migrated_from";
    (* PKM schema — spec §3. ktype/maturity are new AXES; absent is "" *)
    aliases = list "aliases";
    ktype = text "ktype";
    maturity = text "maturity";
    domain = text "domain";
    topics = list "topics";
    links = list "links";
    created = text "created";
    orphan = get "orphan" = Some "true";
    visibility =
      (match get "visibility" with
      | Some v when v <> "" -> v
      | _ -> if get "draft" = Some "true" then "draft"
             else if get "unlisted" = Some "true" then "unlisted" else "");
    (* HW.2.7.2: what a bare `span` means — "code" (identity, the
       default) or "any" (a checked reference). Config, not PKM schema. *)
    default_role = (match get "default_role" with Some v when v <> "" -> v | _ -> "code");
    (* HW.1.3.10–13. A malformed sidebar_position CLAMPS to None rather
       than raising: a typo in one page's frontmatter must not take the
       whole corpus down, and an unordered page has a defined place. *)
    keywords = list "keywords";
    sidebar_position = (match get "sidebar_position" with
                        | Some v -> int_of_string_opt (String.trim v)
                        | None -> None);
    sidebar_label = text "sidebar_label";
    (* HW.1.2.6/1.3.9 — read here, so the corpus keeps ONE frontmatter
       parser. The LAWS over them live in Wiki_lifecycle: a declared slug
       wins but leaves a countable mark, and a description feeds ranking
       additively. This module only carries the claim. *)
    hide_toc = get "hide_table_of_contents" = Some "true";
    slug_claim = text "slug";
    description = text "description" }

(* -------------------------------------------------------------- renderer *)

let render_inline ?(default_role = "code") ?(resolve_term = fun _ -> None) ~resolve line =
  let escaped = escape_html line in
  (* The wiki scan as a PER-SEGMENT pass: it runs only on non-code
     segments below, so a backticked [[link]] stays literal — code is
     not prose on the render surface exactly as in the reference scan
     (the two must agree, or the dependency sheaf's L27.1 breaks). *)
  let wiki_pass s =
    let buffer = Buffer.create (String.length s) in
    let n = String.length s in
    let i = ref 0 in
    while !i < n do
      if !i + 1 < n && s.[!i] = '[' && s.[!i + 1] = '[' then (
        let rec close k =
          if k + 1 < n then if s.[k] = ']' && s.[k + 1] = ']' then Some k else close (k + 1)
          else None
        in
        match close (!i + 2) with
        | Some k ->
            let payload = String.sub s (!i + 2) (k - !i - 2) in
            let r = Wiki_ref.parse payload in
            let target = r.Wiki_ref.target in
            (* zigvm §6: a [[Doc#Section]] fragment is normalized PURELY —
               it references an anchor another document declared, so it
               must not consult this document's slugger state. *)
            let document, fragment =
              match String.index_opt target '#' with
              | Some h ->
                  ( String.sub target 0 h,
                    Some (String.sub target (h + 1) (String.length target - h - 1)) )
              | None -> (target, None)
            in
            (if r.Wiki_ref.suppress then
               (* HW.3.7.6: mentioned, not asserted — plain text, no link,
                  no missing-span, and never a warning. *)
               Buffer.add_string buffer target
             else
               (* HW.3.7.1 kind law at the render surface: a Term reference
                  resolves ONLY in the glossary space (HW.3.7.4) — the
                  wrong kind is a failure, not a fallback. A term's href
                  arrives complete (the term IS a location), so the
                  author-side fragment applies to doc references only. *)
               let resolved =
                 match r.Wiki_ref.kind with
                 | Wiki_ref.Term -> resolve_term (slugify document)
                 | Wiki_ref.Doc | Wiki_ref.Any -> (
                     match resolve (slugify document) with
                     | Some href ->
                         Some
                           (match fragment with
                           | Some f -> href ^ "#" ^ slugify f
                           | None -> href)
                     | None -> None)
               in
               match resolved with
               | Some href ->
                   (* HW.4.1.5: the RELATION reaches the surface. It was
                      parsed and then dropped here, so a typed edge
                      rendered identically to an untyped one and the
                      discourse dimension existed only in the model — an
                      edge whose type is invisible to a reader is an
                      untyped edge with extra syntax. *)
                   let rel_attr =
                     match r.Wiki_ref.rel with
                     | Some rel when rel <> "" -> Printf.sprintf " data-rel=\"%s\"" (escape_html rel)
                     | _ -> ""
                   in
                   Buffer.add_string buffer
                     (Printf.sprintf "<a href=\"%s\" class=\"wikilink\"%s>%s</a>" href rel_attr
                        target)
               | None ->
                   Buffer.add_string buffer
                     (Printf.sprintf "<span class=\"missing\">%s</span>" target));
            i := k + 2
        | None ->
            Buffer.add_char buffer s.[!i];
            incr i)
      else (
        Buffer.add_char buffer s.[!i];
        incr i)
    done;
    Buffer.contents buffer
  in
  let with_wiki =
    let parts = String.split_on_char '`' escaped in
    let buffer = Buffer.create (String.length escaped) in
    List.iteri
      (fun i part ->
        if i mod 2 = 1 then
          if default_role = "any" then (
            (* HW.2.7.2: under default_role any, the span IS a reference —
               checked like any other; identity under "code" is the
               unchanged branch below. *)
            match resolve (slugify part) with
            | Some href ->
                Buffer.add_string buffer
                  (Printf.sprintf "<a href=\"%s\" class=\"wikilink\">%s</a>" href part)
            | None ->
                Buffer.add_string buffer
                  (Printf.sprintf "<span class=\"missing\">%s</span>" part))
          else (
            Buffer.add_string buffer "<code>";
            Buffer.add_string buffer part;
            Buffer.add_string buffer "</code>")
        else Buffer.add_string buffer (wiki_pass part))
      parts;
    Buffer.contents buffer
  in
  let with_links =
    let buffer = Buffer.create (String.length with_wiki) in
    let s = with_wiki in
    let n = String.length s in
    let i = ref 0 in
    while !i < n do
      if s.[!i] = '[' then (
        match String.index_from_opt s !i ']' with
        | Some j when j + 1 < n && s.[j + 1] = '(' -> (
            match String.index_from_opt s (j + 1) ')' with
            | Some k ->
                let text = String.sub s (!i + 1) (j - !i - 1) in
                let url = String.sub s (j + 2) (k - j - 2) in
                Buffer.add_string buffer (Printf.sprintf "<a href=\"%s\">%s</a>" url text);
                i := k + 1
            | None ->
                Buffer.add_char buffer s.[!i];
                incr i)
        | _ ->
            Buffer.add_char buffer s.[!i];
            incr i)
      else (
        Buffer.add_char buffer s.[!i];
        incr i)
    done;
    Buffer.contents buffer
  in
  let bold s =
    let buffer = Buffer.create (String.length s) in
    let n = String.length s in
    let i = ref 0 and open_ = ref false in
    while !i < n do
      if !i + 1 < n && s.[!i] = '*' && s.[!i + 1] = '*' then (
        Buffer.add_string buffer (if !open_ then "</strong>" else "<strong>");
        open_ := not !open_;
        i := !i + 2)
      else (
        Buffer.add_char buffer s.[!i];
        incr i)
    done;
    if !open_ then Buffer.add_string buffer "</strong>";
    Buffer.contents buffer
  in
  (* GFM 6.5. Same paired-delimiter shape as bold; a lone `~` is literal,
     so `~b~` stays text. Runs after code extraction, so a tilde inside a
     fence or inline code is never a delimiter. *)
  let strike s =
    let buffer = Buffer.create (String.length s) in
    let n = String.length s in
    let i = ref 0 and open_ = ref false in
    while !i < n do
      if !i + 1 < n && s.[!i] = '~' && s.[!i + 1] = '~' then (
        Buffer.add_string buffer (if !open_ then "</del>" else "<del>");
        open_ := not !open_;
        i := !i + 2)
      else (
        Buffer.add_char buffer s.[!i];
        incr i)
    done;
    if !open_ then Buffer.add_string buffer "</del>";
    Buffer.contents buffer
  in
  strike (bold with_links)

(* zigvm §6: heading anchors are STATEFUL per document (first occurrence
   keeps its anchor, later collisions take -1, -2, …) and LOCAL — one
   slugger per document, so a single-page render and a whole-corpus
   render emit the same anchors. *)
let make_slugger () =
  let seen : (string, int) Hashtbl.t = Hashtbl.create 32 in
  fun text ->
    let base = let s = slugify text in if s = "" then "section" else s in
    match Hashtbl.find_opt seen base with
    | None ->
        Hashtbl.replace seen base 0;
        base
    | Some n ->
        let rec next k =
          let candidate = Printf.sprintf "%s-%d" base k in
          if Hashtbl.mem seen candidate then next (k + 1)
          else (
            Hashtbl.replace seen base k;
            Hashtbl.replace seen candidate 0;
            candidate)
        in
        next (n + 1)

(* The ORACLE (HW.2.0.1). This streaming line machine produced every page
   of this wiki, so its behaviour IS the specification. It stays
   permanently exercised: `test_wiki_ast` compares it against the AST path
   over the whole corpus. Deleting it would delete the specification. *)
(* HW.9.2.1: the injected reader becomes the slice resolver. Absent, it
   resolves nothing — an include then fails CLOSED and renders its
   reason, never an empty block. Defined above BOTH renderers so they
   share one resolution path. *)
let include_resolver read_source (d : Wiki_include.t) =
  match read_source with
  | Some r -> Wiki_include.slice ~read:r d
  | None ->
      (* ONE reason for one condition: Wiki_ast's own default says the
         same thing, so a direct Wiki_ast.render caller and a
         render_markdown caller cannot report different bytes. *)
      Error (Printf.sprintf "no source reader injected for %s" d.Wiki_include.path)

let render_line_machine ?read_source ?default_lang ~resolve markdown =
  let fence_included = ref false in
  let fence_emphasis = ref [] in
  let fence_lineno = ref 0 in
  let anchor = make_slugger () in
  let buffer = Buffer.create (String.length markdown * 2) in
  let para = Buffer.create 128 in
  let in_fence = ref false in
  (* [None] outside a list, else the tag currently open. Tracking WHICH
     kind is what stops a bullet run and a numbered run merging into one
     malformed list. *)
  let in_list = ref None in
  let in_table = ref false in
  let flush_para () =
    if Buffer.length para > 0 then (
      (match Wiki_ast.block_anchor_split (Buffer.contents para) with
      | text, Some a ->
          Buffer.add_string buffer
            ("<p id=\"" ^ a ^ "\">" ^ render_inline ~resolve text ^ "</p>\n")
      | _, None ->
          Buffer.add_string buffer
            ("<p>" ^ render_inline ~resolve (Buffer.contents para) ^ "</p>\n"));
      Buffer.clear para)
  in
  let close_list () =
    match !in_list with
    | Some tag ->
        Buffer.add_string buffer (Printf.sprintf "</%s>\n" tag);
        in_list := None
    | None -> ()
  in
  let open_list tag attrs =
    (* a different list kind closes the current one rather than nesting *)
    (match !in_list with Some t when t <> tag -> close_list () | _ -> ());
    if !in_list = None then (
      Buffer.add_string buffer (Printf.sprintf "<%s%s>\n" tag attrs);
      in_list := Some tag)
  in
  let close_table () =
    if !in_table then (
      Buffer.add_string buffer "</table>\n";
      in_table := false)
  in
  (* HW.2.3.1 gave this machine an INDEXED walk. It was a streaming
     `List.iter` with no lookahead, which is exactly why a callout — a
     group of quote lines with arbitrary block content — could not be
     expressed here. The index costs nothing and every existing branch is
     untouched; only the callout branch reads ahead. *)
  let all_lines = Array.of_list (lines_of markdown) in
  let cursor = ref 0 in
  let skip_until = ref 0 in
  Array.iter
    (fun line ->
      let here = !cursor in
      incr cursor;
      if here < !skip_until then ()
      else if !in_fence then
        if is_fence line then (
          (* an include already emitted its whole block at the opener *)
          if not !fence_included then Buffer.add_string buffer "</code></pre>\n";
          in_fence := false;
          fence_included := false;
          fence_emphasis := [];
          fence_lineno := 0)
        else if !fence_included then
          (* HW.9.2.1: the authored body is IGNORED — the file is the
             only source of truth, so it is not even escaped through. *)
          ()
        else (
          incr fence_lineno;
          let escaped = escape_html line in
          Buffer.add_string buffer
            ((if List.mem !fence_lineno !fence_emphasis then
                "<mark>" ^ escaped ^ "</mark>"
              else escaped)
            ^ "\n"))
      else if is_fence line then (
        flush_para ();
        close_list ();
        close_table ();
        (* HW.2.0.2/9.2.1/2.6.6/2.6.7 — the ONE info grammar, both
           renderers, through the ONE fence emitter. *)
        let info = Wiki_ast.fence_info_of_line line in
        (match Wiki_include.parse info with
        | Some d ->
            Buffer.add_string buffer
              (Wiki_ast.include_html ~escape:escape_html
                 ~resolve:(include_resolver read_source) d);
            fence_included := true
        | None when Wiki_include.attempted info ->
            Buffer.add_string buffer
              (Wiki_ast.fence_html ~escape:escape_html ~lang:"text"
                 [ Printf.sprintf "literalinclude unresolved: malformed directive (%s)" info ]);
            fence_included := true
        | None ->
            fence_emphasis := Wiki_include.emphasize_of_info info;
            (match
               match Wiki_ast.lang_of_info info with Some l -> Some l | None -> default_lang
             with
            | Some lang ->
                Buffer.add_string buffer
                  (Printf.sprintf "<pre><code class=\"language-%s\">" lang)
            | None -> Buffer.add_string buffer "<pre><code>"));
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
          let text = String.trim (String.sub trimmed level (String.length trimmed - level)) in
          Buffer.add_string buffer
            (Printf.sprintf "<h%d id=\"%s\">%s</h%d>\n" level (anchor text)
               (render_inline ~resolve text) level))
        else if is_thematic_break trimmed then (
          (* CommonMark 4.1. Reached only for a line that is NOT a list
             item, so `---` under a bullet still ends the list rather than
             being mistaken for one. Frontmatter never arrives here: it is
             stripped before the body is rendered. *)
          flush_para ();
          close_list ();
          close_table ();
          Buffer.add_string buffer "<hr />\n")
        else if starts_with "- " trimmed || starts_with "* " trimmed then (
          flush_para ();
          close_table ();
          open_list "ul" "";
          let item = String.sub trimmed 2 (String.length trimmed - 2) in
          match task_marker item with
          | Some (checked, rest) ->
              (* GFM 5.3. Rendered READ-ONLY and disabled: task state lives
                 in the plan ledger, so a document must never be able to
                 disagree with it about what is done. *)
              let rest, attr =
                match Wiki_ast.block_anchor_split rest with
                | text, Some a -> (text, Printf.sprintf " id=\"%s\"" a)
                | _ -> (rest, "")
              in
              Buffer.add_string buffer
                (Printf.sprintf
                   "<li class=\"task\"%s><input type=\"checkbox\" disabled%s /> %s</li>\n"
                   attr
                   (if checked then " checked" else "")
                   (render_inline ~resolve rest))
          | None ->
              let item, attr =
                match Wiki_ast.block_anchor_split item with
                | text, Some a -> (text, Printf.sprintf " id=\"%s\"" a)
                | _ -> (item, "")
              in
              Buffer.add_string buffer
                (Printf.sprintf "<li%s>%s</li>\n" attr (render_inline ~resolve item)))
        else if ordered_marker trimmed <> None then (
          flush_para ();
          close_table ();
          match ordered_marker trimmed with
          | Some (start, rest) ->
              (* CommonMark 5.2: the start number is preserved, and only a
                 first item's number can set it. *)
              let attrs =
                if !in_list = None && start <> 1 then Printf.sprintf " start=\"%d\"" start else ""
              in
              open_list "ol" attrs;
              let rest, li_attr =
                match Wiki_ast.block_anchor_split rest with
                | text, Some a -> (text, Printf.sprintf " id=\"%s\"" a)
                | _ -> (rest, "")
              in
              Buffer.add_string buffer
                (Printf.sprintf "<li%s>%s</li>\n" li_attr (render_inline ~resolve rest))
          | None -> ())
        else if starts_with "|" trimmed then (
          flush_para ();
          close_list ();
          let cells =
            String.split_on_char '|' trimmed
            |> List.filter_map (fun c ->
                   let c = String.trim c in
                   if c = "" then None else Some c)
          in
          let is_separator =
            cells <> []
            && List.for_all
                 (fun c -> String.for_all (fun ch -> ch = '-' || ch = ':') c)
                 cells
          in
          if not is_separator then begin
            let tag = if !in_table then "td" else "th" in
            if not !in_table then (
              Buffer.add_string buffer "<table>\n";
              in_table := true);
            Buffer.add_string buffer "<tr>";
            List.iter
              (fun c ->
                Buffer.add_string buffer
                  (Printf.sprintf "<%s>%s</%s>" tag (render_inline ~resolve c) tag))
              cells;
            Buffer.add_string buffer "</tr>\n"
          end)
        else if starts_with "> " trimmed then (
          flush_para ();
          close_list ();
          close_table ();
          let content = String.sub trimmed 2 (String.length trimmed - 2) in
          match Wiki_callout.parse_header content with
          | Some _ ->
              (* Consume the whole group and DELEGATE to the block layer:
                 same parse, same emitter, so the two renderers cannot
                 diverge on callouts. *)
              let last = ref here in
              let continue_ = ref true in
              while !continue_ && !last + 1 < Array.length all_lines do
                let t = String.trim all_lines.(!last + 1) in
                if
                  starts_with "> " t
                  && Wiki_callout.parse_header (String.sub t 2 (String.length t - 2)) = None
                then incr last
                else continue_ := false
              done;
              skip_until := !last + 1;
              let text =
                String.concat "\n"
                  (Array.to_list (Array.sub all_lines here (!last - here + 1)))
              in
              Buffer.add_string buffer
                (Wiki_ast.render ~inline:(render_inline ~resolve) ~anchor ~escape:escape_html
                   (Wiki_ast.parse text))
          | None ->
              Buffer.add_string buffer
                ("<blockquote>" ^ render_inline ~resolve content ^ "</blockquote>\n"))
        else if trimmed = "" then (
          flush_para ();
          close_list ();
          close_table ())
        else (
          if Buffer.length para > 0 then Buffer.add_char para ' ';
          Buffer.add_string para line))
    all_lines;
  flush_para ();
  close_list ();
  close_table ();
  (* an include emitted its whole block at the opener — the EOF closer
     needs the SAME guard the mid-stream closer has, or an unclosed
     include fence appends a stray tag the AST path never emits *)
  if !in_fence && not !fence_included then Buffer.add_string buffer "</code></pre>\n";
  Buffer.contents buffer

(* HW.2.0.1 — the FINAL encoding: parse to a recursive block tree, then
   render it as a catamorphism. Admitted by observational equivalence to
   the oracle above over the whole corpus (`test_wiki_ast`), and pinned
   further by the render baseline.

   The inline layer is still a raw string handed to `render_inline`; the
   BLOCK layer is what needed lifting, and it is what the ten gated
   features require. *)
let render_markdown ?default_role ?resolve_term ?read_source ?default_lang ~resolve markdown =
  let anchor = make_slugger () in
  Wiki_ast.render
    ~resolve_include:(include_resolver read_source)
    ?default_lang
    ~inline:(render_inline ?default_role ?resolve_term ~resolve)
    ~anchor
    ~escape:escape_html
    (Wiki_ast.parse markdown)

(* ----------------------------------------------------------------- build *)

(* "03 · The Gate" / "3. The Gate" / "03 - The Gate" -> "The Gate" — the
   fourth resolver key strips a leading ordinal so numbered playbooks resolve
   by their bare title. Hoisted from build so Dep_sheaf shares ONE source. *)
let strip_ordinal title =
  let n = String.length title in
  let i = ref 0 in
  while !i < n && title.[!i] >= '0' && title.[!i] <= '9' do incr i done;
  if !i = 0 || !i >= n then title
  else begin
    let j = ref !i in
    while
      !j < n
      && (let c = title.[!j] in
          c = ' ' || c = '.' || c = '-' || c = ':' || c = '\xc2' || c = '\xb7')
    do
      incr j
    done;
    if !j > !i then String.trim (String.sub title !j (n - !j)) else title
  end

let title_of body path =
  let rec first = function
    | [] -> Filename.remove_extension (Filename.basename path)
    | line :: rest ->
        let t = String.trim line in
        if starts_with "# " t then String.trim (String.sub t 2 (String.length t - 2))
        else first rest
  in
  first (lines_of body)

let group_of path =
  (* The group is the directory immediately containing the note. Keying
     it off a literal path segment broke the moment the corpus root
     moved (docs/hermes -> hermes_wiki/pages), so it is now relative:
     the parent directory name, with the corpus root itself meaning "no
     group". *)
  let parent = Filename.basename (Filename.dirname path) in
  match parent with
  | "pages" | "hermes" | "." | "/" -> ""
  | group -> group

(* Ordinary markdown links to sibling .md files are the SAME relation as a
   wikilink: a real corpus cross-references that way, and a graph that
   ignored them would understate connectivity. External URLs never
   qualify. *)
let md_link_payloads line =
  let n = String.length line in
  let rec go i acc =
    match String.index_from_opt line i '(' with
    | None -> List.rev acc
    | Some j -> (
        match String.index_from_opt line j ')' with
        | None -> List.rev acc
        | Some k ->
            let url = String.sub line (j + 1) (k - j - 1) in
            let acc =
              if
                Filename.check_suffix url ".md"
                && (not (String.length url > 4 && String.sub url 0 4 = "http"))
                && j > 0 && line.[j - 1] = ']'
              then Filename.remove_extension (Filename.basename url) :: acc
              else acc
            in
            if k + 1 >= n then List.rev acc else go (k + 1) acc)
  in
  go 0 []

(* Heading anchors, extracted with the SAME stateful slugger the renderer
   uses, so a table of contents and the rendered ids can never disagree. *)
let headings_of body =
  let anchor = make_slugger () in
  let in_fence = ref false in
  List.filter_map
    (fun line ->
      if is_fence line then (in_fence := not !in_fence; None)
      else if !in_fence then None
      else
        let t = String.trim line in
        if starts_with "#" t && String.contains t (Char.chr 32) then begin
          let level = ref 0 in
          while !level < String.length t && t.[!level] = (Char.chr 35) do incr level done;
          let level = min !level 4 in
          let text = String.trim (String.sub t level (String.length t - level)) in
          Some (level, text, anchor text)
        end
        else None)
    (lines_of body)

let scan_body body =
  let in_fence = ref false in
  List.fold_left
    (fun (links, tags) line ->
      if is_fence line then (
        in_fence := not !in_fence;
        (links, tags))
      else if !in_fence then (links, tags)
      else
        (* payloads from the MASKED line (code is not prose); the citing
           line kept raw for back_ctx display *)
        let masked = mask_inline_spans line in
        ( links
          @ List.map (fun p -> (p, line)) (wikilink_payloads masked)
          @ List.map (fun p -> (p, line)) (md_link_payloads masked),
          tags @ tags_of_line line ))
    ([], []) (lines_of body)

(* HW.3.3.1 — the block ids of a page: the renderer's own classifier,
   fence-aware, paragraph and list-item lines only (the two carriers the
   renderers mark). Ids keep the ^, so they can never collide with a
   heading anchor. *)
let block_ids raw =
  let in_fence = ref false in
  String.split_on_char '\n' raw
  |> List.filter_map (fun line ->
         let trimmed = String.trim line in
         if starts_with "```" trimmed then (
           in_fence := not !in_fence;
           None)
         else if !in_fence then None
         else if
           trimmed = "" || starts_with "#" trimmed || starts_with ">" trimmed
           || starts_with "|" trimmed || starts_with "<" trimmed
           || is_thematic_break trimmed
         then None
         else
           let candidate =
             if starts_with "- " trimmed then
               let item = String.sub trimmed 2 (String.length trimmed - 2) in
               match task_marker item with Some (_, rest) -> rest | None -> item
             else
               match ordered_marker trimmed with Some (_, rest) -> rest | None -> trimmed
           in
           snd (Wiki_ast.block_anchor_split candidate))

let build ?(read_source = fun _ -> None) files =
  (* MEMOISED for the whole build: the render pass and the include-failure
     scan both resolve every directive, and two independent reads of the
     same path can disagree if the filesystem moves between them — the
     page would then say one thing and the audit another. One read per
     path makes the two passes observe the same world by construction. *)
  let read_cache : (string, string option) Hashtbl.t = Hashtbl.create 16 in
  let read_source path =
    match Hashtbl.find_opt read_cache path with
    | Some v -> v
    | None ->
        let v = read_source path in
        Hashtbl.replace read_cache path v;
        v
  in
  let prepared =
    List.map
      (fun (path, content) ->
        let fields, body = parse_frontmatter content in
        let slug = slugify (Filename.remove_extension (Filename.basename path)) in
        let payloads, tags = scan_body body in
        (* A note that quotes the wikilink grammar as evidence opts out
           of the graph via its own frontmatter (zigvm §9). Without this
           a spec document manufactures phantom edges to targets it is
           only describing. *)
        let payloads =
          if List.assoc_opt "allow_example_links" fields = Some "true" then []
          else payloads
        in
        (* HW.3.7.6: a !suppressed reference is mentioned, not asserted —
           it makes NO edge of any dimension (outlink, typed, fragment)
           and is never warned about. Filtered here so every downstream
           consumer of payloads agrees. *)
        (* HW.3.7.6: a !suppressed reference is mentioned, not asserted —
           it makes NO edge of any dimension (outlink, typed, fragment)
           and is never warned about. Filtered here so every downstream
           consumer of payloads agrees. *)
        let payloads =
          List.filter (fun (p, _) -> not (Wiki_ref.parse p).Wiki_ref.suppress) payloads
        in
        let default_role =
          match List.assoc_opt "default_role" fields with
          | Some v when v <> "" -> v
          | _ -> "code"
        in
        (* HW.2.7.2: under default_role any, every inline `span` is a
           reference — an EDGE like any other. Identity under "code". *)
        let payloads =
          if default_role = "any" then
            let in_fence = ref false in
            payloads
            @ List.concat_map
                (fun line ->
                  if is_fence line then (in_fence := not !in_fence; [])
                  else if !in_fence then []
                  else List.map (fun c -> (c, line)) (line_span_contents line))
                (lines_of body)
          else payloads
        in
        let outlinks =
          List.map (fun (p, _) -> slugify (strip_fragment (fst (split_payload p)))) payloads
          |> List.sort_uniq compare
        in
        let typed =
          List.filter_map
            (fun (p, _) ->
              match split_payload p with
              | target, Some rel -> Some (slugify (strip_fragment target), rel)
              | _ -> None)
            payloads
        in
        (* HW.3.4.2: the fragment references this page makes, kept alongside
           the edge so HW.3.4.3 can check them against the target's anchors.
           Normalized PURELY (as the renderer does) so a reference and the
           anchor it addresses are compared in the same alphabet. *)
        let frag_refs =
          List.filter_map
            (fun (p, _) ->
              let target = fst (split_payload p) in
              match fragment_of target with
              | Some f ->
                  (* HW.3.3.1: a ^fragment names a block id — those keep
                     their case and the ^ (the disjoint namespace); only
                     heading fragments slugify. *)
                  let decoded = percent_decode f in
                  let normalized =
                    if String.length decoded > 0 && decoded.[0] = '^' then decoded
                    else slugify decoded
                  in
                  Some (slugify (strip_fragment target), normalized)
              | None -> None)
            payloads
          |> List.sort_uniq compare
        in
        ( path, slug, fields, body, outlinks, typed,
          List.sort_uniq compare tags, payloads, frag_refs ))
      files
  in
  (* zigvm §6a encodes the path into the page slug so two same-named
     notes cannot collide. Ours stays basename-derived (stable and
     readable in a URL), so a collision is DISAMBIGUATED by prefixing
     the group — first occurrence in corpus order keeps the bare slug.
     Surfaced by importing a corpus carrying two README.md. *)
  let prepared =
    let seen = Hashtbl.create 64 in
    List.map
      (fun (path, slug, fields, body, outlinks, typed, tags, payloads, frag_refs) ->
        let slug =
          if not (Hashtbl.mem seen slug) then slug
          else
            let group = group_of path in
            let qualified = if group = "" then slug ^ "-1" else group ^ "-" ^ slug in
            let rec unique candidate n =
              if not (Hashtbl.mem seen candidate) then candidate
              else unique (Printf.sprintf "%s-%d" qualified n) (n + 1)
            in
            unique qualified 2
        in
        Hashtbl.replace seen slug ();
        (path, slug, fields, body, outlinks, typed, tags, payloads, frag_refs))
      prepared
  in
  let slugs = List.map (fun (_, s, _, _, _, _, _, _, _) -> s) prepared in
  (* zigvm §4: the resolver registers FOUR keys per note — slug, title,
     basename, and title-minus-a-leading-ordinal — so [[The Gate]],
     [[03 · The Gate]] and [[03-the-gate]] all reach one slug. First
     registration wins; collisions resolve by corpus order. *)
  let register_identity table (path, slug, _, body, _, _, _, _, _) =
    let title = title_of body path in
    let keys =
      [ slug; slugify title;
        slugify (Filename.remove_extension (Filename.basename path));
        slugify (strip_ordinal title) ]
    in
    List.fold_left
      (fun table key ->
        if key = "" || List.mem_assoc key table then table else (key, slug) :: table)
      table keys
  in
  (* HW.3.7.2 tier: an ARCHIVED page is a record, not a contestant — its
     identity keys register only after every living page's, so a living
     page wins the key by construction rather than by corpus order. *)
  let living_p, archived_p =
    List.partition
      (fun (_, _, fields, _, _, _, _, _, _) ->
        List.assoc_opt "maturity" fields <> Some "archived")
      prepared
  in
  let resolver = List.fold_left register_identity [] living_p in
  let resolver = List.fold_left register_identity resolver archived_p in
  (* pass 2: aliases register AFTER every identity key, so an alias can
     never shadow a real slug/title/basename regardless of corpus order —
     an alias is a weaker claim than an identity (HW.1.2.7, spec §3) *)
  let resolver =
    List.fold_left
      (fun table (_, slug, fields, _, _, _, _, _, _) ->
        let aliases =
          match List.assoc_opt "aliases" fields with
          | Some v -> parse_inline_list v
          | None -> []
        in
        List.fold_left
          (fun table alias ->
            let key = slugify alias in
            if key = "" || List.mem_assoc key table then table
            else (key, slug) :: table)
          table aliases)
      resolver prepared
  in
  let canonical key = match List.assoc_opt key resolver with Some s -> Some s | None -> None in
  let resolve target =
    match canonical target with
    | Some slug -> Some (slug ^ ".html")
    | None -> if List.mem target slugs then Some (target ^ ".html") else None
  in
  (* HW.3.7.4 — the glossary space: every level-2+ heading of a page with
     "glossary" among its topics defines a term; the href is complete
     because the term IS a location. Disjoint from the doc resolver by
     construction (the kind law). *)
  let term_space =
    List.concat_map
      (fun (_, slug, fields, body, _, _, _, _, _) ->
        let topics =
          match List.assoc_opt "topics" fields with
          | Some v -> parse_inline_list v
          | None -> []
        in
        if List.mem "glossary" topics then
          headings_of body
          |> List.filter (fun (l, _, _) -> l >= 2)
          |> List.map (fun (_, text, anchor) -> (slugify text, (slug, anchor)))
        else [])
      prepared
  in
  let resolve_term key =
    match List.assoc_opt key term_space with
    | Some (slug, anchor) -> Some (slug ^ ".html#" ^ anchor)
    | None -> None
  in
  let backlinks_of slug =
    List.filter_map
      (fun (_, source, _, _, outlinks, _, _, payloads, _) ->
        let outlinks =
          List.map (fun l -> match canonical l with Some s -> s | None -> l) outlinks
        in
        if source <> slug && List.mem slug outlinks then
          let line =
            match
              List.find_opt
                (fun (p, _) ->
                  let raw = slugify (strip_fragment (fst (split_payload p))) in
                  (match canonical raw with Some s -> s | None -> raw) = slug)
                payloads
            with
            | Some (_, line) -> String.trim line
            | None -> ""
          in
          Some (source, line)
        else None)
      prepared
  in
  (* zigvm §4 pass 3: MENTIONS — a page whose text contains another
     note's title verbatim but does NOT link it. A linker is a backlink,
     never also a mention, and a page never mentions itself. *)
  let titles =
    List.map (fun (path, slug, _, body, _, _, _, _, _) -> (slug, title_of body path)) prepared
  in
  let contains_text haystack needle =
    let n = String.length needle and h = String.length haystack in
    n > 0 && n <= h
    &&
    let rec go i = i + n <= h && (String.sub haystack i n = needle || go (i + 1)) in
    go 0
  in
  let mentions_of slug =
    let title = match List.assoc_opt slug titles with Some t -> t | None -> "" in
    if title = "" then []
    else
      List.filter_map
        (fun (_, source, _, body, outlinks, _, _, _, _) ->
          let outlinks =
            List.map (fun l -> match canonical l with Some s -> s | None -> l) outlinks
          in
          if source <> slug && (not (List.mem slug outlinks)) && contains_text body title
          then Some source
          else None)
        prepared
  in
  let pages =
    List.map
      (fun (path, slug, fields, body, outlinks, typed, tags, _, frag_refs) ->
        let back = backlinks_of slug in
        (* Resolve outlinks THROUGH the four-key resolver so a link by
           title and a link by slug are one edge, not two. *)
        let outlinks =
          List.sort_uniq compare
            (List.map (fun l -> match canonical l with Some s -> s | None -> l) outlinks)
        in
        (* Fragment references resolve THROUGH the same resolver as the
           edge, so `[[The Guide#x]]` and `[[guide#x]]` name one target. *)
        let frag_refs =
          List.sort_uniq compare
            (List.map
               (fun (t, f) -> ((match canonical t with Some s -> s | None -> t), f))
               frag_refs)
        in
        let default_role =
          match List.assoc_opt "default_role" fields with
          | Some v when v <> "" -> v
          | _ -> "code"
        in
        (* HW.2.6.7: the document's default highlight language. A fence's
           own language dominates it (applied in the emitter). *)
        let default_lang = List.assoc_opt "highlight" fields in
        { path; slug; title = title_of body path; group = group_of path;
          meta = meta_of ~has_frontmatter:(fields <> []) fields slug;
          html =
            render_markdown ~default_role ~resolve_term ~read_source ?default_lang ~resolve body;
          outlinks; mentions = mentions_of slug; typed; tags;
          headings = headings_of body;
          backlinks = List.map fst back;
          back_ctx = back;
          frag_refs;
          raw = body })
      prepared
  in
  let anomalies =
    let sorted = List.sort compare slugs in
    let rec dups = function
      | a :: (b :: _ as rest) ->
          (if a = b then [ "duplicate slug: " ^ a ] else []) @ dups rest
      | _ -> []
    in
    (* zigvm's discourse vocabulary plus "reference": imported material
       that documents another system is neither a claim nor a decision of
       ours, and mislabelling 146 documents to fit a five-item list would
       be worse than extending the list. *)
    (* ...and "policy": the system-engineering track authors normative
       documents (acquisition rules, reproducibility requirements) that
       are neither a claim about the world nor a decision already taken —
       they BIND future work. Admitted deliberately, on the same grounds
       "reference" was; the set stays closed, so an unknown type is still
       a defect. *)
    (* ...and "playbook": the corpus has carried a `pages/playbooks/`
       directory since before this vocabulary was written, so a runbook is
       an ESTABLISHED class here, not a novelty — a procedure to execute,
       distinct from a policy that binds and a decision already taken.
       The set stays closed; an unknown type is still a defect. *)
    let known =
      [ "note"; "question"; "claim"; "evidence"; "decision"; "reference"; "policy";
        "playbook" ]
    in
    (* A resolved collision is REPORTED, never silent: the reader must be
       able to see that a slug was qualified rather than wonder why a URL
       is not the basename. *)
    let renamed =
      List.filter_map
        (fun (path, slug, _, _, _, _, _, _, _) ->
          let natural = slugify (Filename.remove_extension (Filename.basename path)) in
          if slug = natural then None
          else Some (Printf.sprintf "slug collision resolved: %s -> %s (%s)" natural slug path))
        prepared
    in
    (* HW.3.3.1 — a same-page duplicate block anchor makes [[p#^id]]
       ambiguous inside its own page: a DEFECT. Cross-page reuse is legal,
       because a block reference is always page-qualified. *)
    let block_dups =
      List.concat_map
        (fun p ->
          let ids = List.sort compare (block_ids p.raw) in
          let rec dup_ids = function
            | a :: (b :: _ as rest) ->
                (if a = b then [ Printf.sprintf "duplicate block anchor %s in %s" a p.slug ]
                 else [])
                @ dup_ids rest
            | _ -> []
          in
          List.sort_uniq compare (dup_ids ids))
        pages
    in
    renamed @ dups sorted @ block_dups
    @ List.filter_map
        (fun p ->
          if List.mem p.meta.ntype known then None
          else Some ("unknown discourse type '" ^ p.meta.ntype ^ "' on " ^ p.slug))
        pages
  in
  (* HW.9.2.1 — the include failures, computed HERE because only build
     holds the injected reader; the model carries them so the audit
     reports exactly what the reader saw. *)
  let include_failures =
    List.concat_map
      (fun p ->
        (* the example-link exemption applies here as it does to every
           other diagnostic: a page documenting the grammar must be able
           to stop reporting itself *)
        if p.meta.allow_example_links then []
        else
          Wiki_ast.fences (Wiki_ast.parse p.raw)
          |> List.filter (fun (info, _) -> Wiki_include.attempted info)
          |> List.filter_map (fun (info, _) ->
                 match Wiki_include.parse info with
                 | None ->
                     Some
                       (Printf.sprintf "include unresolved: malformed directive in %s (%s)"
                          p.slug info)
                 | Some d -> (
                     match Wiki_include.slice ~read:read_source d with
                     | Ok _ -> None
                     | Error reason ->
                         Some
                           (Printf.sprintf "include unresolved: %s in %s (%s)"
                              d.Wiki_include.path p.slug reason))))
      pages
    |> List.sort_uniq compare
  in
  { pages; anomalies; include_failures }

let page model slug = List.find_opt (fun p -> p.slug = slug) model.pages

(* The four resolver keys a page registers, in registration order — the
   SAME construction build uses, exported so Dep_sheaf resolves through one
   source of truth rather than a re-derivation that can drift. *)
(* Fence-aware wikilink TARGETS of a raw body — what a render OBSERVES,
   before any allow_example_links curation. Dep_sheaf builds covers from
   this, so the cover matches the renderer rather than the graph. *)
(* The fence walk, shared by every raw-body reference scan. *)
let raw_payloads raw =
  let in_fence = ref false in
  List.concat_map
    (fun line ->
      if is_fence line then (in_fence := not !in_fence; [])
      else if !in_fence then []
      else wikilink_payloads (mask_inline_spans line))
    (lines_of raw)

let raw_link_targets raw =
  raw_payloads raw
  |> List.filter (fun payload -> not (Wiki_ref.parse payload).Wiki_ref.suppress)
  |> List.map (fun payload -> fst (split_payload payload))

let resolver_keys p =
  [ p.slug; slugify p.title;
    slugify (Filename.remove_extension (Filename.basename p.path));
    slugify (strip_ordinal p.title) ]

(* HW.2.6.3 — the back-of-book index. An entry is AUTHORED at the point
   of relevance and addresses a LOCATION (page + nearest preceding
   level-2+ heading); tags classify documents, an index addresses
   paragraphs. Directive forms, one per line, fence-aware:
     <!-- index: term -->              <!-- index: term; subterm -->
     <!-- index: see: term -> target -->                          *)
let index_directive line =
  let t = String.trim line in
  let pre = "<!-- index:" and post = "-->" in
  let np = String.length pre and ns = String.length post in
  if
    String.length t >= np + ns
    && String.sub t 0 np = pre
    && String.sub t (String.length t - ns) ns = post
  then
    let body = String.trim (String.sub t np (String.length t - np - ns)) in
    if String.length body >= 4 && String.sub body 0 4 = "see:" then
      let rest = String.trim (String.sub body 4 (String.length body - 4)) in
      match
        let rec find i =
          if i + 4 > String.length rest then None
          else if String.sub rest i 4 = " -> " then Some i
          else find (i + 1)
        in
        find 0
      with
      | Some i ->
          let term = String.trim (String.sub rest 0 i) in
          let target =
            String.trim (String.sub rest (i + 4) (String.length rest - i - 4))
          in
          if term = "" || target = "" then None else Some (`See (term, target))
      | None -> None
    else
      match String.index_opt body ';' with
      | Some i ->
          let term = String.trim (String.sub body 0 i) in
          let sub = String.trim (String.sub body (i + 1) (String.length body - i - 1)) in
          if term = "" then None else Some (`Single (term, sub))
      | None -> if body = "" then None else Some (`Single (body, ""))
  else None

let corpus_index m =
  List.concat_map
    (fun p ->
      let heads = ref p.headings in
      let current = ref "" in
      let in_fence = ref false in
      List.concat_map
        (fun line ->
          if is_fence line then (in_fence := not !in_fence; [])
          else if !in_fence then []
          else
            let t = String.trim line in
            if String.length t > 0 && t.[0] = '#' then (
              (match !heads with
              | (level, _, anchor) :: rest ->
                  current := (if level >= 2 then anchor else "");
                  heads := rest
              | [] -> ());
              [])
            else
              match index_directive t with
              | Some (`Single (term, sub)) -> [ (term, sub, p.slug, !current) ]
              | Some (`See (term, target)) ->
                  [ (term, "see: " ^ target, p.slug, !current) ]
              | None -> [])
        (lines_of p.raw))
    m.pages
  |> List.sort_uniq compare

(* see-targets must exist as CONCRETE entries — a redirect into nothing
   is the index's own dead link. *)
let index_violations m =
  let ix = corpus_index m in
  let concrete =
    List.filter_map
      (fun (t, sub, _, _) ->
        if String.length sub >= 5 && String.sub sub 0 5 = "see: " then None else Some t)
      ix
  in
  List.filter_map
    (fun (t, sub, slug, _) ->
      if String.length sub >= 5 && String.sub sub 0 5 = "see: " then
        let target = String.sub sub 5 (String.length sub - 5) in
        if List.mem target concrete then None
        else
          Some
            (Printf.sprintf "index see-target missing: %s -> %s in %s" t target slug)
      else None)
    ix
  |> List.sort_uniq compare

let include_gaps m = m.include_failures

(* HW.2.6.6 — `emphasize ⊆ [1..lines(body)]`. Checked for AUTHORED
   fences; an include's emphasis is relative to a slice only build can
   see, so it is not re-derived here (stated, not hidden). *)
let fence_option_gaps m =
  List.concat_map
    (fun p ->
      if p.meta.allow_example_links then []
      else
      Wiki_ast.fences (Wiki_ast.parse p.raw)
      |> List.filter (fun (info, _) -> Wiki_include.parse info = None)
      |> List.concat_map (fun (info, body) ->
             let n = List.length body in
             Wiki_include.emphasize_of_info info
             |> List.filter (fun e -> e > n)
             |> List.map (fun e ->
                    Printf.sprintf "emphasize %d out of range (fence has %d lines) in %s" e n
                      p.slug)))
    m.pages
  |> List.sort_uniq compare

(* TOTAL. `match e with | exception _` catches the SCRUTINEE only, and
   `open_in_bin` SUCCEEDS on a directory here — `in_channel_length` then
   raises out of the body and kills every tool that builds the corpus.
   The whole body must be guarded, and the descriptor closed on the
   raising path too. *)
let read_source_file path =
  try
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

(* HW.9.3.1 — the doctest builder's core. A `doctest`-tagged fence is a
   TESTED example: `> input` markdown rendered with the empty resolver
   must equal the expected lines, byte-exact. A mismatch is
   documentation drift — the fence claimed the grammar does something
   it no longer does. Pure and deterministic by construction. *)
(* A doctest fence is a SEQUENCE of groups, not two heaps. `List.partition`
   was order-blind: a blank separator line — the most natural way to write
   one — landed in "expected" and manufactured drift, and interleaved
   input/output pairs collapsed into one wrong comparison. Grouping keeps
   the author's structure: each run of `>` lines is an input, the
   following non-`>` lines (blanks trimmed) are its expected output. *)
let doctest_groups body =
  let is_input l = l = ">" || (String.length l >= 2 && String.sub l 0 2 = "> ") in
  let strip l = if l = ">" then "" else String.sub l 2 (String.length l - 2) in
  let trim_blanks ls =
    let rec drop = function "" :: t -> drop t | l -> l in
    List.rev (drop (List.rev (drop ls)))
  in
  let rec go acc cur_in cur_out = function
    | [] -> List.rev (if cur_in = [] then acc else (List.rev cur_in, trim_blanks (List.rev cur_out)) :: acc)
    | l :: rest when is_input l ->
        if cur_out <> [] && cur_in <> [] then
          (* a new input after an output closes the previous group *)
          go ((List.rev cur_in, trim_blanks (List.rev cur_out)) :: acc) [ strip l ] [] rest
        else go acc (strip l :: cur_in) cur_out rest
    | l :: rest -> go acc cur_in (l :: cur_out) rest
  in
  go [] [] [] body

let doctest_drift m =
  List.concat_map
    (fun p ->
      if p.meta.allow_example_links then []
      else
        Wiki_ast.fences (Wiki_ast.parse p.raw)
        |> List.filter (fun (info, _) ->
               (not (Wiki_include.attempted info))
               && String.split_on_char ' ' info
                  |> List.concat_map (String.split_on_char '\t')
                  |> List.exists (fun tok -> tok = "doctest"))
        |> List.mapi (fun i (_, body) -> (i + 1, body))
        |> List.filter_map (fun (i, body) ->
               let bad =
                 doctest_groups body
                 |> List.exists (fun (inputs, expected) ->
                        let got =
                          render_markdown ~resolve:(fun _ -> None)
                            (String.concat "\n" inputs ^ "\n")
                        in
                        let want =
                          if expected = [] then "" else String.concat "\n" expected ^ "\n"
                        in
                        got <> want)
               in
               if bad then Some (Printf.sprintf "doctest drift: %s #%d" p.slug i) else None))
    m.pages
  |> List.sort_uniq compare

let notice_prefix = "slug collision resolved"

let is_notice text =
  String.length text >= String.length notice_prefix
  && String.sub text 0 (String.length notice_prefix) = notice_prefix

(* Alias resolver keys of a page — slugified, registration pass 2. One
   source of truth for Dep_sheaf, exactly like resolver_keys. *)
let alias_keys p = List.map slugify p.meta.aliases

(* HW.3.7.2 — ambiguity as an error, AT THE USE SITE. The resolver's
   first-wins table makes resolution deterministic, but a reader following
   a contested key is shown one of several candidates with no signal; this
   is where Sphinx errors, and where we now report. Tiering mirrors the
   pass-2 registration algebra exactly: identity keys contest identity
   keys; aliases contest only when NO identity claims the key (an alias
   never shadows an identity, HW.1.2.7). Zero candidates is a DEAD link —
   a different verdict with a different fix, never conflated here. *)
(* THREE tiers, mirroring registration: living identity > archived
   identity > alias. An archive is a record, not a contestant — its name
   claim yields to any living page (and build registers it after every
   living identity, so resolution agrees BY CONSTRUCTION). One shared
   construction for ambiguity (HW.3.7.2) and nitpicky (HW.3.7.3). *)
let ref_candidates m =
  let living, archived =
    List.partition (fun p -> p.meta.maturity <> "archived") m.pages
  in
  let regs_of pages keys_of =
    List.concat_map
      (fun p ->
        List.filter_map (fun k -> if k = "" then None else Some (k, p.slug)) (keys_of p))
      pages
  in
  let living_ids = regs_of living resolver_keys in
  let archived_ids = regs_of archived resolver_keys in
  let alias = regs_of m.pages alias_keys in
  let tier key table =
    List.sort_uniq compare
      (List.filter_map (fun (k, s) -> if k = key then Some s else None) table)
  in
  fun key ->
    match tier key living_ids with
    | [] -> ( match tier key archived_ids with [] -> tier key alias | ids -> ids)
    | ids -> ids

let ambiguous_refs m =
  let candidates = ref_candidates m in
  List.concat_map
    (fun p ->
      if p.meta.allow_example_links then []
      else
        raw_link_targets p.raw
        |> List.map (fun t -> slugify (strip_fragment t))
        |> List.filter (fun k -> k <> "")
        |> List.sort_uniq compare
        |> List.filter_map (fun key ->
               match candidates key with
               | _ :: _ :: _ as cands ->
                   Some
                     (Printf.sprintf "ambiguous reference: [[%s]] in %s -> {%s}" key
                        p.slug (String.concat ", " cands))
               | _ -> None))
    m.pages
  |> List.sort_uniq compare

(* HW.3.7.3 — nitpicky: a doc reference resolving at NO tier is a
   FAILURE. Term references belong to HW.3.7.4 and fragments to
   broken_anchors (the kind law keeps verdicts separate); !suppressed
   references are exempt by design and disclosed below. *)
let unresolved_refs m =
  let candidates = ref_candidates m in
  List.concat_map
    (fun p ->
      if p.meta.allow_example_links then []
      else
        let explicit =
          raw_payloads p.raw
          |> List.map Wiki_ref.parse
          |> List.filter (fun r ->
                 (not r.Wiki_ref.suppress) && r.Wiki_ref.kind <> Wiki_ref.Term)
          |> List.map (fun r -> slugify (strip_fragment r.Wiki_ref.target))
        in
        (* HW.2.7.2: under default_role any, spans are references and FAIL
           like references — the page opted into the checked universe. *)
        let spans =
          if p.meta.default_role = "any" then
            let in_fence = ref false in
            List.concat_map
              (fun line ->
                if is_fence line then (in_fence := not !in_fence; [])
                else if !in_fence then []
                else List.map slugify (line_span_contents line))
              (lines_of p.raw)
          else []
        in
        explicit @ spans
        |> List.filter (fun k -> k <> "")
        |> List.sort_uniq compare
        |> List.filter_map (fun key ->
               if candidates key = [] then
                 Some (Printf.sprintf "unresolved reference: [[%s]] in %s" key p.slug)
               else None))
    m.pages
  |> List.sort_uniq compare

(* HW.3.7.4 — the glossary, model-side: MUST agree with build's term
   space (same topics test, same heading filter, same keys). *)
let glossary_terms m =
  m.pages
  |> List.filter (fun p -> List.mem "glossary" p.meta.topics)
  |> List.concat_map (fun p ->
         p.headings
         |> List.filter (fun (l, _, _) -> l >= 2)
         |> List.map (fun (_, text, anchor) -> (slugify text, (p.slug, anchor))))
  |> List.sort_uniq compare

(* Term used and undefined => diag. The enforcement half of the
   controlled vocabulary; the verdict is disjoint from unresolved_refs
   by the kind law. *)
let term_gaps m =
  let terms = glossary_terms m in
  List.concat_map
    (fun p ->
      if p.meta.allow_example_links then []
      else
        raw_payloads p.raw
        |> List.map Wiki_ref.parse
        |> List.filter (fun r ->
               r.Wiki_ref.kind = Wiki_ref.Term && not r.Wiki_ref.suppress)
        |> List.map (fun r -> slugify (strip_fragment r.Wiki_ref.target))
        |> List.filter (fun k -> k <> "")
        |> List.sort_uniq compare
        |> List.filter_map (fun key ->
               if List.mem_assoc key terms then None
               else
                 Some
                   (Printf.sprintf "term used and undefined: [[term:%s]] in %s" key
                      p.slug)))
    m.pages
  |> List.sort_uniq compare

(* HW.3.7.6 — the opt-outs, DISCLOSED: never warned, always countable. *)
let suppressed_refs m =
  List.concat_map
    (fun p ->
      if p.meta.allow_example_links then []
      else
        raw_payloads p.raw
        |> List.map Wiki_ref.parse
        |> List.filter (fun r -> r.Wiki_ref.suppress)
        |> List.map (fun r ->
               Printf.sprintf "suppressed reference: [[!%s]] in %s"
                 (slugify (strip_fragment r.Wiki_ref.target))
                 p.slug))
    m.pages
  |> List.sort_uniq compare

(* PKM schema conformance (spec §3): the REQUIRED fields are ktype,
   maturity, domain, topics and created. aliases and links are optional by
   nature (not every note has another name or a parent). Reported as gap
   strings — notices, never defects: report first, ratchet later, exactly
   the broken_anchors decision. *)
let schema_gaps model =
  List.concat_map
    (fun p ->
      let missing =
        (if p.meta.ktype = "" then [ "ktype" ] else [])
        @ (if p.meta.maturity = "" then [ "maturity" ] else [])
        @ (if p.meta.domain = "" then [ "domain" ] else [])
        @ (if p.meta.topics = [] then [ "topics" ] else [])
        @ (if p.meta.created = "" then [ "created" ] else [])
      in
      List.map (fun f -> Printf.sprintf "schema: %s missing %s" p.slug f) missing)
    model.pages

let notices model = List.filter is_notice model.anomalies
let defects model = List.filter (fun a -> not (is_notice a)) model.anomalies

(* HW.3.4.2 — the anchors a page emits. Today every id in the rendered
   page comes from a heading, so this is the heading anchor set; the law
   in the suite pins that equality, so a future construct that emits an id
   without registering it here fails rather than silently escaping the
   check. *)
let anchors model slug =
  match page model slug with
  | Some p -> List.map (fun (_, _, a) -> a) p.headings @ block_ids p.raw
  | None -> []

(* HW.3.4.3 — a fragment reference whose DOCUMENT resolves but whose
   ANCHOR does not. Reported separately from a dead link because the fixes
   differ: a dead link wants a target, a dead fragment wants a heading.
   Mirrors Sphinx's isAnchorBrokenLink, which is a distinct predicate from
   isPathBrokenLink for exactly this reason.

   A reference into a page that does NOT exist is deliberately NOT
   reported here — that is already a dead link, and reporting it twice
   would make the two diagnoses agree about nothing useful. *)
let broken_anchors model =
  List.concat_map
    (fun p ->
      List.filter_map
        (fun (target, fragment) ->
          match page model target with
          | None -> None
          | Some t ->
              let available = List.map (fun (_, _, a) -> a) t.headings @ block_ids t.raw in
              if List.mem fragment available then None
              else
                Some
                  (Printf.sprintf "broken anchor: %s links %s#%s (no such anchor in %s)"
                     p.slug target fragment target))
        p.frag_refs)
    model.pages

let moc model =
  let groups = List.sort_uniq compare (List.map (fun p -> p.group) model.pages) in
  List.map
    (fun g ->
      ( g,
        List.filter_map (fun p -> if p.group = g then Some p.slug else None) model.pages ))
    groups

(* Guarded around the WHOLE body (R19.1). This is the first statement of
   work in every tool: an unreadable tracked path (mode 000, a directory
   that passed Sys.file_exists, a file shrinking under a concurrent
   writer) used to raise `Sys_error` out of main with no diagnosis. It is
   now a NAMED refusal — unreadable is not the same as absent, and
   neither is silently skippable. *)
exception Corpus_unreadable of string

let read_file path =
  match
    try
      let channel = open_in_bin path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () -> Some (really_input_string channel (in_channel_length channel)))
    with _ -> None
  with
  | Some content -> (path, content)
  | None ->
      raise
        (Corpus_unreadable
           (Printf.sprintf "%s is tracked but could not be read (permissions, or not a file)" path))

(* zigvm §3: the CORPUS is what git tracks. An untracked note is
   invisible until it is committed — a page cannot exist that a reviewer
   never saw. git is a declared oracle here (revision stamping already
   uses it); if it cannot answer, the corpus is empty rather than
   silently falling back to a filesystem walk. *)
let read_tracked root =
  let command =
    Printf.sprintf "git ls-files -- %s 2>/dev/null" (Filename.quote (root ^ "/"))
  in
  (* THE ORACLE'S STATUS IS THE ANSWER'S VALIDITY. Discarding it made a
     failed git indistinguishable from an empty corpus: git refusing on
     dubious ownership, or a wrong cwd, produced `[]` — a clean,
     plausible, catastrophic answer that let a tool re-pin the baseline
     to nothing and exit 0. `Unix.open_process_in` does NOT raise when
     the command fails; /bin/sh returns 127/128 with empty stdout. An
     oracle that cannot answer is UNDETERMINED, never empty. *)
  let paths =
    let channel = Unix.open_process_in command in
    let lines =
      let rec collect acc =
        match input_line channel with
        | line -> collect (line :: acc)
        | exception End_of_file -> List.rev acc
        | exception _ -> List.rev acc
      in
      collect []
    in
    match Unix.close_process_in channel with
    | Unix.WEXITED 0 -> lines
    | Unix.WEXITED code ->
        raise
          (Corpus_unreadable
             (Printf.sprintf "git ls-files exited %d for root %s — the corpus is UNDETERMINED, not empty"
                code root))
    | _ ->
        raise
          (Corpus_unreadable
             (Printf.sprintf "git ls-files was signalled for root %s — the corpus is UNDETERMINED" root))
  in
  List.filter_map
    (fun path ->
      if Filename.check_suffix path ".md" && Sys.file_exists path then
        Some (read_file path)
      else None)
    (List.sort compare paths)

let read_tree root =
  let rec walk dir acc =
    if Sys.file_exists dir && Sys.is_directory dir then
      Array.fold_left
        (fun acc name ->
          let path = Filename.concat dir name in
          if Sys.is_directory path then walk path acc
          else if Filename.check_suffix path ".md" then path :: acc
          else acc)
        acc (Sys.readdir dir)
    else acc
  in
  let read path =
    let channel = open_in_bin path in
    let n = in_channel_length channel in
    let content = really_input_string channel n in
    close_in channel;
    (path, content)
  in
  List.map read (List.sort compare (walk root []))

(* HW.4.1.5 — the inverse typed edge. See the mli: the outgoing direction
   is on the page, this is the incoming one. *)
let typed_backlinks m slug =
  m.pages
  |> List.concat_map (fun p ->
         List.filter_map
           (fun (target, rel) -> if target = slug then Some (p.slug, rel) else None)
           p.typed)
  |> List.sort_uniq compare
