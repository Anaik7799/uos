(* The corpus differential AS A GATE: the live corpus is rendered and
   compared against the committed baseline. A renderer change now moves
   named documents loudly instead of every page silently. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let baseline_path = "modules/hermes_wiki/baseline/render-baseline.txt"

let read_lines path =
  let channel = open_in_bin path in
  let rec go acc =
    match input_line channel with
    | line -> go (line :: acc)
    | exception End_of_file -> close_in channel; List.rev acc
  in
  go []

let documents () =
  let files = Hermes_wiki.read_tracked "modules/hermes_wiki/pages" in
  let model = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file files in
  List.map
    (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.path, p.Hermes_wiki.raw, p.Hermes_wiki.html))
    model.Hermes_wiki.pages

let () =
  check "the committed baseline exists and is populated" (fun () ->
      Sys.file_exists baseline_path && List.length (read_lines baseline_path) >= 20);
  let baseline = Wiki_baseline.of_lines (read_lines baseline_path) in
  let docs = documents () in
  check "the live corpus is non-empty" (fun () -> List.length docs >= 20);
  let outcomes = Wiki_baseline.check ~baseline docs in
  check "NO document has drifted (the gate)" (fun () ->
      match Wiki_baseline.drift outcomes with
      | [] -> true
      | lines -> List.iter (fun l -> print_endline ("  " ^ l)) lines; false);
  check "every document is accounted for (checked, or honestly skipped)"
    (fun () ->
      List.for_all
        (fun (o : Wiki_baseline.outcome) ->
          match o.Wiki_baseline.verdict with
          | Wiki_baseline.Checked | Wiki_baseline.Edited_since -> true
          | Wiki_baseline.Unlisted ->
              print_endline ("  unlisted: " ^ o.Wiki_baseline.path);
              false
          | Wiki_baseline.Drifted _ -> false)
        outcomes);
  check "the gate CAN fail: a mutated render is reported as drift" (fun () ->
      match docs with
      | (path, content, render) :: rest ->
          let mutated = (path, content, render ^ "<!--mutant-->") :: rest in
          Wiki_baseline.drift (Wiki_baseline.check ~baseline mutated) <> []
      | [] -> false);
  check "and a mutated SOURCE is skipped instead (honesty, not drift)" (fun () ->
      match docs with
      | (path, content, render) :: rest ->
          let edited = (path, content ^ "\n\nnew line\n", render ^ "<p>new</p>") :: rest in
          Wiki_baseline.drift (Wiki_baseline.check ~baseline edited) = []
      | [] -> false)

let () =
  Printf.printf "render_baseline: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_render_baseline" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
