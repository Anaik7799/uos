module Controller = Playwright_control.Playwright_controller
module Feature = Zigvm_harness_support.Infranodus_feature

let find_arg name default =
  let rec loop index =
    if index + 1 >= Array.length Sys.argv then default
    else if Sys.argv.(index) = name then Sys.argv.(index + 1) else loop (index + 1)
  in loop 1

let rec ensure_directory path =
  if Sys.file_exists path then () else begin
    let parent = Filename.dirname path in if parent <> path then ensure_directory parent;
    Unix.mkdir path 0o755
  end

let write_atomic path json =
  ensure_directory (Filename.dirname path);
  let temporary = path ^ ".tmp" in
  let channel = open_out_bin temporary in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> Yojson.Safe.pretty_to_channel channel json; output_char channel '\n');
  Sys.rename temporary path

let page_ids = List.init 37 (fun index -> Printf.sprintf "P%02d" (index + 1))

let () =
  let url = find_arg "--url" "http://127.0.0.1:8093/bonsai" in
  let executable_path = find_arg "--executable" "" in
  let artifact_dir = find_arg "--artifacts" "work/infranodus-full-ui-playwright" in
  let manifest = find_arg "--manifest"
      "docs/evidence/infranodus-ocaml/full-feature-matrix/manifest.json" in
  if executable_path = "" then (prerr_endline "--executable is required"; exit 2);
  ensure_directory artifact_dir;
  let results =
    Controller.run_matrix ~engine:Controller.Chromium ~executable_path ~url
      ~artifact_dir ~run_id:"infranodus-full-ui"
      Controller.default_viewports
  in
  let rows =
    List.map
      (fun (observation, decision) ->
        let state, violations = match decision with
          | `Accept -> "Executed_pass", []
          | `Reject found -> "Executed_fail", List.map Controller.violation_name found
        in
        `Assoc
          [ "evidence_id", `String ("workflow:full-ui:" ^ observation.Controller.viewport.name);
            "scope", `String "executed_workflow_not_fabricated_per-feature";
            "viewport", `String observation.viewport.name;
            "feature_ids", `List (List.map (fun feature -> `String (Feature.id feature)) Feature.all);
            "page_ids", `List (List.map (fun page -> `String page) page_ids);
            "screenshot", `String observation.screenshot;
            "lifecycle_screenshot", `String observation.lifecycle_screenshot;
            "capability_screenshot", `String observation.capability_screenshot;
            "video", `String observation.video; "trace", `String observation.trace;
            "state", `String state;
            "violations", `List (List.map (fun value -> `String value) violations) ])
      results
  in
  let json =
    `Assoc [ "schema_version", `Int 1; "authority", `String "typed_ocaml_playwright";
      "declared_feature_rows", `Int 280; "executed_workflow_rows", `Int 4;
      "rows", `List rows ]
  in
  write_atomic manifest json;
  Yojson.Safe.pretty_to_channel stdout json; output_char stdout '\n';
  if List.exists (fun (_, decision) -> match decision with `Reject _ -> true | `Accept -> false) results
  then exit 1
