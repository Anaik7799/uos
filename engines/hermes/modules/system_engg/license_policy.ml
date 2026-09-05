type license_id =
  | Apache_2_0 | EPL_2_0 | GPL_3_0_only | CC_BY_4_0
  | Omg_specification_terms | No_assertion | Other_terms of string

type intended_use =
  | Download | Local_analysis | Execute | Modify
  | Link_and_hash | Redistribute_verbatim | Redistribute_excerpt
  | Create_derivative

type decision =
  | Permit
  | Permit_with_obligations of string list
  | Review_required of string
  | Reject of string

type evidence = {
  terms_uri : Uri.t;
  evidence_path : string option;
  evidence_sha256 : string option;
  copyright : string list;
  notices : string list;
  path_exceptions : string list;
}

type error =
  | Missing_use of intended_use
  | Duplicate_use of intended_use
  | Invalid_evidence of string
  | Embedded_violation of string
  | Rule_violation of string

type t = {
  id : string;
  license : license_id;
  evidence : evidence;
  embedded_third_party : bool;
  decisions : (intended_use * decision) list;
}

type authorization = {
  use : intended_use;
  obligations : string list;
}

let all_uses = [
  Download; Local_analysis; Execute; Modify;
  Link_and_hash; Redistribute_verbatim; Redistribute_excerpt;
  Create_derivative
 ]

let is_valid_sha256 s =
  String.length s = 64 &&
  try
    String.iter (function
      | '0'..'9' | 'a'..'f' | 'A'..'F' -> ()
      | _ -> failwith "invalid hex") s;
    true
  with _ -> false

let make ~id ~license ~evidence ~embedded_third_party ~decisions =
  let errors = ref [] in

  (* LP-TOTAL check *)
  List.iter (fun use ->
    let count = List.length (List.filter (fun (u, _) -> u = use) decisions) in
    if count = 0 then errors := Missing_use use :: !errors
    else if count > 1 then errors := Duplicate_use use :: !errors
  ) all_uses;

  (* LP-NO-IMPLICIT-PERMIT check *)
  (match license with
   | No_assertion | Other_terms _ ->
       List.iter (fun (_use, dec) ->
         match dec with
         | Permit | Permit_with_obligations _ ->
             errors := Rule_violation "No_assertion/Other_terms cannot implicitly permit" :: !errors
         | _ -> ()
       ) decisions
   | _ -> ());

  (* LP-NOTICE-CLOSED check *)
  let has_notice =
    List.exists (fun (_, dec) ->
      match dec with Permit_with_obligations _ -> true | _ -> false
    ) decisions || evidence.notices <> []
  in
  if has_notice then begin
    let uri_str = Uri.to_string evidence.terms_uri in
    if uri_str = "" || uri_str = "/" then
      errors := Invalid_evidence "Notice obligation requires non-blank terms_uri" :: !errors;
    match evidence.evidence_sha256 with
    | Some sha ->
        if not (is_valid_sha256 sha) then
          errors := Invalid_evidence "Invalid SHA-256 digest" :: !errors
    | None -> ()
  end;

  (* LP-EMBEDDED-BOUNDARY check *)
  if embedded_third_party then begin
    List.iter (fun (use, dec) ->
      match use, dec with
      | (Modify | Create_derivative), (Permit | Permit_with_obligations _) ->
          errors := Embedded_violation "Embedded third-party content cannot be modified or derivated under container policy" :: !errors
      | _ -> ()
    ) decisions
  end;

  if !errors = [] then Ok { id; license; evidence; embedded_third_party; decisions }
  else Error (List.rev !errors)

let authorize t use =
  match List.assoc_opt use t.decisions with
  | None -> Error (Missing_use use)
  | Some (Reject reason) -> Error (Rule_violation ("Use rejected: " ^ reason))
  | Some (Review_required reason) -> Error (Rule_violation ("Review required: " ^ reason))
  | Some Permit -> Ok { use; obligations = [] }
  | Some (Permit_with_obligations obs) -> Ok { use; obligations = obs }

let string_of_license = function
  | Apache_2_0 -> "Apache_2_0"
  | EPL_2_0 -> "EPL_2_0"
  | GPL_3_0_only -> "GPL_3_0_only"
  | CC_BY_4_0 -> "CC_BY_4_0"
  | Omg_specification_terms -> "Omg_specification_terms"
  | No_assertion -> "No_assertion"
  | Other_terms s -> "Other_terms:" ^ s

let string_of_use = function
  | Download -> "Download"
  | Local_analysis -> "Local_analysis"
  | Execute -> "Execute"
  | Modify -> "Modify"
  | Link_and_hash -> "Link_and_hash"
  | Redistribute_verbatim -> "Redistribute_verbatim"
  | Redistribute_excerpt -> "Redistribute_excerpt"
  | Create_derivative -> "Create_derivative"

let string_of_decision = function
  | Permit -> "Permit"
  | Permit_with_obligations obs -> "Permit_with_obligations:" ^ (String.concat "," obs)
  | Review_required r -> "Review_required:" ^ r
  | Reject r -> "Reject:" ^ r

let canonical t =
  let decs_str =
    t.decisions
    |> List.map (fun (u, d) -> string_of_use u ^ "=" ^ string_of_decision d)
    |> String.concat ";"
  in
  Printf.sprintf "id=%s;license=%s;uri=%s;embedded=%b;decisions=[%s]"
    t.id
    (string_of_license t.license)
    (Uri.to_string t.evidence.terms_uri)
    t.embedded_third_party
    decs_str

let digest t =
  Digestif.SHA256.digest_string (canonical t)