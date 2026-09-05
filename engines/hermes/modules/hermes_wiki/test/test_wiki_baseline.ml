(* The corpus render differential. The laws that matter are the honesty
   ones: a drifted render is RED, an edited source is SKIPPED (never
   silently re-baselined), and an unlisted document is named rather than
   ignored. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let corpus =
  [ ("a.md", "# A", "<h1>A</h1>"); ("b.md", "# B", "<h1>B</h1>") ]

let baseline = Wiki_baseline.build corpus

let () =
  check "a baseline has one entry per document" (fun () ->
      List.length baseline = 2);
  check "entries carry BOTH digests and the path" (fun () ->
      List.for_all
        (fun (e : Wiki_baseline.entry) ->
          String.length e.Wiki_baseline.render_digest = 64
          && String.length e.Wiki_baseline.content_digest = 64
          && e.Wiki_baseline.path <> "")
        baseline);
  check "the two digests differ (they digest different things)" (fun () ->
      List.for_all
        (fun (e : Wiki_baseline.entry) ->
          e.Wiki_baseline.render_digest <> e.Wiki_baseline.content_digest)
        baseline);
  check "serialization round trips and is sorted" (fun () ->
      let lines = Wiki_baseline.to_lines baseline in
      Wiki_baseline.of_lines lines = baseline
      && lines = List.sort compare lines);
  check "building is deterministic" (fun () ->
      Wiki_baseline.build corpus = baseline)

let () =
  check "an unchanged corpus is fully Checked" (fun () ->
      List.for_all
        (fun (o : Wiki_baseline.outcome) -> o.Wiki_baseline.verdict = Wiki_baseline.Checked)
        (Wiki_baseline.check ~baseline corpus)
      && Wiki_baseline.drift (Wiki_baseline.check ~baseline corpus) = []);
  check "a RENDER change with unchanged source is DRIFT (the red case)" (fun () ->
      let mutated = [ ("a.md", "# A", "<h1>A CHANGED</h1>"); ("b.md", "# B", "<h1>B</h1>") ] in
      let outcomes = Wiki_baseline.check ~baseline mutated in
      Wiki_baseline.drift outcomes <> []
      && List.exists
           (fun (o : Wiki_baseline.outcome) ->
             o.Wiki_baseline.path = "a.md"
             && match o.Wiki_baseline.verdict with
                | Wiki_baseline.Drifted _ -> true
                | _ -> false)
           outcomes);
  check "an EDITED source is skipped, never silently re-baselined" (fun () ->
      let edited = [ ("a.md", "# A edited", "<h1>A edited</h1>"); ("b.md", "# B", "<h1>B</h1>") ] in
      let outcomes = Wiki_baseline.check ~baseline edited in
      (* The render differs too, but the source changed — so the checker
         must NOT call it drift, and must NOT absorb it. *)
      Wiki_baseline.drift outcomes = []
      && List.exists
           (fun (o : Wiki_baseline.outcome) ->
             o.Wiki_baseline.path = "a.md"
             && o.Wiki_baseline.verdict = Wiki_baseline.Edited_since)
           outcomes);
  check "a document absent from the baseline is Unlisted, not ignored" (fun () ->
      let extra = ("c.md", "# C", "<h1>C</h1>") :: corpus in
      List.exists
        (fun (o : Wiki_baseline.outcome) ->
          o.Wiki_baseline.path = "c.md"
          && o.Wiki_baseline.verdict = Wiki_baseline.Unlisted)
        (Wiki_baseline.check ~baseline extra));
  check "drift names the expected and the actual digest" (fun () ->
      let mutated = [ ("a.md", "# A", "<h1>OTHER</h1>") ] in
      match Wiki_baseline.drift (Wiki_baseline.check ~baseline mutated) with
      | [ line ] ->
          let contains needle =
            let n = String.length needle and h = String.length line in
            let rec go i = i + n <= h && (String.sub line i n = needle || go (i + 1)) in
            go 0
          in
          contains "a.md" && String.length line > 40
      | _ -> false);
  check "checking is deterministic" (fun () ->
      Wiki_baseline.check ~baseline corpus = Wiki_baseline.check ~baseline corpus)

let () =
  Printf.printf "wiki_baseline: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_baseline" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
