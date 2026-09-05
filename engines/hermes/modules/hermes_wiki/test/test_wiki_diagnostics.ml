(* Fractal diagnostics for the wiki plane. Mutants (killers named):
     F-M1 a monitor denies credit        (killed: the R5 law leg)
     F-M2 origin Implementation          (killed: the R5 origin leg)
     F-M3 every finding one level        (killed: the coordinate leg)
     F-M4 the otel bridge drops the level(killed: the attribute leg) *)
let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let all = Wiki_diagnostics.all_findings_sample
let ds = List.map Wiki_diagnostics.diagnose all

let () =
  check "the sample exercises EVERY finding constructor (16)" (fun () ->
      List.length all = 16);
  check "HW.9.2.1: an unresolved include is an L4 FIXTURE finding (the file IS the fixture)"
    (fun () ->
      let d =
        Wiki_diagnostics.diagnose
          (Wiki_diagnostics.Include_gap { page = "p"; path = "src/a.ml"; reason = "cannot read" })
      in
      d.Fractal_diagnostic.level = Fractal_diagnostic.L4_fixture
      && d.Fractal_diagnostic.impact = Fractal_diagnostic.Blocks_credit
      && d.Fractal_diagnostic.origin <> Fractal_diagnostic.Implementation);
  check "THE R5 LAW: no wiki monitor diagnostic ever denies credit" (fun () ->
      List.for_all
        (fun (d : Fractal_diagnostic.t) ->
          d.Fractal_diagnostic.impact <> Fractal_diagnostic.Denies_credit)
        ds);
  check "THE R5 LAW: no wiki monitor diagnostic blames Implementation" (fun () ->
      List.for_all
        (fun (d : Fractal_diagnostic.t) ->
          d.Fractal_diagnostic.origin <> Fractal_diagnostic.Implementation)
        ds);
  check "the fractal coordinate is USED: findings land at several levels" (fun () ->
      let levels =
        List.sort_uniq compare
          (List.map (fun (d : Fractal_diagnostic.t) -> Fractal_diagnostic.level_name d.Fractal_diagnostic.level) ds)
      in
      List.length levels >= 4);
  check "control-plane findings file at LX, never at a corpus level (R9)" (fun () ->
      let lx f =
        let d = Wiki_diagnostics.diagnose f in
        d.Fractal_diagnostic.level = Fractal_diagnostic.LX_control
      in
      lx (Wiki_diagnostics.Ratchet_breach { gauge = "g"; previous = 0; current = 1 })
      && lx (Wiki_diagnostics.Stale_declaration { row = "HW.1.1.1" })
      && lx (Wiki_diagnostics.Unported_mirror { module_ = "m"; row = "HW.1.1.1" }));
  check "corpus findings file at a corpus level, never LX" (fun () ->
      let corpus f =
        let d = Wiki_diagnostics.diagnose f in
        d.Fractal_diagnostic.level <> Fractal_diagnostic.LX_control
      in
      corpus (Wiki_diagnostics.Dead_link { source = "a"; target = "b" })
      && corpus (Wiki_diagnostics.Schema_gap { page = "a"; field = "ktype" })
      && corpus (Wiki_diagnostics.Drifted_render { page = "a" }));
  check "HW.3.7.4/2.6.3/defects: the cluster's three findings land at their levels"
    (fun () ->
      let level f = (Wiki_diagnostics.diagnose f).Fractal_diagnostic.level in
      level (Wiki_diagnostics.Term_gap { page = "p"; term = "quirk" })
      = Fractal_diagnostic.L2_capability
      && level (Wiki_diagnostics.Index_violation { page = "p"; target = "t" })
         = Fractal_diagnostic.L3_contract
      && level (Wiki_diagnostics.Corpus_defect { detail = "duplicate slug: x" })
         = Fractal_diagnostic.L0_product);
  check "HW.3.7.2: an ambiguous reference is an L2 link-capability finding, distinct from a dead link"
    (fun () ->
      let d =
        Wiki_diagnostics.diagnose
          (Wiki_diagnostics.Ambiguous_ref { source = "user"; target = "the-gate" })
      in
      d.Fractal_diagnostic.level = Fractal_diagnostic.L2_capability
      && d.Fractal_diagnostic.origin <> Fractal_diagnostic.Implementation
      && d.Fractal_diagnostic.impact = Fractal_diagnostic.Blocks_credit
      && d.Fractal_diagnostic.subject = "user");
  check "every diagnostic names a cause AND a fix (never a bare complaint)" (fun () ->
      List.for_all
        (fun (d : Fractal_diagnostic.t) ->
          String.length d.Fractal_diagnostic.cause > 10 && String.length d.Fractal_diagnostic.fix > 10)
        ds);
  check "every diagnostic names its subject (the actionable artifact)" (fun () ->
      List.for_all (fun (d : Fractal_diagnostic.t) -> d.Fractal_diagnostic.subject <> "") ds);
  check "the render leads with the fractal coordinate" (fun () ->
      List.for_all
        (fun (d : Fractal_diagnostic.t) ->
          let r = Fractal_diagnostic.render d in
          String.length r > 2 && r.[0] = '[')
        ds)

let () =
  check "OTEL BRIDGE: level, origin and impact become attributes" (fun () ->
      let d = Wiki_diagnostics.diagnose (Wiki_diagnostics.Dead_link { source = "a"; target = "b" }) in
      let r = Wiki_diagnostics.to_otel ~ts:"t" d in
      List.mem_assoc "fractal.level" r.Wiki_otel.attrs
      && List.mem_assoc "fractal.origin" r.Wiki_otel.attrs
      && List.mem_assoc "fractal.impact" r.Wiki_otel.attrs
      && List.assoc "fractal.origin" r.Wiki_otel.attrs <> "implementation");
  check "OTEL BRIDGE is one-directional: rendering is deterministic" (fun () ->
      let d = Wiki_diagnostics.diagnose (Wiki_diagnostics.Orphan { page = "p" }) in
      Wiki_otel.render (Wiki_diagnostics.to_otel ~ts:"t" d)
      = Wiki_otel.render (Wiki_diagnostics.to_otel ~ts:"t" d));
  check "blocking findings log at WARN; informational ones do not" (fun () ->
      let sev f = (Wiki_diagnostics.to_otel ~ts:"t" (Wiki_diagnostics.diagnose f)).Wiki_otel.severity in
      sev (Wiki_diagnostics.Ratchet_breach { gauge = "g"; previous = 0; current = 1 })
      = Wiki_otel.Warn
      && sev (Wiki_diagnostics.Orphan { page = "p" }) = Wiki_otel.Info)

let () =
  Printf.printf "wiki_diagnostics: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_diagnostics" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
