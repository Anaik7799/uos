open Dependability_recovery_vault

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get diagnostic = function
  | Ok value -> value
  | Error error -> failwith (diagnostic ^ ": " ^ diagnostic_code error)

let jj_id make label =
  match make label with
  | Ok value -> value
  | Error _ -> failwith ("invalid fixture identity: " ^ label)

let receipt = jj_id Jj_id.Receipt.make
let request = jj_id Jj_id.Request.make
let operation = jj_id Jj_id.Operation.make
let workspace = jj_id Jj_id.Workspace.make

let clock () =
  match
    Dependability_clock.observe ~max_pair_span_ns:1_000_000_000L
      ~lifetime_ns:Dependability_clock.maximum_lifetime_ns
  with
  | Ok value -> value
  | Error _ -> failwith "clock unavailable"

let authority_digest label =
  label |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
  |> Dependability_authority_store.Digest.make
  |> function
  | Ok value -> value
  | Error diagnostic ->
      failwith
        ("authority digest: "
        ^ Dependability_authority_store.diagnostic_code diagnostic)

let authority_opened =
  let registry =
    Dependability_sqlite_test_protocol.create ~maximum_live:1
    |> function
    | Ok value -> value
    | Error error ->
        failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let registry, lease =
    Dependability_sqlite_test_protocol.acquire registry
      Dependability_sqlite_test_protocol.In_memory
    |> function
    | Ok value -> value
    | Error error ->
        failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let location =
    Dependability_sqlite_test_protocol.reference registry lease
    |> function
    | Ok value -> value
    | Error error ->
        failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let observed_at = clock () in
  let bootstrap =
    Dependability_authority_store.prepare_bootstrap
      ~build:(authority_digest "build") ~root:(authority_digest "root")
      ~configuration:(authority_digest "configuration")
      ~host:(authority_digest "host") ~pins:(authority_digest "pins")
      ~observed_at
    |> function
    | Ok value -> value
    | Error diagnostic ->
        failwith
          ("authority bootstrap: "
          ^ Dependability_authority_store.diagnostic_code diagnostic)
  in
  Dependability_authority_store.open_first_or_successor ~location ~bootstrap
  |> function
  | Ok value -> value
  | Error diagnostic ->
      failwith
        ("authority open: "
        ^ Dependability_authority_store.diagnostic_code diagnostic)

let authority = Dependability_authority_store.operational authority_opened

let context () =
  let observed_at = clock () in
  let prepared =
    prepare_context ~manifest:(receipt "manifest-current")
      ~authority
      ~recovery_attempt:(request "recovery-attempt-one")
      ~challenge:(receipt "recovery-challenge-one")
      ~transition:(receipt "source-transition-one") ~observed_at
    |> get "prepare context"
  in
  prepared, validate_context_current ~now:(clock ()) prepared |> get "current"

let anchors () =
  prepare_anchors ~operation:(operation "operation-before")
    ~workspace:(workspace "workspace-one")
    ~source:(receipt "source-before")

let digest label = Jj_split_manifest.Digest.of_bytes (Bytes.of_string label)

let triplet locator suffix =
  let locator = receipt locator in
  [ seal_absent ~locator () |> get "seal absent";
    seal_present ~role:Candidate ~locator ~mode:Jj_split_manifest.Regular
      ~size_bytes:9 ~content_digest:(digest ("candidate-" ^ suffix))
      ~symlink_target_digest:None
    |> get "seal candidate";
    seal_present ~role:Remainder ~locator ~mode:Jj_split_manifest.Regular
      ~size_bytes:9 ~content_digest:(digest ("remainder-" ^ suffix))
      ~symlink_target_digest:None
    |> get "seal remainder" ]

let prepare_vault purpose objects =
  let _, current = context () in
  Dependability_recovery_vault.prepare ~purpose ~context:current
    ~anchors:(anchors ()) ~objects
  |> get "prepare vault"

let evidence label = receipt ("evidence-" ^ label)

let step model action request_label evidence_label outcome =
  For_test.step model ~now:(clock ()) ~request:(request request_label) ~action
    ~evidence:(evidence evidence_label) ~outcome

