let () =
  let capabilities = Capability_catalog.all in
  (* Every L2 slice hangs off a real L1 public feature family. *)
  assert
    (List.for_all
       (fun (capability : Capability_catalog.capability) ->
         List.exists
           (fun (feature : Feature_catalog.feature) -> feature.id = capability.family_id)
           Feature_catalog.all)
       capabilities);
  (* Every family carries at least one capability slice. *)
  assert
    (List.for_all
       (fun (feature : Feature_catalog.feature) ->
         Capability_catalog.for_family feature.id <> [])
       Feature_catalog.all);
  (* Node ids and semantic keys are unique. *)
  let unique values = List.length (List.sort_uniq compare values) = List.length values in
  assert (unique (List.map Capability_catalog.node_id capabilities));
  assert (unique (List.map Capability_catalog.semantic_key capabilities));
  (* Each slice is source-anchored and doc-anchored. *)
  assert
    (List.for_all
       (fun (capability : Capability_catalog.capability) ->
         capability.source_anchors <> [] && capability.doc_anchors <> []
         && String.trim capability.label <> "")
       capabilities);
  (* The dependency table only names real slices, on both sides of every edge. *)
  assert
    (List.for_all
       (fun (key, deps) ->
         Capability_catalog.find key <> None
         && List.for_all (fun dep -> Capability_catalog.find dep <> None) deps
         && not (List.mem key deps))
       Capability_catalog.dependencies);
  (* The graph is acyclic and orders every slice after its dependencies. *)
  (match Capability_catalog.topological_order () with
  | Error message -> failwith message
  | Ok ordered ->
      assert (List.length ordered = List.length capabilities);
      let rec check placed = function
        | [] -> ()
        | (capability : Capability_catalog.capability) :: rest ->
            List.iter
              (fun dependency ->
                if not (List.mem dependency placed) then
                  failwith
                    (Capability_catalog.semantic_key capability
                     ^ ": dependency ordered too late: " ^ dependency))
              (Capability_catalog.depends_on capability);
            check (Capability_catalog.semantic_key capability :: placed) rest
      in
      check [] ordered);
  (* Anchors are discovery facts: every path must exist in the frozen snapshot. *)
  let reference_root = Bootstrap.reference_root "." in
  if Sys.file_exists reference_root then
    List.iter
      (fun (capability : Capability_catalog.capability) ->
        List.iter
          (fun anchor ->
            let path = Filename.concat reference_root anchor in
            if not (Sys.file_exists path) then
              failwith (Capability_catalog.node_id capability ^ ": missing anchor " ^ anchor))
          (Capability_catalog.anchors capability))
      capabilities
  else failwith ("frozen reference root is absent: " ^ reference_root);
  print_endline (Printf.sprintf "capabilities: %d" (List.length capabilities))

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_capability_catalog" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_capability_catalog ]);
  exit (Suite_telemetry.exit_code self)
