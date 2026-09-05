(** Pure, operation-indexed Jujutsu readback admission.  The decoder is
    injected; this module performs no filesystem or process effect. *)

type recovery_anchor =
  | Before_state of string
  | Partition_anchor of string

type child_status =
  | Exited_zero
  | Exited_nonzero of int
  | Signaled of int
  | Timed_out
  | Not_reaped

type decoded = {
  operation_key : string;
  request_id : string;
  event_id : string;
  postcondition_id : string;
  state_digest : string;
  output_bytes : int;
  recovery_anchor : recovery_anchor option;
}

type decoder =
  max_output_bytes:int -> string -> (decoded, string) result

type refusal =
  | Invalid_digest
  | Missing_recovery_anchor
  | Unexpected_recovery_anchor
  | Wrong_recovery_anchor_kind
  | Output_too_large
  | Decoder_refused
  | Nondeterministic_decoder
  | Child_not_successful
  | Identity_mismatch
  | Postcondition_mismatch
  | Output_length_mismatch
  | Recovery_anchor_mismatch

type expectation
type receipt

val postcondition_id : Jj_operation.t -> string

val expect :
  operation:Jj_operation.t ->
  request:Jj_id.Request.t ->
  event:Jj_id.Event.t ->
  expected_state_digest:string ->
  recovery_anchor:recovery_anchor option ->
  (expectation, refusal) result
(*@ ensures match result with Ok _ -> String.length expected_state_digest = 64
            | Error _ -> true *)

val verify :
  expectation ->
  child:child_status ->
  decode:decoder ->
  string ->
  (receipt, refusal) result
(*@ ensures match result with Ok _ -> child = Exited_zero | Error _ -> true *)

val receipt_digest : receipt -> string
val receipt_operation_key : receipt -> string
val source_digest : string
