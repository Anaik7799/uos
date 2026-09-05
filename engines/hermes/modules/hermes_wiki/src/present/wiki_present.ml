(* The PRESENTATION family. See the mli for the laws; this file is their
   mechanism. Pure throughout: no filesystem, no Unix, no clock. *)

(* ------------------------------------------------------------ helpers *)

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

let index_from hay needle start =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = if i + nn > nh then None else if String.sub hay i nn = needle then Some i else go (i + 1) in
  if nn = 0 then None else go (max 0 start)

let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r'
let is_digit c = c >= '0' && c <= '9'
let is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_ident_start c = is_alpha c || c = '_'
let is_ident c = is_alpha c || is_digit c || c = '_' || c = '\''
let strip_spaces s = String.concat "" (List.filter (fun x -> x <> "")
  (List.map (fun c -> if is_space c then "" else String.make 1 c)
     (List.init (String.length s) (String.get s))))

let sort_uniq = List.sort_uniq compare

(* --------------------------------------------------------- the escaper *)

(* The four-entity map of the corpus escaper. `&` FIRST in the sense that
   it is itself replaced, which is what makes the map injective and
   [unescape] its exact inverse. *)
let escape text =
  let b = Buffer.create (String.length text) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    text;
  Buffer.contents b

let unescape text =
  let n = String.length text in
  let b = Buffer.create n in
  let entities = [ ("&amp;", '&'); ("&lt;", '<'); ("&gt;", '>'); ("&quot;", '"') ] in
  let rec go i =
    if i >= n then ()
    else if text.[i] = '&' then
      match
        List.find_opt
          (fun (e, _) ->
            let m = String.length e in
            i + m <= n && String.sub text i m = e)
          entities
      with
      | Some (e, c) -> Buffer.add_char b c; go (i + String.length e)
      | None -> Buffer.add_char b '&'; go (i + 1)
    else (Buffer.add_char b text.[i]; go (i + 1))
  in
  go 0;
  Buffer.contents b

let strip_markup html =
  let n = String.length html in
  let b = Buffer.create n in
  let rec go i in_tag =
    if i >= n then ()
    else
      match (html.[i], in_tag) with
      | '<', false -> go (i + 1) true
      | '>', true -> go (i + 1) false
      | _, true -> go (i + 1) true
      | c, false -> Buffer.add_char b c; go (i + 1) false
  in
  go 0 false;
  unescape (Buffer.contents b)

(* An `on…=` attribute is only an event handler INSIDE a tag; the word
   "one=" in prose is not markup. Tracking the tag state keeps this from
   refusing honest text. *)
let has_script html =
  let low = String.lowercase_ascii html in
  let n = String.length low in
  let handler =
    let rec scan i in_tag =
      if i >= n then false
      else
        match low.[i] with
        | '<' -> scan (i + 1) true
        | '>' -> scan (i + 1) false
        | 'o' when in_tag && i > 0 && is_space low.[i - 1] && i + 2 < n && low.[i + 1] = 'n' ->
            let rec name j = if j < n && is_alpha low.[j] then name (j + 1) else j in
            let e = name (i + 2) in
            if e > i + 2 && e < n && low.[e] = '=' then true else scan (i + 1) in_tag
        | _ -> scan (i + 1) in_tag
    in
    scan 0 false
  in
  contains low "<script" || contains low "javascript:" || handler

(* ================================================ HW.7.1.2 — dark mode *)

type mode = Light | Dark

let modes = [ Light; Dark ]
let mode_name = function Light -> "light" | Dark -> "dark"

(* THE TWO PALETTES. Same keys, every value rebound — the law is visible
   here, by reading down the two columns, and checked by the suite. *)
let light_palette =
  [ ("color/accent", "#0c6cb0");
    ("color/bg", "#ffffff");
    ("color/border", "#e5e7eb");
    ("color/code-bg", "#f4f2ee");
    ("color/ink", "#1a1a1a");
    ("color/mark", "#fff3b0");
    ("color/muted", "#5c6a70");
    ("color/surface", "#f6f8fa") ]

