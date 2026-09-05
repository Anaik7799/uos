(* ZK Markdown -> HTML compiler — a REAL Model->View compiler over the live ZK corpus.

   Promoted from a phase-7 printf stub. It parses a documented subset of the ZK
   markdown grammar and emits SAFE (HTML-escaped) Notion-like HTML, computed over
   the real bytes under docs/zk/**/*.md.

   GRAMMAR SUBSET (line-oriented, honest scope):
     - ATX headings         `# .. ######`  -> <h1..h6>
     - unordered list items `- ` / `* `     -> <ul><li>
     - fenced code blocks   ``` ... ```      -> <pre><code> (raw, escaped)
     - inline bold          **x**            -> <strong>
     - inline code          `x`              -> <code>
     - wikilinks            [[t|label]]      -> <a href="t">label</a>
     - tags                 #tag             -> <span class="tag">
     - everything else                       -> <p> paragraphs
   SAFETY: every literal text run is HTML-escaped (ampersand/angle-brackets/
   quotes) BEFORE structural tags are added, so no corpus byte can inject markup.

   [LIMITATION] This is a pragmatic subset, not a CommonMark-complete compiler
   (no tables, nested lists, blockquotes, or reference links). It is a real
   compiler over real bytes, not a renderer stub. *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let zk_files root =
  let dir = Filename.concat root "docs/zk" in
  let rec walk d acc =
    let entries = try Sys.readdir d with _ -> [||] in
    Array.fold_left (fun acc name ->
      let p = Filename.concat d name in
      if (try Sys.is_directory p with _ -> false) then walk p acc
      else if Filename.check_suffix name ".md" then p :: acc
      else acc) acc entries
  in List.sort compare (walk dir [])

let html_escape s =
  let b = Buffer.create (String.length s + 16) in
  String.iter (fun c -> match c with
    | '&' -> Buffer.add_string b "&amp;"
    | '<' -> Buffer.add_string b "&lt;"
    | '>' -> Buffer.add_string b "&gt;"
    | '"' -> Buffer.add_string b "&quot;"
    | '\'' -> Buffer.add_string b "&#39;"
    | c -> Buffer.add_char b c) s;
  Buffer.contents b

let find_from s sub i =
  let ls = String.length s and lsub = String.length sub in
  let rec go i =
    if i + lsub > ls then None
    else if String.sub s i lsub = sub then Some i
    else go (i + 1)
  in if lsub = 0 then None else go i

let reveal_pairs s delim otag ctag =
  let out = Buffer.create (String.length s) in
  let ls = String.length s and ld = String.length delim in
  let rec loop i opening =
    match find_from s delim i with
    | None -> Buffer.add_string out (String.sub s i (ls - i)); Buffer.contents out
    | Some p ->
      Buffer.add_string out (String.sub s i (p - i));
      Buffer.add_string out (if opening then otag else ctag);
      loop (p + ld) (not opening)
  in loop 0 true

let reveal_tags s =
  let out = Buffer.create (String.length s) in
  let ls = String.length s in
  let is_tagchar c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '-' || c = '_' in
  let rec loop i =
    if i >= ls then Buffer.contents out
    else if s.[i] = '#'
            && (i = 0 || s.[i-1] = ' ' || s.[i-1] = '(' || s.[i-1] = '\t')
            && i + 1 < ls && is_tagchar s.[i+1] then begin
      let j = ref (i + 1) in
      while !j < ls && is_tagchar s.[!j] do incr j done;
      let tag = String.sub s i (!j - i) in
      Buffer.add_string out (Printf.sprintf "<span class=\"tag\">%s</span>" tag);
      loop !j
    end else begin Buffer.add_char out s.[i]; loop (i + 1) end
  in loop 0

let inline_no_link seg =
  let e = html_escape seg in
  let e = reveal_pairs e "**" "<strong>" "</strong>" in
  let e = reveal_pairs e "`" "<code>" "</code>" in
  reveal_tags e

(* Inline transform on a plain line: wikilinks handled on the raw line so the
   target/label split survives escaping; the rest goes through inline_no_link. *)
let inline_html line =
  let b = Buffer.create (String.length line + 16) in
  let n = String.length line in
  let rec go i =
    if i >= n then ()
    else
      match find_from line "[[" i with
      | Some a when (match find_from line "]]" (a + 2) with Some _ -> true | None -> false) ->
        let bend = (match find_from line "]]" (a + 2) with Some x -> x | None -> a) in
        Buffer.add_string b (inline_no_link (String.sub line i (a - i)));
        let inner = String.sub line (a + 2) (bend - (a + 2)) in
        let target, label =
          match String.index_opt inner '|' with
          | Some p -> String.sub inner 0 p, String.sub inner (p + 1) (String.length inner - p - 1)
          | None -> inner, inner in
        Buffer.add_string b (Printf.sprintf "<a href=\"%s\">%s</a>"
          (html_escape (String.trim target)) (html_escape (String.trim label)));
        go (bend + 2)
      | _ ->
        Buffer.add_string b (inline_no_link (String.sub line i (n - i)))
  in
  go 0; Buffer.contents b

let compile_html markdown =
  let lines = String.split_on_char '\n' markdown in
  let b = Buffer.create (String.length markdown * 2) in
  let in_code = ref false and in_list = ref false in
  let close_list () = if !in_list then (Buffer.add_string b "</ul>\n"; in_list := false) in
  List.iter (fun line ->
    let trimmed = String.trim line in
    if String.length trimmed >= 3 && String.sub trimmed 0 3 = "```" then begin
      close_list ();
      if !in_code then (Buffer.add_string b "</code></pre>\n"; in_code := false)
      else (Buffer.add_string b "<pre><code>"; in_code := true)
    end
    else if !in_code then (Buffer.add_string b (html_escape line); Buffer.add_char b '\n')
    else if String.length trimmed >= 2
            && trimmed.[0] = '#'
            && (let k = ref 0 in
                while !k < String.length trimmed && trimmed.[!k] = '#' do incr k done;
                !k <= 6 && !k < String.length trimmed && trimmed.[!k] = ' ') then begin
      close_list ();
      let k = ref 0 in while trimmed.[!k] = '#' do incr k done;
      let level = !k in
      let text = String.trim (String.sub trimmed level (String.length trimmed - level)) in
      Buffer.add_string b (Printf.sprintf "<h%d>%s</h%d>\n" level (inline_html text) level)
    end
    else if String.length trimmed >= 2
            && (trimmed.[0] = '-' || trimmed.[0] = '*') && trimmed.[1] = ' ' then begin
      if not !in_list then (Buffer.add_string b "<ul>\n"; in_list := true);
      let item = String.sub trimmed 2 (String.length trimmed - 2) in
      Buffer.add_string b (Printf.sprintf "<li>%s</li>\n" (inline_html item))
    end
    else if trimmed = "" then close_list ()
    else begin
      close_list ();
      Buffer.add_string b (Printf.sprintf "<p>%s</p>\n" (inline_html trimmed))
    end
  ) lines;
  close_list ();
  if !in_code then Buffer.add_string b "</code></pre>\n";
  Buffer.contents b

let run (root : string) : unit =
  let files = zk_files root in
  Printf.printf "[zk_markdown_to_html_compiler] safe Markdown->HTML over %d ZK notes\n"
    (List.length files);
  let total_in = ref 0 and total_out = ref 0 and n = ref 0 in
  let sample = ref "" in
  List.iter (fun path ->
    let md = try read_file path with _ -> "" in
    if md <> "" then begin
      let html = compile_html md in
      total_in := !total_in + String.length md;
      total_out := !total_out + String.length html;
      incr n;
      if !sample = "" then
        sample := Printf.sprintf "  first note %s: %d md bytes -> %d html bytes\n"
          (Filename.basename path) (String.length md) (String.length html)
    end
  ) files;
  print_string !sample;
  let raw_angles = List.fold_left (fun acc path ->
    let md = try read_file path with _ -> "" in
    String.fold_left (fun a c -> if c = '<' || c = '>' then a + 1 else a) acc md)
    0 files in
  Printf.printf "  compiled %d notes: %d bytes in -> %d bytes safe HTML out\n"
    !n !total_in !total_out;
  Printf.printf "  safety: %d source angle-bracket bytes HTML-escaped (no markup injection)\n"
    raw_angles;
  Printf.printf "  [LIMITATION] subset grammar (headings/lists/code/bold/wikilinks/tags), not full CommonMark\n"
