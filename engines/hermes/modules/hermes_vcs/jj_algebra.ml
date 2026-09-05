type canonical_field = { name : string; value : string }
type canonical_refusal =
  | Empty_field_name
  | Invalid_field_name
  | Field_too_large
  | Too_many_fields
  | Duplicate_field

let max_fields = 64
let max_field_bytes = 4096

let valid_name name =
  name <> ""
  && String.for_all
       (function
         | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' -> true
         | _ -> false)
       name

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat ""

let canonicalize fields =
  if List.length fields > max_fields then Error Too_many_fields
  else if List.exists (fun field -> field.name = "") fields then
    Error Empty_field_name
  else if List.exists (fun field -> not (valid_name field.name)) fields then
    Error Invalid_field_name
  else if
    List.exists
      (fun field -> String.length field.name > 128
                    || String.length field.value > max_field_bytes)
      fields
  then Error Field_too_large
  else
    let sorted = List.sort (fun left right -> String.compare left.name right.name) fields in
    let rec duplicate = function
      | left :: (right :: _ as tail) ->
          String.equal left.name right.name || duplicate tail
      | _ -> false
    in
    if duplicate sorted then Error Duplicate_field
    else
      Ok
        (sorted
         |> List.map (fun field -> length_frame [ field.name; field.value ])
         |> String.concat "")

let sha256 value =
  Digestif.SHA256.digest_string value |> Digestif.SHA256.to_hex

type identity = { canonical : string; digest : string }

let identity ~operation ~request ~repository ~workspace =
  canonicalize
    [ { name = "operation"; value = (Jj_operation.declaration operation).key };
      { name = "repository"; value = Jj_id.Repository.to_string repository };
      { name = "request"; value = Jj_id.Request.to_string request };
      { name = "workspace"; value = Jj_id.Workspace.to_string workspace } ]
  |> Result.map (fun canonical -> { canonical; digest = sha256 canonical })

let identity_digest identity = identity.digest
let identity_separated left right = not (String.equal left.digest right.digest)

let policy_conjunction decisions =
  List.fold_left Jj_policy.combine Jj_policy.Permit decisions

let policy_monotone decisions =
  match policy_conjunction decisions with
  | Jj_policy.Permit ->
      List.for_all (fun decision -> decision = Jj_policy.Permit) decisions
  | Jj_policy.Deny _ ->
      List.exists (function Jj_policy.Deny _ -> true | Jj_policy.Permit -> false)
        decisions

type approval_posture = Approval_valid | Approval_missing
type lease_posture = Lease_valid | Lease_stale
type guard_refusal = Policy_denied | Approval_absent | Lease_absent
type guard = Guarded | Refused of guard_refusal

let guard ~policy ~approval ~lease =
  match policy, approval, lease with
  | Jj_policy.Deny _, _, _ -> Refused Policy_denied
  | Jj_policy.Permit, Approval_missing, _ -> Refused Approval_absent
  | Jj_policy.Permit, Approval_valid, Lease_stale -> Refused Lease_absent
  | Jj_policy.Permit, Approval_valid, Lease_valid -> Guarded

type apply_state = Unapplied | Applied of string
type apply_disposition = First_applied | Replayed
type apply_refusal = Invalid_effect_digest | Apply_conflict

let is_lower_hex character =
  match character with '0' .. '9' | 'a' .. 'f' -> true | _ -> false

let valid_digest digest =
  String.length digest = 64 && String.for_all is_lower_hex digest

let apply_once state ~effect_digest =
  if not (valid_digest effect_digest) then Error Invalid_effect_digest
  else
    match state with
    | Unapplied -> Ok (Applied effect_digest, First_applied)
    | Applied existing when String.equal existing effect_digest ->
        Ok (state, Replayed)
    | Applied _ -> Error Apply_conflict

let output_within_bound operation ~output_bytes =
  output_bytes >= 0
  && output_bytes <= (Jj_operation.declaration operation).budget.max_output_bytes

let readback_matches ~expected_operation ~observed_operation ~expected_state
    ~observed_state =
  expected_operation = observed_operation
  && valid_digest expected_state
  && String.equal expected_state observed_state

type recovery_anchor = No_anchor | Before_state_anchor | Partition_anchor

let recovery_anchor_valid operation ~anchor =
  match (Jj_operation.declaration operation).recovery, anchor with
  | Jj_operation.Recovery_none, No_anchor
  | Jj_operation.Recovery_before_state, Before_state_anchor
  | Jj_operation.Recovery_partition_anchor, Partition_anchor -> true
  | _ -> false

let source_only = Mainline_carrier_policy.source_only_closure
let redact = Mainline_carrier_policy.redacted_identity

type surface = Ocaml_api | Cli | Mcp | Zenoh
type normalized_receipt = {
  operation_key : string;
  disposition : string;
  state_digest : string;
}

let surface_receipt _ receipt = receipt

type bridge = Bridge_unavailable | Bridge_admitted
type effect_posture = Zero_effect | Effect_prepared

let effect_posture ~bridge ~requested_effect =
  match bridge, requested_effect with
  | Bridge_admitted, true -> Effect_prepared
  | Bridge_unavailable, _ | _, false -> Zero_effect

type cas = Cas_unproved | Cas_proved
type publication =
  | Not_remote_publication
  | Publication_unavailable
  | Publication_prepared

let remote_publication ~operation ~cas =
  match (Jj_operation.declaration operation).capability, cas with
  | Jj_operation.Capability_remote_publish, Cas_proved -> Publication_prepared
  | Jj_operation.Capability_remote_publish, Cas_unproved -> Publication_unavailable
  | _ -> Not_remote_publication

type law_credit = Validation_only
type law = {
  id : string;
  statement : string;
  negative_control_id : string;
  credit : law_credit;
}

let law id statement =
  { id; statement; negative_control_id = "mutant." ^ id;
    credit = Validation_only }

let laws =
  [ law "canonicalization" "field order cannot change canonical identity";
    law "identity-separation" "operation, request, repository and workspace identities separate";
    law "monotone-policy" "a denial cannot be weakened by composition";
    law "approval-lease-absorption" "missing approval or lease absorbs admission";
    law "apply-once-replay" "one digest applies once and identical replay is no new effect";
    law "output-bounds" "operation output never exceeds its declared budget";
    law "exact-readback" "operation and state readback identities both match";
    law "recovery-anchor-retention" "recovery retains the declared anchor kind";
    law "source-only-closure" "private and digest-only carriers do not enter source closure";
    law "redaction" "private bytes do not enter a safe projection";
    law "surface-equivalence" "four surfaces normalize to one receipt";
    law "zero-effect-before-bridge" "an unadmitted intent prepares no effect";
    law "remote-publish-requires-cas" "remote publication is unavailable without proved CAS" ]

let law_id law = law.id
let law_statement law = law.statement
let law_negative_control_id law = law.negative_control_id
let law_credit law = law.credit

let source_digest =
  laws
  |> List.map (fun law ->
       length_frame
         [ law.id; law.statement; law.negative_control_id; "validation-only" ])
  |> String.concat ""
  |> sha256
