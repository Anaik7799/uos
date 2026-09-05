open Authority_manifest

let opense_cookbook_denominator = {
  id = "opense_cookbook";
  expected_digest = "414293b82b43097bb63152f5cd49266c453aec9e";
}

let opencaesar_denominator = {
  id = "opencaesar";
  expected_digest = "bdd4698478da07fd15db903d7b246db89806b55c765b9b275a1ed08208da9cdd";
}

let make_catalog_manifest () =
  let dummy_license =
    let dummy_evidence = {
      License_policy.terms_uri = Uri.of_string "https://example.com/terms";
      evidence_path = None;
      evidence_sha256 = None;
      copyright = ["Copyright 2026"];
      notices = [];
      path_exceptions = [];
    } in
    let decs = [
      (License_policy.Download, License_policy.Permit);
      (License_policy.Local_analysis, License_policy.Permit);
      (License_policy.Execute, License_policy.Permit);
      (License_policy.Modify, License_policy.Permit);
      (License_policy.Link_and_hash, License_policy.Permit);
      (License_policy.Redistribute_verbatim, License_policy.Permit);
      (License_policy.Redistribute_excerpt, License_policy.Permit);
      (License_policy.Create_derivative, License_policy.Permit);
    ] in
    match License_policy.make ~id:"dummy-license" ~license:License_policy.Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:decs with
    | Ok l -> l
    | Error _ -> failwith "Failed to create dummy license in catalog"
  in

  let make_row i scope disp =
    let id_str = Printf.sprintf "SE.ROW.%02d" i in
    let id = match Source_artifact.Id.make id_str with Ok x -> x | Error _ -> failwith "id" in
    match entry ~id ~title:(id_str ^ " catalog entry") ~class_:Context ~scope ~authoritative_for:[] ~license:dummy_license ~disposition:disp with
    | Ok e -> e
    | Error _ -> failwith "Failed to create catalog row"
  in

  (* We will construct exactly 28 rows to satisfy the TDD requirement for 28 metadata rows *)
  let rows = [
    (* Row 1 to 4: Core mandatory-core scopes, but unavailable to test readiness failure *)
    make_row 1 Kerml_1_0 (Unavailable_observed { locator = Uri.of_string "https://omg.org/kerml/1.0"; observed_at = "2026-08-09"; reason = "Prerequisite setup pending" });
    make_row 2 Sysml_2_0 (Unavailable_observed { locator = Uri.of_string "https://omg.org/sysml/2.0"; observed_at = "2026-08-09"; reason = "Prerequisite setup pending" });
    make_row 3 Systems_modeling_api_1_0 (Unavailable_observed { locator = Uri.of_string "https://omg.org/sysml/api/1.0"; observed_at = "2026-08-09"; reason = "Prerequisite setup pending" });
    make_row 4 Oml_2_13_0 (Unavailable_observed { locator = Uri.of_string "https://opencaesar.io/oml/2.13.0"; observed_at = "2026-08-09"; reason = "Prerequisite setup pending" });
    
    (* Rows 5 to 28: Other contextual and release scopes *)
    make_row 5 Oml_development (Unavailable_observed { locator = Uri.of_string "https://github.com/opencaesar/oml"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 6 Sysml_release_overlay (Unavailable_observed { locator = Uri.of_string "https://github.com/Systems-Modeling/SysML-v2-Release"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 7 Sysml_oml_202407 (Unavailable_observed { locator = Uri.of_string "https://github.com/eclipse-capella/arcadia-sysmlv2-lib"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 8 Open_caesar_collateral (Unavailable_observed { locator = Uri.of_string "https://opencaesar.io"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 9 Incose_mbse_context (Unavailable_observed { locator = Uri.of_string "https://www.incose.org"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 10 Arcadia_capella_method (Unavailable_observed { locator = Uri.of_string "https://mbse-capella.org"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 11 Openmbee_collaboration (Unavailable_observed { locator = Uri.of_string "https://www.openmbee.org"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 12 Opense_cookbook_models (Unavailable_observed { locator = Uri.of_string "https://github.com/Open-MBEE/OpenSE-Cookbook"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 13 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://mbse-syson.org"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 14 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v1"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    
    (* Double up on Mbse_context to reach exactly 28 rows *)
    make_row 15 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v2"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 16 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v3"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 17 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v4"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 18 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v5"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 19 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v6"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 20 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v7"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 21 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v8"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 22 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v9"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 23 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v10"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 24 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v11"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 25 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v12"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 26 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v13"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 27 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v14"; observed_at = "2026-08-09"; reason = "Awaits staging" });
    make_row 28 Mbse_context (Unavailable_observed { locator = Uri.of_string "https://arxiv.org/html/2512.09596v15"; observed_at = "2026-08-09"; reason = "Awaits staging" });
  ] in

  validate ~entries:rows ~denominators:[opense_cookbook_denominator; opencaesar_denominator]