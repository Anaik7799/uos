let assert_true message value = if not value then failwith message

let () =
  let open Playwright_control.Playwright_controller in
  assert_true "compact lower bound" (classify 0 = Compact);
  assert_true "compact upper bound" (classify 599 = Compact);
  assert_true "medium lower bound" (classify 600 = Medium);
  assert_true "expanded lower bound" (classify 840 = Expanded);
  assert_true "large lower bound" (classify 1200 = Large);
  assert_true "extra-large lower bound" (classify 1600 = Extra_large);
  let viewport = { name = "law"; width = 390; height = 844 } in
  let box x y width height = { x; y; width; height } in
  let observation =
    {
      viewport;
      window_class = Compact;
      root = box 0. 0. 390. 1200.;
      graph = box 16. 100. 358. 400.;
      inspector = box 16. 500. 358. 300.;
      controls = [ box 0. 0. 44. 44. ];
      tab_count = 6;
      console_errors = [];
      page_errors = [];
      screenshot = "/tmp/law.png";
      lifecycle_screenshot = "/tmp/law-project-lifecycle.png";
      capability_screenshot = "/tmp/law-capability-workbench.png";
      video = "/tmp/law.webm";
      trace = "/tmp/law.zip";
    }
  in
  assert_true "valid compact observation must pass" (orient observation = Pass);
  let mutant = { observation with controls = [ box 0. 0. 43. 44. ] } in
  assert_true "43px touch target mutant must be killed"
    (match orient mutant with Fail (Undersized_control _ :: _) -> true | _ -> false);
  let screenshot, video, trace = artifact_paths ~artifact_dir:"/tmp/evidence" viewport in
  assert_true "deterministic screenshot name" (screenshot = "/tmp/evidence/law.png");
  assert_true "deterministic video name" (video = "/tmp/evidence/law.webm");
  assert_true "deterministic trace name" (trace = "/tmp/evidence/law.zip");
  assert_true "deterministic lifecycle screenshot name"
    (lifecycle_screenshot_path ~artifact_dir:"/tmp/evidence" viewport
    = "/tmp/evidence/law-project-lifecycle.png");
  assert_true "deterministic capability screenshot name"
    (capability_screenshot_path ~artifact_dir:"/tmp/evidence" viewport
    = "/tmp/evidence/law-capability-workbench.png");
  assert_true "run-scoped lifecycle project IDs are deterministic and URL-safe"
    (scoped_project_id ~run_id:"Cycle 42 / retry" viewport
    = "pw-cycle-42-retry-law");
  assert_true "project lifecycle selector contract"
    (project_lifecycle_selectors
    =
    [
      "[data-testid='view-tab-project']";
      "[data-testid='project-new-id']";
      "[data-testid='project-new-name']";
      "[data-testid='project-new-created-on']";
      "[data-testid='project-new-analysis-type']";
      "[data-testid='project-new-language']";
      "[data-testid='project-create']";
      "[data-testid='project-search']";
      "[data-testid='project-filter-created-from']";
      "[data-testid='project-filter-created-to']";
      "[data-testid='project-filter-analysis-type']";
      "[data-testid='project-filter-language']";
      "[data-testid='project-filter-favorite']";
      "[data-testid='project-rename']";
      "[data-testid='project-duplicate']";
    ]);
  assert_true "capability workbench selector contract"
    (List.for_all (fun selector -> List.mem selector capability_workbench_selectors)
       [ "[data-testid='graph-zoom-in']"; "[data-testid='layout-community']";
         "[data-testid='graph-reveal-underlying']";
         "[data-testid='graph-playback']";
         "[data-testid='comparison-difference-left']";
         "[data-testid='saved-view-save']";
         "[data-testid='saved-view-restore']";
         "[data-testid='project-note-save']";
         "[data-testid='project-share-public']";
         "[data-testid='view-tab-sa-plan']";
         "[data-testid='sa-plan-panel']";
         "[data-testid='research-analyze']";
         "[data-testid='preview-analytics']";
         "[data-testid='export-source-json']" ]);
  let manifest_path = "/tmp/zigvm-playwright-manifest-law.json" in
  write_manifest manifest_path [ (observation, `Accept) ];
  let manifest = Yojson.Safe.from_file manifest_path in
  Unix.unlink manifest_path;
  assert_true "media manifest persists the viewport verdict"
    (match manifest with
    | `List [ `Assoc fields ] ->
        List.assoc_opt "viewport" fields = Some (`String "law")
        && List.mem_assoc "verdict" fields
    | _ -> false);
  let ontology =
    Playwright_control.Playwright_ontology.load "third_party/ocaml_playwright_55/protocol/protocol.yml"
  in
  assert_true "protocol must expose interfaces" (Playwright_control.Playwright_ontology.interface_count ontology > 30);
  assert_true "protocol must expose commands" (Playwright_control.Playwright_ontology.command_count ontology > 150);
  assert_true "protocol must expose events" (Playwright_control.Playwright_ontology.event_count ontology > 40);
  let channel = open_in_bin "_opam/lib/playwright/api.mli" in
  let api = really_input_string channel (in_channel_length channel) in
  close_in channel;
  assert_true "all protocol commands must have typed OCaml bindings"
    (Playwright_control.Playwright_ontology.missing_command_bindings ontology api = []);
  assert_true "all protocol events must have typed OCaml subscriptions"
    (Playwright_control.Playwright_ontology.missing_event_bindings ontology api = []);
  let source =
    Playwright_control.Playwright_source_ontology.load
      ~root:"third_party/microsoft_playwright_159"
      ~revision:"01b2b1533e0bfa1c582117e3ec109fcb57657747"
      ~tree:"e1bcfae84368d3c9b7cedf3ab24ea491d67d61c5"
  in
  assert_true "upstream source inventory must be complete"
    (List.length source.artifacts = 3089);
  assert_true "upstream documentation corpus must be complete"
    (Playwright_control.Playwright_source_ontology.documentation_count source = 231);
  assert_true "upstream package graph must be non-vacuous"
    (List.length source.packages = 41);
  assert_true "all three browser adapters must be represented"
    (List.for_all
       (fun kind -> Playwright_control.Playwright_source_ontology.count_kind source kind > 0)
       [ "chromium-adapter"; "firefox-adapter"; "webkit-adapter" ]);
  let authority =
    Playwright_control.Playwright_authority.build ~protocol:ontology ~source ~api
  in
  let open Playwright_control.Playwright_authority in
  assert_true "every upstream source domain must have exactly one authority classification"
    (validate authority = []);
  assert_true "typed protocol control must cover every command and event"
    (protocol_control_complete authority);
  assert_true "the supported browser runtime boundary must be fully controlled by OCaml"
    (runtime_boundary_complete authority);
  assert_true "Playwright product parity must remain partial while product surfaces are gaps"
    (not (product_parity_complete authority));
  assert_true "Playwright Test runner parity gap must be explicit"
    (List.mem "test-runner" (product_gaps authority));
  assert_true "Playwright CLI parity gap must be explicit"
    (List.mem "cli-tooling" (product_gaps authority));
  assert_true "Playwright MCP/agent tooling parity gap must be explicit"
    (List.mem "agent-tooling" (product_gaps authority));
  let dropped = mutate_drop_domain authority "wire-protocol" in
  assert_true "missing wire authority mutant must be killed"
    (validate dropped <> []);
  let false_full = mutate_authority authority "test-runner" Typed_protocol in
  assert_true "false full-control promotion mutant must be killed"
    (validate false_full <> []);
  print_endline "playwright controller laws: ok"
