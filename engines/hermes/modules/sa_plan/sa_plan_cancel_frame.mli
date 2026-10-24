(** One-shot framing for the existing Telegram store guardian, not an authority
    grant. The protected caller chooses pinned worker and database.
    Exactly one 1..16384-byte frame and EOF are required before DB access.
    Malformed framing never runs an effect. Blocking reads/writes must stay
    inside the existing finite guardian/service supervision. *)
val read_frame : in_channel -> (string, string) result
(** Closed envelope with unique schema/operation/request keys. The nested
    request is decoded by Cancel_protocol without changing its strict schema.
    No clock, path, approval flag or executor policy is accepted in payload. *)
val decode : string -> (Sa_plan_cancel_protocol.t, string) result
(** Domain rejection is represented inside a successful transport response;
    error text never echoes caller data. This does not imply success of effect. *)
val response : (Yojson.Safe.t, string) result -> Yojson.Safe.t
(** Emits one bounded UTF-8 length-prefixed response and flushes.
    IO failure is transport uncertainty, never permission to repeat an effect. *)
val write_frame : out_channel -> Yojson.Safe.t -> (unit, string) result
