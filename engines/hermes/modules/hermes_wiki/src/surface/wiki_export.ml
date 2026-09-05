(* The export surfaces — see wiki_export.mli for the six laws.

   Every emitter here is a fold over a value the engine already
   computed: the built model (HW.6.2.1), the rendered page bytes
   (HW.6.9.2), one `Wiki_ast.parse` (HW.6.9.3 and HW.6.5.1), the online
   search engine's own answers (HW.6.3.7). Nothing re-reads the corpus
   and nothing re-derives a score, because a second derivation is the
   only thing that can drift from the first. *)

(* ------------------------------------------------------------ shared *)

let html_escape text =
  let b = Buffer.create (String.length text + 8) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | '\'' -> Buffer.add_string b "&#39;"
      | c -> Buffer.add_char b c)
    text;
  Buffer.contents b

(* A COMPLETE JSON string literal. No byte is dropped: `\r` is emitted
   as `\r` rather than discarded, because an export that quietly loses a
   byte disagrees with the corpus about the corpus. *)
let json_string s =
  let b = Buffer.create (String.length s + 16) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\b' -> Buffer.add_string b "\\b"
      | '\012' -> Buffer.add_string b "\\f"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let json_array items = "[" ^ String.concat "," items ^ "]"
let json_strings xs = json_array (List.map json_string xs)

let starts_at s i pat =
  let n = String.length pat in
  i + n <= String.length s && String.sub s i n = pat

(* The plain-text inline renderer: removes MARKUP, never TEXT. *)
let rec inline_text_raw s =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if starts_at s !i "![[" then i := !i + 3
    else if starts_at s !i "[[" then i := !i + 2
    else if starts_at s !i "]]" then i := !i + 2
    else if (s.[!i] = '[' || (s.[!i] = '!' && !i + 1 < n && s.[!i + 1] = '['))
            && not (starts_at s !i "[[")
    then begin
      (* `[text](url)` / `![alt](url)` — keep the text, drop the target *)
      let open_bracket = if s.[!i] = '!' then !i + 1 else !i in
      match String.index_from_opt s open_bracket ']' with
      | Some close when close + 1 < n && s.[close + 1] = '(' -> (
          match String.index_from_opt s (close + 1) ')' with
          | Some rparen ->
              Buffer.add_string b
                (inline_text_raw (String.sub s (open_bracket + 1) (close - open_bracket - 1)));
              i := rparen + 1
          | None ->
              Buffer.add_char b s.[!i];
              incr i)
      | _ ->
          Buffer.add_char b s.[!i];
          incr i
    end
    else if s.[!i] = '*' || s.[!i] = '`' || s.[!i] = '~' then incr i
    else begin
      Buffer.add_char b s.[!i];
      incr i
    end
  done;
  Buffer.contents b

(* TOTALITY CLAUSE: text that is entirely markup is returned verbatim —
   a render that turns a heading into nothing has deleted a section. *)
let inline_text s =
  let stripped = inline_text_raw s in
  if String.trim stripped = "" && String.trim s <> "" then s else stripped

(* The one page order this module uses, everywhere: SLUG, ascending.
   `Wiki_ordering`'s authored order is not in this dependency closure,
   and a silently different order would make two exports of one corpus
   differ. *)
let sorted_pages (m : Hermes_wiki.model) =
  List.sort
    (fun (a : Hermes_wiki.page) (b : Hermes_wiki.page) ->
      compare a.Hermes_wiki.slug b.Hermes_wiki.slug)
    m.Hermes_wiki.pages

let is_alnum c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

(* ----------------------------------- HW.6.9.3 plain-text export *)

let underline_char level =
  match level with 1 -> '=' | 2 -> '-' | 3 -> '~' | _ -> '^'

let level_of_underline c =
  match c with '=' -> Some 1 | '-' -> Some 2 | '~' -> Some 3 | '^' -> Some 4 | _ -> None

let indent_of n = String.make (3 * n) ' '

let flatten s =
  String.concat " " (String.split_on_char '\n' s) |> String.trim

let block_text s = inline_text (fst (Wiki_ast.block_anchor_split s))

let rec text_lines indent (bs : Wiki_ast.t) = List.concat_map (block_lines indent) bs

