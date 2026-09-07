#directory "+unix";;
#load "unix.cma";;
#use "ops_mutate.ml";;

(* Repository-owned, bounded adapter around Ops_mutate. Canonical workspace
   is refused; only the two named candidate files are temporarily changed. *)
let () =
  let root = Unix.realpath (Sys.getcwd ()) in
  if Array.length Sys.argv <> 3 || Sys.argv.(1) <> "--dune"
     || not (contains root "/.uos-workspaces/codex-side-resource-controls/")
     || not (Filename.check_suffix root "/engines/hermes")
  then (prerr_endline "Use the isolated resource-controls workspace and --dune ABSOLUTE_DUNE"; exit 64);
  let dune = Unix.realpath Sys.argv.(2) in
  Unix.access dune [Unix.X_OK];
  let resource = "modules/hermes_harness/resource_envelope.ml"
  and programme = "modules/system_engg/run_swarm_bridge_programme.ml" in
  let gold = List.map (fun path -> path,
    match read_file path with Some text -> text | None -> failwith path) [resource; programme] in
  let mutation name file find replace expect_killer = {name;file;find;replace;expect_killer} in
  let table = [
    mutation "R1 negative quantities" resource
      "if needed < 0 || available < 0 then" "if false then" "NUMERIC negative request";
    mutation "R2 negative margins" resource
      "not (Float.is_finite margin) || margin < 0.0" "not (Float.is_finite margin)"
      "NUMERIC negative margin";
    mutation "R3 nonfinite margins" resource
      "not (Float.is_finite margin) || margin < 0.0" "margin < 0.0"
      "NUMERIC nan margin";
    mutation "R4 rounded requested bytes" resource
      "Q.of_int needed" "Q.of_float (float_of_int needed)"
      "NUMERIC exact large margin accepts equality";
    mutation "R5 rounded available bytes" resource
      "Q.of_int available" "Q.of_float (float_of_int available)"
      "NUMERIC exact large margin rejects one-byte shortage";
    mutation "R6 weakened floor" resource
      "available - needed >= floor_bytes" "available - needed >= floor_bytes - 1"
      "NUMERIC zero request one byte below floor";
    mutation "R7 forged receipt authority" resource
      "check.met && check.receipt_bound" "check.met"
      "ORACLE facts never mint receipts";
    mutation "R8 shadow filesystem observation" programme
      "let checks = Resource_envelope.preflight (state_resources path) in"
      "let checks = if Sys.file_exists (Filename.dirname path) then Resource_envelope.preflight (state_resources path) else [] in"
      "unavailable observer is disclosed even when state directory is absent"
  ] in
  let tmp = Filename.temp_file "uos-resource-mutations-" "" in
  Sys.remove tmp; Unix.mkdir tmp 0o700;
  let shim = Filename.concat tmp "dune" and suite = Filename.concat tmp "suite" in
  let log = Filename.concat tmp "result" in
  let path = Option.value (Sys.getenv_opt "PATH") ~default:"/usr/bin:/bin" in
  write_file shim ("#!/bin/sh\nset -eu\n[ \"$#\" -eq 2 ] && [ \"$1\" = build ] && [ \"$2\" = --pkg=disabled ] || exit 64\nexec timeout --kill-after=2s 30s "
    ^ Filename.quote dune
    ^ " build -j 1 modules/hermes_harness/test_resource_envelope.exe modules/system_engg/test_run_swarm_bridge_programme.exe\n");
  let executables = ["modules/hermes_harness/test_resource_envelope.exe";
                     "modules/system_engg/test_run_swarm_bridge_programme.exe"] in
  write_file suite ("#!/bin/sh\nset -eu\n" ^ String.concat "\n"
    (List.map (fun executable ->
      "if timeout --kill-after=2s 15s " ^
      Filename.quote (Filename.concat root ("_build/default/" ^ executable))
      ^ " >" ^ Filename.quote log ^ " 2>&1; then rc=0; else rc=$?; fi\n"
      ^ "[ \"$rc\" -le 1 ] || exit 2\n"
      ^ "sed 's/^[[:space:]]*FAIL[[:space:]]*/FAILED: /' " ^ Filename.quote log)
      executables) ^ "\n");
  Unix.chmod shim 0o700; Unix.chmod suite 0o700;
  Sys.catch_break true;
  Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> raise Exit));
  let code = Fun.protect ~finally:(fun () ->
    List.iter (fun (file,text) -> write_file file text;
      if read_file file <> Some text then failwith "source restoration failed") gold;
    Unix.putenv "PATH" path;
    List.iter (fun file -> if Sys.file_exists file then Sys.remove file) [shim;suite;log];
    Unix.rmdir tmp)
    (fun () ->
      Unix.putenv "PATH" (tmp ^ ":" ^ path);
      let report = run ~suite table in
      let output, code = render report in print_string output; code) in
  exit code

