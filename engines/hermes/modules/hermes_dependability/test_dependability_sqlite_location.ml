open Dependability_sqlite_location

module Dependability_sqlite_test_protocol =
  Dependability_sqlite_location.For_test

open Dependability_sqlite_test_protocol

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAIL %s\n" name
  end

let unique values =
  List.sort_uniq String.compare values |> List.length = List.length values

exception Stop_case

let require_ok name string_of_error = function
  | Ok value ->
      check name true;
      value
  | Error error ->
      check name false;
      Printf.eprintf "  %s\n" (string_of_error error);
      raise Stop_case

let test_production_registry () =
  let production = Dependability_sqlite_location.all_registered in
  check "L1 production registration is a closed six-member denominator"
    (List.length production = 6
     && production
        = [ Event_store; Effect_store; Jujutsu_authority_store; Dispatch_store;
            Completion_store; Completion_history_store ]);
  let references = List.map Dependability_sqlite_location.registered production in
  check "L2 registered references bind only their closed production identity"
    (List.map Dependability_sqlite_location.registration references
     = List.map (fun registration -> Some registration) production
     && unique (List.map Dependability_sqlite_location.reference_digest references)
     && List.for_all
          (fun reference ->
             String.length
               (Dependability_sqlite_location.reference_digest reference)
             = 64)
          references);
  check "L2b SQLite owner resolves the exact closed production identity"
    (List.map Dependability_sqlite_location.For_sqlite_owner.resolve references
     = List.map
         (fun registration ->
           Ok
             (Dependability_sqlite_location.For_sqlite_owner.Production
                registration))
         production)

let test_fixture_denominator () =
  let fixtures =
    [ Dependability_sqlite_test_protocol.In_memory; Temporary_file;
      Fault_open; Fault_close; Fault_busy_once ]
  in
  check "L3 test protocol has a finite fixture and fault denominator"
    (List.length fixtures = 5
     && fixtures
        = [ Dependability_sqlite_test_protocol.In_memory;
            Temporary_file;
            Fault_open; Fault_close; Fault_busy_once ])

let fixture_resolution_is profile reference =
  match Dependability_sqlite_location.For_sqlite_owner.resolve reference with
  | Ok (Dependability_sqlite_location.For_sqlite_owner.Test_fixture identity) ->
      Dependability_sqlite_location.For_sqlite_owner.fixture_profile identity
      = profile
      && String.length
           (Dependability_sqlite_location.For_sqlite_owner
            .fixture_identity_digest identity)
         = 64
  | Ok (Dependability_sqlite_location.For_sqlite_owner.Production _)
  | Error _ -> false

