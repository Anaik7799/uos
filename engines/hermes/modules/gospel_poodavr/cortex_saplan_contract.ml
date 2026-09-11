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

let hard_denied_serial = "25503L801736"
let jidoka_halt_code = -32002

let init_coordinator () = {
  total_dispatched = 0;
  total_completed = 0;
  andon_active = false;
}

let contains_substr s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let rec check i =
      if i + len_sub > len_s then false
      else if String.sub s i len_sub = sub then true
      else check (i + 1)
    in
    check 0

let coordinate_intent st intent worker now_ns =
  if contains_substr intent.raw_text hard_denied_serial then
    (VerdictHardDenied { serial = hard_denied_serial }, { st with andon_active = true })
  else if contains_substr intent.raw_text "bypass_sa_plan" then
    (VerdictHaltAndon { code = jidoka_halt_code; reason = "Andon Halt" }, { st with andon_active = true })
  else
    let task_id = "task-" ^ intent.id in
    let receipt = "sha256-receipt-" ^ task_id ^ "-" ^ worker ^ "-" ^ string_of_int now_ns in
    let st' = {
      total_dispatched = st.total_dispatched + 1;
      total_completed = st.total_completed + 1;
      andon_active = false;
    } in
    (VerdictSuccess { task_id; receipt_sha256 = receipt; execution_ms = 50 }, st')
