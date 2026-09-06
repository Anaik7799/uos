#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
#require "str";;
(* @agent_intent Publish a bounded, source-addressed cross-project static review.
   @laws No source mutation/execution or source-code admission; lexical declarations
   are not executed cases or coverage percentages; uncertainty remains explicit. *)
open Bos
open Yojson.Basic.Util
let get = function Ok x->x |Error(`Msg s)->failwith s
let read p=get(OS.File.read(Fpath.v p))
let write p text=get(OS.File.write(Fpath.v p)text)
let str r k=match member k r with `String s->s|_->""
let arr r k=match member k r with `List xs->xs|_->[]
let s x=`String x
let has text word=try ignore(Str.search_forward(Str.regexp_string word)text 0);true with Not_found->false
let re pattern text=try ignore(Str.search_forward(Str.regexp_case_fold pattern)text 0);true with Not_found->false
let replace a b text=Str.global_replace(Str.regexp_string a)b text
let escape text=text|>replace "&" "&amp;"|>replace "<" "&lt;"|>replace ">" "&gt;"|>replace "|" "&#124;"|>replace "\n" " "
let csv text="\""^replace "\"" "\"\"" text^"\""
let clip n text=if String.length text<=n then text else String.sub text 0 n^"..."
let root="/home/an/NAS-setup/uos"
let prefix="20260906-0631-"
let output=root^"/docs/design/"^prefix
let run args=get(OS.Cmd.(run_out(Cmd.of_list args)|>out_string|>success))|>String.trim
let sha path=String.sub(run["sha256sum";"--";path])0 64
let browser path text =
  if has text "use Wallaby.Feature" || has text "use Wallaby.DSL" || has text "use Hound" then "B3_REAL_BROWSER_DRIVER_DECLARED_UNRUN"
  else if has text "page.goto" || has text "puppeteer.launch" || has text "chromium.launch" then "B3_REAL_BROWSER_DRIVER_DECLARED_UNRUN"
  else if has text "Phoenix.LiveViewTest" then "B2_SERVER_SIMULATED_LIVEVIEW_NOT_BROWSER"
  else if has text "Phoenix.ConnTest" || has text "ConnCase" then "B1_SERVER_HTTP_OR_COMPONENT_NOT_BROWSER"
  else if has path "/e2e/" || has path "playwright/" || has text "Wallaby" || has text "BasePage" then "BX_INDIRECT_OR_CONFIG_BROWSER_CANDIDATE_INSPECT_RUNNER"
  else "B0_NO_BROWSER_DRIVER_IN_FILE_STATIC_ONLY"
let family path text =
  if re "zettelkasten\\|knowledge\\|smriti\\|wiki" path then "Knowledge, wiki, Zettelkasten and retrieval"
  else if re "navigation\\|portal\\|owner_parent\\|page_spec" path then "Navigation, routes and page contracts"
  else if re "property\\|fractal_bdd\\|full_scenario_bdd\\|fmea" path then "Model properties, BDD and failure scenarios"
  else if re "playwright\\|wallaby\\|/e2e/\\|chrome_browser" path then "Browser drivers, adapters and browser-shaped unit tests"
  else if re "a2ui\\|agui\\|sse\\|eventsource" path then "UI protocol, event streams and component schema"
  else if re "accessib\\|ui_report\\|graphene\\|ruliology" path then "Accessibility, visual representation and report quality"
  else if has text "Phoenix.LiveViewTest" || has path "_live_" || has path "/live/" then "LiveView state, rendering and event handling"
  else "Page/component rendering, controls and shared state"
let scope path text =
  if has text "no production" || has text "self-contained" || has text "defmodule KG do" then "Self-contained reference model; not production integration."
  else if has path "layouts_test.exs" then "Module availability only; layout geometry and behavior absent."
  else if has path "kms_invariants" || has path "vault_kms" then "Key-management security, not knowledge management; adjacent boundary only."
  else if has path "chrome_browser_test" then "Browser configuration, commands and payload constructors; no browser is launched."
  else if has path "wallaby_regression_test.gleam" then "Pure Gleam element construction; the name does not invoke Wallaby."
  else if has path "ssr_views_comprehensive" then "View calls on healthy/critical/zero fixtures; primarily non-crash smoke checks."
  else if has path "c5_navigation" then "Synthetic page-enumeration graph laws; replace model edges with observed links for site coverage."
  else if has text "Phoenix.LiveViewTest" then "Server LiveView/render/click/change observations; JavaScript, CSS, focus and actual browser remain separate."
  else if has text "use Wallaby.Feature" || has text "page.goto" then "Driver-backed scenario declarations; original suite not run in this audit."
  else if has path "zettelkasten" then "Pure knowledge type/classification, decay/trust, ingestion/linking or retrieval laws; inspect per-case assertions."
  else "Static scenario/assertion inventory; coverage limited to recorded operations and predicates, not execution or percentage."
let useful browser family =
  if String.starts_with ~prefix:"B3" browser || String.starts_with ~prefix:"BX" browser then "Preserve scenarios as typed Gleam intents; execute via bounded browser adapter and assert exact DOM/network/state postconditions."
  else if String.starts_with ~prefix:"B2" browser then "Port model/update laws to Gleam and Lustre element queries; map server events to Mist/OTP integration; add real browser scenarios."
  else if has family "Knowledge" then "Port value/graph/parser laws to Gleam; retain Hermes differential oracle; add browser journeys for search, links and export."
  else "Port pure rules and fixtures to Gleeunit over actual UOS modules; replace existence/reflexive checks with semantic and negative assertions."
let selected path text =
  Filename.check_suffix path ".feature" ||
  re "indrajaal_web/\\|/live/\\|wallaby\\|browser\\|e2e/\\|playwright\\|navigation\\|knowledge\\|wiki\\|zettel\\|webui\\|page\\|lustre\\|shell\\|a2ui\\|agui\\|c[1-8]_\\|ssr\\|split_screen\\|fractal_bdd\\|full_scenario_bdd\\|ui_report\\|smriti\\|status_filter\\|eventsource\\|sse_darkcockpit\\|fractal_widget\\|dashboard\\|ruliology_viz" path
  || re "import cepaf_gleam/ui/\\|import cepaf_gleam/zettelkasten/\\|Phoenix.LiveViewTest\\|use Wallaby.Feature\\|@playwright/test\\|puppeteer" text
let declarations language text =
  let in_doc=ref false in
  String.split_on_char '\n' text |>List.mapi(fun i line->i+1,String.trim line)
  |>List.filter_map(fun(line,t)->
    let triples=Str.full_split(Str.regexp_string "\"\"\"")t|>List.filter(function Str.Delim _->true|_->false)|>List.length in
    let hidden= !in_doc || triples>0 in
    if triples mod 2=1 then in_doc:=not !in_doc;
    if hidden || String.starts_with ~prefix:"#" t || String.starts_with ~prefix:"//" t then None else
    let kind=if language="gherkin" && re "^Scenario\\( Outline\\)?:" t then Some "Gherkin scenario (examples not expanded)"
      else if language="gleam" && re "^pub fn [a-z0-9_]+_test(" t then Some "Gleeunit function"
      else if language="elixir" && re "^\\(test\\|property\\|feature\\|scenario\\) " t then Some "ExUnit/feature/property declaration"
      else if language="elixir" && re "^def\\(given\\|when\\|then\\) " t then Some "Gherkin step definition"
      else if language="javascript" && re "^\\(test\\|it\\)\\(\\.skip\\|\\.only\\|\\.each([^)]*)\\)?(" t then Some "JS test declaration (loops not expanded)"
      else None in
    Option.map(fun kind->`Assoc["line",`Int line;"kind",s kind;"declaration",s(clip 300 t)])kind)
