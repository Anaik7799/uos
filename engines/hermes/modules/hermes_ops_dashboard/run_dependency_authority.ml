type diagnostic_code =
  | Durable_owner_unavailable
  | Invalid_binding
  | Invalid_redacted_evidence
  | Dependency_conflict
  | Dependency_expired
  | Dependency_binding_mismatch
  | Foreign_carrier
  | Dependency_capacity_exhausted

type diagnostic = {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type durable_owner_current = {
  owner_id : string;
  generation : int;
  owner_digest_value : string;
  owner_binding_digest : string;
}

type binding = {
  execution_identity : string;
  activity_digest : string;
  producer_action_id : string;
  consumer_action_id : string;
  request_digest : string;
  expires_at_ns : int64;
}

type evidence_disposition = Dependency_succeeded | Dependency_unavailable

type redacted_evidence = {
  disposition : evidence_disposition;
  evidence_digest : string;
}

type carrier = {
  carrier_lineage : unit ref;
  carrier_id : string;
  carrier_binding_digest : string;
  carrier_owner_digest : string;
}

type receipt = {
  receipt_id : string;
  binding_digest : string;
  owner_digest : string;
  evidence_digest : string;
  expires_at_ns : int64;
  was_replayed : bool;
}

type row = {
  row_binding : binding;
  row_evidence : redacted_evidence;
  row_carrier_id : string;
  row_receipt_id : string;
}

type registry = {
  lineage : unit ref;
  owner : durable_owner_current;
  rows : (string * row) list;
}

let production_posture = `Implemented_unavailable
let maximum_live_dependencies = 64

let coordinate =
  { Ops_capability.level = Ops_capability.L3; phase = Ops_capability.Act }

let diagnostic ?(origin = Ops_capability.Control) code message =
  { code; message; coordinate; rca_origin = origin;
    hazard_id = "HZ-DEPENDENCY-AUTHORITY-01" }

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = string_of_int (String.length value) ^ ":" ^ value
let digest_fields values = values |> List.map frame |> String.concat "" |> sha256

let valid_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let valid_identifier value =
  let length = String.length value in
  length > 0 && length <= 256
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
         | '.' | '_' | ':' | '-' -> true
         | _ -> false)
       value

let make_binding ~execution_identity ~activity_digest ~producer_action_id
    ~consumer_action_id ~request_digest ~expires_at_ns =
  if not (valid_digest execution_identity) then
    Error (diagnostic Invalid_binding "execution identity is not lowercase SHA-256")
  else if not (valid_digest activity_digest) then
    Error (diagnostic Invalid_binding "activity digest is not lowercase SHA-256")
  else if not (valid_identifier producer_action_id) then
    Error (diagnostic Invalid_binding "producer action identity is invalid")
  else if not (valid_identifier consumer_action_id) then
    Error (diagnostic Invalid_binding "consumer action identity is invalid")
  else if String.equal producer_action_id consumer_action_id then
    Error (diagnostic Invalid_binding "producer and consumer must be distinct")
  else if not (valid_digest request_digest) then
    Error (diagnostic Invalid_binding "request digest is not lowercase SHA-256")
  else if Int64.compare expires_at_ns 0L <= 0 then
    Error (diagnostic Invalid_binding "expiry must be positive")
  else
    Ok { execution_identity; activity_digest; producer_action_id;
         consumer_action_id; request_digest; expires_at_ns }

let make_redacted_evidence ~disposition ~evidence_digest =
  if valid_digest evidence_digest then Ok { disposition; evidence_digest }
  else
    Error
      (diagnostic Invalid_redacted_evidence
         "redacted evidence digest is not lowercase SHA-256")

let binding_digest (binding : binding) =
  digest_fields
    [ "run-dependency-binding-v1"; binding.execution_identity;
      binding.activity_digest; binding.producer_action_id;
      binding.consumer_action_id; binding.request_digest;
      Int64.to_string binding.expires_at_ns ]

let disposition_id = function
  | Dependency_succeeded -> "succeeded"
  | Dependency_unavailable -> "unavailable"

let owner_equal left right =
  left.generation = right.generation
  && String.equal left.owner_id right.owner_id
  && String.equal left.owner_digest_value right.owner_digest_value
  && String.equal left.owner_binding_digest right.owner_binding_digest

let open_registry ~owner =
  if owner.generation < 1 || not (valid_identifier owner.owner_id)
     || not (valid_digest owner.owner_digest_value)
  then
    Error
      (diagnostic ~origin:Ops_capability.Implementation
         Durable_owner_unavailable "durable owner current receipt is invalid")
  else Ok { lineage = ref (); owner; rows = [] }

let receipt row owner binding_digest was_replayed =
  { receipt_id = row.row_receipt_id; binding_digest;
    owner_digest = owner.owner_binding_digest;
    evidence_digest = row.row_evidence.evidence_digest;
    expires_at_ns = row.row_binding.expires_at_ns; was_replayed }

let carrier registry row binding_digest =
  { carrier_lineage = registry.lineage; carrier_id = row.row_carrier_id;
    carrier_binding_digest = binding_digest;
    carrier_owner_digest = registry.owner.owner_binding_digest }

let issue_once (registry : registry) ~(binding : binding)
    ~(evidence : redacted_evidence) ~now_ns =
  if Int64.compare now_ns 0L < 0
     || Int64.compare now_ns binding.expires_at_ns >= 0
  then Error (diagnostic Dependency_expired "dependency binding is not current")
  else
    let registry =
      { registry with
        rows =
          List.filter
            (fun (_, row) ->
              Int64.compare now_ns row.row_binding.expires_at_ns < 0)
            registry.rows }
    in
    let digest = binding_digest binding in
    match List.assoc_opt digest registry.rows with
    | Some row when row.row_binding = binding && row.row_evidence = evidence ->
        Ok (registry, carrier registry row digest,
            receipt row registry.owner digest true)
    | Some _ ->
        Error
          (diagnostic Dependency_conflict
             "dependency binding is already sealed to different evidence")
    | None when List.length registry.rows >= maximum_live_dependencies ->
        Error
          (diagnostic Dependency_capacity_exhausted
             "live dependency carrier bound is exhausted")
    | None ->
        let row_receipt_id =
          digest_fields
            [ "run-dependency-receipt-v1"; registry.owner.owner_binding_digest;
              digest; disposition_id evidence.disposition;
              evidence.evidence_digest ]
        in
        let row_carrier_id =
          digest_fields [ "run-dependency-carrier-v1"; row_receipt_id ]
        in
        let row = { row_binding = binding; row_evidence = evidence;
                    row_carrier_id; row_receipt_id } in
        let updated = { registry with rows = (digest, row) :: registry.rows } in
        Ok (updated, carrier updated row digest,
            receipt row updated.owner digest false)

let resolve (registry : registry) ~(owner : durable_owner_current)
    ~(binding : binding) ~carrier:(token : carrier) ~now_ns =
  if token.carrier_lineage != registry.lineage then
    Error (diagnostic Foreign_carrier "carrier belongs to another registry lineage")
  else if not (owner_equal owner registry.owner)
       || not (String.equal token.carrier_owner_digest
                 registry.owner.owner_binding_digest)
  then
    Error
      (diagnostic Dependency_binding_mismatch
         "durable owner identity or generation differs")
  else
    let observed_binding_digest = binding_digest binding in
    if not (String.equal observed_binding_digest token.carrier_binding_digest)
    then
      Error
        (diagnostic Dependency_binding_mismatch
           "execution/activity/producer/consumer/request/expiry binding differs")
    else if Int64.compare now_ns 0L < 0
            || Int64.compare now_ns binding.expires_at_ns >= 0
    then Error (diagnostic Dependency_expired "dependency carrier has expired")
    else
      match List.assoc_opt observed_binding_digest registry.rows with
      | Some row
        when row.row_binding = binding
             && String.equal row.row_carrier_id token.carrier_id ->
          Ok row.row_evidence
      | Some _ ->
          Error
            (diagnostic Dependency_binding_mismatch
               "carrier identity differs from its sealed row")
      | None -> Error (diagnostic Foreign_carrier "carrier row is absent")

let string_of_diagnostic_code = function
  | Durable_owner_unavailable -> "durable-owner-unavailable"
  | Invalid_binding -> "invalid-binding"
  | Invalid_redacted_evidence -> "invalid-redacted-evidence"
  | Dependency_conflict -> "dependency-conflict"
  | Dependency_expired -> "dependency-expired"
  | Dependency_binding_mismatch -> "dependency-binding-mismatch"
  | Foreign_carrier -> "foreign-carrier"
  | Dependency_capacity_exhausted -> "dependency-capacity-exhausted"

let source_denominator =
  [ "execution-identity"; "activity-digest"; "producer-action";
    "consumer-action"; "request-digest"; "expiry"; "durable-owner" ]

let source_digest_of denominator =
  digest_fields
    ("run-dependency-authority-v1"
     :: ("maximum-live:" ^ string_of_int maximum_live_dependencies)
     :: denominator)

let source_digest = source_digest_of source_denominator

module For_test = struct
  let durable_owner_current ~owner_id ~generation ~owner_digest =
    if not (valid_identifier owner_id) || generation < 1
       || not (valid_digest owner_digest)
    then
      Error
        (diagnostic Durable_owner_unavailable
           "test durable owner current receipt is invalid")
    else
      let owner_binding_digest =
        digest_fields
          [ "run-dependency-owner-current-v1"; owner_id;
            string_of_int generation; owner_digest ]
      in
      Ok { owner_id; generation; owner_digest_value = owner_digest;
           owner_binding_digest }

  type source_mutation =
    | Drop_execution_identity
    | Drop_activity_digest
    | Drop_producer_action
    | Drop_consumer_action
    | Drop_request_digest
    | Drop_expiry
    | Drop_durable_owner

  let source_digest_with_mutation mutation =
    let removed = match mutation with
      | Drop_execution_identity -> "execution-identity"
      | Drop_activity_digest -> "activity-digest"
      | Drop_producer_action -> "producer-action"
      | Drop_consumer_action -> "consumer-action"
      | Drop_request_digest -> "request-digest"
      | Drop_expiry -> "expiry"
      | Drop_durable_owner -> "durable-owner"
    in
    source_denominator
    |> List.filter (fun value -> not (String.equal value removed))
    |> source_digest_of
end
