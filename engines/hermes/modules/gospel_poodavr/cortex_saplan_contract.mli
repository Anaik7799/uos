(** Gospel specification for Cortex OODA and Sa-Plan Fenced Execution.
    Enforces SC-COG-001, SC-SA-PLAN-001, SC-JIDOKA-001, and CHK-07-DRIVE. *)

type task_intent = {
  id : string;
  intent_type : string;
  raw_text : string;
  stress_level : float;
  timestamp_ms : int;
}

type execution_verdict =
  | VerdictSuccess of { task_id : string; receipt_sha256 : string; execution_ms : int }
  | VerdictHaltAndon of { code : int; reason : string }
  | VerdictHardDenied of { serial : string }

type coordinator_state = {
  total_dispatched : int;
  total_completed : int;
  andon_active : bool;
}

val hard_denied_serial : string
val jidoka_halt_code : int

val init_coordinator : unit -> coordinator_state

val coordinate_intent :
  coordinator_state -> task_intent -> string -> int -> execution_verdict * coordinator_state
(*@ (verdict, st') = coordinate_intent st intent worker now_ns
    ensures String.contains intent.raw_text hard_denied_serial ->
      verdict = VerdictHardDenied { serial = hard_denied_serial } /\ st'.andon_active = true
    ensures String.contains intent.raw_text "bypass_sa_plan" ->
      verdict = VerdictHaltAndon { code = jidoka_halt_code; reason = "Andon Halt" } /\ st'.andon_active = true
    ensures not (String.contains intent.raw_text hard_denied_serial) /\ not (String.contains intent.raw_text "bypass_sa_plan") ->
      st'.total_dispatched = st.total_dispatched + 1 /\ st'.total_completed = st.total_completed + 1 *)
