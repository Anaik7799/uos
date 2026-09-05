(* Pure preparation for a Datarhei vision request.

   This module owns no scheduler, process, effect, telemetry transport, or
   execution verdict.  It validates the declarative envelope and derives the
   typed FFmpeg intent that a future admitted operations bridge may wrap. *)

type error =
  | Empty_request_id
  | Empty_source_endpoint
  | Empty_host
  | Invalid_retry_budget of int
  | Invalid_connection_timeout of int

type request = private {
  request_id : string;
  envelope : Datarhei_intent.pipeline_envelope;
  intent : Ffmpeg_intent.ffmpeg_intent;
}

val string_of_error : error -> string

(* Deterministic projection only.  This function performs no validation and
   no effect; [prepare] is the admitted constructor for a request. *)
val intent_of_envelope :
  Datarhei_intent.pipeline_envelope -> Ffmpeg_intent.ffmpeg_intent

(* Validate all request/envelope fields used by the projection and return all
   findings in stable field order.  No command line is compiled or executed. *)
val prepare :
  request_id:string ->
  Datarhei_intent.pipeline_envelope ->
  (request, error list) result
