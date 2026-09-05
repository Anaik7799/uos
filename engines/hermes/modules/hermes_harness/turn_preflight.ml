(** Single pure admission gate for a chat-completions turn. *)

type rejection = Missing_credentials | Exhausted

type ready = {
  budget : Turn_budget.t;
  request : Openrouter_contract.request;
}

type result = Ready of ready | Rejected of rejection * Turn_budget.t

let prepare ~budget ~credentials ~model ~messages ~reasoning ~supports_reasoning
    ~session_id ~provider_preferences ~pareto_min_coding_score =
  let resolved = Openrouter_contract.resolve_credentials credentials in
  match resolved.api_key with
  | None -> Rejected (Missing_credentials, budget)
  | Some _ ->
      let consumed = Turn_budget.consume budget in
      if not consumed.allowed then Rejected (Exhausted, budget)
      else
        let sanitized = Message_hygiene.sanitize_messages ~model_id:model messages in
        let request =
          Openrouter_contract.build ~credentials ~model_id:model ~messages:sanitized ~reasoning
            ~supports_reasoning ~session_id ~provider_preferences
            ~pareto_min_coding_score ()
        in
        Ready { budget = consumed.budget; request }
