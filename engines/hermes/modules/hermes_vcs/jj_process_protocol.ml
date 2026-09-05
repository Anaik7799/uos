type request_kind =
  | Jujutsu_operation of Jj_operation.t
  | Candidate_verification of Jj_action_kind.candidate_step
  | Formal_oracle of Jj_action_kind.formal_tool

let all =
  List.map (fun operation -> Jujutsu_operation operation) Jj_operation.all
  @ List.map (fun step -> Candidate_verification step) Jj_action_kind.candidate_steps
  @ List.map (fun tool -> Formal_oracle tool) Jj_action_kind.formal_tools

let key = function
  | Jujutsu_operation operation ->
      "jujutsu-operation:" ^ (Jj_operation.declaration operation).key
  | Candidate_verification step ->
      "candidate-verification:" ^ Jj_action_kind.candidate_step_key step
  | Formal_oracle tool -> "formal-oracle:" ^ Jj_action_kind.formal_tool_key tool

let source_digest =
  all |> List.map key |> Jj_id.length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex
