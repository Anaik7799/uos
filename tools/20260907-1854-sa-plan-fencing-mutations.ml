#directory "+unix";;
#load "unix.cma";;
#use "ops_mutate.ml";;

(* Run from an explicitly isolated UOS workspace's engines/hermes directory.
   Reuses Ops_mutate without modifying its source. The private dune adapter
   narrows its legacy whole-tree build command to the fencing test and one job.
   No live Sa-plan database, integration bookmark or service is accessed. *)
let () =
  let root = Unix.realpath (Sys.getcwd ()) in
  if Array.length Sys.argv <> 3 || Sys.argv.(1) <> "--dune"
     || not (contains root "/.uos-workspaces/")
     || not (Filename.check_suffix root "/engines/hermes")
  then (prerr_endline "Run in an isolated .uos-workspaces/*/engines/hermes with --dune ABSOLUTE_DUNE"; exit 64);
  let dune = Unix.realpath Sys.argv.(2) in
  Unix.access dune [Unix.X_OK];
  let source = "modules/sa_plan/sa_plan_store.ml" in
  let gold = match read_file source with Some s -> s | None -> failwith "missing store source" in
  let section first last =
    let index from needle =
      let rec find i =
        if i + String.length needle > String.length gold then failwith ("missing " ^ needle)
        else if String.sub gold i (String.length needle) = needle then i else find (i+1) in
      find from in
    let a = index 0 first in
    String.sub gold a (index a last - a) in
  let mutate name first last find replace expect_killer =
    let body = section first last in
    let changed = match replace_first ~find ~replace body with
      | Some text when text <> body -> text | _ -> failwith ("invalid mutant " ^ name) in
    { name; file=source; find=body; replace=changed; expect_killer } in
  let job_body = section "let complete_job store" "let cancel_job store" in
  let substitute find replace text = match replace_first ~find ~replace text with
    | Some t -> t | None -> failwith ("missing guard " ^ find) in
  let job_changed = job_body
    |> substitute "job.attempt <> expected_attempt" "expected_attempt <= 0"
    |> substitute "AND attempt = ? AND lease_until_ns > ?" "AND ? > 0 AND lease_until_ns > ?" in
  let table = [
    mutate "F-M1 release ignores original attempt" "let release_task store" "let complete_task store"
      "AND attempt = ?" "AND ? > 0" "FENCE-ORACLE";
    mutate "F-M2 completion ignores original attempt" "let complete_task store" "let select_activity db"
      "AND attempt = ?" "AND ? > 0" "FENCE-ORACLE";
    mutate "F-M3 completion accepts exact expiry" "let complete_task store" "let select_activity db"
      "lease_until_ns > ?" "lease_until_ns >= ?" "FENCE-ORACLE";
    {name="F-M4 job ignores original attempt";file=source;find=job_body;replace=job_changed;
     expect_killer="FENCE-JOB-RESTART-SAME-WORKER-STALE"};
    mutate "F-M5 bridge ignores bound task attempt" "let complete_bridge_task store" "let ensure_bridge_mapping store"
      "AND attempt=?" "AND ?>0" "FENCE-BRIDGE-CANNOT-COMPLETE-REPLACEMENT-GENERIC-ATTEMPT";
    mutate "F-M6 lease deadline wraps" "let lease_deadline " "let validate_completion "
      "now_ns > max_value - lease_ns" "now_ns < 0L" "FENCE-CLAIM-DEADLINE-BOUNDS"
  ] in
  let tmp = Filename.temp_file "uos-fence-mutations-" "" in
  Sys.remove tmp; Unix.mkdir tmp 0o700;
  let shim = Filename.concat tmp "dune" and suite = Filename.concat tmp "fencing-suite" in
  let path = Option.value (Sys.getenv_opt "PATH") ~default:"/usr/bin:/bin" in
  let bounded_build = "exec timeout --kill-after=2s 30s " ^ Filename.quote dune
    ^ " build -j 1 modules/sa_plan/test/test_sa_plan_leases.exe\n" in
  write_file shim ("#!/bin/sh\nset -eu\n[ \"$#\" -eq 2 ] && [ \"$1\" = build ] && [ \"$2\" = --pkg=disabled ] || exit 64\n" ^ bounded_build);
  write_file suite ("#!/bin/sh\nexec timeout --kill-after=2s 15s "
    ^ Filename.quote (Filename.concat root "_build/default/modules/sa_plan/test/test_sa_plan_leases.exe") ^ "\n");
  Unix.chmod shim 0o700; Unix.chmod suite 0o700;
  Sys.catch_break true;
  Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> raise Exit));
  let code = Fun.protect ~finally:(fun () ->
      write_file source gold;
      if read_file source <> Some gold then failwith "gold restoration failed";
      Unix.putenv "PATH" path;
      Sys.remove shim; Sys.remove suite; Unix.rmdir tmp)
    (fun () ->
      Unix.putenv "PATH" (tmp ^ ":" ^ path);
      let report = run ~suite table in
      let text, code = render report in print_string text; code) in
  exit code
