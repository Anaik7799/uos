(* The executable completion control/data plane as an FPP topology.

   Ops_topology remains the R22 read-only monitor. Keeping this topology
   separate prevents a command receiver from being smuggled into the monitor
   while still modelling every typed command, audit, receipt, MBSE and formal
   evidence edge requested by the completion plane. Base ids use 0x3000+ and
   are disjoint from wiki (0x1000+), ops monitor (0x2000) and the harness. *)

open Fpp_model

let chan ?(update = Always) name id =
  { chan_name = name; chan_id = id; chan_type = Prim U32; update;
    chan_format = None; low = None; high = None }

let warn name id fmt =
  { event_name = name; event_id = id; severity = Warning_hi; format = fmt; throttle = None }

let ping_pair =
  [ General { name = "pingIn"; port = "Ping"; direction = Sync_input; count = 1 };
    General { name = "pingOut"; port = "Ping"; direction = Output; count = 1 } ]

let command_gateway =
  { comp_name = "commandGateway"; kind = Queued;
    ports =
      [ General { name = "intentIn"; port = "Intent";
                  direction = Async_input { priority = Some 1; queue_full = Block };
                  count = 4 };
        General { name = "auditOut"; port = "Audit"; direction = Output; count = 2 };
        General { name = "receiptOut"; port = "Receipt"; direction = Output; count = 1 };
        Special Command_recv; Special Command_reg; Special Command_resp;
        Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands =
      [ { cmd_name = "DISPATCH"; opcode = 0;
          cmd_kind = Async_cmd { priority = Some 1; queue_full = Block };
          cmd_params = [ ("surface", Prim U8); ("action", Prim (String (Some 128))) ] } ];
    events = [ warn "COMMAND_BLOCKED" 1 "command blocked: %s" ];
    channels =
      [ chan "commands_accepted" 0 ~update:On_change;
        chan "commands_blocked" 1 ~update:On_change;
        chan "command_duration_ns" 2 ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let completion_history =
  { comp_name = "completionHistory"; kind = Passive;
    ports =
      [ General { name = "record"; port = "Receipt"; direction = Sync_input; count = 1 };
        General { name = "query"; port = "Audit"; direction = Sync_input; count = 1 };
        General { name = "snapshot"; port = "Counts"; direction = Output; count = 1 };
        Special Event_p; Special Telemetry_p ];
    commands = [];
    events = [ warn "IMMUTABLE_REPLAY_REJECTED" 0 "receipt replay rejected: %s" ];
    channels =
      [ chan "receipts_recorded" 0 ~update:On_change;
        chan "surface_observations_recorded" 1 ~update:On_change;
        chan "interaction_records" 2 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let mbse_projector =
  { comp_name = "mbseProjector"; kind = Passive;
    ports =
      [ General { name = "project"; port = "Audit"; direction = Sync_input; count = 1 };
        General { name = "evidence"; port = "Evidence"; direction = Output; count = 1 };
        Special Event_p; Special Telemetry_p ];
    commands = []; events = [ warn "MBSE_GAP" 0 "MBSE projection gap: %s" ];
    channels =
      [ chan "sysml_elements" 0 ~update:On_change;
        chan "oml_elements" 1 ~update:On_change;
        chan "openmbee_elements" 2 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let formal_oracle =
  { comp_name = "formalOracle"; kind = Queued;
    ports =
      [ General { name = "verify"; port = "Evidence";
                  direction = Async_input { priority = Some 2; queue_full = Block };
                  count = 1 };
        Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = []; events = [ warn "FORMAL_REFUTATION" 0 "formal refutation: %s" ];
    channels =
      [ chan "formal_discharged" 0 ~update:On_change;
        chan "formal_refuted" 1 ~update:On_change;
        chan "formal_unavailable" 2 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let instances =
  [ { inst_name = "commandGateway"; of_component = "commandGateway";
      base_id = Fpp_window_authority.base_of_instance Fpp_window_authority.Completion "commandGateway";
      queue_size = Some 32; stack_size = None; inst_priority = None; cpu = None };
    { inst_name = "completionHistory"; of_component = "completionHistory";
      base_id = Fpp_window_authority.base_of_instance Fpp_window_authority.Completion "completionHistory";
      queue_size = None; stack_size = None; inst_priority = None; cpu = None };
    { inst_name = "mbseProjector"; of_component = "mbseProjector";
      base_id = Fpp_window_authority.base_of_instance Fpp_window_authority.Completion "mbseProjector";
      queue_size = None; stack_size = None; inst_priority = None; cpu = None };
    { inst_name = "formalOracle"; of_component = "formalOracle";
      base_id = Fpp_window_authority.base_of_instance Fpp_window_authority.Completion "formalOracle";
      queue_size = Some 8; stack_size = None; inst_priority = None; cpu = None } ]

let endpoint ep_instance ep_port ep_index = { ep_instance; ep_port; ep_index }

let command_flow =
  Direct
    { graph_name = "CommandEvidenceFlow";
      connections =
        [ { from_ = endpoint "commandGateway" "receiptOut" None;
            to_ = endpoint "completionHistory" "record" None };
          { from_ = endpoint "commandGateway" "auditOut" (Some 0);
            to_ = endpoint "completionHistory" "query" None };
          { from_ = endpoint "commandGateway" "auditOut" (Some 1);
            to_ = endpoint "mbseProjector" "project" None };
          { from_ = endpoint "mbseProjector" "evidence" None;
            to_ = endpoint "formalOracle" "verify" None } ] }

let topology =
  { topo_name = "HermesCompletion";
    members = List.map (fun i -> i.inst_name) instances;
    graphs = [ command_flow ] }

let model =
  { model_name = Fpp_window_authority.declared_model_name Fpp_window_authority.Completion;
    type_defs = [];
    port_defs =
      [ { port_name = "Ping"; params = []; return_type = None };
        { port_name = "Audit"; params = []; return_type = None };
        { port_name = "Counts"; params = []; return_type = None };
        { port_name = "Intent"; params = []; return_type = None };
        { port_name = "Receipt"; params = []; return_type = None };
        { port_name = "Evidence"; params = []; return_type = None } ];
    constants = [];
    components = [ command_gateway; completion_history; mbse_projector; formal_oracle ];
    machines = [];
    instances;
    topologies = [ topology ] }
