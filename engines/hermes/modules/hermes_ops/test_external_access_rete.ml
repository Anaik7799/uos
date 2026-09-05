module R = Run_intelligence.Rete_ul

let checks = ref 0
let failures = ref 0
let check name condition =
  incr checks;
  if condition then Printf.printf "PASS %s\n" name
  else begin incr failures; Printf.eprintf "FAIL %s\n" name end

let provenance : Run_model.provenance =
  { source_revision = "external-access-rete"; source_clean = true;
    configuration_digest = String.make 64 'a'; authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let context () =
  match Run_safety.For_test.current_head_receipt ~run_id:"run-external-access-rete"
      ~provenance ~observed_at_ns:900L ~current_at_ns:1_000L ~expires_at_ns:2_000L with
  | Error issue -> failwith issue.Run_safety.message
  | Ok current_head ->
      match Run_safety.make_gate_context ~current_head
          ~request_id:"request-external-access-rete"
          ~activity_id:"activity.decide-intent"
          ~coordinate:{ Ops_capability.level = Ops_capability.L2; phase = Ops_capability.Decide }
          ~plane:Ops_capability.Control_plane with
      | Ok value -> value
      | Error issue -> failwith issue.Run_safety.message

let budgets : R.budgets =
  { max_facts = 8; max_alpha_entries = 32; max_beta_tokens = 32;
    max_agenda = 16; max_firings = 16; max_trace_entries = 16 }

let network : R.network =
  { network_id = "network.external-access-admission"; budgets;
    rules =
      [ { rule_id = "rule.external-access.block-unsafe"; salience = 100;
          patterns =
            [ { pattern_id = "pattern.external-access-unsafe";
                fact_kind = "external-access-intent";
                conditions = [ R.Field_eq ("unsafe", R.Bool true) ] } ];
          actions = [ R.Block_rhs "external-access invariant refused" ] } ] }

let fact id unsafe =
  R.make_fact ~fact_id:id ~fact_kind:"external-access-intent"
    ~attrs:
      [ "unsafe", R.Bool unsafe; "validated", R.Bool (not unsafe);
        "authorized", R.Bool (not unsafe); "bounded", R.Bool (not unsafe);
        "fpp_total", R.Bool (not unsafe); "bridge_only", R.Bool (not unsafe) ]

let () =
  let context = context () in
  let safe = match fact "intent.safe" false with Ok item -> item | Error detail -> failwith detail in
  let unsafe = match fact "intent.unsafe" true with Ok item -> item | Error detail -> failwith detail in
  let safe_outcome = R.static_outcome context network [ safe ] in
  let unsafe_outcome = R.static_outcome context network [ unsafe ] in
  check "EA-RETE-01 safe intent reaches fixed-point accept"
    (safe_outcome = Ok R.Static_accept);
  check "EA-RETE-02 unsafe intent reaches absorbing block"
    (unsafe_outcome = Ok R.Static_block);
  check "EA-RETE-03 independent Hermes_rete oracle agrees"
    (R.hermes_rete_static_outcome network [ safe ] = Ok R.Static_accept
     && R.hermes_rete_static_outcome network [ unsafe ] = Ok R.Static_block);
  check "EA-RETE-04 compiled replay produces current fixed-point receipt"
    (match R.compile context network with
     | Error _ -> false
     | Ok compiled ->
         match R.replay context compiled [ R.Assert_fact safe ] with
         | Error _ -> false
         | Ok (_, receipt) -> Result.is_ok (R.validate_receipt ~context receipt));
  check "EA-RETE-05 exact dispatch admission requires accepted receipt"
    (match R.compile context network with
     | Error _ -> false
     | Ok compiled ->
         match R.replay context compiled [ R.Assert_fact safe ] with
         | Error _ -> false
         | Ok (_, receipt) -> Result.is_ok (R.admit_dispatch context ~network ~facts:[ safe ] receipt));
  check "EA-RETE-06 blocked receipt cannot admit dispatch"
    (match R.compile context network with
     | Error _ -> false
     | Ok compiled ->
         match R.replay context compiled [ R.Assert_fact unsafe ] with
         | Error _ -> true
         | Ok (_, receipt) -> Result.is_error (R.admit_dispatch context ~network ~facts:[ unsafe ] receipt));
  let tiny = { network with budgets = { budgets with max_facts = 1 } } in
  check "EA-RETE-07 fact budget fails closed"
    (match R.compile context tiny with
     | Error _ -> false
     | Ok compiled ->
         Result.is_error
           (R.replay context compiled [ R.Assert_fact safe; R.Assert_fact unsafe ]));
  let self = Suite_telemetry.observe ~suite:"test_external_access_rete"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0 in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n"
    (!checks - !failures) !failures;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
