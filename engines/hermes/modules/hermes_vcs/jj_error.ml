type code =
  | Empty_identity
  | Control_byte
  | Identity_too_long
  | Noncanonical_identity
  | Invalid_budget
  | Unknown_operation
  | Unavailable_observed

type t = { code : code; detail : string }

let make code ~detail = { code; detail }
let code value = value.code
let detail value = value.detail

let code_name = function
  | Empty_identity -> "empty-identity"
  | Control_byte -> "control-byte"
  | Identity_too_long -> "identity-too-long"
  | Noncanonical_identity -> "noncanonical-identity"
  | Invalid_budget -> "invalid-budget"
  | Unknown_operation -> "unknown-operation"
  | Unavailable_observed -> "unavailable-observed"

let to_string value = code_name value.code ^ ":" ^ value.detail

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let source_digest =
  [ Empty_identity; Control_byte; Identity_too_long; Noncanonical_identity;
    Invalid_budget; Unknown_operation; Unavailable_observed ]
  |> List.map code_name
  |> fun codes -> length_frame ("jj-error-authority-v1" :: codes)
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
