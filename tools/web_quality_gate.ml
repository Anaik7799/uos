#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
#require "str";;
(* @agent_intent Compile the real UOS Gleam contract, reject invalid type fixtures,
   execute runtime laws, and check independent bounded SMT models with SAT controls.
   @laws Fail closed on unknown/timeout/error; no boolean claim is proof; hash every
   candidate input; compiler and solver are separate evidence modalities. *)
open Bos
let get = function Ok x -> x | Error (`Msg s) -> failwith s
let read p = get(OS.File.read(Fpath.v p))
let write p text = get(OS.File.write(Fpath.v p) text)
let contains s n = try ignore(Str.search_forward(Str.regexp_string n)s 0);true with Not_found->false
let json_string s = `String s
let root = "/home/an/NAS-setup/uos"
let source = root ^ "/apps/cepaf_gleam/src/cepaf_gleam/verification/web_quality_contract.gleam"
let scratch = Filename.temp_dir "uos-web-quality-" ""
let run ?(cwd=root) seconds args =
  let errpath = Filename.concat scratch "command.stderr" in
  let cmd = Cmd.(v "timeout" % "--signal=TERM" % "--kill-after=2s" % (string_of_int seconds ^ "s") %% of_list args) in
  let (out, (_, status)) = get(OS.Dir.with_current(Fpath.v cwd)(fun () ->
    OS.Cmd.(run_out ~err:(err_file(Fpath.v errpath)) cmd |> out_string))()) |> get in
  let code = match status with `Exited c->c | `Signaled s->128+s in
  code, out ^ "\n" ^ read errpath
let checked args = let code,out=run 30 args in if code<>0 then failwith out;String.trim out
let sha path = String.sub (checked ["sha256sum";"--";path]) 0 64
let records = ref []
let record name passed detail =
  records := `Assoc["name",json_string name;"passed",`Bool passed;"detail",json_string detail] :: !records;
  Printf.printf "%s %s\n%!" (if passed then "PASS" else "FAIL") name
