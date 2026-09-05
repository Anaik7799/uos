type domain =
  | Authority | Prompting | Surfaces | Fractal | Fast_ooda
  | Sysml | Oml | Openmbee | Fpp | Formal
  | Safety | Reliability | Security | Provenance | Supply_chain
  | Lifecycle | Evidence | Observability | Metrics | Performance
  | Recovery | Data_governance | Human_control | Publication

type obligation = {
  id : string;
  domain : domain;
  title : string;
  guidance : string;
  command : string;
  declaration_id : string;
  plane : Ops_capability.plane;
  path : Ops_capability.coordinate list;
  required_evidence : Ops_capability.evidence list;
  gates : string list;
  metric : string;
  completion_criterion : string;
}

type sop_step = {
  step_id : string;
  phase : Ops_capability.ooda_phase;
  title : string;
  command : string;
  dependencies : string list;
  completion_criterion : string;
}

val obligations : obligation list
val whole_system_sop : sop_step list
val string_of_domain : domain -> string
val validate : unit -> string list
val render_guidance : unit -> string
val guidance_path : string
val write_guidance : unit -> unit
val check_guidance : unit -> (unit, string) result
val find_obligation : string -> obligation option
val render_obligation : obligation -> string
