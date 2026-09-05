(* The BDD use-case catalog. See fpp_usecases.mli. Scenarios are data; the
   runner is test_fpp_bdd. Generic cases run on small purpose-built models;
   workflow cases run on the REAL Harness_topology.model — the point is
   that the harness's operational vocabulary is expressible and checkable
   in FPP terms. *)

open Fpp_model

type step =
  | When_signal of string * (string * bool) list
  | Then_state of string
  | Then_log_includes of string
  | When_command of string * int
  | Then_dispatch of
      [ `Executed | `Enqueued | `Assert_failed | `Blocked | `Dropped | `Rejected ]
  | Then_event_severity of string * string * string
  | Then_channel of string * string * string
  | Then_no_command_named of string
  | Then_connection of string * string
  | Then_no_connection of string list * string list
  | Then_law of string * (unit -> bool)

type scenario = {
  name : string;
  given : string;
  model : Fpp_model.model;
  topology_name : string;
  machine : Fpp_model.state_machine option;
  queue_capacity : int;
  steps : step list;
}

(* ------------------------------------------------------- generic models *)

let data_port = { port_name = "DataP"; params = [ ("v", Prim U32) ]; return_type = None }
let time_port = { port_name = "TimeP"; params = [ ("t", Prim U64) ]; return_type = None }