let model = {|
(set-option :timeout 3000)
(set-logic QF_LIA)
(define-fun join ((a Int) (b Int)) Int (ite (> a b) a b))
(define-fun valid ((a Int)) Bool (and (<= 0 a) (<= a 2)))
(define-fun admit ((a Int) (b Int)) Bool (and (= a 0) (= b 0)))
(declare-const a Int)
(declare-const b Int)
(declare-const c Int)
(assert (and (valid a) (valid b) (valid c)))
|}
let models = [
  "join_associativity", "(not (= (join (join a b) c) (join a (join b c))))", "unsat";
  "join_commutativity", "(not (= (join a b) (join b a)))", "unsat";
  "join_idempotence", "(not (= (join a a) a))", "unsat";
  "failed_absorbs", "(not (= (join a 2) 2))", "unsat";
  "unrun_cannot_admit", "(and (= a 1) (admit a b))", "unsat";
  "two_keys_required", "(and (admit a b) (or (not (= a 0)) (not (= b 0))))", "unsat";
  "satisfiable_success_control", "(and (admit a b) (= c 2))", "sat";
  "satisfiable_rejection_control", "(and (= a 1) (= b 0) (not (admit a b)))", "sat";
  "mutant_min_join_witness", "(and (not (= a b)) (not (= (join a b) (ite (< a b) a b))))", "sat";
  "mutant_or_admission_witness", "(and (or (= a 0) (= b 0)) (not (admit a b)))", "sat";
]
let fixtures = [
 "positive", "pub fn check() { q.layer(4) }", true, "";
 "opaque_constructor", "pub fn check() { q.Layer(99) }", false, "Unknown module value";
 "wrong_layer_type", "pub fn check() { q.layer(\"four\") }", false, "Type mismatch";
 "nonexhaustive_evidence", "pub fn check(e: q.Evidence) { case e { q.Passed -> True q.Unrun -> False } }", false, "Inexhaustive patterns";
 "opaque_route", "pub fn check() { q.Route(\"javascript:bad\") }", false, "Unknown module value";
]
let main output =
  if not(String.starts_with ~prefix:"/tmp/" output || String.starts_with ~prefix:(root^"/verification/") output) then failwith "Output outside evidence roots";
  let digest_before=sha source in
  let version=checked ["gleam";"--version"] and solver_version=checked ["z3";"--version"] in
  let revision=checked ["jj";"log";"--no-graph";"-r";"@";"-T";"change_id ++ \" \" ++ commit_id"] in
  let project=scratch^"/compiler" in
  ignore(get(OS.Dir.create ~path:true(Fpath.v(project^"/src"))));
  write (project^"/gleam.toml") "name = \"web_quality_fixture\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n";
  write (project^"/src/web_quality_contract.gleam") (read source);
  List.iter(fun (name,body,positive,diagnostic)->
    write (project^"/src/fixture.gleam") ("import web_quality_contract as q\n"^body^"\n");
    let code,out=run ~cwd:project 30 ["gleam";"check"] in
    let passed=if positive then code=0 else code=1 && contains out diagnostic in
    record ("compiler_"^name) passed out) fixtures;
  write (project^"/src/fixture.gleam") "import web_quality_contract as q\npub fn check() { q.layer(4) }\n";
  let js_code,js_out=run ~cwd:project 30 ["gleam";"check";"--target";"javascript"] in
  record "compiler_javascript_target_positive" (js_code=0) js_out;
  let code,out=run ~cwd:(root^"/apps/cepaf_gleam") 60 ["gleam";"run";"-m";"web_quality_contract_test"] in
  record "actual_uos_gleam_runtime" (code=0 && contains out "10 test functions passed; 1000 generated route seeds; 512 graph oracles") out;
  let observed=String.split_on_char '\n' out |>List.filter(fun line->String.starts_with ~prefix:"MODEL " line) in
  let pairs=List.filter_map(fun line->match String.split_on_char ' ' line with
    |["MODEL";a;b;_;_]->Some(a^":"^b)|_->None)observed |>List.sort_uniq String.compare in
  let expected_pairs=List.concat_map(fun a->List.map(fun b->string_of_int a^":"^string_of_int b)[0;1;2])[0;1;2] in
  record "runtime_model_pair_coverage" (List.length observed=9 && pairs=expected_pairs)
    ("observations="^string_of_int(List.length observed)^"; unique_pairs="^String.concat "," pairs);
  List.iteri(fun index line->
    match String.split_on_char ' ' line with
    | ["MODEL";a;b;joined;admitted] when List.mem admitted ["true";"false"] ->
      let a=int_of_string a and b=int_of_string b and joined=int_of_string joined in
      if a<0 || a>2 || b<0 || b>2 || joined<0 || joined>2 then failwith "Invalid runtime evidence encoding";
      let query=model^Printf.sprintf "\n(assert (and (= a %d) (= b %d)))\n(assert (or (not (= (join a b) %d)) (not (= (admit a b) %s))))\n(check-sat)\n(exit)\n" a b joined admitted in
      let path=scratch^"/runtime-"^string_of_int index^".smt2" in write path query;
      let code,out=run 8 ["z3";"-smt2";path] in
      record ("gleam_to_smt_conformance_"^string_of_int a^"_"^string_of_int b)
        (code=0 && String.trim out="unsat") (line^"; negated conformance="^String.trim out)
    | _ ->failwith "Malformed runtime evidence observation") observed;
  List.iter(fun (name,assertion,expected)->
    let query=model^"\n(assert "^assertion^")\n(check-sat)\n(exit)\n" in
    let path=scratch^"/"^name^".smt2" in write path query;
    let code,out=run 8 ["z3";"-smt2";path] in
    record ("smt_"^name) (code=0 && String.trim out=expected)
      ("expected="^expected^"; observed="^String.trim out^"; query_sha256="^sha path);
  ) models;
  record "source_unchanged_during_gate" (digest_before=sha source) digest_before;
  let passed=List.for_all(fun r->Yojson.Basic.Util.(r|>member "passed"|>to_bool)) !records in
  write output (Yojson.Basic.pretty_to_string(`Assoc[
    "schema",json_string "uos.web-quality-gate.v1";"passed",`Bool passed;
    "scope",json_string "Compiler/runtime checks of the named UOS module; SMT proofs of the stated evidence semilattice model only. No browser execution or proof of arbitrary Gleam programs.";
    "source",json_string source;"source_sha256",json_string digest_before;
    "test_sha256",json_string(sha(root^"/apps/cepaf_gleam/test/web_quality_contract_test.gleam"));
    "gate_sha256",json_string(sha(root^"/tools/web_quality_gate.ml"));
    "candidate",json_string revision;"clock_utc",json_string(checked["date";"-u";"+%Y-%m-%dT%H:%M:%SZ"]);
    "gleam",json_string version;"z3",json_string solver_version;
    "scratch_evidence",json_string scratch;"checks",`List(List.rev !records)])^"\n");
  if not passed then exit 1
let () = try
  if Array.length Sys.argv<>2 then failwith "usage: ocaml tools/web_quality_gate.ml OUTPUT.json";
  main Sys.argv.(1)
with exn -> Printf.eprintf "web quality gate error: %s\n%!" (Printexc.to_string exn);exit 2
