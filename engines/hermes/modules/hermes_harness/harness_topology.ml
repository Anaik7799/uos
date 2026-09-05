(* The harness AS an F Prime topology. See harness_topology.mli.

   Everything here is a description of machinery that already exists — the
   components are the real modules, the connections are the real dataflow,
   the state machine is the real converge loop, the parameters are the real
   environment knobs. Nothing is aspirational; where the harness has no
   counterpart, the model has no element. *)

open Fpp_model

(* --------------------------------------------------------------- ports *)

let port_defs =
  [ { port_name = "Rows"; params = [ ("rows", Named "EvidenceRow") ]; return_type = None };
    { port_name = "Verdicts"; params = [ ("verdict", Named "Verdict") ]; return_type = None };
    { port_name = "Sweep"; params = [ ("worst", Named "Alert") ]; return_type = None };
    { port_name = "Gate"; params = [ ("satisfied", Prim Bool) ]; return_type = None };
    { port_name = "Plan"; params = [ ("converged", Prim Bool) ]; return_type = None };
    { port_name = "Ping"; params = [ ("key", Prim U32) ]; return_type = None };
    { port_name = "Time"; params = [ ("revision", Prim (String (Some 64))) ]; return_type = None };
    { port_name = "Mesh"; params = [ ("payload", Prim (String (Some 1024))) ]; return_type = None };
    { port_name = "Log"; params = [ ("diagnostic", Prim (String (Some 256))) ]; return_type = None } ]

(* The two lattices as FPP enums — separate types, so the forbidden
   morphism (alert -> verdict) cannot even be typed. *)
let type_defs =
  [ Enum_t
      { name = "Verdict"; repr = U8;
        constants = [ ("VERIFIED", 0); ("UNMAPPED", 1); ("BLOCKED", 2); ("DIVERGENT", 3) ] };
    Enum_t
      { name = "Alert"; repr = U8;
        constants = [ ("GREEN", 0); ("P2", 1); ("P1", 2); ("P0", 3) ] };
    Struct_t
      { name = "EvidenceRow";
        members =
          [ ("contract", Prim (String (Some 64))); ("scenario", Prim (String (Some 64)));
            ("passed", Prim Bool) ] } ]

(* ---------------------------------------------------------- state machine *)

(* The converge loop (auto_converge / Converge), OODA-shaped: preflight
   gates (R13), the choice node is the Kleene-iteration decision, Anomalous
   is terminal (exit 2 — every verdict suspect; a human, not a signal,
   resets, the L-09 breaker lesson). *)
let converge_loop =
  Internal_machine
    { machine_name = "ConvergeLoop";
      signals =
        [ { signal_name = "tick"; signal_type = None };
          { signal_name = "preflight_ok"; signal_type = None };
          { signal_name = "preflight_refused"; signal_type = None };
          { signal_name = "progress"; signal_type = None };
          { signal_name = "no_progress"; signal_type = None };
          { signal_name = "anomaly"; signal_type = Some (Prim (String (Some 128))) } ];
      guards = [ "frontier_advanced" ];
      actions = [ "observe"; "orient"; "decide"; "act"; "record"; "alert" ];
      states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "tick"; guard = None; do_actions = []; target = To_state "Preflight" } ] };
          { state_name = "Preflight"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "preflight_ok"; guard = None; do_actions = [ "observe" ];
                  target = To_state "Observing" };
                { on_signal = "preflight_refused"; guard = None; do_actions = [ "alert" ];
                  target = To_state "Blocked" } ] };
          { state_name = "Observing"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "progress"; guard = None; do_actions = [];
                  target = To_choice "advance" };
                { on_signal = "no_progress"; guard = None; do_actions = [ "record" ];
                  target = To_state "Converged" };
                { on_signal = "anomaly"; guard = None; do_actions = [ "alert" ];
                  target = To_state "Anomalous" } ] };
          { state_name = "Converged"; entry = [ "record" ]; exit_ = [];
            transitions =
              [ { on_signal = "tick"; guard = None; do_actions = []; target = To_state "Preflight" } ] };
          { state_name = "Blocked"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "tick"; guard = None; do_actions = []; target = To_state "Preflight" } ] };
          { state_name = "Anomalous"; entry = [ "alert" ]; exit_ = []; transitions = [] } ];
      choices =
        [ { choice_name = "advance"; choice_guard = "frontier_advanced";
            if_true = ([ "orient"; "decide"; "act"; "record" ], To_state "Observing");
            if_false = ([ "record" ], To_state "Converged") } ];
      initial = ([], "Idle") }

