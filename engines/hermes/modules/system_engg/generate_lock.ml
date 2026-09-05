let () =
  match Authority_catalog.make_catalog_manifest () with
  | Error _ -> failwith "Failed"
  | Ok manifest ->
      let entries = Authority_manifest.entries manifest in
      let md = Authority_manifest.digest manifest in
      let l_entries = List.map (fun m_entry ->
        let l_status = match Authority_manifest.disposition m_entry with
          | Exact _ -> Authority_lock.Admitted
          | Unavailable_observed _ -> Authority_lock.Unavailable_observed
          | Rejected_by_policy _ -> Authority_lock.Rejected_by_policy
        in
        {
          Authority_lock.manifest_digest = md;
          authority_id = Authority_manifest.id m_entry;
          resolved_revision = None;
          content_digest = None;
          license_policy_digest = md;
          status = l_status;
          reason = Some "Prerequisite setup pending";
        }
      ) entries in
      let json = Authority_lock.encode_canonical l_entries in
      Yojson.Safe.to_file "modules/system_engg/authority-lock.json" json;
      print_endline "Generated authority-lock.json successfully!"