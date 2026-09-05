let passed = ref 0
let failed = ref 0
let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn -> incr failed; Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let () =
  check "A1 ontology has every kind and stable unique nodes" (fun () ->
      let kinds = Ops_governance_model.[ Declaration; Command; Surface; Activity; Receipt; Criterion; Metric; Model ] in
      let ids = List.map (fun (node : Ops_governance_model.node) -> node.node_id) Ops_governance_model.nodes in
      ids <> [] && List.length ids = List.length (List.sort_uniq compare ids)
      && List.for_all (fun kind -> List.exists (fun (node : Ops_governance_model.node) -> node.kind = kind) Ops_governance_model.nodes) kinds);
  check "A2 atlas edges are closed and total" (fun () -> Ops_governance_model.validate () = []);
  check "A3 every obligation has four surface paths to one criterion" (fun () ->
      List.for_all
        (fun (item : Ops_governance.obligation) ->
          List.length (Ops_governance_model.paths_to_criterion item.id) = 4)
        Ops_governance.obligations);
  check "L1 lifecycle is exactly an ordered four-state chain" (fun () ->
      let open Ops_capability in
      Ops_governance_model.lifecycle_leq Declared Current
      && Ops_governance_model.lifecycle_leq Implemented Executed
      && not (Ops_governance_model.lifecycle_leq Current Executed));
  check "P1 accepted L4-L6 differential evidence grants parity" (fun () ->
      Ops_governance_model.admit_parity ~level:Ops_capability.L4
        ~evidence:Differential ~origin:Evidence ~divergent:false = Grant);
  check "P2 only Implementation differential divergence denies parity" (fun () ->
      Ops_governance_model.admit_parity ~level:Ops_capability.L5
        ~evidence:Differential ~origin:Implementation ~divergent:true = Deny
      && Ops_governance_model.admit_parity ~level:L5
           ~evidence:Differential ~origin:Environment ~divergent:true = Block
      && Ops_governance_model.admit_parity ~level:L3
           ~evidence:Differential ~origin:Implementation ~divergent:true = Block);
  check "S1 surface homomorphism is equality of normalized receipts" (fun () ->
      let base =
        { Ops_command.request_id = "r"; action = "check"; scope = "whole-system";
          verdict = Succeeded; output = "ok"; digest = String.make 64 'a' }
      in
      Ops_governance_model.surface_homomorphism [ base; base; base; base ]
      && not (Ops_governance_model.surface_homomorphism [ base; { base with digest = String.make 64 'b' } ]));
  check "O1 Fast OODA is causal and closes with Observe" (fun () ->
      let open Ops_capability in
      Ops_governance_model.ooda_closed [ Observe; Orient; Decide; Act; Observe ]
      && not (Ops_governance_model.ooda_closed [ Observe; Orient; Decide; Act ])
      && not (Ops_governance_model.ooda_closed [ Observe; Decide; Orient; Act; Observe ]));
  check "D1 denominator is authored paths, not a Cartesian product" (fun () ->
      let actual = Ops_governance_model.semantic_denominator () in
      let expected =
        List.concat_map
          (fun (item : Ops_governance.obligation) ->
            List.map (fun coordinate -> (item.id, coordinate)) item.path)
          Ops_governance.obligations
      in
      actual = expected
      && List.length actual < List.length Ops_governance.obligations * 7 * 4);
  check "F1 formal model contains negated laws and a non-vacuous Sat control" (fun () ->
      let text = Ops_governance_model.formal_smt2 () in
      let contains needle =
        let n = String.length text and k = String.length needle in
        let rec loop i = i + k <= n && (String.sub text i k = needle || loop (i + 1)) in
        loop 0
      in
      contains "negated_surface_totality" && contains "negated_ooda_order"
      && contains "non_vacuous_sat_control" && contains "(check-sat)");

  Printf.printf "ops_governance_model: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_governance_model" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
