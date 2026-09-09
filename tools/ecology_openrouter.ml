#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "unix,sqlite3,yojson,bos.setup,cryptokit";;

(* @agent_intent: One bounded paid calibration call through shared Gleam policy,
   canonical Sa-plan and a fixed daily ledger. No task mutations or optimizer.
   @laws: WIP1; exact body binding; no retries/refunds; fresh task fences;
   results are advisory evidence, never a quality pass or effect authority.
   Run from canonical root after the repository risk active check. This tool
   cannot control unrelated clients spending through the same provider account. *)
open Yojson.Safe.Util
let root="/home/an/NAS-setup/uos"
let ledger=root^"/var/ecology/openrouter_budget.sqlite3"
let evidence=root^"/var/ecology/openrouter-evaluations"
let ocaml=root^"/toolchains/opam-ocaml/bin/ocaml"
let erl=root^"/toolchains/nix-profile/bin/erl"
let guardian=root^"/tools/ecology_process.ml"
let require condition label=if not condition then failwith label
let ok=function Ok value->value|Error message->failwith message
let bos=function Ok value->value|Error(`Msg message)->failwith message
let str key json=member key json |> to_string
let num key json=member key json |> to_int
let int64_json value=`Intlit(Int64.to_string value)
let now_ns()=Int64.of_float(Unix.gettimeofday() *. 1e9)
let sha body=Cryptokit.hash_string(Cryptokit.Hash.sha256())body |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let read path bound=
  let st=Unix.lstat path in require(st.Unix.st_kind=Unix.S_REG && st.Unix.st_size<=bound)"regular_file_bound";
  bos(Bos.OS.File.read(Fpath.v path))
let exclusive path body=
  let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
    let rec write offset=if offset<String.length body then
      write(offset+Unix.write_substring fd body offset(String.length body-offset)) in
    write 0;Unix.fsync fd)
let mkdir path=
  ignore(bos(Bos.OS.Dir.create ~mode:0o700(Fpath.v path)));
  require((Unix.lstat path).Unix.st_kind=Unix.S_DIR)"directory_kind"
let exact fields json=
  require(List.sort String.compare(List.map fst(to_assoc json))=List.sort String.compare fields)"json_fields"
let identifier text=
  String.length text>=1 && String.length text<=128 &&
  String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'.'|'_'|'-'|':'->true|_->false)text
let scope_fields=["plan_id";"task_id";"worker";"attempt";"call_id";"profile";"max_tokens";"system";"user";"case_id";"suite_id"]
let validate_scope json=
  exact scope_fields json;
  List.iter(fun key->let value=str key json in require(String.length value>0 && String.length value<=512 && not(String.contains value '\000'))("scope_"^key))
    ["plan_id";"task_id";"worker";"profile";"case_id";"suite_id"];
  require(identifier(str "call_id" json))"call_id";
  require(num "attempt" json>0)"attempt";
  require(num "max_tokens" json>=1 && num "max_tokens" json<=4096)"token_bound";
  List.iter(fun key->require(String.length(str key json)<=8192 && not(String.contains(str key json)'\000'))"input_bound")["system";"user"];
  json
let authorized_scope scope=
  (* This is the explicitly authorized calibration task, not a capability to
     spend from any task which merely happens to be executing. Expiry/attempt
     still come from current canonical Sa-plan rows. Future tasks need a new
     reviewed effect grant; model advice cannot widen this finite grant. *)
  require(str "plan_id" scope="uos/ecology/20260909-0146"
    && str "task_id" scope="ECOLOGY"
    && str "worker" scope="codex-01a083d2-ecology"
    && num "attempt" scope=2)"paid_calibration_scope"
let sql_rows db query values=
  let statement=Sqlite3.prepare db query in
  Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize statement))(fun()->
    require(Sqlite3.bind_values statement values=Sqlite3.Rc.OK)"task_query_bind";
    let rec read count acc=
      require(count<4096)"task_dependency_bound";
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW->read(count+1)(Array.init(Sqlite3.column_count statement)(Sqlite3.column statement)::acc)
      | Sqlite3.Rc.DONE->List.rev acc
      | _->failwith "task_query_failed" in
    read 0 [])
