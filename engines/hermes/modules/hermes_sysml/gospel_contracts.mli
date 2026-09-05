(* modules/hermes_sysml/gospel_contracts.mli *)

type ooda_state =
  | Idle
  | Observe
  | Orient
  | Decide
  | Act

type context = {
  anomaly_detected : bool;
  data_ready : bool;
  decision_made : bool;
  action_complete : bool;
}

(* Every [context] record has the complete OODA input shape above.  The
   representation is public, so this is explanatory prose rather than a Gospel
   type invariant: Gospel permits invariants only on abstract types. *)
val next_state : ooda_state -> context -> ooda_state
(*@ s' = next_state s ctx
    ensures ctx.anomaly_detected -> s' = Observe
    ensures not ctx.anomaly_detected ->
      match s with
      | Idle -> if ctx.data_ready then s' = Observe else s' = Idle
      | Observe -> if ctx.data_ready then s' = Orient else s' = Observe
      | Orient -> if ctx.decision_made then s' = Decide else s' = Orient
      | Decide -> if ctx.decision_made then s' = Act else s' = Decide
      | Act -> if ctx.action_complete then s' = Idle else s' = Act

    ensures s' = Idle || s' = Observe || s' = Orient || s' = Decide || s' = Act
*)
