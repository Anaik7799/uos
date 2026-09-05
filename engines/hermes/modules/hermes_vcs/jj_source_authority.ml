type unavailable_reason = Missing_digest_accessor
type availability =
  | Available of string
  | Unavailable of unavailable_reason
type constituent = { id : string; availability : availability }

let schema_id = "hermes.jj-source-authority.v1"

let available id digest = { id; availability = Available digest }

let constituents =
  [ available "jj-id" Jj_id.source_digest;
    available "jj-error" Jj_error.source_digest;
    available "jj-budget" Jj_budget.source_digest;
    available "jj-operation" Jj_operation.source_digest;
    available "jj-revset" Jj_revset.source_digest;
    available "jj-path" Jj_path.source_digest;
    available "jj-split-manifest" Jj_split_manifest.source_digest;
    available "jj-action-kind" Jj_action_kind.source_digest;
    available "jj-recovery-schema" Jj_recovery_schema.source_digest;
    available "jj-partition" Jj_partition.source_digest;
    available "jj-campaign-action" Jj_campaign_action.source_digest;
    available "jj-intent" Jj_intent.source_digest;
    available "jj-codec" Jj_codec.source_digest;
    available "jj-policy" Jj_policy.source_digest;
    available "jj-approval" Jj_approval.source_digest;
    available "jj-writer-lease" Jj_writer_lease.source_digest;
    available "mainline-carrier-policy" Mainline_carrier_policy.source_digest;
    available "jj-source-manifest" Jj_source_manifest.source_digest;
    available "jj-secret-scan" Jj_secret_scan.source_digest;
    available "jj-readback" Jj_readback.source_digest;
    available "jj-receipt-core" Jj_receipt_core.source_digest;
    available "jj-ontology" Jj_ontology.source_digest;
    available "jj-algebra" Jj_algebra.source_digest;
    available "jj-fpp" Jj_fpp.source_digest;
    available "jj-sysml" Jj_sysml.source_digest;
    available "jj-command-contract" Jj_command_contract.source_digest;
    available "jj-process-protocol" Jj_process_protocol.source_digest;
    available "jj-target-protocol" Jj_target_protocol.source_digest;
    available "jj-dependency-schema" Jj_dependency_schema.source_digest;
    available "jj-release-protocol" Jj_release_protocol.source_digest;
    available "jj-runtime-manifest" Jj_runtime_manifest.source_digest;
    available "jj-runtime-current-protocol"
      Jj_runtime_current_protocol.source_digest;
    available "jj-recovery-transition-port-protocol"
      Jj_recovery_transition_port_protocol.source_digest;
    available "jj-completion-store-protocol"
      Jj_completion_store_protocol.source_digest;
    available "jj-formal-obligations" Jj_formal_obligations.source_digest ]

let constituent_id value = value.id
let constituent_availability value = value.availability

let unavailable_constituents () =
  List.filter
    (fun row ->
      match row.availability with
      | Available _ -> false
      | Unavailable Missing_digest_accessor -> true)
    constituents

let is_lower_hex = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false
let valid_digest value =
  String.length value = 64 && String.for_all is_lower_hex value

let expected_ids = List.map constituent_id constituents

module For_test = struct
  type compose_error =
    | Denominator_mismatch
    | Duplicate_constituent
    | Invalid_digest of string

  let compose rows =
    let ids = List.map fst rows in
    if List.length ids <> List.length (List.sort_uniq String.compare ids) then
      Error Duplicate_constituent
    else if ids <> expected_ids then Error Denominator_mismatch
    else
      match List.find_opt (fun (_, digest) -> not (valid_digest digest)) rows with
      | Some (id, _) -> Error (Invalid_digest id)
      | None ->
          let framed =
            List.map
              (fun (id, digest) -> Jj_id.length_frame [ id; digest ])
              rows
          in
          Jj_id.length_frame (schema_id :: framed)
          |> Digestif.SHA256.digest_string
          |> Digestif.SHA256.to_hex
          |> Result.ok
end

let source_digest () =
  match unavailable_constituents () with
  | _ :: _ as gaps -> Error gaps
  | [] ->
      let rows =
        List.map
          (fun row ->
            match row.availability with
            | Available digest -> (row.id, digest)
            | Unavailable Missing_digest_accessor -> assert false)
          constituents
      in
      (match For_test.compose rows with
       | Ok digest -> Ok digest
       | Error _ -> assert false)
