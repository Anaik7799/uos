(* The operations layer AS an FPP topology — the directive is that every
   capability is a modelled component before it is a command, and an ops
   tool is no exception.

   Base-id window 0x2000+, disjoint from the wiki topology's 0x1000+ and
   the harness topology's 0x100..0xB00: three topologies of three systems
   (R9), and a shared id would make two components indistinguishable in
   one telemetry stream. *)

open Fpp_model

let chan ?(update = Always) name id =
  { chan_name = name; chan_id = id; chan_type = Prim U32; update;
    chan_format = None; low = None; high = None }

let warn name id fmt =
  { event_name = name; event_id = id; severity = Warning_hi; format = fmt; throttle = None }

let ping_pair =
  [ General { name = "pingIn"; port = "Ping"; direction = Sync_input; count = 1 };
    General { name = "pingOut"; port = "Ping"; direction = Output; count = 1 } ]

let governance_channels =
  Ops_governance.obligations
  |> List.mapi (fun index (item : Ops_governance.obligation) ->
         chan item.metric (100 + index) ~update:On_change)

(* The verifier: senses the suites and reports. It is a MONITOR — it runs
   binaries and reads their exit codes, and writes nothing anywhere. *)
let verifier =
  { comp_name = "opsVerifier"; kind = Queued;
    ports = [ General { name = "verify"; port = "Audit";
                        direction = Async_input { priority = Some 2; queue_full = Block };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands = [];
    events =
      [ warn "SUITE_FAILED" 0 "suite failed: %s";
        (* R2: a suite that could not be run is DISCLOSED, never counted
           as one that passed — the event exists so a skip is loud. *)
        warn "SUITE_SKIPPED" 1 "suite could not be run: %s" ];
    channels =
      [ chan "suites_passed" 0 ~update:On_change;
        chan "suites_failed" 1 ~update:On_change;
        chan "suites_skipped" 2 ~update:On_change;
        (* the offload's own measurement: bytes that did NOT have to enter
           an agent's context. Measured, unlike tokens, which nothing here
           can observe and which are therefore never reported. *)
        chan "bytes_offloaded" 3;
        chan "fast_suites_discovered" 4 ~update:On_change;
        chan "full_suites_discovered" 5 ~update:On_change;
        chan "control_suites_admitted" 6 ~update:On_change;
        chan "control_suites_terminal" 7 ~update:On_change;
        chan "control_parallelism_limit" 8 ~update:On_change;
        chan "control_suites_timeout" 9 ~update:On_change;
        chan "control_process_spawn_failures" 10 ~update:On_change;
        chan "control_wall_ms" 11;
        chan "data_bytes_captured" 12;
        chan "data_residual_groups_terminated" 13 ~update:On_change;
        chan "data_children_reaped" 14 ~update:On_change;
        chan "data_summaries_missing" 15 ~update:On_change;
        chan "data_case_max_duration_ms" 16 ]
      @ governance_channels;
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

let instances =
  [ { inst_name = "opsVerifier"; of_component = "opsVerifier";
      base_id = Fpp_window_authority.base_of_instance Fpp_window_authority.Ops_monitor "opsVerifier";
      queue_size = Some 16; stack_size = None; inst_priority = None; cpu = None } ]

let topology =
  { topo_name = "HermesOps";
    members = List.map (fun i -> i.inst_name) instances;
    graphs = [] }

let model =
  { model_name = Fpp_window_authority.declared_model_name Fpp_window_authority.Ops_monitor;
    type_defs = [];
    port_defs =
      [ { port_name = "Ping"; params = []; return_type = None };
        { port_name = "Audit"; params = []; return_type = None };
        { port_name = "Counts"; params = []; return_type = None } ];
    constants = [];
    components = [ verifier ];
    machines = [];
    instances;
    topologies = [ topology ] }