let () =
  let census=Yojson.Basic.from_string(read "/tmp/uos-cross-corpus.json") in
  let all=arr census "records" in
  let rows=all|>List.filter(fun r->str r "kind"="test_code" && str r "review"<>"EXCLUDED_SENSITIVE_OR_OVERSIZE")
    |>List.filter_map(fun r->let path=str r "path" in
      let file=str r "root"^"/"^path in
      let text=read file in
      if not(selected path text) then None else (
        let current=sha file in
        let browser=browser path text and family=family path text in
        let warnings=["rescue";"or true";"assert true";"should.be_true(True)";"@tag :skip";"@moduletag :skip";"function_exported?";"Code.ensure_loaded?";"mock";"stub";"no production";"self-contained";"todo"]
          |>List.filter(fun x->has text x)|>List.map s in
        let imports=String.split_on_char '\n' text|>List.map String.trim|>List.filter(fun t->re "^\\(import\\|alias\\|use\\) " t)|>List.map s in
        let summary=scope path text and port=useful browser family in
        let ds=declarations(str r "language")text in
        let lines=Array.of_list(String.split_on_char '\n' text) in
        let ds=List.mapi(fun i d->
          let line=member "line" d|>to_int in
          let last=if i+1<List.length ds then member "line"(List.nth ds(i+1))|>to_int else Array.length lines in
          let predicates=List.init(max 0(last-line))(fun j->line+j+1,lines.(line+j))
            |>List.filter(fun(_,l)->re "assert\\|should\\.\\|expect(\\|refute\\|check all" l)
            |>List.map(fun(n,l)->`Assoc["line",`Int n;"expression",s(clip 220(String.trim l))]) in
          `Assoc(to_assoc d@["assertion_lines",`List predicates;"boundary_note",s "Lexical region to next declaration, not a language AST; helper assertions may be included."]))ds in
        Some(`Assoc["project",member "project" r;"root",member "root" r;"path",s path;"language",member "language" r;
          "sha256",s current;"initial_census_sha256",member "sha256" r;"unchanged_since_census",`Bool(current=str r "sha256");
          "review",s "full_text_indexed_and_classified; detailed human findings are separately identified";
          "category",s family;"browser",s browser;"purpose_and_scope",s summary;"gleam_use",s port;
          "warning_signals_not_automatic_failures",`List warnings;"imports",`List imports;"cases",`List ds;"execution",s "UNRUN"]))) in
  let clock=run["date";"-u";"+%Y-%m-%dT%H:%M:%SZ"] in
  let jsonsafe text=text|>replace "<" "\\u003c"|>replace ">" "\\u003e"|>replace "&" "\\u0026" in
  write(output^"source-corpus-index.json")(jsonsafe(Yojson.Basic.pretty_to_string census)^"\n");
  write(output^"cross-project-test-catalogue.json")(jsonsafe(Yojson.Basic.pretty_to_string(`Assoc["schema",s "uos.cross-project-ui-review.v1";"clock",s clock;"scope",s "Selected file paths plus UI/knowledge imports from the bounded full-text census. Static declarations and assertion lines are not runtime test counts or coverage percentages.";"records",`List rows]))^"\n");
  let cases=List.concat_map(fun r->List.map(fun c->[str r "project";str r "path";string_of_int(member "line" c|>to_int);str c "kind";str c "declaration";str r "category";str r "browser";str r "purpose_and_scope";str r "gleam_use";str r "sha256";"UNRUN"])(arr r "cases"))rows in
  write(output^"cross-project-test-cases.csv")(String.concat "\n"(List.map(fun row->String.concat ","(List.map csv row))(["project";"path";"line";"declaration_kind";"declared_behavior";"category";"browser_class";"coverage_limit";"gleam_use";"source_sha256";"execution"]::cases))^"\n");
  let header=read "/tmp/uos-report-navigation.md" and footer=read "/tmp/uos-report-checklist.md" in
  let table rs="| File and static declarations | Classification and coverage | Gleam use | Browser | Signals to inspect |\n|---|---|---|---|---|\n"^
    String.concat "\n"(List.map(fun r->Printf.sprintf "| [%s](%s/%s) (%d) | **%s**. %s | %s | %s | %s |"
      (escape(str r "path"))(str r "root")(str r "path")(List.length(arr r "cases"))
      (escape(str r "category"))(escape(str r "purpose_and_scope"))(escape(str r "gleam_use"))(str r "browser")
      (arr r "warning_signals_not_automatic_failures"|>List.map to_string|>String.concat ", "|>escape))rs)^"\n" in
  let sections=["c3i";"indrajaal_legacy";"uos"]|>List.map(fun project->
    let rs=List.filter(fun r->str r "project"=project)rows in
    Printf.sprintf "## %s — %d selected files\n\n%s"project(List.length rs)(table rs))|>String.concat "\n" in
  write(output^"cross-project-test-catalogue.md")("# Cross-project UI, navigation and knowledge test catalogue\n\n"^header^
    "\nThis is a static catalogue with a per-declaration CSV and assertion-line JSON. Every entry is UNRUN unless a separate current execution receipt names it. Original source bodies are not changed or imported. The original corpus census is broader than the UI selection; the selection uses both paths and imports. These are declarations, not coverage percentages, runtime loop expansions, or proof of assertions being effective.\n\nB0 = no driver in file; B1 = server/component; B2 = server-simulated LiveView; B3 = real driver declared; BX = indirect/configuration, runner inspection needed. Browser classification is an independent axis from property/BDD/unit. A weak assertion signal warrants inspection, not automatic dismissal of the whole suite. **KMS can mean key management; it is not automatically knowledge management.**\n\n"^sections^footer);
  Printf.printf "Published %d selected files, %d declarations/steps and %d corpus records.\n%!"(List.length rows)(List.length cases)(List.length all);
  List.iter(fun project->let rs=List.filter(fun r->str r "project"=project)rows in
    Printf.printf "%s files=%d declarations=%d changed_since_census=%d\n%!"project(List.length rs)
      (List.fold_left(fun n r->n+List.length(arr r "cases"))0 rs)
      (List.length(List.filter(fun r->member "unchanged_since_census" r=`Bool false)rs)))["c3i";"indrajaal_legacy";"uos"]
