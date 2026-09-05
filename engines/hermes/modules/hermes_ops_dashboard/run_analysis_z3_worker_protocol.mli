(** Closed data protocol for one hard-isolated linked Smtml/Z3 query.

    This leaf contains no solver, process, limit-setting, descriptor, channel or
    higher-order IO API. A parent prepares one immutable declaration and writes the
    exact query bytes to worker stdin.  The executable emits a bounded typed
    transcript.  Resource preflight remains advisory; only an applied-limit,
    owned-group handshake plus the supervising parent receipt can establish the
    later isolation claim. *)

type sha256 = private string

val digest_bytes : string -> sha256
val sha256_to_hex : sha256 -> string

type limits = private {
  virtual_memory_bytes : int64;
  cpu_seconds : int;
  maximum_query_bytes : int;
  maximum_output_bytes : int;
  limits_digest : sha256;
}

val make_limits :
  virtual_memory_bytes:int64 -> cpu_seconds:int -> maximum_query_bytes:int ->
  maximum_output_bytes:int -> (limits, string list) result
(** @ensures result is [Error _] or every returned bound is positive. *)

type group_policy = Own_process_group

type request = private {
  protocol_version : string;
  obligation_id : string;
  worker_executable_digest : sha256;
  query_digest : sha256;
  query_bytes : int;
  limits : limits;
  group_policy : group_policy;
  request_digest : sha256;
}

type prepared_request = private { request : request; query : string }

val prepare :
  obligation_id:string -> worker_executable_digest:sha256 -> query:string ->
  limits:limits ->
  (prepared_request, string list) result

val argv : prepared_request -> string array
(** Fixed worker arguments excluding argv[0]. No caller-defined option or
    command is accepted. *)

val stdin_bytes : prepared_request -> string

type error =
  | Invalid_argv of string
  | Invalid_field of string
  | Invalid_digest of string
  | Query_too_large
  | Query_length_mismatch
  | Query_digest_mismatch
  | Frame_malformed of string
  | Frame_too_large
  | Protocol_unavailable

val render_error : error -> string
val sha256_of_hex : string -> (sha256, error) result
val decode_argv : string array -> (request, error) result

type admitted_query = private { bytes : string; digest : sha256; length : int }

val admit_stdin : request -> string -> (admitted_query, error) result
(** @ensures result is [Error _] or the admitted bytes have exactly the
    declaration's length and digest. *)

val resource_requirements :
  worker_path:string -> expected:Resource_envelope.executable_identity ->
  Resource_envelope.resource list

type limit_value = Finite of int64 | Infinite
type limit_observation = private { current : limit_value; maximum : limit_value }

type applied_limit = private {
  requested : int64;
  before : limit_observation;
  after : limit_observation;
  applied : bool;
}

type worker_object = private {
  identity : Resource_envelope.executable_identity;
  bytes : int;
  digest : sha256;
}

type handshake = private {
  protocol_version : string;
  request_digest : sha256;
  declared_query_digest : sha256;
  declared_query_bytes : int;
  object_before : worker_object;
  object_after : worker_object;
  virtual_memory : applied_limit;
  cpu : applied_limit;
  process_id : int;
  process_group_id : int;
  group_policy : group_policy;
  handshake_digest : sha256;
}

val validate_handshake : request:request -> handshake -> string list

type capture_receipt = private {
  directory_object_before : Resource_envelope.executable_identity;
  directory_mode_before : int;
  file_object_before : Resource_envelope.executable_identity;
  file_object_after : Resource_envelope.executable_identity;
  file_mode_before : int;
  readback_digest : sha256;
  readback_bytes : int;
  file_removed : bool;
  directory_removed : bool;
}

type answer = Sat | Unsat | Unknown

type result = private {
  request_digest : sha256;
  executed_query_digest : sha256;
  executed_query_bytes : int;
  handshake_digest : sha256;
  capture : capture_receipt;
  answer : answer;
  solver_id : string;
  solver_version : string;
  solver_call_delta : int;
  assertion_count : int;
  peak_rss_bytes : int64;
  result_digest : sha256;
}

(** Validating constructors reserved to the worker boundary.  The underlying
    evidence carriers remain private: callers can only obtain them after all
    local consistency laws and canonical digests have been checked. *)
module Worker_evidence : sig
  val worker_object :
    identity:Resource_envelope.executable_identity -> bytes:int ->
    digest:sha256 -> (worker_object, string list) Stdlib.result

  val limit_observation :
    current:limit_value -> maximum:limit_value -> limit_observation

  val applied_limit :
    requested:int64 -> before:limit_observation -> after:limit_observation ->
    applied:bool -> applied_limit

  val handshake :
    request -> object_before:worker_object -> object_after:worker_object ->
    virtual_memory:applied_limit -> cpu:applied_limit -> process_id:int ->
    process_group_id:int -> (handshake, string list) Stdlib.result

  val capture :
    directory_object_before:Resource_envelope.executable_identity ->
    directory_mode_before:int ->
    file_object_before:Resource_envelope.executable_identity ->
    file_object_after:Resource_envelope.executable_identity ->
    file_mode_before:int -> readback_digest:sha256 -> readback_bytes:int ->
    file_removed:bool -> directory_removed:bool ->
    (capture_receipt, string list) Stdlib.result

  val result :
    request:request -> query:admitted_query -> handshake:handshake ->
    capture:capture_receipt -> answer:answer -> solver_id:string ->
    solver_version:string -> solver_call_delta:int -> assertion_count:int ->
    peak_rss_bytes:int64 -> (result, string list) Stdlib.result
end

val validate_result :
  request:request -> query:admitted_query -> handshake:handshake -> result ->
  string list

type refusal_reason =
  | Unsupported_capability of Resource_envelope.kernel_capability
  | Invalid_request
  | Query_rejected
  | Limit_application_failed
  | Group_setup_failed
  | Worker_identity_failed
  | Capture_failed
  | Solver_unavailable
  | Solver_failed
  | Output_limit_exceeded

type refusal = private {
  request_digest : sha256 option;
  reason : refusal_reason;
  detail : string;
  refusal_digest : sha256;
}

val make_refusal :
  request_digest:sha256 option -> refusal_reason -> detail:string -> refusal

type frame = private Handshake of handshake | Result of result | Refusal of refusal

val encode_refusal : refusal -> string
val encode_handshake : handshake -> string
val encode_result : result -> string
val decode_frame : maximum_bytes:int -> string -> (frame, error) Stdlib.result

type transcript = private
  | Completed of { handshake : handshake; result : result }
  | Refused of refusal

val decode_transcript :
  maximum_bytes:int -> string -> (transcript, error) Stdlib.result

type worker_exit =
  | Completed_exit
  | Unsupported_exit
  | Rejected_exit
  | Failed_exit

val exit_code : worker_exit -> int
