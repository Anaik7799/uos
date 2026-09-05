type operation = Remote_synchronization | Remote_publication
type idempotency = Stable_request_identity_required | Expected_remote_tip_cas_required
type redaction = Credentials_and_payloads_redacted
type status = Unavailable_observed | Expired | Revoked | Cleaned
type request = {
  remote : Dependability_credential.remote;
  operation : operation;
  timeout_ms : int;
  max_response_bytes : int;
  idempotency : idempotency;
  digest : string;
}
type receipt = {
  status : status;
  remote : string;
  credential_digest : string;
  request_digest : string;
  observed_at : Dependability_clock.receipt;
  observation_clock_digest : string;
  digest : string;
}
type error =
  | Remote_lease_mismatch
  | Invalid_credential_lease
  | Invalid_clock_receipt
  | Clock_rollback

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let maximum_timeout_ms = 30_000
let maximum_response_bytes = 1_048_576
let synchronization_timeout_ms = 30_000
let publication_timeout_ms = 30_000
let synchronization_response_bound = 1_048_576
let publication_response_bound = 262_144
let all_operations = [ Remote_synchronization; Remote_publication ]

let operation_key = function
  | Remote_synchronization -> "remote-synchronization"
  | Remote_publication -> "remote-publication"

let idempotency_key = function
  | Stable_request_identity_required -> "stable-request-identity-required"
  | Expected_remote_tip_cas_required -> "expected-remote-tip-cas-required"

let status_key = function
  | Unavailable_observed -> "unavailable-observed"
  | Expired -> "expired"
  | Revoked -> "revoked"
  | Cleaned -> "cleaned"

let redaction_key Credentials_and_payloads_redacted =
  "credentials-and-payloads-redacted"

let authority_digest ?(remote_binding = true) ?(credential_binding = true)
    ?(timeout = true) ?(response_bound = true) ?(idempotency = true)
    ?(redaction = true) ?(expiry = true) ?(cleanup = true) () =
  length_frame
    [ "dependability-network-authority-v1";
      Dependability_clock.source_digest;
      Dependability_credential.source_digest;
      "remote-binding"; string_of_bool remote_binding;
      "credential-binding"; string_of_bool credential_binding;
      "timeout"; string_of_bool timeout;
      "maximum-timeout-ms"; string_of_int maximum_timeout_ms;
      "response-bound"; string_of_bool response_bound;
      "maximum-response-bytes"; string_of_int maximum_response_bytes;
      "idempotency"; string_of_bool idempotency;
      "redaction"; string_of_bool redaction;
      "expiry"; string_of_bool expiry;
      "cleanup"; string_of_bool cleanup;
      "operations";
      length_frame (List.map operation_key all_operations);
      "network-backend"; "unavailable-observed" ]
  |> sha256

let source_digest = authority_digest ()

let policy operation =
  match operation with
  | Remote_synchronization ->
      (synchronization_timeout_ms, synchronization_response_bound,
       Stable_request_identity_required)
  | Remote_publication ->
      (publication_timeout_ms, publication_response_bound,
       Expected_remote_tip_cas_required)

let request_digest_of remote operation timeout_ms max_response_bytes idempotency =
  length_frame
    [ "network-request-v1"; source_digest;
      Dependability_credential.remote_digest remote; operation_key operation;
      string_of_int timeout_ms; string_of_int max_response_bytes;
      idempotency_key idempotency ]
  |> sha256

let declare ~remote operation =
  let timeout_ms, max_response_bytes, idempotency = policy operation in
  { remote; operation; timeout_ms; max_response_bytes; idempotency;
    digest =
      request_digest_of remote operation timeout_ms max_response_bytes
        idempotency }

let timeout_ms request = request.timeout_ms
let max_response_bytes request = request.max_response_bytes
let idempotency request = request.idempotency
let request_digest (request : request) = request.digest

let status_of_credential_error = function
  | Dependability_credential.Credential_unavailable -> Ok Unavailable_observed
  | Lease_expired -> Ok Expired
  | Lease_revoked -> Ok Revoked
  | Lease_cleaned -> Ok Cleaned
  | Clock_rollback -> Error Clock_rollback
  | Invalid_clock_receipt -> Error Invalid_clock_receipt
  | Invalid_lease | Invalid_remote -> Error Invalid_credential_lease

let receipt_digest_of status remote credential_digest request_digest
    observation_clock_digest =
  length_frame
    [ "network-redacted-receipt-v1"; source_digest; status_key status; remote;
      credential_digest; request_digest; observation_clock_digest;
      redaction_key Credentials_and_payloads_redacted ]
  |> sha256

let observe ~now ~lease (request : request) =
  if not (Dependability_credential.matches_remote lease request.remote) then
    Error Remote_lease_mismatch
  else
    match Dependability_credential.validate_current ~now lease with
    | Ok () -> Error Invalid_credential_lease
    | Error credential_error ->
        match status_of_credential_error credential_error with
    | Error _ as error -> error
    | Ok status ->
        let remote = Dependability_credential.redacted_remote
            (Dependability_credential.redacted_receipt lease) in
        let credential_digest = Dependability_credential.lease_digest lease in
        let observation_clock_digest = Dependability_clock.digest now in
        let digest =
          receipt_digest_of status remote credential_digest request.digest
            observation_clock_digest in
        Ok { status; remote; credential_digest; request_digest = request.digest;
             observed_at = now; observation_clock_digest; digest }

let status receipt = receipt.status
let network_permitted _ = false
let redacted_remote receipt = receipt.remote
let credential_lease_digest receipt = receipt.credential_digest
let observation_clock_digest receipt = receipt.observation_clock_digest
let redaction _ = Credentials_and_payloads_redacted
let receipt_digest receipt = receipt.digest

let validate_current ~now ~lease receipt =
  match Dependability_clock.validate_current ~now receipt.observed_at with
  | Error Dependability_clock.Invalid_receipt -> Error Invalid_clock_receipt
  | Error Dependability_clock.Wall_clock_rollback
  | Error Dependability_clock.Monotonic_clock_rollback -> Error Clock_rollback
  | Error _ -> Error Invalid_clock_receipt
  | Ok () ->
      let credential_digest = Dependability_credential.lease_digest lease in
      let current_status =
        match Dependability_credential.validate_current ~now lease with
        | Ok () -> Error Invalid_credential_lease
        | Error error -> status_of_credential_error error
      in
      match current_status with
      | Error _ as error -> error
      | Ok expected_status ->
          let expected_digest =
            receipt_digest_of expected_status receipt.remote credential_digest
              receipt.request_digest receipt.observation_clock_digest
          in
          if credential_digest <> receipt.credential_digest
             || expected_status <> receipt.status
             || expected_digest <> receipt.digest
          then Error Invalid_credential_lease
          else Ok ()

module For_test = struct
  type mutation =
    | Drop_remote_binding | Drop_credential_binding | Drop_timeout
    | Widen_response_bound | Drop_idempotency | Drop_redaction | Drop_expiry
    | Drop_cleanup

  let source_digest_with_mutation = function
    | Drop_remote_binding -> authority_digest ~remote_binding:false ()
    | Drop_credential_binding -> authority_digest ~credential_binding:false ()
    | Drop_timeout -> authority_digest ~timeout:false ()
    | Widen_response_bound -> authority_digest ~response_bound:false ()
    | Drop_idempotency -> authority_digest ~idempotency:false ()
    | Drop_redaction -> authority_digest ~redaction:false ()
    | Drop_expiry -> authority_digest ~expiry:false ()
    | Drop_cleanup -> authority_digest ~cleanup:false ()
end
