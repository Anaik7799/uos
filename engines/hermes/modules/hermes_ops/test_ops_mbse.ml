let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let contains text needle =
  let n = String.length text and k = String.length needle in
  let rec loop i = i + k <= n && (String.sub text i k = needle || loop (i + 1)) in
  k > 0 && loop 0

let () =
  let sysml = Ops_mbse.sysml_v2 () in
  let oml = Ops_mbse.oml_owl () in
  let mms = Ops_mbse.openmbee_mms () in
  check "MB1 SysML v2 is derived from the governance ontology" (fun () ->
      String.length sysml > 10_000
      && contains sysml "package HermesExecutableGovernance"
      && List.for_all
           (fun (item : Ops_governance.obligation) -> contains sysml item.id)
           Ops_governance.obligations);
  check "MB2 OML OWL carries every ontology node and typed relation" (fun () ->
      String.length oml > 10_000
      && contains oml "owl:Ontology"
      && List.for_all
           (fun (node : Ops_governance_model.node) -> contains oml node.node_id)
           Ops_governance_model.nodes);
  check "MB3 OpenMBEE MMS JSON has total stable elements and relationships" (fun () ->
      match Yojson.Safe.from_string mms with
      | exception Yojson.Json_error _ -> false
      | json ->
          begin match Yojson.Safe.Util.member "elements" json,
                      Yojson.Safe.Util.member "relationships" json with
          | `List elements, `List relationships ->
              List.length elements = List.length Ops_governance_model.nodes
              && List.length relationships = List.length Ops_governance_model.edges
          | _ -> false
          end);
  check "MB4 correspondence validation is closed and deterministic" (fun () ->
      Ops_mbse.validate () = []
      && sysml = Ops_mbse.sysml_v2 ()
      && oml = Ops_mbse.oml_owl ()
      && mms = Ops_mbse.openmbee_mms ());
  Printf.printf "ops_mbse: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_mbse" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)

