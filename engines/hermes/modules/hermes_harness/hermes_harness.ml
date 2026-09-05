let usage () =
  prerr_endline "usage: hermes_harness <bootstrap|inventory|manifest|parity|features|report|verify> [--root PATH]";
  exit 64

let parse () =
  match Array.to_list Sys.argv with
  | _ :: command :: [] -> (command, ".")
  | _ :: command :: [ "--root"; root ] -> (command, root)
  | _ -> usage ()

let ensure_directory path =
  if Sys.file_exists path then Ok ()
  else
    try Unix.mkdir path 0o755; Ok ()
    with Unix.Unix_error (_, _, message) -> Error message

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> Ok (String.trim (input_line channel)))
  with End_of_file -> Error "cannot determine Git revision"
     | Unix.Unix_error (_, _, message) -> Error message

let materialize_plan ~state_directory ~snapshot_digest ~capabilities =
  let bridge = Filename.concat (Filename.dirname Sys.executable_name) "hermes_plan_bridge.exe" in
  let state_path = Filename.concat state_directory "hermes_sa_plan.sqlite3" in
  if not (Sys.file_exists bridge) then Error ("Sa-plan bridge is not built: " ^ bridge)
  else
    let arguments =
      [ "--path"; state_path; "--snapshot"; snapshot_digest ]
      @ List.concat_map
          (fun (feature : Feature_catalog.feature) -> [ "--feature"; feature.id ])
          Feature_catalog.all
      @ List.concat_map
          (fun (capability : Capability_catalog.capability) ->
            let key = Capability_catalog.semantic_key capability in
            match Capability_catalog.depends_on capability with
            | [] -> [ "--capability"; key ]
            | dependencies -> [ "--capability"; key ^ "=" ^ String.concat "," dependencies ])
          capabilities
    in
    let command = String.concat " " (List.map Filename.quote (bridge :: arguments)) in
    match Unix.system command with
    | Unix.WEXITED 0 -> Ok ()
    | Unix.WEXITED code -> Error (Printf.sprintf "Sa-plan bridge exited %d" code)
    | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
        Error (Printf.sprintf "Sa-plan bridge stopped by signal %d" signal)

let inventory root =
  match Inventory.scan ~root with
  | Error message -> Error message
  | Ok entries ->
      let digest = Inventory.snapshot_digest entries in
      Printf.printf "source_digest: %s\nentry_count: %d\n" digest (List.length entries);
      Ok (digest, List.length entries)

let bootstrap root =
  let checks = Bootstrap.run ~root in
  print_endline (Report.render_checks checks);
  checks

let manifest root =
  match Inventory.scan ~root with
  | Error message -> Error message
  | Ok entries ->
      print_endline (Report.render_manifest (Inventory.summarize entries));
      Ok ()

let report root =
  let path = Filename.concat root "state/hermes_harness.sqlite3" in
  if not (Sys.file_exists path) then print_endline "readiness: PENDING (no evidence database)"
  else
    match Evidence_store.open_db ~path with
    | Error message -> prerr_endline message; exit 1
    | Ok store ->
        (match Evidence_store.latest_readiness store with
        | Ok status -> print_endline (Report.render_readiness status)
        | Error message -> prerr_endline message; Evidence_store.close store; exit 1);
        Evidence_store.close store

let parity root =
  let path = Filename.concat root "state/hermes_harness.sqlite3" in
  match Inventory.scan ~root:(Bootstrap.reference_root root) with
  | Error message -> prerr_endline message; exit 1
  | Ok entries ->
      (match Evidence_store.open_db ~path with
      | Error message -> prerr_endline message; exit 1
      | Ok store ->
          let digest = Inventory.snapshot_digest entries in
          let result = Parity_tracker.load store ~snapshot_digest:digest in
          let feature_result = Parity_tracker.load_features store ~snapshot_digest:digest in
          Evidence_store.close store;
          match result, feature_result with
          | Error message, _ | _, Error message -> prerr_endline message; exit 1
          | Ok summary, Ok (_, feature_summary) ->
              print_endline (Report.render_parity summary);
              Printf.printf "feature_parity_total: %d\nfeature_parity_completed: %d\nfeature_parity_percent: %d\nfeature_parity_strict_percent: %d\n"
                feature_summary.total feature_summary.completed feature_summary.completion_percent feature_summary.strict_percent)

let features root =
  let path = Filename.concat root "state/hermes_harness.sqlite3" in
  match Inventory.scan ~root:(Bootstrap.reference_root root) with
  | Error message -> prerr_endline message; exit 1
  | Ok entries ->
      match Evidence_store.open_db ~path with
      | Error message -> prerr_endline message; exit 1
      | Ok store ->
          let result = Parity_tracker.load_features store ~snapshot_digest:(Inventory.snapshot_digest entries) in
          Evidence_store.close store;
          match result with Error message -> prerr_endline message; exit 1 | Ok (cells, _) -> print_endline (Report.render_features cells)