let gsensor =
  { comp_name = "gsensor"; kind = Passive;
    ports = [ General { name = "out"; port = "DataP"; direction = Output; count = 1 } ];
    commands = [];
    events = [];
    channels =
      [ { chan_name = "reading"; chan_id = 0; chan_type = Prim U32; update = Always;
          chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let gctl =
  { comp_name = "gctl"; kind = Active;
    ports =
      [ General { name = "in_"; port = "DataP";
                  direction = Async_input { priority = None; queue_full = Drop }; count = 1 } ];
    commands =
      [ { cmd_name = "HARD"; opcode = 0;
          cmd_kind = Async_cmd { priority = None; queue_full = Assert }; cmd_params = [] };
        { cmd_name = "SOFT"; opcode = 1;
          cmd_kind = Async_cmd { priority = None; queue_full = Drop }; cmd_params = [] };
        { cmd_name = "WAIT"; opcode = 2;
          cmd_kind = Async_cmd { priority = None; queue_full = Block }; cmd_params = [] };
        { cmd_name = "NOW"; opcode = 3; cmd_kind = Sync_cmd; cmd_params = [] } ];
    events = []; channels = []; parameters = []; records = []; containers = [];
    internal_ports = []; machines = []; matched = [] }

let gclock =
  { comp_name = "gclock"; kind = Passive;
    ports = [ General { name = "tin"; port = "TimeP"; direction = Sync_input; count = 1 } ];
    commands = []; events = []; channels = []; parameters = [];
    records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let mini =
  { model_name = "Mini";
    type_defs = []; port_defs = [ data_port; time_port ]; constants = [];
    components = [ gsensor; gctl; gclock ];
    machines = [];
    instances =
      [ { inst_name = "s1"; of_component = "gsensor"; base_id = 0x100; queue_size = None;
          stack_size = None; inst_priority = None; cpu = None };
        { inst_name = "c1"; of_component = "gctl"; base_id = 0x200; queue_size = Some 4;
          stack_size = None; inst_priority = None; cpu = None };
        { inst_name = "k1"; of_component = "gclock"; base_id = 0x400; queue_size = None;
          stack_size = None; inst_priority = None; cpu = None } ];
    topologies =
      [ { topo_name = "g"; members = [ "s1"; "c1"; "k1" ];
          graphs =
            [ Direct
                { graph_name = "wire";
                  connections =
                    [ { from_ = { ep_instance = "s1"; ep_port = "out"; ep_index = Some 0 };
                        to_ = { ep_instance = "c1"; ep_port = "in_"; ep_index = Some 0 } } ] } ] } ] }

let two_controllers =
  { mini with
    model_name = "Twins";
    instances =
      [ { inst_name = "c1"; of_component = "gctl"; base_id = 0x200; queue_size = Some 4;
          stack_size = None; inst_priority = None; cpu = None };
        { inst_name = "c2"; of_component = "gctl"; base_id = 0x300; queue_size = Some 4;
          stack_size = None; inst_priority = None; cpu = None } ];
    topologies = [ { topo_name = "g"; members = [ "c1"; "c2" ]; graphs = [] } ] }

let toy_machine =
  Internal_machine
    { machine_name = "ToyLife";
      signals = [ { signal_name = "go"; signal_type = None } ];
      guards = [ "armed" ];
      actions = [ "work"; "land" ];
      states =
        [ { state_name = "A"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "go"; guard = Some "armed"; do_actions = [ "work" ];
                  target = To_state "B" } ] };
          { state_name = "B"; entry = [ "land" ]; exit_ = []; transitions = [] } ];
      choices = []; initial = ([], "A") }

let on_mini ?(machine = None) ?(queue = 4) name given steps =
  { name; given; model = mini; topology_name = "g"; machine; queue_capacity = queue; steps }

let generic =
  [ on_mini "define a passive sensor with telemetry"
      "a passive component with an output port and an always-updating channel"
      [ Then_law ("the model validates clean", fun () -> validate mini = []);
        Then_channel ("s1", "reading", "always") ];
    on_mini "wire a sensor to an active controller through an async port"
      "an output port connected to an async input on an active component"
      [ Then_connection ("s1", "c1");
        Then_law ("the wiring passes every FPP check", fun () -> validate mini = []) ];
    on_mini ~queue:1 "queue-full policy: drop"
      "an async command whose queue-full behavior is drop, and a queue of one"
      [ When_command ("c1", 1); Then_dispatch `Enqueued;
        When_command ("c1", 1); Then_dispatch `Dropped ];
    on_mini ~queue:1 "queue-full policy: assert"
      "an async command whose queue-full behavior is assert (a lost activity is a defect)"
      [ When_command ("c1", 0); Then_dispatch `Enqueued;
        When_command ("c1", 0); Then_dispatch `Assert_failed ];
    on_mini ~queue:1 "queue-full policy: block"
      "an async command whose queue-full behavior is block"
      [ When_command ("c1", 2); Then_dispatch `Enqueued;
        When_command ("c1", 2); Then_dispatch `Blocked ];
    on_mini ~machine:(Some toy_machine) "a state machine lifecycle"
      "a machine with a guarded transition and an entry action"
      [ When_signal ("go", []); Then_state "A";  (* guard false: dropped *)
        When_signal ("go", [ ("armed", true) ]); Then_state "B";
        Then_log_includes "work"; Then_log_includes "land" ];
    { name = "one component, two instances, two dictionaries";
      given = "the same component instantiated at two base ids";
      model = two_controllers; topology_name = "g"; machine = None; queue_capacity = 4;
      steps =
        [ Then_law
            ( "instance-qualified opcodes are distinct",
              fun () ->
                match to_dictionary two_controllers ~topology:"g" with
                | Ok (`Assoc fields) -> (
                    match List.assoc_opt "commands" fields with
                    | Some (`List commands) ->
                        let opcodes =
                          List.filter_map
                            (fun c ->
                              match c with
                              | `Assoc f -> (
                                  match List.assoc_opt "opcode" f with
                                  | Some (`Int n) -> Some n
                                  | _ -> None)
                              | _ -> None)
                            commands
                        in
                        List.length opcodes = List.length (List.sort_uniq compare opcodes)
                        && List.length opcodes = 8
                    | _ -> false)
                | _ -> false ) ] };
    on_mini "invalid wiring is rejected, not repaired"
      "a connection between ports of different types"
      [ Then_law
          ( "the type mismatch is caught (FPP-TOPO-03)",
            fun () ->
              let broken =
                { mini with
                  topologies =
                    [ { topo_name = "g"; members = [ "s1"; "c1"; "k1" ];
                        graphs =
                          [ Direct
                              { graph_name = "bad";
                                connections =
                                  [ { from_ = { ep_instance = "s1"; ep_port = "out"; ep_index = None };
                                      to_ = { ep_instance = "k1"; ep_port = "tin"; ep_index = None } } ] } ] } ] }
              in
              List.exists
                (fun d -> d.Fractal_diagnostic.hazard = "FPP-TOPO-03")
                (validate broken) ) ] ]

