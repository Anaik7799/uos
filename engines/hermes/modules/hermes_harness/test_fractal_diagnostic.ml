(* Battle-testing the fractal diagnostic layer.

   The property that matters is not "does it format nicely" but "can a
   diagnostic ever misclassify". Specifically: an Environment failure must
   never deny parity credit, because nothing was proved; and every failure the
   harness can produce must map to a hazard that the analysis predicted, or the
   analysis is incomplete and we should know. *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let contains text needle =
  let length = String.length text and needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= length
    && (String.sub text index needle_length = needle || loop (index + 1))
  in
  needle_length = 0 || loop 0

let all_capture_failures =
  [ Reference_capture.Interpreter_missing "p"; Reference_capture.Adapter_missing "a";
    Reference_capture.Reference_missing "r"; Reference_capture.Timed_out;
    Reference_capture.Exited (3, "boom"); Reference_capture.Unreadable "bad";
    Reference_capture.Reference_error "nope" ]

let trace_id = String.make 32 'a'
let span_id = String.make 16 'b'

(* ------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  let diagnostic =
    Fractal_diagnostic.make ~hazard:"HZ-CAP-01" ~node:"hermes.model_routing"
      ~subject:"chat.minimal" ~level:Fractal_diagnostic.L4_fixture
      ~origin:Fractal_diagnostic.Environment ~impact:Fractal_diagnostic.Blocks_credit
      ~message:"the reference never ran" ~cause:"interpreter absent"
      ~fix:"provision the reference env" ()
  in
  let rendered = Fractal_diagnostic.render diagnostic in
  check (contains rendered "L4/fixture") "UNIT render carries the fractal level" rendered;
  check (contains rendered "environment") "UNIT render carries the RCA origin" rendered;
  check (contains rendered "hermes.model_routing") "UNIT render carries the node" rendered;
  check (contains rendered "HZ-CAP-01") "UNIT render carries the hazard" rendered;
  check (contains rendered "root cause:" && contains rendered "fix:")
    "UNIT render separates cause from fix" rendered;

  (* An unanalysed harness failure (it blocks credit) says so loudly. *)
  let unanalysed = { diagnostic with hazard = "" } in
  check
    (contains (Fractal_diagnostic.render unanalysed) "UNANALYSED")
    "UNIT unanalysed failures are flagged" "";

  (* A proved divergence has no hazard by design and must NOT read as
     UNANALYSED: it is the harness working, not an unpredicted failure. *)
  let divergence =
    Fractal_diagnostic.of_divergence ~node:"n" ~subject:"s" ~reference_digest:"a"
      ~candidate_digest:"b"
  in
  let rendered_divergence = Fractal_diagnostic.render divergence in
  check
    (not (contains rendered_divergence "UNANALYSED"))
    "UNIT a divergence is not tagged UNANALYSED" rendered_divergence;
  check (contains rendered_divergence "result, not a harness failure")
    "UNIT a divergence is marked a result" rendered_divergence;

  (* Names are distinct, so a log line is unambiguous. *)
  let levels =
    List.map Fractal_diagnostic.level_name
      [ Fractal_diagnostic.L0_product; L1_family; L2_capability; L3_contract;
        L4_fixture; L5_trace; L6_receipt ]
  in
  check (List.length (List.sort_uniq compare levels) = 7) "UNIT levels are distinct" "";
  let origins =
    List.map Fractal_diagnostic.origin_name
      [ Fractal_diagnostic.Specification; Implementation; Environment; Evidence; Control ]
  in
  check (List.length (List.sort_uniq compare origins) = 5) "UNIT origins are distinct" ""

(* ---------------------------------------------------------- FEATURE layer *)

let feature_layer () =
  (* Every capture failure becomes a diagnostic that names a real hazard. *)
  List.iter
    (fun failure ->
      let diagnostic = Capture_diagnostic.of_capture_failure failure in
      check (diagnostic.hazard <> "") "FEATURE capture failure names a hazard"
        (Reference_capture.describe failure);
      check
        (Fractal_diagnostic.hazard diagnostic.hazard <> None)
        "FEATURE named hazard exists in the analysis" diagnostic.hazard)
    all_capture_failures;

  (* A divergence is the only thing that denies credit. *)
  let divergence =
    Fractal_diagnostic.of_divergence ~node:"hermes.model_routing.provider_transports"
      ~subject:"chat.minimal" ~reference_digest:"aaa" ~candidate_digest:"bbb"
  in
  check
    (divergence.impact = Fractal_diagnostic.Denies_credit)
    "FEATURE divergence denies credit" "";
  check
    (divergence.origin = Fractal_diagnostic.Implementation)
    "FEATURE divergence is an implementation defect" "";
  check
    (contains (Fractal_diagnostic.render divergence) "do not widen the normalizer")
    "FEATURE divergence warns against normalizing it away" ""

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  (* Given a missing interpreter, when it is diagnosed, then parity is blocked
     but not denied: nothing was proved, so nothing may be deducted. *)
  let diagnostic =
    Capture_diagnostic.of_capture_failure (Reference_capture.Interpreter_missing "p")
  in
  check
    (diagnostic.impact = Fractal_diagnostic.Blocks_credit)
    "BDD a missing tool blocks credit" "";
  check
    (diagnostic.impact <> Fractal_diagnostic.Denies_credit)
    "BDD a missing tool never denies credit" "";

  (* Given a missing adapter, the fault is the harness's own, not the
     environment's: the harness cannot find a file it ships. *)
  let adapter =
    Capture_diagnostic.of_capture_failure (Reference_capture.Adapter_missing "a")
  in
  check (adapter.origin = Fractal_diagnostic.Control)
    "BDD a missing adapter is a control fault" (Fractal_diagnostic.origin_name adapter.origin);

  (* Given unreadable output, the fault is with the evidence produced, not with
     the environment that produced it. *)
  let unreadable =
    Capture_diagnostic.of_capture_failure (Reference_capture.Unreadable "x")
  in
  check (unreadable.origin = Fractal_diagnostic.Evidence)
    "BDD unreadable output is an evidence fault" ""

(* --------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  (* P1, load-bearing: no Environment or Evidence diagnostic may deny credit.
     Denying credit asserts a divergence was proved, and neither of those
     origins proves anything about the candidate. *)
  let violations =
    List.filter
      (fun failure ->
        let d = Capture_diagnostic.of_capture_failure failure in
        (d.origin = Fractal_diagnostic.Environment
        || d.origin = Fractal_diagnostic.Evidence
        || d.origin = Fractal_diagnostic.Control)
        && d.impact = Fractal_diagnostic.Denies_credit)
      all_capture_failures
  in
  check (violations = []) "PROPERTY non-implementation origins never deny credit"
    (string_of_int (List.length violations));

  (* P2: classification is total and deterministic. *)
  List.iter
    (fun failure ->
      let first = Capture_diagnostic.of_capture_failure failure in
      let second = Capture_diagnostic.of_capture_failure failure in
      check (first = second) "PROPERTY classification is deterministic" "")
    all_capture_failures;

  (* P3: every diagnostic carries a non-empty message, cause and fix. A
     diagnostic without a fix is a complaint, not a diagnosis. *)
  List.iter
    (fun failure ->
      let d = Capture_diagnostic.of_capture_failure failure in
      check
        (d.message <> "" && d.cause <> "" && d.fix <> "")
        "PROPERTY diagnostics are complete" d.hazard)
    all_capture_failures;

  (* P4: every hazard in the analysis is fully populated, and the ones that can
     grant false parity are marked. *)
  List.iter
    (fun (hazard : Fractal_diagnostic.hazard) ->
      check
        (hazard.id <> "" && hazard.unsafe_action <> "" && hazard.failure_mode <> ""
       && hazard.effect_if_undetected <> "" && hazard.detection <> "")
        "PROPERTY hazards are fully specified" hazard.id)
    Fractal_diagnostic.hazards;
  check
    (List.length (Fractal_diagnostic.realising_h1 ()) > 0)
    "PROPERTY some hazards realise H-1" "";

  (* R13 kernel supervision prerequisites are resources, not candidate
     behavior.  They need their own analysed failure mode: collapsing an
     unavailable rlimit or process-group facility into the binary hazard would
     lose the causal distinction and make the countermeasure misleading. *)
  (match Fractal_diagnostic.hazard "HZ-RES-KERNEL" with
  | Some hazard ->
      check (not hazard.realises_h1)
        "PROPERTY a kernel-capability shortfall cannot realise H-1" hazard.id;
      check
        (contains hazard.failure_mode "kernel"
        || contains hazard.failure_mode "RLIMIT"
        || contains hazard.failure_mode "process-group")
        "PROPERTY the kernel resource hazard names its supervision boundary"
        hazard.failure_mode
  | None ->
      check false "PROPERTY HZ-RES-KERNEL is registered" "missing hazard";
      check false "PROPERTY the kernel resource hazard names its supervision boundary"
        "missing hazard");

  (* P5: hazard ids are unique -- a duplicate would make traceability lie. *)
  let ids = List.map (fun (h : Fractal_diagnostic.hazard) -> h.id) Fractal_diagnostic.hazards in
  check
    (List.length (List.sort_uniq compare ids) = List.length ids)
    "PROPERTY hazard ids are unique" ""

(* ------------------------------------------------------------- OTEL layer *)

let otel_layer () =
  let diagnostic =
    Capture_diagnostic.of_capture_failure ~node:"hermes.agent_loop"
      ~subject:"chat.minimal" Reference_capture.Timed_out
  in
  let record =
    Fractal_diagnostic.to_otlp_log ~time_unix_nano:1234567890L ~trace_id ~span_id
      diagnostic
  in
  let text = Yojson.Safe.to_string record in
  (* Shape: the record must be parseable and carry the OTLP required fields. *)
  check (Yojson.Safe.from_string text = record) "OTEL record round-trips as JSON" "";
  List.iter
    (fun field ->
      check (contains text ("\"" ^ field ^ "\"")) ("OTEL record has " ^ field) "")
    [ "timeUnixNano"; "observedTimeUnixNano"; "severityNumber"; "severityText";
      "body"; "traceId"; "spanId"; "attributes" ];

  (* Ids are the widths OTLP requires: 32 hex for a trace, 16 for a span. *)
  check (String.length trace_id = 32) "OTEL trace id is 32 chars" "";
  check (String.length span_id = 16) "OTEL span id is 16 chars" "";

  (* Fractal coordinates are attributes, not prose, so a backend can filter. *)
  List.iter
    (fun key -> check (contains text key) ("OTEL attribute " ^ key) "")
    [ "hermes.fractal.level"; "hermes.rca.origin"; "hermes.parity.effect";
      "hermes.fractal.node"; "hermes.subject"; "hermes.hazard";
      "hermes.hazard.realises_h1"; "hermes.cause"; "hermes.fix" ];

  (* Severity follows the parity effect, per OTel's numeric scale. *)
  let severity_of impact =
    let d = { diagnostic with impact } in
    match
      Fractal_diagnostic.to_otlp_log ~time_unix_nano:0L ~trace_id ~span_id d
    with
    | `Assoc fields -> (
        match List.assoc_opt "severityNumber" fields with Some (`Int n) -> n | _ -> -1)
    | _ -> -1
  in
  check (severity_of Fractal_diagnostic.Denies_credit = 17) "OTEL denies credit is ERROR" "";
  check (severity_of Fractal_diagnostic.Blocks_credit = 13) "OTEL blocks credit is WARN" "";
  check (severity_of Fractal_diagnostic.No_effect = 9) "OTEL no effect is INFO" "";

  (* A full export payload nests resource, scope and records as OTLP expects. *)
  let payload =
    Fractal_diagnostic.to_otlp_payload ~service:"hermes-harness" ~scope:"parity.capture"
      ~time_unix_nano:1L ~trace_id ~span_id
      (List.map Capture_diagnostic.of_capture_failure all_capture_failures)
  in
  let payload_text = Yojson.Safe.to_string payload in
  List.iter
    (fun field ->
      check (contains payload_text ("\"" ^ field ^ "\"")) ("OTEL payload has " ^ field) "")
    [ "resourceLogs"; "resource"; "scopeLogs"; "scope"; "logRecords"; "service.name" ];
  check (Yojson.Safe.from_string payload_text = payload) "OTEL payload round-trips" "";

  (* Every diagnostic in the payload is present: none silently dropped. *)
  let record_count =
    match payload with
    | `Assoc [ ("resourceLogs", `List [ `Assoc resource ]) ] -> (
        match List.assoc_opt "scopeLogs" resource with
        | Some (`List [ `Assoc scope ]) -> (
            match List.assoc_opt "logRecords" scope with
            | Some (`List records) -> List.length records
            | _ -> -1)
        | _ -> -1)
    | _ -> -1
  in
  check
    (record_count = List.length all_capture_failures)
    "OTEL payload keeps every record" (string_of_int record_count)

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  Random.init 20260808;
  let text length =
    String.init length (fun _ ->
        let choices = "abc \"\\\n\t{}[]<>&%" in
        choices.[Random.int (String.length choices)])
  in
  let survived = ref 0 in
  for _ = 1 to 400 do
    let diagnostic =
      Fractal_diagnostic.make ~hazard:(text (Random.int 8)) ~node:(text (Random.int 12))
        ~subject:(text (Random.int 12))
        ~level:
          (List.nth
             [ Fractal_diagnostic.L0_product; L1_family; L2_capability; L3_contract;
               L4_fixture; L5_trace; L6_receipt ]
             (Random.int 7))
        ~origin:
          (List.nth
             [ Fractal_diagnostic.Specification; Implementation; Environment; Evidence;
               Control ]
             (Random.int 5))
        ~impact:
          (List.nth
             [ Fractal_diagnostic.Blocks_credit; Denies_credit; No_effect ]
             (Random.int 3))
        ~message:(text (Random.int 30)) ~cause:(text (Random.int 30))
        ~fix:(text (Random.int 30)) ()
    in
    match
      let rendered = Fractal_diagnostic.render diagnostic in
      let record =
        Fractal_diagnostic.to_otlp_log ~time_unix_nano:0L ~trace_id ~span_id diagnostic
      in
      (* Hostile content must not break the JSON encoding: quotes, backslashes
         and control characters in a message are exactly what a real failure
         string contains. *)
      let encoded = Yojson.Safe.to_string record in
      String.length rendered >= 0 && Yojson.Safe.from_string encoded = record
    with
    | true -> incr survived
    | false -> check false "FUZZ hostile diagnostic content survives encoding" ""
    | exception exn ->
        check false "FUZZ diagnostic encoding does not raise" (Printexc.to_string exn)
  done;
  check (!survived = 400) "FUZZ 400 hostile diagnostics encode cleanly"
    (string_of_int !survived)

(* -------------------------------------------------------- STRUCTURE layer *)

let structure_layer () =
  (* Every capture failure constructor maps to a distinct hazard-bearing
     diagnostic. Adding a constructor without classifying it fails here. *)
  let diagnostics = List.map Capture_diagnostic.of_capture_failure all_capture_failures in
  check
    (List.for_all (fun (d : Fractal_diagnostic.t) -> d.hazard <> "") diagnostics)
    "STRUCTURE every capture failure is classified" "";

  (* Every hazard that realises H-1 states how it is detected. An undetected
     H-1 hazard is the definition of an unsafe system. *)
  List.iter
    (fun (hazard : Fractal_diagnostic.hazard) ->
      check (hazard.detection <> "")
        ("STRUCTURE H-1 hazard " ^ hazard.id ^ " states its detection") "")
    (Fractal_diagnostic.realising_h1 ());

  (* Lookup is total over declared ids and rejects unknown ones. *)
  List.iter
    (fun (hazard : Fractal_diagnostic.hazard) ->
      check (Fractal_diagnostic.hazard hazard.id <> None) "STRUCTURE hazard lookup finds each id"
        hazard.id)
    Fractal_diagnostic.hazards;
  check (Fractal_diagnostic.hazard "HZ-NOPE" = None) "STRUCTURE unknown hazard is not found" ""

let () =
  print_endline "fractal diagnostic suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("feature", feature_layer); ("bdd", bdd_layer);
      ("property", property_layer); ("otel", otel_layer); ("fuzz", fuzz_layer);
      ("structure", structure_layer) ];
  Printf.printf "\nhazards: %d (%d realise H-1)\npassed: %d   failed: %d\n"
    (List.length Fractal_diagnostic.hazards)
    (List.length (Fractal_diagnostic.realising_h1 ()))
    !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_fractal_diagnostic" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
