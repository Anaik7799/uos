(* ========================================================================= *)
(* render_docs_wiki.ml - Authoritative OCaml GitBook/Notion Docs Generator   *)
(* Transforms project markdown files into rich, semantic, responsive HTML    *)
(* Adheres to docs-design, wiki-design, and OCaml scripting standards       *)
(* ========================================================================= *)

open Printf

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let html_escape s =
  let b = Buffer.create (String.length s + 16) in
  String.iter (function
    | '&' -> Buffer.add_string b "&amp;"
    | '<' -> Buffer.add_string b "&lt;"
    | '>' -> Buffer.add_string b "&gt;"
    | '"' -> Buffer.add_string b "&quot;"
    | '\'' -> Buffer.add_string b "&#39;"
    | c -> Buffer.add_char b c
  ) s;
  Buffer.contents b

let slugify s =
  let b = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | 'a' .. 'z' | '0' .. '9' -> Buffer.add_char b c
    | 'A' .. 'Z' -> Buffer.add_char b (Char.lowercase_ascii c)
    | ' ' | '-' | '_' | '/' | '.' | ':' -> Buffer.add_char b '-'
    | _ -> ()
  ) s;
  let res = Buffer.contents b in
  let re = Str.regexp "-+" in
  let clean = Str.global_replace re "-" res in
  let len = String.length clean in
  if len > 0 && clean.[0] = '-' then String.sub clean 1 (len - 1) else clean

let parse_inline s =
  let s = Str.global_substitute (Str.regexp "`\\([^`]+\\)`") (fun m ->
    let c = Str.matched_group 1 m in
    "<code class=\"inline-code\">" ^ html_escape c ^ "</code>"
  ) s in
  let s = Str.global_substitute (Str.regexp "\\*\\*\\([^*]+\\)\\*\\*") (fun m ->
    let c = Str.matched_group 1 m in
    "<strong>" ^ c ^ "</strong>"
  ) s in
  let s = Str.global_substitute (Str.regexp "\\*\\([^*]+\\)\\*") (fun m ->
    let c = Str.matched_group 1 m in
    "<em>" ^ c ^ "</em>"
  ) s in
  let s = Str.global_substitute (Str.regexp "\\[\\([^]]+\\)\\](\\([^)]+\\))") (fun m ->
    let text = Str.matched_group 1 m in
    let url = Str.matched_group 2 m in
    let mapped_url =
      if Str.string_match (Str.regexp "^file:///home/an/NAS-setup/uos/\\(.*\\)$") url 0 then
        let rel = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/files/" ^ rel
      else if Str.string_match (Str.regexp "^file:///home/an/dev/ver/c3i/\\(.*\\)$") url 0 then
        let rel = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/files/" ^ rel
      else if Str.string_match (Str.regexp "^file:///home/an/\\(.*\\)$") url 0 then
        let rel = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/files/" ^ rel
      else if Str.string_match (Str.regexp "^file://\\(.*\\)$") url 0 then
        let rel = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/files/" ^ rel
      else if Str.string_match (Str.regexp "^http://nas-1\\.tail55d152\\.ts\\.net:4100/docs/journal/\\(.*\\)\\.md$") url 0 then
        let base = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/static/" ^ base ^ ".html"
      else if Str.string_match (Str.regexp "^http://nas-1\\.tail55d152\\.ts\\.net:4100/docs/journal/\\(.*\\)$") url 0 then
        let base = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/static/" ^ base
      else if Str.string_match (Str.regexp "^\\./\\(.*\\)\\.md$") url 0 then
        let base = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/static/" ^ base ^ ".html"
      else if Str.string_match (Str.regexp "^\\./\\(.*\\)$") url 0 then
        let base = Str.matched_group 1 url in
        "http://nas-1.tail55d152.ts.net:4100/static/" ^ base
      else url
    in
    let target = if String.starts_with ~prefix:"http" mapped_url then " target=\"_blank\" rel=\"noopener\"" else "" in
    "<a href=\"" ^ mapped_url ^ "\"" ^ target ^ ">" ^ text ^ "</a>"
  ) s in
  s

type block =
  | Header of int * string * string
  | Paragraph of string
  | Blockquote of string
  | List of bool * string list
  | Table of string list * string list list
  | CodeFence of string * string
  | Divider