and block_lines indent (b : Wiki_ast.block) =
  let pad = indent_of indent in
  match b with
  | Wiki_ast.Heading h ->
      (* NEVER indented: [text_headings] reads the underline against the
         label's own length, and a shifted label would not read back. *)
      let label = inline_text h.text in
      [ ""; label; String.make (max 1 (String.length label)) (underline_char h.level) ]
  | Wiki_ast.Para s -> [ ""; pad ^ flatten (block_text s) ]
  | Wiki_ast.Inline_run s -> [ pad ^ flatten (block_text s) ]
  | Wiki_ast.Rule -> [ ""; pad ^ "* * * *" ]
  | Wiki_ast.Fence f ->
      (* KEPT and indented. A text render of a document containing code
         that omits the code is not a render of that document. The
         indent also guarantees no fence line reads as an underline. *)
      "" :: List.map (fun line -> pad ^ "    " ^ line) f.body
  | Wiki_ast.Table rows ->
      ""
      :: List.map
           (fun (r : Wiki_ast.row) ->
             pad ^ "  " ^ String.concat " | " (List.map block_text r.cells))
           rows
  | Wiki_ast.Quote bs -> "" :: text_lines (indent + 1) bs
  | Wiki_ast.Callout c ->
      let title = block_text c.header.Wiki_callout.title in
      ("" :: [ pad ^ "[!] " ^ flatten title ]) @ text_lines (indent + 1) c.body
  | Wiki_ast.List_block l ->
      let n = ref (l.start - 1) in
      ""
      :: List.concat_map
           (fun (item : Wiki_ast.list_content) ->
             match item with
             | Wiki_ast.Loose blk -> block_lines (indent + 1) blk
             | Wiki_ast.Item it ->
                 incr n;
                 let marker = if l.ordered then Printf.sprintf "%d. " !n else "- " in
                 let task =
                   match it.task with None -> "" | Some true -> "[x] " | Some false -> "[ ] "
                 in
                 let inner =
                   text_lines (indent + 1) it.body
                   |> List.filter (fun line -> String.trim line <> "")
                 in
                 (match inner with
                 | [] -> [ pad ^ marker ^ task ]
                 | first :: rest ->
                     (pad ^ marker ^ task ^ String.trim first)
                     :: List.map (fun line -> indent_of (indent + 1) ^ String.trim line) rest))
           l.content

let render_text_lines raw = text_lines 0 (Wiki_ast.parse raw)

let page_text raw =
  match render_text_lines raw with
  | [] -> ""
  | lines -> String.concat "\n" lines ^ "\n"

let plain_text m =
  sorted_pages m
  |> List.map (fun (p : Hermes_wiki.page) -> page_text p.Hermes_wiki.raw)
  |> String.concat "\n* * * *\n"

let text_headings s =
  let lines = Array.of_list (String.split_on_char '\n' s) in
  let out = ref [] in
  Array.iteri
    (fun i line ->
      if i + 1 < Array.length lines && String.length line > 0 then begin
        let under = lines.(i + 1) in
        if String.length under = String.length line then
          match level_of_underline under.[0] with
          | Some level when String.for_all (fun c -> c = under.[0]) under ->
              out := (level, line) :: !out
          | _ -> ()
      end)
    lines;
  List.rev !out

(* ---------------------------------------- HW.6.5.1 word count *)

let count_words text =
  let count = ref 0 and alnum = ref false and inside = ref false in
  let close () =
    if !inside && !alnum then incr count;
    inside := false;
    alnum := false
  in
  String.iter
    (fun c ->
      match c with
      | ' ' | '\t' | '\n' | '\r' | '\012' -> close ()
      | c ->
          inside := true;
          if is_alnum c then alnum := true)
    text;
  close ();
  !count

let rec block_words (b : Wiki_ast.block) =
  match b with
  (* FENCE-EXCLUDED BY CONSTRUCTION: this arm contributes ZERO, and it
     is the parser — not a line filter — that decided this is a fence. *)
  | Wiki_ast.Fence _ -> 0
  | Wiki_ast.Rule -> 0
  | Wiki_ast.Para s | Wiki_ast.Inline_run s -> count_words (block_text s)
  | Wiki_ast.Heading h -> count_words (block_text h.text)
  | Wiki_ast.Table rows ->
      List.fold_left
        (fun acc (r : Wiki_ast.row) ->
          acc + List.fold_left (fun a c -> a + count_words (block_text c)) 0 r.cells)
        0 rows
  | Wiki_ast.Quote bs -> List.fold_left (fun a b -> a + block_words b) 0 bs
  | Wiki_ast.Callout c ->
      count_words (block_text c.header.Wiki_callout.title)
      + List.fold_left (fun a b -> a + block_words b) 0 c.body
  | Wiki_ast.List_block l ->
      List.fold_left
        (fun acc (item : Wiki_ast.list_content) ->
          match item with
          | Wiki_ast.Loose b -> acc + block_words b
          | Wiki_ast.Item it -> acc + List.fold_left (fun a b -> a + block_words b) 0 it.body)
        0 l.content

let word_count raw =
  List.fold_left (fun a b -> a + block_words b) 0 (Wiki_ast.parse raw)

let page_word_counts m =
  sorted_pages m
  |> List.map (fun (p : Hermes_wiki.page) ->
         (p.Hermes_wiki.slug, word_count p.Hermes_wiki.raw))

let corpus_word_count m = List.fold_left (fun a (_, n) -> a + n) 0 (page_word_counts m)

(* ------------------------------------------------- HW.6.2.1 JSON API *)

let json_slugs m = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) (sorted_pages m)

