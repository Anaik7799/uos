#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
#require "str";;
(* @agent_intent Bounded read-only evidence census; no source execution or ingestion.
   @laws Every record retains origin and digest; lexical declarations are not runtime
   tests; generated/dependency/cache and sensitive incident paths are excluded. *)
open Bos
let get = function Ok x -> x | Error (`Msg x) -> failwith x
let has s n = try ignore(Str.search_forward (Str.regexp_string n) s 0); true with Not_found -> false
let matches re s = try ignore(Str.search_forward (Str.regexp_case_fold re) s 0); true with Not_found -> false
let clip n s = if String.length s <= n then s else String.sub s 0 n ^ "..."
let run c = get OS.Cmd.(run_out c |> out_string |> success) |> String.trim
let sha source_path = String.sub (run Cmd.(v "sha256sum" % "--" % source_path)) 0 64
let s x = `String x
let ignored = [".git";".jj";"_build";"build";"deps";"deps_backup";"node_modules";"target";"vendor";"third_party";".cache";".venv";"_opam";"dist";"backups"]
let sensitive p = matches "oauth.*secret\\|private.key\\|credential\\|token.dump\\|ssh.inject" p
let relevant p = matches "wiki\\|zettel\\|knowledge\\|\\bzk\\b\\|\\bkm\\b\\|html\\|markdown\\|browser\\|playwright\\|wallaby\\|navigation\\|accessib\\|webui\\|web.ui\\|lustre\\|bonsai\\|page\\|layout\\|component\\|graph\\|algebra\\|denotation\\|traceability\\|dmc\\|tcm\\|atlas\\|ui.test\\|ui.spec\\|design.system\\|visual\\|ux\\|customer.experience" p
let cases lang text =
  String.split_on_char '\n' text |> List.mapi (fun i line -> i+1,String.trim line)
  |> List.filter_map(fun (line,t) ->
    let kind = if lang = "gleam" && matches "^pub fn [a-z0-9_]+_test(" t then Some "gleeunit_function"
      else if lang = "elixir" && matches "^\\(test\\|property\\|feature\\|scenario\\) " t then Some "exunit_lexical_declaration"
      else if lang = "javascript" && matches "^\\(test\\|it\\)(" t then Some "browser_js_lexical_declaration"
      else None in
    Option.map(fun kind -> `Assoc["line",`Int line;"kind",s kind;"declaration",s(clip 240 t)]) kind)
let walk root sub =
  let count = ref 0 in
  let rec loop rel =
    incr count; if !count > 100000 then failwith "Traversal quota exceeded";
    let p = root ^ "/" ^ rel in
    let st = Unix.lstat p in
    match st.Unix.st_kind with
    | Unix.S_DIR -> Array.to_list(Sys.readdir p) |> List.sort String.compare
       |> List.filter(fun n -> not(List.mem n ignored) && not(String.starts_with ~prefix:"." n))
       |> List.concat_map(fun n -> loop (rel ^ "/" ^ n))
    | Unix.S_REG -> [rel]
    | _ -> [] in
  if Sys.file_exists(root^"/"^sub) then loop sub else []
let specs = [
  "zigvm","/home/an/dev/ver/zigvm",["docs"],[];
  "c3i","/home/an/dev/ver/c3i",["docs"],["lib/cepaf_gleam/test";"lib/indrajaal_gleam_web/test";"test/e2e";"tests/playwright";"playwright.config.js"];
  "indrajaal_legacy","/home/an/dev/ver/c3i/sub-projects/c3i",["docs"],["test";"tests";"e2e_tests/tests";"e2e_tests/playwright.config.ts"];
  "uos","/home/an/NAS-setup/uos",["docs/design";"docs/wiki";"docs/zk";"contracts/rules"],["apps/cepaf_gleam/test";"apps/indrajaal_gleam_web/test"]]
let record project root kind rel =
  let p = root^"/"^rel in
  let size = (Unix.lstat p).Unix.st_size in
  let ext = Filename.extension p in
  let language = match ext with ".gleam"->"gleam"|".exs"|".ex"->"elixir"|".js"|".ts"->"javascript"|".ml"->"ocaml"|".feature"->"gherkin"|_->"document" in
  let base = ["project",s project;"root",s root;"path",s rel;"kind",s kind;"language",s language;"bytes",`Int size] in
  if sensitive p || size > 4_000_000 then `Assoc(base@["review",s "EXCLUDED_SENSITIVE_OR_OVERSIZE"])
  else let before = sha p in
    let text = get(OS.File.read(Fpath.v p)) in
    let after = sha p in
    if before <> after then failwith("Source changed: "^p);
    let is_relevant = relevant rel || relevant text in
    let lines = String.split_on_char '\n' text in
    let headings = if kind="document" then List.mapi(fun i l -> i+1,l) lines
       |> List.filter(fun (_,l)->String.starts_with ~prefix:"#" l)
       |> List.filteri(fun i _->i<80)
       |> List.map(fun (n,l)->`Assoc["line",`Int n;"text",s(clip 200 l)]) else [] in
    let signal needles = List.filter(fun n->has text n) needles |> List.map s in
    let api = signal ["Phoenix.LiveViewTest";"Phoenix.ConnTest";"Wallaby";"Hound";"Playwright";"page.goto";"page.visit";"visit(";"chrome_browser";"StreamData";"ExUnitProperties";"@tag :skip";"assert true";"should.be_true(True)";"todo";"mock";"stub";"UNIMPLEMENTED"] in
    let browser = if has text "Phoenix.LiveViewTest" then "server_simulated_liveview_not_browser"
      else if has text "Wallaby" || has text "Hound" || has text "page.goto" then "browser_candidate_inspect_execution"
      else "no_browser_driver_detected_not_proof_of_absence" in
    `Assoc(base@["sha256",s before;"review",s "full_text_indexed_static_not_executed";
      "relevant",`Bool is_relevant;"heading_index",`List headings;"declarations",`List(cases language text);
      "signals",`List api;"browser_class",s browser;"execution",s "UNRUN"])
let () =
  if Array.length Sys.argv <> 2 || not(String.starts_with ~prefix:"/tmp/" Sys.argv.(1)) then failwith "usage: corpus.ml /tmp/output.json";
  let records = List.concat_map(fun (project,root,docs,tests)->
    let docs = List.concat_map(walk root) docs |> List.filter(fun p->List.mem(Filename.extension p)[".md";".html";".rst";".txt"])
      |> List.map(fun p->record project root "document" p) in
    let tests = List.concat_map(walk root) tests |> List.sort_uniq String.compare
      |> List.filter(fun p->List.mem(Filename.extension p)[".gleam";".exs";".ex";".js";".ts";".ml";".feature"])
      |> List.map(fun p->record project root "test_code" p) in
    Printf.printf "%s documents=%d test_source_files=%d\n%!" project (List.length docs) (List.length tests);
    docs@tests) specs in
  get(OS.File.write(Fpath.v Sys.argv.(1))(Yojson.Basic.pretty_to_string(`Assoc["schema",s "uos.cross-corpus.v1";"records",`List records])^"\n"))
