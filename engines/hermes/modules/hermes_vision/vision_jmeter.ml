(* Fractal ontology of Apache JMeter. See the .mli: the question is not
   whether the pipeline produced the right bytes, but whether the number
   JMeter reported is about the server at all. *)

type contaminant =
  | No_assertion
  | Client_saturated
  | Coordinated_omission
  | Gui_mode
  | Jvm_pause

let contaminants =
  [ No_assertion; Client_saturated; Coordinated_omission; Gui_mode; Jvm_pause ]

let contaminant_name = function
  | No_assertion -> "no_assertion"
  | Client_saturated -> "client_saturated"
  | Coordinated_omission -> "coordinated_omission"
  | Gui_mode -> "gui_mode"
  | Jvm_pause -> "jvm_pause"

let why_it_invalidates = function
  | No_assertion ->
      "a sampler passes on any HTTP 200, including a 200 carrying an error page, so '100% \
       success' means only that the socket worked"
  | Client_saturated ->
      "the generator's own CPU or connection pool was the limit, so the latency reported is the \
       client queueing rather than the server responding"
  | Coordinated_omission ->
      "an unpaced client sends FEWER requests when the server slows, so the slow responses are \
       never issued and never measured — latency improves on paper as the server gets worse"
  | Gui_mode ->
      "the GUI consumes the CPU it is measuring with, so the generator competes with its own \
       measurement"
  | Jvm_pause ->
      "a garbage-collection pause inside the generator is charged to the server, appearing as a \
       response-time spike the server never caused"

let trustworthy = function [] -> true | _ -> false

type element =
  | Thread_group
  | Http_sampler
  | Assertion
  | Constant_throughput_timer
  | Summary_report
  | Distributed_mode

let elements =
  [ Thread_group; Http_sampler; Assertion; Constant_throughput_timer; Summary_report;
    Distributed_mode ]

let name = function
  | Thread_group -> "thread_group"
  | Http_sampler -> "http_sampler"
  | Assertion -> "assertion"
  | Constant_throughput_timer -> "constant_throughput_timer"
  | Summary_report -> "summary_report"
  | Distributed_mode -> "distributed_mode"

let level = function
  | Thread_group -> Fractal_diagnostic.L2_capability
  | Http_sampler -> Fractal_diagnostic.L4_fixture
  | Assertion -> Fractal_diagnostic.L3_contract
  | Constant_throughput_timer -> Fractal_diagnostic.L2_capability
  | Summary_report -> Fractal_diagnostic.L6_receipt
  | Distributed_mode -> Fractal_diagnostic.LX_control

(* The ASSERTION is the only element whose contract this repository
   defines — it says what a correct response is, and getting that wrong
   is our error. Everything else is the generator or its environment,
   and under R5 may block credit but never deny it. *)
let origin = function
  | Assertion -> Fractal_diagnostic.Implementation
  | Summary_report -> Fractal_diagnostic.Evidence
  | Distributed_mode -> Fractal_diagnostic.Control
  | Thread_group | Http_sampler | Constant_throughput_timer -> Fractal_diagnostic.Environment

let law = function
  | Thread_group -> "the declared concurrency is actually reached and sustained"
  | Http_sampler -> "each request is issued and its response fully read"
  | Assertion -> "the response BODY is checked, not merely its status code"
  | Constant_throughput_timer ->
      "requests are issued on a schedule independent of how fast the server replies"
  | Summary_report -> "percentiles are reported alongside the mean"
  | Distributed_mode -> "every worker's clock and results are reconciled into one series"

let hazard = function
  | Thread_group ->
      "the ramp-up is longer than the test, so the declared concurrency is never reached and the \
       result describes a smaller load than the one reported"
  | Http_sampler ->
      "the response is counted before the body is read, so a server that stalls mid-body is \
       recorded as fast"
  | Assertion ->
      "no assertion is attached, so every 200 passes — including an error page served with 200"
  | Constant_throughput_timer ->
      "without pacing the client slows when the server does, hiding exactly the latency the test \
       exists to find"
  | Summary_report ->
      "only the mean is read, so a server stalling one request in a hundred passes cleanly"
  | Distributed_mode ->
      "one worker fails to start and the aggregate silently describes less load than intended"

(* JMeter's whole purpose here is the Serve stage — concurrent load on
   the media server, which nothing else in this repository tests. *)
let serves = function
  | Assertion -> Vision_ontology.Package
  | Summary_report -> Vision_ontology.Observe
  | Thread_group | Http_sampler | Constant_throughput_timer | Distributed_mode ->
      Vision_ontology.Serve

type result = {
  samples : int;
  errors : int;
  mean_ms : float;
  p95_ms : float;
  p99_ms : float;
  max_ms : float;
  throughput_per_s : float;
}

(* A stream stalls on the tail, not on the mean. Reporting the mean is
   how a server that stalls one request in a hundred passes a load
   test. *)
let governing_latency r = r.p99_ms

let verdict r cs =
  if not (trustworthy cs) then
    Stdlib.Error
      ("the report measures the generator, not the server: "
      ^ String.concat "; " (List.map why_it_invalidates cs))
  else if r.samples <= 0 then Stdlib.Error "no samples were taken, so nothing was measured"
  else if r.errors > 0 then
    Stdlib.Error (Printf.sprintf "%d of %d samples failed" r.errors r.samples)
  else Stdlib.Ok (governing_latency r)

(* Heuristics only. These cannot prove a run was clean — only a person
   knows whether the generator was saturated — but they catch the two
   cases the numbers themselves betray. *)
let suspected r ~previous =
  let pause =
    (* a maximum far beyond the 99th percentile is a stall inside the
       generator far more often than a server that served 99 requests
       well and one catastrophically *)
    r.p99_ms > 0.0 && r.max_ms > r.p99_ms *. 10.0
  in
  let omission =
    match previous with
    (* throughput fell while latency improved: the client stopped
       issuing the requests that would have been slow *)
    | Some p ->
        r.throughput_per_s < p.throughput_per_s *. 0.9
        && r.p99_ms < p.p99_ms
    | None -> false
  in
  List.concat [ (if pause then [ Jvm_pause ] else []);
                (if omission then [ Coordinated_omission ] else []) ]

let render () =
  let b = Buffer.create 1536 in
  Buffer.add_string b "jmeter ontology (the measurement is about the generator until proven otherwise)\n";
  List.iter
    (fun e ->
      Buffer.add_string b
        (Printf.sprintf "  %-28s %-14s %-14s serves=%s\n    law:    %s\n    hazard: %s\n"
           (name e)
           (Fractal_diagnostic.level_name (level e))
           (Fractal_diagnostic.origin_name (origin e))
           (Vision_ontology.stage_name (serves e))
           (law e) (hazard e)))
    elements;
  Buffer.add_string b "  contaminants (each makes a green report meaningless):\n";
  List.iter
    (fun c ->
      Buffer.add_string b
        (Printf.sprintf "    %-22s %s\n" (contaminant_name c) (why_it_invalidates c)))
    contaminants;
  Buffer.contents b
