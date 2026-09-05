type remote = string
type transport = Ssh_strict | Https_tls13
type endpoint_policy = Registered_ssh_endpoint | Registered_https_endpoint
type host_key_policy = Pinned_host_key_required | Host_key_not_applicable
type tls_policy = Tls_not_applicable | Tls_1_3_pinned_server
type status = Unavailable_observed | Expired | Revoked | Cleaned

type declaration = { remote : remote; transport : transport }
type lease = {
  declaration : declaration;
  clock : Dependability_clock.receipt;
  status : status;
  reference : string;
  digest : string;
}
type redacted_receipt = { status : status; remote : string; digest : string }

type error =
  | Invalid_remote
  | Invalid_clock_receipt
  | Clock_rollback
  | Invalid_lease
  | Credential_unavailable
  | Lease_expired
  | Lease_revoked
  | Lease_cleaned

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let maximum_remote_length = 64
let configuration_authority = "JUJUTSU_CREDENTIAL_POLICY"
let strict_scrubbed_inheritance =
  [ "HOME"; "XDG"; "GIT_CONFIG"; "SSH_AGENT"; "ASKPASS";
    "CREDENTIAL_HELPER" ]

let authority_digest ?(remote_binding = true) ?(endpoint_policy = true)
    ?(host_key_policy = true) ?(tls_policy = true) ?(scrub_policy = true)
    ?(serialization_forbidden = true) ?(unavailable_authorizes = false)
    ?(expiry = true) ?(revocation = true) ?(cleanup = true) () =
  length_frame
    [ "dependability-credential-authority-v1";
      Dependability_clock.source_digest;
      "configuration-id"; configuration_authority;
      "maximum-remote-length"; string_of_int maximum_remote_length;
      "remote-binding"; string_of_bool remote_binding;
      "endpoint-policy"; string_of_bool endpoint_policy;
      "host-key-policy"; string_of_bool host_key_policy;
      "tls-policy"; string_of_bool tls_policy;
      "scrub-policy"; string_of_bool scrub_policy;
      "scrubbed-inheritance"; length_frame strict_scrubbed_inheritance;
      "lease-serialization-forbidden"; string_of_bool serialization_forbidden;
      "unavailable-authorizes"; string_of_bool unavailable_authorizes;
      "expiry-absorbing"; string_of_bool expiry;
      "revocation-absorbing"; string_of_bool revocation;
      "cleanup-absorbing"; string_of_bool cleanup;
      "statuses"; length_frame [ "unavailable"; "expired"; "revoked"; "cleaned" ];
      "secret-provider"; "unavailable-observed" ]
  |> sha256

let source_digest = authority_digest ()

let is_name_character = function
  | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' -> true
  | _ -> false

let is_alphanumeric = function
  | 'a' .. 'z' | '0' .. '9' -> true
  | _ -> false

let remote value =
  let length = String.length value in
  if length = 0 || length > maximum_remote_length
     || not (String.for_all is_name_character value)
     || not (is_alphanumeric value.[0])
     || not (is_alphanumeric value.[length - 1])
  then Error Invalid_remote
  else Ok value

let remote_digest value =
  length_frame [ "credential-remote-identity-v1"; value ] |> sha256

let declare ~remote ~transport = { remote; transport }
let endpoint_policy declaration =
  match declaration.transport with
  | Ssh_strict -> Registered_ssh_endpoint
  | Https_tls13 -> Registered_https_endpoint

let host_key_policy declaration =
  match declaration.transport with
  | Ssh_strict -> Pinned_host_key_required
  | Https_tls13 -> Host_key_not_applicable

let tls_policy declaration =
  match declaration.transport with
  | Ssh_strict -> Tls_not_applicable
  | Https_tls13 -> Tls_1_3_pinned_server

let endpoint_key = function
  | Registered_ssh_endpoint -> "registered-ssh-endpoint"
  | Registered_https_endpoint -> "registered-https-endpoint"

let host_key = function
  | Pinned_host_key_required -> "pinned-host-key-required"
  | Host_key_not_applicable -> "host-key-not-applicable"

let tls_key = function
  | Tls_not_applicable -> "tls-not-applicable"
  | Tls_1_3_pinned_server -> "tls-1.3-pinned-server"

let scrubbed_inheritance _ = strict_scrubbed_inheritance
let scrub_policy_digest _ =
  sha256
    (length_frame
       [ "credential-scrub-policy-v1";
         length_frame strict_scrubbed_inheritance ])
let configuration_id _ = configuration_authority

let declaration_digest (declaration : declaration) =
  length_frame
    [ source_digest; declaration.remote;
      endpoint_key (endpoint_policy declaration);
      host_key (host_key_policy declaration);
      tls_key (tls_policy declaration);
      scrub_policy_digest declaration; configuration_authority ]
  |> sha256