let json_page m (p : Hermes_wiki.page) =
  let field k v = json_string k ^ ":" ^ v in
  String.concat ","
    [ "{" ^ field "slug" (json_string p.Hermes_wiki.slug);
      field "path" (json_string p.Hermes_wiki.path);
      field "title" (json_string p.Hermes_wiki.title);
      field "group" (json_string p.Hermes_wiki.group);
      field "id" (json_string p.Hermes_wiki.meta.Hermes_wiki.id);
      field "type" (json_string p.Hermes_wiki.meta.Hermes_wiki.ntype);
      field "status" (json_string p.Hermes_wiki.meta.Hermes_wiki.status);
      (* clause 2: the IDENTICAL bytes the HTML surface serves — carried
         through, never re-rendered. Re-rendering here is exactly how
         the two surfaces would come to disagree. *)
      field "html" (json_string p.Hermes_wiki.html);
      (* clause 3: the anchors a deep link may name *)
      field "anchors" (json_strings (Hermes_wiki.anchors m p.Hermes_wiki.slug));
      field "headings"
        (json_array
           (List.map
              (fun (level, text, anchor) ->
                Printf.sprintf "{%s:%d,%s:%s,%s:%s}" (json_string "level") level
                  (json_string "text") (json_string text) (json_string "anchor")
                  (json_string anchor))
              p.Hermes_wiki.headings));
      field "outlinks" (json_strings p.Hermes_wiki.outlinks);
      field "backlinks" (json_strings p.Hermes_wiki.backlinks);
      field "tags" (json_strings p.Hermes_wiki.tags);
      field "words" (string_of_int (word_count p.Hermes_wiki.raw)) ^ "}" ]

let json m =
  let pages = List.map (json_page m) (sorted_pages m) in
  (* Anomalies travel too: an export that quietly dropped them would
     report a corpus healthier than the builder believes it to be. *)
  "{" ^ json_string "pages" ^ ":" ^ json_array pages ^ "," ^ json_string "anomalies" ^ ":"
  ^ json_strings m.Hermes_wiki.anomalies ^ "}"

(* --------------------------------- HW.6.9.2 single-file HTML export *)

(* The one global anchor table. Uniqueness is a property of THIS
   algorithm — a claimed name is disambiguated with a counter, mirroring
   Hermes_wiki's slug disambiguator — and not of an injectivity argument
   about separators that a future block-id alphabet could invalidate. *)
