let maximum_length = 128

let canonical value =
  let length = String.length value in
  let allowed = function
    | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' | '/' -> true
    | _ -> false
  in
  if length = 0 then Error (Jj_error.make Jj_error.Empty_identity ~detail:"empty")
  else if length > maximum_length then
    Error (Jj_error.make Jj_error.Identity_too_long ~detail:"maximum-128-bytes")
  else if String.exists (fun byte -> Char.code byte < 32 || Char.code byte = 127) value then
    Error (Jj_error.make Jj_error.Control_byte ~detail:"ASCII-control-byte")
  else if value.[0] = '-' || value.[0] = '.' || value.[0] = '/'
          || value.[length - 1] = '-' || value.[length - 1] = '.'
          || value.[length - 1] = '/' || not (String.for_all allowed value)
  then Error (Jj_error.make Jj_error.Noncanonical_identity ~detail:"bounded-lower-ascii-token")
  else Ok value

module Make_identity () = struct
  type t = string
  let make = canonical
  let to_string value = value
end

module Owner_session = Make_identity ()
module Source_identity = Make_identity ()
module Config_identity = Make_identity ()
module Host_identity = Make_identity ()
module Clock_identity = Make_identity ()
module Activity_identity = Make_identity ()
module Source_transition_commitment = Make_identity ()

module Positive_int () = struct
  type t = int
  let make value =
    if value > 0 then Ok value
    else Error (Jj_error.make Jj_error.Invalid_budget ~detail:"positive-ordinal-required")
  let to_int value = value
end

module Lifecycle_epoch = Positive_int ()
module Activation_generation = Positive_int ()

type 'slot owner_claim = { key : string }
type ('generation, 'slot) current_attestation = unit

let claim ~slot ~owner ~epoch ~source ~config ~host ~clock =
  let key =
    Jj_id.length_frame
      [ Jj_runtime_manifest.slot_key slot; Owner_session.to_string owner;
        string_of_int (Lifecycle_epoch.to_int epoch); Source_identity.to_string source;
        Config_identity.to_string config; Host_identity.to_string host;
        Clock_identity.to_string clock ]
    |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
  in
  Ok { key }

let claim_key claim = claim.key

let source_digest =
  Jj_id.length_frame
    [ "jj-runtime-current-protocol-v1"; Jj_runtime_manifest.source_digest;
      "slot-indexed-owner-claim"; "opaque-current-attestation";
      "no-grant-allocator"; "no-current-mint" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
