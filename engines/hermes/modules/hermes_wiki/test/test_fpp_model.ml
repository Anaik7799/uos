(* The FPP metamodel under test: unit laws for every semantic check the FPP
   spec mandates (passive/async law, uniqueness of opcodes and ids, base-id
   range disjointness, connection direction/type/index correctness, state
   machine initial/choice-acyclicity), property coverage over generated
   valid models, and meta-falsification: every injected defect class must be
   caught by the validator that claims to catch it. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let has_hazard hazard diagnostics =
  List.exists (fun (d : Fractal_diagnostic.t) -> d.Fractal_diagnostic.hazard = hazard) diagnostics

open Fpp_model

(* ------------------------------------------------------------ fixtures *)

let data_port = { port_name = "DataOut"; params = [ ("value", Prim U32) ]; return_type = None }
let time_port = { port_name = "Time"; params = [ ("t", Prim U64) ]; return_type = None }
let ping_port = { port_name = "Ping"; params = [ ("key", Prim U32) ]; return_type = None }

let mode_enum = Enum_t { name = "Mode"; repr = U8; constants = [ ("IDLE", 0); ("RUN", 1) ] }
let pair_struct = Struct_t { name = "Pair"; members = [ ("x", Prim U32); ("y", Prim U32) ] }
let vec_array = Array_t { name = "Vec3"; size = 3; element = Prim F32; format = Some "%f" }
let id_alias = Alias { name = "Id"; target = Prim U32 }
let handle_abstract = Abstract { name = "Handle" }

let loop_machine =
  Internal_machine
    { machine_name = "Loop";
      signals = [ { signal_name = "tick"; signal_type = None };
                  { signal_name = "load"; signal_type = Some (Prim U32) } ];
      guards = [ "ready" ];
      actions = [ "step" ];
      states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "tick"; guard = Some "ready"; do_actions = [ "step" ];
                  target = To_state "Busy" } ] };
          { state_name = "Busy"; entry = [ "step" ]; exit_ = [];
            transitions = [ { on_signal = "tick"; guard = None; do_actions = []; target = To_state "Idle" } ] } ];
      choices = [];
      initial = ([], "Idle") }

let no_limits = None

