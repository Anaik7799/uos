(** Bounded local IPC for the existing Sa-plan cancellation store mechanics.
    This protocol authenticates neither reviewers nor Telegram principals.
    Only the trusted Gleam adapter may choose the protected database/artifact.
    [Cancel] rechecks canonical store fences at the supplied host observation.
    [Lookup] performs no job mutation and returns historical receipt evidence;
    it deliberately permits an expired original request, never an effect grant.
    Both modes require the complete exact original request. *)
type operation = Cancel | Lookup
type t

(** Decode at most 8192 UTF-8 bytes, one closed object with unique keys and
    exact integer/string fields. No caller-supplied clock or database path.
    Malformed input returns a static error without echoing request contents. *)
val decode : operation -> string -> (t, string) result

(** Current time comes from the supervised native process, not stdin.
    Successful output distinguishes found=false from a recorded receipt.
    Reconciliation never claims current worker quiescence or task cancellation.
    Lookup binds the stored request hash/result to all original request fields. *)
val execute :
  Sa_plan_store.t -> t -> now_ns:int64 ->
  (Yojson.Safe.t, string) result

(** Production entry: acquire the canonical transaction BEFORE observing time,
    so SQLite lock contention cannot reuse a pre-wait expiry decision. The
    observer is trusted native code; it is never decoded from request data.
    Exceptions and clock failures fail closed. Current host/boot admission and
    authenticated ingress remain the supervising Gleam adapter responsibility. *)
val execute_observed :
  Sa_plan_store.t -> t -> observe_now:(unit -> int64) ->
  (Yojson.Safe.t, string) result