type anchor_table = {
  claimed : (string, unit) Hashtbl.t;
  (* (slug, anchor) -> qualified name of its FIRST occurrence. A link
     resolves to the first matching id, exactly as a browser does. *)
  first : (string * string, string) Hashtbl.t;
  (* slug -> the qualified ids of that page, in emission order. A page
     may legitimately carry the SAME block id twice (the engine reports
     it and still emits both); each OCCURRENCE therefore claims its own
     name, or the concatenation would contain a duplicate anchor and
     this row's law would be false on a corpus the engine accepts. *)
  queues : (string, string Queue.t) Hashtbl.t;
}

let claim tbl base =
  let rec unique candidate n =
    if not (Hashtbl.mem tbl.claimed candidate) then candidate
    else unique (Printf.sprintf "%s-%d" base n) (n + 1)
  in
  let name = unique base 2 in
  Hashtbl.replace tbl.claimed name ();
  name

(* Attribute values in a rendered page are safe to scan for a closing
   double quote: the engine escapes an authored one to &quot;, so the
   closing delimiter is never an authored byte. *)
let attribute_value html i =
  match String.index_from_opt html i '"' with
  | Some close -> Some (String.sub html i (close - i), close + 1)
  | None -> None

let ids_of_html html =
  let out = ref [] and i = ref 0 in
  let n = String.length html in
  while !i < n do
    if starts_at html !i " id=\"" then (
      match attribute_value html (!i + 5) with
      | Some (v, next) ->
          out := v :: !out;
          i := next
      | None -> incr i)
    else incr i
  done;
  List.rev !out

let build_table m =
  let tbl =
    { claimed = Hashtbl.create 256; first = Hashtbl.create 256; queues = Hashtbl.create 64 }
  in
  List.iter
    (fun (p : Hermes_wiki.page) ->
      let slug = p.Hermes_wiki.slug in
      Hashtbl.replace tbl.first (slug, "") (claim tbl ("page-" ^ slug));
      let q = Queue.create () in
      List.iter
        (fun id ->
          let name = claim tbl (slug ^ "--" ^ id) in
          if not (Hashtbl.mem tbl.first (slug, id)) then
            Hashtbl.replace tbl.first (slug, id) name;
          Queue.add name q)
        (ids_of_html p.Hermes_wiki.html);
      Hashtbl.replace tbl.queues slug q)
    (sorted_pages m);
  tbl

(* A fragment with no registered anchor is a link that was ALREADY
   broken on the per-page surface. It keeps a qualified — and equally
   dangling — name: rewriting it to the page top would turn a visible
   defect into a reader landing on the wrong text. *)
let qualified tbl slug anchor =
  match Hashtbl.find_opt tbl.first (slug, anchor) with
  | Some q -> q
  | None -> if anchor = "" then "page-" ^ slug else slug ^ "--" ^ anchor

(* The next id THIS page emits, in the order phase one claimed them. *)
let next_id tbl slug fallback =
  match Hashtbl.find_opt tbl.queues slug with
  | Some q when not (Queue.is_empty q) -> Queue.pop q
  | _ -> fallback

let split_fragment v =
  match String.index_opt v '#' with
  | None -> (v, None)
  | Some i -> (String.sub v 0 i, Some (String.sub v (i + 1) (String.length v - i - 1)))

let strip_html_suffix s =
  let n = String.length s in
  if n > 5 && String.sub s (n - 5) 5 = ".html" then String.sub s 0 (n - 5) else s

let rewrite_page tbl slugs tbl_slug html ~anchors ~links =
  let b = Buffer.create (String.length html + 64) in
  let n = String.length html in
  let i = ref 0 in
  let emit_link target =
    links := target :: !links;
    Buffer.add_string b ("#" ^ target)
  in
  while !i < n do
    if starts_at html !i " id=\"" then (
      match attribute_value html (!i + 5) with
      | Some (v, next) ->
          let q = next_id tbl tbl_slug (qualified tbl tbl_slug v) in
          anchors := q :: !anchors;
          Buffer.add_string b (" id=\"" ^ q ^ "\"");
          i := next
      | None ->
          Buffer.add_char b html.[!i];
          incr i)
    else if starts_at html !i " href=\"" then (
      match attribute_value html (!i + 7) with
      | Some (v, next) ->
          Buffer.add_string b " href=\"";
          (if String.length v > 0 && v.[0] = '#' then
             emit_link (qualified tbl tbl_slug (String.sub v 1 (String.length v - 1)))
           else
             let doc, frag = split_fragment v in
             let base = strip_html_suffix doc in
             if base <> "" && List.mem base slugs then
               emit_link (qualified tbl base (match frag with None -> "" | Some f -> f))
             else
               (* not this document's link to rewrite *)
               Buffer.add_string b v);
          Buffer.add_string b "\"";
          i := next
      | None ->
          Buffer.add_char b html.[!i];
          incr i)
    else begin
      Buffer.add_char b html.[!i];
      incr i
    end
  done;
  Buffer.contents b

(* ONE emission; the three observations are projections of it, so a law
   about the document is never checked against a re-derivation of it. *)
let emit m =
  let tbl = build_table m in
  let pages = sorted_pages m in
  let slugs = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) pages in
  let anchors = ref [] and links = ref [] in
  let b = Buffer.create 8192 in
  Buffer.add_string b
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n\
     <title>Hermes wiki — single file</title>\n</head>\n<body>\n";
  Buffer.add_string b "<nav class=\"export-toc\">\n<ol>\n";
  List.iter
    (fun (p : Hermes_wiki.page) ->
      let q = qualified tbl p.Hermes_wiki.slug "" in
      links := q :: !links;
      Buffer.add_string b
        (Printf.sprintf "<li><a href=\"#%s\">%s</a></li>\n" q
           (html_escape p.Hermes_wiki.title)))
    pages;
  Buffer.add_string b "</ol>\n</nav>\n";
  List.iter
    (fun (p : Hermes_wiki.page) ->
      let q = qualified tbl p.Hermes_wiki.slug "" in
      anchors := q :: !anchors;
      Buffer.add_string b (Printf.sprintf "<section id=\"%s\" class=\"export-page\">\n" q);
      Buffer.add_string b
        (rewrite_page tbl slugs p.Hermes_wiki.slug p.Hermes_wiki.html ~anchors ~links);
      Buffer.add_string b "</section>\n")
    pages;
  Buffer.add_string b "</body>\n</html>\n";
  (Buffer.contents b, List.rev !anchors, List.rev !links)

let single_file_html m = let h, _, _ = emit m in h
let single_file_anchors m = let _, a, _ = emit m in a
let single_file_links m = let _, _, l = emit m in l

let dead_links m =
  let _, anchors, links = emit m in
  links |> List.filter (fun l -> not (List.mem l anchors)) |> List.sort_uniq compare

(* -------------------------------- HW.6.10.1 extlinks (shortening) *)

type extlink = { name : string; base : string; caption : string }

let extlink_table defs =
  let names = List.map (fun d -> d.name) defs in
  let dups =
    names
    |> List.filter (fun n -> List.length (List.filter (fun m -> m = n) names) > 1)
    |> List.sort_uniq compare
  in
  if dups = [] then Ok defs else Error dups

let is_name_char c = is_alnum c || c = '_' || c = '-'

(* `:name:`value`` at [i], or None. TOTAL: an unterminated form is text. *)
let extlink_at line i =
  if line.[i] <> ':' then None
  else
    let n = String.length line in
    let j = ref (i + 1) in
    while !j < n && is_name_char line.[!j] do incr j done;
    if !j = i + 1 || !j >= n || line.[!j] <> ':' then None
    else if !j + 1 >= n || line.[!j + 1] <> '`' then None
    else
      let name = String.sub line (i + 1) (!j - i - 1) in
      match String.index_from_opt line (!j + 2) '`' with
      | None -> None
      | Some close ->
          let value = String.sub line (!j + 2) (close - !j - 2) in
          Some (name, value, close + 1)

let is_fence_line line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

(* A use inside a fence is an EXAMPLE, not a use — the convention the
   rest of this corpus keeps for wikilinks, tags and embeds. *)
let scan_body body f =
  let in_fence = ref false in
  String.split_on_char '\n' body
  |> List.map (fun line ->
         if is_fence_line line then (
           in_fence := not !in_fence;
           line)
         else if !in_fence then line
         else f line)

let extlink_uses body =
  let out = ref [] in
  ignore
    (scan_body body (fun line ->
         let n = String.length line in
         let i = ref 0 in
         while !i < n do
           match extlink_at line !i with
           | Some (name, value, next) ->
               out := (name, value) :: !out;
               i := next
           | None -> incr i
         done;
         line));
  List.rev !out

let substitute pattern value =
  let n = String.length pattern in
  let b = Buffer.create (n + String.length value) in
  let i = ref 0 and hit = ref false in
  while !i < n do
    if starts_at pattern !i "%s" then (
      Buffer.add_string b value;
      hit := true;
      i := !i + 2)
    else begin
      Buffer.add_char b pattern.[!i];
      incr i
    end
  done;
  (Buffer.contents b, !hit)

let expand_extlinks defs body =
  let expand_line line =
    let n = String.length line in
    let b = Buffer.create (n + 32) in
    let i = ref 0 in
    while !i < n do
      match extlink_at line !i with
      | Some (name, value, next) -> (
          match List.find_opt (fun d -> d.name = name) defs with
          | None ->
              (* UNDEFINED stays VERBATIM: a text a reader can fix,
                 never a link to nowhere. *)
              Buffer.add_string b (String.sub line !i (next - !i));
              i := next
          | Some d ->
              let href, hit = substitute d.base value in
              let href = if hit then href else href ^ value in
              let text =
                if d.caption = "" then href else fst (substitute d.caption value)
              in
              Buffer.add_string b
                (Printf.sprintf "<a href=\"%s\">%s</a>" (html_escape href) (html_escape text));
              i := next)
      | None ->
          Buffer.add_char b line.[!i];
          incr i
    done;
    Buffer.contents b
  in
  String.concat "\n" (scan_body body expand_line)

(* ------------------------- HW.6.3.7 client-side search index *)

type search_index = {
  tokenise : string -> string list;
  posts : (string * (string * int) list) list; (* sorted by token *)
  digest : string;
}

let search_index ~tokenise ~search ~digest (m : Hermes_wiki.model) =
  let vocabulary =
    m.Hermes_wiki.pages
    |> List.concat_map (fun (p : Hermes_wiki.page) ->
           tokenise p.Hermes_wiki.raw @ tokenise p.Hermes_wiki.title
           @ List.concat_map (fun (_, text, _) -> tokenise text) p.Hermes_wiki.headings
           @ List.concat_map tokenise p.Hermes_wiki.meta.Hermes_wiki.keywords
           @ tokenise p.Hermes_wiki.meta.Hermes_wiki.description)
    |> List.sort_uniq compare
  in
  (* The postings ARE the online engine's answers — there is no scoring
     here to drift from the scoring there. *)
  let posts =
    vocabulary
    |> List.filter_map (fun t -> match search t with [] -> None | ps -> Some (t, ps))
  in
  { tokenise; posts; digest }

let vocabulary idx = List.map fst idx.posts
let postings idx t = match List.assoc_opt t idx.posts with Some ps -> ps | None -> []
let index_digest idx = idx.digest

let offline_search idx q =
  match idx.tokenise q with
  | [] -> []
  | qs ->
      let head = postings idx (List.hd qs) in
      head
      |> List.filter_map (fun (slug, _) ->
             let scores =
               List.map
                 (fun t -> Option.value ~default:0 (List.assoc_opt slug (postings idx t)))
                 qs
             in
             if List.exists (fun s -> s = 0) scores then None
             else Some (slug, List.fold_left ( + ) 0 scores))
      |> List.sort (fun (s1, x1) (s2, x2) -> if x1 = x2 then compare s1 s2 else compare x2 x1)

let index_canonical idx =
  let b = Buffer.create 4096 in
  List.iter
    (fun (t, ps) ->
      List.iter (fun (slug, score) -> Buffer.add_string b (Printf.sprintf "%s %s %d\n" t slug score)) ps)
    idx.posts;
  Buffer.contents b

let index_json idx =
  let entry (t, ps) =
    json_string t ^ ":"
    ^ json_array
        (List.map (fun (slug, score) -> "[" ^ json_string slug ^ "," ^ string_of_int score ^ "]") ps)
  in
  "{" ^ json_string "digest" ^ ":" ^ json_string idx.digest ^ "," ^ json_string "postings" ^ ":{"
  ^ String.concat "," (List.map entry idx.posts)
  ^ "}}"
