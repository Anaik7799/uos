open! Core

(** Bounded native SA-plan bridge protocol over [Sa_plan_store].

    Trusted Gleam IPC prerequisite only; this module does NOT perform runtime
    or cryptographic signature admission.

    Protocol laws:
    - [decode] is pure (no I/O, clock, or store access) and accepts at most
      4096 UTF-8 bytes encoding a JSON object with the exact 8 unique keys:
      [schema = "uos.sa-plan.bridge-bind-request.v1"], [mapping_id], [plan_id],
      [task_id], [owner], [task_attempt], [lease_id], and [expires_at_ns].
    - Token fields ([mapping_id], [plan_id], [task_id], [owner], [lease_id])
      must be 1..240 ASCII characters in [A-Za-z0-9_./:-] and must not contain
      "..".
    - [task_attempt] must be a canonical base-10 integer in [1..2147483647];
      [expires_at_ns] must be a canonical base-10 positive [int64] deadline.
      Duplicate, unknown, or missing keys and non-canonical numbers are
      rejected with static redacted error ["bridge_request_rejected"].
    - [execute] and [execute_observed] enter [Sa_plan_store.with_transaction]
      before inspecting mappings or time; [execute_observed] invokes
      [observe_now] only inside the transaction. Both require [now_ns >= 0L],
      require an existing [Sa_plan] domain bridge mapping matching [plan_id]
      and [task_id] without creating mappings or tasks, and fail closed to
      [Error "bridge_request_rejected"] on any store error, mismatch, or
      exception.
    - [Bind] requires [expires_at_ns > now_ns] and
      [expires_at_ns - now_ns <= 300_000_000_000L], atomically binds the lease
      to the currently claimed task attempt, verifies the returned lease
      matches request fields with [fencing_token > 0L], and returns schema
      ["uos.sa-plan.bridge-bind-response.v1"] with [found = true],
      [historical = false], [observed_at_ns = now_ns], and the 8-field [lease].
    - [Lookup] performs read-only reconciliation via
      [Sa_plan_store.find_bridge_lease] without mutating task or lease state or
      granting live authority ([expires_at_ns] may be in the past): [None]
      yields [found = false], [historical = true], [lease = null]; [Some]
      requires exact match on [mapping_id], [owner], [lease_id],
      [task_attempt], [expires_at_ns], and [fencing_token > 0L] (mismatch
      rejects), yielding [found = true], [historical = true], and the 8-field
      [lease]. *)

type operation =
  | Bind
  | Lookup

type t

val decode : operation -> string -> (t, string) result

val execute
  :  Sa_plan_store.t
  -> t
  -> now_ns:int64
  -> (Yojson.Safe.t, string) result

val execute_observed
  :  Sa_plan_store.t
  -> t
  -> observe_now:(unit -> int64)
  -> (Yojson.Safe.t, string) result
