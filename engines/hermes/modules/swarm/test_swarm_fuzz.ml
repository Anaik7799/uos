open QCheck
open Swarm_algebra
open Intent_config

let test_idempotent =
  Test.make ~name:"execute_job_idempotent is idempotent"
    (pair string string)
    (fun (job_id, payload) ->
       let res1 = execute_job_idempotent job_id payload in
       let res2 = execute_job_idempotent job_id payload in
       String.equal res1 res2)

let arb_intent = 
  QCheck.map (fun (target, constraints, capabilities, success_criteria) ->
    { target; constraints; capabilities; success_criteria; miq_routing = [] }
  ) QCheck.(tup4 string (list (pair string string)) (list string) (list string))

let test_dag_size =
  Test.make ~name:"synthesize_dag always returns 15 tasks"
    arb_intent
    (fun intent ->
       let dag = synthesize_dag intent in
       List.length dag = 15)

let () =
  let seed = Qcheck_seed.configure () in
  Qcheck_seed.disclose seed;
  let errcode = QCheck_runner.run_tests [
    test_idempotent;
    test_dag_size;
  ] in
  if errcode <> 0 then exit errcode;
  let self =
    Suite_telemetry.observe ~suite:"test_swarm_fuzz" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)