let guard scope=
  let scope=validate_scope scope in
  authorized_scope scope;
  let path=root^"/var/sa-plan/uos.sqlite3" in
  require((Unix.lstat path).Unix.st_kind=Unix.S_REG)"canonical_task_store_missing";
  (* Fixed read-only observation of the canonical Sa-plan authority. Do not
     call Store.open_db here: it can initialize/migrate a store on opening. *)
  let db=Sqlite3.db_open ~mode:`READONLY ~uri:false path in
  Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db))(fun()->
    Sqlite3.busy_timeout db 500;
    require(Sqlite3.exec db "PRAGMA query_only=ON; BEGIN"=Sqlite3.Rc.OK)"task_snapshot";
    let values=[Sqlite3.Data.TEXT(str "plan_id" scope);Sqlite3.Data.TEXT(str "task_id" scope)] in
    let rows=sql_rows db "SELECT state,worker,attempt,lease_until_ns FROM sa_plan_task WHERE plan_id=? AND id=?" values in
    let state,owner,attempt,deadline=match rows with
      | [row]->(match Array.to_list row with
        | [Sqlite3.Data.TEXT state;Sqlite3.Data.TEXT owner;Sqlite3.Data.INT attempt;Sqlite3.Data.INT deadline]->state,owner,attempt,deadline
        | _->failwith "task_lease_missing")
      | _->failwith "task_missing" in
    let observed=now_ns() in
    require(state="executing" && owner=str "worker" scope && attempt=Int64.of_int(num "attempt" scope))"task_fence";
    require(deadline>Int64.add observed 70_000_000_000L)"task_lease_window";
    let blocked=sql_rows db "SELECT d.dependency_id FROM sa_plan_dependency d LEFT JOIN sa_plan_task t ON t.plan_id=d.plan_id AND t.id=d.dependency_id WHERE d.plan_id=? AND d.task_id=? AND (t.state IS NULL OR t.state!='completed')" values in
    require(blocked=[])"dependency_not_completed";
    require(Sqlite3.exec db "COMMIT"=Sqlite3.Rc.OK)"task_snapshot_commit";
    `Assoc["status",`String"task_fence_observed";"dispatch_authorized",`Bool false;
      "plan_id",member "plan_id" scope;"task_id",member "task_id" scope;"worker",member "worker" scope;
      "attempt",member "attempt" scope;"observed_ns",int64_json observed;"lease_until_ns",int64_json deadline])
