(* The vision system as an FPP model, projected from the ontologies.
   See the .mli. *)

let instance_base = 0x4000

let chan ?(update = Fpp_model.On_change) name id =
  { Fpp_model.chan_name = name; chan_id = id; chan_type = Fpp_model.Prim Fpp_model.U32;
    update; chan_format = None; low = None; high = None }

let stage_channel_name s =
  "vision_" ^ String.lowercase_ascii (Vision_ontology.stage_name s) ^ "_verdict"

(* One channel per stage, derived — a stage added without a channel is a
   stage whose verdict nothing can receive. *)
let stage_channels =
  List.mapi (fun i s -> chan (stage_channel_name s) i) Vision_ontology.stages
  @ [ chan "vision_stages_live" 100;
      chan "vision_stages_unknown" 101;
      chan "vision_coverage_end_to_end" 102;
      chan "vision_telemetry_published" 103;
      (* the number an operator needs to know the mesh view is partial *)
      chan "vision_telemetry_unpublished" 104 ]

(* One warning per hazard, so a hazard that fires is announced rather
   than merely counted. *)
let hazard_events =
  List.mapi
    (fun i s ->
      { Fpp_model.event_name =
          "VISION_" ^ String.uppercase_ascii (Vision_ontology.stage_name s) ^ "_HAZARD";
        event_id = i;
        severity = Fpp_model.Warning_hi;
        format = Vision_ontology.hazard s ^ ": %s";
        throttle = None })
    Vision_ontology.stages

(* Projected from Vision_restart.legal_transition rather than written
   beside it. *)
let restart_phases =
  [ Vision_restart.Draining; Vision_restart.Starting; Vision_restart.Gating;
    Vision_restart.Promoted; Vision_restart.Rolled_back "" ]

let signal_for p = "TO_" ^ String.uppercase_ascii (Vision_restart.phase_name p)

let restart_machine =
  let states =
    List.map
      (fun from_p ->
        { Fpp_model.state_name = Vision_restart.phase_name from_p;
          entry = []; exit_ = [];
          transitions =
            List.filter_map
              (fun to_p ->
                if Vision_restart.legal_transition from_p to_p then
                  Some
                    { Fpp_model.on_signal = signal_for to_p; guard = None;
                      do_actions = [ "recordPhase" ];
                      target = Fpp_model.To_state (Vision_restart.phase_name to_p) }
                else None)
              restart_phases })
      restart_phases
  in
  Fpp_model.Internal_machine
    { machine_name = "VisionRestart";
      signals =
        List.map (fun p -> { Fpp_model.signal_name = signal_for p; signal_type = None })
          restart_phases;
      guards = []; actions = [ "recordPhase" ]; states; choices = [];
      initial = ([], Vision_restart.phase_name Vision_restart.Draining) }

let machine_agrees () =
  match restart_machine with
  | Fpp_model.External_machine _ -> false
  | Fpp_model.Internal_machine m ->
      let declared = List.map (fun (s : Fpp_model.state) -> s.state_name) m.states in
      let expected = List.map Vision_restart.phase_name restart_phases in
      List.sort compare declared = List.sort compare expected
      && List.for_all
           (fun from_p ->
             let modelled =
               match
                 List.find_opt
                   (fun (s : Fpp_model.state) ->
                     s.state_name = Vision_restart.phase_name from_p)
                   m.states
               with
               | Some s -> List.map (fun (t : Fpp_model.transition) -> t.target) s.transitions
               | None -> []
             in
             List.for_all
               (fun to_p ->
                 (not (Vision_restart.legal_transition from_p to_p))
                 || List.mem (Fpp_model.To_state (Vision_restart.phase_name to_p)) modelled)
               restart_phases)
           restart_phases

let ping =
  [ Fpp_model.General { name = "pingIn"; port = "Ping"; direction = Fpp_model.Sync_input; count = 1 };
    Fpp_model.General { name = "pingOut"; port = "Ping"; direction = Fpp_model.Output; count = 1 } ]

