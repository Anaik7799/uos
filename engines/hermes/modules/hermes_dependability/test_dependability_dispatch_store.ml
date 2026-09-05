open Dependability_dispatch_store

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAILED: %s\n" name
  end

let get label = function
  | Ok value -> value
  | Error diagnostic ->
      failwith (label ^ ": " ^ diagnostic_code diagnostic)

let digest label =
  label |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
  |> Digest.make |> get ("digest " ^ label)

let authority_digest label =
  label |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
  |> Dependability_authority_store.Digest.make
  |> function
  | Ok value -> value
  | Error diagnostic ->
      failwith
        ("authority digest " ^ label ^ ": "
        ^ Dependability_authority_store.diagnostic_code diagnostic)

let get_authority label = function
  | Ok value -> value
  | Error diagnostic ->
      failwith
        (label ^ ": "
        ^ Dependability_authority_store.diagnostic_code diagnostic)

let clock () =
  Dependability_clock.observe ~max_pair_span_ns:1_000_000_000L
    ~lifetime_ns:30_000_000_000L
  |> function Ok receipt -> receipt | Error _ -> failwith "clock unavailable"

let owner_identity label =
  Dependability_owner_inventory.Identity.make label
  |> function
  | Ok identity -> identity
  | Error refusal ->
      failwith (Dependability_owner_inventory.refusal_code refusal)

let with_in_memory_reference f =
  let registry =
    Dependability_sqlite_test_protocol.create ~maximum_live:1
    |> function
    | Ok registry -> registry
    | Error error ->
        failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let registry, lease =
    Dependability_sqlite_test_protocol.acquire registry
      Dependability_sqlite_test_protocol.In_memory
    |> function
    | Ok acquired -> acquired
    | Error error ->
        failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let location =
    Dependability_sqlite_test_protocol.reference registry lease
    |> function
    | Ok reference -> reference
    | Error error ->
        failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let result = f location in
  ignore (Dependability_sqlite_test_protocol.release registry lease);
  result

let with_authority f =
  let observed_at = clock () in
  let authority_bootstrap =
    Dependability_authority_store.prepare_bootstrap
      ~build:(authority_digest "authority-build")
      ~root:(authority_digest "authority-root")
      ~configuration:(authority_digest "authority-configuration")
      ~host:(authority_digest "authority-host")
      ~pins:(authority_digest "authority-pins")
      ~observed_at
    |> get_authority "prepare authority bootstrap"
  in
  with_in_memory_reference (fun authority_location ->
      match
        Dependability_authority_store.open_first_or_successor
          ~location:authority_location ~bootstrap:authority_bootstrap
      with
      | Error diagnostic ->
          failwith
            ("open authority foundation: "
            ^ Dependability_authority_store.diagnostic_code diagnostic)
      | Ok opened ->
          let authority = Dependability_authority_store.operational opened in
          let peer_opens =
            Dependability_authority_store.peer_operational_open_bundle opened
          in
          let (_writer_open, dispatch_open, _vault_open, _completion_open) =
            Dependability_authority_store.split_peer_operational_open_once
              peer_opens
            |> get_authority "split peer operational opens"
          in
          let authority_roles = Dependability_authority_store.role_bundle opened in
          let authority_lifecycle =
            Dependability_authority_store.take_lifecycle authority_roles
            |> function
            | Ok role -> role
            | Error diagnostic ->
                failwith
                  (Dependability_authority_store.diagnostic_code diagnostic)
          in
          let result = f authority dispatch_open observed_at in
          let drained =
            Dependability_authority_store.drain_once authority_lifecycle
            |> function Ok value -> value | Error _ -> failwith "authority drain"
          in
          ignore
            (Dependability_authority_store.close_once authority_lifecycle
               drained);
          result)

let check_unavailable code origin = function
  | Error diagnostic ->
      diagnostic_code diagnostic = code && diagnostic_origin diagnostic = origin
  | Ok _ -> false

