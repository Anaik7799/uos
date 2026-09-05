(** Zenoh publisher for the harness's system-to-system telemetry — the c3i
    `scripts/common/zenoh` discipline (R14): all INTER-SYSTEM messaging goes
    through this module; INTRA-process composition stays pure function calls
    (the algebra IS the proof — messaging never replaces the evidence fold).

    Everything published is observation or advice — sweeps, alerts, runbook
    items. Nothing published is authority: the evidence store remains the only
    source of parity truth, and subscribers get copies, never the record
    (the two-lattice law). Telemetry is FAIL-OPEN at call sites: a missing
    router degrades to a printed note, never a failed run ("Zenoh failure must
    not fail the aggregator"). *)

val default_endpoint : string
(** [tcp/127.0.0.1:7447] — the local mesh router. *)

val endpoint : unit -> string
(** [HERMES_ZENOH_ENDPOINT] when set and non-empty, else {!default_endpoint}. *)

val enabled : unit -> bool
(** False when [HERMES_ZENOH=0] — an explicit opt-out, reported by {!publish}
    as an [Error] so call sites print why telemetry stayed local. *)

val valid_key : string -> bool
(** A publishable key expression: non-empty, no leading/trailing ['/'], no
    whitespace, and CONCRETE — no [*], [$], [?] or [#] (wildcards belong to
    subscribers, never to a publisher). *)

val publish : key:string -> payload:string -> (unit, string) result
(** Open a client session to {!endpoint}, put [payload] at [key], close.
    [Error detail] on: disabled, invalid key, unreachable router, or any
    zenoh-side failure — the caller prints the detail and continues (fail-open
    telemetry). Never raises. *)

val serve_queryable :
  keyexpr:string -> callback:(string -> string -> string) -> (unit, string) result
(** Serve a fail-closed Zenoh queryable until the process is stopped. Each query
    calls [callback key payload] and replies with its returned JSON. Setup
    errors are returned; a missing/disabled router never becomes success. *)

val query : key:string -> payload:string -> (string, string) result
(** Send one command query to a live queryable and return its reply. Router,
    timeout, protocol, and remote-error failures remain explicit [Error]. *)