let run_command ?(input="") ~timeout_ms ~output_limit arguments=
  let command=Bos.Cmd.of_list(ocaml::"-I"::"+unix"::guardian::string_of_int timeout_ms::string_of_int output_limit::"framed"::arguments) in
  let body,(_,status)=bos(Bos.OS.Cmd.run_io command (Bos.OS.Cmd.in_string input) |> Bos.OS.Cmd.out_string) in
  require(String.length body<=output_limit)"output_bound";
  body,(match status with `Exited code->code|_->125)
let source_files=[
  "tools/ecology_openrouter.ml";"tools/ecology_budget.ml";
  "apps/cepaf_gleam/src/ecology_openrouter_cli.erl";
  "apps/cepaf_gleam/src/cepaf_gleam/ecology/openrouter_engine.gleam";
  "apps/cepaf_gleam/src/cepaf_gleam/ecology/daily_budget.gleam";
  "apps/uos_swarm/src/uos_swarm/openrouter_worker.gleam";
  "apps/uos_swarm/src/uos_openrouter_ffi.erl";
  "tools/validation/openrouter_eval_catalog.ml";
  "tools/validation/openrouter_eval_expr.ml";
  "tools/validation/openrouter_eval_validate.ml";
  "tools/validation/openrouter_eval_native.ml";
  "tools/validation/openrouter_eval_cli.ml"]
let source_snapshot()=`List(List.map(fun path->`Assoc["path",`String path;"sha256",`String(sha(read(root^"/"^path)(1024*1024)))])source_files)
let reserve envelope=
  exact ["scope";"request";"body"] envelope;
  let scope=validate_scope(member "scope" envelope) in
  let request=member "request" envelope and body=str "body" envelope in
  exact ["call_id";"model";"max_tokens";"input_bytes";"body_bytes"] request;
  require(String.length body<=65536)"body_bound";
  let parsed=Yojson.Safe.from_string body in
  let actual_input=match member "messages" parsed |> to_list with
    | [system;user] when str "role" system="system" && str "role" user="user"
      && str "content" system=str "system" scope && str "content" user=str "user" scope ->
        String.length(str "content" system)+String.length(str "content" user)
    | _->failwith "bound_messages" in
  require(str "call_id" request=str "call_id" scope && str "model" request=str "model" parsed
    && num "max_tokens" request=num "max_tokens" parsed && num "max_tokens" request=num "max_tokens" scope
    && num "input_bytes" request=actual_input && num "body_bytes" request=String.length body)"request_binding";
  let fence=guard scope in
  let directory=evidence^"/"^str "call_id" scope in
  let prepared=Yojson.Safe.from_string(read(directory^"/prepared.json")65536) in
  require(str "body" prepared=body && str "status" prepared="prepared")"exact_prepared_body_required";
  let inputs=Yojson.Safe.from_string(read(directory^"/input-manifest.json")65536) in
  require(member "source_files" inputs=source_snapshot())"source_changed_before_reservation";
  let intent=`Assoc["schema",`String"uos.openrouter-evaluation-intent.v1";"scope",scope;
    "request",request;"body_sha256",`String(sha body);"fence",fence;"source_files",source_snapshot()] in
  exclusive(directory^"/intent.json")(Yojson.Safe.to_string intent^"\n");
  let raw,status=run_command ~input:(Yojson.Safe.to_string request) ~timeout_ms:5000 ~output_limit:8192
    [ocaml;root^"/tools/ecology_budget.ml";"reserve";ledger] in
  let result=try Yojson.Safe.from_string raw with _->failwith "uncertain_reservation" in
  require(status=0 && member "dispatch_authorized" result=`Bool true && str "status" result="reserved"
    && str "ledger_path" result=ledger && str "call_id" result=str "call_id" scope
    && num "reservation_nanodollars" result=250_000_000 && num "daily_limit_nanodollars" result=10_000_000_000)"reservation_denied_or_uncertain";
  let receipt=`Assoc["schema",`String"uos.openrouter-bound-reservation.v1";"body_sha256",`String(sha body);
    "request",request;"fence",fence;"reservation",result] in
  exclusive(directory^"/reservation.json")(Yojson.Safe.to_string receipt^"\n");
  `Assoc["status",`String"reserved";"body_sha256",`String(sha body);"call_id",member "call_id" scope;
    "ledger_path",`String ledger;"dispatch_authorized",`Bool true]
let candidate_binding()=
  let binding=Yojson.Safe.from_string(read(root^"/var/ecology/openrouter-candidate.json")4096) in
  exact ["release";"candidate_sha256"] binding;
  let path=str "release" binding and digest=str "candidate_sha256" binding in
  require(String.length digest=64 && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)digest)"candidate_digest";
  require(Filename.dirname path=root^"/var/releases/ecology" && Unix.realpath path=path
    && Filename.check_suffix path digest)"candidate_path";
  let manifest=Yojson.Safe.from_string(read(path^"/release-manifest.json")(1024*1024)) in
  require(str "candidate_sha256" manifest=digest)"candidate_manifest";
  let verified,code=run_command ~timeout_ms:30000 ~output_limit:8192 [ocaml;root^"/tools/ecology_release.ml";"verify";path] in
  require(code=0 && member "status"(Yojson.Safe.from_string verified)=`String"PASS")"candidate_verification_failed";
  binding
let beam_directories binding=
  let base=str "release" binding^"/apps" in
  Sys.readdir base |> Array.to_list |> List.sort String.compare
  |> List.filter_map(fun name->let path=base^"/"^name^"/ebin" in if Sys.file_exists path && Sys.is_directory path then Some path else None)
let run path=
  require(Unix.realpath(Sys.getcwd())=root)"canonical_working_directory_required";
  let raw=read path 24576 in let scope=validate_scope(Yojson.Safe.from_string raw) in
  ignore(guard scope);
  mkdir(root^"/var/ecology");mkdir evidence;
  let lock_path=evidence^"/.dispatch.lock" in
  let fd=Unix.openfile lock_path [Unix.O_RDWR;Unix.O_CREAT;Unix.O_CLOEXEC]0o600 in
  Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
    require((Unix.lstat lock_path).Unix.st_kind=Unix.S_REG)"lock_kind";
    Unix.lockf fd Unix.F_TLOCK 0;
    let directory=evidence^"/"^str "call_id" scope in
    require(not(Sys.file_exists directory))"call_id_already_observed";
    Unix.mkdir directory 0o700;
    exclusive(directory^"/request.json")(Yojson.Safe.to_string scope^"\n");
    let source_before=source_snapshot() in
    let binding=candidate_binding() in
    exclusive(directory^"/input-manifest.json")(Yojson.Safe.to_string(`Assoc["source_files",source_before;"candidate",binding])^"\n");
    let arguments entry=[erl;"+S";"2:2";"+A";"2";"-pa"]@beam_directories binding@
      ["-noshell";"-eval";entry;"-extra";directory^"/request.json"] in
    Unix.putenv "ERL_CRASH_DUMP" "/dev/null";
    let prepared,prepared_code=run_command ~timeout_ms:6000 ~output_limit:65536(arguments "ecology_openrouter_cli:prepare().") in
    require(prepared_code=0 && member "status"(Yojson.Safe.from_string prepared)=`String"prepared")"body_preparation_failed";
    exclusive(directory^"/prepared.json")(prepared^"\n");
    let started=now_ns() in
    let output,code=run_command ~timeout_ms:60000 ~output_limit:65536(arguments "ecology_openrouter_cli:main().") in
    let completed=now_ns() in
    let result=try Yojson.Safe.from_string output with _->`Assoc["status",`String"stopped";"reason",`String"invalid_or_missing_worker_receipt"] in
    let source_after=source_snapshot() in
    let receipt=`Assoc["schema",`String"uos.openrouter-evaluation-observation.v1";"scope",scope;
      "started_ns",int64_json started;"completed_ns",int64_json completed;"exit_code",`Int code;
      "source_unchanged",`Bool(source_before=source_after);"source_files",source_before;
      "candidate",binding;"prepared",Yojson.Safe.from_string prepared;
      "wip_scope",`String"cooperative runner lifetime; crash-safe service ownership remains required";
      "result",result;"quality_evaluation",`String"unrun";"effect_authority",`Bool false;
      "liability_refunded",`Bool false;"account_wide_enforcement",`Bool false] in
    exclusive(directory^"/observation.json")(Yojson.Safe.to_string receipt^"\n");
    print_endline(Yojson.Safe.to_string(`Assoc["receipt",`String(directory^"/observation.json");"observation",receipt]));
    code=0 && str "status" result="completed" && source_before=source_after)
let main()=
  ignore(Unix.umask 0o077);
  require(Array.length Sys.argv=3)"usage: ecology_openrouter.ml run CONFIG | guard JSON | reserve JSON";
  require(String.length Sys.argv.(2)<=131072 && not(String.contains Sys.argv.(2)'\000'))"argument_bound";
  match Sys.argv.(1) with
  | "run"->if not(run Sys.argv.(2)) then exit 1
  | "guard"->guard(Yojson.Safe.from_string Sys.argv.(2)) |> Yojson.Safe.to_string |> print_endline
  | "reserve"->reserve(Yojson.Safe.from_string Sys.argv.(2)) |> Yojson.Safe.to_string |> print_endline
  | _->failwith "unknown_operation"
let ()=try main() with
  | Failure reason->print_endline(Yojson.Safe.to_string(`Assoc["status",`String"stopped";"reason",`String reason;"dispatch_authorized",`Bool false]));exit 1
  | _->print_endline"{\"status\":\"stopped\",\"reason\":\"bounded_driver_failure\",\"dispatch_authorized\":false}";exit 1
