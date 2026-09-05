(** Sole production owner for bounded paired POSIX-wall and monotonic time. *)

type receipt

type error =
  | Invalid_pair_bound
  | Invalid_lifetime_bound
  | Wall_clock_unavailable
  | Monotonic_clock_unavailable
  | Timezone_unavailable
  | Wall_time_out_of_range
  | Pair_window_exceeded
  | Arithmetic_overflow
  | Invalid_receipt
  | Wall_clock_rollback
  | Monotonic_clock_rollback
  | Expired

val maximum_pair_span_ns : int64
val maximum_lifetime_ns : int64

val observe :
  max_pair_span_ns:int64 -> lifetime_ns:int64 -> (receipt, error) result
(** Acquires monotonic-before, POSIX wall time and monotonic-after exactly once.
    The receipt is refused if acquisition exceeds [max_pair_span_ns], its
    lifetime is outside the closed bound, any clock is unavailable, or expiry
    arithmetic would overflow. *)

val validate : receipt -> (unit, error) result
(** Recomputes the private receipt digest and all structural bounds. *)

val validate_order :
  previous:receipt -> next:receipt -> (unit, error) result
(** Refuses wall or monotonic rollback between two authentic receipts. *)

val validate_current : now:receipt -> receipt -> (unit, error) result
(** Refuses rollback and monotonic expiry relative to a fresh authentic
    [now] receipt. Expiry is absorbing. *)

val wall_ns : receipt -> int64
val monotonic_started_ns : receipt -> int64
val monotonic_finished_ns : receipt -> int64
val expires_monotonic_ns : receipt -> int64
(* The local calendar projection uses mandatory [YYYYMMDD-HHSS] form. *)
val journal_timestamp : receipt -> string
val digest : receipt -> string

val source_digest : string

module For_test : sig
  type mutation =
    | Drop_wall
    | Drop_monotonic
    | Widen_pair_bound
    | Widen_lifetime_bound
    | Remove_wall_rollback
    | Remove_monotonic_rollback
    | Remove_expiry

  val source_digest_with_mutation : mutation -> string
end
