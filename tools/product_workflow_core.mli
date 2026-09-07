(** Pure product evidence algebra. Source presence never grants test credit.
    All containment paths have exactly Product/Feature/Requirement/Acceptance
    levels. Required empty nodes and duplicate identities are rejected. *)
type level = Product | Feature | Requirement | Acceptance
type node = { id : string; parent : string option; level : level; required : bool }
val validate_nodes : node list -> (unit, string) result

type binding = {
  candidate : string; specification : string; oracle : string;
  executable : string; normalizer : string; checker : string;
}
type kind = Runtime | Formal
type receipt = {
  case_id : string; kind : kind; binding : binding; sequence : int;
  observed : float; expires : float; passed : bool;
  artifact_valid : bool; invocation_valid : bool;
}
type state = Unrun | Stale | Blocked | Failed | Passed
type verdict = { state : state; reasons : string list }
val state_name : state -> string
(** Latest receipt wins per case/kind. Both kinds must match every expected
    identity, be current, and retain validated artifact/invocation evidence.
    Future timestamps, equal sequence ambiguity, absence and failed evidence
    withhold credit. A passing verdict is evidence readiness, not admission. *)
val evaluate_case : now:float -> source_current:bool -> expected:binding ->
  case_id:string -> receipt list -> verdict
val roll_up : verdict list -> verdict
(** Executable finite model used in independent reference comparison. *)
val eligible_bits : bool list -> bool
