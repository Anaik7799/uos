(* The embedded Rust rule engine, end to end across the FFI, plus the
   DIFFERENTIAL admission test: the OCaml Hermes_rete engine is the reference,
   and both engines must reach the same conclusion over the same drift facts.
   Chaos: malformed GRL and malformed facts come back as Error, never a crash. *)

let member name json =
  match json with `Assoc fields -> List.assoc_opt name fields | _ -> None

let () =
  let open Rust_rules in
  assert (available ());

  (* A GRL rule fires over a fact and its then-action mutates the fact --
     observable in the returned facts (proven differential: the output depends
     on the rule actually running). *)
  let grl =
    {|rule FixCandidate "divergent drift needs a candidate fix" {
        when
            Drift.Actual == "divergent"
        then
            Drift.Advice = "fix-candidate";
    }|}
  in
  let facts drift_actual =
    `Assoc [ ("Drift", `Assoc [ ("Target", `String "hermes.agent_loop.interrupt_control");
                                ("Actual", `String drift_actual);
                                ("Advice", `String "none") ]) ]
  in
  (match eval ~grl ~facts:(facts "divergent") with
  | Ok result ->
      assert (result.rules_fired >= 1);
      (match member "Drift" result.facts with
      | Some drift -> assert (member "Advice" drift = Some (`String "fix-candidate"))
      | None -> failwith "Drift fact missing from reply")
  | Error e -> failwith ("divergent eval: " ^ e));

  (* The rule does NOT fire for a non-matching fact: advice stays "none". *)
  (match eval ~grl ~facts:(facts "verified") with
  | Ok result -> (
      assert (result.rules_fired = 0);
      match member "Drift" result.facts with
      | Some drift -> assert (member "Advice" drift = Some (`String "none"))
      | None -> failwith "Drift fact missing")
  | Error e -> failwith ("verified eval: " ^ e));

  (* DIFFERENTIAL admission: the OCaml engine over the same drift reaches the
     same conclusion. Same input, two independent engines, equal verdicts. *)
  let ocaml_advice drift_actual =
    let open Hermes_rete in
    let wm = WM.create () in
    WM.insert wm "drift" [ ("actual", Value.String drift_actual) ];
    let advice = ref "none" in
    let rule =
      { name = "FixCandidate";
        patterns =
          [ { pat_kind = "drift";
              conds = [ FieldCmp ("actual", Eq, Value.String "divergent") ];
              bind_name = None } ];
        action = (fun _ _ -> advice := "fix-candidate"; Ok ()) }
    in
    (match fire_rules wm [ rule ] with Ok () -> () | Error e -> failwith e);
    !advice
  in
  let rust_advice drift_actual =
    match eval ~grl ~facts:(facts drift_actual) with
    | Ok result -> (
        match member "Drift" result.facts with
        | Some drift -> (
            match member "Advice" drift with Some (`String s) -> s | _ -> "missing")
        | None -> "missing")
    | Error e -> "error:" ^ e
  in
  List.iter
    (fun actual -> assert (ocaml_advice actual = rust_advice actual))
    [ "divergent"; "verified"; "unmapped"; "blocked" ];

  (* Chaos. MEASURED FINDING (admission test, 2026-08-08): the crate ACCEPTS
     malformed GRL silently, loading zero rules -- fail-OPEN for a gate, since a
     typo'd rule simply vanishes. Pinned here so a future version that starts
     rejecting (better) or silently firing (worse) is noticed. MITIGATION: the
     OCaml Hermes_rete engine remains the authoritative fail-closed gate; this
     engine is advisory/differential only. *)
  (match eval ~grl:"rule Broken { when Nonsense then" ~facts:(facts "divergent") with
  | Ok r -> assert (r.rules_fired = 0)
  | Error _ -> () (* a rejecting parser would be an improvement, not a break *));
  (* Malformed facts ARE rejected -- by our wrapper, fail-closed. *)
  (match eval ~grl ~facts:(`String "not an object") with
  | Error _ -> ()
  | Ok _ -> failwith "malformed facts must be rejected");
  (* And the FFI boundary survives hostile content in fact values. *)
  (match
     eval ~grl
       ~facts:(`Assoc [ ("Drift", `Assoc [ ("Actual", `String "quote\"back\\slash\nnewline") ]) ])
   with
  | Ok _ | Error _ -> ());
  print_endline "rust_rules: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_rust_rules" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_rust_rules ]);
  exit (Suite_telemetry.exit_code self)
