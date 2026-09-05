let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  let valid_intent =
    Nix_intent.Evaluate
      { target = Nix_intent.Raw_expression { expr = "1 + 1" };
        budget = Nix_budget.default;
        pure = true }
  in
  check "POL-1 valid intent is admitted"
    (Nix_policy.evaluate_intent valid_intent = Nix_policy.Admitted);

  let bad_budget =
    { Nix_budget.default with timeout_ms = -1 }
  in
  let invalid_budget_intent =
    Nix_intent.Evaluate
      { target = Nix_intent.Raw_expression { expr = "1 + 1" };
        budget = bad_budget;
        pure = true }
  in
  check "POL-2 invalid budget is rejected"
    (match Nix_policy.evaluate_intent invalid_budget_intent with
     | Nix_policy.Rejected (Nix_error.Policy_violation _) -> true
     | _ -> false);

  check "POL-3 sensitive paths outside sandbox are rejected"
    (Result.is_error (Nix_policy.check_path_sandbox "/etc/shadow")
     && Result.is_error (Nix_policy.check_path_sandbox "/root/.ssh/id_rsa")
     && Result.is_ok (Nix_policy.check_path_sandbox "/home/an/dev/project"));

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_policy"
