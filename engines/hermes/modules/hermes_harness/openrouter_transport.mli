(** L3 contract: injectable OpenRouter chat-completions transport.

    Reference capability: [model_routing.provider_transports]
    Frozen anchors: [agent/transports/base.py],
    [agent/transports/chat_completions.py]

    The executor is supplied by a higher layer. That keeps the protocol decoder
    deterministic and stops bootstrap and tests from creating network traffic,
    which is what makes the decoding half specifiable at all: [decode] is a
    pure function from JSON to an optional response, and every failure mode of
    [submit] is a value in [error] rather than an exception.

    [submit] takes an effectful executor, so it is not [pure] and carries no
    algebraic obligation here. Its contract is the totality of [error]: it
    never raises, and a malformed payload is [Malformed_response] rather than a
    Yojson exception escaping. Proving that is an L4 obligation, since Gospel
    cannot state it over a functional argument. *)

type tool_call = { id : string; name : string; arguments : string }
type usage = { prompt_tokens : int option; completion_tokens : int option; total_tokens : int option }

type response = {
  id : string option;
  content : string option;
  finish_reason : string;
  tool_calls : tool_call list;
  usage : usage option;
}

type error =
  | Missing_credentials
  | Transport_error of string
  | Http_error of int
  | Malformed_response

type executor =
  endpoint:string -> api_key:string -> body:string -> (int * string, string) result

val member : string -> Yojson.Safe.t -> Yojson.Safe.t option
(*@ found = member name value
    pure *)

val string : Yojson.Safe.t option -> string option
(*@ text = string value
    pure *)

val integer : Yojson.Safe.t option -> int option
(*@ number = integer value
    pure *)

val decode_tool_call : Yojson.Safe.t -> tool_call option
(*@ call = decode_tool_call value
    pure *)

val decode_usage : Yojson.Safe.t option -> usage option
(*@ used = decode_usage value
    pure *)

val decode : Yojson.Safe.t -> response option
(*@ decoded = decode json
    pure *)

(*@ axiom decode_is_total:
      forall json: Yojson.Safe.t. decode json = None \/ decode json <> None *)

val submit : execute:executor -> Openrouter_contract.request -> (response, error) result
