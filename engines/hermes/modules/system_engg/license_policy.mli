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

type t
type authorization

type error =
  | Missing_use of intended_use
  | Duplicate_use of intended_use
  | Invalid_evidence of string
  | Embedded_violation of string
  | Rule_violation of string

val make :
  id:string -> license:license_id -> evidence:evidence ->
  embedded_third_party:bool ->
  decisions:(intended_use * decision) list ->
  (t, error list) result
val authorize : t -> intended_use -> (authorization, error) result
val canonical : t -> string
val digest : t -> Digestif.SHA256.t