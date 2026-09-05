let string_of_status = function
  | Core.Pending -> "PENDING"
  | Core.Passed -> "PASSED"
  | Core.Failed message -> "FAILED: " ^ message

let render_checks checks =
  checks
  |> List.map (fun (name, status) -> name ^ ": " ^ string_of_status status)
  |> String.concat "\n"

let render_readiness status = "readiness: " ^ string_of_status status

let render_manifest summaries =
  summaries
  |> List.map (fun (summary : Inventory.domain_summary) ->
         String.concat "\t"
           [ summary.domain; string_of_int summary.file_count; summary.digest; "unmapped" ])
  |> String.concat "\n"

let render_parity (summary : Parity_tracker.summary) =
  String.concat "\n"
    [ "parity_total: " ^ string_of_int summary.total;
      "parity_completed: " ^ string_of_int summary.completed;
      "parity_percent: " ^ string_of_int summary.completion_percent;
      "parity_strict_percent: " ^ string_of_int summary.strict_percent;
      "parity_verified: " ^ string_of_int summary.verified;
      "parity_approved_divergence: " ^ string_of_int summary.approved_divergence;
      "parity_implemented: " ^ string_of_int summary.implemented;
      "parity_specified: " ^ string_of_int summary.specified;
      "parity_unmapped: " ^ string_of_int summary.unmapped;
      "parity_strict_completion: " ^ string_of_bool summary.strict_completion ]

let render_features cells =
  cells
  |> List.map (fun (cell : Parity_tracker.feature_cell) ->
         String.concat "\t" [ cell.feature.id; cell.feature.label;
           Parity_tracker.feature_status_string cell.status;
           String.concat "," cell.blocking_domains ])
  |> String.concat "\n"
