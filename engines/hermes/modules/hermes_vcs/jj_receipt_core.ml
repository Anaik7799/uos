type digest = Jj_secret_scan.digest

type payload_kind =
  | Patch
  | Description
  | Operation_log_description
  | Credential_bearing_remote_url

type sensitive_payload = {
  kind : payload_kind;
  bytes : string;
}

type payload_error = Empty_payload | Payload_too_large
let maximum_payload_bytes = 1_048_576

let sensitive_payload ~kind ~bytes =
  let length = String.length bytes in
  if length = 0 then Error Empty_payload
  else if length > maximum_payload_bytes then Error Payload_too_large
  else Ok { kind; bytes }

type payload_summary = {
  payload_kind_value : payload_kind;
  byte_length : int;
  digest_value : digest;
}

let digest_bytes bytes =
  Digestif.SHA256.digest_string bytes |> Digestif.SHA256.to_hex
  |> Jj_secret_scan.digest |> Result.get_ok

let normalize_payload payload =
  { payload_kind_value = payload.kind;
    byte_length = String.length payload.bytes;
    digest_value = digest_bytes payload.bytes }

let payload_kind summary = summary.payload_kind_value
let payload_byte_length summary = summary.byte_length
let payload_digest summary = summary.digest_value

type anchor_retention = Until_terminal_readback | Until_reconciled

type recovery_anchor = {
  identity : Jj_id.Receipt.t;
  prefix : digest;
  cut : digest;
  disposition : digest;
  retention : anchor_retention;
}

let recovery_anchor ~identity ~prefix ~cut ~disposition ~retention =
  { identity; prefix; cut; disposition; retention }

type receipt_kind = Observation | Mutation | Recovery
type disposition = First_applied | Replayed | No_effect | Indeterminate

type receipt = {
  receipt_id : Jj_id.Receipt.t;
  request_id : Jj_id.Request.t;
  operation : Jj_operation.t;
  kind : receipt_kind;
  disposition : disposition;
  request_digest : digest;
  target_digest : digest;
  before_digest : digest;
  after_digest : digest;
  readback_id : Jj_id.Receipt.t;
  readback_digest : digest;
  secret_scan_digest : digest;
  payloads : payload_summary list;
  recovery : recovery_anchor option;
}

type receipt_error =
  | Too_many_payload_summaries
  | Duplicate_payload_summary

let payload_kind_key = function
  | Patch -> "patch"
  | Description -> "description"
  | Operation_log_description -> "operation-log-description"
  | Credential_bearing_remote_url -> "credential-bearing-remote-url"

let receipt_kind_key = function
  | Observation -> "observation"
  | Mutation -> "mutation"
  | Recovery -> "recovery"

let disposition_key = function
  | First_applied -> "first-applied"
  | Replayed -> "replayed"
  | No_effect -> "no-effect"
  | Indeterminate -> "indeterminate"

let retention_key = function
  | Until_terminal_readback -> "until-terminal-readback"
  | Until_reconciled -> "until-reconciled"

let payload_fields payload =
  [ payload_kind_key payload.payload_kind_value;
    string_of_int payload.byte_length;
    Jj_secret_scan.digest_to_hex payload.digest_value ]

let payload_key payload = Jj_id.length_frame (payload_fields payload)
let maximum_payload_summaries = 64

let rec duplicate_payload = function
  | left :: (right :: _ as rest) ->
      String.equal (payload_key left) (payload_key right)
      || duplicate_payload rest
  | _ -> false

let make ~receipt_id ~request_id ~operation ~kind ~disposition ~request_digest
    ~target_digest ~before_digest ~after_digest ~readback_id ~readback_digest
    ~secret_scan ~payloads ~recovery =
  if List.length payloads > maximum_payload_summaries then
    Error Too_many_payload_summaries
  else
    let payloads = List.sort (fun left right ->
      String.compare (payload_key left) (payload_key right)) payloads in
    if duplicate_payload payloads then Error Duplicate_payload_summary
    else
      Ok
        { receipt_id; request_id; operation; kind; disposition; request_digest;
          target_digest; before_digest; after_digest; readback_id;
          readback_digest;
          secret_scan_digest = Jj_secret_scan.canonical_digest secret_scan;
          payloads; recovery }

let recovery_fields = function
  | None -> [ "no-recovery-anchor" ]
  | Some anchor ->
      [ "recovery-anchor"; Jj_id.Receipt.to_string anchor.identity;
        Jj_secret_scan.digest_to_hex anchor.prefix;
        Jj_secret_scan.digest_to_hex anchor.cut;
        Jj_secret_scan.digest_to_hex anchor.disposition;
        retention_key anchor.retention ]

let receipt_fields receipt =
  [ Jj_id.Receipt.to_string receipt.receipt_id;
    Jj_id.Request.to_string receipt.request_id;
    (Jj_operation.declaration receipt.operation).key;
    receipt_kind_key receipt.kind;
    disposition_key receipt.disposition;
    Jj_secret_scan.digest_to_hex receipt.request_digest;
    Jj_secret_scan.digest_to_hex receipt.target_digest;
    Jj_secret_scan.digest_to_hex receipt.before_digest;
    Jj_secret_scan.digest_to_hex receipt.after_digest;
    Jj_id.Receipt.to_string receipt.readback_id;
    Jj_secret_scan.digest_to_hex receipt.readback_digest;
    Jj_secret_scan.digest_to_hex receipt.secret_scan_digest;
    Jj_id.length_frame (List.map payload_key receipt.payloads);
    Jj_id.length_frame (recovery_fields receipt.recovery) ]

