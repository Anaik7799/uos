let passed = ref 0
let failed = ref 0
let check name condition =
  if condition then incr passed else (incr failed; Printf.printf "FAILED: %s\n" name)

let coordinate = Ops_capability.{ level = L2; phase = Observe }
let observation id digest = Debug_ontology.{
  observation_id = id; statement = "measured evidence"; coordinate;
  rca_origin = Ops_capability.Evidence; status = Fresh;
  observed_at_ns = 10L; evidence_digest = digest }

let () =
  check "D01 registry has the exact nine codebase debugging intents"
    (List.length Debug_intent.all = 9);
  check "D02 registry identifiers are unique and validation is clean"
    (Debug_intent.validate Debug_intent.all = []);
  check "D03 all intents author a nonempty semantic path and four surfaces"
    (List.for_all (fun (item : Debug_intent.t) ->
       item.path <> [] && List.length item.surfaces = 4) Debug_intent.all);
  check "D04 every intent has competing hypotheses and a discriminator"
    (List.for_all (fun (item : Debug_intent.t) ->
       List.length item.hypotheses >= 2
       && item.next_measurement.hypothesis_ids
          = List.map (fun (h : Debug_ontology.hypothesis) -> h.hypothesis_id) item.hypotheses)
       Debug_intent.all);
  check "D05 dependability envelopes are bounded and non-vacuous"
    (List.for_all (fun (item : Debug_intent.t) -> Debug_dependability.validate item.dependability = []) Debug_intent.all);
  let a = observation "a" (String.make 64 'a') in
  let b = observation "b" (String.make 64 'b') in
  let union left right = Debug_algebra.evidence_union left right in
  check "D06 evidence union is commutative idempotent and has identity"
    (union [a] [b] = union [b] [a] && union [a] [a] = [a]
     && union [] [a] = [a] && union [a] [] = [a]);
  check "D07 evidence union is associative"
    (union (union [a] [b]) [a] = union [a] (union [b] [a]));
  let hypotheses = match Debug_intent.all with [] -> [] | item :: _ -> item.hypotheses in
  check "D08 counterevidence elimination is monotone"
    (match hypotheses with
     | first :: _ ->
         let survivors = Debug_algebra.eliminate hypotheses [first.hypothesis_id] in
         List.length survivors < List.length hypotheses
         && not (List.mem first survivors)
     | [] -> false);
  check "D09 conservative verdict join cannot hide blockers"
    (Debug_algebra.join_verdict Debug_algebra.Closed Stale = Stale
     && Debug_algebra.join_verdict Verified Closed = Verified);
  check "D10 only Implementation origin denies parity"
    (List.map Debug_algebra.failure_effect
       [ Ops_capability.Specification; Implementation; Environment; Evidence; Control ]
     = [ Blocks_credit; Denies_credit; Blocks_credit; Blocks_credit; Blocks_credit ]);
  List.iter (fun (name, mutation) ->
    check ("NEGATIVE CONTROL: " ^ name)
      (Debug_intent.For_test.mutate mutation |> Debug_intent.validate <> []))
    [ ("missing intent", Debug_intent.For_test.Drop_first);
      ("duplicate intent", Duplicate_first);
      ("empty symptom", Empty_symptoms);
      ("direct corrective effect", Direct_effect);
      ("unbounded dependable test", Unbounded_test);
      ("collapsed hypotheses", Collapse_hypotheses) ];
  begin match Debug_intent.all with
  | [] -> check "D11 protocol executes the causal typed path" false
  | intent :: _ ->
      let declared = Debug_protocol.declare intent in
      check "D11 empty observation is refused"
        (Result.is_error (Debug_protocol.observe declared []));
      check "D12 correction is reachable only after discrimination"
        (match Debug_protocol.observe declared [a] with
         | Error _ -> false
         | Ok observed ->
             match Debug_protocol.orient observed with
             | Error _ -> false
             | Ok oriented ->
                 match Debug_protocol.hypothesize oriented ~mechanical_proof:false intent.hypotheses with
                 | Error _ -> false
                 | Ok hypothesized ->
                     match Debug_protocol.discriminate hypothesized intent.next_measurement
                             ~eliminated:[(List.hd intent.hypotheses).hypothesis_id] with
                     | Error _ -> false
                     | Ok discriminated ->
                         Result.is_ok (Debug_protocol.correct discriminated
                           ~correction_id:"correction.test" ~via_bridge:true))
      end;
  Printf.printf "debug_system: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_debug_system"
      ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
