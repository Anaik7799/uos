type process_role = Jujutsu_process | Candidate_process | Formal_process

type obligation =
  | Exact_source
  | Exact_configuration
  | Approval_required
  | Writer_lease_required
  | Resource_preflight_required
  | Bridge_admission_required
  | Apply_once_receipt_required
  | Readback_required
  | Remote_publication_cas_required

type availability =
  | Bridge_unavailable
  | Formal_oracle_unavailable
  | Remote_publication_unavailable_without_cas

type projection = {
  request_id : Jj_id.Request.t;
  kind : Jj_process_protocol.request_kind;
  process_role : process_role;
  target : Jj_target_protocol.t;
  budget : Jj_budget.t;
  recovery : Jj_operation.recovery_policy;
  obligations : obligation list;
  availability : availability;
  digest : string;
}

type declaration = projection
type reconciliation = Stable_replay | Identity_conflict | Different_request

let schema_id = "hermes.dependability-process-protocol.v1"
let all_kinds = Jj_process_protocol.all

let common_obligations =
  [ Exact_source; Exact_configuration; Approval_required;
    Writer_lease_required; Resource_preflight_required;
    Bridge_admission_required; Apply_once_receipt_required; Readback_required ]

let candidate_obligations =
  [ Exact_source; Exact_configuration; Approval_required;
    Resource_preflight_required; Bridge_admission_required;
    Apply_once_receipt_required; Readback_required ]

let formal_obligations = candidate_obligations

let role = function
  | Jj_process_protocol.Jujutsu_operation _ -> Jujutsu_process
  | Candidate_verification _ -> Candidate_process
  | Formal_oracle _ -> Formal_process

let target = function
  | Jj_process_protocol.Jujutsu_operation _ -> Jj_target_protocol.Jujutsu
  | Candidate_verification _ -> Candidate_verification
  | Formal_oracle _ -> Formal

let budget = function
  | Jj_process_protocol.Jujutsu_operation operation ->
      (Jj_operation.declaration operation).budget
  | Candidate_verification _ | Formal_oracle _ ->
      Jj_budget.for_profile Observation

let recovery = function
  | Jj_process_protocol.Jujutsu_operation operation ->
      (Jj_operation.declaration operation).recovery
  | Candidate_verification _ | Formal_oracle _ -> Jj_operation.Recovery_none

let obligations = function
  | Jj_process_protocol.Jujutsu_operation Jj_operation.Git_push ->
      common_obligations @ [ Remote_publication_cas_required ]
  | Candidate_verification _ -> candidate_obligations
  | Formal_oracle _ -> formal_obligations
  | Jujutsu_operation _ -> common_obligations

let availability = function
  | Jj_process_protocol.Formal_oracle _ -> Formal_oracle_unavailable
  | Jujutsu_operation Jj_operation.Git_push ->
      Remote_publication_unavailable_without_cas
  | Jujutsu_operation _ | Candidate_verification _ -> Bridge_unavailable

let role_key = function
  | Jujutsu_process -> "jujutsu-process"
  | Candidate_process -> "candidate-process"
  | Formal_process -> "formal-process"

let recovery_key = function
  | Jj_operation.Recovery_none -> "none"
  | Recovery_before_state -> "before-state"
  | Recovery_partition_anchor -> "partition-anchor"

let obligation_key = function
  | Exact_source -> "exact-source"
  | Exact_configuration -> "exact-configuration"
  | Approval_required -> "approval-required"
  | Writer_lease_required -> "writer-lease-required"
  | Resource_preflight_required -> "resource-preflight-required"
  | Bridge_admission_required -> "bridge-admission-required"
  | Apply_once_receipt_required -> "apply-once-receipt-required"
  | Readback_required -> "readback-required"
  | Remote_publication_cas_required -> "remote-publication-cas-required"

let availability_key = function
  | Bridge_unavailable -> "bridge-unavailable"
  | Formal_oracle_unavailable -> "formal-oracle-unavailable"
  | Remote_publication_unavailable_without_cas ->
      "remote-publication-unavailable-without-cas"

let sha256 values =
  values |> Jj_id.length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let canonical_fields ~request_identity ~kind ~process_role ~target ~budget
    ~recovery ~obligations ~availability =
  [ schema_id; request_identity; Jj_process_protocol.key kind;
    role_key process_role; Jj_target_protocol.key target;
    string_of_int budget.Jj_budget.max_attempts;
    string_of_int budget.timeout_ms; string_of_int budget.max_output_bytes;
    recovery_key recovery; availability_key availability;
    Jj_id.length_frame (List.map obligation_key obligations) ]

let declare ~request_id kind =
  let process_role = role kind in
  let target = target kind in
  let budget = budget kind in
  let recovery = recovery kind in
  let obligations = obligations kind in
  let availability = availability kind in
  let digest =
    canonical_fields ~request_identity:(Jj_id.Request.to_string request_id)
      ~kind ~process_role ~target ~budget ~recovery ~obligations ~availability
    |> sha256 in
  { request_id; kind; process_role; target; budget; recovery; obligations;
    availability; digest }

