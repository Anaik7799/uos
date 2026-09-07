(* test_gospel_dispatch_contracts.ml — Unit and differential tests for Gospel contracts (EV-107) *)

let test_valid_payload () =
  let payload = "{\"tool\":\"read_file\",\"args\":{\"path\":\"/home/an/doc.txt\"}}" in
  match Gospel_dispatch_contracts.validate_dispatch_contract payload with
  | Gospel_dispatch_contracts.Pass { digest; _ } ->
      assert (String.length digest = 64);
      print_endline "PASS: Valid payload contract satisfied"
  | Gospel_dispatch_contracts.FailClosed _ ->
      failwith "FAIL: Valid payload unexpectedly rejected"

let test_nul_byte_trapping () =
  let payload = "{\"tool\":\"eval\",\"code\":\"print(\x00)\"}" in
  match Gospel_dispatch_contracts.validate_dispatch_contract payload with
  | Gospel_dispatch_contracts.FailClosed { error_code; _ } ->
      assert (error_code = -2);
      print_endline "PASS: Embedded NUL byte trapped (code -2)"
  | Gospel_dispatch_contracts.Pass _ ->
      failwith "FAIL: NUL byte was not trapped"

let test_sql_injection_rejection () =
  let payload = "{\"query\":\"SELECT * FROM users; DROP TABLE users;\"}" in
  match Gospel_dispatch_contracts.validate_dispatch_contract payload with
  | Gospel_dispatch_contracts.FailClosed { error_code; _ } ->
      assert (error_code = -3);
      print_endline "PASS: SQL injection trapped (code -3)"
  | Gospel_dispatch_contracts.Pass _ ->
      failwith "FAIL: SQL injection was not trapped"

let test_differential_oracle_parity () =
  let payload_good = "{\"tool\":\"system_health\"}" in
  (match Gospel_dispatch_contracts.bounded_differential_oracle payload_good "" with
   | Ok true -> print_endline "PASS: Differential oracle parity verified on clean payload"
   | _ -> failwith "FAIL: Differential oracle discrepancy on clean payload");

  let payload_bad = "{\"tool\":\"exec\",\"cmd\":\"ls\x00-la\"}" in
  (match Gospel_dispatch_contracts.bounded_differential_oracle payload_bad "" with
   | Ok true -> print_endline "PASS: Differential oracle parity verified on malicious payload"
   | _ -> failwith "FAIL: Differential oracle discrepancy on malicious payload")

let () =
  print_endline "=== Hermes Gospel Dispatch Contracts Test Suite ===";
  test_valid_payload ();
  test_nul_byte_trapping ();
  test_sql_injection_rejection ();
  test_differential_oracle_parity ();
  print_endline "ALL 4 GOSPEL CONTRACT TESTS PASSED"
