let ontology_path = "docs/hermes/wiki/module-intent-ontology.md"
let atlas_path = "docs/hermes/wiki/module-intent-fractal-atlas.md"
let algebra_path = "docs/hermes/wiki/module-intent-fractal-algebra.md"

let frontmatter ~id ~title ~topics ~links =
  Printf.sprintf
    "---\nid: hermes-%s\ntitle: %s\naliases: [%s]\nstatus: published\ntype: reference\nktype: source\nmaturity: evergreen\ndomain: hermes\ntopics: [%s]\nlinks: [%s]\ncreated: 2026-08-13\n---\n\n"
    id title id (String.concat ", " topics) (String.concat ", " links)

let notice =
  "> GENERATED from `Module_intent.all`, `Stanza.all`, and `Run_fpp_authority`. Do not hand-edit; regenerate with `ops module-intent --write-docs`.\n\n"

let escape value =
  value |> String.split_on_char '|' |> String.concat "\\|"
  |> String.split_on_char '\n' |> String.concat " "

let surface_name (surface, applicability) =
  let name = Ops_capability.string_of_surface surface in
  match applicability with
  | Ops_capability.Applicable -> name ^ ":applicable"
  | Ops_capability.Not_applicable reason -> name ^ ":N/A(" ^ reason ^ ")"

let fpp_text = function
  | Module_intent.Fpp_not_applicable reason -> "N/A: " ^ reason
  | Module_intent.Fpp_components mappings ->
      mappings
      |> List.map (fun (owner, components) ->
             Fpp_window_authority.owner_name owner ^ "/" ^ String.concat "," components)
      |> String.concat "; "

let mediation_text = function
  | Module_intent.Direct_read -> "direct-read"
  | Module_intent.Run_swarm_bridge activities ->
      "Run_swarm_bridge(" ^ String.concat "," activities ^ ")"
  | Module_intent.Unavailable_until_bridge_activity reason ->
      "Unavailable_observed: " ^ reason

let render_ontology () =
  let buffer = Buffer.create 32768 in
  let add format = Printf.ksprintf (Buffer.add_string buffer) format in
  Buffer.add_string buffer
    (frontmatter ~id:"module-intent-ontology"
       ~title:"Declarative module intent ontology"
       ~topics:[ "declarative-intent"; "module-interface"; "fpp"; "ops" ]
       ~links:[ "hermes-module-intent-fractal-atlas";
                "hermes-module-intent-fractal-algebra" ]);
  Buffer.add_string buffer "# Declarative module intent ontology\n\n";
  Buffer.add_string buffer notice;
  add "Authority digest: `%s`  \nFPP portfolio digest: `%s`  \nDenominator: **%d module interfaces / %d Dune libraries / %d FPP owners**.\n\n"
    Module_intent.source_digest Run_fpp_authority.source_digest
    (List.length Module_intent.all) (List.length Stanza.all)
    (List.length Run_fpp_authority.all);
  Buffer.add_string buffer
    "| Interface | Dune owner | Purpose | Plane | Coordinate | Effect | Config intent | Capabilities | FPP | Mediation |\n|---|---|---|---|---|---|---|---|---|---|\n";
  List.iter
    (fun (item : Module_intent.t) ->
      add "| `%s` | `%s` | %s | %s | %s/%s | %s | %s | %s | %s | %s |\n"
        item.stable_id item.owner_directory (escape item.purpose)
        (Ops_capability.string_of_plane item.plane)
        (Ops_capability.string_of_level item.coordinate.level)
        (Ops_capability.string_of_phase item.coordinate.phase)
        (Module_intent.string_of_effect_posture item.effect_posture)
        (escape (if item.configuration_ids = [] then "none" else String.concat ", " item.configuration_ids))
        (escape (if item.capability_ids = [] then "none" else String.concat ", " item.capability_ids))
        (escape (fpp_text item.fpp)) (escape (mediation_text item.mediation)))
    Module_intent.all;
  Buffer.contents buffer

