let () =
  let nodes = Fractal_catalog.nodes ~snapshot_digest:"S" in
  let expected =
    1 + List.length Feature_catalog.all + List.length Capability_catalog.all
  in
  assert (List.length nodes = expected);
  assert (List.exists (fun (node : Evidence_store.fractal_node) -> node.id = "hermes" && node.level = 0) nodes);
  assert (List.length (List.filter (fun (node : Evidence_store.fractal_node) -> node.level = 1) nodes)
          = List.length Feature_catalog.all);
  assert (List.length (List.filter (fun (node : Evidence_store.fractal_node) -> node.level = 2) nodes)
          = List.length Capability_catalog.all);
  (* L1 hangs off the product root; L2 hangs off an L1 node that is present. *)
  assert (List.for_all (fun (node : Evidence_store.fractal_node) ->
    node.level <> 1 || node.parent_id = Some "hermes") nodes);
  let ids = List.map (fun (node : Evidence_store.fractal_node) -> node.id) nodes in
  assert (List.for_all (fun (node : Evidence_store.fractal_node) ->
    node.level <> 2
    || (match node.parent_id with Some parent -> List.mem parent ids | None -> false)) nodes);
  (* Node ids and semantic keys stay unique across every level. *)
  assert (List.length (List.sort_uniq compare ids) = List.length ids);
  let keys = List.map (fun (node : Evidence_store.fractal_node) -> node.semantic_key) nodes in
  assert (List.length (List.sort_uniq compare keys) = List.length keys);
  (* Parents precede children so a single transaction can insert the whole tree. *)
  let rec ordered seen = function
    | [] -> true
    | (node : Evidence_store.fractal_node) :: rest ->
        (match node.parent_id with
        | None -> ordered (node.id :: seen) rest
        | Some parent -> List.mem parent seen && ordered (node.id :: seen) rest)
  in
  assert (ordered [] nodes)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_fractal_catalog" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_fractal_catalog ]);
  exit (Suite_telemetry.exit_code self)
