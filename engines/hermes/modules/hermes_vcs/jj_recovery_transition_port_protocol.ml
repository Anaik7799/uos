module Expiry = struct
  type t = string

  let make value =
    let length = String.length value in
    let allowed = function
      | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' | '/' -> true
      | _ -> false
    in
    if length = 0 then Error (Jj_error.make Jj_error.Empty_identity ~detail:"empty")
    else if length > 128 then
      Error (Jj_error.make Jj_error.Identity_too_long ~detail:"maximum-128-bytes")
    else if value.[0] = '-' || value.[0] = '.' || value.[0] = '/'
            || value.[length - 1] = '-' || value.[length - 1] = '.'
            || value.[length - 1] = '/'
            || String.exists (fun byte -> Char.code byte < 32 || Char.code byte = 127) value
            || not (String.for_all allowed value) then
      Error (Jj_error.make Jj_error.Noncanonical_identity ~detail:"bounded-lower-ascii-token")
    else Ok value

  let to_string value = value
end

type prepared_reference = { key : string }
type reference = unit
type reference_current = unit

let prepare ~owner_session ~activation_generation ~activity ~commitment ~target
    ~consumer ~expiry =
  match consumer with
  | Jj_action_kind.Activate_source_recovery_branch ->
      let key =
        Jj_id.length_frame
          [ Jj_runtime_manifest.slot_key target;
            Jj_runtime_current_protocol.Owner_session.to_string owner_session;
            string_of_int
              (Jj_runtime_current_protocol.Activation_generation.to_int activation_generation);
            Jj_runtime_current_protocol.Activity_identity.to_string activity;
            Jj_runtime_current_protocol.Source_transition_commitment.to_string commitment;
            Jj_action_kind.frontier_action_key consumer; Expiry.to_string expiry ]
        |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
      in
      Ok { key }
  | Jj_action_kind.Set_activity_frontier _ ->
      Error (Jj_error.make Jj_error.Unavailable_observed
               ~detail:"only-transition-activation-may-consume-recovery-reference")

let prepared_key prepared = prepared.key

let source_digest =
  Jj_id.length_frame
    [ "jj-recovery-transition-port-protocol-v1";
      Jj_runtime_current_protocol.source_digest; Jj_runtime_manifest.source_digest;
      "prepared-reference-only"; "sealed-reference-boundary";
      "authority-store-sealing-required" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
