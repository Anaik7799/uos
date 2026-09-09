#use "topfind";;
#require "unix,yojson";;
(* Repeatable local compiler/test driver, no shell, network or dependencies. *)
let require b m=if not b then failwith m
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let write p s=let c=open_out_bin p in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c s)
let root=Sys.getcwd()
let compiler=Filename.concat root "toolchains/opam-ocaml/bin/ocamlfind"
let run argv=let pid=Unix.create_process compiler(Array.of_list(compiler::argv))Unix.stdin Unix.stdout Unix.stderr in
  match snd(Unix.waitpid [] pid)with Unix.WEXITED 0->true|_->false
let facade_check dir =
  let ocaml=Filename.concat root "toolchains/opam-ocaml/bin/ocaml" in
  let guardian=Filename.concat root "tools/ecology_process.ml" in
  let count=ref 0 in
  let invoke mojo command ledger input =
    incr count;let stem=Filename.concat dir("facade-"^string_of_int !count) in
    write(stem^".in")input;
    let input_fd=Unix.openfile(stem^".in")[Unix.O_RDONLY]0 in
    let output_fd=Unix.openfile(stem^".out")[Unix.O_CREAT;Unix.O_WRONLY;Unix.O_EXCL]0o600 in
    let args=if mojo then [Filename.concat root "toolchains/pixi/bin/pixi";"run";"--manifest-path";Filename.concat root "services/inference/max/pixi.toml";"--no-install";"--frozen";"mojo";Filename.concat root "tools/ecology_budget.mojo";command;ledger]
      else [ocaml;Filename.concat root "tools/ecology_budget.ml";command;ledger] in
    let full=Array.of_list(ocaml::guardian::"20000"::"8192"::"framed"::args) in
    let pid=Unix.create_process ocaml full input_fd output_fd Unix.stderr in
    Unix.close input_fd;Unix.close output_fd;
    let status=match snd(Unix.waitpid [] pid)with Unix.WEXITED n->n|_->125 in
    let normalized=match Yojson.Safe.from_string(read(stem^".out"))with
      | `Assoc pairs->`Assoc(List.filter(fun(k,_)->k<>"observed_us" && k<>"ledger_path")pairs)
      | _->failwith "facade output must be object" in status,normalized in
  let direct=Filename.concat dir "facade-ocaml.sqlite3" and mojo=Filename.concat dir "facade-mojo.sqlite3" in
  let request={|{"call_id":"facade:one","model":"z-ai/glm-5.3","max_tokens":256,"input_bytes":10,"body_bytes":100}|} in
  let cases=["init","";"reserve",request;"status","";"reserve",request;"reserve","invalid-json"] in
  List.iter(fun(command,input)->require(invoke false command direct input=invoke true command mojo input)("Mojo/OCaml CLI divergence: "^command))cases;
  Printf.printf "{\"facade_status\":\"PASS\",\"equivalent_cases\":5,\"invocations\":10,\"normalized_fields\":[\"observed_us\",\"ledger_path\"]}\n%!"
let () =
  require(Array.length Sys.argv=2) "usage: ocaml tools/validation/ecology_budget_check.ml FRESH_TMP_DIR (from repository root)";
  let dir=Sys.argv.(1) in require(Filename.is_relative dir=false && not(Sys.file_exists dir))"fresh absolute test directory required";
  Unix.mkdir dir 0o700;
  let source=read(Filename.concat root "tools/ecology_budget.ml") in
  let lines=String.split_on_char '\n' source in
  require(List.length(List.filter((=)"let () = cli()")lines)=1)"exact CLI marker required";
  let core=List.filter(fun l->not(String.starts_with ~prefix:"#" l) && l<>"let () = cli()")lines |> String.concat "\n" in
  let core_path=Filename.concat dir "ecology_budget.ml" in write core_path core;
  let main=Filename.concat dir "budget_cli.ml" in write main "let () = Ecology_budget.cli()\n";
  let tests=Filename.concat dir "budget_test.ml" in write tests(read(Filename.concat root "tools/validation/ecology_budget_test.ml"));
  let flags=["ocamlopt";"-package";"unix,sqlite3,yojson,mtime.clock";"-linkpkg";"-w";"+8";"-warn-error";"+8";"-I";dir] in
  let cli=Filename.concat dir "budget_cli" and test=Filename.concat dir "budget_test" in
  require(run(flags@[core_path;main;"-o";cli]))"production source compile failed";
  require(run(flags@[Filename.concat dir "ecology_budget.cmx";tests;"-o";test]))"test source compile failed";
  let negative=Filename.concat dir "negative_conformance.ml" in
  write negative "module Broken : Ecology_budget.STORE = struct type t = unit let initialize ~now:_ _ = Ok () let observe ~now:_ _ = Error Ecology_budget.Ledger_io end\n";
  require(not(run["ocamlc";"-I";dir;"-c";negative]))"negative STORE conformance unexpectedly compiled";
  Printf.printf "negative_conformance=EXPECTED_COMPILE_FAILURE\n%!";
  let pid=Unix.create_process test[|test;cli;dir|]Unix.stdin Unix.stdout Unix.stderr in
  (match snd(Unix.waitpid [] pid)with Unix.WEXITED 0->()|_->failwith "budget tests failed");
  facade_check dir