let projection declaration = declaration
let digest declaration = declaration.digest

let reconcile left right =
  if Jj_id.Request.to_string left.request_id
     <> Jj_id.Request.to_string right.request_id
  then Different_request
  else if String.equal left.digest right.digest then Stable_replay
  else Identity_conflict

type template = {
  template_kind : Jj_process_protocol.request_kind;
  template_role : process_role;
  template_target : Jj_target_protocol.t;
  template_budget : Jj_budget.t;
  template_recovery : Jj_operation.recovery_policy;
  template_obligations : obligation list;
  template_availability : availability;
}

let template kind =
  { template_kind = kind; template_role = role kind;
    template_target = target kind; template_budget = budget kind;
    template_recovery = recovery kind; template_obligations = obligations kind;
    template_availability = availability kind }

let templates = List.map template all_kinds

let canonical_template ?budget_values ?recovery_value ?availability_value row =
  let attempts, timeout, output =
    match budget_values with
    | Some values -> values
    | None ->
        (row.template_budget.max_attempts, row.template_budget.timeout_ms,
         row.template_budget.max_output_bytes) in
  Jj_id.length_frame
    [ Jj_process_protocol.key row.template_kind;
      role_key row.template_role; Jj_target_protocol.key row.template_target;
      string_of_int attempts; string_of_int timeout; string_of_int output;
      (match recovery_value with
       | Some value -> value | None -> recovery_key row.template_recovery);
      (match availability_value with
       | Some value -> value | None -> availability_key row.template_availability);
      Jj_id.length_frame (List.map obligation_key row.template_obligations) ]

let digest_templates rows =
  ([ schema_id; Jj_process_protocol.source_digest;
     Jj_target_protocol.source_digest; Jj_operation.source_digest;
     Jj_budget.source_digest; Jj_runtime_manifest.source_digest ]
   @ List.map canonical_template rows)
  |> sha256

let source_digest = digest_templates templates

module For_test = struct
  type mutation =
    | Drop_row | Duplicate_row | Swap_target | Widen_budget | Remove_recovery
    | Promote_availability | Drop_obligation
    | Add_candidate_writer_lease | Add_formal_writer_lease

  let replace_first predicate change rows =
    let rec loop prefix = function
      | [] -> List.rev prefix
      | row :: rest when predicate row -> List.rev_append prefix (change row :: rest)
      | row :: rest -> loop (row :: prefix) rest
    in
    loop [] rows

  let digest_rows rows = digest_templates rows

  let source_digest_with_mutation = function
    | Drop_row -> digest_rows (List.tl templates)
    | Duplicate_row -> digest_rows (List.hd templates :: templates)
    | Swap_target ->
        let first = List.hd templates in
        digest_rows
          ({ first with template_target = Jj_target_protocol.Formal }
           :: List.tl templates)
    | Widen_budget ->
        let first = List.hd templates in
        let widened =
          canonical_template
            ~budget_values:
              (first.template_budget.max_attempts,
               first.template_budget.timeout_ms,
               first.template_budget.max_output_bytes + 1)
            first in
        ([ schema_id; Jj_process_protocol.source_digest;
           Jj_target_protocol.source_digest; Jj_operation.source_digest;
           Jj_budget.source_digest; Jj_runtime_manifest.source_digest;
           widened ]
         @ List.map canonical_template (List.tl templates))
        |> sha256
    | Remove_recovery ->
        let rows =
          replace_first
            (fun row -> row.template_recovery <> Jj_operation.Recovery_none)
            (fun row -> { row with template_recovery = Recovery_none })
            templates in
        digest_rows rows
    | Promote_availability ->
        let first = List.hd templates in
        let promoted = canonical_template ~availability_value:"available" first in
        ([ schema_id; Jj_process_protocol.source_digest;
           Jj_target_protocol.source_digest; Jj_operation.source_digest;
           Jj_budget.source_digest; Jj_runtime_manifest.source_digest;
           promoted ]
         @ List.map canonical_template (List.tl templates))
        |> sha256
    | Drop_obligation ->
        let first = List.hd templates in
        digest_rows
          ({ first with template_obligations = List.tl first.template_obligations }
           :: List.tl templates)
    | Add_candidate_writer_lease ->
        templates
        |> replace_first
             (fun row ->
                match row.template_kind with
                | Jj_process_protocol.Candidate_verification _ -> true
                | Jujutsu_operation _ | Formal_oracle _ -> false)
             (fun row ->
                { row with
                  template_obligations =
                    row.template_obligations @ [ Writer_lease_required ] })
        |> digest_rows
    | Add_formal_writer_lease ->
        templates
        |> replace_first
             (fun row ->
                match row.template_kind with
                | Jj_process_protocol.Formal_oracle _ -> true
                | Jujutsu_operation _ | Candidate_verification _ -> false)
             (fun row ->
                { row with
                  template_obligations =
                    row.template_obligations @ [ Writer_lease_required ] })
        |> digest_rows
end
