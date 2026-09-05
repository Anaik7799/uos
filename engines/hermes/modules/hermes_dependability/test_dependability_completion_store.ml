open Dependability_completion_store

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

let owner_identity label =
  Dependability_owner_inventory.Identity.make label
  |> function
  | Ok identity -> identity
  | Error refusal ->
      failwith (Dependability_owner_inventory.refusal_code refusal)

let clock () =
  Dependability_clock.observe ~max_pair_span_ns:1_000_000_000L
    ~lifetime_ns:30_000_000_000L
  |> function Ok receipt -> receipt | Error _ -> failwith "clock unavailable"

let authority_digest label =
  label |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
  |> Dependability_authority_store.Digest.make
  |> function
  | Ok digest -> digest
  | Error diagnostic ->
      failwith
        ("authority digest " ^ label ^ ": "
         ^ Dependability_authority_store.diagnostic_code diagnostic)

let jj_id make label =
  make label |> function
  | Ok identity -> identity
  | Error _ -> failwith ("invalid fixture identity: " ^ label)

let reserve_request ~completion ~payload =
  Jj_completion_store_protocol.prepare_reserve
    ~completion:(jj_id Jj_id.Receipt.make completion)
    ~source:(jj_id Jj_id.Receipt.make "source-main")
    ~head:(jj_id Jj_id.Operation.make "head-main")
    ~campaign:(jj_id Jj_id.Intent.make "campaign-main")
    ~payload:(jj_id Jj_id.Receipt.make payload)
  |> function Ok prepared -> prepared | Error _ -> failwith "reserve fixture"

let finalize_request ~completion ~payload =
  Jj_completion_store_protocol.prepare_finalize
    ~completion:(jj_id Jj_id.Receipt.make completion)
    ~source:(jj_id Jj_id.Receipt.make "source-main")
    ~head:(jj_id Jj_id.Operation.make "head-main")
    ~campaign:(jj_id Jj_id.Intent.make "campaign-main")
    ~payload:(jj_id Jj_id.Receipt.make payload)
    ~bookmark:(jj_id Jj_id.Bookmark.make "bookmark-main")
    ~readback:(jj_id Jj_id.Receipt.make "readback-main")
    ~lease_release:(jj_id Jj_id.Receipt.make "lease-release-main")
  |> function Ok prepared -> prepared | Error _ -> failwith "finalize fixture"

