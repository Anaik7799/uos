(* The mirrored rule engine: matching, binding joins across fact kinds, and the
   fail-closed gate (an Error action rejects the run, naming the rule). Also the
   diagnosis pattern: an action that INSERTS facts, so rules can produce advice. *)

let () =
  let open Hermes_rete in
  let contains n h =
    let hl = String.length h and nl = String.length n in
    let rec f i = i + nl <= hl && (String.sub h i nl = n || f (i + 1)) in
    f 0
  in
  let wm = WM.create () in
  WM.insert wm "drift" [ ("target", Value.String "hermes.a.b"); ("actual", Value.String "divergent") ];
  WM.insert wm "drift" [ ("target", Value.String "hermes.c.d"); ("actual", Value.String "unmapped") ];
  WM.insert wm "hazard" [ ("id", Value.String "HZ-X"); ("realises_h1", Value.Bool true) ];
  WM.insert wm "countermeasure" [ ("hazard", Value.String "HZ-X"); ("auto", Value.Bool false) ];

  (* FieldCmp filters within a kind. *)
  assert (List.length (WM.get_by_kind wm "drift") = 2);
  let divergent_only =
    { name = "divergent-drifts-diagnose";
      patterns =
        [ { pat_kind = "drift";
            conds = [ FieldCmp ("actual", Eq, Value.String "divergent");
                      VarBind ("t", "target") ];
            bind_name = Some "d" } ];
      action =
        (fun wm named ->
          assert (List.mem_assoc "d" named);
          WM.insert wm "diagnosis" [ ("kind", Value.String "fix-candidate") ];
          Ok ()) }
  in
  (match fire_rules wm [ divergent_only ] with
  | Ok () -> ()
  | Error e -> failwith e);
  (* Exactly one divergent drift -> exactly one diagnosis inserted. *)
  assert (List.length (WM.get_by_kind wm "diagnosis") = 1);

  (* VarCmp joins across kinds: a hazard bound in one pattern joined to the
     countermeasure that names it. *)
  let joined = ref 0 in
  let join_rule =
    { name = "hazard-has-countermeasure";
      patterns =
        [ { pat_kind = "hazard"; conds = [ VarBind ("h", "id") ]; bind_name = None };
          { pat_kind = "countermeasure"; conds = [ VarCmp ("hazard", Eq, "h") ];
            bind_name = Some "cm" } ];
      action = (fun _ named -> assert (List.mem_assoc "cm" named); incr joined; Ok ()) }
  in
  (match fire_rules wm [ join_rule ] with Ok () -> () | Error e -> failwith e);
  assert (!joined = 1);

  (* The fail-closed gate: an Error action rejects the run, naming the rule. *)
  let gate =
    { name = "no-unmapped-drift-allowed";
      patterns =
        [ { pat_kind = "drift";
            conds = [ FieldCmp ("actual", Eq, Value.String "unmapped") ];
            bind_name = None } ];
      action = (fun _ _ -> Error "an unmapped drift is present") }
  in
  (match fire_rules wm [ gate ] with
  | Error message ->
      assert (contains "no-unmapped-drift-allowed" message)
  | Ok () -> failwith "the gate must reject");

  (* StartsWith operator works (target prefix matching). *)
  let prefixed = ref 0 in
  let prefix_rule =
    { name = "hermes-targets-only";
      patterns =
        [ { pat_kind = "drift";
            conds = [ FieldCmp ("target", StartsWith, Value.String "hermes.") ];
            bind_name = None } ];
      action = (fun _ _ -> incr prefixed; Ok ()) }
  in
  (match fire_rules wm [ prefix_rule ] with Ok () -> () | Error e -> failwith e);
  assert (!prefixed = 2);

  (* Constitutional Invariant Gates (Psi-6, Psi-7, Psi-9) *)
  WM.insert wm "storage_request" [ ("serial", Value.String "25503L801736"); ("action", Value.String "osd_wipe") ];
  WM.insert wm "provenance_claim" [ ("ev_cycle", Value.Int 108); ("source", Value.String "quarantined_event_437") ];
  WM.insert wm "task_execution" [ ("task_id", Value.String "ad_hoc_task"); ("has_sa_plan_lease", Value.Bool false) ];

  let psi6_gate =
    { name = "psi6-hardware-inviolability-gate";
      patterns =
        [ { pat_kind = "storage_request";
            conds = [ FieldCmp ("serial", Eq, Value.String "25503L801736");
                      FieldCmp ("action", Eq, Value.String "osd_wipe") ];
            bind_name = None } ];
      action = (fun _ _ -> Error "Psi-6 Violation: OS root NVMe drive 25503L801736 cannot be wiped") }
  in
  (match fire_rules wm [ psi6_gate ] with
  | Error msg -> assert (contains "Psi-6 Violation" msg)
  | Ok () -> failwith "Psi-6 gate must reject");

  let psi7_gate =
    { name = "psi7-provenance-ceiling-gate";
      patterns =
        [ { pat_kind = "provenance_claim";
            conds = [ FieldCmp ("source", Eq, Value.String "quarantined_event_437") ];
            bind_name = None } ];
      action = (fun _ _ -> Error "Psi-7 Violation: EV cycles above EV-93 ceiling originate in quarantined events") }
  in
  (match fire_rules wm [ psi7_gate ] with
  | Error msg -> assert (contains "Psi-7 Violation" msg)
  | Ok () -> failwith "Psi-7 gate must reject");

  let psi9_gate =
    { name = "psi9-sa-plan-exclusivity-gate";
      patterns =
        [ { pat_kind = "task_execution";
            conds = [ FieldCmp ("has_sa_plan_lease", Eq, Value.Bool false) ];
            bind_name = None } ];
      action = (fun _ _ -> Error "-32002: Fractal Jidoka Andon Halt: Non-sa-plan task execution attempted") }
  in
  (match fire_rules wm [ psi9_gate ] with
  | Error msg -> assert (contains "-32002" msg)
  | Ok () -> failwith "Psi-9 gate must reject");

  print_endline "hermes_rete: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_hermes_rete" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_hermes_rete ]);
  exit (Suite_telemetry.exit_code self)
