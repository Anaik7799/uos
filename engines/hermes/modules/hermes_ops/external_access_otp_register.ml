type axis = Behavior | Performance | Scalability | Reliability | Operability | Predictability
type statistic = Median_with_mad
type measurement_protocol = {
  sample_count : int;
  statistic : statistic;
  requires_same_host : bool;
  requires_same_otp_pin : bool;
  requires_warmup : bool;
  requires_replay : bool;
}
type evidence_receipt = {
  run_id : string;
  source_digest : string;
  otp_pin : string;
  host_fingerprint : string;
  evidence_level : int;
}
type status = Unmeasured | Reference_documented
  | Differential_equivalent of evidence_receipt
  | Measured_improvement of evidence_receipt
type improvement = {
  hypothesis : string;
  compatibility_invariant : string;
  proof_obligation_ids : string list;
  acceptance_metric_ids : string list;
}
type row = {
  feature_id : string;
  otp_service : string;
  reference_behavior : string;
  otp_source_paths : string list;
  hermes_component_ids : string list;
  axes : axis list;
  status : status;
  measurement : measurement_protocol;
  improvement : improvement option;
  residual : string;
}
type reference = { release : string; commit : string; pin_file : string }

let reference =
  { release = "30.0-rc0"; commit = "679f9dbbc491d92e99fb08fd3f95fdbe9be30ec0";
    pin_file = "third_party/OTP30_PIN" }

let measurement =
  { sample_count = 7; statistic = Median_with_mad; requires_same_host = true;
    requires_same_otp_pin = true; requires_warmup = true; requires_replay = true }

let improvement hypothesis compatibility_invariant proof_obligation_ids acceptance_metric_ids =
  { hypothesis; compatibility_invariant; proof_obligation_ids; acceptance_metric_ids }

let row ?(status = Reference_documented) ?improvement feature_id otp_service
    reference_behavior otp_source_paths hermes_component_ids axes residual =
  { feature_id; otp_service; reference_behavior; otp_source_paths;
    hermes_component_ids; axes; status; measurement; improvement; residual }

