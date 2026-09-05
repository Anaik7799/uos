type turn_step =
  | Init
  | UserInput
  | AssistantResponse
  | ToolCall
  | Complete
  | Interrupted

type turn_state = {
  step : turn_step;
  model_id : string;
  message_count : int;
  budget : Turn_budget.t;
}

let init_state ~model_id ~max_turns =
  let max_turns = if max_turns < 0 then 0 else max_turns in
  let budget = Turn_budget.create max_turns in
  { step = Init; model_id; message_count = 0; budget }

let is_complete st =
  match st.step with
  | Complete | Interrupted -> true
  | _ -> false

let has_tool_calls message =
  match message with
  | `Assoc fields -> (
      match List.assoc_opt "tool_calls" fields with
      | Some (`List (_ :: _)) -> true
      | _ -> (
          match List.assoc_opt "role" fields with
          | Some (`String "tool") -> true
          | _ -> false))
  | _ -> false

let step_turn st ~messages =
  let consume_res = Turn_budget.consume st.budget in
  if not consume_res.allowed then
    let st' = { st with step = Interrupted; budget = consume_res.budget } in
    let sanitized = Message_hygiene.sanitize_messages ~model_id:st.model_id messages in
    (st', sanitized)
  else
    let sanitized = Message_hygiene.sanitize_messages ~model_id:st.model_id messages in
    let count = List.length sanitized in
    let next_step =
      if count = 0 then Complete
      else
        let last_msg = List.nth sanitized (count - 1) in
        if has_tool_calls last_msg then ToolCall
        else
          match last_msg with
          | `Assoc fields -> (
              match List.assoc_opt "role" fields with
              | Some (`String "assistant") -> Complete
              | Some (`String "user") -> AssistantResponse
              | _ -> Complete)
          | _ -> Complete
    in
    let st' =
      {
        step = next_step;
        model_id = st.model_id;
        message_count = st.message_count + 1;
        budget = consume_res.budget;
      }
    in
    (st', sanitized)

let process ~model_id ~messages =
  let sanitized = Message_hygiene.sanitize_messages ~model_id messages in
  `Assoc [ ("messages", `List sanitized); ("model", `String model_id) ]