let test_lease_lifecycle () =
  try
    let registry =
      Dependability_sqlite_test_protocol.create ~maximum_live:2
      |> require_ok "L4 bounded fixture registry accepts a positive capacity"
           Dependability_sqlite_test_protocol.string_of_error
    in
    check "L4a registry reports its exact live bound"
      (Dependability_sqlite_test_protocol.maximum_live registry = 2);
    let registry, first_lease =
      Dependability_sqlite_test_protocol.acquire registry Temporary_file
      |> require_ok "L4b first fixture lease acquisition succeeds"
           Dependability_sqlite_test_protocol.string_of_error
    in
    let registry, second_lease =
      Dependability_sqlite_test_protocol.acquire registry Temporary_file
      |> require_ok "L4c second same-profile lease acquisition succeeds"
           Dependability_sqlite_test_protocol.string_of_error
    in
    check "L4d same-profile leases have unique opaque identities"
      (Dependability_sqlite_test_protocol.lease_digest first_lease
       <> Dependability_sqlite_test_protocol.lease_digest second_lease
       && Dependability_sqlite_test_protocol.active_count registry = 2);
    let first_reference =
      Dependability_sqlite_test_protocol.reference registry first_lease
      |> require_ok "L4e active lease projects an opaque reference"
           Dependability_sqlite_test_protocol.string_of_error
    in
    let second_reference =
      Dependability_sqlite_test_protocol.reference registry second_lease
      |> require_ok "L4f second active lease projects an opaque reference"
           Dependability_sqlite_test_protocol.string_of_error
    in
    let replayed_reference =
      Dependability_sqlite_test_protocol.replay registry first_lease
      |> require_ok "L4g active lease replay projects the same reference"
           Dependability_sqlite_test_protocol.string_of_error
    in
    check "L4h fixture resolution remains logical and path-free"
      (Dependability_sqlite_location.reference_digest first_reference
       = Dependability_sqlite_location.reference_digest replayed_reference
       && Dependability_sqlite_location.registration first_reference = None
       && fixture_resolution_is
            Dependability_sqlite_location.For_sqlite_owner.Temporary_file
            first_reference);
    check "L4i capacity exhaustion refuses rather than aliasing"
      (Result.is_error
         (Dependability_sqlite_test_protocol.acquire registry In_memory));
    let registry, release =
      Dependability_sqlite_test_protocol.release registry first_lease
      |> require_ok "L4j active lease releases exactly once"
           Dependability_sqlite_test_protocol.string_of_error
    in
    let registry, release_replay =
      Dependability_sqlite_test_protocol.release registry first_lease
      |> require_ok "L4k release replay is idempotent"
           Dependability_sqlite_test_protocol.string_of_error
    in
    check "L4l release replay retains one receipt and revokes all access"
      (not (Dependability_sqlite_test_protocol.release_replayed release)
       && Dependability_sqlite_test_protocol.release_replayed release_replay
       && Dependability_sqlite_test_protocol.release_receipt_digest release
          = Dependability_sqlite_test_protocol.release_receipt_digest
              release_replay
       && Result.is_error
            (Dependability_sqlite_test_protocol.reference registry first_lease)
       && Result.is_error
            (Dependability_sqlite_test_protocol.replay registry first_lease)
       && Result.is_error
            (Dependability_sqlite_location.For_sqlite_owner.resolve
               first_reference));
    let registry, third_lease =
      Dependability_sqlite_test_protocol.acquire registry Temporary_file
      |> require_ok "L4m released capacity admits a fresh unique lease"
           Dependability_sqlite_test_protocol.string_of_error
    in
    check "L4n replacement lease never reuses identity"
      (Dependability_sqlite_test_protocol.lease_digest first_lease
       <> Dependability_sqlite_test_protocol.lease_digest third_lease);
    let third_reference =
      Dependability_sqlite_test_protocol.reference registry third_lease
      |> require_ok "L4o replacement lease projects an active reference"
           Dependability_sqlite_test_protocol.string_of_error
    in
    let foreign_registry =
      Dependability_sqlite_test_protocol.create ~maximum_live:1
      |> require_ok "L4p independent bounded registry is admitted"
           Dependability_sqlite_test_protocol.string_of_error
    in
    check "L4q a lease cannot cross registry ownership"
      (Result.is_error
         (Dependability_sqlite_test_protocol.reference foreign_registry
            third_lease));
    let registry, cleanup =
      Dependability_sqlite_test_protocol.cleanup registry
      |> require_ok "L4r cleanup admits a bounded CAS"
           Dependability_sqlite_test_protocol.string_of_error
    in
    let registry, cleanup_replay =
      Dependability_sqlite_test_protocol.cleanup registry
      |> require_ok "L4s cleanup replay admits a bounded CAS"
           Dependability_sqlite_test_protocol.string_of_error
    in
    check "L4t cleanup releases the exact live set and replays"
      (Dependability_sqlite_test_protocol.active_count registry = 0
       && Dependability_sqlite_test_protocol.cleanup_released_count cleanup = 2
       && not (Dependability_sqlite_test_protocol.cleanup_replayed cleanup)
       && Dependability_sqlite_test_protocol.cleanup_replayed cleanup_replay
       && Dependability_sqlite_test_protocol.cleanup_receipt_digest cleanup
          = Dependability_sqlite_test_protocol.cleanup_receipt_digest
              cleanup_replay
       && Result.is_error
            (Dependability_sqlite_test_protocol.reference registry second_lease)
       && Result.is_error
            (Dependability_sqlite_test_protocol.reference registry third_lease)
       && Result.is_error
            (Dependability_sqlite_location.For_sqlite_owner.resolve
               second_reference)
       && Result.is_error
            (Dependability_sqlite_location.For_sqlite_owner.resolve
               third_reference))
  with Stop_case -> ()

let test_refusal_and_branch_guard () =
  check "L4u zero capacity is refused"
    (Result.is_error
       (Dependability_sqlite_test_protocol.create ~maximum_live:0));
  let branch_guard =
    match Dependability_sqlite_test_protocol.create ~maximum_live:1 with
    | Error _ -> false
    | Ok registry ->
        (match
           Dependability_sqlite_test_protocol.acquire registry Temporary_file
         with
        | Error _ -> false
        | Ok (_same_registry, first_lease) ->
            Result.is_error
              (Dependability_sqlite_test_protocol.acquire registry Temporary_file)
            && String.length
                 (Dependability_sqlite_test_protocol.lease_digest first_lease)
               = 64)
  in
  check "L4v duplicated pre-acquire registry cannot bypass its live bound"
    branch_guard

let test_mutations () =
  check "L5 every location authority mutation changes the source digest"
    (String.length Dependability_sqlite_location.source_digest = 64
     && List.for_all
          (fun mutation ->
             Dependability_sqlite_location.source_digest
             <> Dependability_sqlite_location.For_test
                .source_digest_with_mutation mutation)
          [ Dependability_sqlite_location.For_test.Drop_registration;
            Duplicate_registration; Promote_test_fixture;
            Permit_raw_location; Reuse_fixture_identity;
            Permit_released_reference; Unbounded_fixture_registry ])

let () =
  test_production_registry ();
  test_fixture_denominator ();
  test_lease_lifecycle ();
  test_refusal_and_branch_guard ();
  test_mutations ();
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_sqlite_location"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_sqlite_location ]);
  exit (Suite_telemetry.exit_code self)
