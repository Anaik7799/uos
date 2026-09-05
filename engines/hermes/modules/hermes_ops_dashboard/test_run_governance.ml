let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf "FAIL: %s\n" name
  end

let is_ok = function Ok () -> true | Error _ -> false
let is_error = function Error _ -> true | Ok _ -> false

let provenance : Run_model.provenance =
  { source_revision = "80f93278"; source_clean = true;
    configuration_digest = String.make 64 'a';
    authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let coordinate phase : Ops_capability.coordinate =
  { level = Ops_capability.LX; phase }

let metric_digest id =
  match Run_metrics.find id with
  | Some declaration -> Run_metrics.declaration_digest declaration
  | None -> String.make 64 '0'

let observation ?(metric_id = "process.cpu.user_seconds")
    ?(source = Run_metrics.Process_times) ?(sampled_at_ns = 900L)
    ?(sample = Run_metrics.Measured { value = Run_metrics.Float 1.5;
                                     sampled_at_ns = 900L })
    ?(labels = [ ("phase", "dispatch") ]) () : Run_metrics.observation =
  let sample =
    match sample with
    | Run_metrics.Measured { value; _ } -> Run_metrics.Measured { value; sampled_at_ns }
    | Unavailable_observed { reason; _ } ->
        Unavailable_observed { reason; sampled_at_ns }
  in
  { metric_id; declaration_digest = metric_digest metric_id;
    run_id = "run-1"; subject_id = "process";
    subject_digest = String.make 64 'd'; provenance;
    coordinate = coordinate Ops_capability.Observe;
    rca_origin = Ops_capability.Environment; source; labels; sample }

let contains_assoc name = function
  | `Assoc fields -> List.mem_assoc name fields
  | _ -> false

let assoc_field name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let list_field name json =
  match assoc_field name json with Some (`List values) -> values | _ -> []

let otlp_spans = function
  | `Assoc [ ("resourceSpans", `List [ resource ]) ] ->
      begin match list_field "scopeSpans" resource with
      | [ scope ] -> list_field "spans" scope
      | _ -> []
      end
  | _ -> []

