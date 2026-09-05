(* Everything the ontologies declare, rendered deterministically.

   This exists to be DIFFED. An ontology is data, and the risk with data
   is that it changes without anyone noticing — a hazard reworded, an
   origin flipped from Environment to Implementation, a channel renamed.
   None of those breaks a test that only checks structure, and all of
   them change what the system claims. The expect test makes each one a
   reviewable diff instead. *)
let () =
  print_string (Vision_atlas.render ());
  print_string (Vision_gstreamer.render ());
  print_string (Vision_vlc.render ());
  print_string (Vision_obs.render ());
  print_string (Vision_jmeter.render ());
  print_string (Vision_libav_ontology.render ());
  print_string (Vision_browser_api.render ());
  print_string (Vision_fpp.render ());
  print_string (Vision_safety.render ());
  (* a fixed run id, so the ids are stable and a diff is readable *)
  let obs =
    List.map
      (fun s ->
        { Vision_controller.stage = s;
          verdict = Vision_controller.Unknown "not run";
          level = Vision_ontology.level s;
          origin = Vision_ontology.origin s;
          detail = ""; elapsed_ms = 0.0 })
      Vision_ontology.stages
  in
  print_endline "";
  print_endline (Vision_otel.to_otlp ~run_id:"expect-fixed-run" obs)
