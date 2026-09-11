(* [UOS-HERMES-GOSPEL] 15 Continuous Evolutionary Cycles Contract (EV-111 .. EV-125)
   Governing contracts: SC-HA-001, SC-SOV-001, SC-POODAVR-001, SC-CHECKLIST-001 *)

type sovereign_id = AGY | Claude | Codex | OpenRouter

type cycle_record = {
  cycle_num : int;
  ev_tag : string;
  title : string;
  target_aspects : int list;
  target_layer : int;
  expected_gain_pct : float;
  risk_score : float;
}

type quorum_ballot = {
  cycle_num : int;
  approvals : sovereign_id list;
  rejections : sovereign_id list;
  is_ratified : bool;
}

type cycle_receipt = {
  cycle_num : int;
  ev_tag : string;
  generation : int;
  lyapunov_energy_prior : float;
  lyapunov_energy_posterior : float;
  receipt_sha256 : string;
}

val all_15_cycles : unit -> cycle_record list

(*@ val is_aspect_covered : int -> cycle_record list -> bool
    ensures result = true <-> (List.exists (fun c -> List.mem aspect_id c.target_aspects) cycles) *)
val is_aspect_covered : int -> cycle_record list -> bool

(*@ val verify_full_17_aspect_completeness : cycle_record list -> bool
    ensures result = true <-> (forall a. 1 <= a && a <= 17 -> is_aspect_covered a cycles) *)
val verify_full_17_aspect_completeness : cycle_record list -> bool

(*@ val ratify_cycle : quorum_ballot -> bool
    ensures result = true <-> List.length ballot.approvals >= 3 *)
val ratify_cycle : quorum_ballot -> bool

(*@ val apply_evolution_step : int -> float -> cycle_record -> cycle_receipt
    ensures result.generation = current_gen + 1
    ensures result.lyapunov_energy_posterior <= current_energy *)
val apply_evolution_step : int -> float -> cycle_record -> cycle_receipt
