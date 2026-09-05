(** L3 contract candidate: Retry-After parsing for the
    [model_routing.rate_and_retry] capability.

    Reference capability: [model_routing.rate_and_retry]
    Frozen anchor: [agent/retry_utils.py]

    [parse_retry_after_seconds] mirrors the frozen function's DETERMINISTIC
    branches: [None]/bool -> [None]; int/float -> [max 0.]; a trimmed numeric
    string -> [max 0.]; empty/whitespace -> [None]; any other non-numeric,
    non-date string -> [None]. The HTTP-date branch (which calls [datetime.now])
    is deliberately out of scope, so date-like inputs are excluded from scenarios
    and this reproduction is faithful for the deterministic surface -- proven by
    the fixtures, not assumed. Header-mapping inputs are out of scope for this
    first cut. *)

val parse_retry_after_seconds : Yojson.Safe.t -> float option
(*@ seconds = parse_retry_after_seconds value
    pure *)
