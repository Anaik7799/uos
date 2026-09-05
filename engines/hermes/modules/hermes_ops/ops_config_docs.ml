let ontology_path = "docs/hermes/wiki/declarative-intent-config-ontology.md"
let atlas_path = "docs/hermes/wiki/declarative-intent-config-fractal-atlas.md"
let algebra_path = "docs/hermes/wiki/declarative-intent-config-fractal-algebra.md"

let page_ids =
  [ "declarative-intent-config-ontology";
    "declarative-intent-config-fractal-atlas";
    "declarative-intent-config-fractal-algebra" ]

let frontmatter ~id ~title ~aliases ~topics ~links =
  Printf.sprintf
    "---\nid: hermes-%s\ntitle: %s\naliases: [%s]\nstatus: published\ntype: reference\nktype: source\nmaturity: evergreen\ndomain: hermes\ntopics: [%s]\nlinks: [%s]\ncreated: 2026-08-13\n---\n\n"
    id title (String.concat ", " aliases) (String.concat ", " topics)
    (String.concat ", " links)

let generated_notice =
  "> GENERATED from typed OCaml rooted at `Ops_config.elements`. Do not hand-edit; regenerate with `ops config --write-docs`.\n\n"

let escape_cell value =
  value
  |> String.split_on_char '|'
  |> String.concat "\\|"
  |> String.split_on_char '\n'
  |> String.concat " "

let layer_name = function
  | None -> "cross-layer"
  | Some layer -> Ops_config.layer_name layer

let render_ontology () =
  let buffer = Buffer.create 16384 in
  let add format = Printf.ksprintf (Buffer.add_string buffer) format in
  Buffer.add_string buffer
    (frontmatter ~id:"declarative-intent-config-ontology"
       ~title:"Declarative intent configuration ontology"
       ~aliases:[ "configuration-ontology"; "r23-ontology" ]
       ~topics:[ "declarative-intent"; "configuration"; "ontology"; "run-swarm-bridge" ]
       ~links:[ "hermes-declarative-intent-config-fractal-atlas";
                "hermes-declarative-intent-config-fractal-algebra";
                "hermes-run-swarm-bridge-km-map" ]);
  Buffer.add_string buffer "# Declarative intent configuration ontology\n\n";
  Buffer.add_string buffer generated_notice;
  add "Authority digest: `%s`\n\n"
    (Ops_config_algebra.declaration_digest Ops_config.elements);
  Buffer.add_string buffer
    "Configuration declaration and operational execution intent are distinct types. The validated, value-free configuration digest is their only binding. `Run_swarm_bridge` remains the sole execution authority; the Swarm engine schedules admitted work but grants no completion credit.\n\n";
  Buffer.add_string buffer
    "| Node | Kind | Layer | Authority | Function |\n|---|---|---|---|---|\n";
  List.iter
    (fun (node : Ops_config_ontology.node) ->
      add "| `%s` | %s | %s | %s | %s |\n"
        (escape_cell node.id)
        (Ops_config_ontology.kind_name node.kind)
        (layer_name node.layer)
        (Ops_config_ontology.authority_name node.authority)
        (escape_cell node.purpose))
    Ops_config_ontology.all;
  Buffer.contents buffer

let render_atlas () =
  let buffer = Buffer.create 24576 in
  let add format = Printf.ksprintf (Buffer.add_string buffer) format in
  Buffer.add_string buffer
    (frontmatter ~id:"declarative-intent-config-fractal-atlas"
       ~title:"Declarative intent configuration fractal functional atlas"
       ~aliases:[ "configuration-fractal-atlas"; "r23-atlas" ]
       ~topics:[ "declarative-intent"; "configuration"; "fractal-functional-atlas";
                 "run-swarm-bridge" ]
       ~links:[ "hermes-declarative-intent-config-ontology";
                "hermes-declarative-intent-config-fractal-algebra";
                "hermes-run-swarm-bridge-km-map" ]);
  Buffer.add_string buffer
    "# Declarative intent configuration fractal functional atlas\n\n";
  Buffer.add_string buffer generated_notice;
  Buffer.add_string buffer
    "Every configuration element repeats the same bounded functional path. No element reaches scheduling or evidence without validation, exact digest binding, assurance, and the bridge.\n\n";
  Buffer.add_string buffer "| Source | Relation | Target |\n|---|---|---|\n";
  List.iter
    (fun (edge : Ops_config_atlas.edge) ->
      add "| `%s` | %s | `%s` |\n" (escape_cell edge.source)
        (Ops_config_atlas.kind_name edge.kind) (escape_cell edge.target))
    Ops_config_atlas.edges;
  Buffer.add_string buffer "\n## Per-element receipt paths\n\n";
  List.iter
    (fun (element : Ops_config.element) ->
      let paths =
        Ops_config_atlas.paths_to_receipt
          (Ops_config_ontology.element_id element.key)
      in
      List.iter
        (fun path -> add "- `%s`: `%s`\n" element.key (String.concat " -> " path))
        paths)
    Ops_config.elements;
  Buffer.contents buffer

