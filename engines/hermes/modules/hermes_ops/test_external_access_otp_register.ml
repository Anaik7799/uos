open External_access_otp_register

let passed = ref 0
let failed = ref 0
let check name predicate =
  if predicate () then (incr passed; Printf.printf "PASS %s\n" name)
  else (incr failed; Printf.eprintf "FAIL %s\n" name)

let () =
  check "EA-OTP-REG-01 register has a nonempty closed denominator" (fun () ->
      List.length rows >= 20 && validate rows = []);
  check "EA-OTP-REG-02 all six production axes are represented" (fun () ->
      rows |> List.concat_map (fun row -> row.axes) |> List.sort_uniq compare
      = [ Behavior; Performance; Scalability; Reliability; Operability; Predictability ]);
  check "EA-OTP-REG-03 no row claims unmeasured equivalence or improvement" (fun () ->
      List.for_all (fun row -> match row.status with
        | Unmeasured | Reference_documented -> true
        | Differential_equivalent _ | Measured_improvement _ -> false) rows);
  check "EA-OTP-REG-04 every performance row pins disciplined measurement" (fun () ->
      rows |> List.filter (fun row -> List.mem Performance row.axes)
      |> List.for_all (fun row ->
           row.measurement.sample_count = 7
           && row.measurement.statistic = Median_with_mad
           && row.measurement.requires_same_host
           && row.measurement.requires_same_otp_pin));
  check "EA-OTP-REG-05 improvement hypotheses preserve compatibility" (fun () ->
      rows |> List.filter_map (fun row -> row.improvement)
      |> List.for_all (fun item -> item.compatibility_invariant <> ""
                        && item.proof_obligation_ids <> []));
  check "EA-OTP-REG-06 reference pin is exact and source-bound" (fun () ->
      reference.release = "30.0-rc0"
      && reference.commit = "679f9dbbc491d92e99fb08fd3f95fdbe9be30ec0"
      && reference.pin_file = "third_party/OTP30_PIN");
  check "EA-OTP-REG-07 source digest is SHA-256" (fun () ->
      String.length source_digest = 64);
  let self = Suite_telemetry.observe ~suite:"test_external_access_otp_register"
      ~passed:!passed ~failed:!failed ~skipped:0 in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n" !passed !failed;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