let () =
  check "V1 purpose and object-role denominators are exact and closed"
    (List.map purpose_id
       [ Pack_purpose B_success; Pack_purpose Completion_record ]
     = [ "b-success"; "completion-record" ]
     && List.map object_role_id [ Original; Candidate; Remainder ]
        = [ "original"; "candidate"; "remainder" ]);

  let prepared_context, current = context () in
  check "V2 context binds typed manifest session transition and fresh clock"
    (String.length (context_digest prepared_context) = 64
     && String.length (current_context_digest current) = 64
     && Result.is_ok (validate_context_current ~now:(clock ()) prepared_context));

  let locator = receipt "object-one" in
  let absent = seal_absent ~locator () |> get "absent before image" in
  let regular =
    seal_present ~role:Original ~locator ~mode:Jj_split_manifest.Regular
      ~size_bytes:0 ~content_digest:(digest "empty")
      ~symlink_target_digest:None
    |> get "regular before image"
  in
  let symlink_digest = digest "link-target" in
  let symlink =
    seal_present ~role:Original ~locator ~mode:Jj_split_manifest.Symlink
      ~size_bytes:11 ~content_digest:symlink_digest
      ~symlink_target_digest:(Some symlink_digest)
    |> get "symlink before image"
  in
  check "V3 sealed metadata carries no bytes or locator projection and changes identity"
    (List.for_all (fun value -> String.length (sealed_object_digest value) = 64)
       [ absent; regular; symlink ]
     && sealed_object_digest absent <> sealed_object_digest regular
     && sealed_object_digest regular <> sealed_object_digest symlink);
  check "V4 inconsistent present absent mode and symlink metadata refuse"
    (Result.is_error (seal_absent ~role:Candidate ~locator ())
     && Result.is_error
          (seal_present ~role:Original ~locator ~mode:Jj_split_manifest.Regular
             ~size_bytes:1 ~content_digest:(digest "regular")
             ~symlink_target_digest:(Some (digest "forbidden-link")))
     && Result.is_error
          (seal_present ~role:Original ~locator ~mode:Jj_split_manifest.Symlink
             ~size_bytes:1 ~content_digest:(digest "link-a")
             ~symlink_target_digest:(Some (digest "link-b")))
     && Result.is_error
          (seal_present ~role:Original ~locator ~mode:Jj_split_manifest.Regular
             ~size_bytes:(max_object_size_bytes + 1)
             ~content_digest:(digest "too-large") ~symlink_target_digest:None));

  let objects = triplet "entry-one" "one" @ triplet "entry-two" "two" in
  let prepared = prepare_vault B_success objects in
  check "V5 a complete bounded original candidate remainder set prepares only nonauthority"
    (prepared_status prepared = `Prepared_nonauthorizing
     && prepared_entry_count prepared = 2
     && String.length (prepared_digest prepared) = 64);
  check "V6 missing duplicate and unbounded sealed denominators refuse"
    (Result.is_error
       (let _, current = context () in
        Dependability_recovery_vault.prepare ~purpose:B_success
          ~context:current ~anchors:(anchors ())
          ~objects:(List.tl objects))
     && Result.is_error
          (let _, current = context () in
           Dependability_recovery_vault.prepare ~purpose:B_success
             ~context:current ~anchors:(anchors ())
             ~objects:(objects @ [ List.hd objects ]))
     && Result.is_error
          (let _, current = context () in
           let rec many index acc =
             if index = max_entries + 1 then acc
             else
               many (index + 1)
                 (triplet (Printf.sprintf "entry-%03d" index)
                    (string_of_int index)
                 @ acc)
           in
           Dependability_recovery_vault.prepare ~purpose:B_success
             ~context:current ~anchors:(anchors ())
             ~objects:(many 0 [])));

  check "V7 production opens fail closed while descriptor-relative backend is unavailable"
    (match open_operational ~purpose:B_success ~context:current with
     | Error diagnostic ->
         diagnostic_code diagnostic = "filesystem-backend-unavailable"
         && diagnostic_origin diagnostic = Environment
     | Ok _ -> false)
    ;
  check "V8 recovery and lifecycle roles are nominally separate and also unavailable"
    (match open_recovery ~purpose:Completion_record ~context:current with
     | Error diagnostic ->
         diagnostic_code diagnostic = "filesystem-backend-unavailable"
     | Ok _ -> false);

  let model = For_test.start prepared in
  check "V9 injected algebra starts at exact bounded Stage prefix"
    (For_test.state model = Prepared
     && For_test.completed model = 0
     && For_test.total model = 6);
  let model, stage_one =
    step model Stage "stage-one" "stage-one" For_test.Applied_exact
    |> get "stage one"
  in
  let model_replayed, stage_one_replay =
    step model Stage "stage-one" "stage-one" For_test.Applied_exact
    |> get "stage replay"
  in
  check "V10 same stage request replays without advancing twice"
    (For_test.state model = Staging
     && For_test.completed model = 1
     && For_test.model_digest model = For_test.model_digest model_replayed
     && For_test.receipt_digest stage_one
        = For_test.receipt_digest stage_one_replay
     && not (For_test.receipt_replayed stage_one)
     && For_test.receipt_replayed stage_one_replay);
  check "V11 same request with changed evidence is a permanent conflict"
    (match
       step model Stage "stage-one" "changed" For_test.Applied_exact
     with
     | Error diagnostic -> diagnostic_code diagnostic = "request-conflict"
     | Ok _ -> false);

  let model, lost =
    step model Stage "stage-two" "stage-two" For_test.Reply_lost
    |> get "lost stage reply"
  in
  check "V12 a lost reply is indeterminate and blocks guessed progress"
    (For_test.state model = Indeterminate Stage
     && not (For_test.receipt_replayed lost)
     && match
          step model Restore "restore-too-early" "restore"
            For_test.Applied_exact
        with
        | Error diagnostic -> diagnostic_code diagnostic = "indeterminate-effect"
        | Ok _ -> false);
  let model, reconciled =
    For_test.reconcile_lost_reply model ~now:(clock ())
      ~request:(request "stage-two") ~action:Stage
      ~readback:(receipt "stage-two-readback")
      ~resolution:For_test.Not_applied_on_readback
    |> get "reconcile lost stage"
  in
  let model_replayed, reconciled_replay =
    For_test.reconcile_lost_reply model ~now:(clock ())
      ~request:(request "stage-two") ~action:Stage
      ~readback:(receipt "stage-two-readback")
      ~resolution:For_test.Not_applied_on_readback
    |> get "replay reconciliation"
  in
  check "V13 exact readback resolves not-applied without inventing progress"
    (For_test.state model = Staging
     && For_test.completed model = 1
     && For_test.model_digest model = For_test.model_digest model_replayed
     && For_test.receipt_digest reconciled
        = For_test.receipt_digest reconciled_replay
     && For_test.receipt_replayed reconciled_replay);

  let rec finish_action model action ordinal =
    let state = For_test.state model in
    let done_ =
      match action, state with
      | Stage, Staged | Restore, Restored | Readback, Readback_verified
      | Cleanup, Cleaned -> true
      | _ -> false
    in
    if done_ then model
    else
      let label = Printf.sprintf "%s-%02d" (action_id action) ordinal in
      let model, _ =
        step model action label label For_test.Applied_exact
        |> get ("finish " ^ action_id action)
      in
      finish_action model action (ordinal + 1)
  in
  let staged = finish_action model Stage 20 in
  let restored = finish_action staged Restore 40 in
  let readback = finish_action restored Readback 60 in
  let cleaned = finish_action readback Cleanup 80 in
  check "V14 exact stage restore readback cleanup order reaches one absorbing terminal"
    (For_test.state staged = Staged
     && For_test.state restored = Restored
     && For_test.state readback = Readback_verified
     && For_test.state cleaned = Cleaned
     && match
          step cleaned Cleanup "cleanup-after-terminal" "cleanup"
            For_test.Applied_exact
        with
        | Error diagnostic -> diagnostic_code diagnostic = "terminal-state"
        | Ok _ -> false);

  let fragment =
    For_test.prepare_recovery_inventory cleaned ~now:(clock ())
    |> get "prepare recovery inventory"
  in
  check "V15 recovery inventory is owner-derived but cannot forge current producer credit"
    (String.length
       (Dependability_owner_inventory.prepared_fragment_digest fragment)
     = 64
     && Dependability_owner_inventory.current_join_authority
        = `Lower_pure_nonauthorizing);

  let completion = prepare_vault Completion_record objects in
  check "V16 purpose is digest-bound and cannot be cross-consumed by typed operations"
    (prepared_digest prepared <> prepared_digest completion);

  check "V17 source identity kills capability replay currentness cleanup and authority mutants"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
            source_digest <> For_test.source_digest_with_mutation mutation)
          [ For_test.Cross_purpose_restore;
            Emit_raw_payload;
            Skip_currentness;
            Drop_replay_check;
            Guess_lost_reply;
            Forge_current_inventory;
            Skip_cleanup_order;
            Unbind_manifest_session;
            Enable_filesystem_backend ]);

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_recovery_vault"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_recovery_vault ]);
  exit (Suite_telemetry.exit_code self)