let dark_palette =
  [ ("color/accent", "#58a6ff");
    ("color/bg", "#0d1117");
    ("color/border", "#30363d");
    ("color/code-bg", "#101a1e");
    ("color/ink", "#e6edf3");
    ("color/mark", "#4d3f00");
    ("color/muted", "#8b949e");
    ("color/surface", "#161b22") ]

let palette = function Light -> light_palette | Dark -> dark_palette
let token_keys m = List.sort compare (List.map fst (palette m))
let variable_of_key k = "--" ^ String.map (fun c -> if c = '/' then '-' else c) k
let qualified m k = mode_name m ^ "/" ^ k

let theme_tokens =
  List.concat_map
    (fun m ->
      List.map (fun (k, v) -> { Wiki_theme.path = qualified m k; value = v }) (palette m))
    modes

let theme_themes =
  List.map
    (fun m ->
      { Wiki_theme.mode = mode_name m;
        bindings = List.map (fun (k, _) -> (variable_of_key k, qualified m k)) (palette m) })
    modes

(* The no-script leg. `:not([data-theme="light"])` is load-bearing: without
   it an explicit light choice would be overridden by the operating
   system's preference (R14 mirror: wiki_theme_token_injector). Built from
   the SAME sorted palette, with the SAME `/* token path */` annotation
   Wiki_theme emits, so the two blocks cannot drift. *)
let dark_media_css =
  let b = Buffer.create 512 in
  Buffer.add_string b "\n@media (prefers-color-scheme: dark) {\n";
  Buffer.add_string b "  :root:not([data-theme=\"light\"]) {\n";
  List.iter
    (fun (k, v) ->
      Buffer.add_string b
        (Printf.sprintf "    %s: %s; /* %s */\n" (variable_of_key k) v (qualified Dark k)))
    (List.sort compare (palette Dark));
  Buffer.add_string b "  }\n}\n";
  Buffer.contents b

let theme_css =
  match Wiki_theme.css ~tokens:theme_tokens ~themes:theme_themes with
  | Error e -> Error e
  | Ok base -> Ok (base ^ dark_media_css)

let declared_variables css =
  let n = String.length css in
  let is_var c = is_alpha c || is_digit c || c = '-' || c = '_' in
  let rec go i acc =
    if i + 1 >= n then acc
    else if css.[i] = '-' && css.[i + 1] = '-' && (i = 0 || not (is_var css.[i - 1])) then
      let rec name j = if j < n && is_var css.[j] then name (j + 1) else j in
      let e = name (i + 2) in
      let rec skip j = if j < n && is_space css.[j] then skip (j + 1) else j in
      let c = skip e in
      if e > i + 2 && c < n && css.[c] = ':' then go e (String.sub css i (e - i) :: acc)
      else go e acc
    else go (i + 1) acc
  in
  sort_uniq (go 0 [])

(* ========================================= HW.7.1.3 — print stylesheet *)

let print_chrome =
  [ ".back-to-top"; ".skip-link"; ".wiki-nav"; ".wiki-pagination"; ".wiki-search";
    ".wiki-sidebar"; ".wiki-theme-toggle"; ".wiki-toc" ]

let print_content =
  [ "blockquote"; "code"; "figcaption"; "figure"; "h1"; "h2"; "h3"; "img"; "li"; "main";
    "mark"; "p"; "pre"; "table"; ".wiki-caption-ref"; ".wiki-code"; ".wiki-main" ]

(* The hidden list is BUILT FROM [print_chrome], so declaring a content
   selector to be chrome makes it actually disappear — which is what makes
   the disjointness leg of the law worth checking. *)
let print_css =
  "\n@media print {\n" ^ "  " ^ String.concat ", " print_chrome ^ " { display: none; }\n"
  ^ "  a[href]::after { content: \" (\" attr(href) \")\"; font-size: 0.85em; word-break: break-all; }\n"
  ^ "  a[href^=\"#\"]::after { content: \"\"; }\n"
  ^ "  .wiki-main { max-width: none; margin: 0; padding: 0; }\n"
  ^ "  pre, blockquote, figure, table { break-inside: avoid; page-break-inside: avoid; }\n"
  ^ "  pre, .wiki-code { white-space: pre-wrap; word-break: break-word; }\n"
  ^ "  h1, h2, h3 { break-after: avoid; page-break-after: avoid; }\n"
  ^ "  mark, mark.wiki-hl { background: none; border-left: 3px solid #000; padding-left: 5px; }\n"
  ^ "}\n"

