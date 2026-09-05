type staging_root = {
  project_root : string;
  path : string;
}

type promotion = {
  source : string;
  destination : string;
}

type verified_batch = {
  receipts : Source_artifact.receipt list;
  promotions : promotion list;
}

type error =
  | Verifier_not_implemented
  | Invalid_staging_root of string
  | Missing_member of string
  | Verification_failure of string
  | Destination_conflict of string

let staging_root ~project_root path =
  if String.length path = 0 then Error (Invalid_staging_root "Empty path")
  else Ok { project_root; path }

let verify_one ~manifest ~staged_root ~(authority_id : Source_artifact.Id.t) =
  let m_entries = Authority_manifest.entries manifest in
  let matched_opt = List.find_opt (fun e ->
    String.equal (Authority_manifest.id e :> string) (authority_id :> string)
  ) m_entries in
  match matched_opt with
  | None -> Error [Missing_member (authority_id :> string)]
  | Some m_entry ->
      match Authority_manifest.disposition m_entry with
      | Exact expected ->
          let item_path = Filename.concat staged_root.path (authority_id :> string) in
          let obs_res = match Source_artifact.pin expected with
            | Blob_pin _ -> Source_artifact.observe_blob ~path:item_path
            | Git_tree_pin _ -> Source_artifact.observe_git_tree ~root:item_path
          in
          (match obs_res with
           | Error e -> Error [Verification_failure e]
           | Ok obs ->
               match Source_artifact.verify expected obs with
               | Ok r -> Ok r
               | Error _ -> Error [Verification_failure "Digest mismatch"])
      | _ -> Error [Verification_failure "Not an admitted expected artifact"]

let verify_batch ~manifest ~lock ~staged_root =
  let m_entries = Authority_manifest.entries manifest in
  let rec verify_all acc_receipts acc_promotions = function
    | [] -> Ok { receipts = List.rev acc_receipts; promotions = List.rev acc_promotions }
    | m_entry :: rest ->
        let aid = Authority_manifest.id m_entry in
        match verify_one ~manifest ~staged_root ~authority_id:aid with
        | Error errs -> Error errs
        | Ok r ->
            let src = Filename.concat staged_root.path (aid :> string) in
            let dest = Filename.concat "external/system_engg" (aid :> string) in
            let promo = { source = src; destination = dest } in
            verify_all (r :: acc_receipts) (promo :: acc_promotions) rest
  in
  (* Check that lock is compatible with manifest first *)
  match Authority_lock.validate_against ~manifest lock with
  | Error errs -> Error (List.map (fun e -> Verification_failure e) errs)
  | Ok () ->
      verify_all [] [] m_entries

let receipts batch = batch.receipts
let promotion_plan batch = batch.promotions