let rows =
  [ row "OTP-EA-001" "supervisor" "hierarchical supervision owns child lifecycle"
      [ "third_party/otp/lib/stdlib/src/supervisor.erl" ]
      [ "externalAccessSupervisor" ] [ Behavior; Reliability; Operability ]
      "typed model only; no live bridge-owned supervisor receipt";
    row "OTP-EA-002" "supervisor" "one_for_one, one_for_all, and rest_for_one restart sets"
      [ "third_party/otp/lib/stdlib/src/supervisor.erl";
        "third_party/otp/lib/stdlib/test/supervisor_SUITE.erl" ]
      [ "externalAccessSupervisor" ] [ Behavior; Reliability ]
      "finite model green; differential oracle run absent";
    row "OTP-EA-003" "supervisor" "restart intensity escalates after bounded failures per period"
      [ "third_party/otp/lib/stdlib/src/supervisor.erl" ]
      [ "externalAccessSupervisor" ] [ Behavior; Reliability; Predictability ]
      "wall-clock and concurrency differential absent";
    row "OTP-EA-004" "supervisor" "permanent, transient, and temporary restart semantics"
      [ "third_party/otp/lib/stdlib/src/supervisor.erl" ]
      [ "externalAccessSupervisor" ] [ Behavior; Reliability ]
      "finite model green; exit-reason differential absent";
    row "OTP-EA-005" "proc_lib/link/monitor" "failures propagate through explicit ownership relationships"
      [ "third_party/otp/lib/stdlib/src/proc_lib.erl" ]
      [ "externalAccessSupervisor"; "externalAccessEvidenceAuthority" ]
      [ Behavior; Reliability; Operability ] "link and monitor equivalence unimplemented";
    row "OTP-EA-006" "erts process" "worker state and failure are isolated from peers"
      [ "third_party/otp/erts/emulator/beam/erl_process.c" ]
      [ "externalAccessSupervisor" ] [ Behavior; Scalability; Reliability ]
      "OCaml isolation and fault-containment benchmark absent";
    row "OTP-EA-007" "process mailbox" "messages are ordered per sender and mailbox state is observable"
      [ "third_party/otp/erts/emulator/beam/erl_message.c" ]
      [ "externalAccessGateway" ] [ Behavior; Performance; Scalability; Operability ]
      "bounded admission mailbox differs intentionally; differential envelope absent";
    row "OTP-EA-008" "BEAM scheduler" "preemptive reductions provide latency and fairness under load"
      [ "third_party/otp/erts/emulator/beam/erl_process.c" ]
      [ "Run_swarm_bridge" ] [ Behavior; Performance; Scalability; Reliability ]
      "Swarm scheduling has no OTP fairness or reduction-equivalence receipt";
    row ~improvement:(improvement
        "typed resource scopes can make cleanup obligations explicit at compile-time boundaries"
        "resource lifetime must be no longer than the corresponding OTP-owned child lifetime"
        [ "EA-IRIS-RESOURCE-CLOSURE"; "EA-QUINT-SCOPE-LIVENESS" ]
        [ "external_access.open_resources"; "external_access.cleanup_latency_ms" ])
      "OTP-EA-009" "process/supervisor resources" "child termination releases owned runtime resources"
      [ "third_party/otp/lib/stdlib/src/supervisor.erl" ]
      [ "externalAccessRecovery" ] [ Behavior; Reliability; Operability; Predictability ]
      "Iris semantic proof and chaos receipt absent";
    row "OTP-EA-010" "exit signals" "shutdown and abnormal exit reasons drive different lifecycle behavior"
      [ "third_party/otp/erts/emulator/beam/erl_process.c" ]
      [ "externalAccessSupervisor" ] [ Behavior; Reliability ]
      "cancellation race differential absent";
    row "OTP-EA-011" "erts timers" "timers are bounded, cancellable, and do not revive stale work"
      [ "third_party/otp/erts/emulator/beam/erl_timer.c" ]
      [ "externalAccessPolicy" ] [ Behavior; Performance; Scalability; Reliability ]
      "timer-wheel scale and cancellation evidence absent";
    row "OTP-EA-012" "registry" "names resolve to live owned processes without duplicate registration"
      [ "third_party/otp/erts/emulator/beam/erl_register.c" ]
      [ "externalAccessPolicy" ] [ Behavior; Operability ]
      "typed identity uniqueness proven only in scoped model";
    row "OTP-EA-013" "trace/system_monitor" "runtime events expose causal process and scheduler behavior"
      [ "third_party/otp/erts/emulator/beam/erl_trace.c" ]
      [ "externalAccessTelemetry" ] [ Behavior; Performance; Operability; Predictability ]
      "trace correspondence and overhead benchmark absent";
    row "OTP-EA-014" "logger" "structured events route with bounded metadata and overload protection"
      [ "third_party/otp/lib/kernel/src/logger.erl" ]
      [ "externalAccessTelemetry" ] [ Behavior; Performance; Reliability; Operability ]
      "logger overload differential absent";
    row "OTP-EA-015" "application_controller" "applications start, stop, and fail as owned dependency trees"
      [ "third_party/otp/lib/kernel/src/application_controller.erl" ]
      [ "externalAccessSupervisor" ] [ Behavior; Reliability; Operability ]
      "application lifecycle correspondence unimplemented";
    row "OTP-EA-016" "release_handler/code_server" "upgrade and rollback preserve declared compatibility"
      [ "third_party/otp/lib/sasl/src/release_handler.erl";
        "third_party/otp/lib/kernel/src/code_server.erl" ]
      [ "externalAccessSupervisor"; "externalAccessRecovery" ]
      [ Behavior; Reliability; Operability ] "hot upgrade is not implemented";
    row "OTP-EA-017" "distribution" "remote identity, failure, ordering, and partition behavior are explicit"
      [ "third_party/otp/erts/emulator/beam/dist.c" ]
      [ "externalAccessNetworkAdapter" ] [ Behavior; Performance; Scalability; Reliability; Operability ]
      "external-access distribution is not implemented";
    row "OTP-EA-018" "ETS" "concurrent shared state has declared ownership and consistency behavior"
      [ "third_party/otp/erts/emulator/beam/erl_db.c" ]
      [ "externalAccessEvidenceAuthority" ] [ Behavior; Performance; Scalability; Reliability ]
      "SQLite state has different semantics and needs explicit comparative envelope";
    row ~improvement:(improvement
        "bounded typed mailboxes and pre-admission backpressure can prevent hidden overload earlier"
        "accepted request ordering and refusal semantics must remain deterministic and documented"
        [ "EA-Z3-MAILBOX-BOUND"; "EA-QUINT-BACKPRESSURE-LIVENESS" ]
        [ "external_access.mailbox_depth"; "external_access.refused_intents" ])
      "OTP-EA-019" "mailbox overload" "mailbox growth and scheduler pressure are visible to operators"
      [ "third_party/otp/erts/emulator/beam/erl_message.c" ]
      [ "externalAccessGateway"; "externalAccessTelemetry" ]
      [ Performance; Scalability; Reliability; Operability; Predictability ]
      "improvement hypothesis is unmeasured";
    row ~improvement:(improvement
        "fractal path state can forecast saturation, restart storms, and readback risk before failure"
        "predictions may only recommend; they cannot bypass admission or raise evidence credit"
        [ "EA-STAN-CALIBRATION"; "EA-Z3-CREDIT-NONESCALATION";
          "EA-QUINT-PREDICTION-SAFETY" ]
        [ "external_access.prediction_brier"; "external_access.prediction_lead_time_ms" ])
      "OTP-EA-020" "system_monitor" "runtime thresholds surface pressure and abnormal behavior"
      [ "third_party/otp/erts/emulator/beam/erl_monitor_link.c" ]
      [ "externalAccessTelemetry"; "externalAccessPolicy" ]
      [ Reliability; Operability; Predictability ] "calibration history and controlled Stan receipt absent";
    row ~improvement:(improvement
        "lexically scoped typed capabilities can reduce ambient external authority"
        "all behavior admitted by OTP comparison must remain expressible without ambient authority"
        [ "EA-ROCQ-AUTHORITY-CONSERVATION"; "EA-IRIS-CAPABILITY-OWNERSHIP" ]
        [ "external_access.authority_denials"; "external_access.bypass_findings" ])
      "OTP-EA-021" "runtime authority" "runtime services own and mediate OS resources"
      [ "third_party/otp/erts/emulator/beam/erl_driver.h" ]
      [ "externalAccessPolicy" ] [ Behavior; Reliability; Operability; Predictability ]
      "capability theorem and zero-bypass census absent";
    row ~status:Unmeasured ~improvement:(improvement
        "evidence-bound tuning recommendations can shorten diagnosis without unsafe auto-tuning"
        "recommendations remain no-effect until a fresh admitted intent authorizes change"
        [ "EA-STPA-TUNING-UCA"; "EA-Z3-RECOMMENDATION-NOEFFECT" ]
        [ "external_access.mtta_ms"; "external_access.false_intervention_rate" ])
      "OTP-EA-022" "observer and operator tooling" "operators inspect truthful runtime state and act explicitly"
      [ "third_party/otp/lib/observer" ]
      [ "externalAccessTelemetry"; "externalAccessPolicy" ]
      [ Operability; Predictability ] "improvement hypothesis is unmeasured" ]

