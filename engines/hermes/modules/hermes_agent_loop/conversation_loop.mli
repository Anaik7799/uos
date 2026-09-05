(** L3 contract: Conversation turn loop management and state machine.

    Reference capability: [agent_loop.conversation_loop]
    Frozen anchor: [agent_loop.conversation_loop.70b2efe95be5.json]
*)

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

(*@ predicate valid_model_id (s: string) =
      s <> "" *)

(*@ predicate valid_state (st: turn_state) =
      st.message_count >= 0 && valid_model_id st.model_id *)

val init_state : model_id:string -> max_turns:int -> turn_state
(*@ st = init_state ~model_id ~max_turns
    pure
    requires valid_model_id model_id
    ensures valid_state st
    ensures st.step = Init
    ensures st.message_count = 0
    ensures st.model_id = model_id *)

val is_complete : turn_state -> bool
(*@ b = is_complete st
    pure
    requires valid_state st
    ensures b <-> (st.step = Complete || st.step = Interrupted) *)

val step_turn : turn_state -> messages:Yojson.Safe.t list -> turn_state * Yojson.Safe.t list
(*@ st', sanitized = step_turn st ~messages
    requires valid_state st
    ensures valid_state st'
    ensures st'.model_id = st.model_id
    ensures st'.step = Init || st'.step = UserInput || st'.step = AssistantResponse || st'.step = ToolCall || st'.step = Complete || st'.step = Interrupted *)

val process : model_id:string -> messages:Yojson.Safe.t list -> Yojson.Safe.t
(*@ res = process ~model_id ~messages
    pure
    requires valid_model_id model_id *)
