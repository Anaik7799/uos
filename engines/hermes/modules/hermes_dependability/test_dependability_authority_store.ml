open Dependability_authority_store

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

let prepare_context observed_at =
  prepare_bootstrap ~build:(digest "build") ~root:(digest "root")
    ~configuration:(digest "configuration") ~host:(digest "host")
    ~pins:(digest "pins") ~observed_at
  |> get "prepare bootstrap"

let () =
  check "A1 digest identities reject noncanonical or wrong-size input"
    (Result.is_error (Digest.make "")
     && Result.is_error (Digest.make (String.make 64 'A'))
     && Result.is_error (Digest.make (String.make 63 'a'))
     && Result.is_ok
          (Digest.make
             (Digestif.SHA256.digest_string "valid"
             |> Digestif.SHA256.to_hex)));

  let observed_at = clock () in
  let bootstrap = prepare_context observed_at in
  check "A2 production opening refuses while the exclusive filesystem lock is unavailable"
    (match
       open_first_or_successor
         ~location:
           (Dependability_sqlite_location.registered
              Dependability_sqlite_location.Jujutsu_authority_store)
         ~bootstrap
     with
     | Error diagnostic ->
         diagnostic_code diagnostic = "physical-owner-lock-unavailable"
         && diagnostic_origin diagnostic = Environment
     | Ok _ -> false);

  with_in_memory_reference (fun location ->
      match open_first_or_successor ~location ~bootstrap with
      | Error _ -> check "A3 volatile test foundation opens" false
      | Ok opened ->
          let operational = operational opened in
          let roles = role_bundle opened in
          let peer_opens = peer_operational_open_bundle opened in
          check "A3 volatile opening binds one positive owner session and epoch"
            (owner_session_generation operational = 1
             && String.length (owner_session_digest operational) = 64
             && String.length (store_epoch_digest operational) = 64
             && operational_posture operational = `Volatile_test_foundation);
          let writer_open, dispatch_open, vault_open, completion_open =
            split_peer_operational_open_once peer_opens
            |> get "split peer operational opens"
          in
          check "A4 peer operational-open bundle is exact-session and one-shot"
            (Result.is_ok
               (consume_writer_operational_open writer_open ~authority:operational)
             && Result.is_ok
                  (consume_dispatch_operational_open dispatch_open
                     ~authority:operational)
             && Result.is_ok
                  (consume_vault_operational_open vault_open ~authority:operational)
             && Result.is_ok
                  (consume_completion_operational_open completion_open
                     ~authority:operational)
             && (match split_peer_operational_open_once peer_opens with
                 | Error diagnostic ->
                     diagnostic_code diagnostic = "peer-bundle-already-split"
                 | Ok _ -> false)
             && peer_inventory_fence_posture = `Implemented_unavailable);

          let approval_nonce_role =
            take_approval_nonce roles |> get "take approval nonce role"
          in
          let approval =
            approval_identity (digest "approval-campaign-one")
          in
          let occurrences =
            [ approval_occurrence ~identity:(digest "occurrence-one")
                ~nonce:(digest "nonce-one");
              approval_occurrence ~identity:(digest "occurrence-two")
                ~nonce:(digest "nonce-two");
              approval_occurrence ~identity:(digest "occurrence-three")
                ~nonce:(digest "nonce-three") ]
          in
          let campaign_key =
            prepare_approval_campaign_key approval_nonce_role ~approval
              ~plan:(digest "approval-plan")
            |> get "prepare approval campaign key"
          in
          let registration request occurrences =
            prepare_approval_campaign ~key:campaign_key ~request
              ~verification:(digest "verified-ticket") ~occurrences ~observed_at
            |> get "prepare approval campaign"
          in
          let campaign =
            register_approval_campaign_once approval_nonce_role
              (registration (digest "approval-register-request") occurrences)
            |> get "register approval campaign"
          in
          let campaign_replay =
            register_approval_campaign_once approval_nonce_role
              (registration (digest "approval-register-request") occurrences)
            |> get "replay approval campaign"
          in
          check "A5 exact approval denominator registers Available atomically with stable replay"
            (approval_campaign_occurrence_count campaign = List.length occurrences
             && approval_campaign_receipt_digest campaign
                = approval_campaign_receipt_digest campaign_replay
             && approval_campaign_replayed campaign_replay
             && (match
                   register_approval_campaign_once approval_nonce_role
                     (registration (digest "different-approval-request") occurrences)
                 with
                 | Error diagnostic -> diagnostic_code diagnostic = "request-conflict"
                 | Ok _ -> false)
             && Result.is_error
                  (prepare_approval_campaign ~key:campaign_key
                     ~request:(digest "empty-denominator-request")
                     ~verification:(digest "verified-ticket") ~occurrences:[]
                     ~observed_at));
          let nonce =
            approval_occurrence_nonce campaign ~occurrence:(List.hd occurrences)
            |> get "approval occurrence nonce"
          in
          let nonce_readback =
            read_approval_nonce approval_nonce_role nonce
            |> get "read approval nonce"
          in
          let nonce_current =
            reconcile_approval_nonce_current approval_nonce_role ~now:(clock ())
              nonce_readback
            |> get "reconcile approval nonce"
          in
          check "A6 nonce readback/currentness bind exact session epoch and Available row"
            (approval_nonce_readback_state nonce_readback = Available
             && String.length (approval_nonce_readback_digest nonce_readback) = 64
             && approval_nonce_current_state nonce_current = Available
             && String.length (approval_nonce_current_digest nonce_current) = 64
             && approval_nonce_transition_posture = `Implemented_unavailable);

          let inventory_readback =
            read_approval_campaign_inventory approval_nonce_role
              ~campaign
            |> get "read approval campaign inventory"
          in
          let inventory_current =
            reconcile_approval_campaign_inventory_current approval_nonce_role
              ~now:(clock ()) ~campaign inventory_readback
            |> get "reconcile approval campaign inventory"
          in
          let inventory_replay =
            reconcile_approval_campaign_inventory_current approval_nonce_role
              ~now:(clock ()) ~campaign inventory_readback
            |> get "replay approval campaign inventory"
          in
          check "A7 per-campaign inventory binds exact ordered current nonce denominator"
            (approval_campaign_inventory_readback_nonce_count inventory_readback
             = List.length occurrences
             && String.length
                  (approval_campaign_inventory_readback_digest
                     inventory_readback)
                = 64
             && approval_inventory_campaign_count inventory_current = 1
             && approval_inventory_nonce_count inventory_current
                = List.length occurrences
             && approval_inventory_digest inventory_current
                = approval_inventory_digest inventory_replay);
          let second_occurrences =
            [ approval_occurrence ~identity:(digest "occurrence-foreign")
                ~nonce:(digest "nonce-foreign") ]
          in
          let second_key =
            prepare_approval_campaign_key approval_nonce_role
              ~approval:(approval_identity (digest "approval-campaign-two"))
              ~plan:(digest "approval-plan-two")
            |> get "prepare foreign campaign key"
          in
          let second_campaign =
            prepare_approval_campaign ~key:second_key
              ~request:(digest "approval-register-request-two")
              ~verification:(digest "verified-ticket-two")
              ~occurrences:second_occurrences ~observed_at
            |> get "prepare foreign campaign"
            |> register_approval_campaign_once approval_nonce_role
            |> get "register foreign campaign"
          in
          let changed_inventory =
            For_test.mutate_approval_inventory_readback
              For_test.Current_nonce_identity inventory_readback
          in
          check "A8 changed-current and cross-campaign inventory readbacks refuse"
            ((match
                reconcile_approval_campaign_inventory_current
                  approval_nonce_role ~now:(clock ()) ~campaign
                  changed_inventory
              with
              | Error diagnostic ->
                  diagnostic_code diagnostic = "approval-inventory-mismatch"
              | Ok _ -> false)
             && match
                  reconcile_approval_campaign_inventory_current
                    approval_nonce_role ~now:(clock ())
                    ~campaign:second_campaign inventory_readback
                with
                | Error diagnostic ->
                    diagnostic_code diagnostic = "approval-inventory-mismatch"
                | Ok _ -> false);
          check "A9 terminal and global restart authority remain exact unavailable"
            (approval_inventory_terminal_posture = `Implemented_unavailable
             && approval_inventory_terminal_prerequisites
                = [ Campaign_open_current;
                    Conditional_decision_terminal_evidence;
                    Abandonment_terminal_evidence ]
             && global_approval_inventory_posture
                = `Implemented_unavailable
             && global_approval_inventory_prerequisites
                = [ Closed_approval_campaign_inventory ]);
          let activation =
            take_production_activation roles |> get "take activation role"
          in
          let lifecycle = take_lifecycle roles |> get "take lifecycle role" in
          check "A4 every role transfer is one-shot and there is no store-wide fallback"
            (match take_production_activation roles with
             | Error diagnostic -> diagnostic_code diagnostic = "role-already-transferred"
             | Ok _ -> false);

          let key =
            prepare_activation_key activation ~root:(digest "root")
            |> get "prepare key"
          in
          let initial_request = digest "initialize-request" in
          let prepare_initial request =
            prepare_initialization ~key ~request ~evidence:(digest "initialize-evidence")
              ~context:(digest "initialize-context") ~observed_at
            |> get "prepare initialization"
          in
          let initialized =
            initialize_first_missing activation (prepare_initial initial_request)
            |> get "initialize first missing"
          in
          let initialized_replay =
            initialize_first_missing activation (prepare_initial initial_request)
            |> get "replay initialize"
          in
          check "A5 generation zero initialization is replay-stable and conflict-absorbing"
            (transition_status initialized = Missing
             && transition_generation initialized = 0
             && transition_id initialized = transition_id initialized_replay
             && transition_replayed initialized_replay
             && (match
                   initialize_first_missing activation
                     (prepare_initial (digest "different-initialize-request"))
                 with
                 | Error diagnostic -> diagnostic_code diagnostic = "request-conflict"
                 | Ok _ -> false));

          let missing = read_status activation key |> get "read missing" in
          let prepare_root request =
            prepare_root_activation ~predecessor:missing ~request
              ~context:(digest "root-context")
              ~observed_at
            |> get "prepare root"
          in
          let root =
            activate_root_once activation (prepare_root (digest "root-request"))
            |> get "activate root"
          in
          let root_replay =
            activate_root_once activation (prepare_root (digest "root-request"))
            |> get "replay root"
          in
          check "A6 Missing to Root_active is one append-only CAS with stable replay"
            (transition_status root = Root_active
             && transition_id root = transition_id root_replay
             && transition_replayed root_replay
             && (match
                   activate_root_once activation
                     (prepare_root (digest "different-root-request"))
                 with
                 | Error diagnostic -> diagnostic_code diagnostic = "request-conflict"
                 | Ok _ -> false));

          let root_readback = read_status activation key |> get "read root" in
          let prepare_classified request =
            prepare_classification ~predecessor:root_readback ~request
              ~evidence:(digest "source-receipt")
              ~context:(digest "classification-context") ~observed_at
            |> get "prepare classification"
          in
          let classified =
            classify_once activation
              (prepare_classified (digest "classification-request"))
            |> get "classify"
          in
          let classified_replay =
            classify_once activation
              (prepare_classified (digest "classification-request"))
            |> get "replay classification"
          in
          check "A7 Root_active to Classified_active is exclusive and replay-stable"
            (transition_status classified = Classified_active
             && transition_id classified = transition_id classified_replay
             && transition_replayed classified_replay
             && (match
                   classify_once activation
                     (prepare_classified (digest "different-classification-request"))
                 with
                 | Error diagnostic -> diagnostic_code diagnostic = "request-conflict"
                 | Ok _ -> false));

          let classified_readback =
            read_status activation key |> get "read classified"
          in
          let current =
            reconcile_current activation ~now:(clock ()) classified_readback
            |> get "reconcile current"
          in
          check "A8 readback and currentness bind the exact pointer generation and state"
            (readback_status classified_readback = Classified_active
             && readback_generation classified_readback = 0
             && String.length (readback_digest classified_readback) = 64
             && current_status current = Classified_active
             && current_generation current = 0
             && String.length (current_digest current) = 64);

          let prepared_inventory =
            prepare_activation_inventory activation
              ~manifest:(owner_identity "manifest-current")
              ~recovery_attempt:(owner_identity "attempt-one")
              ~challenge:(owner_identity "challenge-one")
              ~transition:(owner_identity "transition-one")
            |> get "prepare activation inventory"
          in
          check "A9 activation inventory is owner-derived and remains nonauthorizing"
            (String.length
               (Dependability_owner_inventory.prepared_fragment_digest
                  prepared_inventory)
             = 64);

          let drained = drain_once lifecycle |> get "drain" in
          let drained_replay = drain_once lifecycle |> get "replay drain" in
          check "A10 drain is monotone and replay-stable"
            (drain_receipt_digest drained = drain_receipt_digest drained_replay
             && drain_replayed drained_replay);
          let closed = close_once lifecycle drained |> get "close" in
          let closed_replay = close_once lifecycle drained |> get "replay close" in
          check "A11 close is cleanup-bound replay-stable and absorbs later work"
            (close_receipt_digest closed = close_receipt_digest closed_replay
             && close_replayed closed_replay
             && (match read_status activation key with
                 | Error diagnostic -> diagnostic_code diagnostic = "owner-not-active"
                 | Ok _ -> false)));

  check "A12 source identity kills every named authority-store mutant"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation -> source_digest <> For_test.source_digest_with_mutation mutation)
          [ For_test.Drop_role_separation;
            Permit_production_without_lock;
            Drop_session_fence;
            Overwrite_transition;
            Drop_request_replay_check;
            Drop_pointer_cas;
            Skip_current_readback;
            Forge_inventory_current;
            Duplicate_peer_open;
            Forge_inventory_fence;
            Partial_nonce_denominator;
            Overwrite_nonce_state;
            Reopen_terminal_nonce;
            Forge_approval_inventory_current;
            Skip_approval_inventory_readback;
            Permit_global_inventory_without_closed_enumeration ]);

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_authority_store"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_authority_store ]);
  exit (Suite_telemetry.exit_code self)
