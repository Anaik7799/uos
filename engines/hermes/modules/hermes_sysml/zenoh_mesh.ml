[@@@ocaml.warning "-34"]
[@@@ocaml.warning "-8"]
[@@@warning "-8"]
[@@@warning "-34"]
(* Zenoh mesh integration mock for HermesAgent *)

module ZenohMock = struct
  type session = { id : string }
  type publisher = { topic : string }

  let connect () =
    print_endline "Connecting to Zenoh mesh...";
    { id = "mock-session" }

  let declare_subscriber _session topic _callback =
    Printf.printf "[Zenoh] Declared subscriber on topic: %s\n" topic;
    ()

  let declare_publisher _session topic =
    Printf.printf "[Zenoh] Declared publisher on topic: %s\n" topic;
    { topic }

  let put publisher data =
    Printf.printf "[Zenoh] Publishing to %s: %s\n" publisher.topic data
end

type idle
type observe
type orient
type decide
type act

type _ state =
  | Idle : idle state
  | Observe : observe state
  | Orient : orient state
  | Decide : decide state
  | Act : act state

type any_state = Any : 's state -> any_state

type ('src, 'dst) ooda_step =
  | Wake : (idle, observe) ooda_step
  | Sense : string -> (observe, orient) ooda_step
  | Think : (orient, decide) ooda_step
  | Choose : (decide, act) ooda_step
  | Execute : string -> (act, idle) ooda_step

let step : type s d. s state -> (s, d) ooda_step -> d state = fun s t ->
  match s, t with
  | Idle, Wake -> Observe
  | Observe, Sense _data -> Orient
  | Orient, Think -> Decide
  | Decide, Choose -> Act
  | Act, Execute _cmd -> Idle
  | _ -> assert false

let telemetry_topic = "hermes/telemetry"
let command_topic = "hermes/commands"

let run_agent () =
  let session = ZenohMock.connect () in
  let pub = ZenohMock.declare_publisher session command_topic in
  
  let _sub = ZenohMock.declare_subscriber session telemetry_topic (fun data ->
    Printf.printf "Received telemetry: %s\n" data;
  ) in

  let run_iterations iters =
    let rec go i (Any s) =
      if i = 0 then ()
      else
        match s with
        | Idle -> 
            print_endline "[Agent] Idle. Waking up...";
            go (i - 1) (Any (step Idle Wake))
        | Observe ->
            print_endline "[Agent] Observing. Reading telemetry...";
            let data = "mock_telemetry_data" in
            go (i - 1) (Any (step Observe (Sense data)))
        | Orient ->
            print_endline "[Agent] Orienting.";
            go (i - 1) (Any (step Orient Think))
        | Decide ->
            print_endline "[Agent] Deciding.";
            go (i - 1) (Any (step Decide Choose))
        | Act ->
            let cmd = "execute_action_mock" in
            print_endline "[Agent] Acting.";
            ZenohMock.put pub cmd;
            go (i - 1) (Any (step Act (Execute cmd)))
    in
    go iters (Any Idle)
  in
  run_iterations 10

let () =
  print_endline "Starting HermesAgent Zenoh Mesh Integration...";
  run_agent ()
