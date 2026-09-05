(* Fractal ontology of Apache JMeter.

   Every other tool modelled here acts on the media. JMeter does not: it
   is a LOAD GENERATOR, and it is the only tool in the set whose output
   is a MEASUREMENT rather than a stream. That inverts where the defects
   live. For ffmpeg the question is whether the pipeline produced the
   right bytes; for JMeter the question is whether the NUMBER IT REPORTED
   IS ABOUT THE SERVER AT ALL.

   It very often is not. A load generator is a program on a machine with
   finite CPU, a JVM that pauses, and a scheduler that slips. Every one
   of those contaminates the measurement while producing a clean-looking
   report, and none of them shows up as an error.

   Its place in this repository is the Serve stage — concurrent load on
   the media server, which nothing currently tests.

   -------------------------------------------------------------------
   THE FOUR WAYS A GREEN JMETER REPORT IS MEANINGLESS

   - NO ASSERTION. A sampler passes on any HTTP 200, including a 200
     carrying an error page. Without an assertion on the body, "100%
     success" means "the socket worked".
   - CLIENT SATURATION. When the generator's own CPU or connection pool
     is the limit, the latency reported is the client queueing, not the
     server responding. The report looks identical either way.
   - COORDINATED OMISSION. When the server slows, an unpaced client
     simply sends fewer requests, so the slow responses are never issued
     and never measured. Latency improves on paper as the server gets
     worse — the most dangerous artefact in load testing.
   - THE AVERAGE. Mean response time hides the tail that actually breaks
     playback. A stream stalls on the 99th percentile, not the mean.

   Each is enumerated below as a [contaminant], and a run is usable as
   evidence only when none of them applies. *)

type contaminant =
  | No_assertion
  | Client_saturated
  | Coordinated_omission
  | Gui_mode          (* the GUI itself consumes the CPU it is measuring with *)
  | Jvm_pause         (* a GC pause inside the generator, charged to the server *)

val contaminants : contaminant list
val contaminant_name : contaminant -> string
val why_it_invalidates : contaminant -> string

(* True only for the empty list. A report carrying any contaminant
   measures the generator, not the system under test. *)
val trustworthy : contaminant list -> bool

(* ------------------------------------------------------- the elements *)

type element =
  | Thread_group      (* concurrency, ramp-up, iterations *)
  | Http_sampler      (* one request *)
  | Assertion         (* what makes a 200 mean something *)
  | Constant_throughput_timer  (* pacing — the defence against omission *)
  | Summary_report    (* aggregate output *)
  | Distributed_mode  (* master/worker, when one generator is not enough *)

val elements : element list
val name : element -> string
val level : element -> Fractal_diagnostic.fractal_level
val origin : element -> Fractal_diagnostic.origin
val law : element -> string
val hazard : element -> string
val serves : element -> Vision_ontology.stage

(* ---------------------------------------------------------- the result *)

type result = {
  samples : int;
  errors : int;
  mean_ms : float;
  p95_ms : float;
  p99_ms : float;
  max_ms : float;
  throughput_per_s : float;
}

(* Latency at the percentile that governs playback. NOT the mean: a
   stream stalls on the tail, and reporting the mean is how a server that
   stalls one request in a hundred passes a load test. *)
val governing_latency : result -> float

(* A result is only a verdict about the server when no contaminant
   applies AND the error count is zero. Returns the reason when not. *)
(* Stdlib.result is qualified: this module's own `result` record
   shadows it. *)
val verdict : result -> contaminant list -> (float, string) Stdlib.result

(* Heuristic contamination checks derived from the numbers themselves.
   These cannot prove a run was clean — only a person knows whether the
   generator was saturated — but they catch the cases the numbers betray:
   a max wildly beyond p99 (a pause), or throughput that fell while
   latency improved (omission). *)
val suspected : result -> previous:result option -> contaminant list

val render : unit -> string
