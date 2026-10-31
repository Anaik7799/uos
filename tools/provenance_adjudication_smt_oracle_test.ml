#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,str,yojson";;
#use "provenance_adjudication_smt_oracle.ml";;

(* @agent_intent: repeat the corrected UOS 52 independent mutation controls,
   real bounded CLI invocations and OS file-boundary controls using only private
   synthetic fixtures. The sole argv is the retained pinned-Z3 output log; the
   sibling oracle source and actual running OCaml interpreter are derived.
   Import first runs the positive oracle on that log. No hardcoded private var
   paths, new packages, network, task/VCS, production or admission operations.
   The fixed-fixture mutations adapt UOS's 20261031-1548 control evidence.
   @laws: all 52 mutations must HOLD/exit2; complete positive fixture passes;
   raced changes observed before reading retain fd offset0; EOF cap inclusive. *)

let ()=require(Array.length Sys.argv=2)
  "usage: provenance_adjudication_smt_oracle_test.ml <retained-z3-log>"
let oracle_source=Filename.concat (Filename.dirname(Unix.realpath Sys.argv.(0)))
  "provenance_adjudication_smt_oracle.ml"
let interpreter=Unix.realpath Sys.executable_name
let fixture_root=Fpath.v(Unix.realpath(Filename.get_temp_dir_name()))
let run_dir=Fpath.(fixture_root / ("uos-provenance-oracle-test-"^string_of_int(Unix.getpid())))
let ()=match Bos.OS.Dir.create run_dir with
  | Ok true->()|Ok false->failwith "fixture directory exists"|Error(`Msg e)->failwith e
let fixture name=Fpath.to_string Fpath.(run_dir / name)
let write path body=
  let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  let channel=Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun()->close_out channel)(fun()->output_string channel body)
let replace text old fresh=
  ignore(Str.search_forward(Str.regexp_string old)text 0);
  Str.replace_first(Str.regexp_string old)fresh text
let split text marker=
  let at=Str.search_forward(Str.regexp_string marker)text 0 in
  String.sub text 0 at,String.sub text at(String.length text-at)
let run_path name path=
  let out_path=fixture(name^".stdout") and err_path=fixture(name^".stderr") in
  let out=Unix.openfile out_path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  let err=Unix.openfile err_path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  let argv=[|"/usr/bin/timeout";"12s";interpreter;"-w";"@A-4-29-40-41-42-44-45-48-58";
    oracle_source;path|] in
  let pid=Fun.protect ~finally:(fun()->Unix.close out;Unix.close err)
    (fun()->Unix.create_process argv.(0)argv Unix.stdin out err) in
  let _,status=Unix.waitpid [] pid in
  let code=match status with Unix.WEXITED n->n|_-> -1 in
  write(fixture(name^".exit"))(string_of_int code^"\n");
  code,out_path,err_path
let run name body=
  let path=fixture(name^".input") in write path body;
  let code,_,_=run_path name path in name,code
let log=read_regular Sys.argv.(1)
let first,rest=split log "missing_intermediate_refutation"
let fields=
  let re=Str.regexp {|(\([A-Za-z0-9]+\) \(true\|false\|[0-9]+\))|} in
  let rec scan at acc=match Str.search_forward re first at with
    | _->let k=Str.matched_group 1 first and v=Str.matched_group 2 first in
      scan(Str.match_end())((k,v)::acc)
    | exception Not_found->List.rev acc in
  scan 0 []
let ()=require(List.length fields=43) "unexpected positive fixture field count"
let singles=List.map(fun(k,v)->
  let changed=match v with "true"->"false"|"false"->"true"|n->string_of_int(int_of_string n+1000) in
  "positive-"^k,replace first("("^k^" "^v^")")("("^k^" "^changed^")")^rest)fields
let coherent name names old fresh=
  let body=List.fold_left(fun text key->replace text("("^key^" "^old^")")
    ("("^key^" "^fresh^")"))first names in name,body^rest
let coherent_controls=[
  coherent "coherent-candidate" ["candidate";"runtimeCandidate";"formalCandidate";"codexCandidate";"agyCandidate"] "101" "303";
  coherent "coherent-source" ["source";"runtimeSource";"formalSource";"codexSource";"agySource"] "202" "404";
  coherent "coherent-clock" ["utcRaw";"observed";"now"] "5" "6"]
let endpoint_prefix,endpoint=split log "bad_endpoint_only_mutant_witness"
let endpoint_controls=List.map(fun(k,v,fresh)->"endpoint-"^k,
  endpoint_prefix^replace endpoint("("^k^" "^v^")")("("^k^" "^fresh^")"))
  ["target","95","96";"r94","false","true";"r95","true","false"]
let malformed_controls=["unexpected-unknown",log^"\nunknown\n";
  "missing-positive-field",replace first " (r96 false)" ""^rest;
  "extra-positive-field",first^"(unrelated 1)\n"^rest]
let positive_path=fixture "positive.input"
let ()=write positive_path log
let positive_code,positive_out,_=run_path "positive" positive_path
let ()=
  require(positive_code=0) "positive oracle failed";
  let json=Yojson.Safe.from_string(read_regular positive_out) in
  let number key=match Yojson.Safe.Util.member key json with `Int n->n|_->failwith key in
  require(number "positive_fixed_fields"=43 && number "endpoint_fixed_fields"=3 &&
    number "prefix_pairs"=8912896 && number "receipt_patterns"=65536)
    "positive oracle counts changed"
let mutation_outcomes=List.map(fun(name,body)->run name body)
  (singles@coherent_controls@endpoint_controls@malformed_controls)
let ()=require(List.length mutation_outcomes=52 && List.for_all(fun(_,code)->code=2)mutation_outcomes)
  "one of the 52 original negative controls did not HOLD"
let whitespace_controls=[
  "unknown-leading-whitespace",log^"\n \tunknown\n";
  "unknown-trailing-whitespace",log^"\nunknown \t\n";
  "error-leading-whitespace",log^"\n \t(error \"synthetic control\")\n";
  "error-trailing-whitespace",log^"\n(error \"synthetic control\") \t\n"]
let whitespace_outcomes=List.map(fun(name,body)->run name body)whitespace_controls
let ()=require(List.length whitespace_outcomes=4 && List.for_all(fun(_,code)->code=2)whitespace_outcomes)
  "whitespace-normalized unknown/error solver record did not HOLD"

let file_outcomes=ref []
let expect_hold name path=
  let code,_,_=run_path name path in
  file_outcomes:=(name,code)::!file_outcomes;
  require(code=2)("file boundary did not HOLD: "^name)
let ()=
  let symlink=fixture "symlink.input" in Unix.symlink positive_path symlink;
  expect_hold "symlink" symlink;
  let parent=fixture "linked-parent" in Unix.symlink(Fpath.to_string run_dir)parent;
  expect_hold "symlink-parent" (Filename.concat parent "positive.input");
  let dangling=fixture "dangling.input" in Unix.symlink(fixture "absent-target")dangling;
  expect_hold "dangling-symlink" dangling;
  let fifo=fixture "fifo.input" in Unix.mkfifo fifo 0o600;
  expect_hold "fifo" fifo;
  expect_hold "directory" (Fpath.to_string run_dir);
  expect_hold "missing" (fixture "missing.input");
  expect_hold "non-directory-parent" (Filename.concat positive_path "child");
  expect_hold "overlong-path" (String.make 4097 'x');
  let oversized=fixture "oversized.input" in write oversized(String.make(max_log_bytes+1)'x');
  expect_hold "oversized" oversized;
  require(String.length log<=max_log_bytes) "positive fixture exceeds cap";
  let at_cap=fixture "at-cap.input" in
  write at_cap(log^String.make(max_log_bytes-String.length log)' ');
  let code,_,_=run_path "inclusive-cap-positive" at_cap in
  require(code=0) "inclusive 262144-byte EOF cap rejected a valid log"

let staged_outcomes=ref []
let staged name mutate=
  let path=fixture(name^".input") in write path log;
  let opened=open_log path in
  Fun.protect ~finally:(fun()->Unix.close opened.fd)(fun()->
    mutate path;
    let held=try ignore(read_opened opened);false with Failure _->true in
    let unread=Unix.lseek opened.fd 0 Unix.SEEK_CUR=0 in
    require(held && unread)("staged change read payload or did not HOLD: "^name);
    staged_outcomes:=(name,unread)::!staged_outcomes)
let ()=
  staged "growth-after-open" (fun path->
    let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_APPEND;Unix.O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->Unix.close fd)(fun()->ignore(Unix.write_substring fd "x" 0 1)));
  staged "truncate-after-open" (fun path->Unix.truncate path 0);
  staged "replace-after-open" (fun path->
    let foreign=fixture "replacement.input" in write foreign log;Unix.rename foreign path);
  let invalid_nul=try ignore(open_log "bad\000path");false with Failure _->true in
  require invalid_nul "NUL path did not HOLD before open";
  let result=`Assoc[
    "status",`String"PASS_SCOPED";"authority",`String"NONE";
    "provenance",`String"LOCAL CODEX; bounded local solver-output oracle controls";
    "positive_exit",`Int positive_code;"positive_fixed_fields",`Int 43;"endpoint_fixed_fields",`Int 3;
    "prefix_pairs",`Int 8912896;
    "negative_controls",`Int(List.length mutation_outcomes+List.length whitespace_outcomes);
    "original_negative_controls",`Int(List.length mutation_outcomes);
    "whitespace_solver_controls",`Int(List.length whitespace_outcomes);
    "all_negative_exit2",`Bool true;"file_negative_controls",`Int(List.length !file_outcomes);
    "all_file_negative_exit2",`Bool true;"inclusive_cap_positive",`Bool true;
    "staged_changes",`Int(List.length !staged_outcomes);"all_staged_fd_offsets_zero",`Bool true;
    "nul_path_hold",`Bool invalid_nul;"fixture_dir",`String(Fpath.to_string run_dir);
    "mutation_outcomes",`List(List.map(fun(name,code)->`Assoc["case",`String name;"exit",`Int code])
      (mutation_outcomes@whitespace_outcomes));
    "file_outcomes",`List(List.map(fun(name,code)->`Assoc["case",`String name;"exit",`Int code])
      (List.rev !file_outcomes))] in
  let text=Yojson.Safe.pretty_to_string result^"\n" in
  write(fixture "controls.json")text;
  print_string text
