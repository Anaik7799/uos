type applicability = Unavailable_until_bridge | Implemented_unavailable
type error = Unsafe_operation_declaration

type projection = {
  operation : Jj_operation.t;
  repository : Jj_id.Repository.t;
  workspace : Jj_id.Workspace.t;
  expected_before : Jj_id.Operation.t;
  approval_reference : Jj_id.Approval.t;
  approval : Jj_operation.approval_class;
  budget : Jj_budget.t;
  postcondition : Jj_operation.postcondition;
  recovery : Jj_operation.recovery_policy;
  applicability : applicability;
}

type t = projection

let make ~operation ~repository ~workspace ~expected_before
    ~approval_reference =
  if not (Jj_operation.declaration_is_safe operation) then
    Error Unsafe_operation_declaration
  else
    let declaration = Jj_operation.declaration operation in
    let applicability =
      match declaration.activation with
      | Jj_operation.Unavailable_until_bridge -> Unavailable_until_bridge
      | Jj_operation.Implemented_unavailable -> Implemented_unavailable
    in
    Ok
      { operation; repository; workspace; expected_before; approval_reference;
        approval = declaration.approval; budget = declaration.budget;
        postcondition = declaration.postcondition;
        recovery = declaration.recovery; applicability }

let projection value = value

let projection_fields =
  [ "operation"; "repository"; "workspace"; "expected-before";
    "approval-reference"; "approval"; "budget:max-attempts";
    "budget:timeout-ms"; "budget:max-output-bytes"; "postcondition";
    "recovery"; "applicability" ]

let applicability_denominator =
  [ "unavailable-until-bridge"; "implemented-unavailable" ]

let source_digest_of ~fields ~applicability =
  Jj_id.length_frame
    [ "intent-authority-v1"; Jj_operation.source_digest;
      Jj_id.length_frame fields; Jj_id.length_frame applicability;
      Jj_id.length_frame [ "error:unsafe-operation-declaration" ] ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest =
  source_digest_of ~fields:projection_fields
    ~applicability:applicability_denominator

module For_test = struct
  type source_mutation = Drop_projection_field | Change_applicability
  let source_digest_with_mutation = function
    | Drop_projection_field ->
        source_digest_of ~fields:(List.tl projection_fields)
          ~applicability:applicability_denominator
    | Change_applicability ->
        source_digest_of ~fields:projection_fields
          ~applicability:[ "unavailable-until-bridge" ]
end
