(* Metrics and profiling.

   -------------------------------------------------------------------
   THE HAZARD THIS WHOLE MODULE IS BUILT AROUND

   Every metric surface already modelled here fails the same way: a
   counter reads zero both when everything is fine and when nothing ever
   ran. OBS's loss counters do it, JMeter's error count does it, and a
   naive histogram does it worst of all — it reports a p99 of 0.0 for a
   stage that was never observed, which is indistinguishable from a
   stage that is instantaneous.

   So an empty histogram has NO percentile. [percentile] returns an
   option, and there is no default. A caller that wants a number must
   say what it means when there isn't one.

   -------------------------------------------------------------------
   EVERY METRIC NEEDS A DECLARED CHANNEL

   Same law as the OTel spans: a metric on a channel the FPP model does
   not declare is a metric nothing can receive. [undeclared] reports
   them and the exporters refuse. *)

type histogram

val empty : histogram
val observe : histogram -> float -> histogram
val count : histogram -> int

(* NONE when nothing was observed. A zero here would be a lie about a
   stage that never ran. *)
val percentile : histogram -> float -> float option
val mean : histogram -> float option

type metric = {
  name : string;
  channel : string;      (* must be declared on the FPP model *)
  value : float;
  unit_ : string;
}

(* Counters and gauges derived from a run's observations, plus the
   latency histogram per stage. *)
val of_observations : Vision_controller.observation list -> metric list
val histograms : Vision_controller.observation list -> (Vision_ontology.stage * histogram) list

val undeclared : metric list -> string list

(* ---------------------------------------------------------- profiling

   A budget per stage, and a stage that exceeds it is a FAILURE rather
   than a note. A profile nobody gates on is a profile nobody reads. *)

val budget_ms : Vision_ontology.stage -> float

(* Stages over budget, with the observed figure. Empty is the law. *)
val over_budget :
  Vision_controller.observation list -> (Vision_ontology.stage * float * float) list

(* A stage whose budget was never exercised is reported separately from
   one that met it — "not measured" and "fast" are different claims. *)
val unprofiled :
  Vision_controller.observation list -> Vision_ontology.stage list

(* Prometheus text exposition, and OTLP metrics JSON. Both REFUSE when a
   metric names an undeclared channel. *)
val to_prometheus : metric list -> (string, string) result
val to_otlp : run_id:string -> metric list -> (string, string) result

val render : Vision_controller.observation list -> string
