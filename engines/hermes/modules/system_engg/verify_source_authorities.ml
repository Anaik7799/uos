let () =
  let args = Sys.argv |> Array.to_list |> List.tl in
  let staged = 
    let rec find_staged = function
      | "--staged" :: s :: _ -> s
      | _ :: rest -> find_staged rest
      | [] -> "state/tmp/system-engg-acquire"
    in find_staged args
  in
  match Authority_catalog.make_catalog_manifest () with
  | Error _ -> Printf.eprintf "Failed to load catalog manifest\n"; exit 1
  | Ok manifest ->
      let lock_json = 
        try Yojson.Safe.from_file "modules/system_engg/authority-lock.json"
        with _ -> `Assoc []
      in
      match Authority_lock.decode_strict lock_json with
      | Error _ -> Printf.eprintf "Failed to decode authority lock\n"; exit 1
      | Ok lock ->
          match Collateral_verifier.staging_root ~project_root:"." staged with
          | Error _ -> Printf.eprintf "Invalid staging root\n"; exit 1
          | Ok staged_root ->
              match Collateral_verifier.verify_batch ~manifest ~lock ~staged_root with
              | Ok _ -> print_endline "Staged authorities are fully verified!"; exit 0
              | Error _ -> Printf.eprintf "Staged authorities verification failed!\n"; exit 1