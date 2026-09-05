(** L3 contract: pure OpenRouter request shaping.

    Reference capability: [model_routing.provider_transports]
    Frozen anchors: [agent/transports/base.py],
    [agent/transports/chat_completions.py]

    This module has no network, environment, filesystem or persistence
    dependency: the caller supplies credential candidates and receives a request
    description that can be inspected before transport. That purity is the
    contract's foundation — every function below is [pure], so the shaping can
    be reasoned about without an effect model.

    Gospel limits shaping what is written here: a labelled function cannot be
    applied inside a term, so the obligations on [build] are stated over its
    result rather than by applying it, and the round-trip properties live in
    the L4 fixtures instead. Specification parameters avoid [model], a Gospel
    keyword. *)

val default_base_url : string
val default_models_url : string

type credentials = {
  supplied_key : string option;
  openrouter_key : string option;
  openai_key : string option;
  base_url_override : string option;
}

type resolved_credentials = { base_url : string; api_key : string option }

type reasoning = Unspecified | Disabled | Effort of string

type request = {
  endpoint : string;
  api_key : string option;
  body : Yojson.Safe.t;
}

val nonempty : string option -> string option
(*@ trimmed = nonempty value
    pure *)

(*@ axiom nonempty_idempotent:
      forall value: string option. nonempty (nonempty value) = nonempty value *)

val host_of_url : string -> string
(*@ host = host_of_url url
    pure *)

val is_openrouter_url : string -> bool
(*@ verdict = is_openrouter_url url
    pure *)

val first_key : string option list -> string option
(*@ key = first_key candidates
    pure *)

(*@ axiom first_key_of_none:
      forall candidates: string option list.
        candidates = [] -> first_key candidates = None *)

val resolve_credentials : credentials -> resolved_credentials
(*@ resolved = resolve_credentials creds
    pure
    ensures resolved.base_url <> "" *)

val valid_efforts : string list

val parse_reasoning : string -> reasoning
(*@ level = parse_reasoning value
    pure *)

val build :
  credentials:credentials ->
  model_id:string ->
  messages:Yojson.Safe.t list ->
  ?tools:Yojson.Safe.t list ->
  ?max_tokens:int ->
  reasoning:reasoning ->
  supports_reasoning:bool ->
  session_id:string option ->
  provider_preferences:Yojson.Safe.t option ->
  pareto_min_coding_score:float option ->
  unit ->
  request
(*@ shaped = build ~credentials ~model_id ~messages ?tools ?max_tokens ~reasoning ~supports_reasoning
                   ~session_id ~provider_preferences ~pareto_min_coding_score ()
    pure
    ensures shaped.endpoint <> "" *)
