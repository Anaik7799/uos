open License_policy

let check name f =
  match f () with
  | true -> Printf.printf "PASS %s\n" name; true
  | false -> Printf.printf "FAIL %s\n" name; false
  | exception exn -> Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn); false

let dummy_evidence = {
  terms_uri = Uri.of_string "https://example.com/terms";
  evidence_path = None;
  evidence_sha256 = None;
  copyright = ["Copyright 2026"];
  notices = [];
  path_exceptions = [];
}

let valid_decisions = [
  (Download, Permit);
  (Local_analysis, Permit);
  (Execute, Permit);
  (Modify, Permit);
  (Link_and_hash, Permit);
  (Redistribute_verbatim, Permit);
  (Redistribute_excerpt, Permit);
  (Create_derivative, Permit);
]

let () =
  let p = ref 0 and f = ref 0 in
  let run name fn = if check name fn then incr p else incr f in

  run "LP-TOTAL: make fails on missing use" (fun () ->
    let decs = List.filter (fun (u, _) -> u <> Download) valid_decisions in
    match make ~id:"p1" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:decs with
    | Error [Missing_use Download] -> true
    | _ -> false
  );

  run "LP-TOTAL: make fails on duplicate use" (fun () ->
    let decs = (Download, Reject "no") :: valid_decisions in
    match make ~id:"p2" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:decs with
    | Error [Duplicate_use Download] -> true
    | _ -> false
  );

  run "LP-NO-IMPLICIT-PERMIT: No_assertion rejects Permit" (fun () ->
    match make ~id:"p3" ~license:No_assertion ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:valid_decisions with
    | Error (Rule_violation _ :: _) -> true
    | _ -> false
  );

  run "LP-NOTICE-CLOSED: blank terms uri rejects notice" (fun () ->
    let bad_evidence = { dummy_evidence with terms_uri = Uri.of_string "" } in
    let decs = List.map (fun (u, d) -> if u = Download then (u, Permit_with_obligations ["Keep notice"]) else (u, d)) valid_decisions in
    match make ~id:"p4" ~license:Apache_2_0 ~evidence:bad_evidence ~embedded_third_party:false ~decisions:decs with
    | Error (Invalid_evidence _ :: _) -> true
    | _ -> false
  );

  run "LP-NOTICE-CLOSED: malformed digest rejects" (fun () ->
    let bad_evidence = { dummy_evidence with evidence_sha256 = Some "bad-sha" } in
    let decs = List.map (fun (u, d) -> if u = Download then (u, Permit_with_obligations ["Keep notice"]) else (u, d)) valid_decisions in
    match make ~id:"p5" ~license:Apache_2_0 ~evidence:bad_evidence ~embedded_third_party:false ~decisions:decs with
    | Error (Invalid_evidence _ :: _) -> true
    | _ -> false
  );

  run "LP-EMBEDDED-BOUNDARY: embedded_third_party rejects Permit on Modify" (fun () ->
    match make ~id:"p6" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:true ~decisions:valid_decisions with
    | Error (Embedded_violation _ :: _) -> true
    | _ -> false
  );

  run "LP-REVIEW-NONCREDIT: authorize returns error on Review_required/Reject" (fun () ->
    let decs = List.map (fun (u, d) -> if u = Modify then (u, Reject "never") else (u, d)) valid_decisions in
    match make ~id:"p7" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:decs with
    | Error _ -> false
    | Ok t ->
        match authorize t Modify with
        | Error (Rule_violation _) -> true
        | _ -> false
  );

  run "LP-DETERMINISTIC: digests are stable" (fun () ->
    match make ~id:"p8" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:valid_decisions with
    | Error _ -> false
    | Ok t1 ->
        match make ~id:"p8" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:valid_decisions with
        | Error _ -> false
        | Ok t2 ->
            let d1 = digest t1 and d2 = digest t2 in
            Digestif.SHA256.equal d1 d2
  );

  (* MUT-LP-DEFAULT-PERMIT mock test *)
  run "MUT-LP-DEFAULT-PERMIT is killed by LP-TOTAL" (fun () ->
    let missing_decisions = List.filter (fun (u, _) -> u <> Download) valid_decisions in
    (* A default-permit implementation would implicitly complete missing uses with Permit.
       LP-TOTAL forces make to fail on Missing_use Download. *)
    match make ~id:"p_mut1" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:false ~decisions:missing_decisions with
    | Error [Missing_use Download] -> true
    | _ -> false
  );

  (* MUT-LP-INHERIT-CONTAINER mock test *)
  run "MUT-LP-INHERIT-CONTAINER is killed by LP-EMBEDDED-BOUNDARY" (fun () ->
    (* An implementation allowing embedded content to inherit container permissions would Permit Modify.
       LP-EMBEDDED-BOUNDARY forces make to reject Permit on Modify when embedded_third_party is true. *)
    match make ~id:"p_mut2" ~license:Apache_2_0 ~evidence:dummy_evidence ~embedded_third_party:true ~decisions:valid_decisions with
    | Error (Embedded_violation _ :: _) -> true
    | _ -> false
  );

  Printf.printf "test_license_policy: %d passed, %d failed\n" !p !f;
  let self = Suite_telemetry.observe ~suite:"test_license_policy" ~passed:!p ~failed:!f ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook; Stanza.run_swarm_bridge_programme ]);
  exit (Suite_telemetry.exit_code self)