let nonempty value = String.trim value <> ""
let unique values = List.length values = List.length (List.sort_uniq String.compare values)

let valid_receipt receipt =
  nonempty receipt.run_id && String.length receipt.source_digest = 64
  && receipt.otp_pin = reference.commit && nonempty receipt.host_fingerprint
  && receipt.evidence_level >= 4 && receipt.evidence_level <= 6

let validate rows =
  let gaps = ref [] in
  let ids = List.map (fun row -> row.feature_id) rows in
  if rows = [] then gaps := "OTP register is empty" :: !gaps;
  if not (List.for_all nonempty ids && unique ids) then
    gaps := "OTP register identities are empty or duplicate" :: !gaps;
  List.iter
    (fun row ->
      if not (nonempty row.otp_service && nonempty row.reference_behavior
              && row.otp_source_paths <> [] && row.hermes_component_ids <> []
              && row.axes <> [] && nonempty row.residual)
      then gaps := (row.feature_id ^ " is incomplete") :: !gaps;
      if List.length row.axes <> List.length (List.sort_uniq compare row.axes) then
        gaps := (row.feature_id ^ " duplicates an axis") :: !gaps;
      if List.mem Performance row.axes
         && (row.measurement.sample_count <> 7
             || row.measurement.statistic <> Median_with_mad
             || not row.measurement.requires_same_host
             || not row.measurement.requires_same_otp_pin)
      then gaps := (row.feature_id ^ " weakens performance measurement") :: !gaps;
      begin match row.status with
      | Unmeasured | Reference_documented -> ()
      | Differential_equivalent receipt | Measured_improvement receipt ->
          if not (valid_receipt receipt) then
            gaps := (row.feature_id ^ " has an invalid L4-L6 receipt") :: !gaps
      end;
      begin match row.improvement with
      | None -> ()
      | Some item ->
          if not (nonempty item.hypothesis && nonempty item.compatibility_invariant
                  && item.proof_obligation_ids <> [] && item.acceptance_metric_ids <> [])
          then gaps := (row.feature_id ^ " improvement is not falsifiable") :: !gaps
      end)
    rows;
  let axes = rows |> List.concat_map (fun row -> row.axes) |> List.sort_uniq compare in
  if axes <> [ Behavior; Performance; Scalability; Reliability; Operability; Predictability ]
  then gaps := "six-axis denominator differs" :: !gaps;
  List.rev !gaps

let axis_name = function
  | Behavior -> "behavior" | Performance -> "performance" | Scalability -> "scalability"
  | Reliability -> "reliability" | Operability -> "operability"
  | Predictability -> "predictability"

let source_digest =
  rows
  |> List.concat_map (fun row ->
      row.feature_id :: row.otp_service :: row.reference_behavior :: row.residual
      :: (List.map axis_name row.axes @ row.otp_source_paths @ row.hermes_component_ids))
  |> String.concat "\000"
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
