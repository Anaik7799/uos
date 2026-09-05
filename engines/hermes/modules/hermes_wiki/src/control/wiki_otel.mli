(* OTel-shaped structured logging for the wiki/ZK control plane.

   R4 BY TYPE: the arrow points OUTWARD only. This module consumes states
   and verdicts and produces log records; it exports NO parser and no
   reader, so nothing can flow from telemetry back into a verdict — the
   S38 absent arrow, held structurally. In the actor model this is the
   Special Telemetry_p port every component already carries.

   R16: timestamps are supplied by the caller from the environment; this
   module never reads a clock. Rendering is deterministic: one record,
   one JSON line, byte-stable. *)

type severity = Trace | Debug | Info | Warn | Error_

(* OTel SeverityNumber anchors: 1, 5, 9, 13, 17 — strictly monotone. *)
val severity_number : severity -> int
val severity_text : severity -> string

type record = {
  ts : string;                       (* ISO-8601, caller-supplied *)
  severity : severity;
  body : string;
  attrs : (string * string) list;    (* rendered in the given order *)
}

val record :
  ts:string -> severity:severity -> body:string -> attrs:(string * string) list -> record

val render : record -> string        (* one JSON line, deterministic *)

val of_verdict : ts:string -> Ratchet.verdict -> record
val state_transition : ts:string -> actor:string -> from_:string -> to_:string -> record