let sensor =
  { comp_name = "sensor"; kind = Passive;
    ports =
      [ General { name = "dataOut"; port = "DataOut"; direction = Output; count = 2 };
        Special Telemetry_p; Special Time_get ];
    commands = [];
    events = [ { event_name = "STARTED"; event_id = 0; severity = Activity_lo;
                 format = "started"; throttle = None } ];
    channels = [ { chan_name = "reading"; chan_id = 0; chan_type = Prim U32; update = Always;
                   chan_format = Some "%d"; low = no_limits; high = no_limits } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let controller =
  { comp_name = "controller"; kind = Active;
    ports =
      [ General { name = "dataIn"; port = "DataOut";
                  direction = Async_input { priority = Some 1; queue_full = Drop }; count = 1 };
        Special Command_recv; Special Command_reg; Special Command_resp;
        Special Event_p; Special Telemetry_p; Special Time_get ];
    commands =
      [ { cmd_name = "GO"; opcode = 0;
          cmd_kind = Async_cmd { priority = None; queue_full = Assert }; cmd_params = [] };
        { cmd_name = "HALT"; opcode = 1; cmd_kind = Sync_cmd; cmd_params = [ ("mode", Named "Mode") ] } ];
    events = [ { event_name = "MODE_CHANGED"; event_id = 2; severity = Activity_hi;
                 format = "mode %d"; throttle = Some 5 } ];
    channels = [ { chan_name = "mode"; chan_id = 3; chan_type = Named "Mode"; update = On_change;
                   chan_format = None; low = no_limits;
                   high = Some { yellow = Some 1.0; orange = None; red = Some 2.0 } } ];
    parameters = [ { param_name = "WINDOW"; param_id = 4; param_type = Prim U32;
                     default = Some "10"; set_opcode = 16; save_opcode = 17; external_ = false } ];
    records = [ { record_name = "sample"; record_id = 5; record_type = Prim U32; record_is_array = true } ];
    containers = [ { container_name = "batch"; container_id = 6; default_priority = Some 5 } ];
    internal_ports = []; machines = [ ("loop", "Loop") ]; matched = [] }

let hub =
  { comp_name = "hub"; kind = Queued;
    ports =
      [ General { name = "hubIn"; port = "DataOut";
                  direction = Async_input { priority = None; queue_full = Block }; count = 2 };
        General { name = "hubOut"; port = "DataOut"; direction = Output; count = 2 } ];
    commands = []; events = []; channels = []; parameters = [];
    records = []; containers = []; internal_ports = []; machines = [];
    matched = [ ("hubIn", "hubOut") ] }

let timesrc =
  { comp_name = "timesrc"; kind = Passive;
    ports = [ General { name = "timeGetIn"; port = "Time"; direction = Sync_input; count = 4 } ];
    commands = []; events = []; channels = []; parameters = [];
    records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let valid_instances =
  [ { inst_name = "clock"; of_component = "timesrc"; base_id = 0x50;
      queue_size = None; stack_size = None; inst_priority = None; cpu = None };
    { inst_name = "sensor1"; of_component = "sensor"; base_id = 0x100;
      queue_size = None; stack_size = None; inst_priority = None; cpu = None };
    { inst_name = "ctl"; of_component = "controller"; base_id = 0x200;
      queue_size = Some 10; stack_size = Some 4096; inst_priority = Some 5; cpu = Some 0 };
    { inst_name = "hub1"; of_component = "hub"; base_id = 0x300;
      queue_size = Some 4; stack_size = None; inst_priority = None; cpu = None } ]

let ep instance port index = { ep_instance = instance; ep_port = port; ep_index = index }

let valid_topology =
  { topo_name = "demo";
    members = [ "clock"; "sensor1"; "ctl"; "hub1" ];
    graphs =
      [ Direct { graph_name = "data";
                 connections =
                   [ { from_ = ep "sensor1" "dataOut" (Some 0); to_ = ep "ctl" "dataIn" (Some 0) };
                     { from_ = ep "sensor1" "dataOut" (Some 1); to_ = ep "hub1" "hubIn" (Some 0) };
                     { from_ = ep "hub1" "hubOut" (Some 0); to_ = ep "ctl" "dataIn" (Some 0) } ] };
        Pattern { pattern = P_time; source = "clock"; targets = [ "sensor1"; "ctl" ] } ] }

let valid_model =
  { model_name = "Demo";
    type_defs = [ mode_enum; pair_struct; vec_array; id_alias; handle_abstract ];
    port_defs = [ data_port; time_port; ping_port ];
    constants = [ ("QUEUE_DEPTH", 10) ];
    components = [ sensor; controller; hub; timesrc ];
    machines = [ loop_machine ];
    instances = valid_instances;
    topologies = [ valid_topology ] }

let with_components model components = { model with components }
let with_instances model instances = { model with instances }
let with_topologies model topologies = { model with topologies }

(* ---------------------------------------------------------------- unit *)

let () =
  check "valid model validates clean" (fun () -> validate valid_model = []);
  check "id_span of empty component is 1" (fun () -> id_span timesrc = 1);
  check "id_span covers the largest relative identifier (+1)"
    (fun () -> id_span controller = 18);
  check "id_span of sensor covers event and channel ids" (fun () -> id_span sensor = 1)

(* passive/async law *)
let () =
  let passive_async =
    { sensor with
      ports =
        General { name = "bad"; port = "DataOut";
                  direction = Async_input { priority = None; queue_full = Drop }; count = 1 }
        :: sensor.ports }
  in
  check "passive component with async port is rejected (FPP-CMP-01)" (fun () ->
      has_hazard "FPP-CMP-01" (validate (with_components valid_model [ passive_async; timesrc ])));
  let passive_machine = { sensor with machines = [ ("m", "Loop") ] } in
  check "passive component with state machine instance is rejected (FPP-CMP-01)" (fun () ->
      has_hazard "FPP-CMP-01" (validate (with_components valid_model [ passive_machine; timesrc ])));
  let passive_internal =
    { sensor with
      internal_ports = [ { internal_name = "note"; internal_params = [];
                           internal_priority = None; internal_queue_full = Drop } ] }
  in
  check "passive component with internal port is rejected (FPP-CMP-01)" (fun () ->
      has_hazard "FPP-CMP-01" (validate (with_components valid_model [ passive_internal; timesrc ])));
  let passive_async_cmd =
    { sensor with
      commands = [ { cmd_name = "X"; opcode = 9;
                     cmd_kind = Async_cmd { priority = None; queue_full = Assert };
                     cmd_params = [] } ] }
  in
  check "passive component with async command is rejected (FPP-CMP-01)" (fun () ->
      has_hazard "FPP-CMP-01" (validate (with_components valid_model [ passive_async_cmd; timesrc ])));
  let idle_queued = { hub with ports = []; matched = [] } in
  check "queued component with no async element is rejected (FPP-CMP-02)" (fun () ->
      has_hazard "FPP-CMP-02" (validate (with_components valid_model [ idle_queued; timesrc ])));
  check "state machine instance satisfies the async-element requirement" (fun () ->
      let machine_only =
        { hub with ports = []; matched = []; machines = [ ("loop", "Loop") ] }
      in
      not (has_hazard "FPP-CMP-02" (validate (with_components valid_model [ machine_only; timesrc ]))))

(* dictionary uniqueness laws *)
let () =
  let dup f = validate (with_components valid_model [ f; timesrc ]) in
  check "duplicate opcodes rejected (FPP-CMP-03)" (fun () ->
      has_hazard "FPP-CMP-03"
        (dup { controller with
               commands =
                 [ { cmd_name = "A"; opcode = 7; cmd_kind = Sync_cmd; cmd_params = [] };
                   { cmd_name = "B"; opcode = 7; cmd_kind = Sync_cmd; cmd_params = [] } ] }));
  check "duplicate command names rejected (FPP-CMP-03)" (fun () ->
      has_hazard "FPP-CMP-03"
        (dup { controller with
               commands =
                 [ { cmd_name = "A"; opcode = 7; cmd_kind = Sync_cmd; cmd_params = [] };
                   { cmd_name = "A"; opcode = 8; cmd_kind = Sync_cmd; cmd_params = [] } ] }));
  check "duplicate event ids rejected (FPP-CMP-04)" (fun () ->
      has_hazard "FPP-CMP-04"
        (dup { controller with
               events =
                 [ { event_name = "E1"; event_id = 2; severity = Diagnostic; format = "x"; throttle = None };
                   { event_name = "E2"; event_id = 2; severity = Fatal; format = "y"; throttle = None } ] }));
  check "duplicate channel ids rejected (FPP-CMP-05)" (fun () ->
      has_hazard "FPP-CMP-05"
        (dup { controller with
               channels =
                 [ { chan_name = "c1"; chan_id = 3; chan_type = Prim U8; update = Always;
                     chan_format = None; low = None; high = None };
                   { chan_name = "c2"; chan_id = 3; chan_type = Prim U8; update = Always;
                     chan_format = None; low = None; high = None } ] }));
  check "duplicate parameter ids rejected (FPP-CMP-06)" (fun () ->
      has_hazard "FPP-CMP-06"
        (dup { controller with
               parameters =
                 [ { param_name = "P1"; param_id = 4; param_type = Prim U32; default = None;
                     set_opcode = 20; save_opcode = 21; external_ = false };
                   { param_name = "P2"; param_id = 4; param_type = Prim U32; default = None;
                     set_opcode = 22; save_opcode = 23; external_ = false } ] }));
  check "parameter set/save opcodes must not collide with command opcodes (FPP-CMP-06)"
    (fun () ->
      has_hazard "FPP-CMP-06"
        (dup { controller with
               parameters =
                 [ { param_name = "P1"; param_id = 4; param_type = Prim U32; default = None;
                     set_opcode = 0 (* collides with GO *); save_opcode = 21; external_ = false } ] }));
  check "duplicate record/container ids rejected (FPP-CMP-07)" (fun () ->
      has_hazard "FPP-CMP-07"
        (dup { controller with
               containers = [ { container_name = "batch"; container_id = 5 (* = record id *);
                                default_priority = None } ] }));
  check "a record without a container is rejected (FPP-CMP-08)" (fun () ->
      has_hazard "FPP-CMP-08" (dup { controller with containers = [] }));
  check "a container without a record is rejected (FPP-CMP-08)" (fun () ->
      has_hazard "FPP-CMP-08" (dup { controller with records = [] }));
  check "two special ports of one kind rejected (FPP-CMP-09)" (fun () ->
      has_hazard "FPP-CMP-09" (dup { controller with ports = Special Telemetry_p :: controller.ports }));
  check "machine instance naming an unknown machine rejected (FPP-CMP-10)" (fun () ->
      has_hazard "FPP-CMP-10" (dup { controller with machines = [ ("loop", "NoSuchMachine") ] }));
  check "duplicate machine instance names rejected (FPP-CMP-10)" (fun () ->
      has_hazard "FPP-CMP-10"
        (dup { controller with machines = [ ("loop", "Loop"); ("loop", "Loop") ] }))

(* state machine laws *)
let () =
  let with_machine m = validate { valid_model with machines = [ m ] } in
  let default_states =
    [ { state_name = "Idle"; entry = []; exit_ = [];
        transitions =
          [ { on_signal = "tick"; guard = Some "ready"; do_actions = [ "step" ];
              target = To_state "Busy" } ] };
      { state_name = "Busy"; entry = [ "step" ]; exit_ = [];
        transitions = [ { on_signal = "tick"; guard = None; do_actions = []; target = To_state "Idle" } ] } ]
  in
  let make ?(states = default_states) ?(choices = []) ?(initial = ([], "Idle")) () =
    Internal_machine
      { machine_name = "Loop";
        signals = [ { signal_name = "tick"; signal_type = None } ];
        guards = [ "ready" ]; actions = [ "step" ];
        states; choices; initial }
  in
  check "initial transition must target a defined state (FPP-SM-01)" (fun () ->
      has_hazard "FPP-SM-01" (with_machine (make ~initial:([], "Nowhere") ())));
  check "transition to an unknown state rejected (FPP-SM-02)" (fun () ->
      let states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "tick"; guard = None; do_actions = []; target = To_state "Ghost" } ] } ]
      in
      has_hazard "FPP-SM-02" (with_machine (make ~states ())));
  check "transition on an unknown signal rejected (FPP-SM-02)" (fun () ->
      let states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "boom"; guard = None; do_actions = []; target = To_state "Idle" } ] } ]
      in
      has_hazard "FPP-SM-02" (with_machine (make ~states ())));
  check "transition with an unknown guard rejected (FPP-SM-02)" (fun () ->
      let states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "tick"; guard = Some "ghost"; do_actions = []; target = To_state "Idle" } ] } ]
      in
      has_hazard "FPP-SM-02" (with_machine (make ~states ())));
  check "transition doing an unknown action rejected (FPP-SM-02)" (fun () ->
      let states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "tick"; guard = None; do_actions = [ "ghost" ]; target = To_state "Idle" } ] } ]
      in
      has_hazard "FPP-SM-02" (with_machine (make ~states ())));
  check "a cycle in the choice graph is rejected (FPP-SM-03)" (fun () ->
      let choices =
        [ { choice_name = "c1"; choice_guard = "ready";
            if_true = ([], To_choice "c2"); if_false = ([], To_state "Idle") };
          { choice_name = "c2"; choice_guard = "ready";
            if_true = ([], To_choice "c1"); if_false = ([], To_state "Idle") } ]
      in
      has_hazard "FPP-SM-03" (with_machine (make ~choices ())));
  check "an acyclic choice chain is accepted" (fun () ->
      let choices =
        [ { choice_name = "c1"; choice_guard = "ready";
            if_true = ([], To_choice "c2"); if_false = ([], To_state "Idle") };
          { choice_name = "c2"; choice_guard = "ready";
            if_true = ([ "step" ], To_state "Busy"); if_false = ([], To_state "Idle") } ]
      in
      validate { valid_model with machines = [ make ~choices () ] } = []);
  check "an external machine needs no body" (fun () ->
      let m = External_machine { machine_name = "Loop" } in
      validate { valid_model with machines = [ m ] } = [])