let parse_markdown text =
  let lines = String.split_on_char '\n' text in
  let blocks = ref [] in
  let in_code = ref false in
  let code_lang = ref "" in
  let code_acc = ref [] in
  let in_frontmatter = ref false in
  let check_first_line =
    match List.find_opt (fun l -> String.trim l <> "") lines with
    | Some l when String.trim l = "---" -> false
    | _ -> true
  in
  let frontmatter_done = ref check_first_line in
  let table_acc = ref [] in
  let list_acc = ref [] in
  let list_ordered = ref false in

  let flush_list () =
    if !list_acc <> [] then begin
      let items = List.rev !list_acc in
      let ord = !list_ordered in
      list_acc := [];
      blocks := List (ord, items) :: !blocks
    end
  in

  let flush_table () =
    if !table_acc <> [] then begin
      let rows = List.rev !table_acc in
      table_acc := [];
      match rows with
      | hdr :: sep :: rest when String.contains sep '-' ->
          let split_row r =
            let parts = String.split_on_char '|' r in
            let filtered = match parts with
              | "" :: tl -> tl
              | p -> p
            in
            let filtered = match List.rev filtered with
              | "" :: tl -> List.rev tl
              | p -> List.rev p
            in
            List.map String.trim filtered
          in
          let headers = split_row hdr in
          let body_rows = List.map split_row rest in
          blocks := Table (headers, body_rows) :: !blocks
      | _ ->
          List.iter (fun r -> blocks := Paragraph r :: !blocks) rows
    end
  in

  let rec process_lines = function
    | [] ->
        flush_list ();
        flush_table ()
    | line :: rest ->
        let trimmed = String.trim line in
        if not !frontmatter_done && trimmed = "---" then begin
          if not !in_frontmatter then in_frontmatter := true
          else begin
            in_frontmatter := false;
            frontmatter_done := true;
          end;
          process_lines rest
        end else if !in_frontmatter then begin
          process_lines rest
        end else if String.starts_with ~prefix:"```" trimmed then begin
          flush_list ();
          flush_table ();
          if not !in_code then begin
            in_code := true;
            let lang = String.sub trimmed 3 (String.length trimmed - 3) |> String.trim in
            code_lang := lang;
            code_acc := [];
            process_lines rest
          end else begin
            in_code := false;
            let code_str = String.concat "\n" (List.rev !code_acc) in
            blocks := CodeFence (!code_lang, code_str) :: !blocks;
            process_lines rest
          end
        end else if !in_code then begin
          code_acc := line :: !code_acc;
          process_lines rest
        end else if trimmed = "---" || trimmed = "***" then begin
          flush_list ();
          flush_table ();
          blocks := Divider :: !blocks;
          process_lines rest
        end else if String.starts_with ~prefix:"|" trimmed then begin
          flush_list ();
          table_acc := trimmed :: !table_acc;
          process_lines rest
        end else if String.starts_with ~prefix:"> " trimmed || trimmed = ">" then begin
          flush_list ();
          flush_table ();
          let content = if String.length trimmed > 2 then String.sub trimmed 2 (String.length trimmed - 2) else "" in
          blocks := Blockquote content :: !blocks;
          process_lines rest
        end else if String.starts_with ~prefix:"# " trimmed then begin
          flush_list ();
          flush_table ();
          let title = String.sub trimmed 2 (String.length trimmed - 2) |> String.trim in
          blocks := Header (1, slugify title, title) :: !blocks;
          process_lines rest
        end else if String.starts_with ~prefix:"## " trimmed then begin
          flush_list ();
          flush_table ();
          let title = String.sub trimmed 3 (String.length trimmed - 3) |> String.trim in
          blocks := Header (2, slugify title, title) :: !blocks;
          process_lines rest
        end else if String.starts_with ~prefix:"### " trimmed then begin
          flush_list ();
          flush_table ();
          let title = String.sub trimmed 4 (String.length trimmed - 4) |> String.trim in
          blocks := Header (3, slugify title, title) :: !blocks;
          process_lines rest
        end else if String.starts_with ~prefix:"#### " trimmed then begin
          flush_list ();
          flush_table ();
          let title = String.sub trimmed 5 (String.length trimmed - 5) |> String.trim in
          blocks := Header (4, slugify title, title) :: !blocks;
          process_lines rest
        end else if String.starts_with ~prefix:"- " trimmed || String.starts_with ~prefix:"* " trimmed then begin
          flush_table ();
          let item = String.sub trimmed 2 (String.length trimmed - 2) |> String.trim in
          list_ordered := false;
          list_acc := item :: !list_acc;
          process_lines rest
        end else if Str.string_match (Str.regexp "^[0-9]+\\.\\s-+") trimmed 0 || Str.string_match (Str.regexp "^[0-9]+\\.\\s+") trimmed 0 then begin
          flush_table ();
          let pos = String.index trimmed '.' in
          let item = String.sub trimmed (pos + 1) (String.length trimmed - pos - 1) |> String.trim in
          list_ordered := true;
          list_acc := item :: !list_acc;
          process_lines rest
        end else if trimmed = "" then begin
          flush_list ();
          flush_table ();
          process_lines rest
        end else begin
          flush_list ();
          flush_table ();
          blocks := Paragraph trimmed :: !blocks;
          process_lines rest
        end
  in
  process_lines lines;
  List.rev !blocks

