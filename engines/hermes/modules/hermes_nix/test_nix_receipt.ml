let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  let intent =
    Nix_intent.Evaluate
      { target = Nix_intent.Raw_expression { expr = "42" };
        budget = Nix_budget.default;
        pure = true }
  in
  let receipt =
    Nix_receipt_core.make
      ~intent
      ~duration_ms:150
      ~output_paths:[]
      ~closure_digest:None
      ~summary:"Evaluated 42"
      ~verdict:Nix_receipt_core.Success
  in
  check "RCPT-1 receipt is successful" (Nix_receipt_core.is_success receipt);
  check "RCPT-2 receipt ID is non-empty"
    (String.length (Nix_id.Receipt_id.to_string receipt.receipt_id) > 0);
  check "RCPT-3 timestamp follows YYYYMMDD-HHSS format"
    (let ts = receipt.timestamp in
     String.length ts = 13 && ts.[8] = '-');

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_receipt"