let verify root =
  let checks = bootstrap root in
  match inventory (Bootstrap.reference_root root) with
  | Error message -> prerr_endline message; exit 1
  | Ok (digest, entry_count) ->
      let state_directory = Filename.concat root "state" in
      (match ensure_directory state_directory with
      | Error message -> prerr_endline message; exit 1
      | Ok () ->
          let path = Filename.concat state_directory "hermes_harness.sqlite3" in
          match Evidence_store.open_db ~path with
          | Error message -> prerr_endline message; exit 1
          | Ok store ->
              let snapshot_result = Evidence_store.record_snapshot store ~digest ~entry_count in
              let cell_result =
                match Inventory.scan ~root:(Bootstrap.reference_root root) with
                | Error message -> Error message
                | Ok entries ->
                    Evidence_store.record_cells store ~snapshot_digest:digest
                      (Inventory.summarize entries)
              in
              let feature_result =
                Evidence_store.record_features store
                  (List.map
                     (fun (feature : Feature_catalog.feature) ->
                       { Evidence_store.snapshot_digest = digest; id = feature.id;
                         label = feature.label; source_domains = feature.source_domains })
                     Feature_catalog.all)
              in
              let fractal_result =
                Evidence_store.record_fractal_nodes store (Fractal_catalog.nodes ~snapshot_digest:digest)
              in
              (* Frozen artifacts are pinned to the reference revision, not the
                 harness revision, so replaying verify at a later harness commit
                 reproduces byte-identical rows. *)
              let artifact_result =
                let reference_root = Bootstrap.reference_root root in
                match git_revision reference_root with
                | Error _ as error -> error
                | Ok reference_revision ->
                    match
                      Reference_artifacts.build ~snapshot_digest:digest ~reference_root
                        ~git_revision:reference_revision
                    with
                    | Error _ as error -> error
                    | Ok (artifacts, links) ->
                        match Evidence_store.record_artifacts store artifacts with
                        | Error _ as error -> error
                        | Ok () ->
                            Evidence_store.link_node_artifacts store ~snapshot_digest:digest
                              (List.map
                                 (fun (link : Reference_artifacts.link) ->
                                   (link.node_id, link.artifact_id, link.role))
                                 links)
              in
              (* L3 contracts are declared per snapshot; their check receipts
                 are scoped to this harness revision and to the verifier that
                 produced them. An absent gospel binary yields an "unavailable"
                 receipt, which grants no credit. *)
              let contract_result =
                match git_revision root with
                | Error _ as error -> error
                | Ok harness_revision ->
                    let declarations =
                      List.map
                        (fun (contract : Contract_catalog.contract) ->
                          { Evidence_store.snapshot_digest = digest; id = contract.id;
                            node_id = Contract_catalog.node_id contract;
                            interface_path = contract.interface; law = contract.law })
                        Contract_catalog.all
                    in
                    (match Evidence_store.record_contracts store declarations with
                    | Error _ as error -> error
                    | Ok () ->
                        let receipts =
                          List.fold_left
                            (fun result (contract : Contract_catalog.contract) ->
                              match result with
                              | Error _ -> result
                              | Ok receipts ->
                                  match
                                    Gospel_check.check
                                      ~load_path:(Gospel_check.stub_directories root)
                                      ~interface:contract.interface ()
                                  with
                                  | Error _ as error -> error
                                  | Ok verdict ->
                                      match Inventory.sha256_file contract.interface with
                                      | Error _ as error -> error
                                      | Ok interface_digest ->
                                          Ok
                                            ({ Evidence_store.snapshot_digest = digest;
                                               contract_id = contract.id; harness_revision;
                                               verifier = Gospel_check.verifier verdict;
                                               interface_digest;
                                               verdict = Gospel_check.verdict_string verdict }
                                            :: receipts))
                            (Ok []) Contract_catalog.all
                        in
                        match receipts with
                        | Error _ as error -> error
                        | Ok receipts -> Evidence_store.record_contract_receipts store receipts)
              in
              let history_result =
                match git_revision root with
                | Error _ as error -> error
                | Ok git_revision ->
                    List.fold_left
                      (fun result (feature : Feature_catalog.feature) ->
                        match result with
                        | Error _ -> result
                        | Ok () ->
                            Evidence_store.record_feature_history store
                              { snapshot_digest = digest; feature_id = feature.id; git_revision;
                                phase = "cataloged"; status = "unmapped";
                                implementation_anchor = "modules/hermes_harness/feature_catalog.ml";
                                evidence_digest = digest })
                      (Ok ()) Feature_catalog.all
              in
              let plan_result =
                match Capability_catalog.topological_order () with
                | Error _ as error -> error
                | Ok capabilities ->
                    materialize_plan ~state_directory ~snapshot_digest:digest ~capabilities
              in
              let check_result =
                List.fold_left
                  (fun result (name, status) ->
                    match result with
                    | Error _ -> result
                    | Ok () -> Evidence_store.record_check store ~name ~status)
                  (Ok ()) checks
              in
              let result =
                match snapshot_result, cell_result, feature_result, fractal_result, artifact_result, contract_result, history_result, plan_result, check_result with
                | Error message, _, _, _, _, _, _, _, _ | _, Error message, _, _, _, _, _, _, _
                | _, _, Error message, _, _, _, _, _, _ | _, _, _, Error message, _, _, _, _, _
                | _, _, _, _, Error message, _, _, _, _ | _, _, _, _, _, Error message, _, _, _
                | _, _, _, _, _, _, Error message, _, _
                | _, _, _, _, _, _, _, Error message, _
                | _, _, _, _, _, _, _, _, Error message -> Error message
                | Ok (), Ok (), Ok (), Ok (), Ok (), Ok (), Ok (), Ok _, Ok () ->
                    Ok (Core.readiness (List.map (fun (name, status) -> { Core.name; status }) checks))
              in
              Evidence_store.close store;
              match result with
              | Error message -> prerr_endline message; exit 1
              | Ok status ->
                  print_endline (Report.render_readiness status);
                  match status with Core.Passed -> () | Core.Pending | Core.Failed _ -> exit 1)

let () =
  let command, root = parse () in
  match command with
  | "bootstrap" -> ignore (bootstrap root)
  | "inventory" ->
      (match inventory root with Ok _ -> () | Error message -> prerr_endline message; exit 1)
  | "manifest" ->
      (match manifest root with Ok () -> () | Error message -> prerr_endline message; exit 1)
  | "parity" -> parity root
  | "features" -> features root
  | "report" -> report root
  | "verify" -> verify root
  | _ -> usage ()
