module Digest = struct
  type t = string
  let is_hex = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false
  let make value =
    if String.length value = 64 && String.for_all is_hex value then Ok value
    else Error `Invalid_digest
  let to_string value = value
end

module Actor : Jj_id.ID = Jj_id.Approval
module Host : Jj_id.ID = Jj_id.Executable
module Branch : Jj_id.ID = Jj_id.Bookmark
module Capability : Jj_id.ID = Jj_id.Intent

module Journal_position = struct
  type t = int64
  let make value =
    if Int64.compare value 0L >= 0 then Ok value
    else Error `Invalid_journal_position
  let to_int64 value = value
end

type context = {
  payload : Jj_campaign_action.approval_payload;
  plan : Digest.t;
  design : Digest.t;
  head : Jj_id.Operation.t;
  repository : Jj_id.Repository.t;
  workspace : Jj_id.Workspace.t;
  phase : string;
  branch : Branch.t;
  actor : Actor.t;
  host : Host.t;
  expires_at_epoch : int64;
  journal_position : Journal_position.t;
  occurrence_nonce : string;
  capability_references : Capability.t list;
}

type validation_error =
  | Expired | Payload_mismatch | Plan_mismatch | Design_mismatch
  | Head_mismatch | Repository_mismatch | Workspace_mismatch
  | Phase_mismatch | Branch_mismatch | Actor_mismatch | Host_mismatch
  | Expiry_mismatch | Journal_position_mismatch | Occurrence_nonce_mismatch
  | Empty_capability_references | Duplicate_capability_reference
  | Occurrence_nonce_alias | Capability_references_mismatch

type witness = string

let equal show left right = String.equal (show left) (show right)

let capability_strings context =
  List.map Capability.to_string context.capability_references

let rec has_duplicate = function
  | [] -> false
  | value :: rest -> List.mem value rest || has_duplicate rest

let validate_capability_shape context =
  let capabilities = capability_strings context in
  if capabilities = [] then Error Empty_capability_references
  else if has_duplicate capabilities then Error Duplicate_capability_reference
  else if List.mem context.occurrence_nonce capabilities then
    Error Occurrence_nonce_alias
  else Ok ()

let payload_bytes context =
  Jj_campaign_action.canonical_approval_unsigned_bytes context.payload

let payload_occurrence_nonce context =
  let projection = Jj_campaign_action.approval_projection context.payload in
  Jj_campaign_action.occurrence_nonce projection.occurrence

let canonical context =
  Jj_id.length_frame
    [ "approval-validation-witness-v1";
      payload_bytes context;
      Digest.to_string context.plan;
      Digest.to_string context.design;
      Jj_id.Operation.to_string context.head;
      Jj_id.Repository.to_string context.repository;
      Jj_id.Workspace.to_string context.workspace;
      context.phase;
      Branch.to_string context.branch;
      Actor.to_string context.actor;
      Host.to_string context.host;
      Int64.to_string context.expires_at_epoch;
      Int64.to_string (Journal_position.to_int64 context.journal_position);
      context.occurrence_nonce;
      Jj_id.length_frame (capability_strings context) ]

let digest value = Digestif.SHA256.(to_hex (digest_string value))

let validate ~now_epoch ~expected ~presented =
  match validate_capability_shape expected with
  | Error error -> Error error
  | Ok () ->
      begin match validate_capability_shape presented with
      | Error error -> Error error
      | Ok () ->
          if Int64.compare now_epoch presented.expires_at_epoch >= 0 then
            Error Expired
          else if not (String.equal (payload_bytes expected) (payload_bytes presented)) then
            Error Payload_mismatch
          else if not (equal Digest.to_string expected.plan presented.plan) then
            Error Plan_mismatch
          else if not (equal Digest.to_string expected.design presented.design) then
            Error Design_mismatch
          else if not (equal Jj_id.Operation.to_string expected.head presented.head) then
            Error Head_mismatch
          else if not (equal Jj_id.Repository.to_string expected.repository presented.repository) then
            Error Repository_mismatch
          else if not (equal Jj_id.Workspace.to_string expected.workspace presented.workspace) then
            Error Workspace_mismatch
          else if not (String.equal expected.phase presented.phase) then
            Error Phase_mismatch
          else if not (equal Branch.to_string expected.branch presented.branch) then
            Error Branch_mismatch
          else if not (equal Actor.to_string expected.actor presented.actor) then
            Error Actor_mismatch
          else if not (equal Host.to_string expected.host presented.host) then
            Error Host_mismatch
          else if not (Int64.equal expected.expires_at_epoch presented.expires_at_epoch) then
            Error Expiry_mismatch
          else if not (Int64.equal
                         (Journal_position.to_int64 expected.journal_position)
                         (Journal_position.to_int64 presented.journal_position)) then
            Error Journal_position_mismatch
          else if not (String.equal expected.occurrence_nonce
                         (payload_occurrence_nonce expected))
               || not (String.equal presented.occurrence_nonce
                         (payload_occurrence_nonce presented))
               || not (String.equal expected.occurrence_nonce
                         presented.occurrence_nonce)
          then Error Occurrence_nonce_mismatch
          else if capability_strings expected <> capability_strings presented then
            Error Capability_references_mismatch
          else Ok (digest (canonical presented))
      end

let witness_digest witness = witness

let validation_fields =
  [ "payload"; "plan"; "design"; "head"; "repository"; "workspace";
    "phase"; "branch"; "actor"; "host"; "expires-at-epoch";
    "journal-position"; "occurrence-nonce"; "capability-references" ]

let validation_errors =
  [ "expired"; "payload-mismatch"; "plan-mismatch"; "design-mismatch";
    "head-mismatch"; "repository-mismatch"; "workspace-mismatch";
    "phase-mismatch"; "branch-mismatch"; "actor-mismatch";
    "host-mismatch"; "expiry-mismatch"; "journal-position-mismatch";
    "occurrence-nonce-mismatch"; "empty-capability-references";
    "duplicate-capability-reference"; "occurrence-nonce-alias";
    "capability-references-mismatch" ]

let source_digest_of ~digest_bound ~fields =
  Jj_id.length_frame
    [ "approval-validation-authority-v1";
      Jj_campaign_action.source_digest;
      "digest-hex-bytes:" ^ string_of_int digest_bound;
      "journal-position-minimum:0";
      "capability-reference-minimum:1";
      "expiry-comparison:now-greater-or-equal-refuses";
      "capability-order:exact";
      "witness-schema:approval-validation-witness-v1";
      Jj_id.length_frame fields;
      Jj_id.length_frame validation_errors ]
  |> digest

let source_digest = source_digest_of ~digest_bound:64 ~fields:validation_fields

module For_test = struct
  type source_mutation = Change_digest_bound | Drop_validation_field
  let source_digest_with_mutation = function
    | Change_digest_bound ->
        source_digest_of ~digest_bound:63 ~fields:validation_fields
    | Drop_validation_field ->
        source_digest_of ~digest_bound:64 ~fields:(List.tl validation_fields)
end
