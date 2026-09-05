let temp_directory () =
  let path = Filename.temp_file "ocaml-only-guard-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let write ~root relative contents =
  let path = Filename.concat root relative in
  let rec ensure directory =
    if not (Sys.file_exists directory) then begin
      ensure (Filename.dirname directory);
      Unix.mkdir directory 0o700
    end
  in
  ensure (Filename.dirname path);
  let channel = open_out_bin path in
  output_string channel contents;
  close_out channel

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun name -> remove_tree (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

let with_workspace f =
  let root = temp_directory () in
  write ~root "hermes_workspace.opam" "";
  write ~root "hermes_workspace.opam.locked" "";
  Fun.protect ~finally:(fun () -> remove_tree root) (fun () -> f root)

let paths violations =
  List.map (fun (v : Ocaml_only_guard.violation) -> v.path) violations

let () =
  (* Missing opam files are a violation *)
  let root_missing = temp_directory () in
  let v_missing = Ocaml_only_guard.scan ~root:root_missing in
  assert (List.length v_missing = 2);
  remove_tree root_missing;

  (* Forbidden requirements.txt is a violation *)
  with_workspace (fun root ->
      write ~root "requirements.txt" "requests==2.0\n";
      assert (paths (Ocaml_only_guard.scan ~root) = [ "requirements.txt" ]));

  (* Forbidden package.json is a violation *)
  with_workspace (fun root ->
      write ~root "package.json" "{}\n";
      assert (paths (Ocaml_only_guard.scan ~root) = [ "package.json" ]));

  (* A Python source file anywhere in the workspace is a violation. *)
  with_workspace (fun root ->
      write ~root "tools/helper.py" "print('hi')\n";
      assert (paths (Ocaml_only_guard.scan ~root) = [ "tools/helper.py" ]));

  (* A python shebang is a violation whatever the extension. *)
  with_workspace (fun root ->
      write ~root "scripts/report" "#!/usr/bin/env python3\nprint(1)\n";
      assert (paths (Ocaml_only_guard.scan ~root) = [ "scripts/report" ]));

  (* A build or shell surface that shells out to python is a violation. *)
  with_workspace (fun root ->
      write ~root "run.sh" "#!/bin/sh\npython3 analyse.py\n";
      assert (List.mem "run.sh" (paths (Ocaml_only_guard.scan ~root))));

  (* The frozen reference and its stand-in fixtures are data, not tooling. *)
  with_workspace (fun root ->
      write ~root "external/hermes_source/agent/loop.py" "x = 1\n";
      write ~root "modules/hermes_harness/fixtures/reference/root.py" "y = 2\n";
      assert (Ocaml_only_guard.scan ~root = []));

  (* Vendored deps of the embedded Rust engine are data too -- a build helper
     shipped inside a pinned crate is not our tooling. *)
  with_workspace (fun root ->
      write ~root "rust/drift_engine/vendor/libc/etc/libc-util.py" "z = 3\n";
      assert (Ocaml_only_guard.scan ~root = []));

  (* Prose may name Python: the reference is written in it. *)
  with_workspace (fun root ->
      write ~root "docs/notes.md" "The frozen reference is Python; we do not use python here.\n";
      assert (Ocaml_only_guard.scan ~root = []));

  (* OCaml that merely mentions python is not a tooling surface; the guard
     watches build and shell files, so it does not train people to avoid the
     word in code comments. *)
  with_workspace (fun root ->
      write ~root "lib/probe.ml" "let interpreter = \"python3\"\n";
      assert (Ocaml_only_guard.scan ~root = []));

  (* Ignored directories are not scanned. *)
  with_workspace (fun root ->
      write ~root "_build/default/gen.py" "z = 3\n";
      write ~root "state/dump.py" "z = 4\n";
      assert (Ocaml_only_guard.scan ~root = []));

  (* A directory entry may disappear between readdir and stat (SQLite journal
     sidecars do exactly this).  A transient path is unavailable evidence, not
     an exception that may escape the scanner. *)
  with_workspace (fun root ->
      write ~root "transient-journal" "temporary";
      let removed = ref false in
      Ocaml_only_guard.For_test.with_before_classify
        (fun path ->
          if Filename.basename path = "transient-journal" && not !removed then begin
            removed := true;
            Sys.remove path
          end)
        (fun () -> assert (Ocaml_only_guard.scan ~root = [])));

  (* Several violations are all reported, in path order. *)
  with_workspace (fun root ->
      write ~root "a.py" "1\n";
      write ~root "b/c.py" "2\n";
      assert (paths (Ocaml_only_guard.scan ~root) = [ "a.py"; "b/c.py" ]);
      assert (
        List.for_all
          (fun (v : Ocaml_only_guard.violation) ->
            String.length (Ocaml_only_guard.render v) > String.length v.path)
          (Ocaml_only_guard.scan ~root)));

  (* The real repository must be clean. This is the control, not the fixtures
     above: it fails the moment anyone adds Python tooling to the harness. *)
  let violations = Ocaml_only_guard.scan ~root:"." in
  if violations <> [] then begin
    prerr_endline "OCaml-only rule violated:";
    List.iter (fun v -> prerr_endline ("  " ^ Ocaml_only_guard.render v)) violations;
    exit 1
  end;
  print_endline "ocaml_only_guard: workspace is OCaml-only"

(* The permitted external tools are documented, and each states its
   absent-case behaviour: a tool whose absence could be mistaken for success
   would defeat the point of allowing it at all. *)
let () =
  assert (List.length Ocaml_only_guard.permitted_external_tools = 5);
  (* quint is the bounded state-machine checker: its verdict is compared against
     the OCaml transition system differentially; absent => the differential is
     skipped and DISCLOSED, never assumed. *)
  assert (List.mem_assoc "quint" Ocaml_only_guard.permitted_external_tools);
  List.iter
    (fun (name, rationale) ->
      assert (String.trim name <> "");
      assert (String.length rationale > 20))
    Ocaml_only_guard.permitted_external_tools;
  assert (List.mem_assoc "z3" Ocaml_only_guard.permitted_external_tools);
  assert (List.mem_assoc "gospel" Ocaml_only_guard.permitted_external_tools);
  assert (List.mem_assoc "python3" Ocaml_only_guard.permitted_external_tools);
  (* df is the free-space oracle for the resource-envelope preflight: its output
     is validated and its failure is treated as unknown, never as success. *)
  assert (List.mem_assoc "df" Ocaml_only_guard.permitted_external_tools);
  print_endline "ocaml_only_guard: external tool allowances declared"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_ocaml_only_guard" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_ocaml_only_guard ]);
  exit (Suite_telemetry.exit_code self)