let status_key = function
  | Unavailable_observed -> "unavailable-observed"
  | Expired -> "expired"
  | Revoked -> "revoked"
  | Cleaned -> "cleaned"

let reference_of declaration clock =
  length_frame
    [ "credential-lease-reference-v1"; declaration_digest declaration;
      Dependability_clock.digest clock;
      Int64.to_string (Dependability_clock.expires_monotonic_ns clock) ]
  |> sha256

let lease_digest_of declaration clock status reference =
  length_frame
    [ source_digest; declaration_digest declaration;
      Dependability_clock.digest clock; reference; status_key status ]
  |> sha256

let declare_unavailable ~clock declaration =
  let reference = reference_of declaration clock in
  { declaration; clock; status = Unavailable_observed; reference;
    digest = lease_digest_of declaration clock Unavailable_observed reference }

let with_status next (value : lease) =
  match value.status with
  | Expired | Revoked | Cleaned -> value
  | Unavailable_observed ->
      { value with status = next;
        digest = lease_digest_of value.declaration value.clock next value.reference }

let validate (value : lease) =
  if Dependability_clock.validate value.clock <> Ok ()
     || not
          (String.equal value.reference
             (reference_of value.declaration value.clock))
     || not
          (String.equal value.digest
             (lease_digest_of value.declaration value.clock value.status
                value.reference))
  then Error Invalid_lease
  else Ok ()

let observe ~now (value : lease) =
  match validate value with
  | Error _ as error -> error
  | Ok () ->
      begin
        match value.status with
        | Expired | Revoked | Cleaned -> Ok value
        | Unavailable_observed ->
            match Dependability_clock.validate_current ~now value.clock with
            | Ok () -> Ok value
            | Error Dependability_clock.Expired -> Ok (with_status Expired value)
            | Error Dependability_clock.Wall_clock_rollback
            | Error Dependability_clock.Monotonic_clock_rollback ->
                Error Clock_rollback
            | Error _ -> Error Invalid_clock_receipt
      end

let revoke (value : lease) = with_status Revoked value
let cleanup (value : lease) = with_status Cleaned value

let validate_current ~now (value : lease) =
  match validate value with
  | Error _ as error -> error
  | Ok () ->
      match value.status with
      | Expired -> Error Lease_expired
      | Revoked -> Error Lease_revoked
      | Cleaned -> Error Lease_cleaned
      | Unavailable_observed ->
          match Dependability_clock.validate_current ~now value.clock with
          | Ok () -> Error Credential_unavailable
          | Error Dependability_clock.Expired -> Error Lease_expired
          | Error Dependability_clock.Wall_clock_rollback
          | Error Dependability_clock.Monotonic_clock_rollback ->
              Error Clock_rollback
          | Error _ -> Error Invalid_clock_receipt

let status (value : lease) = value.status
let authorization_permitted (_ : lease) = false
let matches_remote (lease : lease) remote =
  String.equal lease.declaration.remote remote
let lease_reference (value : lease) = value.reference
let lease_digest (value : lease) = value.digest
let redacted_receipt (value : lease) =
  let digest =
    length_frame
      [ "credential-redacted-receipt-v1"; value.declaration.remote;
        declaration_digest value.declaration; value.reference;
        status_key value.status;
        Int64.to_string
          (Dependability_clock.expires_monotonic_ns value.clock);
        value.digest ]
    |> sha256
  in
  { status = value.status; remote = value.declaration.remote; digest }
let redacted_status (value : redacted_receipt) = value.status
let redacted_remote (value : redacted_receipt) = value.remote
let redacted_digest (value : redacted_receipt) = value.digest

module For_test = struct
  type mutation =
    | Drop_remote_binding
    | Drop_endpoint_policy
    | Drop_host_key_policy
    | Drop_tls_policy
    | Drop_scrub_policy
    | Permit_serialization
    | Promote_unavailable
    | Remove_expiry
    | Remove_revocation
    | Remove_cleanup

  let source_digest_with_mutation = function
    | Drop_remote_binding -> authority_digest ~remote_binding:false ()
    | Drop_endpoint_policy -> authority_digest ~endpoint_policy:false ()
    | Drop_host_key_policy -> authority_digest ~host_key_policy:false ()
    | Drop_tls_policy -> authority_digest ~tls_policy:false ()
    | Drop_scrub_policy -> authority_digest ~scrub_policy:false ()
    | Permit_serialization -> authority_digest ~serialization_forbidden:false ()
    | Promote_unavailable -> authority_digest ~unavailable_authorizes:true ()
    | Remove_expiry -> authority_digest ~expiry:false ()
    | Remove_revocation -> authority_digest ~revocation:false ()
    | Remove_cleanup -> authority_digest ~cleanup:false ()
end
