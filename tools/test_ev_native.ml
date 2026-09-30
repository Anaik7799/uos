#!/usr/bin/env ocaml
#use "topfind";;
#require "bos,unix,yojson,mtime.clock.os";;
(* @agent_intent: Exercise native adapter failure paths using private OCaml
   child effects. @laws: an unavailable receipt prevents execution; termination
   is nonpassing; output and time exhaustion cannot become a successful result. *)
let root = "/home/an/NAS-setup/uos"
let source = Filename.dirname (Unix.realpath Sys.argv.(0))
let ml = root ^ "/toolchains/opam-ocaml/bin/ocaml"
let mlrun = root ^ "/toolchains/opam-ocaml/bin/ocamlrun"
let mono () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9
let temp = Filename.temp_file "uos-ev-native-tests-" ""
let () = Unix.unlink temp; Unix.mkdir temp 0o700
let write_new path body =
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
  let oc = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc body)
let read path =
  let ic = open_in_bin path in Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> let n = in_channel_length ic in
      if n > 8_388_608 then failwith "test output exceeded bound";
      really_input_string ic n)
let counter = ref 0
let run ?(closed_stdout=false) executable args =
  incr counter;
  let out = Printf.sprintf "%s/process-%02d.txt" temp !counter in
  let fd = Unix.openfile out [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
  let pid = Unix.fork () in
  if pid = 0 then begin
    ignore (Unix.setsid ()); Unix.chdir temp;
    if closed_stdout then begin
      let r, w = Unix.pipe () in Unix.close r;
      Unix.dup2 w Unix.stdout; Unix.close w
    end else Unix.dup2 fd Unix.stdout;
    Unix.dup2 fd Unix.stderr; Unix.close fd;
    Unix.execv executable (Array.of_list (Bos.Cmd.(v executable %% of_list args) |> Bos.Cmd.to_list))
  end;
  Unix.close fd;
  let deadline = mono () +. 15. in
  let rec await () = match Unix.waitpid [Unix.WNOHANG] pid with
    | 0, _ when mono () < deadline -> Unix.sleepf 0.02; await ()
    | 0, _ -> Unix.kill (-pid) Sys.sigkill; ignore (Unix.waitpid [] pid);
        failwith "test subprocess deadline exceeded"
    | _, Unix.WEXITED code -> code, read out
    | _ -> failwith "test adapter terminated abnormally" in
  await ()
let () = write_new (temp ^ "/ev_native_test_child.ml") (read (source ^ "/ev_native_test_child.ml"))
let child = temp ^ "/ev_native_test_child.exe"
let () = let code, output = run (root ^ "/toolchains/opam-ocaml/bin/ocamlfind")
  ["ocamlopt"; "-package"; "unix"; "-linkpkg"; "-o"; child; temp ^ "/ev_native_test_child.ml"] in
  if code <> 0 then failwith ("fixture build: " ^ output)
let run_ml ?(closed_stdout=false) args = run ~closed_stdout mlrun (ml :: args)
let invoke options args = run_ml ([source ^ "/ev_native.ml"] @ options @ ["--"; "native"; child] @ args)
let checks = ref 0
let check name condition =
  if not condition then failwith ("FAIL: " ^ name);
  incr checks; Printf.printf "PASS: %s\n%!" name
let field name json = Yojson.Safe.Util.member name json
let contains text part =
  let rec at i = i + String.length part <= String.length text
    && (String.sub text i (String.length part) = part || at (i + 1)) in at 0
let () =
  let refused_receipt = temp ^ "/sa-plan-help-refused.json" in
  let code, diagnostic = run_ml [source ^ "/ev_native.ml"; "--receipt";
    refused_receipt; "--"; "sa-plan"; "task"; "claim"; "--help"] in
  check "Sa-plan option-style help refuses before child execution"
    (code = 2 && contains diagnostic "refused before execution"
      && not (Sys.file_exists refused_receipt));
  List.iteri (fun index args ->
    let receipt = temp ^ "/sa-plan-worker-refused-" ^ string_of_int index ^ ".json" in
    let code, diagnostic = run_ml ([source ^ "/ev_native.ml"; "--receipt";
      receipt; "--"; "sa-plan"] @ args) in
    check "Sa-plan task/job option workers refuse before child execution"
      (code = 2 && contains diagnostic "WORKER refused before execution"
        && not (Sys.file_exists receipt)))
    [["task";"claim";"--unknown"];
     ["--format";"json";"job";"claim";"q";"--version"];
     ["oban";"run";"q";""];
     ["--job-claim";"q";" "]];
  let occupied = temp ^ "/occupied.json" and forbidden = temp ^ "/forbidden-effect" in
  write_new occupied "preserved receipt\n";
  let code, _ = invoke ["--receipt"; occupied] ["mark"; forbidden] in
  check "existing receipt refuses before child effect"
    (code = 2 && not (Sys.file_exists forbidden) && read occupied = "preserved receipt\n");
  let receipt = temp ^ "/success.json" and marker = temp ^ "/allowed-effect" in
  let code, _ = invoke ["--receipt"; receipt] ["mark"; marker] in
  let observation = Yojson.Safe.from_file receipt in
  check "successful child outcome and effect are retained"
    (code = 0 && Sys.file_exists marker && field "exit_code" observation = `Int 0);
  let launch_environment = Yojson.Safe.Util.(field "otp_launch" observation
    |> field "environment" |> to_list |> List.map to_string) in
  let launch_path = List.find (String.starts_with ~prefix:"PATH=") launch_environment in
  let first_path = List.hd (String.split_on_char ':' launch_path) in
  let private_alias = String.sub first_path 5 (String.length first_path - 5) in
  check "completed adapter removes its private OTP executable alias"
    (not (Sys.file_exists private_alias));
  let receipt = temp ^ "/closed-output.json" and marker = temp ^ "/closed-output-effect" in
  let code, diagnostic = run_ml ~closed_stdout:true
    [source ^ "/ev_native.ml"; "--receipt"; receipt; "--"; "native"; child; "mark"; marker] in
  let observation = Yojson.Safe.from_file receipt in
  check "closed stdout cannot prevent post-execution receipt persistence"
    (code = 125 && Sys.file_exists marker && field "exit_code" observation = `Int 0
      && field "output" observation = `String "effect observed\n"
      && contains diagnostic "AFTER_EXECUTION_REPORTING_FAILURE");
  let receipt = temp ^ "/signal.json" in
  let code, _ = invoke ["--receipt"; receipt] ["signal"] in
  let outcome = field "child_termination" (Yojson.Safe.from_file receipt) in
  check "signal retains portable identity with nonpassing adapter code"
    (code = 125 && field "kind" outcome = `String "SIGNALED"
      && field "ocaml_portable_signal" outcome = `Int Sys.sigterm);
  let receipt = temp ^ "/deadline.json" in
  let code, _ = invoke ["--seconds"; "0.05"; "--receipt"; receipt] ["wait"] in
  let observation = Yojson.Safe.from_file receipt in
  check "deadline terminates the waiting child"
    (code = 124 && contains (Yojson.Safe.to_string (field "failure" observation)) "deadline exceeded"
      && Yojson.Safe.Util.to_float (field "elapsed_seconds" observation) < 2.);
  let receipt = temp ^ "/overflow.json" in
  let code, _ = invoke ["--receipt"; receipt] ["overflow"] in
  let observation = Yojson.Safe.from_file receipt in
  check "output overflow is nonpassing and captured bytes stay bounded"
    (code = 124 && contains (Yojson.Safe.to_string (field "failure" observation)) "output limit exceeded"
      && String.length (Yojson.Safe.Util.to_string (field "output" observation)) <= 4_194_304);
  Printf.printf "%d checks passed; private evidence %s\n" !checks temp
