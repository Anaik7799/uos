type turn_receipt = {
  turn_id : string;
  status : string;
  turns_executed : int;
  total_tokens_used : int;
  final_output : string option;
}

type finalizer_summary = {
  receipt : turn_receipt;
  metadata : (string * Yojson.Safe.t) list;
}

let create_receipt ~turn_id ~status ~turns ~tokens ~final_output =
  let turns_executed = if turns < 0 then 0 else turns in
  let total_tokens_used = if tokens < 0 then 0 else tokens in
  let turn_id = if String.length turn_id = 0 then "unknown" else turn_id in
  { turn_id; status; turns_executed; total_tokens_used; final_output }

let summarize receipt ~metadata =
  { receipt; metadata }

let finalize ~model_id ~messages =
  let sanitized = Message_hygiene.sanitize_messages ~model_id messages in
  `Assoc [ ("messages", `List sanitized); ("model", `String model_id) ]