(* Scoped to the `@media print` block: the dark-mode media query nests
   braces too, and a parser blind to scope would read its rules as print
   rules. Total — an unbalanced brace yields what has been read. *)
let hidden_selectors css =
  let n = String.length css in
  match index_from css "@media print" 0 with
  | None -> []
  | Some at -> (
      let rec brace i = if i >= n then None else if css.[i] = '{' then Some i else brace (i + 1) in
      match brace at with
      | None -> []
      | Some ob ->
          let acc = ref [] in
          let i = ref (ob + 1) and stop = ref false in
          let sel = Buffer.create 64 in
          while (not !stop) && !i < n do
            match css.[!i] with
            | '}' -> stop := true
            | '{' ->
                let selector = String.trim (Buffer.contents sel) in
                Buffer.clear sel;
                let j = ref (!i + 1) and d = ref 1 in
                let db = Buffer.create 64 in
                while !d > 0 && !j < n do
                  (if css.[!j] = '{' then incr d else if css.[!j] = '}' then decr d);
                  if !d > 0 then Buffer.add_char db css.[!j];
                  incr j
                done;
                if contains (strip_spaces (Buffer.contents db)) "display:none" then
                  acc :=
                    !acc
                    @ List.filter
                        (fun s -> s <> "")
                        (List.map String.trim (String.split_on_char ',' selector));
                i := !j
            | c -> Buffer.add_char sel c; incr i
          done;
          !acc)

let print_violations () =
  let hidden = hidden_selectors print_css in
  let undeclared =
    List.filter_map
      (fun s ->
        if List.mem s print_chrome then None
        else
          Some
            (Printf.sprintf
               "@media print hides %s, which is not declared chrome — content that vanishes on paper vanishes silently"
               s))
      hidden
  in
  let confused =
    List.filter_map
      (fun s ->
        if List.mem s print_content then
          Some
            (Printf.sprintf
               "%s is declared BOTH chrome and content — the two sets must be disjoint or \"hidden is only chrome\" proves nothing"
               s)
        else None)
      print_chrome
  in
  let erased =
    List.filter_map
      (fun s ->
        if List.mem s hidden then
          Some (Printf.sprintf "%s carries content and is display:none in print" s)
        else None)
      print_content
  in
  let undisclosed =
    if contains print_css "attr(href)" then []
    else
      [ "the print rules do not disclose attr(href) — paper has no hyperlinks, so an undisclosed \
         URL is content lost" ]
  in
  undeclared @ confused @ erased @ undisclosed

(* ================================ HW.7.2.2 / HW.7.2.3 — the two anchors *)

let top_id = "top"
let main_id = "main"

(* The fragment and the landmark are written out SEPARATELY, on purpose:
   a surface may place the fragment anywhere, so the two really can drift,
   and [dangling_anchors] over the assembled page is what catches it. *)
let skip_link_html = "<a class=\"skip-link\" href=\"#main\">Skip to content</a>\n"
let top_landmark_html = "<span id=\"top\" class=\"wiki-top\" aria-hidden=\"true\"></span>\n"

let back_to_top_html =
  "<a class=\"back-to-top\" href=\"#top\" title=\"Back to the top of the page\">Back to top</a>\n"

let document_chrome ~content =
  String.concat ""
    [ skip_link_html;
      top_landmark_html;
      "<main id=\"main\" class=\"wiki-main\">\n";
      content;
      "\n</main>\n";
      back_to_top_html ]

(* Off-screen, NEVER display:none — a display:none element leaves the
   focus order, so the commonest way to write this feature is also the
   way that breaks it. *)
let skip_link_css =
  "\n.skip-link { position: absolute; left: -9999px; top: 0; z-index: 100;\n\
  \  padding: 8px 14px; background: var(--color-surface); color: var(--color-ink);\n\
  \  border: 1px solid var(--color-border); border-radius: 0 0 6px 0; }\n\
   .skip-link:focus { left: 0; outline: 2px solid var(--color-accent); }\n"

