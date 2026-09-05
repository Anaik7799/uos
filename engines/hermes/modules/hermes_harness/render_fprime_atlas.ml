(* Render the F Prime atlas artifacts: the harness topology as FPP source
   and as the F Prime JSON dictionary. Fail-closed: refuses if the model is
   invalid or the differential law has gaps — an atlas of a wrong model is
   worse than no atlas. *)

let () =
  let out_dir = if Array.length Sys.argv > 1 then Sys.argv.(1) else "docs/hermes/atlas" in
  (match Harness_topology.validate () with
  | [] -> ()
  | diagnostics ->
      prerr_endline "model invalid; refusing to render:";
      List.iter (fun d -> prerr_endline (Fractal_diagnostic.render d)) diagnostics;
      exit 1);
  (match Harness_topology.ontology_gaps () with
  | [] -> ()
  | gaps ->
      prerr_endline "topology <-> ontology gaps; refusing to render:";
      List.iter (fun g -> prerr_endline ("  " ^ g)) gaps;
      exit 1);
  (try Unix.mkdir out_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let write path content =
    let channel = open_out_bin path in
    output_string channel content;
    close_out channel;
    print_endline ("wrote " ^ path)
  in
  write (Filename.concat out_dir "hermes-harness.fpp") (Harness_topology.to_fpp ());
  match Harness_topology.dictionary () with
  | Error message -> prerr_endline message; exit 1
  | Ok json ->
      write
        (Filename.concat out_dir "hermes-harness-dictionary.json")
        (Yojson.Safe.pretty_to_string json ^ "\n")
