type registration =
  | Event_store
  | Effect_store
  | Jujutsu_authority_store
  | Dispatch_store
  | Completion_store
  | Completion_history_store

type fixture_profile_internal =
  | In_memory
  | Temporary_file
  | Fault_open
  | Fault_close
  | Fault_busy_once

type fixture_identity_internal = {
  profile : fixture_profile_internal;
  identity_digest : string;
  active : bool Atomic.t;
}

type provenance =
  | Production of registration
  | Test_fixture of fixture_identity_internal
type reference = { provenance : provenance; digest : string }

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let registration_key = function
  | Event_store -> "event-store"
  | Effect_store -> "effect-store"
  | Jujutsu_authority_store -> "jujutsu-authority-store"
  | Dispatch_store -> "dispatch-store"
  | Completion_store -> "completion-store"
  | Completion_history_store -> "completion-history-store"

let all_registered =
  [ Event_store; Effect_store; Jujutsu_authority_store; Dispatch_store;
    Completion_store; Completion_history_store ]

let authority_digest ?(registry = all_registered) ?(test_only = true)
    ?(raw_location_forbidden = true) ?(unique_fixture_identity = true)
    ?(released_reference_forbidden = true) ?(bounded_fixture_registry = true)
    () =
  length_frame
    [ "dependability-sqlite-location-authority-v1";
      "production-registry";
      length_frame (List.map registration_key registry);
      "test-fixtures-test-only"; string_of_bool test_only;
      "raw-path-filename-handle-sql-statement-finalizer";
      if raw_location_forbidden then "forbidden" else "permitted";
      "unique-fixture-identity"; string_of_bool unique_fixture_identity;
      "released-reference-forbidden";
      string_of_bool released_reference_forbidden;
      "bounded-fixture-registry"; string_of_bool bounded_fixture_registry ]
  |> sha256

let source_digest = authority_digest ()

let reference_of provenance key =
  { provenance;
    digest =
      length_frame
        [ "dependability-sqlite-location-reference-v1"; source_digest; key ]
      |> sha256 }

let registered registration =
  reference_of (Production registration) ("production:" ^ registration_key registration)

let registration reference =
  match reference.provenance with
  | Production registration -> Some registration
  | Test_fixture _ -> None

let reference_digest reference = reference.digest

module For_sqlite_owner = struct
  type fixture_profile = fixture_profile_internal =
    | In_memory
    | Temporary_file
    | Fault_open
    | Fault_close
    | Fault_busy_once

  type fixture_identity = fixture_identity_internal

  type resolved_identity =
    | Production of registration
    | Test_fixture of fixture_identity

  type resolution_error = Released_test_fixture

  let resolve reference =
    match reference.provenance with
    | Production registration -> Ok (Production registration)
    | Test_fixture identity when Atomic.get identity.active ->
        Ok (Test_fixture identity)
    | Test_fixture _ -> Error Released_test_fixture

  let fixture_profile identity = identity.profile
  let fixture_identity_digest identity = identity.identity_digest
end