let back_to_top_css =
  "\nhtml { scroll-behavior: smooth; }\n\
   .back-to-top { display: inline-block; margin: 32px 0 0; padding: 4px 12px;\n\
  \  font-size: 13px; text-decoration: none; color: var(--color-muted);\n\
  \  border: 1px solid var(--color-border); border-radius: 999px; }\n\
   .back-to-top:hover, .back-to-top:focus { color: var(--color-accent); border-color: var(--color-accent); }\n"

let attr_values html attr =
  let n = String.length html in
  let pat = attr ^ "=\"" in
  let m = String.length pat in
  let rec go i acc =
    match index_from html pat i with
    | None -> List.rev acc
    | Some k ->
        let s = k + m in
        let rec close j = if j >= n || html.[j] = '"' then j else close (j + 1) in
        let e = close s in
        go (min n (e + 1)) (String.sub html s (e - s) :: acc)
  in
  go 0 []

let anchor_ids html = attr_values html "id"

let internal_hrefs html =
  List.filter_map
    (fun h ->
      if String.length h > 1 && h.[0] = '#' then Some (String.sub h 1 (String.length h - 1))
      else None)
    (attr_values html "href")

let dangling_anchors html =
  let ids = anchor_ids html in
  sort_uniq (List.filter (fun f -> not (List.mem f ids)) (internal_hrefs html))

(* ============================== HW.7.3.1 / .2 / .4 — the code block *)

type language = Ocaml | Json | Shell

let languages =
  [ ("bash", Shell); ("json", Json); ("ml", Ocaml); ("mli", Ocaml); ("ocaml", Ocaml);
    ("sh", Shell); ("shell", Shell); ("zsh", Shell) ]

let language_of_lang = function
  | None -> None
  | Some l -> List.assoc_opt (String.lowercase_ascii (String.trim l)) languages

let code_classes = [ "language-json"; "language-ocaml"; "language-plaintext"; "language-shell" ]

let code_class = function
  | Some Ocaml -> "language-ocaml"
  | Some Json -> "language-json"
  | Some Shell -> "language-shell"
  | None -> "language-plaintext"

let label_of_lang = function
  | None -> None
  | Some l ->
      let t = String.trim l in
      if t = "" then None
      else
        Some
          (match String.lowercase_ascii t with
          | "ocaml" | "ml" | "mli" -> "OCaml"
          | "json" -> "JSON"
          | "sh" | "bash" | "shell" | "zsh" -> "Shell"
          | other -> String.uppercase_ascii other)

type tok = Kw | Str | Com | Num | Plain

let class_of_tok = function
  | Kw -> "tok-kw"
  | Str -> "tok-str"
  | Com -> "tok-com"
  | Num -> "tok-num"
  | Plain -> "tok-plain"

let ocaml_keywords =
  [ "and"; "as"; "begin"; "else"; "end"; "exception"; "external"; "false"; "fun"; "function";
    "if"; "in"; "include"; "let"; "match"; "module"; "mutable"; "of"; "open"; "rec"; "sig";
    "struct"; "then"; "true"; "try"; "type"; "val"; "when"; "while"; "with" ]

let json_keywords = [ "false"; "null"; "true" ]

let shell_keywords =
  [ "case"; "do"; "done"; "elif"; "else"; "esac"; "export"; "fi"; "for"; "function"; "if";
    "in"; "local"; "return"; "then"; "while" ]

let keywords_of = function
  | Ocaml -> ocaml_keywords
  | Json -> json_keywords
  | Shell -> shell_keywords

(* ONE LINE AT A TIME, no cross-line state. An unterminated string or
   comment is emitted PLAIN rather than colouring the remainder: with no
   state to carry, guessing would mis-colour every following line, and a
   wrong colour reads as a claim about the code. *)