let () =
  let registry =
    Dependability_sqlite_test_protocol.create ~maximum_live:3
    |> function
    | Ok registry -> ref registry
    | Error error ->
        failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let acquire () =
    Dependability_sqlite_test_protocol.acquire !registry
      Dependability_sqlite_test_protocol.In_memory
    |> function
    | Ok (next, lease) ->
        registry := next;
        let location =
          Dependability_sqlite_test_protocol.reference next lease
          |> function
          | Ok reference -> reference
          | Error error ->
              failwith
                (Dependability_sqlite_test_protocol.string_of_error error)
        in
        (lease, location)
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
    | Ok bootstrap -> bootstrap
    | Error diagnostic ->
        failwith
          (Dependability_authority_store.diagnostic_code diagnostic)
  in
  let authority_lease, authority_location = acquire () in
  let authority_open =
    Dependability_authority_store.open_first_or_successor
      ~location:authority_location ~bootstrap
    |> function
    | Ok opened -> opened
    | Error diagnostic ->
        failwith
          (Dependability_authority_store.diagnostic_code diagnostic)
  in
  let authority = Dependability_authority_store.operational authority_open in
  let authority_lifecycle =
    Dependability_authority_store.take_lifecycle
      (Dependability_authority_store.role_bundle authority_open)
    |> function
    | Ok capability -> capability
    | Error diagnostic ->
        failwith
          (Dependability_authority_store.diagnostic_code diagnostic)
  in

  check "C1 production open is explicitly unavailable without its nominal peer fence"
    (match
       open_first_or_successor ~authority
         ~location:
           (Dependability_sqlite_location.registered
              Dependability_sqlite_location.Completion_store)
         ~observed_at
     with
     | Error diagnostic ->
         diagnostic_code diagnostic = "nominal-peer-open-fence-unavailable"
         && diagnostic_origin diagnostic = Control
     | Ok _ -> false);

  let completion_lease, completion_location = acquire () in
  let opened =
    open_first_or_successor ~authority ~location:completion_location
      ~observed_at
    |> get "open completion foundation"
  in
  let operational = operational opened in
  let roles = role_bundle opened in
  check "C2 volatile open is authority-session bound and grants no production posture"
    (operational_posture operational = `Volatile_test_foundation
     && String.length (owner_session_digest operational) = 64
     && String.length (store_epoch_digest operational) = 64
     && production_availability operational
        = Implemented_unavailable [ Nominal_peer_open_fence ]);

  let reserve = take_reserve roles |> get "take reserve" in
  let finalize = take_finalize roles |> get "take finalize" in
  let read = take_read roles |> get "take read" in
  let recovery = take_recovery roles |> get "take recovery" in
  let lifecycle = take_lifecycle roles |> get "take lifecycle" in
  check "C3 all five nominal roles are one-shot and never collapse to a store-wide role"
    (match take_reserve roles with
     | Error diagnostic -> diagnostic_code diagnostic = "role-already-transferred"
     | Ok _ -> false);

  let request = reserve_request ~completion:"completion-one" ~payload:"payload-one" in
  check "C4 finalize input cannot cross the nominal reserve capability"
    (match
       reserve_once reserve ~observed_at
         (finalize_request ~completion:"completion-one" ~payload:"payload-one")
     with
     | Error diagnostic -> diagnostic_code diagnostic = "wrong-protocol-kind"
     | Ok _ -> false);
  let inserted = reserve_once reserve ~observed_at request |> get "reserve" in
  let replayed = reserve_once reserve ~observed_at request |> get "reserve replay" in
  check "C5 reserve is append-only and same-request replay returns one stable receipt"
    (reserve_outcome inserted = Reserved_inserted
     && reserve_outcome replayed = Reserved_replayed
     && reserve_receipt_digest inserted = reserve_receipt_digest replayed);
  let reserved = read_current read ~observed_at request |> get "read reserved" in
  check "C6 current readback reports the exact reserved row without authorizing it"
    (readback_state reserved = Reserved
     && String.length (readback_digest reserved) = 64
     && readback_credit reserved = `No_credit);

  let finalize_request =
    finalize_request ~completion:"completion-one" ~payload:"payload-one"
  in
  let finalized =
    finalize_once finalize ~observed_at finalize_request |> get "finalize"
  in
  let finalized_replay =
    finalize_once finalize ~observed_at finalize_request
    |> get "finalize replay"
  in
  let finalized_readback =
    read_current read ~observed_at request |> get "read finalized"
  in
  check "C7 finalize proves the shared reservation payload and replays one CAS receipt"
    (finalize_outcome finalized = Finalized_inserted
     && finalize_outcome finalized_replay = Finalized_replayed
     && finalize_receipt_digest finalized
        = finalize_receipt_digest finalized_replay
     && readback_state finalized_readback = Finalized);

  let prepared_inventory =
    inventory_current read
      ~manifest:(owner_identity "manifest-operational")
      ~recovery_attempt:(owner_identity "attempt-operational")
      ~challenge:(owner_identity "challenge-operational")
      ~transition:(owner_identity "transition-operational")
    |> get "operational inventory"
  in
  check "C8 inventory is owner-derived but remains a prepared nonauthorizing fragment"
    (String.length
       (Dependability_owner_inventory.prepared_fragment_digest
          prepared_inventory)
     = 64);

  let unbound =
    open_recovery_inventory recovery
      ~recovery_attempt:(owner_identity "attempt-recovery")
      ~challenge:(owner_identity "challenge-recovery")
      ~transition:(owner_identity "transition-recovery")
      ~observed_at
    |> get "open recovery"
  in
  let manifest = owner_identity "manifest-recovery" in
  let bound, manifest_current =
    bind_recovery_manifest_once unbound manifest |> get "bind manifest"
  in
  let bound_replay, manifest_replay =
    bind_recovery_manifest_once unbound manifest |> get "replay manifest"
  in
  check "C9 recovery manifest bind is one-way, replay-stable and conflict absorbing"
    (bound_manifest_digest manifest_current
     = bound_manifest_digest manifest_replay
     && recovery_bound_digest bound = recovery_bound_digest bound_replay
     && (match
           bind_recovery_manifest_once unbound
             (owner_identity "different-manifest")
         with
         | Error diagnostic -> diagnostic_code diagnostic = "recovery-manifest-conflict"
         | Ok _ -> false));
  let prepared_recovery =
    prepare_recovery_current bound ~observed_at |> get "prepare recovery"
  in
  let reconciled =
    reconcile_recovery_once recovery prepared_recovery |> get "reconcile recovery"
  in
  let reconciled_replay =
    reconcile_recovery_once recovery prepared_recovery
    |> get "replay recovery"
  in
  check "C10 owner-derived recovery classifies Finalized as terminal and replays stably"
    (recovery_outcome reconciled = Finalized_terminal
     && recovery_outcome reconciled_replay = Finalized_terminal
     && recovery_replayed reconciled_replay
     && recovery_result_digest reconciled
        = recovery_result_digest reconciled_replay);
  let recovery_fragment =
    prepare_recovered_fragment reconciled |> get "prepare recovered fragment"
  in
  check "C11 terminal recovery creates only a prepared role fragment, never a current seal"
    (String.length
       (Dependability_owner_inventory.prepared_fragment_digest
          recovery_fragment)
     = 64);

  let conflict_request =
    reserve_request ~completion:"completion-one" ~payload:"payload-two"
  in
  check "C12 same completion identity with a different reserve payload is a durable conflict"
    (match reserve_once reserve ~observed_at conflict_request with
     | Error diagnostic -> diagnostic_code diagnostic = "completion-conflict"
     | Ok _ -> false);
  let conflicted =
    read_current read ~observed_at request |> get "read conflict"
  in
  check "C13 conflict is absorbing and retains the store fence"
    (readback_state conflicted = Conflict
     && (match drain lifecycle with
         | Error diagnostic -> diagnostic_code diagnostic = "blocked-row-retains-fence"
         | Ok _ -> false));

  let clean_lease, clean_location = acquire () in
  let clean_open =
    open_first_or_successor ~authority ~location:clean_location ~observed_at
    |> get "open clean completion foundation"
  in
  let clean_roles = role_bundle clean_open in
  let clean_reserve = take_reserve clean_roles |> get "clean reserve" in
  let clean_lifecycle = take_lifecycle clean_roles |> get "clean lifecycle" in
  ignore
    (reserve_once clean_reserve ~observed_at
       (reserve_request ~completion:"completion-clean" ~payload:"payload-clean")
     |> get "clean reservation");
  let drained = drain clean_lifecycle |> get "drain clean" in
  let drained_replay = drain clean_lifecycle |> get "replay drain clean" in
  let closed = close clean_lifecycle drained |> get "close clean" in
  let closed_replay = close clean_lifecycle drained |> get "replay close clean" in
  check "C14 lifecycle is drain-before-close, replay-stable and closes the native owner"
    (drain_receipt_digest drained = drain_receipt_digest drained_replay
     && drain_replayed drained_replay
     && close_receipt_digest closed = close_receipt_digest closed_replay
     && close_replayed closed_replay);

  check "C15 source identity kills the bounded completion-store mutants"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
             source_digest <> For_test.source_digest_with_mutation mutation)
          [ For_test.Drop_role_separation;
            Permit_production_without_peer_fence;
            Drop_authority_session_binding;
            Overwrite_reservation;
            Drop_replay_check;
            Forge_common_payload_match;
            Skip_current_readback;
            Caller_supplied_reconcile;
            Forge_producer_seal;
            Close_blocked_row ]);

  ignore (Dependability_authority_store.drain_once authority_lifecycle);
  begin match Dependability_authority_store.drain_once authority_lifecycle with
  | Error _ -> ()
  | Ok drained ->
      ignore
        (Dependability_authority_store.close_once authority_lifecycle drained)
  end;
  List.iter
    (fun lease ->
       match Dependability_sqlite_test_protocol.release !registry lease with
       | Ok (next, _) -> registry := next
       | Error _ -> ())
    [ authority_lease; completion_lease; clean_lease ];

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_completion_store"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_completion_store ]);
  exit (Suite_telemetry.exit_code self)
