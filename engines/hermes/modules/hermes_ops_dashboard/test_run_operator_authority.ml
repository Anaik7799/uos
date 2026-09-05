let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf
      "FAIL coordinate=L6/admission rca=Implementation hazard=HZ-OPERATOR-BROKER-01 check=%s\n"
      name
  end

let admitted stable_id =
  match Run_topology.admit_activity ~stable_id with
  | Ok activity -> activity
  | Error issues ->
      failwith (stable_id ^ ": " ^ String.concat "; " issues)

let code_is expected = function
  | Error (issue : Run_operator_authority.unavailable) ->
      issue.Run_operator_authority.code = expected
  | Ok _ -> false

let unavailable_is_exact = function
  | Error (issue : Run_operator_authority.unavailable) ->
      issue.Run_operator_authority.code
      = Run_operator_authority.Current_registration_unavailable
      && issue.Run_operator_authority.missing_prerequisites
         = Run_operator_authority.current_prerequisites
  | Ok _ -> false

let () =
  let open Run_operator_authority in
  let sqlite = admitted "activity.verify-sqlite-dependability" in
  let repository = admitted "activity.verify-repository" in
  check "B01 invalid capacity refuses before allocation"
    (code_is Invalid_capacity (create ~maximum_registrations:0));
  let bounded =
    match create ~maximum_registrations:1 with
    | Ok broker -> broker
    | Error issue -> failwith issue.Run_operator_authority.message
  in
  let first = prepare_slot bounded ~activity:sqlite in
  let replay = prepare_slot bounded ~activity:sqlite in
  check "B02 exact admitted activity prepares one nonauthorizing slot"
    (match first with
     | Ok receipt ->
         receipt.prepared_activity_digest
         = Run_topology.admitted_activity_digest sqlite
         && receipt.prepared_family = Ordinary_activity
         && not receipt.prepared_slot_was_replayed
     | Error _ -> false);
  check "B03 exact same-key replay is stable"
    (match first, replay with
     | Ok first, Ok replay ->
         replay.prepared_slot_was_replayed
         && first.prepared_slot_schema_digest
            = replay.prepared_slot_schema_digest
         && first.prepared_slot_receipt_digest
            = replay.prepared_slot_receipt_digest
         && prepared_registration_count bounded = 1
     | _ -> false);
  check "B04 fixed capacity refuses a distinct activity without mutation"
    (code_is Registration_capacity_exhausted
       (prepare_slot bounded ~activity:repository)
     && prepared_registration_count bounded = 1);
  let conflicted =
    match create ~maximum_registrations:2 with
    | Ok broker -> broker
    | Error issue -> failwith issue.Run_operator_authority.message
  in
  check "B05 exact activity-digest keys admit distinct bounded slots"
    (Result.is_ok (prepare_slot conflicted ~activity:sqlite)
     && Result.is_ok (prepare_slot conflicted ~activity:repository)
     && prepared_registration_count conflicted = 2
     && slot_state conflicted ~activity:sqlite = Slot_prepared
     && slot_state conflicted ~activity:repository = Slot_prepared);
  check "B06 changed same-key preparation conflicts and absorbs replay"
    (For_test.mutate_prepared_slot conflicted ~activity:sqlite
       For_test.Slot_schema_identity
     && code_is Registration_conflict
          (prepare_slot conflicted ~activity:sqlite)
     && code_is Registration_conflict
          (prepare_slot conflicted ~activity:sqlite)
     && slot_state conflicted ~activity:sqlite = Slot_conflict
     && prepared_registration_count conflicted = 2);
  check "B07 operational registration is exact typed unavailable"
    (current_registration_posture = `Implemented_unavailable
     && current_prerequisites
        = [ Target_registry_current; Effect_interpreter_current_identity;
            Conditional_interpreter_current; Event_store_current_identity ]
     && match first with
        | Error _ -> false
        | Ok receipt -> unavailable_is_exact
                          (register_current_unavailable bounded receipt));
  let empty =
    match create ~maximum_registrations:1 with
    | Ok broker -> broker
    | Error issue -> failwith issue.Run_operator_authority.message
  in
  check "B08 absent slot acquisition is typed missing"
    (code_is Missing_registration
       (acquire_current_unavailable empty ~activity:sqlite));
  check "B09 prepared slot still grants no current lease"
    (unavailable_is_exact
       (acquire_current_unavailable bounded ~activity:sqlite));
  check "B10 lease algebra is family-indexed and projection-closed"
    (family_id Ordinary_family = "ordinary"
     && family_id B_family = "b-campaign"
     && family_id Completion_family = "completion-reconcile"
     && lease_projection_ids
        = [ "effect-interpreter"; "conditional-interpreter" ]);
  Printf.printf "run_operator_authority: checks=%d failures=%d\n"
    !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_operator_authority"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