let event ?(sequence = 0L) ?(event_id = "event-0")
    ?(kind = Run_model.Run_declared) ?(payload = `Assoc []) ?previous_digest () =
  match Run_model.make ~run_id:"run-1" ~sequence ~event_id
      ~kind ~subject:Run_model.Run
      ~plane:Ops_capability.Control_plane
      ~coordinate:(coordinate Ops_capability.Observe)
      ~rca_origin:Ops_capability.Control ~occurred_at_ns:100L
      ~monotonic_at_ns:50L ~provenance ~payload ~previous_digest with
  | Ok value -> value
  | Error error -> failwith error

let snapshot_and_event () =
  let first = event () in
  let initial = match Run_snapshot.empty ~run_id:"run-1" ~provenance with
    | Ok value -> value | Error error -> failwith error
  in
  let snapshot = match Run_snapshot.apply initial first with
    | Ok (Run_snapshot.Applied value) -> value
    | _ -> failwith "first snapshot event was not applied"
  in
  (snapshot, first)

let fast_path_context ?(request_id = "request-fast-path") () =
  let current_head =
    match Run_safety.For_test.current_head_receipt ~run_id:"run-1" ~provenance
            ~observed_at_ns:900L ~current_at_ns:1_000L ~expires_at_ns:2_000L with
    | Ok value -> value
    | Error _ -> failwith "fast-path current-head fixture refused"
  in
  match Run_safety.make_gate_context ~current_head ~request_id
          ~activity_id:"activity.verify-sqlite-dependability"
          ~coordinate:{ Ops_capability.level = Ops_capability.L3;
                        phase = Ops_capability.Act }
          ~plane:Ops_capability.Control_plane with
  | Ok value -> value
  | Error _ -> failwith "fast-path context fixture refused"

let trace_span ?parent ?(span_id = "1111111111111111") ?(name = "root")
    ?(attributes = []) ?(links = []) () : Run_trace.span =
  { trace_id = String.make 32 'a'; span_id; parent_span_id = parent; name;
    run_id = "run-1"; provenance; plane = Ops_capability.Control_plane;
    surface = Some Ops_capability.Ocaml_api;
    coordinate = coordinate Ops_capability.Observe;
    rca_origin = Ops_capability.Control; started_at_ns = 100L;
    ended_at_ns = 200L; attributes; links }

let () =
  Printf.printf "[unit] closed metric declarations and observations\n";
  check "metric registry is nonempty" (Run_metrics.all <> []);
  check "every metric declaration validates"
    (is_ok (Run_metrics.validate_declarations Run_metrics.all));
  let expected_metric_ids =
    [ "run.events.total"; "run.phase.duration_ns"; "run.suite.succeeded";
      "process.cpu.user_seconds"; "process.cpu.system_seconds";
      "process.cpu.child_user_seconds"; "process.cpu.child_system_seconds";
      "ocaml.gc.minor_words"; "ocaml.gc.live_words";
      "process.rss.bytes"; "system.load.1m"; "system.load.5m";
      "system.load.15m"; "sqlite.event_lag"; "zenoh.publish_lag_ns";
      "zenoh.subscriber_lag_ns"; "websocket.clients"; "websocket.drops";
      "snapshot.age_ns"; "reconcile.latency_ns"; "render.latency_ns";
      "webgl.frames"; "webgl.context_losses"; "admission.gaps";
      "rete_ul.facts"; "rete_ul.alpha_nodes"; "rete_ul.beta_nodes";
      "rete_ul.tokens"; "rete_ul.joins"; "rete_ul.agenda";
      "rete_ul.firings"; "rete_ul.budgets"; "rete_ul.links";
      "rete_ul.fixed_point"; "rete_ul.latency_ns";
      "mcda.alternatives"; "mcda.criteria"; "mcda.cells";
      "mcda.exclusions"; "mcda.constraint_failures"; "mcda.ties";
      "mcda.margin"; "mcda.sensitivity"; "mcda.selection";
      "mcda.latency_ns"; "stpa.hazards"; "stpa.unsafe_control_actions";
      "stpa.constraints"; "stpa.unmitigated"; "fmea.failure_modes";
      "fmea.severity"; "fmea.occurrence"; "fmea.detection"; "fmea.rpn";
      "fmea.accepted_residuals"; "fmea.gate_latency_ns";
      "ruliad.states"; "ruliad.edges"; "ruliad.depth";
      "ruliad.terminals"; "ruliad.path_count"; "ruliad.confluence";
      "ruliad.cap_hits"; "ruliad.nonconfluence"; "ruliad.latency_ns";
      "stan.scenarios"; "stan.effective_samples"; "stan.posterior_mean";
      "stan.moment_band"; "stan.invalid_priors";
      "stan.unmeasured_families"; "stan.latency_ns";
      "z3.obligations"; "z3.sat"; "z3.unsat"; "z3.unknown";
      "z3.timeout"; "z3.unavailable"; "z3.query_digest_mismatches";
      "z3.cross_path_agreement"; "z3.latency_ns";
      "assurance.unit.receipts"; "assurance.component.receipts";
      "assurance.system.receipts"; "assurance.tdd.receipts";
      "assurance.bdd.receipts"; "assurance.property.receipts";
      "assurance.fuzz.receipts"; "assurance.chaos.receipts";
      "assurance.stm_model.receipts"; "assurance.performance.receipts";
      "assurance.scalability.receipts"; "assurance.formal.receipts";
      "assurance.mutation.receipts"; "assurance.browser.receipts";
      "assurance.freshness_ns"; "assurance.coverage";
      "assurance.failures"; "assurance.unavailable";
      "assurance.latency_ns" ]
  in
  List.iter
    (fun id -> check ("predeclared metric " ^ id) (Option.is_some (Run_metrics.find id)))
    expected_metric_ids;
  let ids = List.map (fun declaration -> declaration.Run_metrics.id) Run_metrics.all in
  let channels = List.map (fun declaration -> declaration.Run_metrics.fpp_channel) Run_metrics.all in
  check "metric ids are unique"
    (List.length ids = List.length (List.sort_uniq String.compare ids));
  check "FPP channels are one-to-one with metrics"
    (List.length channels = List.length (List.sort_uniq String.compare channels));
  begin match Run_metrics.all with
  | first :: second :: _ ->
      check "duplicate metric ids are rejected"
        (is_error (Run_metrics.validate_declarations
           [ first; { second with id = first.id } ]));
      check "duplicate FPP channels are rejected"
        (is_error (Run_metrics.validate_declarations
           [ first; { second with fpp_channel = first.fpp_channel } ]));
      check "a declaration without a source is rejected"
        (is_error (Run_metrics.validate_declarations [ { first with sources = [] } ]))
  | _ -> check "metric mutant fixtures exist" false
  end;
  let measured_zero = observation ~sample:(Run_metrics.Measured { value = Int 0L; sampled_at_ns = 900L }) () in
  let unavailable = observation ~sample:(Run_metrics.Unavailable_observed
      { reason = "sensor absent"; sampled_at_ns = 900L }) () in
  check "measured zero validates" (is_ok (Run_metrics.validate_observation ~now_ns:1_000L measured_zero));
  check "unavailable validates as an explicit state"
    (is_ok (Run_metrics.validate_observation ~now_ns:1_000L unavailable));
  check "measured zero is distinct from unavailable"
    (Run_metrics.observation_digest measured_zero <> Run_metrics.observation_digest unavailable);
  check "future sample is rejected"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~sampled_at_ns:10_000_000_000L ())));
  check "non-finite sample is rejected"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~sample:(Measured { value = Float nan; sampled_at_ns = 900L }) ())));
  check "empty unavailable reason is rejected"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~sample:(Unavailable_observed { reason = ""; sampled_at_ns = 900L }) ())));
  check "raw prompts are forbidden labels"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~labels:[ ("prompt", "secret") ] ())));
  check "embedded raw path labels are forbidden"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~labels:[ ("file_path", "/private") ] ())));
  check "future time inside the declared clock tolerance is accepted"
    (is_ok (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~sampled_at_ns:1_001L ())));
  check "future time beyond the declared clock tolerance is rejected"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~sampled_at_ns:1_000_001_001L ())));
  check "wrong metric source is rejected"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~source:Run_metrics.Ocaml_gc ())));
  check "wrong declaration digest is rejected"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       { measured_zero with declaration_digest = String.make 64 '9' }));
  check "stale observation is rejected without becoming zero"
    (is_error (Run_metrics.validate_observation ~now_ns:40_000_000_000L measured_zero));
  check "label cardinality is bounded"
    (is_error (Run_metrics.validate_observation ~now_ns:1_000L
       (observation ~labels:(List.init 9 (fun i -> ("k" ^ string_of_int i, "v"))) ())));
  let otel = Run_metrics.to_otel_json measured_zero in
  List.iter (fun field -> check ("OTel contains " ^ field) (contains_assoc field otel))
    [ "run_id"; "subject_id"; "coordinate"; "rca_origin"; "metric_id";
      "unit"; "availability"; "source"; "sampled_at_ns" ];

  Printf.printf "[feature] pure and fail-closed resource sampling\n";
  check "strict proc status parses VmRSS in kB"
    (Run_resource_sampler.parse_proc_status "Name:\ttest\nVmRSS:\t42 kB\n" = Ok 43_008L);
  check "proc status refuses a missing VmRSS"
    (match Run_resource_sampler.parse_proc_status "Name:\ttest\n" with Error _ -> true | _ -> false);
  check "proc status refuses a duplicate VmRSS"
    (match Run_resource_sampler.parse_proc_status "VmRSS: 1 kB\nVmRSS: 2 kB\n" with Error _ -> true | _ -> false);
  check "load average parses all three horizons"
    (Run_resource_sampler.parse_load_average "0.25 1.5 2.75 1/10 1\n"
     = Ok (0.25, 1.5, 2.75));
  check "load average refuses malformed values"
    (match Run_resource_sampler.parse_load_average "none\n" with Error _ -> true | _ -> false);
  let context : Run_resource_sampler.context =
    { run_id = "run-1"; subject_id = "process"; subject_digest = String.make 64 'd';
      provenance; coordinate = coordinate Ops_capability.Observe;
      rca_origin = Ops_capability.Environment }
  in
  let gc = Gc.quick_stat () in
  let readings : Run_resource_sampler.readings =
    { process_times = Ok { Unix.tms_utime = 1.; tms_stime = 2.;
                           tms_cutime = 3.; tms_cstime = 4. };
      gc = Ok { gc with minor_words = 5.; promoted_words = 6.; major_words = 7.;
                       live_words = 8; heap_words = 9; minor_collections = 10;
                       major_collections = 11; compactions = 12 };
      proc_status = Ok "VmRSS: 13 kB\n";
      load_average = Ok "0.5 1.0 1.5 1/1 1\n" }
  in
  let sampled = Run_resource_sampler.of_readings context ~now_ns:1_000L readings in
  check "sampler emits every process child and self CPU field" (List.length sampled >= 15);
  check "all injected observations validate"
    (List.for_all (fun metric -> is_ok (Run_metrics.validate_observation ~now_ns:1_000L metric)) sampled);
  let unavailable_readings =
    { Run_resource_sampler.process_times = Error "times unavailable";
      gc = Error "gc unavailable"; proc_status = Error "proc unavailable";
      load_average = Error "load unavailable" }
  in
  let unavailable_samples =
    Run_resource_sampler.of_readings context ~now_ns:1_000L unavailable_readings
  in
  check "unavailable sensors still emit the complete metric family"
    (List.length unavailable_samples = List.length sampled && sampled <> []);
  check "unavailable sensors never invent measured zero"
    (List.for_all
       (fun metric -> match metric.Run_metrics.sample with
          | Unavailable_observed { reason; _ } -> String.trim reason <> ""
          | Measured _ -> false)
       unavailable_samples);
  let raising_sensors : Run_resource_sampler.sensors =
    { process_times = (fun () -> failwith "times boom");
      gc = (fun () -> failwith "gc boom");
      read_file = (fun _ -> failwith "file boom") }
  in
  let guarded = Run_resource_sampler.observe_with raising_sensors context ~now_ns:1_000L in
  check "raising injected sensors are total and unavailable"
    (List.length guarded = List.length sampled
     && List.for_all (fun item -> match item.Run_metrics.sample with
          | Unavailable_observed _ -> true | Measured _ -> false) guarded);

  Printf.printf "[structure] correlated bounded trace graph\n";
  let root = trace_span ~attributes:[ { Run_trace.key = "phase";
                                        value = String_value "dispatch" } ] () in
  let child = trace_span ~parent:root.span_id ~span_id:"2222222222222222"
      ~name:"child"
      ~links:
        [ { kind = Run_trace.Metric_link; id = "process.cpu.user_seconds";
            digest = Some (String.make 64 'e'); resolution = Artifact_resolved };
          { kind = Span_link; id = root.span_id; digest = None;
            resolution = Span_resolved
              { trace_id = root.trace_id; span_id = root.span_id } } ] () in
  check "one rooted trace graph validates" (is_ok (Run_trace.validate_graph [ child; root ]));
  check "trace export is deterministic across input order"
    (Run_trace.to_otlp_json [ root; child ] = Run_trace.to_otlp_json [ child; root ]);
  check "orphan span is rejected"
    (is_error (Run_trace.validate_graph [ trace_span ~parent:"ffffffffffffffff" () ]));
  let cycle_a = trace_span ~span_id:"3333333333333333" ~parent:"4444444444444444" () in
  let cycle_b = trace_span ~span_id:"4444444444444444" ~parent:"3333333333333333" () in
  check "cyclic parentage is rejected" (is_error (Run_trace.validate_graph [ cycle_a; cycle_b ]));
  check "invalid W3C identifier is rejected"
    (is_error (Run_trace.validate_graph [ { root with trace_id = "short" } ]));
  let excess_attrs = List.init 33 (fun i -> { Run_trace.key = "k" ^ string_of_int i;
                                              value = Int_value (Int64.of_int i) }) in
  check "attribute cardinality is bounded"
    (is_error (Run_trace.validate_graph [ { root with attributes = excess_attrs } ]));
  check "multiple trace roots are rejected"
    (is_error (Run_trace.validate_graph [ root; { child with parent_span_id = None } ]));
  check "exact-head drift across spans is rejected"
    (is_error (Run_trace.validate_graph
       [ root; { child with provenance = { provenance with source_revision = "drift" } } ]));
  check "a malformed evidence digest is rejected"
    (is_error (Run_trace.validate_graph
       [ { root with links = [ { kind = Evidence_link; id = "receipt";
                                digest = Some "bad";
                                resolution = Artifact_resolved } ] } ]));
  check "authored attributes cannot shadow exact-head context"
    (is_error (Run_trace.validate_graph
       [ { root with attributes = [ { key = "hermes.run.id";
                                      value = String_value "shadow" } ] } ]));
  check "a phantom resolved span target is rejected"
    (is_error (Run_trace.validate_graph
       [ { root with links =
             [ { kind = Span_link; id = "ffffffffffffffff"; digest = None;
                 resolution = Span_resolved
                   { trace_id = root.trace_id; span_id = "ffffffffffffffff" } } ] } ]));
  check "an artifact link cannot masquerade as a span resolution"
    (is_error (Run_trace.validate_graph
       [ { root with links =
             [ { kind = Metric_link; id = "process.cpu.user_seconds";
                 digest = Some (String.make 64 'e');
                 resolution = Span_resolved
                   { trace_id = root.trace_id; span_id = root.span_id } } ] } ]));
  check "a resolved artifact link requires its content digest"
    (is_error (Run_trace.validate_graph
       [ { root with links =
             [ { kind = Evidence_link; id = "receipt"; digest = None;
                 resolution = Artifact_resolved } ] } ]));
  check "a metric trace link must resolve to the modeled metric registry"
    (is_error (Run_trace.validate_graph
       [ { root with links =
             [ { kind = Metric_link; id = "not-a-modeled-metric";
                 digest = Some (String.make 64 'e');
                 resolution = Artifact_resolved } ] } ]));
  let trace_json = match Run_trace.to_otlp_json [ child; root ] with
    | Ok json -> json | Error _ -> `Null in
  let child_json =
    List.find_opt
      (fun json -> assoc_field "spanId" json = Some (`String child.span_id))
      (otlp_spans trace_json)
  in
  check "OTLP span links contain only real resolved span identities"
    (match child_json with
     | Some json ->
         begin match list_field "links" json with
         | [ link ] ->
             assoc_field "traceId" link = Some (`String root.trace_id)
             && assoc_field "spanId" link = Some (`String root.span_id)
         | _ -> false
         end
     | None -> false);
  check "artifact correlations are exported separately from OTLP span links"
    (match child_json with
     | Some json -> List.length (list_field "hermesReferences" json) = 1
     | None -> false);

  Printf.printf "[bdd] data-driven fast path with fail-closed fallback\n";
  let oracle = Run_fast_path.{ id = "snapshot-fold"; digest = String.make 64 'f' } in
  let policy = Run_fast_path.
    { version = "thresholds-v1"; metric_id = "process.cpu.user_seconds";
      low_threshold = 2.; high_threshold = 8.; oracle;
      equivalent_strategies =
        [ (Incremental, oracle.digest); (Snapshot_then_suffix, oracle.digest);
          (Aggregated_graph, oracle.digest) ];
      budget = { max_age_ns = 500L; future_tolerance_ns = 10L; max_cost = 100. };
      admission = Gate_admitted { gate_id = "assurance";
                                  receipt_digest = String.make 64 '1' } }
  in
  let measured_cost = Run_fast_path.Measured_cost
      { value = 10.; sampled_at_ns = 900L; receipt_digest = String.make 64 '6' } in
  let choose ?(cost = measured_cost) policy ~previous ~now_ns observation =
    Run_fast_path.choose policy ~previous ~now_ns ~cost observation
  in
  let low = choose policy ~previous:None ~now_ns:1_000L (observation ()) in
  check "below-low value chooses incremental" (low.strategy = Run_fast_path.Incremental);
  let high_obs = observation ~sample:(Measured { value = Float 9.; sampled_at_ns = 900L }) () in
  let high = choose policy ~previous:(Some low) ~now_ns:1_000L high_obs in
  check "above-high value chooses snapshot plus suffix"
    (high.strategy = Run_fast_path.Snapshot_then_suffix);
  let band_obs = observation ~sample:(Measured { value = Float 5.; sampled_at_ns = 900L }) () in
  let held = choose policy ~previous:(Some high) ~now_ns:1_000L band_obs in
  check "deadband preserves the previous equivalent strategy"
    (held.strategy = Run_fast_path.Snapshot_then_suffix
     && held.reason = Run_fast_path.Hysteresis_hold);
  check "equal samples make deterministic decisions"
    (choose policy ~previous:(Some high) ~now_ns:1_000L band_obs = held);
  let stale = choose policy ~previous:(Some high) ~now_ns:2_000L band_obs in
  check "stale data falls back to reference with diagnostic"
    (stale.strategy = Run_fast_path.Reference && Option.is_some stale.diagnostic);
  let unavailable_decision =
    choose policy ~previous:None ~now_ns:1_000L unavailable
  in
  check "unavailable input falls back explicitly"
    (unavailable_decision.strategy = Reference && Option.is_some unavailable_decision.diagnostic);
  let not_admitted = { policy with admission = Gate_not_admitted
      { gate_id = "assurance"; reason = "receipt stale" } } in
  check "a gate cannot be bypassed"
    ((choose not_admitted ~previous:(Some high) ~now_ns:1_000L high_obs).strategy
     = Reference);
  let non_equivalent = { policy with equivalent_strategies = [] } in
  check "an unproved fast strategy cannot be selected"
    ((choose non_equivalent ~previous:None ~now_ns:1_000L (observation ())).strategy
     = Reference);
  let reordered = { policy with equivalent_strategies = List.rev policy.equivalent_strategies } in
  check "equivalence input ordering does not change the policy digest"
    (Run_fast_path.policy_digest reordered = Run_fast_path.policy_digest policy);
  let wrong_equivalence = { policy with equivalent_strategies =
      [ (Incremental, String.make 64 'e') ] } in
  check "wrong semantic digest falls back to reference"
    ((choose wrong_equivalence ~previous:None ~now_ns:1_000L
        (observation ())).strategy = Reference);
  let malformed_thresholds = { policy with low_threshold = 8.; high_threshold = 2. } in
  check "malformed thresholds fail closed"
    ((choose malformed_thresholds ~previous:None ~now_ns:1_000L
        (observation ())).strategy = Reference);
  check "fast path honors the metric declaration's future tolerance"
    ((choose policy ~previous:None ~now_ns:1_000L
        (observation ~sampled_at_ns:1_001L ())).strategy = Incremental);
  let estimated_cost = Run_fast_path.Estimated_cost
      { value = 9.; estimated_at_ns = 900L; model_digest = String.make 64 '7' } in
  check "fresh bounded estimated cost admits a semantically equivalent fast path"
    (let decision = choose ~cost:estimated_cost policy ~previous:None ~now_ns:1_000L
         (observation ()) in
     decision.strategy = Incremental && Option.is_some decision.cost_digest);
  check "estimated cost above the operative budget falls back"
    ((choose ~cost:(Estimated_cost
          { value = 100.5; estimated_at_ns = 900L;
            model_digest = String.make 64 '7' })
        policy ~previous:None ~now_ns:1_000L (observation ())).strategy = Reference);
  let over_budget_cost = Run_fast_path.Measured_cost
      { value = 100.5; sampled_at_ns = 900L; receipt_digest = String.make 64 '8' } in
  let over_budget =
    choose ~cost:over_budget_cost policy ~previous:None ~now_ns:1_000L (observation ())
  in
  check "measured cost above the operative budget falls back"
    (over_budget.strategy = Reference
     && match over_budget.diagnostic with
        | Some { kind = Run_fast_path.Cost_exceeded; _ } -> true | _ -> false);
  check "unavailable cost evidence cannot admit a fast path"
    ((choose ~cost:(Run_fast_path.Cost_unavailable { reason = "cost sensor absent" })
        policy ~previous:None ~now_ns:1_000L (observation ())).strategy = Reference);
  check "stale cost evidence cannot admit a fast path"
    ((choose ~cost:(Measured_cost
          { value = 10.; sampled_at_ns = 499L; receipt_digest = String.make 64 '9' })
        policy ~previous:None ~now_ns:1_000L (observation ())).strategy = Reference);
  check "measured cost inside the policy clock tolerance remains current"
    ((choose ~cost:(Measured_cost
          { value = 10.; sampled_at_ns = 1_001L;
            receipt_digest = String.make 64 '9' })
        policy ~previous:None ~now_ns:1_000L (observation ())).strategy = Incremental);
  check "estimated cost inside the policy clock tolerance remains current"
    ((choose ~cost:(Estimated_cost
          { value = 10.; estimated_at_ns = 1_001L;
            model_digest = String.make 64 '7' })
        policy ~previous:None ~now_ns:1_000L (observation ())).strategy = Incremental);
  check "cost evidence beyond the policy clock tolerance falls back"
    ((choose ~cost:(Measured_cost
          { value = 10.; sampled_at_ns = 1_011L;
            receipt_digest = String.make 64 '9' })
        policy ~previous:None ~now_ns:1_000L (observation ())).strategy = Reference);
  let admitted_activity =
    match Run_topology.admit_activity
            ~stable_id:"activity.verify-sqlite-dependability" with
    | Ok value -> value
    | Error _ -> failwith "canonical activity fixture refused"
  in
  let context = fast_path_context () in
  let v2 = Run_fast_path.choose_v2 ~context ~activity:admitted_activity
      ~policy ~previous:None ~now_ns:1_000L ~cost:measured_cost (observation ()) in
  check "private v2 selection admits only reference strategy"
    (match v2 with
     | Ok selection -> Run_fast_path.selected_strategy selection = Reference
     | Error _ -> false);
  check "private v2 selection validates against exact context and activity"
    (match v2 with
     | Ok selection ->
         Run_fast_path.validate_selection ~context ~activity:admitted_activity
           selection = Ok ()
     | Error _ -> false);
  let foreign_context =
    fast_path_context ~request_id:"request-foreign" ()
  in
  check "private v2 selection rejects foreign context"
    (match v2 with
     | Ok selection ->
         Result.is_error
           (Run_fast_path.validate_selection ~context:foreign_context
              ~activity:admitted_activity selection)
     | Error _ -> false);
  let uppercase_policy =
    { policy with oracle = { policy.oracle with digest = String.make 64 'F' } }
  in
  check "private v2 selection rejects uppercase digest authority"
    (Result.is_error
       (Run_fast_path.choose_v2 ~context ~activity:admitted_activity
          ~policy:uppercase_policy ~previous:None ~now_ns:1_000L
          ~cost:measured_cost (observation ())));

  Printf.printf "[ontology] eleven aspects and continuous atlas\n";
  check "ontology validates" (is_ok (Run_ontology.validate ()));
  check "ontology is nonempty" (Run_ontology.components <> []);
  List.iter
    (fun id ->
      check (id ^ " resolves") (Option.is_some (Run_ontology.find id));
      match Run_ontology.find id with
      | Some { availability = Run_ontology.Available; _ } ->
          check (id ^ " has a bounded target path to a criterion")
            (Run_atlas.paths_to_criterion id <> [])
      | Some { availability = (Planned _ | Unavailable_observed _); _ } ->
          check (id ^ " is not promoted to currently available") true
      | None -> check (id ^ " availability resolves") false)
    Run_ontology.components;
  check "atlas validates" (is_ok (Run_atlas.validate ()));
  check "an unavailable target cannot be relabeled as an active atlas flow"
    (is_error (Run_atlas.validate_edges
       (List.map (fun (edge : Run_atlas.edge) ->
            if String.equal edge.source "zenoh" && String.equal edge.target "dream"
            then { edge with kind = Run_atlas.Projection_flow }
            else edge)
          Run_atlas.edges)));
  check "the current Hermes rule engine is typed as a naive forward chainer"
    (match Run_ontology.find "rete_naive" with
     | Some component ->
         component.rule_engine = Run_ontology.Naive_forward_chainer
         && component.availability = Available
         && component.authority = Executable
     | None -> false);
  check "Rete_UL remains a planned unavailable engine"
    (match Run_ontology.find "rete_ul" with
     | Some component ->
         component.rule_engine = Run_ontology.Rete_ul_engine
         && (match component.availability with Planned _ -> true | _ -> false)
     | None -> false);
  check "the naive engine, not Rete_UL, currently mediates the command"
    (Run_atlas.has_active_edge "command" "rete_naive"
     && not (Run_atlas.has_active_edge "command" "rete_ul"));
  check "the unavailable Rete_UL target path remains explicitly planned"
    (Run_atlas.has_edge "command" "rete_ul");
  check "the target MCDA topology follows planned Rete_UL, not Hermes_rete"
    (Run_atlas.has_edge "rete_ul" "raven_matrix"
     && not (Run_atlas.has_edge "rete_naive" "raven_matrix"));
  check "the incomplete target admission chain is not reported available"
    (not (Run_atlas.can_reach_available "prompt" "completion_criterion"));
  List.iter
    (fun id ->
      check (id ^ " absent implementation is planned")
        (match Run_ontology.find id with
         | Some { availability = Planned _; authority = Projection; _ } -> true
         | _ -> false))
    [ "rete_ul"; "raven_matrix"; "dream"; "bonsai"; "webgl"; "table";
      "projection_receipt" ];
  check "Swarm is unreachable without assurance"
    (not (Run_atlas.has_edge "command" "swarm")
     && Run_atlas.can_reach "assurance" "swarm"
     && Run_atlas.has_edge "assurance" "swarm_bridge"
     && Run_atlas.has_edge "swarm_bridge" "swarm"
     && not (Run_atlas.has_edge "assurance" "swarm"));
  check "WebGL cannot reach completion admission"
    (not (Run_atlas.can_reach "webgl" "completion_criterion"));
  check "table cannot reach completion admission"
    (not (Run_atlas.can_reach "table" "completion_criterion"));
  check "projection receipts do not become completion receipts"
    (not (Run_atlas.can_reach "projection_receipt" "completion_receipt"));
  begin match Run_ontology.all with
  | first :: rest ->
      let without_integrity = { first with coverage =
          List.filter (fun (aspect, _) -> aspect <> Fractal_ontology.Integrity)
            first.coverage } in
      check "missing an engineering aspect invalidates the ontology"
        (is_error (Run_ontology.validate_components (without_integrity :: rest)));
      let no_integrity = { first with coverage =
          List.map (fun (aspect, claim) ->
              if aspect = Fractal_ontology.Integrity then
                (aspect, Run_ontology.Not_applicable "incorrect") else (aspect, claim))
            first.coverage } in
      check "integrity can never be not applicable"
        (is_error (Run_ontology.validate_components (no_integrity :: rest)));
      let token_not_applicable = { first with coverage =
          List.map (fun (aspect, claim) ->
              if aspect = Fractal_ontology.Data then
                (aspect, Run_ontology.Not_applicable "no receipt") else (aspect, claim))
            first.coverage } in
      check "missing evidence cannot turn an applicable aspect into not-applicable"
        (is_error (Run_ontology.validate_components (token_not_applicable :: rest)))
  | [] -> check "ontology mutant fixtures exist" false
  end;
  begin match Run_ontology.find "rete_ul", Run_ontology.find "rete_naive" with
  | Some rete_ul, Some rete_naive ->
      check "availability mutant cannot promote absent Rete_UL"
        (is_error (Run_ontology.validate_components
           (List.map (fun (component : Run_ontology.component) ->
                if String.equal component.id rete_ul.id then
                  { component with availability = Available }
                else component)
              Run_ontology.all)));
      check "engine-kind mutant cannot relabel Hermes_rete as Rete_UL"
        (is_error (Run_ontology.validate_components
           (List.map (fun (component : Run_ontology.component) ->
                if String.equal component.id rete_naive.id then
                  { component with rule_engine = Rete_ul_engine }
                else component)
              Run_ontology.all)))
  | _ -> check "rule-engine ontology mutant fixtures exist" false
  end;
  begin match Run_ontology.find "dream", Run_ontology.find "webgl" with
  | Some dream, Some webgl ->
      check "absent future-module mutant cannot promote Dream to available"
        (is_error (Run_ontology.validate_components
           (List.map (fun (component : Run_ontology.component) ->
                if String.equal component.id dream.id then
                  { component with availability = Available }
                else component)
              Run_ontology.all)));
      check "projection-authority mutant cannot promote WebGL to executable"
        (is_error (Run_ontology.validate_components
           (List.map (fun (component : Run_ontology.component) ->
                if String.equal component.id webgl.id then
                  { component with authority = Executable }
                else component)
              Run_ontology.all)))
  | _ -> check "future-module ontology mutant fixtures exist" false
  end;
  List.iter
    (fun (component : Run_ontology.component) ->
      check (component.id ^ " treats every R12 systems aspect as applicable")
        (List.for_all (function _, Run_ontology.Addressed _ -> true | _ -> false)
           component.coverage);
      check (component.id ^ " has one typed evidence posture per R12 aspect")
        (List.map fst component.aspect_evidence
           |> List.map Fractal_ontology.aspect_name |> List.sort String.compare
         = (List.map Fractal_ontology.aspect_name Fractal_ontology.aspects
             |> List.sort String.compare)))
    Run_ontology.all;
  check "applicable prompt risks remain typed unverified rather than N/A"
    (match Run_ontology.find "prompt" with
     | Some component ->
         List.for_all
           (fun aspect -> match List.assoc_opt aspect component.aspect_evidence with
              | Some (Run_ontology.Applicable_unverified reason) ->
                  String.trim reason <> ""
              | _ -> false)
           [ Fractal_ontology.Data; Security; Performance; Sre ]
     | None -> false);
  check "all evidence postures for an absent Dream module remain planned"
    (match Run_ontology.find "dream" with
     | Some component ->
         List.for_all
           (function _, Run_ontology.Planned_unavailable reason ->
               String.trim reason <> ""
             | _ -> false)
           component.aspect_evidence
     | None -> false);
  check "unverified prompt Data cannot be promoted without substantiation"
    (match Run_ontology.find "prompt" with
     | Some prompt ->
         let mutant = { prompt with aspect_evidence =
             List.map
               (fun (aspect, status) ->
                 if aspect = Fractal_ontology.Data then
                   (aspect, Run_ontology.Implemented_observed "invented")
                 else (aspect, status))
               prompt.aspect_evidence } in
         is_error (Run_ontology.validate_components
           (List.map (fun (component : Run_ontology.component) ->
                if String.equal component.id prompt.id then mutant else component)
              Run_ontology.all))
     | None -> false);
  check "run and governance lifecycle carriers remain distinct"
    (Run_ontology.Operations_run Run_model.Succeeded
     <> Run_ontology.Governance_declaration Ops_capability.Current);

  Printf.printf "[property] run and projection algebra\n";
  let snapshot, first = snapshot_and_event () in
  check "snapshot plus suffix equals full fold"
    (Run_algebra.snapshot_suffix_equivalent ~split_at:1 [ first ]);
  let second = event ~sequence:1L ~event_id:"heartbeat-1" ~kind:Run_model.Heartbeat
      ~previous_digest:first.digest () in
  let third = event ~sequence:2L ~event_id:"heartbeat-2" ~kind:Run_model.Heartbeat
      ~previous_digest:second.digest () in
  List.iter
    (fun split -> check ("snapshot+suffix split " ^ string_of_int split)
        (Run_algebra.snapshot_suffix_equivalent ~split_at:split [ first; second; third ]))
    [ 0; 1; 2; 3 ];
  check "duplicate event is identity" (Run_algebra.duplicate_identity snapshot first);
  let gap = event ~sequence:2L ~event_id:"gap" ~previous_digest:first.digest () in
  check "a sequence gap requires resynchronisation"
    (Run_algebra.gap_requires_resync snapshot gap);
  check "no heartbeat is unavailable"
    (Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L
       ~future_tolerance_ns:10L ~last_seen_ns:None
     = Run_algebra.Unavailable);
  check "old heartbeat is stale"
    (Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L ~future_tolerance_ns:10L
       ~last_seen_ns:(Some 899L) = Run_algebra.Stale);
  check "current heartbeat is fresh"
    (Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L ~future_tolerance_ns:10L
       ~last_seen_ns:(Some 900L) = Run_algebra.Fresh);
  check "freshness threshold is inclusive"
    (Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L ~future_tolerance_ns:10L
       ~last_seen_ns:(Some 900L) = Run_algebra.Fresh);
  check "future heartbeat inside declared tolerance remains fresh"
    (Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L ~future_tolerance_ns:10L
       ~last_seen_ns:(Some 1_001L) = Run_algebra.Fresh);
  check "future heartbeat beyond declared tolerance is stale"
    (Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L ~future_tolerance_ns:10L
       ~last_seen_ns:(Some 1_011L) = Run_algebra.Stale);
  check "negative heartbeat is stale"
    (Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L ~future_tolerance_ns:10L
       ~last_seen_ns:(Some (-1L)) = Run_algebra.Stale);
  check "all projections are homomorphic"
    (Run_algebra.projection_homomorphism (Run_snapshot.summary snapshot));
  let summary = Run_snapshot.summary snapshot in
  let projections =
    List.map (fun projection -> Run_algebra.project projection summary)
      [ Run_algebra.Table; Tyxml; Webgl_neutral; Otel; Fpp; Mbse ]
  in
  check "all six typed surface carriers normalize to one semantic receipt"
    (Run_algebra.projections_equivalent projections);
  check "Table projection contract is independently pinned"
    (List.exists (function Run_algebra.Table_surface view ->
         view.columns =
           [ "run_id"; "lifecycle"; "last_sequence"; "last_digest";
             "source_revision"; "source_clean"; "configuration_digest";
             "authority_digest"; "executable_digest"; "terminal"; "counts" ]
       | _ -> false) projections);
  check "TyXML projection contract is independently pinned"
    (List.exists (function Run_algebra.Tyxml_surface view ->
         String.equal view.root_role "main" | _ -> false) projections);
  check "WebGL projection contract is independently pinned"
    (List.exists (function Run_algebra.Webgl_surface view ->
         String.equal view.scene_schema "hermes.run.scene.v1" | _ -> false) projections);
  check "OTel projection contract is independently pinned"
    (List.exists (function Run_algebra.Otel_surface view ->
         String.equal view.scope_name "hermes.operations" | _ -> false) projections);
  check "FPP projection contract is independently pinned"
    (List.exists (function Run_algebra.Fpp_surface view ->
         String.equal view.channel "ops.dashboard.run.summary" | _ -> false) projections);
  check "MBSE projection contract is independently pinned"
    (List.exists (function Run_algebra.Mbse_surface view ->
         String.equal view.element_kind "HermesOperationsRun" | _ -> false) projections);
  let drifted_projection =
    List.map
      (function
        | Run_algebra.Webgl_surface view ->
            Run_algebra.Webgl_surface
              { view with semantic =
                  { view.semantic with summary =
                      { view.semantic.summary with last_sequence = 41L } } }
        | projection -> projection)
      projections
  in
  check "one surface semantic-field drift breaks projection equivalence"
    (not (Run_algebra.projections_equivalent drifted_projection));
  let drifted_contract =
    List.map
      (function
        | Run_algebra.Table_surface view ->
            Run_algebra.Table_surface { view with columns = [ "wrong" ] }
        | projection -> projection)
      projections
  in
  check "one surface contract drift breaks projection equivalence"
    (not (Run_algebra.projections_equivalent drifted_contract));
  let receipt_digest summary =
    match Run_algebra.project Run_algebra.Table summary with
    | Run_algebra.Table_surface view -> view.semantic.receipt_digest
    | _ -> ""
  in
  let base_receipt = receipt_digest summary in
  let counts = summary.Run_snapshot.counts in
  let summary_mutants =
    [ ("run_id", { summary with run_id = "run-2" });
      ("lifecycle", { summary with lifecycle = Run_model.Running });
      ("last_sequence", { summary with last_sequence = Int64.succ summary.last_sequence });
      ("last_digest", { summary with last_digest = Some (String.make 64 '9') });
      ("source_revision", { summary with source_revision = "changed" });
      ("source_clean", { summary with source_clean = not summary.source_clean });
      ("configuration_digest", { summary with configuration_digest = String.make 64 '8' });
      ("authority_digest", { summary with authority_digest = String.make 64 '7' });
      ("executable_digest", { summary with executable_digest = String.make 64 '6' });
      ("terminal", { summary with terminal = not summary.terminal });
      ("counts.events", { summary with counts = { counts with events = counts.events + 1 } });
      ("counts.phases_started",
       { summary with counts = { counts with phases_started = counts.phases_started + 1 } });
      ("counts.phases_finished",
       { summary with counts = { counts with phases_finished = counts.phases_finished + 1 } });
      ("counts.suites_discovered",
       { summary with counts = { counts with suites_discovered = counts.suites_discovered + 1 } });
      ("counts.suites_started",
       { summary with counts = { counts with suites_started = counts.suites_started + 1 } });
      ("counts.suites_succeeded",
       { summary with counts = { counts with suites_succeeded = counts.suites_succeeded + 1 } });
      ("counts.suites_failed",
       { summary with counts = { counts with suites_failed = counts.suites_failed + 1 } });
      ("counts.diagnostics",
       { summary with counts = { counts with diagnostics = counts.diagnostics + 1 } });
      ("counts.receipts",
       { summary with counts = { counts with receipts = counts.receipts + 1 } });
      ("counts.residuals",
       { summary with counts = { counts with residuals = counts.residuals + 1 } });
      ("counts.attempts_ready",
       { summary with counts = { counts with attempts_ready = counts.attempts_ready + 1 } });
      ("counts.attempts_running",
       { summary with counts = { counts with attempts_running = counts.attempts_running + 1 } });
      ("counts.attempts_terminal",
       { summary with counts = { counts with attempts_terminal = counts.attempts_terminal + 1 } }) ]
  in
  List.iter
    (fun (field, mutant) ->
      check ("semantic receipt is sensitive to " ^ field)
        (not (String.equal base_receipt (receipt_digest mutant))))
    summary_mutants;
  check "empty required set is unmapped"
    (Run_algebra.complete_required [] = Run_algebra.Unmapped);
  check "all required facts verify"
    (Run_algebra.complete_required [ true; true ] = Run_algebra.Verified);
  check "one absent required fact blocks"
    (Run_algebra.complete_required [ true; false ] = Run_algebra.Blocked);
  List.iter
    (fun origin ->
      let expected = match origin with Ops_capability.Implementation -> Run_algebra.Denies_credit
        | _ -> Run_algebra.Blocks_credit in
      check ("RCA law " ^ Ops_capability.string_of_rca_origin origin)
        (Run_algebra.failure_effect origin = expected))
    [ Ops_capability.Specification; Implementation; Environment; Evidence; Control ];
  let ooda_step ?(run_id = "run-1") ?(level = Ops_capability.LX)
      ?consumes ~phase ~at receipt : Run_algebra.ooda_step =
    { run_id; coordinate = { Ops_capability.level; phase };
      occurred_at_ns = at; consumes_receipt_digest = consumes;
      produces_receipt_digest = receipt }
  in
  let observe_receipt = String.make 64 '1' in
  let orient_receipt = String.make 64 '2' in
  let decide_receipt = String.make 64 '3' in
  let act_receipt = String.make 64 '4' in
  let closing_receipt = String.make 64 '5' in
  let closed_ooda =
    [ ooda_step ~phase:Ops_capability.Observe ~at:100L observe_receipt;
      ooda_step ~consumes:observe_receipt ~phase:Orient ~at:110L orient_receipt;
      ooda_step ~consumes:orient_receipt ~phase:Decide ~at:120L decide_receipt;
      ooda_step ~consumes:decide_receipt ~phase:Act ~at:130L act_receipt;
      ooda_step ~consumes:act_receipt ~phase:Observe ~at:140L closing_receipt ]
  in
  check "Fast OODA is one causal same-run loop within its latency bound"
    (Run_algebra.closes_fast_ooda ~max_latency_ns:40L closed_ooda);
  check "Fast OODA cannot omit Act"
    (not (Run_algebra.closes_fast_ooda ~max_latency_ns:40L
       [ List.nth closed_ooda 0; List.nth closed_ooda 1;
         List.nth closed_ooda 2; List.nth closed_ooda 4 ]));
  check "Fast OODA rejects a cross-run step"
    (not (Run_algebra.closes_fast_ooda ~max_latency_ns:40L
       (List.mapi (fun index (step : Run_algebra.ooda_step) ->
            if index = 2 then { step with run_id = "run-2" } else step)
          closed_ooda)));
  check "Fast OODA rejects a latency-bound overrun"
    (not (Run_algebra.closes_fast_ooda ~max_latency_ns:39L closed_ooda));
  check "closing Observe must consume the Act receipt"
    (not (Run_algebra.closes_fast_ooda ~max_latency_ns:40L
       (List.mapi (fun index (step : Run_algebra.ooda_step) ->
            if index = 4 then
              { step with consumes_receipt_digest = Some decide_receipt }
            else step)
          closed_ooda)));

  Printf.printf "[fuzz] finite hostile metric and transport samples\n";
  let random = Random.State.make [| 0x4f4f44; 0x414f5053 |] in
  for index = 0 to 99 do
    let value = Random.State.float random 1_000. in
    let sample = observation ~sample:(Measured { value = Float value; sampled_at_ns = 900L }) () in
    let one = choose policy ~previous:None ~now_ns:1_000L sample in
    let two = choose policy ~previous:None ~now_ns:1_000L sample in
    check ("deterministic fast path " ^ string_of_int index) (one = two);
    let last_seen =
      if index mod 13 = 0 then None
      else Some (Int64.of_int (Random.State.int random 1_200))
    in
    let state = Run_algebra.transport_state ~now_ns:1_000L ~max_age_ns:100L
        ~future_tolerance_ns:10L
        ~last_seen_ns:last_seen in
    let expected = match last_seen with
      | None -> Run_algebra.Unavailable
      | Some value when value > 1_010L -> Stale
      | Some value when value > 1_000L -> Fresh
      | Some value when Int64.sub 1_000L value <= 100L -> Fresh
      | Some _ -> Stale
    in
    check ("transport state matches the independent freshness model "
           ^ string_of_int index)
      (state = expected)
  done;

  Printf.printf "run_governance: %d checks, %d failures\n" !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_governance"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