module For_test = struct
  type fixture_tag = fixture_profile_internal =
    | In_memory
    | Temporary_file
    | Fault_open
    | Fault_close
    | Fault_busy_once

  type lease = {
    lease_registry_identity : int;
    lease_identity : int;
    lease_reference : reference;
    lease_digest_value : string;
  }

  type release_receipt = {
    release_registry_identity : int;
    release_lease_identity : int;
    release_digest_value : string;
  }

  type release_outcome =
    | Released of release_receipt
    | Release_replayed of release_receipt

  type cleanup_receipt = {
    cleanup_generation : int;
    cleanup_released_count_value : int;
    cleanup_digest_value : string;
  }

  type cleanup_outcome =
    | Cleaned of cleanup_receipt
    | Cleanup_replayed of cleanup_receipt

  type registry_state = {
    next_lease_identity : int;
    active : lease list;
    released : release_receipt list;
    cleanup_generation : int;
    last_cleanup : cleanup_receipt option;
  }

  type registry = {
    registry_identity : int;
    maximum_live_value : int;
    state : registry_state Atomic.t;
  }

  type error =
    | Invalid_maximum_live of int
    | Capacity_exhausted of { active : int; maximum : int }
    | Foreign_lease
    | Unknown_lease
    | Released_lease
    | Registry_contended of int

  let fixture_key = function
    | In_memory -> "in-memory"
    | Temporary_file -> "temporary-file"
    | Fault_open -> "fault-open"
    | Fault_close -> "fault-close"
    | Fault_busy_once -> "fault-busy-once"

  let next_registry_identity = Atomic.make 0
  let maximum_cas_attempts = 64

  let create ~maximum_live =
    if maximum_live <= 0 then Error (Invalid_maximum_live maximum_live)
    else
      let registry_identity =
        Atomic.fetch_and_add next_registry_identity 1 + 1
      in
      Ok
        { registry_identity; maximum_live_value = maximum_live;
          state =
            Atomic.make
              { next_lease_identity = 0; active = []; released = [];
                cleanup_generation = 0; last_cleanup = None } }

  let maximum_live registry = registry.maximum_live_value
  let active_count registry =
    let state = Atomic.get registry.state in
    List.length state.active

  let acquire registry fixture =
    let rec reserve attempts =
      if attempts >= maximum_cas_attempts then
        Error (Registry_contended attempts)
      else
      let before = Atomic.get registry.state in
      let active = List.length before.active in
      if active >= registry.maximum_live_value then
        Error
          (Capacity_exhausted
             { active; maximum = registry.maximum_live_value })
      else
        let lease_identity = before.next_lease_identity + 1 in
        let identity_digest =
          length_frame
            [ "dependability-sqlite-fixture-identity-v2"; source_digest;
              string_of_int registry.registry_identity;
              string_of_int lease_identity; fixture_key fixture ]
          |> sha256
        in
        let fixture_identity =
          { profile = fixture; identity_digest; active = Atomic.make true }
        in
        let lease_reference =
          reference_of (Test_fixture fixture_identity)
            ("test-fixture-identity:" ^ identity_digest)
        in
        let lease_digest_value =
          length_frame
            [ "dependability-sqlite-fixture-lease-v2"; identity_digest;
              reference_digest lease_reference ]
          |> sha256
        in
        let lease =
          { lease_registry_identity = registry.registry_identity; lease_identity;
            lease_reference; lease_digest_value }
        in
        let after =
          { before with next_lease_identity = lease_identity;
                        active = lease :: before.active;
                        last_cleanup = None }
        in
        if Atomic.compare_and_set registry.state before after then
          Ok (registry, lease)
        else begin
          Atomic.set fixture_identity.active false;
          reserve (attempts + 1)
        end
    in
    reserve 0

  let same_lease left right =
    left.lease_registry_identity = right.lease_registry_identity
    && left.lease_identity = right.lease_identity
    && left.lease_digest_value = right.lease_digest_value

  let find_active state lease =
    List.find_opt (fun candidate -> same_lease candidate lease) state.active

  let find_release state lease =
    List.find_opt
      (fun receipt ->
        receipt.release_registry_identity = lease.lease_registry_identity
        && receipt.release_lease_identity = lease.lease_identity)
      state.released

  let reference_is_current reference =
    match reference.provenance with
    | Production _ -> true
    | Test_fixture identity -> Atomic.get identity.active

  let reference registry lease =
    if lease.lease_registry_identity <> registry.registry_identity then
      Error Foreign_lease
    else begin
      let state = Atomic.get registry.state in
      match find_active state lease with
      | Some active when reference_is_current active.lease_reference ->
          Ok active.lease_reference
      | Some _ -> Error Released_lease
      | None ->
          if Option.is_some (find_release state lease) then
            Error Released_lease
          else Error Unknown_lease
    end

  let replay = reference

  let make_release_receipt registry lease =
    { release_registry_identity = registry.registry_identity;
      release_lease_identity = lease.lease_identity;
      release_digest_value =
        length_frame
          [ "dependability-sqlite-fixture-release-v2"; source_digest;
            lease.lease_digest_value ]
        |> sha256 }

  let revoke_fixture_reference lease =
    match lease.lease_reference.provenance with
    | Test_fixture identity -> Atomic.set identity.active false
    | Production _ -> ()

  let release registry lease =
    if lease.lease_registry_identity <> registry.registry_identity then
      Error Foreign_lease
    else
      let rec commit attempts =
        if attempts >= maximum_cas_attempts then
          Error (Registry_contended attempts)
        else
        let before = Atomic.get registry.state in
        match find_active before lease with
        | Some active ->
            revoke_fixture_reference active;
            let receipt = make_release_receipt registry active in
            let active =
              List.filter
                (fun candidate -> not (same_lease candidate lease))
                before.active
            in
            let after =
              { before with active; released = receipt :: before.released;
                            last_cleanup = None }
            in
            if Atomic.compare_and_set registry.state before after then
              Ok (registry, Released receipt)
            else commit (attempts + 1)
        | None ->
            (match find_release before lease with
            | Some receipt ->
                revoke_fixture_reference lease;
                Ok (registry, Release_replayed receipt)
            | None -> Error Unknown_lease)
      in
      commit 0

  let make_cleanup_receipt registry state active =
    let cleanup_generation = state.cleanup_generation + 1 in
    let lease_digests =
      List.map (fun lease -> lease.lease_digest_value) active
      |> List.sort String.compare
    in
    { cleanup_generation;
      cleanup_released_count_value = List.length active;
      cleanup_digest_value =
        length_frame
          ([ "dependability-sqlite-fixture-cleanup-v2"; source_digest;
             string_of_int registry.registry_identity;
             string_of_int cleanup_generation ]
           @ lease_digests)
        |> sha256 }

  let cleanup registry =
    let rec commit attempts =
      if attempts >= maximum_cas_attempts then
        Error (Registry_contended attempts)
      else
      let before = Atomic.get registry.state in
      match before.active, before.last_cleanup with
      | [], Some receipt ->
          if Atomic.compare_and_set registry.state before before then
            Ok (registry, Cleanup_replayed receipt)
          else commit (attempts + 1)
      | active, _ ->
          List.iter revoke_fixture_reference active;
          let cleanup_receipt = make_cleanup_receipt registry before active in
          let released_now =
            List.map (make_release_receipt registry) active
          in
          let after =
            { before with active = [];
                          released = released_now @ before.released;
                          cleanup_generation =
                            cleanup_receipt.cleanup_generation;
                          last_cleanup = Some cleanup_receipt }
          in
          if Atomic.compare_and_set registry.state before after then
            Ok (registry, Cleaned cleanup_receipt)
          else commit (attempts + 1)
    in
    commit 0

  let lease_digest lease = lease.lease_digest_value

  let release_replayed = function
    | Released _ -> false
    | Release_replayed _ -> true

  let release_receipt_digest = function
    | Released receipt | Release_replayed receipt -> receipt.release_digest_value

  let cleanup_replayed = function
    | Cleaned _ -> false
    | Cleanup_replayed _ -> true

  let cleanup_released_count = function
    | Cleaned receipt | Cleanup_replayed receipt ->
        receipt.cleanup_released_count_value

  let cleanup_receipt_digest = function
    | Cleaned receipt | Cleanup_replayed receipt -> receipt.cleanup_digest_value

  let string_of_error = function
    | Invalid_maximum_live maximum ->
        Printf.sprintf "invalid maximum live fixture leases: %d" maximum
    | Capacity_exhausted { active; maximum } ->
        Printf.sprintf "fixture lease capacity exhausted (%d/%d)" active maximum
    | Foreign_lease -> "fixture lease belongs to another registry"
    | Unknown_lease -> "fixture lease is unknown"
    | Released_lease -> "fixture lease was released"
    | Registry_contended attempts ->
        Printf.sprintf "fixture registry contended after %d attempts" attempts

  type mutation =
    | Drop_registration
    | Duplicate_registration
    | Promote_test_fixture
    | Permit_raw_location
    | Reuse_fixture_identity
    | Permit_released_reference
    | Unbounded_fixture_registry

  let source_digest_with_mutation = function
    | Drop_registration -> authority_digest ~registry:(List.tl all_registered) ()
    | Duplicate_registration ->
        authority_digest ~registry:(List.hd all_registered :: all_registered) ()
    | Promote_test_fixture -> authority_digest ~test_only:false ()
    | Permit_raw_location -> authority_digest ~raw_location_forbidden:false ()
    | Reuse_fixture_identity -> authority_digest ~unique_fixture_identity:false ()
    | Permit_released_reference ->
        authority_digest ~released_reference_forbidden:false ()
    | Unbounded_fixture_registry ->
        authority_digest ~bounded_fixture_registry:false ()
end
