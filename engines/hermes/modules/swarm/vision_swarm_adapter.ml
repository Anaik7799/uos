type error =
  | Empty_request_id
  | Empty_source_endpoint
  | Empty_host
  | Invalid_retry_budget of int
  | Invalid_connection_timeout of int

type request = {
  request_id : string;
  envelope : Datarhei_intent.pipeline_envelope;
  intent : Ffmpeg_intent.ffmpeg_intent;
}

let string_of_error = function
  | Empty_request_id -> "request id is empty"
  | Empty_source_endpoint -> "source endpoint is empty"
  | Empty_host -> "target host is empty"
  | Invalid_retry_budget value ->
      Printf.sprintf "retry budget must be nonnegative (got %d)" value
  | Invalid_connection_timeout value ->
      Printf.sprintf "connection timeout must be positive (got %d)" value

let intent_of_envelope (envelope : Datarhei_intent.pipeline_envelope) =
  Ffmpeg_intent.Transmux_Stream
    { source = envelope.source.endpoint;
      sink = Printf.sprintf "webrtc://%s" envelope.host }

let prepare ~request_id (envelope : Datarhei_intent.pipeline_envelope) =
  let errors = ref [] in
  let reject condition error = if condition then errors := error :: !errors in
  reject (String.trim request_id = "") Empty_request_id;
  reject (String.trim envelope.source.endpoint = "") Empty_source_endpoint;
  reject (String.trim envelope.host = "") Empty_host;
  reject
    (envelope.max_retry < 0)
    (Invalid_retry_budget envelope.max_retry);
  reject
    (envelope.connection_timeout_ms <= 0)
    (Invalid_connection_timeout envelope.connection_timeout_ms);
  match List.rev !errors with
  | [] ->
      Ok
        { request_id;
          envelope;
          intent = intent_of_envelope envelope }
  | findings -> Error findings
