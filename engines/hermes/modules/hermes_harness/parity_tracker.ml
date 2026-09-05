(** Truthful, snapshot-local projection of durable capability-cell evidence. *)

type summary = {
  total : int;
  unmapped : int;
  specified : int;
  implemented : int;
  verified : int;
  approved_divergence : int;
  completed : int;
  completion_percent : int;
  strict_percent : int;
  strict_completion : bool;
}

type feature_status = Unmapped | Specified | Implemented | Verified | Approved_divergence
type feature_cell = { feature : Feature_catalog.feature; status : feature_status; blocking_domains : string list }

let feature_status_of_string = function
  | "specified" -> Specified | "implemented" -> Implemented | "verified" -> Verified
  | "approved_divergence" -> Approved_divergence | _ -> Unmapped

let rank = function Unmapped -> 0 | Specified -> 1 | Implemented -> 2 | Verified | Approved_divergence -> 3

let derive_feature_cell feature cells =
  let statuses =
    List.map (fun domain -> match List.find_opt (fun (name, _, _, _) -> name = domain) cells with
      | Some (_, _, _, status) -> (domain, feature_status_of_string status) | None -> (domain, Unmapped)) feature.Feature_catalog.source_domains
  in
  let blocking_domains = List.filter_map (fun (domain, status) -> if rank status < 3 then Some domain else None) statuses in
  let status =
    if List.exists (fun (_, status) -> status = Unmapped) statuses then Unmapped
    else if List.exists (fun (_, status) -> status = Specified) statuses then Specified
    else if List.exists (fun (_, status) -> status = Implemented) statuses then Implemented
    else if List.exists (fun (_, status) -> status = Approved_divergence) statuses then Approved_divergence
    else Verified
  in { feature; status; blocking_domains }

let feature_status_string = function Unmapped -> "unmapped" | Specified -> "specified" | Implemented -> "implemented" | Verified -> "verified" | Approved_divergence -> "approved_divergence"

let features_of_rows rows =
  List.map
    (fun (id, label, source_domains) -> { Feature_catalog.id; label; source_domains })
    rows

let summarize cells =
  let count status =
    List.fold_left (fun total (_, _, _, cell_status) -> if cell_status = status then total + 1 else total) 0 cells
  in
  let total = List.length cells in
  let unmapped = count "unmapped" in
  let specified = count "specified" in
  let implemented = count "implemented" in
  let verified = count "verified" in
  let approved_divergence = count "approved_divergence" in
  let completed = verified + approved_divergence in
  let completion_percent = if total = 0 then 0 else (completed * 100) / total in
  let strict_percent = if total = 0 then 0 else (verified * 100) / total in
  { total; unmapped; specified; implemented; verified; approved_divergence;
    completed; completion_percent; strict_percent; strict_completion = total > 0 && verified = total }

let summarize_features feature_cells =
  let rows = List.map (fun cell -> (cell.feature.id, 0, "", feature_status_string cell.status)) feature_cells in summarize rows

let load store ~snapshot_digest =
  match Evidence_store.cells store ~snapshot_digest with
  | Error _ as error -> error
  | Ok [] -> Error "no capability cells recorded for snapshot"
  | Ok cells -> Ok (summarize cells)

let load_features store ~snapshot_digest =
  match Evidence_store.cells store ~snapshot_digest, Evidence_store.features store ~snapshot_digest with
  | Error message, _ | _, Error message -> Error message
  | Ok [], _ -> Error "no capability cells recorded for snapshot"
  | _, Ok [] -> Error "no feature catalog recorded for snapshot"
  | Ok cells, Ok feature_rows ->
      let feature_cells =
        List.map (fun feature -> derive_feature_cell feature cells) (features_of_rows feature_rows)
      in
      Ok (feature_cells, summarize_features feature_cells)
