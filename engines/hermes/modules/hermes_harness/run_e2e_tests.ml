let () =
  (* Register framework sanity check test *)
  E2e_framework.register_test {
    id = "framework.sanity";
    name = "E2E Framework Preflight & Infrastructure Sanity Check";
    tier = E2e_framework.Tier1_Feature;
    feature = "e2e_framework";
    run = (fun () -> E2e_framework.Pass);
  };
  (* Initialize & register Tier 1, Tier 2, Tier 3 & Tier 4 E2E test suites *)
  E2e_tier1_tests.register_all ();
  E2e_tier2_tests.register_all ();
  ignore (E2e_tier3_tests.register_all ());
  ignore (E2e_tier4_tests.register_all ());
  let code = E2e_framework.run_all () in
  exit code
