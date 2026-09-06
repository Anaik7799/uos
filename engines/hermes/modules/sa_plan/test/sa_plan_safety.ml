(** Stratum A safety-packet algebra for Sa-plan bridge transitions.

    A packet names the STPA unsafe control action, its control action/context,
    the fail-closed guard, the FMEA failure mode, and independently inspectable
    evidence coordinates.  Validation is pure: a rejected packet cannot change
    any durable bridge or task state.  The Store/transition interpreter is the
    sole later consumer permitted to bind an accepted packet to a transition. *)

type packet = {
  uca_id : string;
  control_action : string;
  context : string;
  guard : string;
  fmea_id : string;
  failure_mode : string;
  evidence : string list;
}

type error =
  | Missing_uca
  | Missing_control_action
  | Missing_context
  | Missing_guard
  | Missing_fmea
  | Missing_failure_mode
  | Missing_evidence
  | Empty_evidence_coordinate

let nonempty value = not (String.equal "" (String.trim value))

let validate packet =
  if not (nonempty packet.uca_id) then Error Missing_uca
  else if not (nonempty packet.control_action) then Error Missing_control_action
  else if not (nonempty packet.context) then Error Missing_context
  else if not (nonempty packet.guard) then Error Missing_guard
  else if not (nonempty packet.fmea_id) then Error Missing_fmea
  else if not (nonempty packet.failure_mode) then Error Missing_failure_mode
  else if List.is_empty packet.evidence then Error Missing_evidence
  else if List.exists (fun coordinate -> not (nonempty coordinate)) packet.evidence
  then Error Empty_evidence_coordinate
  else Ok ()

(** [bind packet transition] is the transition-boundary combinator.  It invokes
    [transition] only after the safety packet is complete, so a rejected packet
    cannot run a state-changing Store operation. *)
let bind packet transition =
  match validate packet with Error error -> Error error | Ok () -> transition ()

let string_of_error = function
  | Missing_uca -> "missing UCA coordinate"
  | Missing_control_action -> "missing control-action coordinate"
  | Missing_context -> "missing UCA context"
  | Missing_guard -> "missing safety guard coordinate"
  | Missing_fmea -> "missing FMEA coordinate"
  | Missing_failure_mode -> "missing FMEA failure mode"
  | Missing_evidence -> "missing safety evidence coordinate"
  | Empty_evidence_coordinate -> "empty safety evidence coordinate"
