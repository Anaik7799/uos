let () =
  let reference_root = Bootstrap.reference_root "." in
  if not (Sys.file_exists reference_root) then
    failwith ("frozen reference root is absent: " ^ reference_root);
  match
    Reference_artifacts.build ~snapshot_digest:"S" ~reference_root ~git_revision:"R"
  with
  | Error message -> failwith message
  | Ok (artifacts, links) ->
      (* Every L2 node gets at least one source artifact and one doc artifact. *)
      List.iter
        (fun (capability : Capability_catalog.capability) ->
          let node_id = Capability_catalog.node_id capability in
          let owned =
            List.filter (fun (link : Reference_artifacts.link) -> link.node_id = node_id) links
          in
          let has role =
            List.exists (fun (link : Reference_artifacts.link) -> link.role = role) owned
          in
          if not (has Reference_artifacts.source_role) then
            failwith (node_id ^ ": no source artifact");
          if not (has Reference_artifacts.documentation_role) then
            failwith (node_id ^ ": no documentation artifact");
          if List.length owned
             <> List.length capability.source_anchors + List.length capability.doc_anchors
          then failwith (node_id ^ ": anchor count does not match link count"))
        Capability_catalog.all;
      (* Shared anchors resolve to one deduplicated, digest-pinned artifact. *)
      let ids = List.map (fun (artifact : Evidence_store.artifact) -> artifact.id) artifacts in
      assert (List.length (List.sort_uniq compare ids) = List.length ids);
      assert
        (List.for_all
           (fun (artifact : Evidence_store.artifact) ->
             String.length artifact.content_digest = 64
             && List.mem artifact.kind [ "source"; "documentation" ])
           artifacts);
      (* Every link points at a catalogued artifact. *)
      assert
        (List.for_all
           (fun (link : Reference_artifacts.link) -> List.mem link.artifact_id ids)
           links);
      Printf.printf "artifacts: %d\nlinks: %d\n" (List.length artifacts) (List.length links)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_reference_artifacts" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_reference_artifacts ]);
  exit (Suite_telemetry.exit_code self)
