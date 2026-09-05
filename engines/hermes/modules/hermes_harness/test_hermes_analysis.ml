let temp_dir () =
  let path = Filename.temp_file "hermes-analysis-" "" in
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

let () =
  let root = temp_dir () in
  write ~root "a.py"
    "def foo():\n    return 1\n\nclass Bar:\n    def baz(self):\n        return 2\n";
  write ~root "sub/c.py" "async def qux():\n    pass\n";
  write ~root "__pycache__/skip.py" "def ignored():\n    pass\n";
  write ~root "notes.txt" "def not_python(): pass\n";
  let s = Hermes_analysis.analyze ~root in
  assert (s.files = 2);
  (* foo, baz, qux -- async def counts; def inside a class counts *)
  assert (s.defs = 3);
  assert (s.classes = 1);
  assert (s.lines = 8);
  assert (List.length s.modules = 2);
  (* modules are sorted by path, so a.py precedes sub/c.py *)
  (match s.modules with
   | first :: _ -> assert (Filename.basename first.Hermes_analysis.path = "a.py")
   | [] -> assert false);
  assert (String.length (Hermes_analysis.describe s) > 0);
  (* A missing root is the empty summary, never a raise. *)
  let empty = Hermes_analysis.analyze ~root:"/no/such/hermes-xyz-123" in
  assert (empty.files = 0 && empty.lines = 0 && empty.modules = []);
  print_endline "hermes_analysis: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_hermes_analysis" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_hermes_analysis ]);
  exit (Suite_telemetry.exit_code self)