let render_algebra () =
  let buffer = Buffer.create 12288 in
  let add format = Printf.ksprintf (Buffer.add_string buffer) format in
  Buffer.add_string buffer
    (frontmatter ~id:"declarative-intent-config-fractal-algebra"
       ~title:"Declarative intent configuration fractal functional algebra"
       ~aliases:[ "configuration-fractal-algebra"; "r23-algebra" ]
       ~topics:[ "declarative-intent"; "configuration"; "fractal-functional-algebra";
                 "run-swarm-bridge" ]
       ~links:[ "hermes-declarative-intent-config-ontology";
                "hermes-declarative-intent-config-fractal-atlas";
                "hermes-run-swarm-bridge-km-map" ]);
  Buffer.add_string buffer
    "# Declarative intent configuration fractal functional algebra\n\n";
  Buffer.add_string buffer generated_notice;
  add "Declaration-set digest: `%s`\n\n"
    (Ops_config_algebra.declaration_digest Ops_config.elements);
  Buffer.add_string buffer
    "## Carriers\n\n- Resolution: `Supplied | Defaulted | Optional_unavailable | Required_blocked`.\n- Completion: `Unmapped | Verified | Partial | Blocked`.\n- Join order: `Unmapped < Verified < Partial < Blocked`.\n\n";
  Buffer.add_string buffer
    "| Presence | Necessity | Resolution | Completion effect |\n|---|---|---|---|\n| present | any | `Supplied` | `Verified` |\n| absent | `Override` | `Defaulted` | `Verified` |\n| absent | `Optional_flag` | `Optional_unavailable` | `Partial` |\n| absent | `Required` | `Required_blocked` | `Blocked` |\n\n";
  Buffer.add_string buffer
    "## Executable laws\n\n| Law | Mechanical meaning |\n|---|---|\n| Closure | Every result remains in the closed completion carrier. |\n| Associativity | Layer and whole-system grouping cannot change the verdict. |\n| Commutativity | Declaration traversal order cannot change the verdict. |\n| Idempotence | Re-observing one declaration cannot inflate credit. |\n| Empty denominator | An empty roll-up is `Unmapped`, never `Verified`. |\n| Digest determinism | Sorting declarations by key makes identity permutation-invariant. |\n| Value non-authority | The digest includes declaration metadata, never supplied secret values. |\n| Exact binding | Execution intent binds only when its context configuration digest is byte-equal. |\n| Optional honesty | An absent optional capability is disclosed `Partial`, never green. |\n| Required failure | An absent required element is `Blocked`. |\n| Bridge uniqueness | Assurance is the bridge's sole predecessor; the bridge is the scheduler's sole predecessor. |\n";
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
         | Some observed when String.equal expected observed -> None
         | Some _ -> Some (path ^ ": stale")
         | None -> Some (path ^ ": missing"))

let cross_reference_targets =
  [ "docs/hermes/declarative-configuration.md";
    "docs/hermes/HANDOVER.md";
    "docs/hermes/system-documentation.md";
    "docs/hermes/wiki/20260812-2152-run-swarm-bridge-km-map.md";
    "modules/hermes_wiki/pages/wiki/features/unified-functional-atlas.md";
    "modules/hermes_wiki/pages/wiki/features/unified-functional-algebra.md" ]

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop offset =
    offset + needle_length <= haystack_length
    && (String.sub haystack offset needle_length = needle || loop (offset + 1))
  in
  needle_length > 0 && loop 0

let cross_reference_drift () =
  cross_reference_targets
  |> List.concat_map (fun path ->
         match read_file path with
         | None -> [ path ^ ": missing" ]
         | Some body ->
             page_ids
             |> List.filter_map (fun page_id ->
                    if contains body page_id then None
                    else Some (path ^ ": missing " ^ page_id)))

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
    | [] -> Ok "wrote declarative configuration ontology, atlas, and algebra"
    | (path, body) :: rest ->
        begin match write_file path body with
        | Ok () -> loop rest
        | Error _ as error -> error
        end
  in
  loop (surfaces ())

let check () =
  let surface_drift = drifted () in
  let reference_drift = cross_reference_drift () in
  let findings = surface_drift @ reference_drift in
  let buffer = Buffer.create 2048 in
  List.iter (fun finding -> Buffer.add_string buffer ("DOC DRIFT: " ^ finding ^ "\n")) findings;
  Buffer.add_string buffer
    (Printf.sprintf "config docs: %d generated surfaces, %d drift finding(s)\n"
       (List.length (surfaces ())) (List.length findings));
  (Buffer.contents buffer, if findings = [] then 0 else 1)
