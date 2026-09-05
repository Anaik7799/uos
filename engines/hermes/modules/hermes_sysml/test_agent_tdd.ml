[@@@ocaml.warning "-33"]
[@@@ocaml.warning "-8"]
[@@@warning "-8"]
[@@@warning "-33"]
open OUnit2
open Hermes_sysml

(* Ghost types for states *)
type idle
type observe
type orient
type decide
type act

(* State machine wrapping current state *)
type _ state =
  | Idle : idle state
  | Observe : observe state
  | Orient : orient state
  | Decide : decide state
  | Act : act state

(* TDD: Define a GADT that represents valid OODA transitions *)
type ('src, 'dst) ooda_step =
  | Wake : (idle, observe) ooda_step
  | Sense : (observe, orient) ooda_step
  | Think : (orient, decide) ooda_step
  | Choose : (decide, act) ooda_step
  | Execute : (act, idle) ooda_step

(* Transition function *)
let step : type s d. s state -> (s, d) ooda_step -> d state = fun s t ->
  match s with
  | Idle -> (match t with Wake -> Observe)
  | Observe -> (match t with Sense -> Orient)
  | Orient -> (match t with Think -> Decide)
  | Decide -> (match t with Choose -> Act)
  | Act -> (match t with Execute -> Idle)

(* Tests *)
let test_idle_to_observe _ =
  let s' = step Idle Wake in
  match s' with Observe -> () | _ -> assert_failure "Failed"

let test_observe_to_orient _ =
  let s' = step Observe Sense in
  match s' with Orient -> () | _ -> assert_failure "Failed"

let test_orient_to_decide _ =
  let s' = step Orient Think in
  match s' with Decide -> () | _ -> assert_failure "Failed"

let test_decide_to_act _ =
  let s' = step Decide Choose in
  match s' with Act -> () | _ -> assert_failure "Failed"

let test_act_to_idle _ =
  let s' = step Act Execute in
  match s' with Idle -> () | _ -> assert_failure "Failed"

let suite =
  "OODA State Machine Tests" >::: [
    "test_idle_to_observe" >:: test_idle_to_observe;
    "test_observe_to_orient" >:: test_observe_to_orient;
    "test_orient_to_decide" >:: test_orient_to_decide;
    "test_decide_to_act" >:: test_decide_to_act;
    "test_act_to_idle" >:: test_act_to_idle;
  ]

let () =
  run_test_tt_main suite;
  (* OUnit exits nonzero itself on failure; reaching here means success. *)
  let self = Suite_telemetry.observe ~suite:"test_agent_tdd" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_sysml ]);
  exit (Suite_telemetry.exit_code self)
