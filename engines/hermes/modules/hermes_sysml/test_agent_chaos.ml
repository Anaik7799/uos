[@@@warning "-32"]
open QCheck

type state = Observe | Orient | Decide | Act



type event =
  | ToolFired
  | FeedbackReceived
  | LatencyInjected of int
  | DroppedFeedback
  | OutOfOrderTool

let show_event = function
  | ToolFired -> "ToolFired"
  | FeedbackReceived -> "FeedbackReceived"
  | LatencyInjected ms -> Printf.sprintf "LatencyInjected(%d)" ms
  | DroppedFeedback -> "DroppedFeedback"
  | OutOfOrderTool -> "OutOfOrderTool"

type agent = {
  state: state;
}

let initial = { state = Observe }

let is_anomalous state ev =
  match state, ev with
  | Observe, FeedbackReceived -> false
  | Orient, ToolFired -> false
  | Decide, ToolFired -> false
  | Act, FeedbackReceived -> false
  | _, LatencyInjected ms when ms < 1000 -> false
  | _ -> true

let safety_kernel current ev =
  if is_anomalous current.state ev then
    { state = Observe }
  else
    match current.state, ev with
    | Observe, FeedbackReceived -> { state = Orient }
    | Orient, ToolFired -> { state = Decide }
    | Decide, ToolFired -> { state = Act }
    | Act, FeedbackReceived -> { state = Observe }
    | _, LatencyInjected _ -> current
    | _ -> { state = Observe }

let gen_event =
  Gen.oneof_weighted [
    (3, Gen.return ToolFired);
    (3, Gen.return FeedbackReceived);
    (2, Gen.map (fun ms -> LatencyInjected ms) (Gen.int_bound 2000));
    (1, Gen.return DroppedFeedback);
    (1, Gen.return OutOfOrderTool);
  ]

let event_arbitrary =
  make ~print:show_event gen_event

let test_safety_kernel_recovers =
  Test.make ~name:"Safety kernel always forces OBSERVE on anomaly"
    ~count:1000
    (list event_arbitrary)
    (fun events ->
       let rec loop agent = function
         | [] -> true
         | ev :: rest ->
             let next_agent = safety_kernel agent ev in
             if is_anomalous agent.state ev && next_agent.state <> Observe then
               false
             else
               loop next_agent rest
       in
       loop initial events)

let () =
  let seed = Qcheck_seed.configure () in
  Qcheck_seed.disclose seed;
  let code = QCheck_base_runner.run_tests [
    test_safety_kernel_recovers
  ] in
  let self = Suite_telemetry.observe ~suite:"test_agent_chaos" ~passed:(if code = 0 then 1 else 0) ~failed:code ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_sysml ]);
  exit (Suite_telemetry.exit_code self)
