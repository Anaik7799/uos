let temp_dir () =
  let path = Filename.temp_file "hermes-imports-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let write ~root relative contents =
  let path = Filename.concat root relative in
  let rec ensure d =
    if not (Sys.file_exists d) then begin ensure (Filename.dirname d); Unix.mkdir d 0o700 end
  in
  ensure (Filename.dirname path);
  let channel = open_out_bin path in
  output_string channel contents;
  close_out channel

let () =
  let open Hermes_imports in
  (* module_of_path: dotted names, __init__ collapses to the package. *)
  assert (module_of_path "agent/transports/chat_completions.py" = "agent.transports.chat_completions");
  assert (module_of_path "agent/__init__.py" = "agent");

  (* imports_of_content: both forms, comma lists, and "as" aliases. *)
  let imports = imports_of_content "import b\nfrom c.d import e\nimport x, y as z\n    from deep import q\n" in
  assert (List.mem "b" imports);
  assert (List.mem "c.d" imports);
  assert (List.mem "x" imports);
  assert (List.mem "y" imports);
  assert (List.mem "deep" imports);

  (* analyze over a small tree. *)
  let root = temp_dir () in
  write ~root "a.py" "import b\nfrom c.d import e\n";
  write ~root "b.py" "x = 1\n";
  write ~root "c/d.py" "y = 2\n";
  let s = analyze ~root in
  assert (s.module_count = 3);
  assert (List.mem { source = "a"; target = "b" } s.edges);
  assert (List.mem { source = "a"; target = "c.d" } s.edges);
  (* both targets resolve within the tree *)
  assert (s.internal_edge_count = 2);

  (* anchor coverage (referenced vs orphaned): b is imported by a; a is orphaned. *)
  let coverage = anchor_coverage s ~anchors:[ "b.py"; "a.py"; "c/d.py" ] in
  let status name = List.find (fun c -> c.anchor = name) coverage in
  assert (status "b.py").referenced;
  assert (status "c/d.py").referenced;      (* from c.d import e *)
  assert (not (status "a.py").referenced);  (* nothing imports a *)

  assert (String.length (describe s) > 0);
  print_endline "hermes_imports: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_hermes_imports" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_hermes_imports ]);
  exit (Suite_telemetry.exit_code self)
