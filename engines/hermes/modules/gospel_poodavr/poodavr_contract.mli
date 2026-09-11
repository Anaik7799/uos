(* [UOS-HERMES-GOSPEL] POODAVR 7-Stage Cybernetic Loop & 17-Aspect Contract
   Governing contracts: SC-POODAVR-001, SC-FPRIME-001, SC-INTENT-ATLAS-001, SC-JIDOKA-001 *)

type poodavr_phase =
  | Predict
  | Observe
  | Orient
  | Decide
  | Act
  | Verify
  | Reflect
  | ConstitutionalHalt

val phase_to_string : poodavr_phase -> string

val hard_denied_system_os_serial : string

type poodavr_intent = {
  intent_id : string;
  target_disk : string;
  is_ledgered_in_sa_plan : bool;
  health_ppm : int;
}

type poodavr_state = {
  phase : poodavr_phase;
  causal_epoch : int;
  halt_code : int option;
  receipt_sha256 : string option;
}

(*@ val is_safe_intent : poodavr_intent -> bool
    ensures result = (intent.target_disk <> hard_denied_system_os_serial
                      && intent.is_ledgered_in_sa_plan
                      && intent.health_ppm >= 850000) *)
val is_safe_intent : poodavr_intent -> bool

(*@ val orient_step : poodavr_intent -> poodavr_state -> poodavr_state
    ensures is_safe_intent intent -> result.phase = Decide
    ensures not (is_safe_intent intent) ->
              result.phase = ConstitutionalHalt && result.halt_code = Some (-32002) *)
val orient_step : poodavr_intent -> poodavr_state -> poodavr_state

(*@ val verify_step : bool -> poodavr_state -> poodavr_state
    ensures ok -> result.phase = Reflect && result.causal_epoch = st.causal_epoch + 1
    ensures not ok -> result.phase = ConstitutionalHalt && result.halt_code = Some (-32003) *)
val verify_step : bool -> poodavr_state -> poodavr_state

(* 17 Canonical UOS System Aspects *)
type aspect_status = AspectActive | AspectDegraded | AspectHalted

type aspect_entry = {
  id : int;
  name : string;
  domain : string;
  authority : string;
  status : aspect_status;
  description : string;
}

val all_17_aspects : unit -> aspect_entry list
val verify_aspect_coverage : aspect_entry list -> bool
