(* The FPP interpreter under test: the spec's dispatch semantics (exit ->
   do -> entry action order, guard-gated transitions, dropped unhandled
   signals, choice resolution) and the command/queue simulation
   (sync/guarded execute; async enqueues with assert/block/drop on full).
   Integration: the REAL ConvergeLoop machine walks its OODA lifecycle. *)

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

(* A small machine exercising every element: guard, choice, entry/exit. *)
let toy =
  Internal_machine
    { machine_name = "Toy";
      signals =
        [ { signal_name = "go"; signal_type = None };
          { signal_name = "stop"; signal_type = None };
          { signal_name = "fork"; signal_type = None } ];
      guards = [ "armed"; "deep" ];
      actions = [ "boot"; "leave"; "work"; "land"; "twist" ];
      states =
        [ { state_name = "A"; entry = []; exit_ = [ "leave" ];
            transitions =
              [ { on_signal = "go"; guard = Some "armed"; do_actions = [ "work" ];
                  target = To_state "B" };
                { on_signal = "fork"; guard = None; do_actions = []; target = To_choice "c1" } ] };
          { state_name = "B"; entry = [ "land" ]; exit_ = [];
            transitions =
              [ { on_signal = "stop"; guard = None; do_actions = []; target = To_state "A" } ] };
          { state_name = "C"; entry = []; exit_ = []; transitions = [] } ];
      choices =
        [ { choice_name = "c1"; choice_guard = "deep";
            if_true = ([ "twist" ], To_choice "c2"); if_false = ([], To_state "A") };
          { choice_name = "c2"; choice_guard = "armed";
            if_true = ([ "work" ], To_state "C"); if_false = ([], To_state "B") } ]
      ;
      initial = ([ "boot" ], "A") }

let init_ok () =
  match Fpp_interp.init toy with Ok s -> s | Error e -> failwith e

let () =
  check "init enters the initial state and runs its actions" (fun () ->
      let s = init_ok () in
      s.Fpp_interp.current = "A" && s.Fpp_interp.log = [ "boot" ]);
  check "init refuses an external machine" (fun () ->
      match Fpp_interp.init (External_machine { machine_name = "X" }) with
      | Error _ -> true
      | Ok _ -> false);
  check "a guarded transition fires when the guard holds, exit->do->entry order"
    (fun () ->
      let s = init_ok () in
      match Fpp_interp.dispatch ~machine:toy ~guards:[ ("armed", true) ] s "go" with
      | Ok s' ->
          s'.Fpp_interp.current = "B"
          && s'.Fpp_interp.log = [ "boot"; "leave"; "work"; "land" ]
      | Error _ -> false);
  check "a guarded transition is dropped when the guard is false" (fun () ->
      let s = init_ok () in
      match Fpp_interp.dispatch ~machine:toy ~guards:[] s "go" with
      | Ok s' -> s'.Fpp_interp.current = "A" && s'.Fpp_interp.log = [ "boot" ]
      | Error _ -> false);
  check "an unhandled signal is dropped silently (spec semantics)" (fun () ->
      let s = init_ok () in
      match Fpp_interp.dispatch ~machine:toy ~guards:[] s "stop" with
      | Ok s' -> s'.Fpp_interp.current = "A" && s'.Fpp_interp.log = [ "boot" ]
      | Error _ -> false);
  check "an unknown signal name is a caller error, not a drop" (fun () ->
      let s = init_ok () in
      match Fpp_interp.dispatch ~machine:toy ~guards:[] s "ghost" with
      | Error _ -> true
      | Ok _ -> false);
  check "a chained choice resolves through both junctions (true/true)" (fun () ->
      let s = init_ok () in
      match
        Fpp_interp.dispatch ~machine:toy
          ~guards:[ ("deep", true); ("armed", true) ]
          s "fork"
      with
      | Ok s' ->
          s'.Fpp_interp.current = "C"
          && s'.Fpp_interp.log = [ "boot"; "leave"; "twist"; "work" ]
      | Error _ -> false);
  check "a chained choice false-arc lands back without arc actions" (fun () ->
      let s = init_ok () in
      match Fpp_interp.dispatch ~machine:toy ~guards:[] s "fork" with
      | Ok s' ->
          (* deep=false: c1 false-arc -> state A. Exit ran, entry of A is []. *)
          s'.Fpp_interp.current = "A" && s'.Fpp_interp.log = [ "boot"; "leave" ]
      | Error _ -> false);
  check "a terminal state is absorbing" (fun () ->
      let s = init_ok () in
      match
        Fpp_interp.dispatch ~machine:toy ~guards:[ ("deep", true); ("armed", true) ] s "fork"
      with
      | Error _ -> false
      | Ok s_c -> (
          match Fpp_interp.dispatch ~machine:toy ~guards:[] s_c "go" with
          | Ok s' -> s'.Fpp_interp.current = "C"
          | Error _ -> false));
  check "a tampered current state is an error, never a crash" (fun () ->
      let s = { Fpp_interp.current = "Nowhere"; log = [] } in
      match Fpp_interp.dispatch ~machine:toy ~guards:[] s "go" with
      | Error _ -> true
      | Ok _ -> false);
  check "self-transitions replay exit and entry" (fun () ->
      let selfy =
        Internal_machine
          { machine_name = "Selfy";
            signals = [ { signal_name = "again"; signal_type = None } ];
            guards = []; actions = [ "out"; "in_" ];
            states =
              [ { state_name = "S"; entry = [ "in_" ]; exit_ = [ "out" ];
                  transitions =
                    [ { on_signal = "again"; guard = None; do_actions = [];
                        target = To_state "S" } ] } ];
            choices = []; initial = ([], "S") }
      in
      match Fpp_interp.init selfy with
      | Error _ -> false
      | Ok s -> (
          match Fpp_interp.dispatch ~machine:selfy ~guards:[] s "again" with
          | Ok s' -> s'.Fpp_interp.log = [ "out"; "in_" ]
          | Error _ -> false))