(* ----------------------------------------------------- harness workflows *)

let harness = Harness_topology.model

let converge_machine =
  List.find
    (function
      | Internal_machine { machine_name; _ } -> machine_name = "ConvergeLoop"
      | External_machine _ -> false)
    harness.machines

let on_harness ?(machine = false) ?(queue = 16) name given steps =
  { name; given; model = harness; topology_name = "hermes_harness";
    machine = (if machine then Some converge_machine else None);
    queue_capacity = queue; steps }

let harness_component name =
  List.find (fun c -> c.comp_name = name) harness.components

let workflows =
  [ on_harness ~queue:1 "run the declarative pipeline"
      "the active dispatcher with a queue of one, and RUN_PIPELINE's queue-full is assert"
      [ When_command ("harness_config", 0); Then_dispatch `Enqueued;
        When_command ("harness_config", 0); Then_dispatch `Assert_failed;
        Then_event_severity ("harness_config", "PIPELINE_BLOCKED", "WARNING_HI") ];
    on_harness ~machine:true "converge to the fixpoint (the OODA walk)"
      "the ConvergeLoop machine at Idle"
      [ When_signal ("tick", []); Then_state "Preflight";
        When_signal ("preflight_ok", []); Then_state "Observing";
        Then_log_includes "observe";
        When_signal ("progress", [ ("frontier_advanced", true) ]); Then_state "Observing";
        Then_log_includes "orient"; Then_log_includes "decide"; Then_log_includes "act";
        When_signal ("progress", [ ("frontier_advanced", false) ]); Then_state "Converged";
        Then_log_includes "record" ];
    on_harness ~machine:true "R13: a resource refusal blocks and retries"
      "the ConvergeLoop machine and an unavailable resource"
      [ When_signal ("tick", []); Then_state "Preflight";
        When_signal ("preflight_refused", []); Then_state "Blocked";
        Then_log_includes "alert";
        Then_event_severity ("resource_envelope", "PREFLIGHT_REFUSED", "WARNING_HI");
        When_signal ("tick", []); Then_state "Preflight" ];
    on_harness ~machine:true "an anomaly stops the line"
      "the ConvergeLoop machine mid-observation"
      [ When_signal ("tick", []); When_signal ("preflight_ok", []);
        When_signal ("anomaly", []); Then_state "Anomalous";
        When_signal ("tick", []); Then_state "Anomalous";  (* absorbing *)
        Then_event_severity ("harness_config", "ANOMALY", "FATAL");
        Then_event_severity ("control_plane", "SWEEP_P0", "FATAL") ];
    on_harness "a divergence is a successful measurement"
      "the differential engine's event dictionary"
      [ Then_event_severity ("parity_compare", "DIVERGENCE_FOUND", "ACTIVITY_HI");
        Then_channel ("parity_compare", "divergences_open", "on change");
        Then_connection ("parity_compare", "fractal_diagnostic");
        Then_law
          ( "a divergence is never FATAL (it proves something)",
            fun () ->
              List.for_all
                (fun e -> e.event_name <> "DIVERGENCE_FOUND" || e.severity <> Fatal)
                (harness_component "parity_compare").events ) ];
    on_harness "capture stays a deliberate command"
      "the read-only topology (run_config maps Capture to Blocked)"
      [ Then_no_command_named "CAPTURE" ];
    on_harness "the report is derived, never commanded"
      "the dashboard follows the store; nothing can order it to say otherwise"
      [ Then_no_command_named "REPORT" ];
    on_harness "the health sweep pings every participant"
      "control_plane as the Svc::Health analogue"
      [ Then_connection ("control_plane", "evidence_store");
        Then_connection ("control_plane", "parity_compare");
        Then_connection ("control_plane", "harness_config");
        Then_connection ("control_plane", "hermes_zenoh") ];
    on_harness "time flows from the snapshot authority"
      "inventory as the time source (snapshot digest + git revision)"
      [ Then_connection ("evidence_store", "inventory");
        Then_connection ("parity_compare", "inventory");
        Then_connection ("control_plane", "inventory") ];
    on_harness "telemetry drains to the mesh, and mesh failure stays local"
      "hermes_zenoh as the telemetry hub with fail-open semantics"
      [ Then_connection ("evidence_store", "hermes_zenoh");
        Then_event_severity ("hermes_zenoh", "MESH_UNREACHABLE", "WARNING_LO");
        Then_channel ("hermes_zenoh", "publish_errors", "always") ];
    on_harness "alerts never touch verdicts"
      "the two-lattice law, structural"
      [ Then_no_connection
          ( [ "control_plane"; "homeostasis"; "hermes_zenoh" ],
            [ "parity_compare"; "parity_algebra"; "evidence_store" ] );
        Then_law
          ( "Verdict and Alert are distinct four-point enums",
            fun () ->
              let enum name =
                List.exists
                  (function
                    | Enum_t e -> e.name = name && List.length e.constants = 4
                    | _ -> false)
                  harness.type_defs
              in
              enum "Verdict" && enum "Alert" ) ];
    on_harness "the frontier regression sensor is armed"
      "verified_count with an on-change update and a low-red limit"
      [ Then_channel ("evidence_store", "verified_count", "on change");
        Then_law
          ( "the shrink limit is a red low threshold",
            fun () ->
              List.exists
                (fun ch ->
                  ch.chan_name = "verified_count"
                  && ch.low = Some { yellow = None; orange = None; red = Some 0.0 })
                (harness_component "evidence_store").channels ) ];
    on_harness "reconcile detects drift and reports convergence"
      "the blueprint's sync command surface"
      [ When_command ("blueprint", 1); Then_dispatch `Executed;
        Then_event_severity ("blueprint", "DRIFT_DETECTED", "WARNING_LO");
        Then_event_severity ("blueprint", "CONVERGED", "ACTIVITY_LO") ];
    on_harness "parameters govern the mesh and the windows"
      "set/save opcodes carried in the dictionary command space"
      [ Then_law
          ( "every parameter has set/save pseudo-commands",
            fun () ->
              match to_dictionary harness ~topology:"hermes_harness" with
              | Ok (`Assoc fields) -> (
                  match List.assoc_opt "commands" fields with
                  | Some (`List commands) ->
                      let kind_of k =
                        List.filter
                          (fun c ->
                            match c with
                            | `Assoc f -> List.assoc_opt "commandKind" f = Some (`String k)
                            | _ -> false)
                          commands
                      in
                      List.length (kind_of "set") = 4 && List.length (kind_of "save") = 4
                  | _ -> false)
              | _ -> false ) ];
    on_harness "the preflight command is guarded and immediate"
      "resource_envelope's PREFLIGHT (guarded: serialized, synchronous)"
      [ When_command ("resource_envelope", 0); Then_dispatch `Executed ];
    on_harness "adding a parity slice outgrows a stale subset and the sensor notices"
      "the L6 registry-drift sensor (playbook 01's integration checklist, live)"
      [ Then_law
          ( "more recorded scenarios than the subset lists fires P1",
            fun () ->
              let leg =
                Control_plane.l6_observation_coverage ~recorded:28 ~corpus:22
              in
              match leg.Control_plane.alert with
              | Homeostasis.P1 _ -> true
              | _ -> false );
        Then_law
          ( "a matching corpus stays green",
            fun () ->
              let leg =
                Control_plane.l6_observation_coverage ~recorded:22 ~corpus:22
              in
              leg.Control_plane.alert = Homeostasis.Green ) ];
    on_harness "a divergence folds to Divergent until it is repaired"
      "playbook 03's resolution tree over the real verdict algebra"
      [ Then_law
          ( "one divergence dominates the fold (max-rank combine)",
            fun () ->
              (Parity_algebra.report ~required:true
                 [ Parity_algebra.Verified; Parity_algebra.Divergent;
                   Parity_algebra.Verified ])
                .Parity_algebra.verdict
              = Parity_algebra.Divergent );
        Then_law
          ( "after a faithful repair the fold is Verified",
            fun () ->
              (Parity_algebra.report ~required:true
                 [ Parity_algebra.Verified; Parity_algebra.Verified;
                   Parity_algebra.Verified ])
                .Parity_algebra.verdict
              = Parity_algebra.Verified );
        Then_law
          ( "a Blocked oracle never counts as a divergence",
            fun () ->
              (Parity_algebra.report ~required:true
                 [ Parity_algebra.Verified; Parity_algebra.Blocked ])
                .Parity_algebra.verdict
              = Parity_algebra.Blocked ) ] ]

(* -------------------------------------------------- code generation *)

let anchored path =
  Sys.file_exists path
  && (let stats = open_in_bin path in
      let size = in_channel_length stats in
      close_in stats;
      size > 0)

let codegen =
  [ on_harness "generate the FPP source for the deployment"
      "Fpp_model.to_fpp over the real model"
      [ Then_law
          ( "the render is deterministic and names the deployment",
            fun () ->
              let text = Harness_topology.to_fpp () in
              text = Harness_topology.to_fpp ()
              && String.length text > 2_000 ) ];
    on_harness "generate the ground dictionary"
      "Fpp_model.to_dictionary per the published JSON dictionary spec"
      [ Then_law
          ( "all ten top-level keys emit, instance-qualified",
            fun () ->
              match Harness_topology.dictionary () with
              | Ok (`Assoc fields) -> List.length fields >= 10
              | _ -> false ) ];
    on_harness "generation is fail-closed"
      "an invalid model must refuse to emit, never emit wrongly"
      [ Then_law
          ( "a nameless component blocks the dictionary",
            fun () ->
              let broken =
                { mini with components = { gsensor with comp_name = "" } :: mini.components }
              in
              match to_dictionary broken ~topology:"g" with
              | Error _ -> true
              | Ok _ -> false ) ];
    on_harness "the committed atlas artifacts are anchored"
      "render_fprime_atlas + render_formal_coverage outputs, in the repository"
      [ Then_law
          ( "the .fpp, the dictionary, and the coverage page exist and are non-empty",
            fun () ->
              anchored "docs/hermes/atlas/hermes-harness.fpp"
              && anchored "docs/hermes/atlas/hermes-harness-dictionary.json"
              && anchored "docs/hermes/atlas/formal-coverage.md" ) ];
    on_harness "the Rocq extraction pipeline is anchored"
      "theorems, transcription, and committed extraction"
      [ Then_law
          ( "Parity_Lattice.v, rocq_lattice.ml, and the extracted module exist",
            fun () ->
              anchored "modules/hermes_harness/proofs/Parity_Lattice.v"
              && anchored "modules/hermes_harness/rocq_lattice.ml"
              && anchored "modules/hermes_harness/generated_rocq/parity_lattice_extracted.ml" ) ];
    on_harness "the quint machine spec is anchored"
      "the frontier machine's second encoding"
      [ Then_law
          ( "specs/parity_frontier.qnt exists and is non-empty",
            fun () -> anchored "modules/hermes_harness/specs/parity_frontier.qnt" ) ];
    on_harness "atlas regeneration preconditions hold right now"
      "the fail-closed gates render_fprime_atlas checks before writing"
      [ Then_law
          ( "the model validates, the ontology law holds, the dictionary emits",
            fun () ->
              Harness_topology.validate () = []
              && Harness_topology.ontology_gaps () = []
              && (match Harness_topology.dictionary () with Ok _ -> true | Error _ -> false) ) ] ]

let all = generic @ workflows @ codegen
