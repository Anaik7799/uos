#use "topfind";;
#require "yojson,cryptokit,mtime.clock.os";;
#load "unix.cma";;

(* EV-02's private check runner.  It is deliberately report-only.  The
   supervisor is adapted from the repository's process-group watchdog model:
   completion is the direct child's waitpid status, never pipe EOF. *)
let workspace = "/home/an/NAS-setup/uos/.uos-workspaces/ev98-health-formal-20260909"
let ocamlrun = "/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlrun"
let ocaml = "/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml"
let jj = "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/jj"
let mapping = workspace ^ "/tools/ev02_governance/directive_mapping_gate.ml"
let amendment = workspace ^ "/governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json"
let per_stream_limit = 1_048_576
let aggregate_limit = 1_572_864
let mono () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9
let sha text = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) text |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let write path text =
  let c = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c text)

type termination = Start_failure of string | Timeout | Output_limit | Unreaped | Exited of int | Signaled of int
type capture = { termination : termination; stdout : string; stderr : string; elapsed : float }
let term_json = function
  | Start_failure x -> `Assoc ["kind",`String "start_failure";"detail",`String x]
  | Timeout -> `Assoc ["kind",`String "timeout"]
  | Output_limit -> `Assoc ["kind",`String "output_limit"]
  | Unreaped -> `Assoc ["kind",`String "unreaped"]
  | Exited x -> `Assoc ["kind",`String "exited";"code",`Int x]
  | Signaled x -> `Assoc ["kind",`String "signaled";"signal",`Int x]
let close fd = try Unix.close fd with Unix.Unix_error _ -> ()
let status_of = function Unix.WEXITED x -> Exited x | Unix.WSIGNALED x | Unix.WSTOPPED x -> Signaled x
let kill_group pid = try Unix.kill (-pid) Sys.sigkill with Unix.Unix_error _ -> ()
let kill_direct pid = try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()

let run ~seconds argv =
  if seconds <= 0. then invalid_arg "nonpositive deadline";
  if Array.length argv = 0 then invalid_arg "empty argv";
  if not (Sys.file_exists argv.(0)) then
    {termination=Start_failure "executable-missing";stdout="";stderr="";elapsed=0.}
  else
  let began = mono () and deadline = mono () +. seconds in
  let out_r, out_w = Unix.pipe ~cloexec:true () and err_r, err_w = Unix.pipe ~cloexec:true () in
  match (try Ok (Unix.fork ()) with Unix.Unix_error (e,_,_) -> Error (Unix.error_message e)) with
  | Error detail -> close out_r; close out_w; close err_r; close err_w;
      {termination=Start_failure detail;stdout="";stderr="";elapsed=mono ()-.began}
  | Ok 0 ->
      (try
         ignore (Unix.setsid ());
         close out_r; close err_r;
         Unix.dup2 out_w Unix.stdout; Unix.dup2 err_w Unix.stderr;
         close out_w; close err_w;
         let null = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
         Unix.dup2 null Unix.stdin; close null;
         Unix.execv argv.(0) argv
       with _ -> Unix._exit 127)
  | Ok pid ->
      close out_w; close err_w; Unix.set_nonblock out_r; Unix.set_nonblock err_r;
      let out = Buffer.create 1024 and err = Buffer.create 1024 in
      let out_open = ref true and err_open = ref true and total = ref 0 in
      let status = ref None and stopped = ref None in
      let chunk = Bytes.create 8192 in
      let quota buffer n = Buffer.length buffer + n <= per_stream_limit && !total + n <= aggregate_limit in
      let drain fd open_ buffer =
        let rec loop () =
          if !stopped <> None || mono () >= deadline then () else
          try
            let n = Unix.read fd chunk 0 (Bytes.length chunk) in
            if n = 0 then (close fd; open_ := false)
            else if quota buffer n then (Buffer.add_subbytes buffer chunk 0 n; total := !total + n; loop ())
            else stopped := Some Output_limit
          with
          | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK),_,_) -> ()
          | Unix.Unix_error (Unix.EBADF,_,_) -> open_ := false
        in loop ()
      in
      let reap_nonblocking grace =
        let limit = mono () +. grace in
        let rec loop () =
          match Unix.waitpid [Unix.WNOHANG] pid with
          | waited, value when waited = pid -> status := Some value
          | _ when mono () >= limit -> ()
          | _ -> ignore (Unix.select [] [] [] 0.002); loop ()
        in if !status = None then loop ()
      in
      let cleanup () =
        kill_group pid;
        if !status = None then kill_direct pid;
        reap_nonblocking 0.10;
        close out_r; close err_r
      in
      Fun.protect ~finally:cleanup (fun () ->
        let rec await () =
          if !status = None then (match Unix.waitpid [Unix.WNOHANG] pid with 0,_ -> () | _,s -> status := Some s);
          drain out_r out_open out; drain err_r err_open err;
          if !stopped = None && mono () >= deadline then stopped := Some Timeout;
          match !stopped, !status with
          | Some _, _ -> ()
          | None, Some _ -> () (* Do not await inherited pipe descriptors. *)
          | None, None ->
              let readers = (if !out_open then [out_r] else []) @ (if !err_open then [err_r] else []) in
              let remaining = max 0. (min 0.01 (deadline -. mono ())) in
              ignore (Unix.select readers [] [] remaining); await ()
        in
        await ();
        (* On a normal direct-child exit, terminate remaining group members
           before returning.  This closes descendant-held writers without a
           pipe-EOF dependency. *)
        kill_group pid;
        if !status = None then reap_nonblocking 0.10;
        if !out_open then drain out_r out_open out;
        if !err_open then drain err_r err_open err;
        let termination = match !stopped, !status with
          | Some x, _ -> x
          | None, Some value -> status_of value
          | None, None -> Unreaped
        in {termination;stdout=Buffer.contents out;stderr=Buffer.contents err;elapsed=mono ()-.began})

let field name = function `Assoc xs -> List.assoc_opt name xs | _ -> None
let str n j = match field n j with Some (`String x) -> Some x | _ -> None
let int n j = match field n j with Some (`Int x) -> Some x | _ -> None
let structured ~schema ~status ~cases c = match c.termination with
  | Exited 0 -> (try let j=Yojson.Safe.from_string c.stdout in str "schema" j=Some schema && str "status" j=Some status && int "cases" j=Some cases with Yojson.Json_error _ -> false)
  | _ -> false
let mapping_hold c = match c.termination with
  | Exited 1 -> (try let j=Yojson.Safe.from_string c.stdout in str "schema" j=Some "uos.ev02-directive-mapping/v1" && str "status" j=Some "HOLD" && int "directive_count" j=Some 38 && (match field "rule_rows" j with Some (`List x) -> List.length x=38 | _ -> false) with Yojson.Json_error _ -> false)
  | _ -> false
let row out id argv valid c =
  let so=out^"/"^id^".stdout" and se=out^"/"^id^".stderr" in write so c.stdout; write se c.stderr;
  `Assoc["id",`String id;"argv",`List(Array.to_list argv |> List.map(fun x -> `String x));"termination",term_json c.termination;"elapsed_seconds",`Float c.elapsed;"stdout_path",`String so;"stdout_sha256",`String(sha c.stdout);"stderr_path",`String se;"stderr_sha256",`String(sha c.stderr);"valid",`Bool valid]

let script_argv script args = Array.of_list (ocamlrun :: ocaml :: "-I" :: "+unix" :: script :: args)
let command_argv exe args = Array.of_list (exe :: args)
let requires condition label = if not condition then failwith label
let rec lowercase_hex s i = if i=String.length s then true else match s.[i] with '0'..'9'|'a'..'f' -> lowercase_hex s (i+1) | _ -> false
let source_paths = ["tools/ev02_governance/run_checks.ml";"tools/ev02_governance/directive_mapping_gate.ml";"tools/ev02_governance/policy_surface_gate.ml";"governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json"]
let local_bytes path =
  let channel = open_in_bin (workspace ^ "/" ^ path) in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () -> really_input_string channel (in_channel_length channel))
let candidate_bytes revision path =
  let selector = "commit_id(\"" ^ revision ^ "\")" in
  let c = run ~seconds:4. (command_argv jj ["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace;"file";"show";"-r";selector;"-T";"";"--";"root:" ^ path]) in
  match c.termination with Exited 0 -> c.stdout | _ -> failwith ("candidate-bytes-unavailable:" ^ path)
let bind_candidate revision =
  requires (String.length revision=40 && lowercase_hex revision 0) "immutable-candidate-required";
  List.map (fun path ->
    let local = local_bytes path and candidate = candidate_bytes revision path in
    requires (local = candidate) ("workspace-bytes-differ:" ^ path);
    `Assoc["path",`String path;"sha256",`String(sha local);"bytes",`Int(String.length local)]) source_paths

let harness_selftest () =
  let f=Filename.temp_file "ev02-harness-" ".ml" in
  write f {|
#load "unix.cma";;
let () = match Sys.argv.(1) with
| "split" -> print_string "{\"schema\":\"x\","; flush stdout; Unix.sleepf 0.02; print_endline "\"status\":\"PASS\",\"cases\":1}"
| "empty" -> ()
| "wrong" -> print_endline "{}"
| "fail" -> exit 1
| "large" -> print_string (String.make 900000 'o'); prerr_string (String.make 900000 'e')
| "early-eof" -> close_out stdout; Unix.sleepf 0.7
| "descendant" ->
    let p=Unix.fork() in
    if p=0 then begin
      Unix.sleepf 0.3;
      let c=open_out Sys.argv.(2) in output_string c "late"; close_out c
    end else exit 0
| _ -> Unix.sleepf 1.0
|};
  let call mode seconds = run ~seconds (script_argv f [mode]) in
  let split=call "split" 1.0 and empty=call "empty" 1.0 and wrong=call "wrong" 1.0 and fail=call "fail" 1.0 and large=call "large" 1.0 and slow=call "slow" 0.05 and eof=call "early-eof" 0.05 and start=run~seconds:1.0[|"/definitely/missing"|] in
  let marker = Filename.temp_file "ev02-harness-descendant-" ".marker" in
  Sys.remove marker;
  let descendant=run ~seconds:1.0 (script_argv f ["descendant"; marker]) in
  Unix.sleepf 0.35;
  requires (structured~schema:"x"~status:"PASS"~cases:1 split) "split-output";
  requires (empty.termination=Exited 0 && not(structured~schema:"x"~status:"PASS"~cases:1 empty)) "empty-exit0";
  requires (not(structured~schema:"x"~status:"PASS"~cases:1 wrong) && fail.termination=Exited 1) "schema-or-exit";
  requires (large.termination=Output_limit && slow.termination=Timeout && eof.termination=Timeout) "quota-or-deadline";
  requires (descendant.termination=Exited 0 && descendant.elapsed<0.3 && not (Sys.file_exists marker)) "descendant-held-writer";
  requires (match start.termination with Start_failure _ -> true | _ -> false) "startup-failure";
  print_endline {|{"schema":"uos.ev02-harness/v2","status":"PASS","cases":8}|}

let checks out revision =
  if Sys.file_exists out then failwith "nonexclusive-output"; Unix.mkdir out 0o700;
  let bindings = bind_candidate revision in
  let one id expect validate argv = let c=run~seconds:10. argv in row out id argv (expect c && validate c) c in
  let rows=[
    one "mapping-selftest" (fun c->c.termination=Exited 0) (structured~schema:"uos.ev02-directive-mapping/v1"~status:"PASS"~cases:5) (script_argv mapping ["--selftest"]);
    one "mapping-fixture-selftest" (fun c->c.termination=Exited 0) (structured~schema:"uos.ev02-directive-mapping/v1"~status:"PASS"~cases:8) (script_argv mapping ["--fixture-selftest"]);
    one "mapping-observation" (fun c->c.termination=Exited 1) mapping_hold (script_argv mapping ["--observe";workspace;amendment])
  ] in
  let valid=List.for_all(function `Assoc x->List.assoc "valid" x=`Bool true|_->false) rows in
  write(out^"/summary.json")(Yojson.Safe.pretty_to_string(`Assoc["schema",`String"uos.ev02-governance-checks/v3";"authority",`String"REPORT_ONLY";"admission",`String"NOT_GRANTED";"candidate_commit",`String revision;"source_bindings",`List bindings;"rows",`List rows;"valid",`Bool valid])^"\\n");
  if valid then 0 else 1

let fixture=Sys.argv.(1)
let child=fixture^"/child.ml"
let ()=write child {child|
#load "unix.cma";;
let write p=let c=open_out_bin p in output_string c "late";close_out c
let ()=match Sys.argv.(1)with
|"normal"->print_endline "normal"
|"close"->Unix.close Unix.stdout;Unix.close Unix.stderr;Unix.sleepf 0.7
|"descendant"->(match Unix.fork()with 0->Unix.sleepf 0.65;write Sys.argv.(2)|_->Unix.sleepf 1.)
|"normal-descendant"->(match Unix.fork()with 0->Unix.sleepf 0.65;write Sys.argv.(2)|_->exit 0)
|"both"->print_string(String.make 800000 'o');flush stdout;prerr_string(String.make 800000 'e');flush stderr
|"finite-writer"->for _=1 to 100 do print_string(String.make 8192 'w');flush stdout;Unix.sleepf 0.003 done
|"exact"->print_string(String.make 1048576 'x');flush stdout
|_->exit 2
|child}
let rows=ref[]
let add name c fields=rows:=`Assoc(["case",`String name;"termination",term_json c.termination;"elapsed",`Float c.elapsed;"stdout_bytes",`Int(String.length c.stdout);"stdout_sha256",`String(sha c.stdout);"stderr_bytes",`Int(String.length c.stderr);"stderr_sha256",`String(sha c.stderr)]@fields)::!rows
let call mode args seconds=run~seconds(script_argv child(mode::args))
let fdcount()=Array.length(Sys.readdir"/proc/self/fd")
let ()=
 let before=fdcount()in
 let normal=call"normal"[]1. in add"normal"normal[];
 let eof=call"close"[]0.1 in add"early-eof"eof[];
 let marker=fixture^"/late-timeout"in let timed=call"descendant"[marker]0.1 in add"descendant-timeout"timed[];
 let marker2=fixture^"/late-normal"in let normal_d=call"normal-descendant"[marker2]1. in add"normal-direct-descendant"normal_d[];
 Unix.sleepf 0.75;
 let both=call"both"[]2. in add"aggregate-output"both[];
 let writer=call"finite-writer"[]0.1 in add"continuing-writer-deadline"writer[];
 let exact=call"exact"[]2. in add"exact-per-stream"exact[];
 let after=fdcount()in
 let policy=run~seconds:0.5(script_argv(fixture^"/policy_surface_gate.ml")["--observe";fixture^"/fifo-root"])in add"retired-policy-fifo"policy["stdout",`String policy.stdout];
 let wrong=try ignore(bind_candidate "e11692afdd54e39b5d2232389bcdc64f93ed0a61");false with Failure _->true in
 let author_summary=let c=open_in_bin"/tmp/ev02-governance-harness-2024/summary.json"in let s=really_input_string c(in_channel_length c)in close_in c;s in
 let strict_json=try ignore(Yojson.Safe.from_string author_summary);true with Yojson.Json_error _->false in
 let checks=["normal",normal.termination=Exited 0;"earlyEOF",eof.termination=Timeout && eof.elapsed<0.5;"timeout-descendant",timed.termination=Timeout && not(Sys.file_exists marker);"normal-descendant",normal_d.termination=Exited 0 && not(Sys.file_exists marker2);"fd-cleanup",before=after;"aggregate",both.termination=Output_limit;"writer-deadline",writer.termination=Timeout && writer.elapsed<0.5;"exact-bound",exact.termination=Exited 0 && String.length exact.stdout=1048576;"retired-policy",policy.termination=Exited 1 && String.contains policy.stdout 'H';"candidate-mismatch",wrong;"strict-author-summary",strict_json]in
 write(fixture^"/lifecycle-results.json")(Yojson.Safe.pretty_to_string(`Assoc["source",`String"1e2f28d24d9f8ac11f7461a81455a8d97560f331";"fd_before",`Int before;"fd_after",`Int after;"timeout_marker_present",`Bool(Sys.file_exists marker);"normal_marker_present",`Bool(Sys.file_exists marker2);"checks",`Assoc(List.map(fun(k,v)->k,`Bool v)checks);"rows",`List(List.rev!rows);"authority",`String"NONE"]));
 List.iter(fun(k,v)->Printf.printf"%s=%b\n"k v)checks