(* ----------------------------------------------------- command dispatch *)

let queued_component =
  { comp_name = "qc"; kind = Active;
    ports = [];
    commands =
      [ { cmd_name = "HARD"; opcode = 0;
          cmd_kind = Async_cmd { priority = None; queue_full = Assert }; cmd_params = [] };
        { cmd_name = "SOFT"; opcode = 1;
          cmd_kind = Async_cmd { priority = None; queue_full = Drop }; cmd_params = [] };
        { cmd_name = "WAIT"; opcode = 2;
          cmd_kind = Async_cmd { priority = None; queue_full = Block }; cmd_params = [] };
        { cmd_name = "NOW"; opcode = 3; cmd_kind = Sync_cmd; cmd_params = [] };
        { cmd_name = "LOCKED"; opcode = 4; cmd_kind = Guarded_cmd; cmd_params = [] } ];
    events = []; channels = [];
    parameters =
      [ { param_name = "P"; param_id = 8; param_type = Prim U32; default = None;
          set_opcode = 16; save_opcode = 17; external_ = false } ];
    records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let queued_model =
  { model_name = "Q"; type_defs = []; port_defs = []; constants = [];
    components = [ queued_component ]; machines = [];
    instances =
      [ { inst_name = "q1"; of_component = "qc"; base_id = 0x1000; queue_size = Some 2;
          stack_size = Some 1024; inst_priority = Some 1; cpu = None } ];
    topologies = [ { topo_name = "t"; members = [ "q1" ]; graphs = [] } ] }

let send ?queue opcode =
  Fpp_interp.send_command queued_model ~instance:"q1" ~opcode:(0x1000 + opcode) ~queue

let () =
  check "a sync command executes immediately" (fun () ->
      send 3 = Ok Fpp_interp.Executed);
  check "a guarded command executes immediately (single-threaded harness)" (fun () ->
      send 4 = Ok Fpp_interp.Executed);
  check "param set/save opcodes dispatch like commands" (fun () ->
      send 16 = Ok Fpp_interp.Executed && send 17 = Ok Fpp_interp.Executed);
  check "an async command enqueues while there is room" (fun () ->
      let q = Fpp_interp.empty_queue ~capacity:2 in
      match send ~queue:q 0 with
      | Ok (Fpp_interp.Enqueued q') -> q'.Fpp_interp.depth = 1
      | _ -> false);
  check "assert on a full queue is Assert_failed (a lost activity is a defect)"
    (fun () ->
      let q = { Fpp_interp.capacity = 2; depth = 2; dropped = 0 } in
      send ~queue:q 0 = Ok Fpp_interp.Assert_failed);
  check "drop on a full queue drops and counts" (fun () ->
      let q = { Fpp_interp.capacity = 2; depth = 2; dropped = 0 } in
      match send ~queue:q 1 with
      | Ok (Fpp_interp.Dropped q') ->
          q'.Fpp_interp.dropped = 1 && q'.Fpp_interp.depth = 2
      | _ -> false);
  check "block on a full queue blocks" (fun () ->
      let q = { Fpp_interp.capacity = 2; depth = 2; dropped = 0 } in
      send ~queue:q 2 = Ok Fpp_interp.Blocked);
  check "an async command without a queue is a caller error" (fun () ->
      match send 0 with Error _ -> true | Ok _ -> false);
  check "an unknown opcode is rejected (the CmdDispatcher law)" (fun () ->
      match send 99 with Error _ -> true | Ok _ -> false);
  check "an opcode below the base id is rejected" (fun () ->
      match Fpp_interp.send_command queued_model ~instance:"q1" ~opcode:5 ~queue:None with
      | Error _ -> true
      | Ok _ -> false);
  check "an unknown instance is rejected" (fun () ->
      match Fpp_interp.send_command queued_model ~instance:"ghost" ~opcode:0x1000 ~queue:None with
      | Error _ -> true
      | Ok _ -> false)

(* --------------------------------------------- the real ConvergeLoop walk *)

let converge_machine =
  List.find
    (function
      | Internal_machine m -> m.machine_name = "ConvergeLoop"
      | External_machine _ -> false)
    Harness_topology.model.machines

let () =
  check "ConvergeLoop: the OODA walk reaches Converged at the fixpoint" (fun () ->
      let ( >>= ) r f = match r with Ok v -> f v | Error e -> Error e in
      let result =
        Fpp_interp.init converge_machine
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "tick"
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "preflight_ok"
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine
          ~guards:[ ("frontier_advanced", true) ] s "progress"
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine
          ~guards:[ ("frontier_advanced", false) ] s "progress"
      in
      match result with
      | Ok s ->
          s.Fpp_interp.current = "Converged"
          && List.mem "observe" s.Fpp_interp.log
          && List.mem "act" s.Fpp_interp.log
          && List.mem "record" s.Fpp_interp.log
      | Error e ->
          print_endline ("  " ^ e);
          false);
  check "ConvergeLoop: R13 refusal walks to Blocked, and a later tick retries"
    (fun () ->
      let ( >>= ) r f = match r with Ok v -> f v | Error e -> Error e in
      let result =
        Fpp_interp.init converge_machine
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "tick"
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "preflight_refused"
        >>= fun s ->
        if s.Fpp_interp.current <> "Blocked" then Error "not Blocked"
        else Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "tick"
      in
      match result with
      | Ok s -> s.Fpp_interp.current = "Preflight"
      | Error _ -> false);
  check "ConvergeLoop: Anomalous is terminal and absorbing (exit 2, human reset)"
    (fun () ->
      let ( >>= ) r f = match r with Ok v -> f v | Error e -> Error e in
      let result =
        Fpp_interp.init converge_machine
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "tick"
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "preflight_ok"
        >>= fun s ->
        Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "anomaly"
        >>= fun s ->
        if s.Fpp_interp.current <> "Anomalous" then Error "not Anomalous"
        else Fpp_interp.dispatch ~machine:converge_machine ~guards:[] s "tick"
      in
      match result with
      | Ok s -> s.Fpp_interp.current = "Anomalous"
      | Error _ -> false)

let () =
  Printf.printf "fpp_interp: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_fpp_interp" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_fpp_interp ]);
  exit (Suite_telemetry.exit_code self)
