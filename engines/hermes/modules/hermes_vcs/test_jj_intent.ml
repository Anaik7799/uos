let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let id make text =
  match make text with
  | Ok value -> value
  | Error _ -> failwith ("typed identity fixture rejected: " ^ text)

let contains source needle =
  let source_length = String.length source in
  let needle_length = String.length needle in
  let rec loop offset =
    offset + needle_length <= source_length
    &&
    (String.sub source offset needle_length = needle || loop (offset + 1))
  in
  loop 0

let () =
  let repository = id Jj_id.Repository.make "repo-main" in
  let workspace = id Jj_id.Workspace.make "workspace-main" in
  let expected_before = id Jj_id.Operation.make "operation-before" in
  let approval_reference = id Jj_id.Approval.make "approval-7" in
  let intent =
    Jj_intent.make ~operation:Jj_operation.Git_push ~repository ~workspace
      ~expected_before ~approval_reference
  in
  check "I1 constructor derives all authority metadata from the operation"
    (match intent with
     | Error _ -> false
     | Ok value ->
         let view = Jj_intent.projection value in
         view.operation = Jj_operation.Git_push
         && view.approval = Jj_operation.Approval_remote_publish
         && view.postcondition = Jj_operation.Postcondition_remote_readback
         && view.recovery = Jj_operation.Recovery_before_state
         && view.applicability = Jj_intent.Implemented_unavailable
         && view.budget.max_attempts = 1
         && view.budget.timeout_ms = 120_000
         && view.budget.max_output_bytes = 262_144);
  check "I2 canonical bytes bind every typed identity and derived field"
    (match intent with
     | Error _ -> false
     | Ok value ->
         let bytes = Jj_codec.canonical_bytes value in
         let digest = Jj_codec.digest value in
         String.length bytes > 0 && String.length digest = 64
         &&
         let other_repository = id Jj_id.Repository.make "repo-other" in
         match
           Jj_intent.make ~operation:Jj_operation.Git_push
             ~repository:other_repository ~workspace ~expected_before
             ~approval_reference
         with
         | Error _ -> false
         | Ok other ->
             not (String.equal digest (Jj_codec.digest other)));
  check "I3 canonical JSON round-trips without execution carriers"
    (match intent with
     | Error _ -> false
     | Ok value ->
         let json = Jj_codec.to_json value in
         not (List.exists (contains json)
                [ "argv"; "executable"; "cwd"; "environment";
                  "effect_kind"; "receipt" ])
         && match Jj_codec.of_json json with
            | Ok decoded -> String.equal json (Jj_codec.to_json decoded)
            | Error _ -> false);
  let reordered =
    "{\"workspace\":\"workspace-main\",\"schema\":\"hermes.jj.intent.v1\","
    ^ "\"operation\":\"git-push\",\"approval_reference\":\"approval-7\","
    ^ "\"repository\":\"repo-main\",\"expected_before\":\"operation-before\","
    ^ "\"approval_class\":\"remote-publish\",\"max_attempts\":\"1\","
    ^ "\"timeout_ms\":\"120000\",\"max_output_bytes\":\"262144\","
    ^ "\"postcondition\":\"remote-readback\",\"recovery\":\"before-state\","
    ^ "\"applicability\":\"implemented-unavailable\"}"
  in
  check "I4 reordered complete JSON normalizes to one canonical encoding"
    (match intent, Jj_codec.of_json reordered with
     | Ok expected, Ok decoded ->
         String.equal (Jj_codec.to_json expected) (Jj_codec.to_json decoded)
     | _ -> false);
  let missing =
    "{\"schema\":\"hermes.jj.intent.v1\",\"operation\":\"git-push\"}"
  in
  let extra =
    String.sub reordered 0 (String.length reordered - 1)
    ^ ",\"argv\":\"jj git push\"}"
  in
  let duplicate =
    String.sub reordered 0 (String.length reordered - 1)
    ^ ",\"operation\":\"version\"}"
  in
  let hostile =
    String.concat ""
      (String.split_on_char ';' reordered)
    |> fun _ ->
    String.sub reordered 0 (String.length reordered - 1)
    ^ ",\"repository\":\"repo;escape\"}"
  in
  check "I5 missing extra duplicate hostile and unbounded JSON refuse"
    (Result.is_error (Jj_codec.of_json missing)
     && Result.is_error (Jj_codec.of_json extra)
     && Result.is_error (Jj_codec.of_json duplicate)
     && Result.is_error (Jj_codec.of_json hostile)
     && Result.is_error (Jj_codec.of_json (String.make 8193 'x')));
  let authority_mutant =
    String.concat ""
      (String.split_on_char '\n' reordered)
    |> fun json ->
    let needle = "\"approval_class\":\"remote-publish\"" in
    let replacement = "\"approval_class\":\"observation\"" in
    match String.index_opt json 'a' with
    | None -> json
    | Some _ ->
        let rec replace offset =
          if offset + String.length needle > String.length json then json
          else if String.sub json offset (String.length needle) = needle then
            String.sub json 0 offset ^ replacement
            ^ String.sub json (offset + String.length needle)
                (String.length json - offset - String.length needle)
          else replace (offset + 1)
        in
        replace 0
  in
  check "I6 caller cannot override operation-derived authority metadata"
    (Result.is_error (Jj_codec.of_json authority_mutant));
  check "I7 intent source digest binds its closed projection and applicability"
    (String.length Jj_intent.source_digest = 64
     && Jj_intent.source_digest
        <> Jj_intent.For_test.source_digest_with_mutation
             Jj_intent.For_test.Drop_projection_field
     && Jj_intent.source_digest
        <> Jj_intent.For_test.source_digest_with_mutation
             Jj_intent.For_test.Change_applicability);
  check "I8 codec source digest binds parser bounds and exact field denominator"
    (String.length Jj_codec.source_digest = 64
     && Jj_codec.source_digest
        <> Jj_codec.For_test.source_digest_with_mutation
             Jj_codec.For_test.Change_json_bound
     && Jj_codec.source_digest
        <> Jj_codec.For_test.source_digest_with_mutation
             Jj_codec.For_test.Drop_expected_field);

  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 8 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_intent"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
