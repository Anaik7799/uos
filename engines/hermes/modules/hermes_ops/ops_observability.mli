type source_context = {
  source_revision : string;
  source_clean : bool;
  configuration_digest : string;
  authority_digest : string;
}

type event = {
  run_id : string;
  request_id : string;
  recorded_at_ns : int64;
  source : source_context;
  plane : string;
  surface : string;
  fractal_coordinate : string;
  ooda_phase : string;
  rca_origin : Ops_capability.rca_origin option;
  mediation : string;
  resource : string;
  duration_ns : int64;
  verdict : string;
  receipt_digest : string;
}

val configuration_digest : unit -> string
val authority_digest : unit -> string
val source_context : root:string -> source_context
val event :
  ?rca_origin:Ops_capability.rca_origin ->
  run_id:string ->
  started_ns:int64 ->
  finished_ns:int64 ->
  source:source_context ->
  Ops_command.observation ->
  event
val validate : event -> string list
val to_json : event -> Yojson.Safe.t
val to_otel_json : event -> Yojson.Safe.t