(* instances *)
let () =
  check "passive instance with a queue size rejected (FPP-INST-01)" (fun () ->
      let bad =
        List.map
          (fun i -> if i.inst_name = "sensor1" then { i with queue_size = Some 3 } else i)
          valid_instances
      in
      has_hazard "FPP-INST-01" (validate (with_instances valid_model bad)));
  check "queued instance without a queue size rejected (FPP-INST-01)" (fun () ->
      let bad =
        List.map
          (fun i -> if i.inst_name = "hub1" then { i with queue_size = None } else i)
          valid_instances
      in
      has_hazard "FPP-INST-01" (validate (with_instances valid_model bad)));
  check "stack size on a non-active instance rejected (FPP-INST-01)" (fun () ->
      let bad =
        List.map
          (fun i -> if i.inst_name = "hub1" then { i with stack_size = Some 1024 } else i)
          valid_instances
      in
      has_hazard "FPP-INST-01" (validate (with_instances valid_model bad)));
  check "an instance of an unknown component rejected (FPP-INST-01)" (fun () ->
      let bad =
        { inst_name = "ghost"; of_component = "nope"; base_id = 0x900;
          queue_size = None; stack_size = None; inst_priority = None; cpu = None }
      in
      has_hazard "FPP-INST-01" (validate (with_instances valid_model (bad :: valid_instances))));
  check "overlapping base-id ranges rejected (FPP-INST-02)" (fun () ->
      let bad =
        List.map
          (fun i -> if i.inst_name = "sensor1" then { i with base_id = 0x200 + 4 } else i)
          valid_instances
      in
      has_hazard "FPP-INST-02" (validate (with_instances valid_model bad)));
  check "adjacent (touching, non-overlapping) ranges are legal" (fun () ->
      (* controller span is 18: [0x200, 0x212). A base at 0x212 touches, no overlap. *)
      let ok =
        List.map
          (fun i -> if i.inst_name = "hub1" then { i with base_id = 0x212 } else i)
          valid_instances
      in
      not (has_hazard "FPP-INST-02" (validate (with_instances valid_model ok))));
  check "duplicate instance names rejected (FPP-INST-03)" (fun () ->
      let dup =
        { inst_name = "sensor1"; of_component = "sensor"; base_id = 0x900;
          queue_size = None; stack_size = None; inst_priority = None; cpu = None }
      in
      has_hazard "FPP-INST-03" (validate (with_instances valid_model (dup :: valid_instances))))

