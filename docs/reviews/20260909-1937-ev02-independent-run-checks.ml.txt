#use "topfind";;
#require "yojson,cryptokit";;
#load "unix.cma";;
let workspace = "/home/an/NAS-setup/uos/.uos-workspaces/ev98-health-formal-20260909"
let ocamlrun = "/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlrun"
let ocaml = "/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml"
let policy = workspace ^ "/tools/ev02_governance/policy_surface_gate.ml"
let mapping = workspace ^ "/tools/ev02_governance/directive_mapping_gate.ml"
let amendment = workspace ^ "/governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json"
let limit = 1_048_576
let sha text = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) text |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let write path text = let c = open_out_bin path in Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c text)
type termination = Start_failure of string | Timeout | Output_limit | Exited of int | Signaled of int
type capture = { termination : termination; stdout : string; stderr : string; elapsed : float }
let term_json = function
  | Start_failure x -> `Assoc ["kind",`String "start_failure";"detail",`String x]
  | Timeout -> `Assoc ["kind",`String "timeout"] | Output_limit -> `Assoc ["kind",`String "output_limit"]
  | Exited x -> `Assoc ["kind",`String "exited";"code",`Int x]
  | Signaled x -> `Assoc ["kind",`String "signaled";"signal",`Int x]
let run ~seconds argv =
  let began = Unix.gettimeofday () in let or_,ow = Unix.pipe () and er,ew = Unix.pipe () in
  let close fd = try Unix.close fd with Unix.Unix_error _ -> () in
  match (try Ok (Unix.create_process argv.(0) argv Unix.stdin ow ew) with Unix.Unix_error (e,_,_) -> Error (Unix.error_message e)) with
  | Error detail -> close or_; close ow; close er; close ew; {termination=Start_failure detail;stdout="";stderr="";elapsed=Unix.gettimeofday()-.began}
  | Ok pid ->
    close ow; close ew; Unix.set_nonblock or_; Unix.set_nonblock er;
    let out=Buffer.create 256 and err=Buffer.create 256 and oo=ref true and eo=ref true and status=ref None and stopped=ref None in
    let kill why = if !stopped=None then (stopped:=Some why; try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) in
    let drain fd open_ buffer = if !open_ then let b=Bytes.create 8192 in let rec loop () =
      try let n=Unix.read fd b 0 8192 in if n=0 then (close fd;open_:=false) else if Buffer.length buffer+n>limit then kill Output_limit else (Buffer.add_subbytes buffer b 0 n;loop())
      with Unix.Unix_error ((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_) -> () in loop() in
    let rec loop () =
      if !status=None then (match Unix.waitpid [Unix.WNOHANG] pid with 0,_->() | _,s->status:=Some s);
      if !stopped=None && Unix.gettimeofday()-.began>seconds then kill Timeout;
      drain or_ oo out; drain er eo err;
      if !status<>None && not !oo && not !eo then () else if !stopped<>None then begin if !status=None then let _,s=Unix.waitpid [] pid in status:=Some s; drain or_ oo out; drain er eo err end
      else let f=(if !oo then [or_] else[])@(if !eo then [er] else[]) in if f=[] then let _,s=Unix.waitpid [] pid in status:=Some s else (ignore(Unix.select f [] [] 0.02);loop())
    in loop();
    let termination=match !stopped,!status with Some x,_->x | None,Some(Unix.WEXITED x)->Exited x | None,Some(Unix.WSIGNALED x)->Signaled x | None,Some(Unix.WSTOPPED x)->Signaled x | None,None->Start_failure "unreaped" in
    {termination;stdout=Buffer.contents out;stderr=Buffer.contents err;elapsed=Unix.gettimeofday()-.began}
let field name = function `Assoc xs->List.assoc_opt name xs | _->None
let str n j=match field n j with Some(`String x)->Some x|_->None
let int n j=match field n j with Some(`Int x)->Some x|_->None
let structured ~schema ~status ~cases c = match c.termination with Exited 0 -> (try let j=Yojson.Safe.from_string c.stdout in str "schema" j=Some schema&&str "status" j=Some status&&int "cases" j=Some cases with Yojson.Json_error _->false)|_->false
let mapping_hold c = match c.termination with Exited 1 -> (try let j=Yojson.Safe.from_string c.stdout in str "schema" j=Some "uos.ev02-directive-mapping/v1"&&str "status" j=Some "HOLD"&&int "directive_count" j=Some 38&&(match field "rule_rows" j with Some(`List x)->List.length x=38|_->false) with Yojson.Json_error _->false)|_->false
let row out id argv valid c = let so=out^"/"^id^".stdout" and se=out^"/"^id^".stderr" in write so c.stdout;write se c.stderr;`Assoc["id",`String id;"argv",`List(Array.to_list argv|>List.map(fun x->`String x));"termination",term_json c.termination;"elapsed_seconds",`Float c.elapsed;"stdout_path",`String so;"stdout_sha256",`String(sha c.stdout);"stderr_path",`String se;"stderr_sha256",`String(sha c.stderr);"valid",`Bool valid]
let harness_selftest () =
 let f=Filename.temp_file "ev02-harness-" ".ml" in write f "#load \"unix.cma\";;let()=match Sys.argv.(1)with|\"split\"->print_string\"{\\\"schema\\\":\\\"x\\\",\";flush stdout;Unix.sleepf 0.05;print_endline\"\\\"status\\\":\\\"PASS\\\",\\\"cases\\\":1}\"|\"empty\"->()|\"wrong\"->print_endline\"{}\"|\"fail\"->exit 1|\"large\"->print_string(String.make 1048577 'x')|_->Unix.sleepf 1.0";
 let call m s=run~seconds:s[|ocamlrun;ocaml;f;m|] in let split=call "split" 1.0 and empty=call "empty" 1.0 and wrong=call "wrong" 1.0 and fail=call "fail" 1.0 and large=call "large" 1.0 and slow=call "slow" 0.05 and start=run~seconds:1.0[|"/definitely/missing"|] in
 if not(structured~schema:"x"~status:"PASS"~cases:1 split && empty.termination=Exited 0 && not(structured~schema:"x"~status:"PASS"~cases:1 empty) && not(structured~schema:"x"~status:"PASS"~cases:1 wrong) && fail.termination=Exited 1 && large.termination=Output_limit && slow.termination=Timeout && match start.termination with Start_failure _->true|_->false) then failwith"harness-selftest";
 print_endline "{\"schema\":\"uos.ev02-harness/v1\",\"status\":\"PASS\",\"cases\":7}"
let checks out source =
 if Sys.file_exists out then failwith"nonexclusive-output";Unix.mkdir out 0o700;
 let one id expect validate argv=let c=run~seconds:10.0 argv in row out id argv (expect c&&validate c) c in
 let rows=[one "policy-selftest" (fun c->c.termination=Exited 0)(structured~schema:"uos.ev02-policy-surface/v1"~status:"PASS"~cases:6)[|ocamlrun;ocaml;policy;"--selftest"|];one "mapping-selftest"(fun c->c.termination=Exited 0)(structured~schema:"uos.ev02-directive-mapping/v1"~status:"PASS"~cases:5)[|ocamlrun;ocaml;mapping;"--selftest"|];one "mapping-fixture-selftest"(fun c->c.termination=Exited 0)(structured~schema:"uos.ev02-directive-mapping/v1"~status:"PASS"~cases:7)[|ocamlrun;ocaml;mapping;"--fixture-selftest"|];one "mapping-observation"(fun c->c.termination=Exited 1)mapping_hold[|ocamlrun;ocaml;mapping;"--observe";workspace;amendment|]] in
 let valid=List.for_all(function `Assoc x->List.assoc"valid"x=`Bool true|_->false)rows in write(out^"/summary.json")(Yojson.Safe.pretty_to_string(`Assoc["schema",`String"uos.ev02-governance-checks/v2";"authority",`String"REPORT_ONLY";"admission",`String"NOT_GRANTED";"source_commit",`String source;"rows",`List rows;"valid",`Bool valid])^"\n");if valid then 0 else 1
let()=match Array.to_list Sys.argv with [_;"--harness-selftest"]->harness_selftest()|[_;"--run";out;source]->exit(checks out source)|_->failwith"usage"
