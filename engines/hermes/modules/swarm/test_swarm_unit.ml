open Swarm_ontology
open Swarm_memory
open Swarm_fpp
open Intent_config

let test_working_memory () =
  print_endline "=== Test 1: Swarm Memory (Working_Memory) CRDT Push/Clear ===";
  let mem = Working_Memory.clear () in
  let frame1 : Working_Memory.context_frame = {
    active_agent = Agent_1;
    current_layer = L0_product;
    local_state = "initial";
  } in
  let mem = Working_Memory.push frame1 mem in
  assert (List.length mem = 1);
  let frame2 : Working_Memory.context_frame = {
    active_agent = Agent_2;
    current_layer = L1_subsystem;
    local_state = "processing";
  } in
  let mem = Working_Memory.push frame2 mem in
  assert (List.length mem = 2);
  let hd = List.hd mem in
  assert (hd.active_agent = Agent_2);
  let mem = Working_Memory.clear () in
  assert (List.length mem = 0);
  print_endline "  [PASS] Working Memory pushes and clears successfully."

let test_fpp_routing () =
  print_endline "\n=== Test 2: Swarm FPP Port Routing ===";
  let intent : Intent_config.t = {
    target = "test target";
    constraints = [];
    capabilities = [];
    success_criteria = [];
    miq_routing = [];
  } in
  
  (* Test STPA *)
  let stpa_out = FPP_STPA.validate (Sync_input intent) in
  (match stpa_out with
   | Output msgs -> assert (List.hd msgs = "Safety constraint 1: Mutex locked")
   | _ -> assert false);
  print_endline "  [PASS] FPP_STPA routing verified.";

  (* Test Fast_OODA *)
  let telemetry : telemetry_node = { layer = L0_product; agent = Agent_1; digest = "abc" } in
  let ooda_out = FPP_Fast_OODA.cycle_loop (Sync_input telemetry) intent in
  (match ooda_out with
   | Output out_intent -> assert (out_intent.target = "test target")
   | _ -> assert false);
  print_endline "  [PASS] FPP_Fast_OODA routing verified.";

  (* Test Raven *)
  let raven_out = FPP_Raven.synthesize (Sync_input "problem") in
  (match raven_out with
   | Output res -> assert (res = "Resolved via Raven matrices")
   | _ -> assert false);
  print_endline "  [PASS] FPP_Raven routing verified.";

  (* Test Ruliad *)
  let ruliad_out = FPP_Ruliad.search_rule_space (Sync_input "space") in
  (match ruliad_out with
   | Output res -> assert (res = "Rule 110 Extracted")
   | _ -> assert false);
  print_endline "  [PASS] FPP_Ruliad routing verified.";
  ()

let () =
  test_working_memory ();
  test_fpp_routing ();
  print_endline "\nAll unit tests passed successfully.";
  let self =
    Suite_telemetry.observe ~suite:"test_swarm_unit" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)