(* topology *)
let () =
  let retopo graphs = with_topologies valid_model [ { valid_topology with graphs } ] in
  check "a member that is not an instance is rejected (FPP-TOPO-01)" (fun () ->
      has_hazard "FPP-TOPO-01"
        (validate
           (with_topologies valid_model [ { valid_topology with members = "ghost" :: valid_topology.members } ])));
  check "an endpoint naming an unknown port is rejected (FPP-TOPO-01)" (fun () ->
      has_hazard "FPP-TOPO-01"
        (validate
           (retopo
              [ Direct { graph_name = "g";
                         connections = [ { from_ = ep "sensor1" "nope" None; to_ = ep "ctl" "dataIn" None } ] } ])));
  check "an endpoint on a non-member instance is rejected (FPP-TOPO-01)" (fun () ->
      has_hazard "FPP-TOPO-01"
        (validate
           (with_topologies valid_model
              [ { valid_topology with
                  members = [ "sensor1"; "ctl" ];
                  graphs =
                    [ Direct { graph_name = "g";
                               connections =
                                 [ { from_ = ep "hub1" "hubOut" None; to_ = ep "ctl" "dataIn" None } ] } ] } ])));
  check "input-to-input connection rejected (FPP-TOPO-02)" (fun () ->
      has_hazard "FPP-TOPO-02"
        (validate
           (retopo
              [ Direct { graph_name = "g";
                         connections = [ { from_ = ep "ctl" "dataIn" None; to_ = ep "hub1" "hubIn" None } ] } ])));
  check "port-type mismatch rejected (FPP-TOPO-03)" (fun () ->
      has_hazard "FPP-TOPO-03"
        (validate
           (retopo
              [ Direct { graph_name = "g";
                         connections = [ { from_ = ep "sensor1" "dataOut" None; to_ = ep "clock" "timeGetIn" None } ] } ])));
  check "port index beyond the array rejected (FPP-TOPO-04)" (fun () ->
      has_hazard "FPP-TOPO-04"
        (validate
           (retopo
              [ Direct { graph_name = "g";
                         connections = [ { from_ = ep "sensor1" "dataOut" (Some 5); to_ = ep "ctl" "dataIn" (Some 0) } ] } ])));
  check "an output index driving two connections rejected (FPP-TOPO-04)" (fun () ->
      has_hazard "FPP-TOPO-04"
        (validate
           (retopo
              [ Direct { graph_name = "g";
                         connections =
                           [ { from_ = ep "sensor1" "dataOut" (Some 0); to_ = ep "ctl" "dataIn" (Some 0) };
                             { from_ = ep "sensor1" "dataOut" (Some 0); to_ = ep "hub1" "hubIn" (Some 0) } ] } ])));
  check "fan-in to one input index is legal" (fun () -> validate valid_model = []);
  check "matched ports with unequal index sets rejected (FPP-TOPO-06)" (fun () ->
      (* hub1.hubIn gets index 0 and 1, hubOut only 0: the match law breaks. *)
      has_hazard "FPP-TOPO-06"
        (validate
           (retopo
              [ Direct { graph_name = "g";
                         connections =
                           [ { from_ = ep "sensor1" "dataOut" (Some 0); to_ = ep "hub1" "hubIn" (Some 0) };
                             { from_ = ep "sensor1" "dataOut" (Some 1); to_ = ep "hub1" "hubIn" (Some 1) };
                             { from_ = ep "hub1" "hubOut" (Some 0); to_ = ep "ctl" "dataIn" (Some 0) } ] } ])));
  check "a pattern with an unknown source rejected (FPP-TOPO-05)" (fun () ->
      has_hazard "FPP-TOPO-05"
        (validate (retopo [ Pattern { pattern = P_time; source = "ghost"; targets = [ "ctl" ] } ])))

