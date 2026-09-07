#!/usr/bin/env -S opam exec -- ocaml
#use "./tests/acceptance/compiler_diagnostics.ml";;

let fail message = prerr_endline ("compiler_diagnostics_test: " ^ message); exit 1
let require condition message = if not condition then fail message
let mkdir path = if not (Sys.file_exists path) then Unix.mkdir path 0o700
let rec mkdir_p path =
  if path <> "." && path <> "/" && not (Sys.file_exists path) then begin
    mkdir_p (Filename.dirname path); mkdir path
  end
let write_file path bytes =
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let rec write offset = if offset < String.length bytes then
      write (offset + Unix.write_substring fd bytes offset (String.length bytes - offset)) in write 0)
let copy_checked source target = match read_checked_file ~maximum:source_maximum_bytes source with
  | Error message -> fail message | Ok checked -> write_file target checked.checked_bytes
let remove_tree root =
  let rec remove path =
    match (Unix.lstat path).Unix.st_kind with
    | Unix.S_DIR -> Sys.readdir path |> Array.iter (fun entry -> remove (Filename.concat path entry)); Unix.rmdir path
    | _ -> Unix.unlink path
  in try remove root with Unix.Unix_error _ | Sys_error _ -> ()
let with_scratch test =
  let root = Filename.temp_file "uos-q01-driver-" "" in Unix.unlink root; Unix.mkdir root 0o700;
  Fun.protect ~finally:(fun () -> remove_tree root) (fun () -> test root)
let source root path = Filename.concat root path
let prepare_bound_sources root =
  List.iter (fun item ->
    let target = source root item.path in mkdir_p (Filename.dirname target);
    copy_checked item.path target) requirements;
  mkdir_p (source root "apps/cepaf_gleam/build/dev/erlang/fixture/ebin")
let fake_stage ~deadline:_ name argv =
  { name; argv; result = { termination = Exited 0; stdout = ""; stderr = ""; duration_ms = 0.;
    stdout_truncated = false; stderr_truncated = false; children_reaped = true; pid = 1 } }
let run_at root argv =
  let previous = Sys.getcwd () in
  Fun.protect ~finally:(fun () -> Sys.chdir previous) (fun () -> Sys.chdir root; run_bounded limits argv)

let () =
  let build_only = fake_stage ~deadline:(monotonic_now ()) "gleam_build" ["gleam"; "build"] in
  let build_only = { build_only with result = { build_only.result with stderr =
    "apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam\nUnused imported type" } } in
  require (targeted_unused_warnings [build_only] = 1) "build-stage targeted warning was not counted";
  with_scratch (fun root ->
    prepare_bound_sources root;
    write_file (source root actor.path) "mismatch";
    require (not (run_operation ~run:fake_stage root).passed) "source mismatch passed");
  with_scratch (fun root ->
    prepare_bound_sources root;
    let drift () = write_file (source root runtime.path) "drift" in
    require (not (run_operation ~run:fake_stage ~after_stages:drift root).passed) "post-execution drift passed");
  let driver = Filename.concat (Sys.getcwd ()) "tests/acceptance/compiler_diagnostics.ml" in
  let malformed = run_bounded limits ["ocaml"; driver; "--malformed"] in
  require (malformed.termination = Exited 2) "malformed arguments did not exit 2";
  with_scratch (fun root ->
    Unix.symlink (Filename.concat (Sys.getcwd ()) "tests") (Filename.concat root "tests");
    prepare_bound_sources root;
    write_file (source root actor.path) "mismatch";
    let mismatch = run_at root ["ocaml"; driver] in
    require (mismatch.termination = Exited 1) "source mismatch CLI did not exit 1");
  with_scratch (fun root ->
    Unix.symlink (Filename.concat (Sys.getcwd ()) "tests") (Filename.concat root "tests");
    prepare_bound_sources root;
    write_file (source root actor.path) "mismatch";
    let directory = source root "governance/testing/ocaml_gleam" in
    mkdir_p directory; Unix.chmod directory 0o500;
    Fun.protect ~finally:(fun () -> Unix.chmod directory 0o700) (fun () ->
      let failed_write = run_at root ["ocaml"; driver; "--output";
        "governance/testing/ocaml_gleam/result.json"] in
      require (failed_write.termination = Exited 2) "output write failure did not exit nonzero"));
  print_endline "compiler diagnostics acceptance controls: PASS"