let render_html_page ~title ~current_slug blocks =
  let buf = Buffer.create 16384 in
  bprintf buf "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n";
  bprintf buf "<meta charset=\"UTF-8\">\n";
  bprintf buf "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n";
  bprintf buf "<title>%s | 2S Consulting & Numantra</title>\n" (html_escape title);
  bprintf buf "<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">\n";
  bprintf buf "<link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>\n";
  bprintf buf "<link href=\"https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap\" rel=\"stylesheet\">\n";
  Buffer.add_string buf "<style>\n";
  Buffer.add_string buf {|
    :root {
      --bg-primary: #0F172A;
      --bg-surface: #1E293B;
      --bg-surface-elevated: #334155;
      --surface-border: #334155;
      --text-main: #F8FAFC;
      --text-muted: #94A3B8;
      --accent-cyan: #38BDF8;
      --accent-emerald: #34D399;
      --accent-amber: #FBBF24;
      --accent-rose: #FB7185;
      --code-bg: #0B1120;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 0;
      background-color: var(--bg-primary);
      color: var(--text-main);
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      font-size: 15px;
      line-height: 1.65;
    }
    /* Top Bar */
    .top-nav {
      position: sticky;
      top: 0;
      z-index: 50;
      background: rgba(15, 23, 42, 0.92);
      backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--surface-border);
      padding: 0.75rem 1.5rem;
      display: flex;
      align-items: center;
      gap: 1.25rem;
      overflow-x: auto;
    }
    .top-nav .nav-brand {
      font-weight: 700;
      font-size: 1rem;
      color: var(--accent-cyan);
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-right: 0.5rem;
      white-space: nowrap;
    }
    .top-nav a {
      color: var(--text-muted);
      text-decoration: none;
      font-size: 0.85rem;
      font-weight: 500;
      padding: 0.35rem 0.65rem;
      border-radius: 6px;
      white-space: nowrap;
      transition: all 0.15s ease;
    }
    .top-nav a:hover, .top-nav a.active {
      color: var(--text-main);
      background: var(--bg-surface);
    }
    .top-nav a.active {
      color: var(--accent-cyan);
      border: 1px solid rgba(56, 189, 248, 0.3);
    }
    /* Layout */
    .layout-container {
      display: flex;
      min-height: calc(100vh - 55px);
    }
    /* Sidebar TOC */
    .sidebar {
      width: 280px;
      flex-shrink: 0;
      background: #0B1120;
      border-right: 1px solid var(--surface-border);
      padding: 1.5rem 1rem;
      overflow-y: auto;
      position: sticky;
      top: 55px;
      height: calc(100vh - 55px);
    }
    .sidebar-title {
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--text-muted);
      margin-bottom: 0.85rem;
      font-weight: 600;
      padding-left: 0.5rem;
    }
    .sidebar-nav {
      list-style: none;
      padding: 0;
      margin: 0;
    }
    .sidebar-nav li { margin-bottom: 0.25rem; }
    .sidebar-nav a {
      display: block;
      color: var(--text-muted);
      text-decoration: none;
      font-size: 0.82rem;
      padding: 0.35rem 0.5rem;
      border-radius: 4px;
      line-height: 1.35;
      transition: all 0.15s;
    }
    .sidebar-nav a:hover {
      color: var(--text-main);
      background: rgba(255, 255, 255, 0.04);
    }
    .sidebar-nav a.level-1 { font-weight: 600; color: #E2E8F0; }
    .sidebar-nav a.level-2 { padding-left: 0.85rem; font-weight: 500; }
    .sidebar-nav a.level-3 { padding-left: 1.4rem; font-size: 0.78rem; opacity: 0.85; }
    .sidebar-nav a.level-4 { padding-left: 2rem; font-size: 0.75rem; opacity: 0.75; }

    /* Main Content */
    .main-content {
      flex: 1;
      padding: 2.5rem 3.5rem;
      max-width: 1050px;
      overflow-x: hidden;
    }
    h1, h2, h3, h4 {
      color: var(--text-main);
      font-weight: 600;
      line-height: 1.3;
      margin-top: 2rem;
      margin-bottom: 0.75rem;
    }
    h1 {
      font-size: 2rem;
      font-weight: 700;
      border-bottom: 1px solid var(--surface-border);
      padding-bottom: 0.75rem;
      margin-top: 0.5rem;
      color: #38BDF8;
    }
    h2 {
      font-size: 1.4rem;
      border-bottom: 1px solid rgba(51, 65, 85, 0.5);
      padding-bottom: 0.5rem;
      margin-top: 2.5rem;
    }
    h3 { font-size: 1.15rem; color: #E2E8F0; }
    h4 { font-size: 1rem; color: #CBD5E1; }
    p { margin-top: 0; margin-bottom: 1.15rem; color: #CBD5E1; }
    a { color: var(--accent-cyan); text-decoration: none; }
    a:hover { text-decoration: underline; }

    /* Tables */
    .table-container {
      overflow-x: auto;
      margin: 1.5rem 0;
      border-radius: 8px;
      border: 1px solid var(--surface-border);
      background: var(--bg-surface);
    }
    table {
      width: 100%;
      border-collapse: collapse;
      text-align: left;
      font-size: 0.88rem;
    }
    th {
      background: #0B1120;
      color: #F1F5F9;
      font-weight: 600;
      padding: 0.75rem 1rem;
      border-bottom: 2px solid var(--surface-border);
      white-space: nowrap;
    }
    td {
      padding: 0.75rem 1rem;
      border-bottom: 1px solid rgba(51, 65, 85, 0.7);
      color: #E2E8F0;
    }
    tr:last-child td { border-bottom: none; }
    tr:nth-child(even) td { background: rgba(255, 255, 255, 0.015); }
    tr:hover td { background: rgba(56, 189, 248, 0.04); }

    /* Callout */
    .callout {
      border-left: 4px solid var(--accent-cyan);
      background: rgba(56, 189, 248, 0.08);
      padding: 1rem 1.25rem;
      margin: 1.25rem 0;
      border-radius: 0 6px 6px 0;
    }
    .callout p { margin: 0; color: #E0F2FE; }

    /* Code */
    .inline-code {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85em;
      background: var(--code-bg);
      border: 1px solid var(--surface-border);
      padding: 0.15rem 0.4rem;
      border-radius: 4px;
      color: #38BDF8;
    }
    .code-block {
      background: var(--code-bg);
      border: 1px solid var(--surface-border);
      border-radius: 8px;
      padding: 1.25rem;
      overflow-x: auto;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
      line-height: 1.5;
      color: #E2E8F0;
      margin: 1.25rem 0;
    }

    /* Lists */
    ul, ol {
      margin-top: 0;
      margin-bottom: 1.25rem;
      padding-left: 1.75rem;
      color: #CBD5E1;
    }
    li { margin-bottom: 0.35rem; }

    /* Footer & Paging */
    .doc-footer {
      margin-top: 3.5rem;
      padding-top: 1.5rem;
      border-top: 1px solid var(--surface-border);
      display: flex;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 1rem;
      font-size: 0.82rem;
      color: var(--text-muted);
    }
    @media (max-width: 960px) {
      .layout-container { flex-direction: column; }
      .sidebar { width: 100%; height: auto; position: static; border-right: none; border-bottom: 1px solid var(--surface-border); }
      .main-content { padding: 1.5rem; }
    }
  |};
  bprintf buf "</style>\n</head>\n<body>\n";

  (* Top Navigation *)
  bprintf buf "<nav class=\"top-nav\">\n";
  bprintf buf "  <span class=\"nav-brand\">⚡ 2S Consulting & Numantra</span>\n";
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/PROJECTS_INDEX.html\" class=\"%s\">🏠 Projects Index</a>\n"
    (if current_slug = "index" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/2S_CONSULTING_NORDIC_OUTREACH_STRATEGY.html\" class=\"%s\">🚀 Outreach Playbook</a>\n"
    (if current_slug = "outreach" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/NORDIC_MEDTECH_COMPETITIVE_LANDSCAPE_AND_PEER_DOSSIER.html\" class=\"%s\">🏆 Competitors</a>\n"
    (if current_slug = "competitors" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/2S_CONSULTING_COMPREHENSIVE_DOSSIER.html\" class=\"%s\">📄 Enterprise Dossier</a>\n"
    (if current_slug = "dossier" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/20260927-1133-2s-consulting-nordic-medtech-service-positioning-journal.html\" class=\"%s\">📖 13-Sec Journal</a>\n"
    (if current_slug = "journal" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/20260927-1133-2s-consulting-nordic-medtech-service-positioning-analysis.html\">📊 Web Report</a>\n";
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/20260927-1133-2s-consulting-nordic-medtech-service-positioning-deck.html\">🎯 Slide Deck</a>\n";
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/pdf_download_converted.html\" class=\"%s\">💡 Strategy Vision</a>\n"
    (if current_slug = "presentation" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/20260927-1145-uos-c3i-codex-astra-sovereign-review-and-ratification-certificate.html\" class=\"%s\">📜 Codex Astra Cert</a>\n"
    (if current_slug = "certificate" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/MEDICAL_NORDICS_FINANCIALS_DOSSIER.html\" class=\"%s\">📗 Nordic Directory</a>\n"
    (if current_slug = "directory" then "active" else "");
  bprintf buf "  <a href=\"http://nas-1.tail55d152.ts.net:4100/static/Medical-Nordics-1.xlsx\">📥 Download XLSX</a>\n";
  bprintf buf "</nav>\n\n";

  (* Extract TOC Items from Headers *)
  let toc_items = List.filter_map (function
    | Header (lvl, id, htitle) when lvl <= 3 -> Some (lvl, id, htitle)
    | _ -> None
  ) blocks in

  (* Layout Container *)
  bprintf buf "<div class=\"layout-container\">\n";

  (* Sidebar TOC *)
  bprintf buf "  <aside class=\"sidebar\">\n";
  bprintf buf "    <div class=\"sidebar-title\">On This Page</div>\n";
  bprintf buf "    <ul class=\"sidebar-nav\">\n";
  List.iter (fun (lvl, id, htitle) ->
    let cls = match lvl with
      | 1 -> "level-1"
      | 2 -> "level-2"
      | 3 -> "level-3"
      | _ -> "level-4"
    in
    bprintf buf "      <li><a href=\"#%s\" class=\"%s\">%s</a></li>\n" id cls (html_escape htitle)
  ) toc_items;
  bprintf buf "    </ul>\n";
  bprintf buf "  </aside>\n\n";

  (* Main Content *)
  bprintf buf "  <main class=\"main-content\">\n";
  List.iter (function
    | Header (lvl, id, htitle) ->
        bprintf buf "    <h%d id=\"%s\">%s</h%d>\n" lvl id (parse_inline htitle) lvl
    | Paragraph p ->
        bprintf buf "    <p>%s</p>\n" (parse_inline p)
    | Blockquote bq ->
        bprintf buf "    <div class=\"callout\"><p>%s</p></div>\n" (parse_inline bq)
    | List (is_ord, items) ->
        let tag = if is_ord then "ol" else "ul" in
        bprintf buf "    <%s>\n" tag;
        List.iter (fun itm -> bprintf buf "      <li>%s</li>\n" (parse_inline itm)) items;
        bprintf buf "    </%s>\n" tag
    | Table (headers, rows) ->
        bprintf buf "    <div class=\"table-container\">\n      <table>\n        <thead>\n          <tr>\n";
        List.iter (fun h -> bprintf buf "            <th>%s</th>\n" (parse_inline h)) headers;
        bprintf buf "          </tr>\n        </thead>\n        <tbody>\n";
        List.iter (fun r ->
          bprintf buf "          <tr>\n";
          List.iter (fun c -> bprintf buf "            <td>%s</td>\n" (parse_inline c)) r;
          bprintf buf "          </tr>\n"
        ) rows;
        bprintf buf "        </tbody>\n      </table>\n    </div>\n"
    | CodeFence (lang, code) ->
        bprintf buf "    <pre class=\"code-block\"><code class=\"language-%s\">%s</code></pre>\n" lang (html_escape code)
    | Divider ->
        bprintf buf "    <hr>\n"
  ) blocks;

  (* Footer *)
  bprintf buf "    <footer class=\"doc-footer\">\n";
  bprintf buf "      <div>Governed by <strong>L0-codex-gpt-6-astra</strong> • Mesh Node: <code>nas-1.tail55d152.ts.net</code></div>\n";
  bprintf buf "      <div>UOS & C3I Sovereign Biomorphic Operations • Timestamp: 2026-09-27</div>\n";
  bprintf buf "    </footer>\n";
  bprintf buf "  </main>\n";
  bprintf buf "</div>\n";

  bprintf buf "</body>\n</html>\n";
  Buffer.contents buf

let () =
  let proj_dir = "/home/an/dev/ver/c3i/sub-projects/work/gdrive/4-Temp/1-Bountytek/projects" in
  let out_dir = "/tmp/generated_html" in
  (try Unix.mkdir out_dir 0o755 with _ -> ());
  
  let files_to_render = [
    ("2S_CONSULTING_NORDIC_OUTREACH_STRATEGY.md", "2S_CONSULTING_NORDIC_OUTREACH_STRATEGY.html", "2S Consulting Nordic Market Outreach Strategy", "outreach");
    ("NORDIC_MEDTECH_COMPETITIVE_LANDSCAPE_AND_PEER_DOSSIER.md", "NORDIC_MEDTECH_COMPETITIVE_LANDSCAPE_AND_PEER_DOSSIER.html", "Nordic MedTech Competitive Landscape & Peer Analysis", "competitors");
    ("2S_CONSULTING_COMPREHENSIVE_DOSSIER.md", "2S_CONSULTING_COMPREHENSIVE_DOSSIER.html", "2S Consulting & Numantra Enterprise Dossier", "dossier");
    ("20260927-1133-2s-consulting-nordic-medtech-service-positioning-journal.md", "20260927-1133-2s-consulting-nordic-medtech-service-positioning-journal.html", "Comprehensive 13-Section Journal", "journal");
    ("MEDICAL_NORDICS_FINANCIALS_DOSSIER.md", "MEDICAL_NORDICS_FINANCIALS_DOSSIER.html", "Nordic Life Sciences Financial Directory", "directory");
    ("20260927-1145-uos-c3i-codex-astra-sovereign-review-and-ratification-certificate.md", "20260927-1145-uos-c3i-codex-astra-sovereign-review-and-ratification-certificate.html", "Codex Astra Sovereign Review & Ratification Certificate", "certificate");
    ("20260927-131534-2s-consulting-nordic-medtech-service-positioning-and-target-rationalization.md", "20260927-131534-2s-consulting-nordic-medtech-service-positioning-and-target-rationalization.html", "Zettelkasten Knowledge Slip-Box Note", "zk_note");
    ("pdf_download_converted.md", "pdf_download_converted.html", "2S Consulting 2026 Executive Strategic Vision", "presentation");
    ("PROJECTS_INDEX.md", "PROJECTS_INDEX.html", "Projects Directory Master Index", "index")
  ] in

  printf "========================================================================\n";
  printf "OCaml Wiki/Docs Generator: Rendering Markdown to Semantic GitBook HTML\n";
  printf "========================================================================\n";

  List.iter (fun (md_name, html_name, title, slug) ->
    let p_local = Filename.concat proj_dir md_name in
    let p_tmp = Filename.concat "/tmp" md_name in
    let md_path = if Sys.file_exists p_tmp then p_tmp else p_local in
    let html_path = Filename.concat out_dir html_name in
    if Sys.file_exists md_path then begin
      let content = read_file md_path in
      let blocks = parse_markdown content in
      let html = render_html_page ~title ~current_slug:slug blocks in
      write_file html_path html;
      printf "✓ Generated %-65s (%d bytes, %d blocks)\n" html_name (String.length html) (List.length blocks)
    end else begin
      printf "✗ File not found: %s\n" md_path
    end
  ) files_to_render;

  printf "========================================================================\n";
  printf "OCaml generation complete in %s\n" out_dir
