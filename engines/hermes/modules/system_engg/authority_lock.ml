open Yojson.Safe.Util

type locked_status = Admitted | Unavailable_observed | Rejected_by_policy

type locked_entry = {
  manifest_digest : Source_artifact.Sha256.t;
  authority_id : Source_artifact.Id.t;
  resolved_revision : string option;
  content_digest : Source_artifact.Sha256.t option;
  license_policy_digest : Source_artifact.Sha256.t;
  status : locked_status;
  reason : string option;
}

type t = locked_entry list

let string_of_status = function
  | Admitted -> "Admitted"
  | Unavailable_observed -> "Unavailable_observed"
  | Rejected_by_policy -> "Rejected_by_policy"

let status_of_string = function
  | "Admitted" -> Ok Admitted
  | "Unavailable_observed" -> Ok Unavailable_observed
  | "Rejected_by_policy" -> Ok Rejected_by_policy
  | s -> Error ("Invalid status: " ^ s)

let decode_entry json =
  try
    let md_str = json |> member "manifest_digest" |> to_string in
    let aid_str = json |> member "authority_id" |> to_string in
    let rev_opt = json |> member "resolved_revision" |> to_string_option in
    let cd_str_opt = json |> member "content_digest" |> to_string_option in
    let lpd_str = json |> member "license_policy_digest" |> to_string in
    let status_str = json |> member "status" |> to_string in
    let reason_opt = json |> member "reason" |> to_string_option in

    match Source_artifact.Sha256.of_hex md_str,
          Source_artifact.Id.make aid_str,
          Source_artifact.Sha256.of_hex lpd_str,
          status_of_string status_str with
    | Ok manifest_digest, Ok authority_id, Ok license_policy_digest, Ok status ->
        let content_digest =
          match cd_str_opt with
          | None -> None
          | Some cd -> (match Source_artifact.Sha256.of_hex cd with Ok x -> Some x | Error _ -> None)
        in
        Ok { manifest_digest; authority_id; resolved_revision = rev_opt; content_digest; license_policy_digest; status; reason = reason_opt }
    | _ -> Error "Validation of parsed hex digests or IDs failed"
  with exn -> Error (Printexc.to_string exn)

let decode_strict json =
  try
    let entries_json = json |> member "entries" |> to_list in
    let decoded = List.map decode_entry entries_json in
    let errors = List.filter_map (function Error e -> Some e | Ok _ -> None) decoded in
    if errors <> [] then Error errors
    else Ok (List.filter_map (function Ok x -> Some x | Error _ -> None) decoded)
  with exn -> Error [Printexc.to_string exn]

let encode_entry e =
  let assoc = [
    ("manifest_digest", `String (Source_artifact.Sha256.to_hex e.manifest_digest));
    ("authority_id", `String (Source_artifact.Id.to_string e.authority_id));
    ("resolved_revision", match e.resolved_revision with None -> `Null | Some s -> `String s);
    ("content_digest", match e.content_digest with None -> `Null | Some s -> `String (Source_artifact.Sha256.to_hex s));
    ("license_policy_digest", `String (Source_artifact.Sha256.to_hex e.license_policy_digest));
    ("status", `String (string_of_status e.status));
    ("reason", match e.reason with None -> `Null | Some s -> `String s);
  ] in
  `Assoc assoc

let encode_canonical t =
  `Assoc [("entries", `List (List.map encode_entry t))]

let validate_against ~manifest t =
  let errors = ref [] in
  let manifest_entries = Authority_manifest.entries manifest in
  List.iter (fun m_entry ->
    let aid_str = (Authority_manifest.id m_entry :> string) in
    let matched_opt = List.find_opt (fun l_entry ->
      String.equal (l_entry.authority_id :> string) aid_str
    ) t in
    match matched_opt with
    | None -> errors := ("Missing locked entry for " ^ aid_str) :: !errors
    | Some l_entry ->
        (* Verify status compatibility *)
        match Authority_manifest.disposition m_entry, l_entry.status with
        | Exact _, Admitted -> ()
        | Unavailable_observed _, Unavailable_observed -> ()
        | Rejected_by_policy _, Rejected_by_policy -> ()
        | _ -> errors := ("Status mismatch for " ^ aid_str) :: !errors
  ) manifest_entries;
  if !errors = [] then Ok () else Error !errors