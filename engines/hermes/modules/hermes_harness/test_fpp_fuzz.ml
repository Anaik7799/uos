(* Fuzz / chaos / property for the FPP layer.

   Fuzz: garbage models (random names incl. empty, dangling references,
   wild ids) — the validator and emitters must be TOTAL: diagnose or
   refuse, never raise. Mutation fuzz: eight defect operators, every
   injection caught by its own check family (meta-falsification at scale).
   Interpreter fuzz: random signal soups over the REAL ConvergeLoop — never
   raises, state stays closed over the machine's states, Anomalous is
   absorbing (and the run count proves the property was actually visited).

   Chaos: 500-instance models, deep alias chains and cycles, an 80-state
   ring machine, a 40-deep choice ladder, 100-target pattern expansion —
   terminate, stay correct, stay fast.

   Property: emitter determinism, dictionary opcode/base-window laws,
   pattern-expansion monotonicity, id_span laws. *)

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

open Fpp_model

let () =
  Random.self_init ();
  let seed = Random.int 1_000_000 in
  Random.init seed;
  Printf.printf "fuzz seed: %d\n" seed

(* ------------------------------------------------------------ generators *)

let data_port = { port_name = "DP"; params = [ ("v", Prim U32) ]; return_type = None }

let valid_component index =
  let name = Printf.sprintf "c%d" index in
  { comp_name = name; kind = Passive;
    ports = [ General { name = "out"; port = "DP"; direction = Output; count = 2 } ];
    commands =
      List.init (Random.int 3) (fun i ->
          { cmd_name = Printf.sprintf "K%d" i; opcode = i;
            cmd_kind = (if Random.bool () then Sync_cmd else Guarded_cmd);
            cmd_params = [] });
    events =
      List.init (Random.int 3) (fun i ->
          { event_name = Printf.sprintf "E%d" i; event_id = 10 + i; severity = Diagnostic;
            format = "e"; throttle = None });
    channels =
      List.init (Random.int 3) (fun i ->
          { chan_name = Printf.sprintf "T%d" i; chan_id = 20 + i; chan_type = Prim U32;
            update = (if Random.bool () then Always else On_change); chan_format = None;
            low = None; high = None });
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let valid_model () =
  let n = 1 + Random.int 5 in
  let components = List.init n valid_component in
  let instances =
    List.mapi
      (fun i (c : component) ->
        { inst_name = Printf.sprintf "i%d" i; of_component = c.comp_name;
          base_id = 0x1000 * (i + 1); queue_size = None; stack_size = None;
          inst_priority = None; cpu = None })
      components
  in
  { model_name = "Gen"; type_defs = []; port_defs = [ data_port ]; constants = [];
    components; machines = []; instances;
    topologies =
      [ { topo_name = "t"; members = List.map (fun i -> i.inst_name) instances;
          graphs = [] } ] }

let junk_string () =
  match Random.int 6 with
  | 0 -> ""
  | 1 -> "x"
  | 2 -> String.make (1 + Random.int 30) (Char.chr (33 + Random.int 90))
  | 3 -> Printf.sprintf "n%d" (Random.int 5)
  | 4 -> "DP"
  | _ -> Printf.sprintf "ghost%d" (Random.int 3)

let junk_ty () = if Random.bool () then Prim U32 else Named (junk_string ())

let garbage_model () =
  let junk_component () =
    { comp_name = junk_string ();
      kind = (match Random.int 3 with 0 -> Passive | 1 -> Queued | _ -> Active);
      ports =
        List.init (Random.int 4) (fun _ ->
            if Random.bool () then
              General
                { name = junk_string (); port = junk_string ();
                  direction =
                    (match Random.int 4 with
                    | 0 -> Sync_input
                    | 1 -> Guarded_input
                    | 2 -> Async_input { priority = Some (Random.int 10); queue_full = Drop }
                    | _ -> Output);
                  count = Random.int 5 - 1 }
            else Special (if Random.bool () then Telemetry_p else Time_get));
      commands =
        List.init (Random.int 3) (fun _ ->
            { cmd_name = junk_string (); opcode = Random.int 8 - 2;
              cmd_kind =
                (if Random.bool () then Sync_cmd
                 else Async_cmd { priority = None; queue_full = Assert });
              cmd_params = [ (junk_string (), junk_ty ()) ] });
      events =
        List.init (Random.int 3) (fun _ ->
            { event_name = junk_string (); event_id = Random.int 6 - 1;
              severity = Fatal; format = junk_string (); throttle = None });
      channels =
        List.init (Random.int 3) (fun _ ->
            { chan_name = junk_string (); chan_id = Random.int 6 - 1;
              chan_type = junk_ty (); update = Always; chan_format = None;
              low = None; high = None });
      parameters = [];
      records =
        List.init (Random.int 2) (fun _ ->
            { record_name = junk_string (); record_id = Random.int 4;
              record_type = junk_ty (); record_is_array = Random.bool () });
      containers = []; internal_ports = [];
      machines = List.init (Random.int 2) (fun _ -> (junk_string (), junk_string ()));
      matched = [ (junk_string (), junk_string ()) ] }
  in
  let components = List.init (1 + Random.int 3) (fun _ -> junk_component ()) in
  { model_name = junk_string ();
    type_defs =
      [ Alias { name = junk_string (); target = junk_ty () };
        Alias { name = "A"; target = Named "B" };
        Alias { name = "B"; target = Named (if Random.bool () then "A" else "C") } ];
    port_defs = [ data_port; { port_name = junk_string (); params = []; return_type = None } ];
    constants = [ (junk_string (), Random.int 100 - 50) ];
    components;
    machines = [];
    instances =
      List.init (Random.int 4) (fun i ->
          { inst_name = junk_string (); of_component = junk_string ();
            base_id = Random.int 100 - 50; queue_size = (if Random.bool () then Some 1 else None);
            stack_size = None; inst_priority = None; cpu = None }
          |> fun inst -> if i = 0 then { inst with inst_name = "i0" } else inst);
    topologies =
      [ { topo_name = junk_string ();
          members = List.init (Random.int 4) (fun _ -> junk_string ());
          graphs =
            [ Direct
                { graph_name = junk_string ();
                  connections =
                    List.init (Random.int 4) (fun _ ->
                        { from_ =
                            { ep_instance = junk_string (); ep_port = junk_string ();
                              ep_index = (if Random.bool () then Some (Random.int 4 - 1) else None) };
                          to_ =
                            { ep_instance = junk_string (); ep_port = junk_string ();
                              ep_index = None } }) };
              Pattern
                { pattern = P_health; source = junk_string ();
                  targets = List.init (Random.int 3) (fun _ -> junk_string ()) } ] } ] }

(* -------------------------------------------------- fuzz: totality (300) *)

let () =
  let crashes = ref 0 and rounds = 300 in
  for _ = 1 to rounds do
    let model = garbage_model () in
    (try ignore (validate model) with _ -> incr crashes);
    (try ignore (to_fpp model) with _ -> incr crashes);
    (try
       match to_dictionary model ~topology:"t" with Ok _ | Error _ -> ()
     with _ -> incr crashes)
  done;
  check
    (Printf.sprintf "totality: %d garbage models diagnosed or refused, never a crash" rounds)
    (fun () -> !crashes = 0);
  check "garbage is actually rejected (the fuzz is not vacuous)" (fun () ->
      (* A garbage model with empty names/dangling refs must draw diagnostics. *)
      validate (garbage_model ()) <> [])

(* ------------------------------------- fuzz: mutation operators (8 x 200) *)

let () =
  let inject model kind =
    match (kind, model.components, model.instances) with
    | 0, c :: rest, _ ->
        ( { model with
            components =
              { c with
                commands =
                  [ { cmd_name = "D"; opcode = 7; cmd_kind = Sync_cmd; cmd_params = [] };
                    { cmd_name = "D2"; opcode = 7; cmd_kind = Sync_cmd; cmd_params = [] } ] }
              :: rest },
          "FPP-CMP-03" )
    | 1, c :: rest, _ ->
        ( { model with
            components =
              { c with
                events =
                  [ { event_name = "E"; event_id = 5; severity = Diagnostic; format = "";
                      throttle = None };
                    { event_name = "E2"; event_id = 5; severity = Fatal; format = "";
                      throttle = None } ] }
              :: rest },
          "FPP-CMP-04" )
    | 2, c :: rest, _ ->
        ( { model with
            components =
              { c with
                ports =
                  General
                    { name = "bad"; port = "DP";
                      direction = Async_input { priority = None; queue_full = Drop };
                      count = 1 }
                  :: c.ports } (* async in a Passive component *)
              :: rest },
          "FPP-CMP-01" )
    | 3, c :: rest, _ ->
        ( { model with
            components =
              { c with records = [ { record_name = "r"; record_id = 0; record_type = Prim U32;
                                     record_is_array = false } ] }
              :: rest },
          "FPP-CMP-08" )
    | 4, c :: rest, _ ->
        ( { model with
            components = { c with ports = Special Telemetry_p :: Special Telemetry_p :: c.ports } :: rest },
          "FPP-CMP-09" )
    | 5, c :: rest, _ ->
        ( { model with components = { c with machines = [ ("m", "NoSuch") ] } :: rest },
          "FPP-CMP-10" )
    | 6, _, i :: rest ->
        ( { model with instances = { i with inst_name = i.inst_name ^ "d" } :: i :: rest },
          "FPP-INST-02" )
    | _, _, i :: _ ->
        ( { model with
            instances =
              List.map (fun x -> if x == i then { x with queue_size = Some 3 } else x)
                model.instances },
          "FPP-INST-01" (* queue on a passive instance *) )
    | _ -> (model, "unreachable")
  in
  let rounds = 200 and caught = ref 0 in
  for _ = 1 to rounds do
    let model = valid_model () in
    let mutated, expected = inject model (Random.int 8) in
    if
      List.exists
        (fun d -> d.Fractal_diagnostic.hazard = expected)
        (validate mutated)
    then incr caught
  done;
  check
    (Printf.sprintf "mutation fuzz: %d/%d injections caught by their own check" !caught rounds)
    (fun () -> !caught = rounds)

(* --------------------------------- fuzz: the ConvergeLoop under signal soup *)

let converge =
  List.find
    (function
      | Internal_machine { machine_name; _ } -> machine_name = "ConvergeLoop"
      | External_machine _ -> false)
    Harness_topology.model.machines

let converge_states =
  match converge with
  | Internal_machine { states; _ } -> List.map (fun s -> s.state_name) states
  | External_machine _ -> []

let () =
  let signals =
    [| "tick"; "preflight_ok"; "preflight_refused"; "progress"; "no_progress";
       "anomaly"; "ghost"; "" |]
  in
  let runs = 200 and violations = ref 0 and anomalous_visits = ref 0 in
  for _ = 1 to runs do
    match Fpp_interp.init converge with
    | Error _ -> incr violations
    | Ok start ->
        let state = ref start in
        for _ = 1 to 30 do
          let signal = signals.(Random.int (Array.length signals)) in
          let guards = [ ("frontier_advanced", Random.bool ()) ] in
          match Fpp_interp.dispatch ~machine:converge ~guards !state signal with
          | Ok next ->
              let was_anomalous = !state.Fpp_interp.current = "Anomalous" in
              if not (List.mem next.Fpp_interp.current converge_states) then
                incr violations;
              if was_anomalous && next.Fpp_interp.current <> "Anomalous" then
                incr violations (* absorbing broken *)
              else if next.Fpp_interp.current = "Anomalous" then
                incr anomalous_visits;
              if
                List.length next.Fpp_interp.log < List.length !state.Fpp_interp.log
              then incr violations (* the log never shrinks *);
              state := next
          | Error _ -> () (* unknown signals error by contract; state unchanged *)
        done
  done;
  check "signal-soup fuzz: closed states, growing log, absorbing Anomalous"
    (fun () -> !violations = 0);
  check "the absorbing property was actually exercised (non-vacuous)" (fun () ->
      !anomalous_visits > 0)

(* ------------------------------------------- fuzz: command opcode space *)

let () =
  let crashes = ref 0 and rounds = 400 in
  let instances = Harness_topology.model.instances in
  for _ = 1 to rounds do
    let i = List.nth instances (Random.int (List.length instances)) in
    let opcode = i.base_id + Random.int 0x60 - 0x20 in
    let queue =
      if Random.bool () then Some (Fpp_interp.empty_queue ~capacity:(Random.int 3))
      else None
    in
    try
      match
        Fpp_interp.send_command Harness_topology.model ~instance:i.inst_name ~opcode ~queue
      with
      | Ok (Fpp_interp.Enqueued q) when q.Fpp_interp.depth > q.Fpp_interp.capacity ->
          incr crashes
      | Ok _ | Error _ -> ()
    with _ -> incr crashes
  done;
  check
    (Printf.sprintf "opcode fuzz: %d random dispatches, total, queue never overfills" rounds)
    (fun () -> !crashes = 0)

(* Persistent-queue load: the first mutant proof exposed that fresh
   per-round queues made the overfill invariant nearly vacuous (async
   opcodes are rare in the harness sweep). This leg drives ONE evolving
   queue hard: depth must never exceed capacity, drops must be monotone. *)
let () =
  let qc =
    { comp_name = "qz"; kind = Active; ports = [];
      commands =
        [ { cmd_name = "SOFT"; opcode = 0;
            cmd_kind = Async_cmd { priority = None; queue_full = Drop }; cmd_params = [] } ];
      events = []; channels = []; parameters = []; records = []; containers = [];
      internal_ports = [];
      machines = [];
      matched = [] }
  in
  (* An async command alone fails FPP-CMP-02? No: an async COMMAND is an
     async element, so the component is legal. The model stays valid. *)
  let model =
    { model_name = "QZ"; type_defs = []; port_defs = []; constants = [];
      components = [ qc ]; machines = [];
      instances =
        [ { inst_name = "q"; of_component = "qz"; base_id = 0x40; queue_size = Some 2;
            stack_size = Some 256; inst_priority = Some 1; cpu = None } ];
      topologies = [ { topo_name = "t"; members = [ "q" ]; graphs = [] } ] }
  in
  let violations = ref 0 in
  for _ = 1 to 100 do
    let capacity = Random.int 3 in
    let queue = ref (Fpp_interp.empty_queue ~capacity) in
    let dropped_before = ref 0 in
    for _ = 1 to 10 do
      match
        Fpp_interp.send_command model ~instance:"q" ~opcode:0x40 ~queue:(Some !queue)
      with
      | Ok (Fpp_interp.Enqueued q) ->
          if q.Fpp_interp.depth > q.Fpp_interp.capacity then incr violations;
          queue := q
      | Ok (Fpp_interp.Dropped q) ->
          if q.Fpp_interp.dropped < !dropped_before then incr violations;
          dropped_before := q.Fpp_interp.dropped;
          queue := q
      | Ok _ -> ()
      | Error _ -> incr violations
    done
  done;
  check "persistent-queue load: depth <= capacity always, drops monotone"
    (fun () -> !violations = 0)

(* ------------------------------------------------------------------ chaos *)

let () =
  check "chaos: a 500-instance model validates clean and fast" (fun () ->
      let components =
        List.init 500 (fun i ->
            { (valid_component i) with comp_name = Printf.sprintf "bulk%d" i;
              commands = []; events = []; channels = [] })
      in
      let instances =
        List.mapi
          (fun i (c : component) ->
            { inst_name = Printf.sprintf "b%d" i; of_component = c.comp_name;
              base_id = 0x100 + (i * 4); queue_size = None; stack_size = None;
              inst_priority = None; cpu = None })
          components
      in
      let model =
        { model_name = "Big"; type_defs = []; port_defs = [ data_port ]; constants = [];
          components; machines = []; instances;
          topologies =
            [ { topo_name = "t"; members = List.map (fun i -> i.inst_name) instances;
                graphs = [] } ] }
      in
      let t0 = Unix.gettimeofday () in
      let clean = validate model = [] in
      let dt = Unix.gettimeofday () -. t0 in
      clean && dt < 5.0);
  check "chaos: a 120-deep alias chain validates; a 60-cycle is caught" (fun () ->
      let chain =
        List.init 120 (fun i ->
            Alias
              { name = Printf.sprintf "a%d" i;
                target = (if i = 0 then Prim U32 else Named (Printf.sprintf "a%d" (i - 1))) })
      in
      let ok =
        validate
          { model_name = "Chain"; type_defs = chain; port_defs = []; constants = [];
            components = []; machines = []; instances = []; topologies = [] }
        = []
      in
      let cycle =
        List.init 60 (fun i ->
            Alias
              { name = Printf.sprintf "z%d" i;
                target = Named (Printf.sprintf "z%d" ((i + 1) mod 60)) })
      in
      let caught =
        List.exists
          (fun d -> d.Fractal_diagnostic.hazard = "FPP-TYPE-02")
          (validate
             { model_name = "Cycle"; type_defs = cycle; port_defs = []; constants = [];
               components = []; machines = []; instances = []; topologies = [] })
      in
      ok && caught);
  check "chaos: an 80-state ring machine survives 500 dispatches" (fun () ->
      let n = 80 in
      let states =
        List.init n (fun i ->
            { state_name = Printf.sprintf "S%d" i; entry = []; exit_ = [];
              transitions =
                [ { on_signal = "step"; guard = None; do_actions = [];
                    target = To_state (Printf.sprintf "S%d" ((i + 1) mod n)) } ] })
      in
      let ring =
        Internal_machine
          { machine_name = "Ring";
            signals = [ { signal_name = "step"; signal_type = None } ];
            guards = []; actions = []; states; choices = []; initial = ([], "S0") }
      in
      match Fpp_interp.init ring with
      | Error _ -> false
      | Ok start ->
          let state = ref start and ok = ref true in
          for _ = 1 to 500 do
            match Fpp_interp.dispatch ~machine:ring ~guards:[] !state "step" with
            | Ok next -> state := next
            | Error _ -> ok := false
          done;
          !ok && !state.Fpp_interp.current = Printf.sprintf "S%d" (500 mod n));
  check "chaos: a 40-deep choice ladder resolves through the fuel bound" (fun () ->
      let n = 40 in
      let choices =
        List.init n (fun i ->
            { choice_name = Printf.sprintf "c%d" i; choice_guard = "on";
              if_true =
                ( [],
                  if i = n - 1 then To_state "End" else To_choice (Printf.sprintf "c%d" (i + 1)) );
              if_false = ([], To_state "Start") })
      in
      let ladder =
        Internal_machine
          { machine_name = "Ladder";
            signals = [ { signal_name = "go"; signal_type = None } ];
            guards = [ "on" ]; actions = [];
            states =
              [ { state_name = "Start"; entry = []; exit_ = [];
                  transitions =
                    [ { on_signal = "go"; guard = None; do_actions = [];
                        target = To_choice "c0" } ] };
                { state_name = "End"; entry = []; exit_ = []; transitions = [] } ];
            choices; initial = ([], "Start") }
      in
      match Fpp_interp.init ladder with
      | Error _ -> false
      | Ok start -> (
          match Fpp_interp.dispatch ~machine:ladder ~guards:[ ("on", true) ] start "go" with
          | Ok s -> s.Fpp_interp.current = "End"
          | Error _ -> false));
  check "chaos: pattern expansion over 100 targets terminates and counts" (fun () ->
      let consumer i =
        { comp_name = Printf.sprintf "n%d" i; kind = Passive;
          ports = [ Special Time_get ]; commands = []; events = []; channels = [];
          parameters = []; records = []; containers = []; internal_ports = [];
          machines = []; matched = [] }
      in
      let source =
        { comp_name = "src"; kind = Passive;
          ports = [ General { name = "timeGetIn"; port = "DP"; direction = Sync_input; count = 200 } ];
          commands = []; events = []; channels = []; parameters = []; records = [];
          containers = []; internal_ports = []; machines = []; matched = [] }
      in
      let consumers = List.init 100 consumer in
      let instances =
        { inst_name = "src"; of_component = "src"; base_id = 0x10; queue_size = None;
          stack_size = None; inst_priority = None; cpu = None }
        :: List.mapi
             (fun i (c : component) ->
               { inst_name = Printf.sprintf "n%d" i; of_component = c.comp_name;
                 base_id = 0x100 + (i * 2); queue_size = None; stack_size = None;
                 inst_priority = None; cpu = None })
             consumers
      in
      let topo =
        { topo_name = "t"; members = List.map (fun i -> i.inst_name) instances;
          graphs =
            [ Pattern
                { pattern = P_time; source = "src";
                  targets = List.init 100 (fun i -> Printf.sprintf "n%d" i) } ] }
      in
      let model =
        { model_name = "Fan"; type_defs = []; port_defs = [ data_port ]; constants = [];
          components = source :: consumers; machines = []; instances;
          topologies = [ topo ] }
      in
      match connections model topo with
      | Ok links -> List.length links = 100
      | Error _ -> false)

(* -------------------------------------------------------------- property *)

let () =
  let rounds = 50 and stable = ref 0 in
  for _ = 1 to rounds do
    let model = valid_model () in
    let same_fpp = to_fpp model = to_fpp model in
    let same_dict = to_dictionary model ~topology:"t" = to_dictionary model ~topology:"t" in
    let same_validate = validate model = validate model in
    if same_fpp && same_dict && same_validate then incr stable
  done;
  check
    (Printf.sprintf "determinism: %d models, emitters and validator stable" rounds)
    (fun () -> !stable = rounds);
  let opcode_law = ref 0 and rounds2 = 50 in
  for _ = 1 to rounds2 do
    let model = valid_model () in
    let holds =
      match to_dictionary model ~topology:"t" with
      | Error _ -> false
      | Ok (`Assoc fields) -> (
          match List.assoc_opt "commands" fields with
          | Some (`List commands) ->
              List.for_all
                (fun c ->
                  match c with
                  | `Assoc f -> (
                      match List.assoc_opt "opcode" f with
                      | Some (`Int op) ->
                          List.exists
                            (fun i ->
                              match
                                List.find_opt
                                  (fun (co : component) -> co.comp_name = i.of_component)
                                  model.components
                              with
                              | Some co ->
                                  op >= i.base_id && op < i.base_id + id_span co
                              | None -> false)
                            model.instances
                      | _ -> false)
                  | _ -> false)
                commands
          | _ -> false)
      | Ok _ -> false
    in
    if holds then incr opcode_law
  done;
  check "dictionary law: every opcode lies inside its instance's base window"
    (fun () -> !opcode_law = rounds2);
  check "expansion is monotone in targets" (fun () ->
      let topo targets =
        { topo_name = "hermes_harness_probe"; members = Harness_topology.topology.members;
          graphs = [ Pattern { pattern = P_time; source = "inventory"; targets } ] }
      in
      let count targets =
        match connections Harness_topology.model (topo targets) with
        | Ok l -> List.length l
        | Error _ -> -1
      in
      let small = count [ "evidence_store" ] in
      let big = count [ "evidence_store"; "parity_compare"; "control_plane" ] in
      small = 1 && big = 3);
  check "id_span is monotone under a higher opcode" (fun () ->
      let c = valid_component 0 in
      let bigger =
        { c with
          commands =
            { cmd_name = "TOP"; opcode = 90; cmd_kind = Sync_cmd; cmd_params = [] }
            :: c.commands }
      in
      id_span bigger = 91 && id_span bigger >= id_span c)

let () =
  Printf.printf "fpp_fuzz: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_fpp_fuzz" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
