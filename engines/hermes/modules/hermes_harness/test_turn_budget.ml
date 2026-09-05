let () =
  let open Turn_budget in
  let initial = create 2 in
  assert (remaining initial = 2);
  let first = consume initial in
  assert (first.allowed);
  assert (used first.budget = 1);
  let second = consume first.budget in
  assert (second.allowed);
  let exhausted = consume second.budget in
  assert (not exhausted.allowed);
  assert (used exhausted.budget = 2);
  let refunded = refund exhausted.budget in
  assert (used refunded = 1);
  assert (remaining refunded = 1);
  assert (refund (create 0) = create 0);
  (* Faithful to the frozen IterationBudget: a negative cap is CARRIED, not
     clamped -- consume is refused (used >= max_total), used stays 0, remaining
     clamps to 0 only in the REPORT (max 0 (maximum - consumed)), exactly the
     reference semantics pinned in fixtures/reference_traces/budget.negative. *)
  let negative = create (-5) in
  assert (negative.maximum = -5);
  let refused = consume negative in
  assert (not refused.allowed);
  assert (used refused.budget = 0);
  assert (remaining negative = 0);
  assert (refund negative = negative)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_turn_budget" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_turn_budget ]);
  exit (Suite_telemetry.exit_code self)
