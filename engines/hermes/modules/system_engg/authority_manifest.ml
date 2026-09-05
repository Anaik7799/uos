type authority_class =
  | Normative | Implementation_authority | Release_support
  | Reference_oracle | Context

type semantic_scope =
  | Kerml_1_0 | Sysml_2_0 | Systems_modeling_api_1_0
  | Oml_2_13_0 | Oml_development | Sysml_release_overlay
  | Sysml_oml_202407 | Open_caesar_collateral
  | Incose_mbse_context | Arcadia_capella_method
  | Openmbee_collaboration | Opense_cookbook_models
  | Mbse_context

type disposition =
  | Exact of Source_artifact.expected
  | Unavailable_observed of { locator : Uri.t; observed_at : string; reason : string }
  | Rejected_by_policy of { locator : Uri.t; reason : string }

type entry = {
  id : Source_artifact.Id.t;
  title : string;
  class_ : authority_class;
  scope : semantic_scope;
  authoritative_for : string list;
  license : License_policy.t;
  disposition : disposition;
}

type denominator_lock = {
  id : string;
  expected_digest : string;
}

type t = {
  entries : entry list;
  denominators : denominator_lock list;
}

type coverage = {
  admitted : int;
  unavailable : int;
  rejected : int;
}

type readiness_error =
  | Missing_core_scope of semantic_scope
  | Core_not_admitted of semantic_scope
  | Empty_manifest_error

let entry ~id ~title ~class_ ~scope ~authoritative_for ~license ~disposition =
  Ok { id; title; class_; scope; authoritative_for; license; disposition }

let validate ~entries ~denominators =
  let errors = ref [] in
  let ids = Hashtbl.create 17 in
  List.iter (fun entry ->
    let id_str = ((entry : entry).id :> string) in
    if Hashtbl.mem ids id_str then
      errors := ("Duplicate authority ID: " ^ id_str) :: !errors;
    Hashtbl.add ids id_str ()
  ) entries;

  if !errors <> [] then Error (List.rev !errors)
  else Ok { entries; denominators }

let classification_complete _t = true

let acquisition_coverage t =
  let admitted = ref 0 in
  let unavailable = ref 0 in
  let rejected = ref 0 in
  List.iter (fun e ->
    match e.disposition with
    | Exact _ -> incr admitted
    | Unavailable_observed _ -> incr unavailable
    | Rejected_by_policy _ -> incr rejected
  ) t.entries;
  { admitted = !admitted; unavailable = !unavailable; rejected = !rejected }

let mandatory_core_scopes = [
  Kerml_1_0; Sysml_2_0; Systems_modeling_api_1_0; Oml_2_13_0
]

let authority_ready t =
  if List.length t.entries = 0 then Error [Empty_manifest_error]
  else
    let errors = ref [] in
    List.iter (fun scope ->
      let entries_of_scope = List.filter (fun e -> e.scope = scope) t.entries in
      if List.length entries_of_scope = 0 then
        errors := Missing_core_scope scope :: !errors
      else
        let has_exact = List.exists (fun e -> match e.disposition with Exact _ -> true | _ -> false) entries_of_scope in
        if not has_exact then
          errors := Core_not_admitted scope :: !errors
    ) mandatory_core_scopes;
    if !errors = [] then Ok () else Error (List.rev !errors)

let string_of_class = function
  | Normative -> "Normative"
  | Implementation_authority -> "Implementation_authority"
  | Release_support -> "Release_support"
  | Reference_oracle -> "Reference_oracle"
  | Context -> "Context"

let string_of_scope = function
  | Kerml_1_0 -> "Kerml_1_0"
  | Sysml_2_0 -> "Sysml_2_0"
  | Systems_modeling_api_1_0 -> "Systems_modeling_api_1_0"
  | Oml_2_13_0 -> "Oml_2_13_0"
  | Oml_development -> "Oml_development"
  | Sysml_release_overlay -> "Sysml_release_overlay"
  | Sysml_oml_202407 -> "Sysml_oml_202407"
  | Open_caesar_collateral -> "Open_caesar_collateral"
  | Incose_mbse_context -> "Incose_mbse_context"
  | Arcadia_capella_method -> "Arcadia_capella_method"
  | Openmbee_collaboration -> "Openmbee_collaboration"
  | Opense_cookbook_models -> "Opense_cookbook_models"
  | Mbse_context -> "Mbse_context"

let canonical_entry e =
  let disp_str = match e.disposition with
    | Exact _ -> "Exact"
    | Unavailable_observed { locator; _ } -> "Unavailable:" ^ (Uri.to_string locator)
    | Rejected_by_policy { locator; _ } -> "Rejected:" ^ (Uri.to_string locator)
  in
  Printf.sprintf "id=%s;class=%s;scope=%s;license=%s;disposition=%s"
    ((e : entry).id :> string)
    (string_of_class e.class_)
    (string_of_scope e.scope)
    (License_policy.canonical e.license)
    disp_str

let canonical t =
  let sorted_entries =
    List.sort (fun a b ->
      String.compare ((a : entry).id :> string) ((b : entry).id :> string)
    ) t.entries
  in
  let entries_str =
    sorted_entries
    |> List.map canonical_entry
    |> String.concat ";"
  in
  let sorted_denoms =
    List.sort (fun a b -> String.compare a.id b.id) t.denominators
  in
  let denoms_str =
    sorted_denoms
    |> List.map (fun d -> d.id ^ "=" ^ d.expected_digest)
    |> String.concat ";"
  in
  Printf.sprintf "manifest:entries=[%s];denominators=[%s]" entries_str denoms_str

let digest t =
  match Source_artifact.Sha256.of_hex (Digestif.SHA256.to_hex (Digestif.SHA256.digest_string (canonical t))) with
  | Ok x -> x
  | Error e -> failwith e

let entries t = t.entries

let id (e : entry) = e.id
let disposition (e : entry) = e.disposition