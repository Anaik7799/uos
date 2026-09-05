(** Pure typed authority for the generic dependability FPP projection. *)

type component = { stable_id : string; purpose : string }
type direction = Input | Output

type port_kind =
  | Intent
  | Admitted_plan
  | Effect_request
  | Attempt_receipt
  | Formal_receipt
  | Evidence
  | Diagnostic

type port = {
  stable_id : string;
  component_id : string;
  name : string;
  direction : direction;
  kind : port_kind;
}

type edge = {
  stable_id : string;
  from_component : string;
  from_port : string;
  to_component : string;
  to_port : string;
  kind : port_kind;
}

type command = {
  stable_id : string;
  component_id : string;
  fpp_name : string;
}

type channel = {
  stable_id : string;
  component_id : string;
  metric_id : string option;
  fpp_name : string;
}

type lifecycle_transition = { signal : string; target_state : string }
type lifecycle_state = {
  stable_id : string;
  transitions : lifecycle_transition list;
}

type lifecycle = {
  stable_id : string;
  component_id : string;
  initial_state : string;
  states : lifecycle_state list;
}

type requirement = {
  stable_id : string;
  statement : string;
  verifier_id : string;
  covered_elements : string list;
}

type authority = {
  components : component list;
  ports : port list;
  edges : edge list;
  commands : command list;
  channels : channel list;
  lifecycle : lifecycle;
  requirements : requirement list;
}

val authority : authority
val model : Fpp_model.model
val to_fpp_model : authority -> Fpp_model.model
val source_digest : string
val source_digest_of : authority -> string
(*@ ensures String.length result = 64 *)
val source_digest_of_model : Fpp_model.model -> string option
val dictionary : unit -> (Yojson.Safe.t, string) result

val lifecycle_paths : lifecycle -> string list list
val identifier_gaps : authority -> string list
(*@ ensures List.length result >= 0 *)
val port_flow_gaps : authority -> string list
val projection_gaps : authority -> Fpp_model.model -> string list
val validate_authority : authority -> string list
val validate : unit -> string list
(*@ ensures result = [] -> authority.components <> [] *)

(** Check the complete half-open identifier intervals of this authority against
    the supplied FPP models. Invalid or overlapping intervals are gaps. *)
val window_gaps : others:(string * Fpp_model.model) list -> string list
(*@ ensures List.length result >= 0 *)