let () =
  check "D1 digest identities reject wrong-size and upper-case input"
    (Result.is_error (Digest.make "")
     && Result.is_error (Digest.make (String.make 64 'A'))
     && Result.is_ok
          (Digest.make
             (Digestif.SHA256.digest_string "valid"
             |> Digestif.SHA256.to_hex)));

  with_authority (fun authority dispatch_open observed_at ->
      let bootstrap =
        prepare_bootstrap ~authority ~observed_at
        |> get "prepare dispatch bootstrap"
      in
      check "D2 bootstrap binds lower owner session clock and pure Jujutsu authority"
        (String.length (bootstrap_digest bootstrap) = 64);
      check "D3 registered production open is typed implemented-unavailable"
        (check_unavailable "implemented-unavailable" Environment
           (open_first_or_successor
              ~fence:dispatch_open
              ~location:
                (Dependability_sqlite_location.registered
                   Dependability_sqlite_location.Dispatch_store)
              ~bootstrap));

      with_in_memory_reference (fun location ->
          match
            open_first_or_successor ~fence:dispatch_open ~location ~bootstrap
          with
          | Error _ -> check "D4 volatile dispatch foundation opens" false
          | Ok opened ->
              let operational = operational opened in
              let roles = role_bundle opened in
              check "D4 volatile owner binds exact session attempt and unavailable production posture"
                (owner_session_generation operational = 1
                 && recovery_attempt_ordinal operational = 1
                 && String.length (owner_session_digest operational) = 64
                 && String.length (store_epoch_digest operational) = 64
                 && operational_posture operational = `Volatile_test_foundation
                 && production_posture operational = `Implemented_unavailable);

              let claim_role =
                take_dispatch_claim roles |> get "take claim role"
              in
              let decision_role =
                take_conditional_decision roles |> get "take decision role"
              in
              let abandonment_role =
                take_abandonment_writer roles |> get "take abandonment role"
              in
              let lifecycle = take_lifecycle roles |> get "take lifecycle" in
              check "D5 role transfer is one-shot and has no store-wide fallback"
                (check_unavailable "role-already-transferred" Control
                   (take_dispatch_claim roles));

              let key =
                prepare_dispatch_key claim_role
                  ~logical_execution:(digest "logical-execution")
                  ~admission:(digest "admission") ~plan:(digest "plan")
                |> get "prepare dispatch key"
              in
              let initial_request = digest "register-request" in
              let register request =
                prepare_registration ~key ~request ~observed_at
                |> get "prepare registration"
              in
              let registered =
                register_not_dispatched_once claim_role
                  (register initial_request)
                |> get "register not dispatched"
              in
              let registered_replay =
                register_not_dispatched_once claim_role
                  (register initial_request)
                |> get "replay registration"
              in
              check "D6 Not_dispatched registration is append-only replay-stable and conflict-absorbing"
                (transition_status registered = Not_dispatched
                 && transition_ordinal registered = 0
                 && transition_id registered = transition_id registered_replay
                 && transition_replayed registered_replay
                 && check_unavailable "request-conflict" Control
                      (register_not_dispatched_once claim_role
                         (register (digest "different-register-request"))));

              let not_dispatched =
                read_dispatch claim_role key |> get "read not dispatched"
              in
              let claim request =
                prepare_claim ~predecessor:not_dispatched ~request
                  ~observed_at
                |> get "prepare claim"
              in
              let claimed =
                claim_once claim_role (claim (digest "claim-request"))
                |> get "claim"
              in
              let claimed_replay =
                claim_once claim_role (claim (digest "claim-request"))
                |> get "replay claim"
              in
              check "D7 dispatch claim is one exact CAS with stable replay"
                (transition_status claimed = Dispatch_claimed
                 && transition_ordinal claimed = 1
                 && transition_id claimed = transition_id claimed_replay
                 && transition_replayed claimed_replay
                 && check_unavailable "request-conflict" Control
                      (claim_once claim_role
                         (claim (digest "different-claim-request"))));

              let claimed_readback =
                read_dispatch claim_role key |> get "read claimed"
              in
              let current =
                reconcile_claim_current claim_role ~now:(clock ())
                  claimed_readback
                |> get "reconcile claim current"
              in
              check "D8 currentness binds exact owner session attempt pointer row and clock"
                (readback_status claimed_readback = Dispatch_claimed
                 && readback_ordinal claimed_readback = 1
                 && String.length (readback_digest claimed_readback) = 64
                 && String.length (claim_digest current) = 64
                 && claim_owner_session_digest current
                    = owner_session_digest operational
                 && claim_recovery_attempt_ordinal current = 1);

              let decision =
                read_decision decision_role current |> get "read decision"
              in
              let undecided =
                reconcile_undecided_current decision_role ~now:(clock ())
                  decision
                |> get "reconcile undecided"
              in
              check "D9 conditional row is durable exactly Undecided and current"
                (decision_readback_status decision = Undecided
                 && String.length (decision_readback_digest decision) = 64
                 && String.length (undecided_current_digest undecided) = 64);

              let completion_plan =
                Jj_campaign_action.derive_completion_reconcile_plan
                  ~request_id:
                    (Jj_id.Request.make "dispatch-completion-plan"
                    |> function Ok value -> value | Error _ -> assert false)
                |> function Ok value -> value | Error _ -> assert false
              in
              check "D10 no caller-selected decision seam exists before the family-bound carrier"
                (check_unavailable "decision-protocol-unavailable" Control
                   (prepare_decision_transition decision_role ~claim:current
                      ~plan:completion_plan)
                 && decision_readback_status
                      (read_decision decision_role current
                       |> get "decision unchanged")
                    = Undecided);

              let abandonment =
                read_abandonment abandonment_role current
                |> get "read abandonment"
              in
              check "D11 abandonment remains exact no-commit without producer-sealed evidence"
                (abandonment_readback_status abandonment = No_abandonment
                 && String.length (abandonment_readback_digest abandonment)
                    = 64);

              let conditional_inventory, abandonment_inventory =
                reconcile_restart_inventories lifecycle ~now:(clock ())
                |> get "reconcile restart inventories"
              in
              let conditional_replay, abandonment_replay =
                reconcile_restart_inventories lifecycle ~now:(clock ())
                |> get "replay restart inventories"
              in
              check "D12 restart inventory is owner-derived read-only and replay-stable"
                (conditional_inventory_decision_count conditional_inventory = 1
                 && abandonment_inventory_commitment_count
                      abandonment_inventory = 0
                 && conditional_inventory_digest conditional_inventory
                    = conditional_inventory_digest conditional_replay
                 && abandonment_inventory_digest abandonment_inventory
                    = abandonment_inventory_digest abandonment_replay
                 && conditional_inventory_terminal_posture
                    = `Implemented_unavailable
                 && abandonment_inventory_terminal_posture
                    = `Implemented_unavailable);

              let prepared_inventory =
                prepare_dispatch_inventory lifecycle
                  ~manifest:(owner_identity "manifest-current")
                  ~recovery_attempt:(owner_identity "attempt-one")
                  ~challenge:(owner_identity "challenge-one")
                  ~transition:(owner_identity "transition-one")
                |> get "prepare dispatch inventory"
              in
              check "D13 inventory is owner-derived prepared and nonauthorizing"
                (String.length
                   (Dependability_owner_inventory.prepared_fragment_digest
                      prepared_inventory)
                 = 64);

              let drained = drain_once lifecycle |> get "drain" in
              let drained_replay = drain_once lifecycle |> get "replay drain" in
              check "D14 drain is monotone replay-stable and fences later claim reads"
                (drain_receipt_digest drained = drain_receipt_digest drained_replay
                 && drain_replayed drained_replay
                 && check_unavailable "owner-not-active" Control
                      (read_dispatch claim_role key));
              let closed = close_once lifecycle drained |> get "close" in
              let closed_replay =
                close_once lifecycle drained |> get "replay close"
              in
              check "D15 close is cleanup-bound and replay-stable"
                (close_receipt_digest closed = close_receipt_digest closed_replay
                 && close_replayed closed_replay)));

  check "D16 source authority kills every named dispatch-store mutant"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
             source_digest <> For_test.source_digest_with_mutation mutation)
          [ For_test.Drop_role_separation;
            Permit_production_without_lock;
            Drop_nominal_open_fence;
            Drop_session_attempt_fence;
            Overwrite_dispatch;
            Drop_request_replay_check;
            Drop_pointer_cas;
            Skip_current_readback;
            Forge_decision;
            Forge_abandonment;
            Forge_conditional_inventory;
            Forge_abandonment_inventory;
            Skip_restart_inventory_readback;
            Forge_inventory_current ]);

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_dispatch_store"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_dispatch_store ]);
  exit (Suite_telemetry.exit_code self)
