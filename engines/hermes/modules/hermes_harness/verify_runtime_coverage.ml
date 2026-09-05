(* Runtime anchor coverage: trace build_kwargs under sys.settrace for a few
   request scenarios, aggregate the executed frozen-relative files, and map them
   to capability anchors -- which anchors are exercised at runtime vs not (an
   honest coverage meter, the zigvm framing). Reuses the trace_execution adapter
   via Reference_capture, Runtime_coverage, and the catalog. *)

let executed_of_trace trace =
  match trace with
  | `Assoc fields -> (
      match List.assoc_opt "executed" fields with
      | Some (`List items) ->
          List.filter_map (function `String s -> Some s | _ -> None) items
      | _ -> [])
  | _ -> []

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let reference_root = Bootstrap.reference_root root in
  let snapshot =
    match Inventory.scan ~root:reference_root with
    | Ok entries -> Inventory.snapshot_digest entries
    | Error message -> prerr_endline message; exit 1
  in
  let normalizer = Parity_normalizer.default in
  let scenarios : Reference_capture.scenario list =
    [ { id = "chat.minimal"; model = "openai/gpt-5.4";
        messages = [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
        tools = None; params = [] };
      { id = "chat.with_tools"; model = "openai/gpt-5.4";
        messages = [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
        tools =
          Some
            (`List
              [ `Assoc
                  [ ("type", `String "function");
                    ("function", `Assoc [ ("name", `String "lookup") ]) ] ]);
        params = [] } ]
  in
  Printf.printf "runtime coverage: tracing build_kwargs under sys.settrace\n\n";
  let executed = ref [] and failures = ref 0 in
  List.iter
    (fun (scenario : Reference_capture.scenario) ->
      match
        Reference_capture.capture ~adapter_basename:"trace_execution_adapter.py" ~root
          ~snapshot_digest:snapshot ~reference_revision:"runtime-coverage" ~normalizer scenario
      with
      | Ok capture ->
          let files = executed_of_trace capture.Reference_capture.trace in
          Printf.printf "  %-18s %d files executed\n" scenario.id (List.length files);
          executed := files @ !executed
      | Error failure ->
          incr failures;
          Printf.printf "  %-18s FAILED %s\n" scenario.id (Reference_capture.describe failure))
    scenarios;
  let anchors =
    Capability_catalog.all
    |> List.concat_map (fun (c : Capability_catalog.capability) -> c.Capability_catalog.source_anchors)
    |> List.filter (fun a -> Filename.check_suffix a ".py")
    |> List.sort_uniq compare
  in
  let cov = Runtime_coverage.coverage ~executed:!executed ~anchors in
  Printf.printf "\nruntime anchor coverage: %s\n" (Runtime_coverage.describe cov);
  List.iter
    (fun (s : Runtime_coverage.anchor_status) ->
      if s.covered then Printf.printf "  covered: %s\n" s.anchor)
    cov.Runtime_coverage.statuses;
  if !failures > 0 then exit 1
