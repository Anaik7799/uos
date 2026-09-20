#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,str";;
(* @agent_intent: local static docs, no script/runtime/network/publication side effects.
   @laws: escape all source text; disallow executable links; errors abort. *)
open Printf
let get = function Ok x -> x | Error (`Msg m) -> failwith m
let read_file p =
 let rec attempt n =
 let a=Unix.stat p in let s=get(Bos.OS.File.read(Fpath.v p)) in let second=get(Bos.OS.File.read(Fpath.v p)) in let b=Unix.stat p in
 if a.Unix.st_size=b.Unix.st_size && a.Unix.st_mtime=b.Unix.st_mtime && String.length s=b.Unix.st_size && s=second then s
 else if n=0 then failwith("unstable or short filesystem read: " ^ p)
 else (Unix.sleepf 0.1;attempt(n-1)) in attempt 2
let write_file p s =
 if Sys.file_exists p && read_file p=s then () else begin
 get (Bos.OS.File.write (Fpath.v p) s); if read_file p<>s then failwith("write/read mismatch: " ^ p)
 end
let html_escape s =
 let b=Buffer.create (String.length s) in
 String.iter (function '&'->Buffer.add_string b "&amp;" | '<'->Buffer.add_string b "&lt;" | '>'->Buffer.add_string b "&gt;" | '"'->Buffer.add_string b "&quot;" | '\''->Buffer.add_string b "&#39;" | c->Buffer.add_char b c) s; Buffer.contents b
let slugify s =
 let b=Buffer.create 50 in String.iter (function 'a'..'z' | '0'..'9' as c->Buffer.add_char b c | 'A'..'Z' as c->Buffer.add_char b (Char.lowercase_ascii c) | _->Buffer.add_char b '-') s;
 Str.global_replace (Str.regexp "-+") "-" (Buffer.contents b)
let safe_url s =
 s<>"" && not (String.exists (fun c -> Char.code c <=32 || c='\\' || c='"' || c='\'' || c='<' || c='>') s)
 && (String.starts_with ~prefix:"https://" s || String.starts_with ~prefix:"http://" s || (not(String.contains s ':') && not(String.starts_with ~prefix:"//" s)))
let parse_inline s =
 let re=Str.regexp "`[^`]+`\\|\\*\\*[^*]+\\*\\*\\|\\[[^]]+\\](\\([^()]\\|([^()]*)\\)*)" in
 let b=Buffer.create (String.length s) in
 let rec loop pos =
  match (try Some (Str.search_forward re s pos) with Not_found -> None) with
  | None -> Buffer.add_string b (html_escape (String.sub s pos (String.length s-pos)))
  | Some i -> let j=Str.match_end() in let token=String.sub s i (j-i) in
    Buffer.add_string b (html_escape (String.sub s pos (i-pos)));
    let rendered = if token.[0]='`' then "<code>" ^ html_escape(String.sub token 1 (String.length token-2)) ^ "</code>"
      else if token.[0]='*' then "<strong>" ^ html_escape(String.sub token 2 (String.length token-4)) ^ "</strong>"
      else let k=String.index token ']' in let label=String.sub token 1 (k-1) in let url=String.sub token (k+2) (String.length token-k-3) in
       let old_prefix="http://nas-1.tail55d152.ts.net:4100/docs/journal/" in
       let url=if String.starts_with ~prefix:old_prefix url then String.sub url (String.length old_prefix) (String.length url-String.length old_prefix) else url in
       let url=if List.mem url ["./verify_pharma_chemicals.mojo";"verify_pharma_chemicals.mojo"] then "verify_assessment_system.ml" else url in
       if safe_url url then "<a href=\"" ^ html_escape url ^ "\">" ^ html_escape label ^ "</a>" else html_escape token in
    Buffer.add_string b rendered; loop j in
 loop 0; Buffer.contents b
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
        flush_table ();
        if !in_code then blocks := CodeFence (!code_lang, String.concat "\n" (List.rev !code_acc)) :: !blocks
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


let normalize blocks =
 let seen=Hashtbl.create 50 in
 List.map (function Header(l,id,t) -> let n=1+Option.value ~default:0 (Hashtbl.find_opt seen id) in Hashtbl.replace seen id n; Header(l,(if n=1 then id else id ^ "-" ^ string_of_int n),t) | b->b) blocks
let html_name p = let s=Filename.remove_extension p in s ^ (if List.mem s ["2S_NORDIC_OUTREACH_PRESENTATION";"NORDIC_COMPETITOR_BENCHMARK_DECK"] then "_DOC.html" else ".html")
let current_docs=["CODEX_HANDOVER.md";"PROJECTS_INDEX.md";"SKILLS_AND_SUPERPOWERS_CATALOG.md";"ACH_ASSESSMENT.md";"ACH_SAFETY_ANALYSIS.md";"ACH_ASSESSMENT_VALIDATION.md";"20260928-0934-ASSESSMENT_SYSTEM_GOVERNANCE.md";"20260928-0934-ASSESSMENT_ARTIFACT_REVIEW.md"]
let render_block = function
 | Header(l,id,t)->sprintf "<h%d id=\"%s\">%s</h%d>" l (html_escape id) (parse_inline t) l
 | Paragraph p -> "<p>" ^ parse_inline p ^ "</p>"
 | Blockquote p -> "<blockquote>" ^ parse_inline p ^ "</blockquote>"
 | List(ord,items)->let tag=if ord then "ol" else "ul" in "<" ^ tag ^ ">" ^ String.concat "" (List.map (fun s->"<li>" ^ parse_inline s ^ "</li>") items) ^ "</" ^ tag ^ ">"
 | Table(h,rows) ->
   if not(List.for_all (fun row->List.length row=List.length h) rows) then
    "<pre>" ^ html_escape(String.concat "\n" (List.map (String.concat " | ") (h::rows))) ^ "</pre>"
   else "<div class=\"table-scroll\"><table><thead><tr>" ^ String.concat "" (List.map(fun s->"<th scope=\"col\">" ^ parse_inline s ^ "</th>") h) ^ "</tr></thead><tbody>" ^ String.concat "" (List.map(fun row->"<tr>" ^ String.concat "" (List.map(fun s->"<td>" ^ parse_inline s ^ "</td>") row) ^ "</tr>") rows) ^ "</tbody></table></div>"
 | CodeFence(_,code)->"<pre><code>" ^ html_escape code ^ "</code></pre>"
 | Divider -> "<hr>"
let render_page pages file text =
 let blocks=normalize(parse_markdown text) in
 let title=match List.find_opt(function Header _->true | _->false) blocks with Some(Header(_,_,t))->t | _->Filename.remove_extension file in
 let link p = "<a href=\"" ^ html_escape(html_name p) ^ "\"" ^ (if p=file then " aria-current=\"page\"" else "") ^ ">" ^ html_escape(Filename.remove_extension p) ^ "</a>" in
 let group name xs = "<h2>" ^ name ^ "</h2><ul>" ^ String.concat "" (List.map(fun p->"<li>" ^ link p ^ "</li>") xs) ^ "</ul>" in
 let index=let rec go n=function []->0 | x::_ when x=file->n | _::xs->go(n+1)xs in go 0 pages in
 let nav label n=if n<0 || n>=List.length pages then "<span>" ^ label ^ ": end</span>" else "<span>" ^ label ^ ": " ^ link(List.nth pages n) ^ "</span>" in
 "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"generator\" content=\"Bountytek OCaml static docs v3\"><title>" ^ html_escape title ^ " | Bountytek</title><style>"
 ^ "*{box-sizing:border-box}body{margin:0;background:#f8fafc;color:#172338;font:16px/1.65 system-ui,sans-serif}a{color:#125a98}header{padding:12px 24px;background:#18283c;color:white}header a{color:#a7dcff}.layout{display:grid;grid-template-columns:250px minmax(0,1fr) 210px;gap:28px;max-width:1600px;margin:auto;padding:24px}nav,aside{font-size:13px;overflow-wrap:anywhere}nav ul,aside ul{padding-left:18px}nav h2{font-size:16px}main{min-width:0;max-width:80ch}h1{font-size:2rem;line-height:1.25}h2{margin-top:2em}h3{margin-top:1.6em}[aria-current=page]{font-weight:bold;color:#172338}blockquote,.status{border-left:4px solid #b85b00;background:#fff3df;margin:16px 0;padding:14px}pre{background:#eaf0f5;padding:14px;overflow:auto}code{font-family:ui-monospace,monospace;font-size:.9em}table{border-collapse:collapse;font-size:14px;width:100%}th,td{border:1px solid #ced7df;padding:8px;text-align:left;vertical-align:top}.table-scroll{overflow:auto}footer{display:flex;gap:24px;justify-content:space-between;margin-top:40px;border-top:1px solid #ccc;padding-top:20px;overflow-wrap:anywhere}.source{font-size:13px}@media(max-width:1000px){.layout{grid-template-columns:210px minmax(0,1fr)}aside{grid-column:2;grid-row:1}main{grid-column:2}nav{grid-row:1/3}}@media(max-width:650px){.layout{display:block;padding:16px}nav,aside{margin-bottom:24px}h1{font-size:1.6rem}}@media print{nav,aside,footer{display:none}.layout{display:block}main{max-width:none}}"
 ^ "</style></head><body><header><a href=\"PROJECTS_INDEX.html\">Bountytek research library</a> · Advisory prototype</header><div class=\"layout\"><nav aria-label=\"Documentation\">"
 ^ group "Assessment and governance" (List.filter(fun p->List.mem p current_docs) pages)
 ^ group "Research and historical records" (List.filter(fun p->not(List.mem p current_docs)) pages)
 ^ "</nav><main><p class=\"source\"><a href=\"PROJECTS_INDEX.html\">Index</a> / " ^ html_escape title ^ "</p><div class=\"status\"><strong>Deployment hold.</strong> No safety certification or operational approval. "
 ^ (if List.mem file current_docs then "Read the validation scope and open obligations." else "Historical/unvalidated source material: earlier verification and ratification claims are superseded.")
 ^ " <a href=\"ACH_ASSESSMENT_VALIDATION.html\">Current validation record</a>.</div><p class=\"source\">Generated from <a href=\"" ^ html_escape file ^ "\">Markdown source</a> · 2026-09-28</p><article>"
 ^ String.concat "\n" (List.map render_block blocks)
 ^ "</article><footer>" ^ nav "Previous" (index-1) ^ nav "Next" (index+1) ^ "</footer></main><aside aria-label=\"On this page\"><h2>On this page</h2><ul>"
 ^ String.concat "" (List.filter_map(function Header(l,id,t) when l<=3->Some("<li><a href=\"#" ^ html_escape id ^ "\">" ^ html_escape t ^ "</a></li>") | _->None) blocks)
 ^ "</ul></aside></div></body></html>\n"
let contains s part = try ignore(Str.search_forward(Str.regexp_string part)s 0);true with Not_found->false
let self_test () =
 let check b m=if not b then failwith("renderer test: " ^ m) in
 check (parse_inline "<script>&\""="&lt;script&gt;&amp;&quot;") "escape prose";
 check (not(contains(parse_inline "[x](javascript:alert)") "href=")) "reject javascript";
 check (not(contains(parse_inline "[x](//evil)") "href=")) "reject protocol relative";
 check (not(contains(parse_inline "[x](https://e/\"x)") "href=")) "reject attribute injection";
 check (contains(parse_inline "[x](ACH_ASSESSMENT.html)") "href=\"ACH_ASSESSMENT.html\"") "relative link";
 check (contains(parse_inline "`<x>`") "<code>&lt;x&gt;</code>") "escape code";
 check (contains(parse_inline "**<x>**") "<strong>&lt;x&gt;</strong>") "escape bold";
 check (contains(render_block(CodeFence("\"onclick", "<x>"))) "&lt;x&gt;") "fence escape";
 check (not(contains(render_block(Table(["a";"b"],[["one"]]))) "<table>")) "ragged table fallback";
 let page=render_page ["a.md";"b.md"] "a.md" "# A\n## B\n## B\n" in
 check (contains page "id=\"b-2\"") "unique anchors";
 check (contains page "Next: <a href=\"b.html\"") "linear navigation";
 check (not(contains page "<script")) "no script";
 check (List.exists(function CodeFence(_,"<x>")->true | _->false)(parse_markdown "```\n<x>")) "unclosed fence preserved";
 check (contains(parse_inline "[PDF](source%20(1).pdf)") "href=\"source%20(1).pdf\"") "parenthesized filename";
 print_endline "Renderer: 14 boundary checks passed."
let () = try
 let pages ()=Sys.readdir "." |> Array.to_list |> List.filter(fun p->Filename.check_suffix p ".md" && p<>"README.md") |> List.sort String.compare in
 let generate all file=let source=read_file file in if String.length source>2_000_000 then failwith("oversized doc " ^ file); write_file(html_name file)(render_page all file source) in
 match Array.to_list Sys.argv with
 | [_;"--self-test"] -> self_test()
 | [_;"--file";file] -> let all=pages() in if not(List.mem file all)then failwith "file must be a top-level Markdown document";generate all file;printf "Rendered %s locally.\n" file
 | [_] -> let all=pages() in List.iter(generate all)all;printf "Rendered %d local pages; no external publication.\n" (List.length all)
 | _ -> failwith "usage: ocaml render_docs_wiki.ml [--self-test|--file NAME.md]"
 with Failure m -> prerr_endline m; exit 1