(* types *)
let () =
  check "an unresolved named type is rejected (FPP-TYPE-01)" (fun () ->
      let bad = { sensor with channels = [ { chan_name = "c"; chan_id = 0; chan_type = Named "Ghost";
                                             update = Always; chan_format = None; low = None; high = None } ] } in
      has_hazard "FPP-TYPE-01" (validate (with_components valid_model [ bad; timesrc ])));
  check "an alias cycle is rejected (FPP-TYPE-02)" (fun () ->
      let a = Alias { name = "A"; target = Named "B" } in
      let b = Alias { name = "B"; target = Named "A" } in
      has_hazard "FPP-TYPE-02" (validate { valid_model with type_defs = [ a; b ] }));
  check "empty names are rejected (FPP-NAME-01)" (fun () ->
      has_hazard "FPP-NAME-01"
        (validate (with_components valid_model [ { sensor with comp_name = "" }; timesrc ])))

(* --------------------------------------------------------- pattern expansion *)

let () =
  check "time pattern expands to one connection per consuming target" (fun () ->
      match connections valid_model valid_topology with
      | Error e -> print_endline e; false
      | Ok all ->
          let time_links =
            List.filter (fun c -> c.to_.ep_instance = "clock" && c.to_.ep_port = "timeGetIn") all
          in
          List.length time_links = 2);
  check "pattern expansion skips targets without the consuming port" (fun () ->
      let topo =
        { valid_topology with
          graphs = [ Pattern { pattern = P_time; source = "clock"; targets = [ "hub1" ] } ] }
      in
      match connections valid_model topo with
      | Error _ -> false
      | Ok all -> not (List.exists (fun c -> c.from_.ep_instance = "hub1") all));
  check "direct connections survive expansion verbatim" (fun () ->
      match connections valid_model valid_topology with
      | Error _ -> false
      | Ok all ->
          List.exists
            (fun c -> c.from_.ep_instance = "sensor1" && c.to_.ep_instance = "ctl")
            all)

