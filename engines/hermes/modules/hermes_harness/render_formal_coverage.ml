(* Render the formal-coverage atlas page. Derived, never asserted: every
   number is recomputed from the live registry, census, and intent — and
   the render REFUSES if any completeness law has a gap or the declared
   intent drifts. An atlas page of a broken registry is worse than none. *)

let () =
  let out_dir = if Array.length Sys.argv > 1 then Sys.argv.(1) else "docs/hermes/atlas" in
  let refuse label = function
    | [] -> ()
    | gaps ->
        prerr_endline (label ^ "; refusing to render:");
        List.iter (fun g -> prerr_endline ("  " ^ g)) gaps;
        exit 1
  in
  refuse "component gaps" (Formal_coverage.component_gaps ());
  refuse "aspect gaps" (Formal_coverage.aspect_gaps ());
  refuse "scenario gaps" (Formal_coverage.scenario_gaps ());
  refuse "interaction gaps" (Formal_coverage.interaction_gaps ());
  refuse "missing cited files" (Formal_coverage.missing_files ());
  refuse "intent drift" (Formal_coverage.reconcile ());
  let buffer = Buffer.create 16384 in
  let line text = Buffer.add_string buffer (text ^ "\n") in
  line "# Formal coverage atlas (derived — regenerate via render_formal_coverage)";
  line "";
  line "Every fractal component's formal backing, the four aspect dimensions,";
  line "the atlas-element usage census, and the declared coverage intent. All";
  line "completeness laws held and the intent reconciled clean at render time;";
  line "this page refuses to exist otherwise.";
  line "";
  line "## Component grid";
  line "";
  line "| Component | Grade | Artifacts | Structural | Static | Behavioral | Dynamic |";
  line "|---|---|---|---|---|---|---|";
  List.iter
    (fun (e : Formal_coverage.entry) ->
      let claim aspect =
        match List.assoc_opt aspect e.Formal_coverage.aspect_coverage with
        | Some (Formal_coverage.Checked _) -> "checked"
        | Some (Formal_coverage.Not_applicable _) -> "n/a (reasoned)"
        | None -> "GAP"
      in
      let grade_name =
        match Formal_coverage.grade e with
        | 5 -> "machine-checked" | 4 -> "solver-proved" | 3 -> "differential"
        | 2 -> "property" | 1 -> "contracted" | _ -> "declared"
      in
      line
        (Printf.sprintf "| %s | %s | %d | %s | %s | %s | %s |"
           e.Formal_coverage.component grade_name
           (List.length e.Formal_coverage.artifacts)
           (claim Formal_coverage.Structural) (claim Formal_coverage.Static)
           (claim Formal_coverage.Behavioral) (claim Formal_coverage.Dynamic)))
    Formal_coverage.entries;
  line "";
  line "## Citations";
  line "";
  List.iter
    (fun (e : Formal_coverage.entry) ->
      line ("### " ^ e.Formal_coverage.component);
      List.iter
        (fun a ->
          let kind =
            match a with
            | Formal_coverage.Machine_checked _ -> "machine-checked"
            | Formal_coverage.Solver_proved _ -> "solver-proved"
            | Formal_coverage.Differentially_tested _ -> "differential"
            | Formal_coverage.Property_tested _ -> "property"
            | Formal_coverage.Contracted _ -> "contracted"
            | Formal_coverage.Declared _ -> "DECLARED GAP"
          in
          line ("- **" ^ kind ^ "**: " ^ Formal_coverage.cite a))
        e.Formal_coverage.artifacts;
      line "")
    Formal_coverage.entries;
  line "## Census — instances of each atlas element in use";
  line "";
  line "| Element | Count |";
  line "|---|---|";
  List.iter
    (fun (k, v) -> line (Printf.sprintf "| %s | %d |" k v))
    (Formal_coverage.census ());
  line "";
  line "### Port-definition usage (instantiations per port type)";
  line "";
  List.iter
    (fun (k, v) -> line (Printf.sprintf "- `%s`: %d" k v))
    (Formal_coverage.port_def_usage ());
  line "";
  line "### Type-definition usage (references per type)";
  line "";
  List.iter
    (fun (k, v) -> line (Printf.sprintf "- `%s`: %d" k v))
    (Formal_coverage.type_def_usage ());
  line "";
  line "## Declared intent (reconciled clean at render time)";
  line "";
  List.iter
    (fun (r : Formal_coverage.requirement) ->
      line
        (Printf.sprintf "- **%s** >= rank %d — %s" r.Formal_coverage.subject
           r.Formal_coverage.minimum r.Formal_coverage.reason))
    Formal_coverage.intent;
  line "";
  line "## Fractal level coverage";
  line "";
  List.iter
    (fun (level, total, covered) ->
      line (Printf.sprintf "- %s: %d/%d components covered at property rank or better" level covered total))
    (Formal_coverage.level_coverage ());
  line "";
  line "## Zenoh seams (identified; boundary-as-law applies)";
  line "";
  line "Live topics:";
  List.iter (fun topic -> line ("- `" ^ topic ^ "`")) Formal_coverage.zenoh_live_topics;
  line "";
  List.iter
    (fun (seam, rationale) -> line ("- **" ^ seam ^ "** — " ^ rationale))
    Formal_coverage.zenoh_seams;
  line "";
  line "Application analysis (high dataflow, hierarchical control):";
  line "`docs/hermes/architecture-applications.md`.";
  (try Unix.mkdir out_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let path = Filename.concat out_dir "formal-coverage.md" in
  let channel = open_out_bin path in
  output_string channel (Buffer.contents buffer);
  close_out channel;
  print_endline ("wrote " ^ path)
