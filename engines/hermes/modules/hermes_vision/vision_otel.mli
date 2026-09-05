(* OpenTelemetry emission for the vision pipeline.

   Two rules from the governance checklist shape this: every reported
   metric needs a run-scoped OTLP attribute set AND an FPP channel. The
   second is the one that is easy to skip — a span with no channel is a
   metric nothing can receive, and a channel with no span is a metric
   nothing records. So [span_of] carries the FPP channel name as an
   attribute and [undeclared_channels] fails when a span names one the
   model does not declare.

   -------------------------------------------------------------------
   IDS ARE DERIVED, NOT RANDOM

   A trace id from a random source would make every run's output differ,
   which defeats the expect test that guards this format and makes a
   diff impossible to read. They are derived from the run id and the
   stage, so the same run of the same pipeline emits the same ids, and a
   CHANGE in them means the structure changed. *)

type span = {
  trace_id : string;   (* 32 hex *)
  span_id : string;    (* 16 hex *)
  name : string;
  status : string;     (* OK | ERROR | UNSET — Unknown maps to UNSET, never OK *)
  attributes : (string * string) list;
  duration_ms : float;
}

(* One span per observation. The three verdicts map to OTel status
   exactly: Live -> OK, Absent -> ERROR, Unknown -> UNSET. Folding
   Unknown into OK is the same lie the third verdict exists to prevent,
   just expressed in someone else's vocabulary. *)
val span_of : run_id:string -> Vision_controller.observation -> span

(* OTLP-shaped JSON for a whole run, with resource attributes. *)
val to_otlp : run_id:string -> Vision_controller.observation list -> string

(* Spans naming a channel the FPP model does not declare. Empty is the
   law: a metric nothing can receive is not observability. *)
val undeclared_channels : span list -> string list

(* Append the run to an OTLP JSONL stream, as the wiki audit does.
   Returns the number of spans written, or a named error — a telemetry
   sink that silently drops is worse than none. *)
val append_jsonl : path:string -> run_id:string ->
  Vision_controller.observation list -> (int, string) result
