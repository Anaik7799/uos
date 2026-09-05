[@@@ocaml.warning "-32"]
[@@@ocaml.warning "-37"]
(* modules/hermes_sysml/test_agent_bdd.ml *)
[@@@warning "-37"]
[@@@warning "-32"]
open OUnit2

type state = OBSERVE | ORIENT | DECIDE | ACT

type agent = {
  state : state;
  plan : string option;
}

let set_state agent state = { agent with state }

let generate_plan agent plan =
  match agent.state with
  | DECIDE -> { state = ACT; plan = Some plan }
  | _ -> agent

let state_to_string = function
  | OBSERVE -> "OBSERVE"
  | ORIENT -> "ORIENT"
  | DECIDE -> "DECIDE"
  | ACT -> "ACT"

let test_decide_to_act _ctxt =
  (* GIVEN an agent in DECIDE state *)
  let agent = { state = DECIDE; plan = None } in
  
  (* WHEN a plan is generated *)
  let updated_agent = generate_plan agent "new plan" in
  
  (* THEN it moves to ACT state *)
  assert_equal ~printer:state_to_string ACT updated_agent.state;
  assert_equal ~printer:(fun opt -> match opt with None -> "None" | Some s -> "Some " ^ s) (Some "new plan") updated_agent.plan

let suite =
  "Agent BDD Suite" >::: [
    "GIVEN agent in DECIDE WHEN plan generated THEN moves to ACT" >:: test_decide_to_act;
  ]

let () =
  run_test_tt_main suite;
  (* OUnit exits nonzero itself on failure; reaching here means success. *)
  let self = Suite_telemetry.observe ~suite:"test_agent_bdd" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_sysml ]);
  exit (Suite_telemetry.exit_code self)
