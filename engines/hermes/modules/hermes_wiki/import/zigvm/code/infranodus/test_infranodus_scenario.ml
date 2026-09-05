module Feature = Zigvm_harness_support.Infranodus_feature
module Scenario = Zigvm_harness_support.Infranodus_scenario

let require condition message = if not condition then failwith message

let () =
  require (List.length Scenario.feature_scenarios = 70) "one scenario per feature";
  require (List.length Scenario.workflows = 9) "nine cross-feature workflows";
  require
    (List.map Feature.id Feature.all = List.map Scenario.feature_id Scenario.feature_scenarios)
    "feature/scenario coverage homomorphism";
  List.iter
    (fun scenario ->
      require (List.length (Scenario.viewports scenario) = 4)
        (Scenario.id scenario ^ " must cover four canonical viewports");
      require (Scenario.has_screenshot scenario)
        (Scenario.id scenario ^ " has no screenshot checkpoint");
      require (Scenario.has_video scenario)
        (Scenario.id scenario ^ " has no video chapter");
      require (Scenario.has_state_expectation scenario)
        (Scenario.id scenario ^ " has no state expectation"))
    (Scenario.feature_scenarios @ Scenario.workflows);
  (match Scenario.validate (Scenario.feature_scenarios @ Scenario.workflows) with
  | Ok () -> ()
  | Error errors -> failwith (String.concat "; " errors));
  let manifest = Scenario.evidence_manifest Scenario.feature_scenarios in
  require (List.length manifest = 280) "70 features x four viewport evidence rows";
  let mutant = List.tl Scenario.feature_scenarios in
  require
    (match Scenario.validate_feature_coverage mutant with Error _ -> true | Ok () -> false)
    "missing-feature mutant must be killed";
  print_endline "infranodus scenario laws: pass (seed=7804, deterministic)"