let tokenize lang line =
  let n = String.length line in
  let out = ref [] in
  let plain = Buffer.create 32 in
  let flush () =
    if Buffer.length plain > 0 then (out := (Plain, Buffer.contents plain) :: !out; Buffer.clear plain)
  in
  let emit k s = flush (); out := (k, s) :: !out in
  let i = ref 0 in
  let close_quote q from =
    let rec go j =
      if j >= n then None
      else if line.[j] = '\\' && q = '"' then go (j + 2)
      else if line.[j] = q then Some (j + 1)
      else go (j + 1)
    in
    go from
  in
  while !i < n do
    let c = line.[!i] in
    let ml_comment = lang = Ocaml && c = '(' && !i + 1 < n && line.[!i + 1] = '*' in
    let hash_comment = lang = Shell && c = '#' && (!i = 0 || is_space line.[!i - 1]) in
    let quote = c = '"' || (c = '\'' && lang = Shell) in
    if ml_comment then (
      match index_from line "*)" (!i + 2) with
      | Some e -> emit Com (String.sub line !i (e + 2 - !i)); i := e + 2
      | None -> Buffer.add_char plain c; incr i)
    else if hash_comment then (emit Com (String.sub line !i (n - !i)); i := n)
    else if quote then (
      match close_quote c (!i + 1) with
      | Some e when e <= n -> emit Str (String.sub line !i (e - !i)); i := e
      | Some _ | None -> Buffer.add_char plain c; incr i)
    else if is_digit c && (!i = 0 || not (is_ident line.[!i - 1])) then (
      let j = ref !i in
      while !j < n && (is_digit line.[!j] || line.[!j] = '.') do incr j done;
      emit Num (String.sub line !i (!j - !i));
      i := !j)
    else if is_ident_start c then (
      let j = ref !i in
      while !j < n && is_ident line.[!j] do incr j done;
      let word = String.sub line !i (!j - !i) in
      if List.mem word (keywords_of lang) then emit Kw word else Buffer.add_string plain word;
      i := !j)
    else (Buffer.add_char plain c; incr i)
  done;
  flush ();
  List.rev !out

(* Tokenize RAW, escape per token, then wrap. Escaping before tokenizing
   would shift every offset and make `&amp;` look like content. *)
let render_toks toks =
  let b = Buffer.create 128 in
  List.iter
    (fun (k, s) ->
      let e = escape s in
      match k with
      | Plain -> Buffer.add_string b e
      | Kw | Str | Com | Num ->
          Buffer.add_string b (Printf.sprintf "<span class=\"%s\">%s</span>" (class_of_tok k) e))
    toks;
  Buffer.contents b

let highlight_line lang line =
  match lang with None -> escape line | Some l -> render_toks (tokenize l line)

type diagnostic =
  | Highlight_out_of_range of { requested : int; line_count : int }
  | Highlight_not_positive of { requested : int }

let describe = function
  | Highlight_out_of_range { requested; line_count } ->
      Printf.sprintf
        "line %d is highlighted but the block has %d lines — the range is NOT clamped, because \
         marking a line the author did not choose and reporting success is the failure this row \
         exists to prevent"
        requested line_count
  | Highlight_not_positive { requested } ->
      Printf.sprintf
        "line %d is highlighted but lines are numbered from 1 — a non-positive marker names no line"
        requested

let diagnostic_level = function
  | Highlight_out_of_range _ | Highlight_not_positive _ -> "L2"

let diagnostic_origin = function
  | Highlight_out_of_range _ | Highlight_not_positive _ -> "Specification"

let check_highlight ~line_count requests =
  let rec go seen = function
    | [] -> []
    | r :: rest when List.mem r seen -> go seen rest
    | r :: rest ->
        let seen = r :: seen in
        if r <= 0 then Highlight_not_positive { requested = r } :: go seen rest
        else if r > line_count then
          Highlight_out_of_range { requested = r; line_count } :: go seen rest
        else go seen rest
  in
  go [] requests

type rendered = { html : string; diagnostics : diagnostic list }