let sha256 fields =
  Jj_id.length_frame fields
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let canonical_digest receipt =
  sha256 ("jj-receipt-core-v1" :: receipt_fields receipt)
  |> Jj_secret_scan.digest |> Result.get_ok

let safe_summary receipt =
  Jj_id.length_frame
    [ "jj-receipt-core";
      Jj_id.Receipt.to_string receipt.receipt_id;
      string_of_int (List.length receipt.payloads);
      Jj_secret_scan.digest_to_hex (canonical_digest receipt) ]

let recovery_anchor_retained receipt = Option.is_some receipt.recovery

let source_digest =
  sha256
    [ "jj-receipt-core-authority-v1"; "ephemeral-sensitive-payload";
      "durable-summary-only"; "exact-readback-identity";
      "recovery-anchor-retention"; "maximum-payload-bytes=1048576";
      "maximum-payload-summaries=64"; "duplicate-summary-refusal";
      "payload-order-independent"; "non-authorizing" ]

module For_test = struct
  type mutation =
    | Receipt_id
    | Request_id
    | Operation
    | Receipt_kind
    | Disposition
    | Request_digest
    | Target_digest
    | Before_digest
    | After_digest
    | Readback_id
    | Readback_digest
    | Secret_scan_digest
    | Payload_kind
    | Payload_length
    | Payload_digest
    | Recovery_identity
    | Recovery_prefix
    | Recovery_cut
    | Recovery_disposition
    | Recovery_retention

  let mutated_digest value =
    digest_bytes ("mutated:" ^ Jj_secret_scan.digest_to_hex value)

  let mutate_payload mutation payload =
    match mutation with
    | Payload_kind ->
        { payload with payload_kind_value =
            (match payload.payload_kind_value with
             | Patch -> Description
             | Description | Operation_log_description
             | Credential_bearing_remote_url -> Patch) }
    | Payload_length -> { payload with byte_length = payload.byte_length + 1 }
    | Payload_digest ->
        { payload with digest_value = mutated_digest payload.digest_value }
    | _ -> payload

  let mutate_recovery mutation anchor =
    match mutation with
    | Recovery_identity ->
        { anchor with identity =
            Jj_id.Receipt.make "mutated-recovery" |> Result.get_ok }
    | Recovery_prefix ->
        { anchor with prefix = mutated_digest anchor.prefix }
    | Recovery_cut -> { anchor with cut = mutated_digest anchor.cut }
    | Recovery_disposition ->
        { anchor with disposition = mutated_digest anchor.disposition }
    | Recovery_retention ->
        { anchor with retention =
            (match anchor.retention with
             | Until_terminal_readback -> Until_reconciled
             | Until_reconciled -> Until_terminal_readback) }
    | _ -> anchor

  let canonical_digest_with_mutation receipt mutation =
    let mutated = match mutation with
      | Receipt_id ->
          { receipt with receipt_id =
              Jj_id.Receipt.make "mutated-receipt" |> Result.get_ok }
      | Request_id ->
          { receipt with request_id =
              Jj_id.Request.make "mutated-request" |> Result.get_ok }
      | Operation ->
          { receipt with operation =
              (match receipt.operation with
               | Jj_operation.Version -> Jj_operation.Describe
               | _ -> Jj_operation.Version) }
      | Receipt_kind ->
          { receipt with kind =
              (match receipt.kind with
               | Observation -> Mutation
               | Mutation | Recovery -> Observation) }
      | Disposition ->
          { receipt with disposition =
              (match receipt.disposition with
               | First_applied -> Replayed
               | Replayed | No_effect | Indeterminate -> First_applied) }
      | Request_digest ->
          { receipt with request_digest = mutated_digest receipt.request_digest }
      | Target_digest ->
          { receipt with target_digest = mutated_digest receipt.target_digest }
      | Before_digest ->
          { receipt with before_digest = mutated_digest receipt.before_digest }
      | After_digest ->
          { receipt with after_digest = mutated_digest receipt.after_digest }
      | Readback_id ->
          { receipt with readback_id =
              Jj_id.Receipt.make "mutated-readback" |> Result.get_ok }
      | Readback_digest ->
          { receipt with readback_digest = mutated_digest receipt.readback_digest }
      | Secret_scan_digest ->
          { receipt with secret_scan_digest =
              mutated_digest receipt.secret_scan_digest }
      | Payload_kind | Payload_length | Payload_digest ->
          { receipt with payloads =
              (match receipt.payloads with
               | [] ->
                   [ { payload_kind_value = Patch; byte_length = 1;
                       digest_value = digest_bytes "mutated-payload" } ]
               | payload :: rest -> mutate_payload mutation payload :: rest) }
      | Recovery_identity | Recovery_prefix | Recovery_cut
      | Recovery_disposition | Recovery_retention ->
          { receipt with recovery =
              (match receipt.recovery with
               | Some anchor -> Some (mutate_recovery mutation anchor)
               | None ->
                   Some
                     { identity = Jj_id.Receipt.make "mutated-recovery"
                                  |> Result.get_ok;
                       prefix = digest_bytes "mutated-prefix";
                       cut = digest_bytes "mutated-cut";
                       disposition = digest_bytes "mutated-disposition";
                       retention = Until_reconciled }) }
    in
    canonical_digest mutated |> Jj_secret_scan.digest_to_hex
end
