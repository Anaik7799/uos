#use "topfind";;
#require "bos.setup,yojson,unix";;
(* @agent_intent: Exercise real admission CLI boundaries without model calls.
   @laws: wrong scopes and body bindings fail before paid reservations. *)
open Yojson.Safe.Util
let root="/home/an/NAS-setup/uos"
let ocaml=root^"/toolchains/opam-ocaml/bin/ocaml"
let checks=ref 0
let require label b=if not b then failwith label else incr checks
let bos=function Ok x->x|Error(`Msg x)->failwith x
let set key value json=`Assoc((key,value)::List.remove_assoc key(to_assoc json))
let run operation json=
  let cmd=Bos.Cmd.of_list[ocaml;"-I";"+unix";root^"/tools/ecology_process.ml";"6000";"8192";"framed";
    ocaml;root^"/tools/ecology_openrouter.ml";operation;Yojson.Safe.to_string json] in
  let out,(_,status)=bos(Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.out_string) in
  let code=match status with `Exited n->n|_->125 in
  code,Yojson.Safe.from_string(String.trim out)
let deny expected operation json=
  let code,result=run operation json in
  require("deny_"^expected)(code=1 && member "dispatch_authorized" result=`Bool false && member "reason" result=`String expected)
let ()=
  if Array.length Sys.argv<>2 then failwith "usage: ecology_openrouter_check.ml ACTIVE_SCOPE_JSON";
  let scope=Yojson.Safe.from_file Sys.argv.(1) in
  let code,result=run "guard" scope in
  require "current_scope_observed_without_effect_authority"(code=0 && member "status" result=`String"task_fence_observed" && member "dispatch_authorized" result=`Bool false);
  deny "paid_calibration_scope" "guard" (set "worker"(`String"wrong-owner")scope);
  deny "paid_calibration_scope" "guard" (set "attempt"(`Int(to_int(member "attempt" scope)+1))scope);
  deny "paid_calibration_scope" "guard" (set "task_id"(`String"MISSING-ECOLOGY-EVALUATION-TEST")scope);
  deny "token_bound" "guard" (set "max_tokens"(`Int 4097)scope);
  deny "token_bound" "guard" (set "max_tokens"(`Int 0)scope);
  deny "call_id" "guard" (set "call_id"(`String"../escape")scope);
  deny "input_bound" "guard" (set "user"(`String("bad"^String.make 1 '\000'))scope);
  deny "input_bound" "guard" (set "user"(`String(String.make 8193 'x'))scope);
  deny "json_fields" "guard" (set "ledger_path"(`String"/tmp/alternate.sqlite3")scope);
  deny "json_fields" "guard" (`Assoc(("worker",member "worker" scope)::to_assoc scope));
  let body=`Assoc["model",`String"google/gemma-4-31b-it";"max_tokens",member "max_tokens" scope;
    "messages",`List[
      `Assoc["role",`String"system";"content",member "system" scope];
      `Assoc["role",`String"user";"content",member "user" scope]]] |> Yojson.Safe.to_string in
  let request=`Assoc["call_id",member "call_id" scope;"model",`String"google/gemma-4-31b-it";
    "max_tokens",member "max_tokens" scope;"input_bytes",`Int 0;"body_bytes",`Int(String.length body)] in
  deny "request_binding" "reserve" (`Assoc["scope",scope;"request",request;"body",`String body]);
  let bad_body=`Assoc["model",`String"google/gemma-4-31b-it";"max_tokens",member "max_tokens" scope;"messages",`List[]] |> Yojson.Safe.to_string in
  deny "bound_messages" "reserve" (`Assoc["scope",scope;"request",request;"body",`String bad_body]);
  print_endline(Yojson.Safe.to_string(`Assoc["status",`String"PASS";"checks",`Int !checks;"network_calls",`Int 0;
    "paid_reservations",`Int 0;"scope",`String"real CLI input/task/body rejection boundaries; engine tests cover dispatch ordering"]))