let code_block ?lang ?(highlight = []) body =
  let line_count = List.length body in
  let diagnostics = check_highlight ~line_count highlight in
  let l = language_of_lang lang in
  let b = Buffer.create 256 in
  (* an absent language is an ABSENT attribute, not an empty one *)
  (match label_of_lang lang with
  | Some label -> Buffer.add_string b (Printf.sprintf "<div class=\"wiki-code\" data-lang=\"%s\">\n" (escape label))
  | None -> Buffer.add_string b "<div class=\"wiki-code\">\n");
  Buffer.add_string b (Printf.sprintf "<pre><code class=\"%s\">" (code_class l));
  List.iteri
    (fun idx line ->
      let rendered = highlight_line l line in
      (* NOT CLAMPED, and by construction: the line number is compared to
         the request AS THE AUTHOR WROTE IT. A request outside
         `1 .. line_count` equals no line index, so it draws nothing —
         there is no arithmetic here that could move it onto a
         neighbouring line. (An earlier draft filtered the requests to the
         range first; that filter was provably redundant, and redundant
         defensive code is a place a law can appear to be enforced twice
         while being enforced nowhere.) *)
      let out =
        if List.mem (idx + 1) highlight then "<mark class=\"wiki-hl\">" ^ rendered ^ "</mark>"
        else rendered
      in
      Buffer.add_string b (out ^ "\n"))
    body;
  Buffer.add_string b "</code></pre>\n</div>\n";
  { html = Buffer.contents b; diagnostics }

(* The label is drawn by CSS from `data-lang`, so it never lands in the
   copied text or the search index (R14 mirror: docs_wiki's `.cb[data-lang]`). *)
let code_css =
  "\n.wiki-code { position: relative; margin: 14px 0; }\n\
   .wiki-code pre { background: var(--color-code-bg); border: 1px solid var(--color-border);\n\
  \  border-radius: 8px; padding: 14px 16px; overflow-x: auto; margin: 0; }\n\
   .wiki-code[data-lang]::after { content: attr(data-lang); position: absolute; top: 8px; right: 10px;\n\
  \  font-size: 10px; letter-spacing: 0.04em; color: var(--color-muted); pointer-events: none; }\n\
   mark.wiki-hl { display: inline-block; width: 100%; background: var(--color-mark); }\n\
   .tok-kw { color: var(--color-accent); font-weight: 600; }\n\
   .tok-str { color: var(--color-accent); }\n\
   .tok-com { color: var(--color-muted); font-style: italic; }\n\
   .tok-num { color: var(--color-ink); }\n"

(* ==================== HW.7.8.1 — numbered figures and tables *)

type caption_kind = Figure | Table

let kind_name = function Figure -> "figure" | Table -> "table"

type numbered = { kind : caption_kind; number : int; caption : string; id : string }

(* Derived from POSITION, per kind. Written as an explicit recursion
   rather than a fold over refs, because List.map's evaluation order is
   unspecified and a counter that depends on it is a coin toss. *)
let number_captions items =
  let make kind number caption =
    { kind; number; caption; id = Printf.sprintf "%s-%d" (kind_name kind) number }
  in
  let rec go f t = function
    | [] -> []
    | (Figure, c) :: rest -> make Figure (f + 1) c :: go (f + 1) t rest
    | (Table, c) :: rest -> make Table (t + 1) c :: go f (t + 1) rest
  in
  go 0 0 items

let caption_label kind n =
  Printf.sprintf "%s %d" (match kind with Figure -> "Figure" | Table -> "Table") n

let figure_html ~content nb =
  Printf.sprintf
    "<figure id=\"%s\" class=\"wiki-%s\">\n%s\n<figcaption><span class=\"wiki-caption-label\">%s.</span> %s</figcaption>\n</figure>\n"
    nb.id (kind_name nb.kind) content
    (escape (caption_label nb.kind nb.number))
    (escape nb.caption)

let caption_ref_html nb =
  Printf.sprintf "<a class=\"wiki-caption-ref\" href=\"#%s\">%s</a>" nb.id
    (escape (caption_label nb.kind nb.number))

let figure_css =
  "\nfigure.wiki-figure, figure.wiki-table { margin: 18px 0; padding: 0; }\n\
   figure figcaption { margin-top: 8px; font-size: 13px; color: var(--color-muted); }\n\
   .wiki-caption-label { font-weight: 600; color: var(--color-ink); }\n\
   .wiki-caption-ref { color: var(--color-accent); }\n"

(* ------------------------------------------------------ the whole sheet *)

let stylesheet =
  match theme_css with
  | Error e -> Error e
  | Ok t ->
      (* print LAST, so its rules override the screen rules they follow *)
      Ok (String.concat "" [ t; skip_link_css; back_to_top_css; code_css; figure_css; print_css ])
