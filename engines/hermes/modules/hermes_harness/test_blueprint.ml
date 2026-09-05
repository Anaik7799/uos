(* A blueprint declares intended state; reconcile diffs it against reality. The
   tests cover validation (vacuous intent, duplicate id, unresolved requirement,
   cycle), dependency ordering, and reconciliation (satisfied vs drift, and that a
   drift's diagnostic carries the right fractal origin). *)

let d ~id ?(requires = []) ?(desired = Parity_algebra.Verified) intent =
  Blueprint.{ id; target = id ^ ".target"; desired; intent; requires }

let () =
  let open Blueprint in
  (* A well-formed blueprint validates and orders by dependency. *)
  let good =
    [ d ~id:"transports" "the provider transport must match the frozen reference wire";
      d ~id:"budget" ~requires:[ "transports" ]
        "the iteration budget must match the frozen IterationBudget exactly" ]
  in
  assert (validate good = Ok ());
  (match order good with
  | Ok [ "transports"; "budget" ] -> ()
  | Ok other -> failwith ("unexpected order: " ^ String.concat "," other)
  | Error _ -> failwith "good blueprint should order");

  (* Validation catches each defect. *)
  (match validate [ d ~id:"x" "short" ] with
  | Error errors -> assert (List.mem (Vacuous_intent "x") errors)
  | Ok () -> failwith "vacuous intent must fail");
  (match validate [ d ~id:"x" "a perfectly substantive intent here";
                    d ~id:"x" "another perfectly substantive intent here" ] with
  | Error errors -> assert (List.mem (Duplicate_id "x") errors)
  | Ok () -> failwith "duplicate id must fail");
  (match validate [ d ~id:"a" ~requires:[ "ghost" ] "a substantive intent about a" ] with
  | Error errors ->
      assert (List.mem (Unresolved_requirement { directive = "a"; missing = "ghost" }) errors)
  | Ok () -> failwith "unresolved requirement must fail");
  (match
     validate
       [ d ~id:"a" ~requires:[ "b" ] "a substantive intent about a";
         d ~id:"b" ~requires:[ "a" ] "a substantive intent about b" ]
   with
  | Error errors -> assert (List.exists (function Cycle _ -> true | _ -> false) errors)
  | Ok () -> failwith "a cycle must fail");

  (* Target resolution (the ontology/catalog alignment check): with a resolver,
     an intent about a node the fractal does not contain fails Unknown_target. *)
  (match
     validate
       ~resolve:(fun target -> target = "transports.target")
       [ d ~id:"transports" "the provider transport must match the frozen reference wire";
         d ~id:"ghostly" "a substantive intent about a missing node" ]
   with
  | Error errors ->
      assert (List.mem (Unknown_target { directive = "ghostly"; target = "ghostly.target" }) errors)
  | Ok () -> failwith "an unresolvable target must fail");
  assert (validate ~resolve:(fun _ -> true) good = Ok ());

  (* Reconciliation: satisfied where actual meets desired, drift otherwise. *)
  let actual_all_but_budget target =
    if target = "budget.target" then Parity_algebra.Divergent else Parity_algebra.Verified
  in
  let reconciled = reconcile good ~actual:actual_all_but_budget in
  let by id = List.find (fun r -> r.directive.id = id) reconciled in
  assert ((by "transports").outcome = Satisfied);
  assert ((by "transports").diagnostic = None);
  (match (by "budget").outcome with
  | Drift { desired = Parity_algebra.Verified; actual = Parity_algebra.Divergent } -> ()
  | _ -> failwith "budget should drift");
  (* A Divergent drift is an Implementation/Denies fractal diagnostic. *)
  (match (by "budget").diagnostic with
  | Some diag ->
      assert (diag.Fractal_diagnostic.origin = Fractal_diagnostic.Implementation);
      assert (diag.Fractal_diagnostic.impact = Fractal_diagnostic.Denies_credit)
  | None -> failwith "a drift must carry a diagnostic");
  assert (not (converged reconciled));

  (* When everything meets intent, the loop has converged. *)
  let all = reconcile good ~actual:(fun _ -> Parity_algebra.Verified) in
  assert (converged all);
  assert (List.for_all (fun r -> r.diagnostic = None) all);
  assert (String.length (summary reconciled) > 0);
  assert (String.length (render good) > 0);
  print_endline "blueprint: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_blueprint" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_blueprint ]);
  exit (Suite_telemetry.exit_code self)
