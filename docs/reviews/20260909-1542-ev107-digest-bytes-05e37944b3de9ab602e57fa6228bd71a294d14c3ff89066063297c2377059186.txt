(** Extended Gospel Contracts and Bounded Differential Oracles for Tool Dispatches (EV-107).
    Contract specifications define preconditions, postconditions, and fail-closed
    validation semantics across all cross-domain MCP tool invocations. *)

type verdict =
  | Pass of { digest : string; timestamp : string }
  | FailClosed of { reason : string; error_code : int }

val contains_nul_byte : string -> bool
(** [contains_nul_byte s] checks if [s] has an embedded NUL byte.
    [s] is searched byte-by-byte.
    @ensures [contains_nul_byte s = true] <-> (\exists i. 0 <= i < String.length s /\ s.[i] = '\x00') *)

val contains_sql_injection : string -> bool
(** [contains_sql_injection s] verifies absence of unparameterized SQL syntax.
    @ensures returns true if any barred SQL injection signature is present. *)

val sha256_digest : string -> string
(** [sha256_digest s] computes 64-character lowercase hexadecimal SHA-256 digest.
    @ensures String.length (sha256_digest s) = 64 *)

val validate_dispatch_contract : string -> verdict
(** [validate_dispatch_contract payload] evaluates Gospel contract invariants on incoming payload.
    @ensures match result with
             | Pass { digest; _ } -> String.length digest = 64 /\ not (contains_nul_byte payload) /\ not (contains_sql_injection payload)
             | FailClosed { error_code; _ } -> error_code = -2 \/ error_code = -3 \/ error_code = -1 *)

val bounded_differential_oracle : string -> string -> (bool, string) result
(** [bounded_differential_oracle payload baseline_output] executes differential comparison
    between primary dispatch validation and independent formal reference oracle.
    @ensures returns Ok true iff primary and reference oracle produce identical verdicts. *)