let render_atlas () =
  let buffer = Buffer.create 65536 in
  let add format = Printf.ksprintf (Buffer.add_string buffer) format in
  Buffer.add_string buffer
    (frontmatter ~id:"module-intent-fractal-atlas"
       ~title:"Declarative module intent fractal functional atlas"
       ~topics:[ "declarative-intent"; "fractal-functional-atlas"; "fpp"; "ops" ]
       ~links:[ "hermes-module-intent-ontology";
                "hermes-module-intent-fractal-algebra" ]);
  Buffer.add_string buffer "# Declarative module intent fractal functional atlas\n\n";
  Buffer.add_string buffer notice;
  Buffer.add_string buffer
    "The same path recurs at every scale: Dune witness → semantic module intent → FPP structural mapping or explicit exclusion → four-surface projection → bridge mediation or disclosed unavailability.\n\n";
  Buffer.add_string buffer
    "| Module interface | Library witness | Surfaces | FPP mapping | Execution boundary |\n|---|---|---|---|---|\n";
  List.iter
    (fun (item : Module_intent.t) ->
      let libraries = match item.libraries with
        | [] -> [ "(executable-only Dune owner)" ]
        | values -> List.map Stanza.name values
      in
      List.iter
        (fun library ->
          add "| `%s` | `%s` | %s | %s | %s |\n"
            item.stable_id library
            (escape (String.concat "; " (List.map surface_name item.surfaces)))
            (escape (fpp_text item.fpp))
            (escape (mediation_text item.mediation)))
        libraries)
    Module_intent.all;
  Buffer.contents buffer

let render_algebra () =
  let buffer = Buffer.create 16384 in
  Buffer.add_string buffer
    (frontmatter ~id:"module-intent-fractal-algebra"
       ~title:"Declarative module intent fractal functional algebra"
       ~topics:[ "declarative-intent"; "fractal-functional-algebra"; "fpp"; "ops" ]
       ~links:[ "hermes-module-intent-ontology";
                "hermes-module-intent-fractal-atlas" ]);
  Buffer.add_string buffer "# Declarative module intent fractal functional algebra\n\n";
  Buffer.add_string buffer notice;
  Buffer.add_string buffer
    "## Carriers\n\n- Structural identity: abstract `Stanza.t`.\n- Semantic ownership: private `Module_intent.t`.\n- Effects: `Pure | Read_only | Guarded_write | External_effect`.\n- Configuration references: keys resolving to `Ops_config.elements`.\n- Capability references: IDs resolving to `Ops_capability.all`.\n- FPP applicability: `Fpp_components | Fpp_not_applicable reason`.\n- Mediation: `Direct_read | Run_swarm_bridge activities | Unavailable_until_bridge_activity reason`.\n\n## Laws\n\n| Law | Refusal |\n|---|---|\n| Total ownership | The union of interface libraries differs from `Stanza.all`. |\n| Unique ownership | One `Stanza.t` occurs in two interfaces. |\n| Live-directory equality | Typed interface directories differ from live Dune files. |\n| Configuration closure | A module references an undeclared or duplicate configuration key. |\n| Capability closure | A module references an undeclared or duplicate capability ID. |\n| Four-surface totality | A surface is omitted or an exclusion is vacuous. |\n| FPP non-vacuity | Every module excludes FPP or a mapped component is absent. |\n| Effect mediation | A guarded or external effect is marked direct-read. |\n| Five-owner identity | Harness, Wiki, Ops monitor, Completion, or Operations is absent, duplicated, reordered, or renamed. |\n| Digest binding | Swarm typed intent omits the module or FPP authority digest. |\n| Authority separation | FPP may block admission but never execute or grant parity. |\n| Empty denominator | Zero interfaces, libraries, models, actions, or selected cases cannot be green. |\n";
  Buffer.contents buffer

let surfaces () =
  [ (ontology_path, render_ontology ());
    (atlas_path, render_atlas ());
    (algebra_path, render_algebra ()) ]

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr channel)
      (fun () -> Some (really_input_string channel (in_channel_length channel)))
  with Sys_error _ -> None

let drifted () =
  surfaces ()
  |> List.filter_map (fun (path, expected) ->
         match read_file path with
         | Some observed when String.equal observed expected -> None
         | Some _ -> Some (path ^ ": stale")
         | None -> Some (path ^ ": missing"))

let write_file path body =
  let temporary = path ^ ".tmp" in
  try
    let channel = open_out_bin temporary in
    Fun.protect ~finally:(fun () -> close_out_noerr channel)
      (fun () -> output_string channel body);
    Sys.rename temporary path;
    Ok ()
  with Sys_error message -> Error (path ^ ": " ^ message)

let write () =
  let rec loop = function
    | [] -> Ok "wrote module-intent ontology, fractal atlas, and fractal algebra"
    | (path, body) :: rest ->
        begin match write_file path body with Ok () -> loop rest | Error _ as error -> error end
  in loop (surfaces ())

let check () =
  let findings = drifted () in
  let output =
    String.concat "" (List.map (fun item -> "DOC DRIFT: " ^ item ^ "\n") findings)
    ^ Printf.sprintf "module intent docs: %d surfaces, %d drift finding(s)\n"
        (List.length (surfaces ())) (List.length findings)
  in
  (output, if findings = [] then 0 else 1)
