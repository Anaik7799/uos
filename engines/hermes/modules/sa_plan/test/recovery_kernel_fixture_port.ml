(* PRIVATE TEST WORKER, never linked into production. Only the private fixture
   DRIVER contains the compiled configuration locator/pin; this worker receives
   those test values through its private argv. This is NOT an admitted launcher
   trust boundary. The production recovery_port cannot select this interpreter. *)
module S=Recovery_kernel_fixture
let response status code record=Yojson.Basic.to_string(`Assoc[
 "status",`String status;"code",`String code;"authority",`String"FIXTURE_ONLY_NONE_IN_PRODUCTION";"receipt",record])
let run locator body=
 let open Result in
 let ( let* )=bind in
 let* path,pin,database,ready=try match Yojson.Basic.from_string locator with
  |`List[`String p;`String h;`String d]->Ok(p,h,d,None)
  |`List[`String p;`String h;`String d;`String ready]->Ok(p,h,d,Some ready)
  |_->Error"FIXTURE_LOCATOR"with _->Error"FIXTURE_LOCATOR"in
 let* cfg=Recovery_kernel.read_pinned_data ~path ~sha256:pin in
 let* j=try if String.length body>65536 then Error"WIRE_BOUND"else Ok(Yojson.Basic.from_string body)with Yojson.Json_error _->Error"WIRE_JSON"in
 let* fs=match j with `Assoc fs when List.map fst fs=["operation";"request";"capability";"reviewer_signature";"issuer_signature"]&&Yojson.Basic.to_string j=body->Ok fs|_->Error"WIRE_SCHEMA"in
 let get k=match List.assoc k fs with `String s->Ok s|_->Error"WIRE_TYPE"in
 let* op=get"operation"in let* request_bytes=get"request"in let* capability_bytes=get"capability"in let* reviewer_signature=get"reviewer_signature"in let* issuer_signature=get"issuer_signature"in
 if op="inspect"then(
  let* historical=Recovery_kernel.verify_history cfg ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature in
  match S.cap_inspect_history database historical with
  |Ok(Some j)->Ok(response"HISTORICAL""COMMITTED_FACT_ONLY"j)
  |Ok None->Ok(response"HOLD""ABSENT_RECONCILE_ONLY"`Null)
  |Error _->Error"RECONCILE_UNAVAILABLE")else
 let* ()=if op="commit"then Ok()else Error"UNKNOWN_OPERATION"in
 let* e=Recovery_kernel.verify cfg ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature in
 (* DB locator is also private launcher-owned, never wire. *)
 let* db=S.open_existing database in
 Fun.protect ~finally:(fun()->S.close db)(fun()->
 (match ready with None->()|Some path->let fd=Unix.openfile path[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in ignore(Unix.write_substring fd"ready"0 5);Unix.close fd);
 match S.cap_execute db e with
 |Ok(S.Cap_committed j)->Ok(response"COMMITTED""FIXTURE_COMMIT"j)
 |Ok(S.Cap_historical j)->Ok(response"HISTORICAL""NO_NEW_PERMISSION"j)
 |Error S.Reclaim_unknown->Ok(response"UNKNOWN""RECONCILE_ONLY"`Null)
 |Error(S.Reclaim_refused _)->Error"REFUSED_ROLLBACK")
let ()=
 let body=try
  if Array.length Sys.argv<>2 then Error"LOCATOR_REFUSED"else
  let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  if !n<1|| !n>65536 then Error"FRAME_BOUND"else
  let b=really_input_string stdin !n in
  (try ignore(input_char stdin);Error"TRAILING_INPUT"with End_of_file->run Sys.argv.(1) b)
 with End_of_file->Error"TRUNCATED_FRAME"|_->Error"WORKER_UNAVAILABLE"in
 let b=match body with Ok b->b|Error code->response"HOLD"code`Null in let n=String.length b in
 for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;output_string stdout b;flush stdout
