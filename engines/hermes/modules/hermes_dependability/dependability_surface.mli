(** Pure four-surface projection of the closed dependability intent.

    The module owns codecs and a recording dispatcher only. It performs no
    process, filesystem, SQLite, network, MCP-server, Zenoh-session, scheduler,
    Domain, or SOP operation. *)

type transport = Ocaml_api | Cli | Mcp | Zenoh

type action = Verify_reliability | Verify_full

type verdict = Passed | Failed | Unavailable_observed | Skipped

type diagnostic_code =
  | Malformed_request
  | Unknown_field
  | Unknown_action
  | Unknown_target
  | Plane_mismatch
  | Generic_invoke_forbidden
  | Invalid_intent
  | Invalid_receipt
  | Dispatch_unavailable

type diagnostic = private {
  code : diagnostic_code;
  detail_digest : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type success = private {
  intent_digest : string;
  action : action;
  verdict : verdict;
  receipt_digest : string;
  effect_digest : string;
  readback_digest : string;
  result_digest : string;
}

type failure = private {
  intent_digest : string option;
  action : action option;
  verdict : verdict;
  diagnostic : diagnostic;
  receipt_digest : string;
  effect_digest : string;
  readback_digest : string;
  result_digest : string;
}

type normalized_result = Success of success | Error of failure

type request = private {
  action : action;
  intent : Dependability_intent.t;
}

type observation = {
  transport : transport;
  result : normalized_result;
}

type status_query = private {
  status_request_id : string;
  status_intent_digest : string;
}

type status_observation = private {
  status_query : status_query;
  current_result : normalized_result option;
  status_digest : string;
}

type executor = Dependability_intent.t -> normalized_result

val operation_of_action : action -> Dependability_intent.operation
val action_name : action -> string
val transport_name : transport -> string
val diagnostic_code_name : diagnostic_code -> string

val make_request :
  action:action ->
  intent:Dependability_intent.t ->
  (request, diagnostic) result

val action : request -> action
val intent_of_request : request -> Dependability_intent.t

val semantic_digest : request -> string
(** The semantic digest is exactly [Dependability_intent.digest intent] and
    deliberately excludes transport and envelope representation. *)

val canonical_request_json : request -> string
val decode_request_json : string -> (request, diagnostic) result

val canonical_envelope_json : transport:transport -> request -> string
val decode_envelope_json :
  expected_transport:transport -> string -> (request, diagnostic) result

val cli_argv : request -> string list
val decode_cli : string list -> (request, diagnostic) result

val mcp_method_name : string
val mcp_schema : Yojson.Safe.t
val decode_mcp :
  method_name:string -> payload:string -> (request, diagnostic) result

val make_status_query :
  request_id:string ->
  intent_digest:string ->
  (status_query, diagnostic) result

val canonical_status_query_json : status_query -> string
val mcp_status_method_name : string
val mcp_status_schema : Yojson.Safe.t
val decode_mcp_status :
  method_name:string -> payload:string -> (status_query, diagnostic) result

val dispatch_mcp_status :
  method_name:string ->
  payload:string ->
  current:normalized_result option ->
  (status_observation, diagnostic) result
(** Pure projection of a caller-supplied immutable snapshot. It accepts no
    verification executor or effect callback. *)

val zenoh_key : request -> string
val decode_zenoh :
  key:string -> payload:string -> (request, diagnostic) result

val make_success :
  intent:Dependability_intent.t ->
  receipt_digest:string ->
  effect_digest:string ->
  readback_digest:string ->
  (normalized_result, diagnostic) result

val make_failure :
  intent:Dependability_intent.t option ->
  verdict:verdict ->
  code:diagnostic_code ->
  detail:string ->
  coordinate:Ops_capability.coordinate ->
  rca_origin:Ops_capability.rca_origin ->
  hazard_id:string ->
  receipt_digest:string ->
  effect_digest:string ->
  readback_digest:string ->
  (normalized_result, diagnostic) result

val normalized_result_json : normalized_result -> string

val dispatch_api : execute:executor -> request -> observation
val dispatch_cli : execute:executor -> string list -> observation
val dispatch_mcp :
  execute:executor -> method_name:string -> payload:string -> observation
val dispatch_zenoh :
  execute:executor -> key:string -> payload:string -> unit -> observation