(* ------------------------------------------------------------ components *)

let ping_pair =
  [ General { name = "pingIn"; port = "Ping"; direction = Sync_input; count = 1 };
    General { name = "pingOut"; port = "Ping"; direction = Output; count = 1 } ]

let inventory =
  { comp_name = "inventory"; kind = Passive;
    ports =
      [ (* The time-pattern source: the snapshot digest + git revision ARE
           this system's time context. *)
        General { name = "timeGetIn"; port = "Time"; direction = Sync_input; count = 8 };
        General { name = "rowsOut"; port = "Rows"; direction = Output; count = 1 } ];
    commands = []; events = [];
    channels =
      [ { chan_name = "modules_scanned"; chan_id = 0; chan_type = Prim U32;
          update = Always; chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let capability_catalog =
  { comp_name = "capability_catalog"; kind = Passive;
    ports =
      [ General { name = "inventoryIn"; port = "Rows"; direction = Sync_input; count = 2 };
        General { name = "catalogOut"; port = "Rows"; direction = Output; count = 2 };
        Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = []; events = []; channels = []; parameters = []; records = [];
    containers = []; internal_ports = []; machines = []; matched = [] }

let gospel_contracts =
  { comp_name = "gospel_contracts"; kind = Passive;
    ports =
      [ General { name = "catalogIn"; port = "Rows"; direction = Sync_input; count = 1 };
        General { name = "storeIn"; port = "Rows"; direction = Sync_input; count = 1 };
        Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = []; events = []; channels = []; parameters = []; records = [];
    containers = []; internal_ports = []; machines = []; matched = [] }

let reference_capture =
  { comp_name = "reference_capture"; kind = Passive;
    ports =
      [ General { name = "catalogIn"; port = "Rows"; direction = Sync_input; count = 1 };
        General { name = "storeIn"; port = "Rows"; direction = Sync_input; count = 1 };
        General { name = "configIn"; port = "Gate"; direction = Sync_input; count = 1 };
        General { name = "resourceIn"; port = "Gate"; direction = Sync_input; count = 1 };
        General { name = "captureOut"; port = "Rows"; direction = Output; count = 1 };
        Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = []; events = []; channels = []; parameters = []; records = [];
    containers = []; internal_ports = []; machines = []; matched = [] }

let parity_normalizer =
  { comp_name = "parity_normalizer"; kind = Passive;
    ports =
      [ General { name = "captureIn"; port = "Rows"; direction = Sync_input; count = 1 };
        Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = []; events = []; channels = []; parameters = []; records = [];
    containers = []; internal_ports = []; machines = []; matched = [] }

let evidence_store =
  { comp_name = "evidence_store"; kind = Passive;
    ports =
      [ General { name = "record"; port = "Rows"; direction = Guarded_input; count = 4 };
        General { name = "rows"; port = "Rows"; direction = Output; count = 4 };
        General { name = "storeOut"; port = "Rows"; direction = Output; count = 3 };
        Special Event_p; Special Telemetry_p; Special Time_get ]
      @ ping_pair;
    commands = [];
    events =
      [ { event_name = "RECEIPT_RECORDED"; event_id = 4; severity = Diagnostic;
          format = "receipt recorded for %s"; throttle = None } ];
    channels =
      [ { chan_name = "receipts_total"; chan_id = 0; chan_type = Prim U32; update = Always;
          chan_format = None; low = None; high = None };
        { chan_name = "verified_count"; chan_id = 1; chan_type = Prim U32; update = On_change;
          chan_format = None;
          low = Some { yellow = None; orange = None; red = Some 0.0 }; high = None } ];
    parameters = [];
    records =
      [ (* The store's rows are this system's data products. *)
        { record_name = "receipt"; record_id = 8; record_type = Named "EvidenceRow";
          record_is_array = true } ];
    containers = [ { container_name = "evidence"; container_id = 9; default_priority = Some 1 } ];
    internal_ports = []; machines = []; matched = [] }

let parity_compare =
  { comp_name = "parity_compare"; kind = Passive;
    ports =
      [ General { name = "gate"; port = "Gate"; direction = Sync_input; count = 2 };
        General { name = "verdicts"; port = "Verdicts"; direction = Output; count = 1 };
        General { name = "receipts"; port = "Rows"; direction = Output; count = 1 };
        Special Event_p; Special Telemetry_p; Special Time_get ]
      @ ping_pair;
    commands =
      [ { cmd_name = "COMPARE_ALL"; opcode = 0; cmd_kind = Sync_cmd; cmd_params = [] };
        { cmd_name = "COMPARE_SCENARIO"; opcode = 1; cmd_kind = Sync_cmd;
          cmd_params = [ ("scenario", Prim (String (Some 64))) ] } ];
    events =
      [ { event_name = "DIVERGENCE_FOUND"; event_id = 2; severity = Activity_hi;
          format = "divergence on %s -- a successful measurement"; throttle = None };
        { event_name = "SCENARIO_VERIFIED"; event_id = 3; severity = Activity_lo;
          format = "%s verified"; throttle = None };
        { event_name = "ORACLE_UNAVAILABLE"; event_id = 4; severity = Warning_hi;
          format = "oracle %s unavailable -- Blocked, nothing proved"; throttle = None } ];
    channels =
      [ { chan_name = "scenarios_compared"; chan_id = 5; chan_type = Prim U32;
          update = Always; chan_format = None; low = None; high = None };
        { chan_name = "divergences_open"; chan_id = 6; chan_type = Prim U32;
          update = On_change; chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let parity_algebra =
  { comp_name = "parity_algebra"; kind = Passive;
    ports =
      [ General { name = "verdicts"; port = "Verdicts"; direction = Sync_input; count = 4 };
        General { name = "verdict"; port = "Verdicts"; direction = Output; count = 1 } ];
    commands = []; events = [];
    channels =
      [ { chan_name = "fold_rank"; chan_id = 0; chan_type = Named "Verdict";
          update = On_change; chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let resource_envelope =
  { comp_name = "resource_envelope"; kind = Passive;
    ports =
      [ General { name = "check"; port = "Gate"; direction = Output; count = 3 };
        Special Event_p ];
    commands = [ { cmd_name = "PREFLIGHT"; opcode = 0; cmd_kind = Guarded_cmd; cmd_params = [] } ];
    events =
      [ { event_name = "PREFLIGHT_REFUSED"; event_id = 1; severity = Warning_hi;
          format = "R13: resource %s unavailable -- refusing"; throttle = None } ];
    channels = []; parameters = []; records = []; containers = [];
    internal_ports = []; machines = []; matched = [] }

let blueprint =
  { comp_name = "blueprint"; kind = Passive;
    ports =
      [ General { name = "actual"; port = "Verdicts"; direction = Sync_input; count = 1 };
        General { name = "plan"; port = "Plan"; direction = Output; count = 2 };
        Special Event_p ];
    commands =
      [ { cmd_name = "VALIDATE"; opcode = 0; cmd_kind = Sync_cmd; cmd_params = [] };
        { cmd_name = "RECONCILE"; opcode = 1; cmd_kind = Sync_cmd; cmd_params = [] } ];
    events =
      [ { event_name = "DRIFT_DETECTED"; event_id = 2; severity = Warning_lo;
          format = "intent %s drifted"; throttle = None };
        { event_name = "CONVERGED"; event_id = 3; severity = Activity_lo;
          format = "blueprint converged"; throttle = None } ];
    channels =
      [ { chan_name = "directives_satisfied"; chan_id = 4; chan_type = Prim U32;
          update = On_change; chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let harness_config =
  { comp_name = "harness_config"; kind = Active;
    ports =
      [ General { name = "run"; port = "Gate"; direction = Output; count = 5 };
        Special Command_recv; Special Command_reg; Special Command_resp;
        Special Event_p; Special Telemetry_p; Special Time_get ]
      @ ping_pair;
    commands =
      [ { cmd_name = "RUN_PIPELINE"; opcode = 0;
          cmd_kind = Async_cmd { priority = Some 1; queue_full = Assert }; cmd_params = [] };
        { cmd_name = "CONVERGE"; opcode = 1;
          cmd_kind = Async_cmd { priority = None; queue_full = Block }; cmd_params = [] } ];
    events =
      [ { event_name = "PIPELINE_BLOCKED"; event_id = 2; severity = Warning_hi;
          format = "activity %s blocked -- fail-closed"; throttle = None };
        { event_name = "ANOMALY"; event_id = 3; severity = Fatal;
          format = "converge anomaly: %s -- every verdict suspect"; throttle = None } ];
    channels =
      [ { chan_name = "activities_run"; chan_id = 4; chan_type = Prim U32; update = Always;
          chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = [ ("converge", "ConvergeLoop") ]; matched = [] }

let control_plane =
  { comp_name = "control_plane"; kind = Passive;
    ports =
      [ General { name = "history"; port = "Rows"; direction = Sync_input; count = 1 };
        General { name = "alerts"; port = "Sweep"; direction = Sync_input; count = 2 };
        General { name = "sweep"; port = "Sweep"; direction = Output; count = 2 };
        (* The Svc::Health analogue: the ping table over the fractal. *)
        General { name = "pingOut"; port = "Ping"; direction = Output; count = 8 };
        General { name = "pingIn"; port = "Ping"; direction = Sync_input; count = 8 };
        Special Event_p; Special Telemetry_p; Special Time_get ];
    commands = [];
    events =
      [ { event_name = "SWEEP_P0"; event_id = 2; severity = Fatal;
          format = "P0: %s -- exit 2"; throttle = None };
        { event_name = "SWEEP_P1"; event_id = 3; severity = Warning_hi;
          format = "P1: %s"; throttle = None };
        { event_name = "SWEEP_P2"; event_id = 4; severity = Warning_lo;
          format = "P2: %s"; throttle = None };
        { event_name = "SWEEP_GREEN"; event_id = 5; severity = Activity_lo;
          format = "sweep green"; throttle = None } ];
    channels =
      [ { chan_name = "worst_alert"; chan_id = 0; chan_type = Named "Alert";
          update = On_change; chan_format = None; low = None;
          high = Some { yellow = Some 1.0; orange = Some 2.0; red = Some 3.0 } };
        { chan_name = "legs_green"; chan_id = 1; chan_type = Prim U8; update = Always;
          chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let homeostasis =
  { comp_name = "homeostasis"; kind = Passive;
    ports =
      [ General { name = "window"; port = "Rows"; direction = Sync_input; count = 2 };
        General { name = "satisfied"; port = "Plan"; direction = Sync_input; count = 1 };
        General { name = "alert"; port = "Sweep"; direction = Output; count = 4 };
        General { name = "resilienceOut"; port = "Rows"; direction = Output; count = 6 } ];
    commands = []; events = [];
    channels =
      [ { chan_name = "lyapunov"; chan_id = 0; chan_type = Prim U32; update = On_change;
          chan_format = None; low = None; high = None };
        { chan_name = "breaker_open"; chan_id = 1; chan_type = Prim Bool; update = On_change;
          chan_format = None; low = None; high = None } ];
    parameters =
      [ { param_name = "WINDOW"; param_id = 2; param_type = Prim U32; default = Some "10";
          set_opcode = 0x10; save_opcode = 0x11; external_ = false };
        { param_name = "BREAKER_THRESHOLD"; param_id = 3; param_type = Prim U32;
          default = Some "3"; set_opcode = 0x12; save_opcode = 0x13; external_ = false } ];
    records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let hermes_zenoh =
  { comp_name = "hermes_zenoh"; kind = Passive;
    ports =
      [ General { name = "publish"; port = "Sweep"; direction = Sync_input; count = 4 };
        General { name = "tlmIn"; port = "Mesh"; direction = Sync_input; count = 8 };
        General { name = "gossipOut"; port = "Rows"; direction = Output; count = 6 };
        Special Event_p; Special Time_get ]
      @ ping_pair;
    commands = [];
    events =
      [ { event_name = "MESH_UNREACHABLE"; event_id = 4; severity = Warning_lo;
          format = "zenoh: %s -- telemetry stays local"; throttle = None } ];
    channels =
      [ { chan_name = "publishes_ok"; chan_id = 2; chan_type = Prim U32; update = Always;
          chan_format = None; low = None; high = None };
        { chan_name = "publish_errors"; chan_id = 3; chan_type = Prim U32; update = Always;
          chan_format = None; low = None;
          high = Some { yellow = Some 1.0; orange = None; red = None } } ];
    parameters =
      [ { param_name = "ENDPOINT"; param_id = 0; param_type = Prim (String (Some 128));
          default = Some "tcp/127.0.0.1:7447"; set_opcode = 0x20; save_opcode = 0x21;
          external_ = false };
        { param_name = "ENABLED"; param_id = 1; param_type = Prim Bool; default = Some "true";
          set_opcode = 0x22; save_opcode = 0x23; external_ = false } ];
    records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let irmin =
  { comp_name = "irmin"; kind = Passive;
    ports = [ General { name = "memoryOut"; port = "Rows"; direction = Output; count = 6 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let eio =
  { comp_name = "eio"; kind = Passive;
    ports = [ General { name = "eioOut"; port = "Rows"; direction = Output; count = 6 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let fractal_diagnostic =
  { comp_name = "fractal_diagnostic"; kind = Passive;
    ports =
      [ General { name = "logIn"; port = "Log"; direction = Sync_input; count = 8 } ];
    commands = []; events = []; channels = []; parameters = [];
    records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let agents =
  { comp_name = "agents"; kind = Passive;
    ports = [ General { name = "taskIn"; port = "Rows"; direction = Sync_input; count = 10 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let sop =
  { comp_name = "sop"; kind = Passive;
    ports = [ General { name = "sopOut"; port = "Rows"; direction = Output; count = 5 };
              General { name = "sopIn"; port = "Rows"; direction = Sync_input; count = 6 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let planning =
  { comp_name = "planning"; kind = Passive;
    ports = [ General { name = "planOut"; port = "Rows"; direction = Output; count = 1 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let job_manager =
  { comp_name = "job_manager"; kind = Passive;
    ports = [ General { name = "jobOut"; port = "Rows"; direction = Output; count = 5 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let temporal =
  { comp_name = "temporal"; kind = Passive;
    ports = [ General { name = "wfOut"; port = "Rows"; direction = Output; count = 6 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let skills =
  { comp_name = "skills"; kind = Passive;
    ports = [ General { name = "skillOut"; port = "Rows"; direction = Output; count = 1 };
              General { name = "agentIn"; port = "Rows"; direction = Sync_input; count = 1 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let superpowers =
  { comp_name = "superpowers"; kind = Passive;
    ports = [ General { name = "powerOut"; port = "Rows"; direction = Output; count = 1 };
              General { name = "agentIn"; port = "Rows"; direction = Sync_input; count = 1 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let rules =
  { comp_name = "rules"; kind = Passive;
    ports = [ General { name = "agentOut"; port = "Rows"; direction = Output; count = 5 };
              General { name = "skillOut"; port = "Rows"; direction = Output; count = 1 };
              General { name = "powerOut"; port = "Rows"; direction = Output; count = 1 } ];
    commands = []; events = []; channels = []; parameters = []; records = []; containers = []; internal_ports = []; machines = []; matched = [] }

(* ------------------------------------------------------------- instances *)

let instances =
  let passive name base =
    { inst_name = name; of_component = name; base_id = base; queue_size = None;
      stack_size = None; inst_priority = None; cpu = None }
  in
  let agent_inst name base =
    { inst_name = name; of_component = "agents"; base_id = base; queue_size = None;
      stack_size = None; inst_priority = None; cpu = None }
  in
  [ passive "inventory" 0x100;
    passive "capability_catalog" 0x110;
    passive "gospel_contracts" 0x120;
    passive "reference_capture" 0x130;
    passive "parity_normalizer" 0x140;
    passive "evidence_store" 0x200;
    passive "parity_compare" 0x300;
    passive "parity_algebra" 0x400;
    passive "resource_envelope" 0x500;
    passive "blueprint" 0x600;
    { inst_name = "harness_config"; of_component = "harness_config";
      base_id = Fpp_window_authority.base_of_instance Fpp_window_authority.Harness "harness_config";
      queue_size = Some 16; stack_size = Some 65536; inst_priority = Some 5; cpu = Some 0 };
    passive "control_plane" 0x800;
    passive "homeostasis" 0x900;
    passive "hermes_zenoh" 0xA00;
    passive "fractal_diagnostic" 0xB00;
    agent_inst "agent_1" 0xC01;
    agent_inst "agent_2" 0xC02;
    agent_inst "agent_3" 0xC03;
    agent_inst "agent_4" 0xC04;
    agent_inst "agent_5" 0xC05;
    passive "sop" 0xC10;
    passive "planning" 0xC20;
    passive "job_manager" 0xC30;
    passive "temporal" 0xC40;
    passive "skills" 0xD00;
    passive "rules" 0xE00;
    passive "superpowers" 0xF00;
    passive "irmin" 0x1000;
    passive "eio" 0x1100 ]

(* -------------------------------------------------------------- topology *)

let topology =
  { topo_name = "hermes_harness";
    members = List.map (fun i -> i.inst_name) instances;
    graphs =
      [ (* Domain dataflow: every connection lies over a fractal-ontology
           edge — the differential law below enforces it. *)
        Direct
          { graph_name = "evidence";
            connections =
              [ { from_ = { ep_instance = "inventory"; ep_port = "rowsOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "capability_catalog"; ep_port = "inventoryIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "capability_catalog"; ep_port = "catalogOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "gospel_contracts"; ep_port = "catalogIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "capability_catalog"; ep_port = "catalogOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "reference_capture"; ep_port = "catalogIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "evidence_store"; ep_port = "storeOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "gospel_contracts"; ep_port = "storeIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "evidence_store"; ep_port = "storeOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "reference_capture"; ep_port = "storeIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "evidence_store"; ep_port = "storeOut"; ep_index = Some 2 };
                  to_ = { ep_instance = "capability_catalog"; ep_port = "inventoryIn"; ep_index = Some 1 } };
                { from_ = { ep_instance = "reference_capture"; ep_port = "captureOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "parity_normalizer"; ep_port = "captureIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "parity_compare"; ep_port = "receipts"; ep_index = Some 0 };
                  to_ = { ep_instance = "evidence_store"; ep_port = "record"; ep_index = Some 0 } };
                { from_ = { ep_instance = "parity_compare"; ep_port = "verdicts"; ep_index = Some 0 };
                  to_ = { ep_instance = "parity_algebra"; ep_port = "verdicts"; ep_index = Some 0 } };
                { from_ = { ep_instance = "parity_algebra"; ep_port = "verdict"; ep_index = Some 0 };
                  to_ = { ep_instance = "blueprint"; ep_port = "actual"; ep_index = Some 0 } };
                { from_ = { ep_instance = "sop"; ep_port = "sopOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "sop"; ep_port = "sopOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "agent_2"; ep_port = "taskIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "sop"; ep_port = "sopOut"; ep_index = Some 2 };
                  to_ = { ep_instance = "agent_3"; ep_port = "taskIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "sop"; ep_port = "sopOut"; ep_index = Some 3 };
                  to_ = { ep_instance = "agent_4"; ep_port = "taskIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "sop"; ep_port = "sopOut"; ep_index = Some 4 };
                  to_ = { ep_instance = "agent_5"; ep_port = "taskIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "rules"; ep_port = "agentOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 1 } };
                { from_ = { ep_instance = "rules"; ep_port = "agentOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "agent_2"; ep_port = "taskIn"; ep_index = Some 1 } };
                { from_ = { ep_instance = "rules"; ep_port = "agentOut"; ep_index = Some 2 };
                  to_ = { ep_instance = "agent_3"; ep_port = "taskIn"; ep_index = Some 1 } };
                { from_ = { ep_instance = "rules"; ep_port = "agentOut"; ep_index = Some 3 };
                  to_ = { ep_instance = "agent_4"; ep_port = "taskIn"; ep_index = Some 1 } };
                { from_ = { ep_instance = "rules"; ep_port = "agentOut"; ep_index = Some 4 };
                  to_ = { ep_instance = "agent_5"; ep_port = "taskIn"; ep_index = Some 1 } };
                { from_ = { ep_instance = "rules"; ep_port = "skillOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "skills"; ep_port = "agentIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "rules"; ep_port = "powerOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "superpowers"; ep_port = "agentIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "job_manager"; ep_port = "jobOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 2 } };
                { from_ = { ep_instance = "job_manager"; ep_port = "jobOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "agent_2"; ep_port = "taskIn"; ep_index = Some 2 } };
                { from_ = { ep_instance = "job_manager"; ep_port = "jobOut"; ep_index = Some 2 };
                  to_ = { ep_instance = "agent_3"; ep_port = "taskIn"; ep_index = Some 2 } };
                { from_ = { ep_instance = "job_manager"; ep_port = "jobOut"; ep_index = Some 3 };
                  to_ = { ep_instance = "agent_4"; ep_port = "taskIn"; ep_index = Some 2 } };
                { from_ = { ep_instance = "job_manager"; ep_port = "jobOut"; ep_index = Some 4 };
                  to_ = { ep_instance = "agent_5"; ep_port = "taskIn"; ep_index = Some 2 } };
                { from_ = { ep_instance = "temporal"; ep_port = "wfOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 3 } };
                { from_ = { ep_instance = "temporal"; ep_port = "wfOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "agent_2"; ep_port = "taskIn"; ep_index = Some 3 } };
                { from_ = { ep_instance = "temporal"; ep_port = "wfOut"; ep_index = Some 2 };
                  to_ = { ep_instance = "agent_3"; ep_port = "taskIn"; ep_index = Some 3 } };
                { from_ = { ep_instance = "temporal"; ep_port = "wfOut"; ep_index = Some 3 };
                  to_ = { ep_instance = "agent_4"; ep_port = "taskIn"; ep_index = Some 3 } };
                { from_ = { ep_instance = "temporal"; ep_port = "wfOut"; ep_index = Some 4 };
                  to_ = { ep_instance = "agent_5"; ep_port = "taskIn"; ep_index = Some 3 } };
                { from_ = { ep_instance = "planning"; ep_port = "planOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "sop"; ep_port = "sopIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "temporal"; ep_port = "wfOut"; ep_index = Some 5 };
                  to_ = { ep_instance = "sop"; ep_port = "sopIn"; ep_index = Some 1 } };
                { from_ = { ep_instance = "skills"; ep_port = "skillOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 4 } };
                { from_ = { ep_instance = "superpowers"; ep_port = "powerOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 5 } };
                { from_ = { ep_instance = "hermes_zenoh"; ep_port = "gossipOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 6 } };
                { from_ = { ep_instance = "irmin"; ep_port = "memoryOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 7 } };
                { from_ = { ep_instance = "homeostasis"; ep_port = "resilienceOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 8 } };
                { from_ = { ep_instance = "eio"; ep_port = "eioOut"; ep_index = Some 0 };
                  to_ = { ep_instance = "agent_1"; ep_port = "taskIn"; ep_index = Some 9 } };
                { from_ = { ep_instance = "hermes_zenoh"; ep_port = "gossipOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "sop"; ep_port = "sopIn"; ep_index = Some 2 } };
                { from_ = { ep_instance = "irmin"; ep_port = "memoryOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "sop"; ep_port = "sopIn"; ep_index = Some 3 } };
                { from_ = { ep_instance = "homeostasis"; ep_port = "resilienceOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "sop"; ep_port = "sopIn"; ep_index = Some 4 } };
                { from_ = { ep_instance = "eio"; ep_port = "eioOut"; ep_index = Some 1 };
                  to_ = { ep_instance = "sop"; ep_port = "sopIn"; ep_index = Some 5 } } ] };
        Direct
          { graph_name = "gating";
            connections =
              [ { from_ = { ep_instance = "resource_envelope"; ep_port = "check"; ep_index = Some 0 };
                  to_ = { ep_instance = "parity_compare"; ep_port = "gate"; ep_index = Some 0 } };
                { from_ = { ep_instance = "resource_envelope"; ep_port = "check"; ep_index = Some 1 };
                  to_ = { ep_instance = "reference_capture"; ep_port = "resourceIn"; ep_index = Some 0 } };
                { from_ = { ep_instance = "harness_config"; ep_port = "run"; ep_index = Some 0 };
                  to_ = { ep_instance = "parity_compare"; ep_port = "gate"; ep_index = Some 1 } };
                { from_ = { ep_instance = "harness_config"; ep_port = "run"; ep_index = Some 1 };
                  to_ = { ep_instance = "reference_capture"; ep_port = "configIn"; ep_index = Some 0 } } ] };
        Direct
          { graph_name = "sweep";
            connections =
              [ { from_ = { ep_instance = "evidence_store"; ep_port = "rows"; ep_index = Some 0 };
                  to_ = { ep_instance = "control_plane"; ep_port = "history"; ep_index = Some 0 } };
                { from_ = { ep_instance = "evidence_store"; ep_port = "rows"; ep_index = Some 1 };
                  to_ = { ep_instance = "homeostasis"; ep_port = "window"; ep_index = Some 0 } };
                { from_ = { ep_instance = "blueprint"; ep_port = "plan"; ep_index = Some 0 };
                  to_ = { ep_instance = "homeostasis"; ep_port = "satisfied"; ep_index = Some 0 } };
                { from_ = { ep_instance = "homeostasis"; ep_port = "alert"; ep_index = Some 0 };
                  to_ = { ep_instance = "control_plane"; ep_port = "alerts"; ep_index = Some 0 } };
                { from_ = { ep_instance = "control_plane"; ep_port = "sweep"; ep_index = Some 0 };
                  to_ = { ep_instance = "hermes_zenoh"; ep_port = "publish"; ep_index = Some 0 } } ] };
        (* Framework plumbing: the standard F Prime patterns. *)
        Pattern
          { pattern = P_time; source = "inventory";
            targets =
              [ "capability_catalog"; "gospel_contracts"; "reference_capture"; "parity_normalizer";
                "evidence_store"; "parity_compare"; "harness_config"; "control_plane";
                "hermes_zenoh" ] };
        Pattern
          { pattern = P_health; source = "control_plane";
            targets = [ "capability_catalog"; "gospel_contracts"; "reference_capture"; "parity_normalizer"; "evidence_store"; "parity_compare"; "harness_config"; "hermes_zenoh" ] };
        Pattern
          { pattern = P_telemetry; source = "hermes_zenoh";
            targets = [ "capability_catalog"; "gospel_contracts"; "reference_capture"; "parity_normalizer"; "evidence_store"; "parity_compare"; "harness_config"; "control_plane" ] };
        Pattern
          { pattern = P_event; source = "fractal_diagnostic";
            targets =
              [ "capability_catalog"; "gospel_contracts"; "reference_capture"; "parity_normalizer"; "evidence_store"; "parity_compare"; "resource_envelope"; "blueprint";
                "harness_config"; "control_plane"; "hermes_zenoh" ] } ] }

let model =
  { model_name = Fpp_window_authority.declared_model_name Fpp_window_authority.Harness;
    type_defs;
    port_defs;
    constants = [ ("SWEEP_WINDOW", 10) ];
    components =
      [ inventory; capability_catalog; gospel_contracts; reference_capture; parity_normalizer; evidence_store; parity_compare; parity_algebra; resource_envelope;
        blueprint; harness_config; control_plane; homeostasis; hermes_zenoh; irmin; eio;
        fractal_diagnostic; sop; planning; job_manager; temporal; agents; skills; rules; superpowers ];
    machines = [ converge_loop ];
    instances;
    topologies = [ topology ] }

(* -------------------------------------------------------------- analysis *)

let validate () = Fpp_model.validate model

let direct_connections () =
  List.concat_map
    (function Direct { connections; _ } -> connections | Pattern _ -> [])
    topology.graphs

let ontology_ids =
  List.map (fun c -> c.Fractal_ontology.id) Fractal_ontology.components

let gaps_for_instances candidates =
  List.filter_map
    (fun i ->
      if List.mem i.of_component ontology_ids then None
      else
        Some
          (Printf.sprintf "instance %s: component %s is not in the fractal ontology"
             i.inst_name i.of_component))
    candidates

let edge_between a b =
  List.exists
    (fun e ->
      (e.Fractal_ontology.source = a && e.Fractal_ontology.target = b)
      || (e.Fractal_ontology.source = b && e.Fractal_ontology.target = a))
    Fractal_ontology.atlas

let component_of_instance name =
  match List.find_opt (fun i -> i.inst_name = name) instances with
  | Some i -> i.of_component
  | None -> name

let gaps_for_connections candidates =
  List.filter_map
    (fun c ->
      let a = component_of_instance c.from_.ep_instance in
      let b = component_of_instance c.to_.ep_instance in
      if edge_between a b then None
      else
        Some
          (Printf.sprintf "connection %s.%s -> %s.%s has no fractal-ontology edge"
             c.from_.ep_instance c.from_.ep_port c.to_.ep_instance c.to_.ep_port))
    candidates

let ontology_gaps () =
  gaps_for_instances instances @ gaps_for_connections (direct_connections ())

(* -------------------------------------------------------------- emitters *)

let to_fpp () = Fpp_model.to_fpp model

let dictionary () = Fpp_model.to_dictionary model ~topology:"hermes_harness"