(* ---------------------------------------------------------------- emitters *)

let () =
  check "to_fpp renders every component kind keyword" (fun () ->
      let text = to_fpp valid_model in
      let contains needle =
        let n = String.length needle and h = String.length text in
        let rec go i = i + n <= h && (String.sub text i n = needle || go (i + 1)) in
        go 0
      in
      contains "passive component sensor" && contains "active component controller"
      && contains "queued component hub" && contains "topology demo"
      && contains "state machine Loop" && contains "telemetry"
      && contains "async command GO" && contains "param WINDOW");
  check "to_fpp is deterministic" (fun () -> to_fpp valid_model = to_fpp valid_model);
  check "dictionary emits all specified top-level keys" (fun () ->
      match to_dictionary valid_model ~topology:"demo" with
      | Error e -> print_endline e; false
      | Ok json -> (
          match json with
          | `Assoc fields ->
              List.for_all
                (fun k -> List.mem_assoc k fields)
                [ "metadata"; "typeDefinitions"; "constants"; "commands"; "events";
                  "telemetryChannels"; "parameters"; "records"; "containers";
                  "telemetryPacketSets" ]
          | _ -> false));
  check "dictionary command opcodes are base-id offset" (fun () ->
      match to_dictionary valid_model ~topology:"demo" with
      | Error _ -> false
      | Ok (`Assoc fields) -> (
          match List.assoc "commands" fields with
          | `List commands ->
              List.exists
                (fun c ->
                  match c with
                  | `Assoc f ->
                      List.assoc_opt "name" f = Some (`String "ctl.GO")
                      && List.assoc_opt "opcode" f = Some (`Int 0x200)
                  | _ -> false)
                commands
          | _ -> false)
      | Ok _ -> false);
  check "dictionary refuses an unknown topology" (fun () ->
      match to_dictionary valid_model ~topology:"ghost" with Error _ -> true | Ok _ -> false);
  check "dictionary refuses an invalid model (fail-closed)" (fun () ->
      let bad = with_components valid_model [ { sensor with comp_name = "" }; timesrc ] in
      match to_dictionary bad ~topology:"demo" with Error _ -> true | Ok _ -> false);
  check "dictionary is deterministic" (fun () ->
      to_dictionary valid_model ~topology:"demo" = to_dictionary valid_model ~topology:"demo")