(* The pipeline ACTS on the world, so unlike a monitor it declares
   commands. *)
let pipeline_component =
  { Fpp_model.comp_name = "visionPipeline";
    kind = Fpp_model.Active;
    ports =
      [ Fpp_model.General { name = "intentIn"; port = "VisionIntent";
                            direction = Fpp_model.Async_input
                                          { priority = Some 1; queue_full = Fpp_model.Block };
                            count = 1 };
        Fpp_model.General { name = "observationOut"; port = "Observation";
                            direction = Fpp_model.Output; count = 1 };
        Fpp_model.Special Fpp_model.Event_p; Fpp_model.Special Fpp_model.Telemetry_p ]
      @ ping;
    commands =
      [ { Fpp_model.cmd_name = "START"; opcode = 0;
          cmd_kind = Fpp_model.Async_cmd { priority = Some 1; queue_full = Fpp_model.Block };
          cmd_params = [] };
        { Fpp_model.cmd_name = "STOP"; opcode = 1;
          cmd_kind = Fpp_model.Async_cmd { priority = Some 1; queue_full = Fpp_model.Block };
          cmd_params = [] } ];
    events = hazard_events;
    channels = stage_channels;
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

(* Separate from the pipeline because its failure posture is the
   OPPOSITE — the pipeline is fail-open, this is fail-closed — and
   merging them would hide that. *)
let control_component =
  { Fpp_model.comp_name = "visionControl";
    kind = Fpp_model.Queued;
    ports =
      [ Fpp_model.General { name = "queryIn"; port = "Control";
                            direction = Fpp_model.Sync_input; count = 1 };
        Fpp_model.General { name = "replyOut"; port = "Reply";
                            direction = Fpp_model.Output; count = 1 };
        Fpp_model.Special Fpp_model.Event_p; Fpp_model.Special Fpp_model.Telemetry_p ]
      @ ping;
    commands =
      [ { Fpp_model.cmd_name = "RESTART"; opcode = 0;
          cmd_kind = Fpp_model.Async_cmd { priority = Some 2; queue_full = Fpp_model.Block };
          cmd_params = [] } ];
    events =
      [ { Fpp_model.event_name = "CONTROL_REFUSED"; event_id = 0;
          severity = Fpp_model.Warning_hi;
          format = "control action refused: %s"; throttle = None };
        { Fpp_model.event_name = "RESTART_ROLLED_BACK"; event_id = 1;
          severity = Fpp_model.Warning_hi;
          format = "restart rolled back, pipeline is DOWN: %s"; throttle = None } ];
    channels =
      [ chan "vision_control_accepted" 0; chan "vision_control_refused" 1;
        chan "vision_restart_promoted" 2; chan "vision_restart_rolled_back" 3 ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = [ ("restart", "VisionRestart") ]; matched = [] }

let components = [ pipeline_component; control_component ]

let declared_channels () =
  List.concat_map
    (fun (c : Fpp_model.component) ->
      List.map (fun (ch : Fpp_model.channel) -> ch.Fpp_model.chan_name) c.Fpp_model.channels)
    components

(* Both directions: a stage with no channel, and a stage channel nothing
   would emit. *)
let channel_drift () =
  let declared = declared_channels () in
  List.filter_map
    (fun s ->
      let n = stage_channel_name s in
      if List.mem n declared then None else Some ("stage has no channel: " ^ n))
    Vision_ontology.stages

let render () =
  let b = Buffer.create 2048 in
  Buffer.add_string b (Printf.sprintf "vision FPP model (instance base 0x%x)\n" instance_base);
  List.iter
    (fun (c : Fpp_model.component) ->
      Buffer.add_string b
        (Printf.sprintf "  %-16s cmds=%d events=%d channels=%d\n" c.Fpp_model.comp_name
           (List.length c.Fpp_model.commands) (List.length c.Fpp_model.events)
           (List.length c.Fpp_model.channels)))
    components;
  List.iter
    (fun n -> Buffer.add_string b (Printf.sprintf "    channel %s\n" n))
    (declared_channels ());
  Buffer.contents b