(* ------------------------------------------------- property + meta-falsification *)

let () =
  Random.self_init ();
  let seed = Random.int 1_000_000 in
  Random.init seed;
  Printf.printf "property seed: %d\n" seed;
  (* Generator: assemble a valid model from healthy parts with randomized
     sizes/ids, then confirm the validator accepts every one. *)
  let random_component index =
    let name = Printf.sprintf "comp%d" index in
    let n_cmds = Random.int 4 in
    let commands =
      List.init n_cmds (fun i ->
          { cmd_name = Printf.sprintf "CMD%d" i; opcode = i;
            cmd_kind = (if Random.bool () then Sync_cmd else Guarded_cmd); cmd_params = [] })
    in
    let events =
      List.init (Random.int 3) (fun i ->
          { event_name = Printf.sprintf "EV%d" i; event_id = 100 + i; severity = Diagnostic;
            format = "e"; throttle = None })
    in
    let channels =
      List.init (Random.int 3) (fun i ->
          { chan_name = Printf.sprintf "CH%d" i; chan_id = 200 + i; chan_type = Prim U32;
            update = Always; chan_format = None; low = None; high = None })
    in
    { comp_name = name; kind = Passive;
      ports = [ General { name = "out"; port = "DataOut"; direction = Output; count = 1 } ];
      commands; events; channels; parameters = []; records = []; containers = [];
      internal_ports = []; machines = []; matched = [] }
  in
  let generate () =
    let n = 1 + Random.int 5 in
    let components = List.init n random_component in
    let instances =
      List.mapi
        (fun i (c : component) ->
          { inst_name = Printf.sprintf "i%d" i; of_component = c.comp_name;
            base_id = 0x1000 * (i + 1); queue_size = None; stack_size = None;
            inst_priority = None; cpu = None })
        components
    in
    { model_name = "Gen";
      type_defs = []; port_defs = [ data_port ]; constants = [];
      components; machines = []; instances;
      topologies =
        [ { topo_name = "t"; members = List.map (fun i -> i.inst_name) instances; graphs = [] } ] }
  in
  let clean = ref 0 in
  for _ = 1 to 200 do
    if validate (generate ()) = [] then incr clean
  done;
  check "200 generated valid models validate clean" (fun () -> !clean = 200);
  (* Meta-falsification: every injected defect class must be detected, and by
     its OWN check. A validator that cannot see its target defect is theatre. *)
  let inject model kind =
    match kind, model.components, model.instances with
    | 0, c :: rest, _ ->
        (* duplicate opcode *)
        let c' =
          { c with
            commands =
              [ { cmd_name = "D1"; opcode = 42; cmd_kind = Sync_cmd; cmd_params = [] };
                { cmd_name = "D2"; opcode = 42; cmd_kind = Sync_cmd; cmd_params = [] } ] }
        in
        ({ model with components = c' :: rest }, "FPP-CMP-03")
    | 1, c :: rest, _ ->
        (* async port inside a passive component *)
        let c' =
          { c with
            ports =
              General { name = "bad"; port = "DataOut";
                        direction = Async_input { priority = None; queue_full = Drop }; count = 1 }
              :: c.ports }
        in
        ({ model with components = c' :: rest }, "FPP-CMP-01")
    | 2, _, i :: rest ->
        (* base-id collision *)
        let clone = { i with inst_name = i.inst_name ^ "_dup" } in
        ({ model with instances = clone :: i :: rest }, "FPP-INST-02")
    | _, _, i :: _ ->
        (* dangling endpoint *)
        let graphs =
          [ Direct { graph_name = "bad";
                     connections =
                       [ { from_ = ep i.inst_name "out" None; to_ = ep "ghost" "in" None } ] } ]
        in
        ({ model with
           topologies = [ { topo_name = "t"; members = List.map (fun x -> x.inst_name) model.instances; graphs } ] },
         "FPP-TOPO-01")
    | _ -> (model, "unreachable")
  in
  let caught = ref 0 and total = 100 in
  for _ = 1 to total do
    let model = generate () in
    let kind = Random.int 4 in
    let mutated, expected = inject model kind in
    if has_hazard expected (validate mutated) then incr caught
  done;
  check "every injected defect is caught by its own check (100 mutations)"
    (fun () -> !caught = total)

(* ----------------------------------------------------------------- chaos *)

let () =
  check "near-max_int base ids do not overflow the span arithmetic" (fun () ->
      let inst =
        { inst_name = "edge"; of_component = "timesrc"; base_id = max_int - 1;
          queue_size = None; stack_size = None; inst_priority = None; cpu = None }
      in
      let model = with_instances valid_model (inst :: valid_instances) in
      (* Must terminate and not report a spurious overlap against small ids. *)
      not (has_hazard "FPP-INST-02" (validate model)));
  check "validation of a large model terminates quickly" (fun () ->
      let components = List.init 60 (fun i ->
          { timesrc with comp_name = Printf.sprintf "bulk%d" i }) in
      let instances =
        List.mapi
          (fun i (c : component) ->
            { inst_name = Printf.sprintf "b%d" i; of_component = c.comp_name;
              base_id = 0x10000 + (i * 16); queue_size = None; stack_size = None;
              inst_priority = None; cpu = None })
          components
      in
      let model =
        { valid_model with
          components = valid_model.components @ components;
          instances = valid_instances @ instances }
      in
      let t0 = Unix.gettimeofday () in
      let ok = validate model = [] in
      ok && Unix.gettimeofday () -. t0 < 2.0)

let () =
  Printf.printf "fpp_model: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_fpp_model" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
