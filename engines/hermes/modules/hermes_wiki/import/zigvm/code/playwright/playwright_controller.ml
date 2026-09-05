type engine = Chromium | Firefox | Webkit

type window_class = Compact | Medium | Expanded | Large | Extra_large

type viewport = {
  name : string;
  width : int;
  height : int;
}

type box = {
  x : float;
  y : float;
  width : float;
  height : float;
}

type observation = {
  viewport : viewport;
  window_class : window_class;
  root : box;
  graph : box;
  inspector : box;
  controls : box list;
  tab_count : int;
  console_errors : string list;
  page_errors : string list;
  screenshot : string;
  lifecycle_screenshot : string;
  capability_screenshot : string;
  video : string;
  trace : string;
}

type violation =
  | Horizontal_overflow of float
  | Undersized_control of int * box
  | Pane_relation
  | Missing_tabs of int
  | Console_error of string
  | Page_error of string

type verdict = Pass | Fail of violation list

let default_viewports =
  [
    { name = "mobile-390x844"; width = 390; height = 844 };
    { name = "tablet-768x1024"; width = 768; height = 1024 };
    { name = "desktop-1440x900"; width = 1440; height = 900 };
    { name = "large-1920x1080"; width = 1920; height = 1080 };
  ]

let classify width =
  if width < 600 then Compact
  else if width < 840 then Medium
  else if width < 1200 then Expanded
  else if width < 1600 then Large
  else Extra_large

let window_class_name = function
  | Compact -> "compact"
  | Medium -> "medium"
  | Expanded -> "expanded"
  | Large -> "large"
  | Extra_large -> "extra-large"

let box_of_rect (rect : Playwright.Rect.Wrap.t) =
  { x = rect.x; y = rect.y; width = rect.width; height = rect.height }

let require_box label locator =
  match Playwright.Locator.bounding_box ~timeout:10000. locator with
  | Some rect -> box_of_rect rect
  | None -> failwith ("Playwright could not observe " ^ label)

let console_errors page =
  Playwright.Page.console_messages page
  |> Array.to_list
  |> List.filter_map (fun (message : Playwright.Page.Messages.t) ->
         if message.type_ = "error" then Some message.text else None)

let page_errors page =
  Playwright.Page.page_errors page
  |> Array.to_list
  |> List.map (fun (error : Playwright.SerializedError.t) ->
         match error.error with
         | Some (detail : Playwright.SerializedError.Error.t) -> detail.message
         | None -> "unstructured page error")

let orient observation =
  let violations = ref [] in
  let overflow = observation.root.x +. observation.root.width -. float observation.viewport.width in
  if overflow > 0.5 then violations := Horizontal_overflow overflow :: !violations;
  List.iteri
    (fun index box ->
      if box.width +. 0.5 < 44. || box.height +. 0.5 < 44. then
        violations := Undersized_control (index, box) :: !violations)
    observation.controls;
  let side_by_side = observation.inspector.x >= observation.graph.x +. observation.graph.width -. 1. in
  let stacked = observation.inspector.y >= observation.graph.y +. observation.graph.height -. 1. in
  let pane_ok =
    match observation.window_class with
    | Compact | Medium -> stacked
    | Expanded | Large | Extra_large -> side_by_side
  in
  if not pane_ok then violations := Pane_relation :: !violations;
  if observation.tab_count <> 6 then violations := Missing_tabs observation.tab_count :: !violations;
  List.iter (fun message -> violations := Console_error message :: !violations)
    observation.console_errors;
  List.iter (fun message -> violations := Page_error message :: !violations)
    observation.page_errors;
  match List.rev !violations with [] -> Pass | values -> Fail values

let decide = function Pass -> `Accept | Fail violations -> `Reject violations

let write_screenshot path payload =
  let bytes =
    if String.length payload >= 8 && String.sub payload 0 8 = "\137PNG\r\n\026\n" then payload
    else Base64.decode_exn payload
  in
  let channel = open_out_bin path in
  output_string channel bytes;
  close_out channel

let artifact_paths ~artifact_dir viewport =
  ( Filename.concat artifact_dir (viewport.name ^ ".png"),
    Filename.concat artifact_dir (viewport.name ^ ".webm"),
    Filename.concat artifact_dir (viewport.name ^ ".zip") )

let lifecycle_screenshot_path ~artifact_dir viewport =
  Filename.concat artifact_dir (viewport.name ^ "-project-lifecycle.png")

let capability_screenshot_path ~artifact_dir viewport =
  Filename.concat artifact_dir (viewport.name ^ "-capability-workbench.png")

let scoped_project_id ~run_id viewport =
  let slug =
    run_id |> String.lowercase_ascii
    |> String.map (fun character ->
           if
             (character >= 'a' && character <= 'z')
             || (character >= '0' && character <= '9')
           then character
           else '-')
    |> String.split_on_char '-'
    |> List.filter (fun part -> not (String.equal part ""))
    |> String.concat "-"
  in
  let slug = if String.equal slug "" then "run" else slug in
  "pw-" ^ slug ^ "-" ^ viewport.name

let project_lifecycle_selectors =
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
  ]

let capability_workbench_selectors =
  [
    "[data-testid='view-tab-graph']";
    "[data-testid='graph-zoom-in']";
    "[data-testid='graph-zoom-out']";
    "[data-testid='graph-fit']";
    "[data-testid='graph-reset-camera']";
    "[data-testid='layout-community']";
    "[data-testid='layout-mind-map']";
    "[data-testid='layout-word-cloud']";
    "[data-testid='display-labels']";
    "[data-testid='display-edges']";
    "[data-testid='graph-reveal-underlying']";
    "[data-testid='graph-playback']";
    "[data-testid='comparison-difference-left']";
    "[data-testid='comparison-overlap']";
    "[data-testid='saved-view-save']";
    "[data-testid='saved-view-restore']";
    "[data-testid='project-note-save']";
    "[data-testid='project-share-public']";
    "[data-testid='project-share-private']";
    "[data-testid='view-tab-research']";
    "[data-testid='research-analyze']";
    "[data-testid='preview-analytics']";
    "[data-testid='export-source-json']";
    "[data-testid='acquisition-workbench']";
    "[data-testid='acquire-document']";
    "[data-testid='acquire-web']";
    "[data-testid='intelligence-workbench']";
    "[data-testid='intelligence-chat']";
    "[data-testid='host-obsidian']";
    "[data-testid='view-tab-sa-plan']";
    "[data-testid='sa-plan-panel']";
  ]

let wait_visible page selector =
  Playwright.Page.locator ~selector page
  |> Playwright.Locator.wait_for ~state:`Visible ~timeout:15000.

let wait_input_value page selector expected =
  let locator = Playwright.Page.locator ~selector page in
  let deadline = Unix.gettimeofday () +. 15. in
  let rec loop stable_observations =
    let actual = Playwright.Locator.input_value locator in
    let stable_observations =
      if String.equal actual expected then stable_observations + 1 else 0
    in
    if stable_observations >= 3 then ()
    else if Unix.gettimeofday () >= deadline then
      failwith
        (Printf.sprintf "timeout waiting for %s value %S; observed %S" selector
           expected actual)
    else begin
      Unix.sleepf 0.02;
      loop stable_observations
    end
  in
  loop 0

let fill_stable page selector expected =
  let locator = Playwright.Page.locator ~selector page in
  let deadline = Unix.gettimeofday () +. 15. in
  let rec attempt () =
    Playwright.Page.fill ~selector ~value:"" page;
    Playwright.Page.fill ~selector ~value:expected page;
    Unix.sleepf 0.04;
    if String.equal (Playwright.Locator.input_value locator) expected then
      wait_input_value page selector expected
    else if Unix.gettimeofday () >= deadline then
      failwith (Printf.sprintf "timeout stabilizing %s as %S" selector expected)
    else attempt ()
  in
  attempt ()

let run_project_lifecycle ~artifact_dir ~run_id ~viewport page =
  let step name =
    Printf.eprintf "playwright[%s] lifecycle: %s\n%!" viewport.name name
  in
  let durable_id = scoped_project_id ~run_id viewport in
  let duplicate_id = durable_id ^ "-copy" in
  let survey_id = durable_id ^ "-survey" in
  let transient_id = durable_id ^ "-private-session" in
  step "open project panel";
  Playwright.Page.click ~selector:"[data-testid='view-tab-project']" page;
  wait_visible page "[data-testid='project-new-id']";
  Playwright.Page.fill ~selector:"[data-testid='project-new-id']" ~value:durable_id page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-name']"
    ~value:("Lifecycle " ^ viewport.name) page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-created-on']"
    ~value:"2026-08-03" page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-analysis-type']"
    ~value:"literature" page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-language']" ~value:"en"
    page;
  wait_visible page "[data-testid='project-create']:not([disabled])";
  Playwright.Page.click ~selector:"[data-testid='project-create']" page;
  step "durable classified project submitted";
  wait_visible page (Printf.sprintf "[data-testid='project-select-%s']" durable_id);
  Playwright.Page.click
    ~selector:(Printf.sprintf "[data-testid='project-select-%s']" durable_id)
    page;
  wait_visible page "[data-testid='project-rename']";
  Playwright.Page.fill ~selector:"[data-testid='project-rename-name']"
    ~value:("Renamed " ^ viewport.name) page;
  Playwright.Page.click ~selector:"[data-testid='project-rename']" page;
  step "rename submitted";
  wait_visible page
    (Printf.sprintf
       "[data-testid='project-select-%s'][aria-label='Open project Renamed %s']"
       durable_id viewport.name);
  Playwright.Page.click
    ~selector:(Printf.sprintf "[data-testid='project-favorite-%s']" durable_id)
    page;
  wait_visible page
    (Printf.sprintf
       "[data-testid='project-favorite-%s'][aria-label='Unfavorite Renamed %s']"
       durable_id viewport.name);
  Playwright.Page.click
    ~selector:(Printf.sprintf "[data-testid='project-select-%s']" durable_id)
    page;
  fill_stable page "[data-testid='project-duplicate-id']" duplicate_id;
  fill_stable page "[data-testid='project-duplicate-name']"
    ("Copy " ^ viewport.name);
  wait_visible page "[data-testid='project-duplicate']:not([disabled])";
  Playwright.Page.click ~selector:"[data-testid='project-duplicate']" page;
  step "duplicate submitted";
  wait_visible page (Printf.sprintf "[data-testid='project-select-%s']" duplicate_id);
  Playwright.Page.click
    ~selector:(Printf.sprintf "[data-testid='project-delete-%s']" duplicate_id)
    page;
  step "duplicate delete submitted";
  Playwright.Page.locator
    ~selector:(Printf.sprintf "[data-testid='project-select-%s']" duplicate_id)
    page
  |> Playwright.Locator.wait_for ~state:`Hidden ~timeout:15000.;
  Playwright.Page.fill ~selector:"[data-testid='project-search']" ~value:durable_id page;
  Playwright.Page.click
    ~selector:(Printf.sprintf "[data-testid='project-archive-%s']" durable_id)
    page;
  step "archive submitted";
  wait_visible page
    (Printf.sprintf
       "[data-testid='project-archive-%s'][aria-label='Restore Renamed %s']"
       durable_id viewport.name);
  Playwright.Page.click
    ~selector:(Printf.sprintf "[data-testid='project-archive-%s']" durable_id)
    page;
  step "restore submitted";
  wait_visible page
    (Printf.sprintf
       "[data-testid='project-archive-%s'][aria-label='Archive Renamed %s']"
       durable_id viewport.name);
  Playwright.Page.fill ~selector:"[data-testid='project-search']" ~value:"" page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-id']" ~value:survey_id page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-name']"
    ~value:("Survey " ^ viewport.name) page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-created-on']"
    ~value:"2026-07-01" page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-analysis-type']"
    ~value:"survey" page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-language']" ~value:"sv"
    page;
  wait_visible page "[data-testid='project-create']:not([disabled])";
  Playwright.Page.click ~selector:"[data-testid='project-create']" page;
  step "survey project submitted";
  wait_visible page (Printf.sprintf "[data-testid='project-select-%s']" survey_id);
  Playwright.Page.fill ~selector:"[data-testid='project-new-id']" ~value:transient_id page;
  Playwright.Page.fill ~selector:"[data-testid='project-new-name']"
    ~value:"Private browser session" page;
  Playwright.Page.click ~selector:"[data-testid='project-privacy-non-persistent']" page;
  wait_visible page
    "[data-testid='project-privacy-non-persistent'][aria-pressed='true']";
  wait_visible page "[data-testid='project-create']:not([disabled])";
  Playwright.Page.click ~selector:"[data-testid='project-create']" page;
  step "non-persistent project submitted";
  wait_input_value page "[data-testid='project-new-name']" "";
  let transient_count =
    Playwright.Page.locator
      ~selector:(Printf.sprintf "[data-testid='project-select-%s']" transient_id)
      page
    |> Playwright.Locator.count
  in
  if transient_count <> 0 then failwith "non-persistent project leaked into durable inventory";
  Playwright.Page.fill ~selector:"[data-testid='project-search']" ~value:"renamed" page;
  Playwright.Page.fill ~selector:"[data-testid='project-filter-created-from']"
    ~value:"2026-08-01" page;
  Playwright.Page.fill ~selector:"[data-testid='project-filter-created-to']"
    ~value:"2026-08-31" page;
  Playwright.Page.fill ~selector:"[data-testid='project-filter-analysis-type']"
    ~value:"literature" page;
  Playwright.Page.fill ~selector:"[data-testid='project-filter-language']" ~value:"en"
    page;
  step "composed inventory filters applied";
  wait_visible page (Printf.sprintf "[data-testid='project-select-%s']" durable_id);
  Playwright.Page.locator
    ~selector:(Printf.sprintf "[data-testid='project-select-%s']" survey_id)
    page
  |> Playwright.Locator.wait_for ~state:`Hidden ~timeout:15000.;
  Playwright.Page.click
    ~selector:(Printf.sprintf "[data-testid='project-select-%s']" durable_id)
    page;
  step "inventory filter observations satisfied";
  let path = lifecycle_screenshot_path ~artifact_dir viewport in
  Playwright.Page.screenshot ~full_page:true ~timeout:10000. page
  |> write_screenshot path;
  path

let run_capability_workbench ~artifact_dir ~run_id ~viewport page =
  let step name =
    Printf.eprintf "playwright[%s] capabilities: %s\n%!" viewport.name name
  in
  let durable_id = scoped_project_id ~run_id viewport in
  Playwright.Page.click ~selector:"[data-testid='view-tab-graph']" page;
  List.iter (wait_visible page)
    [ "[data-testid='graph-zoom-in']"; "[data-testid='layout-community']";
      "[data-testid='saved-view-save']" ];
  Playwright.Page.click ~selector:"[data-testid='graph-zoom-in']" page;
  Playwright.Page.click ~selector:"[data-testid='graph-zoom-out']" page;
  Playwright.Page.click ~selector:"[data-testid='layout-community']" page;
  Playwright.Page.click ~selector:"[data-testid='layout-mind-map']" page;
  Playwright.Page.click ~selector:"[data-testid='layout-word-cloud']" page;
  Playwright.Page.click ~selector:"[data-testid='layout-community']" page;
  Playwright.Page.click ~selector:"[data-testid='display-labels']" page;
  Playwright.Page.click ~selector:"[data-testid='display-labels']" page;
  Playwright.Page.click ~selector:"[data-testid='display-edges']" page;
  Playwright.Page.click ~selector:"[data-testid='display-edges']" page;
  Playwright.Page.click ~selector:"[data-testid='graph-reveal-underlying']" page;
  Playwright.Page.click ~selector:"[data-testid='graph-reveal-underlying']" page;
  Playwright.Page.click ~selector:"[data-testid='graph-playback']" page;
  Playwright.Page.click ~selector:"[data-testid='graph-playback']" page;
  Playwright.Page.click ~selector:"[data-testid='comparison-difference-left']" page;
  Playwright.Page.click ~selector:"[data-testid='comparison-overlap']" page;
  Playwright.Page.click ~selector:"[data-testid='graph-fit']" page;
  Playwright.Page.click ~selector:"[data-testid='graph-reset-camera']" page;
  step "camera, display, layouts, playback, and comparison exercised";
  Playwright.Page.fill ~selector:"[data-testid='saved-view-name']"
    ~value:("Lens " ^ viewport.name) page;
  Playwright.Page.click ~selector:"[data-testid='saved-view-save']" page;
  wait_visible page
    (Printf.sprintf "[data-testid='workspace-result']:has-text('%s-lens')" durable_id);
  Playwright.Page.click ~selector:"[data-testid='saved-view-restore']" page;
  wait_visible page "[data-testid='workspace-result']:has-text('Restored saved view')";
  step "saved analytical lens round-tripped";
  Playwright.Page.fill ~selector:"[data-testid='project-note-text']"
    ~value:"Inspect the conceptual gateway" page;
  Playwright.Page.click ~selector:"[data-testid='project-note-save']" page;
  wait_visible page "[data-testid='workspace-result']:has-text('Inspect the conceptual gateway')";
  Playwright.Page.click ~selector:"[data-testid='project-share-public']" page;
  wait_visible page "[data-testid='workspace-result']:has-text('public')";
  Playwright.Page.click ~selector:"[data-testid='project-share-private']" page;
  wait_visible page "[data-testid='workspace-result']:has-text('private')";
  step "revision note and confirmed share visibility exercised";
  step "opening research";
  wait_visible page "[data-testid='view-tab-research']";
  Playwright.Page.click ~selector:"[data-testid='view-tab-research']" page;
  Playwright.Page.click ~selector:"[data-testid='view-tab-research']" page;
  step "research tab clicked";
  wait_visible page
    "[data-testid='view-tab-research'][aria-selected='true']";
  let research_count =
    Playwright.Page.locator ~selector:"[data-testid='research-text']" page
    |> Playwright.Locator.count
  in
  Printf.eprintf "playwright[%s] capabilities: research-count=%d page-errors=%s console-errors=%s\n%!"
    viewport.name research_count (String.concat " | " (page_errors page))
    (String.concat " | " (console_errors page));
  wait_visible page "[data-testid='research-text']";
  step "research profile visible";
  Playwright.Page.fill ~selector:"[data-testid='research-text']"
    ~value:
      "Graphs connect evidence and robust research. [[Knowledge Graph]] links @analyst #insight. Entity:InfraNodus reveals unsafe gaps and successful ideas."
    page;
  Playwright.Page.fill ~selector:"[data-testid='processing-language']" ~value:"en" page;
  Playwright.Page.fill ~selector:"[data-testid='processing-stop-words']" ~value:"and,the" page;
  Playwright.Page.fill ~selector:"[data-testid='processing-protected-words']" ~value:"InfraNodus" page;
  Playwright.Page.fill ~selector:"[data-testid='processing-synonyms']" ~value:"graphs=graph,ideas=idea" page;
  Playwright.Page.fill ~selector:"[data-testid='processing-window']" ~value:"5" page;
  Playwright.Page.click ~selector:"[data-testid='processing-graph-mode']" page;
  Playwright.Page.click ~selector:"[data-testid='processing-graph-mode']" page;
  Playwright.Page.click ~selector:"[data-testid='research-analyze']" page;
  step "analysis submitted";
  wait_visible page "[data-testid='preview-analytics']";
  step "analytics visible";
  let panel_count =
    Playwright.Page.locator ~selector:".analytics-panel" page
    |> Playwright.Locator.count
  in
  if panel_count <> 14 then
    failwith (Printf.sprintf "analytics panel totality: expected 14, observed %d" panel_count);
  Playwright.Page.click ~selector:"[data-testid='export-source-json']" page;
  wait_visible page "[data-testid='export-result']:has-text('zigvm.infranodus.source-backup.v1')";
  step "processing, analytics, and source export exercised";
  let local_acquisition =
    [ "document"; "spreadsheet"; "batch"; "knowledge-notes";
      "graph-network"; "api" ]
  in
  List.iter
    (fun kind ->
      Playwright.Page.click ~selector:(Printf.sprintf "[data-testid='acquire-%s']" kind) page;
      wait_visible page "[data-testid='export-result']:has-text('processing_digest')")
    local_acquisition;
  List.iter
    (fun kind ->
      Playwright.Page.click ~selector:(Printf.sprintf "[data-testid='acquire-%s']" kind) page;
      wait_visible page
        (Printf.sprintf "[data-testid='export-result']:has-text('%s_provider_not_configured')" kind))
    [ "web"; "search"; "youtube"; "social" ];
  step "all ten acquisition coordinates and provider honesty states exercised";
  List.iter
    (fun host ->
      Playwright.Page.click ~selector:(Printf.sprintf "[data-testid='host-%s']" host) page)
    [ "browser"; "obsidian"; "ide"; "n8n" ];
  wait_visible page "[data-testid='export-result']:has-text('processing_digest')";
  step "browser, Obsidian, IDE, and n8n host adapters exercised";
  List.iter
    (fun operation ->
      Playwright.Page.click
        ~selector:(Printf.sprintf "[data-testid='intelligence-%s']" operation) page;
      wait_visible page
        (Printf.sprintf "[data-testid='export-result']:has-text('%s')" operation))
    [ "overview"; "summary"; "gaps"; "chat"; "augment"; "retrieve";
      "ontology"; "note"; "providers" ];
  step "all nine graph-intelligence operations exercised";
  Playwright.Page.click ~selector:"[data-testid='view-tab-sa-plan']" page;
  wait_visible page "[data-testid='sa-plan-panel']";
  wait_visible page "[data-testid='sa-plan-task-list']";
  wait_visible page "[data-testid='sa-plan-job-list']";
  wait_visible page "[data-testid='sa-plan-workflow-list']";
  step "Sa-plan read-only tasks, leases, retries, and workflows observed";
  let path = capability_screenshot_path ~artifact_dir viewport in
  Playwright.Page.screenshot ~full_page:true ~timeout:10000. page
  |> write_screenshot path;
  Playwright.Page.click ~selector:"[data-testid='view-tab-graph']" page;
  wait_visible page ".graph-stage";
  path

let observe ~artifact_dir ~viewport ~lifecycle_screenshot ~capability_screenshot page =
  let root = Playwright.Page.locator ~selector:"html" page |> require_box "document root" in
  let graph = Playwright.Page.locator ~selector:".graph-stage" page |> require_box "graph pane" in
  let inspector = Playwright.Page.locator ~selector:".inspector" page |> require_box "inspector pane" in
  let controls =
    Playwright.Page.locator
      ~selector:".workspace button, .workspace input, .workspace textarea"
      page
    |> Playwright.Locator.all
    |> List.map (require_box "interactive control")
  in
  let tab_count =
    Playwright.Page.locator ~selector:".view-tab" page |> Playwright.Locator.count
  in
  let screenshot, video, trace = artifact_paths ~artifact_dir viewport in
  Playwright.Page.screenshot ~full_page:true ~timeout:10000. page
  |> write_screenshot screenshot;
  {
    viewport;
    window_class = classify viewport.width;
    root;
    graph;
    inspector;
    controls;
    tab_count;
    console_errors = console_errors page;
    page_errors = page_errors page;
    screenshot;
    lifecycle_screenshot;
    capability_screenshot;
    video;
    trace;
  }

let browser_type engine playwright =
  match engine with
  | Chromium -> Playwright.Playwright.chromium playwright
  | Firefox -> Playwright.Playwright.firefox playwright
  | Webkit -> Playwright.Playwright.webkit playwright

let run_viewport ~browser ~url ~artifact_dir ~run_id (viewport : viewport) =
  let dimensions = Playwright.Browser.Viewport.{ width = viewport.width; height = viewport.height } in
  let video_size = Playwright.Browser.Size.{ width = viewport.width; height = viewport.height } in
  let record_video =
    Playwright.Browser.Record_video.
      { dir = Some artifact_dir; size = Some video_size; show_actions = None }
  in
  let context =
    Playwright.Browser.new_context ~viewport:dimensions
      ~screen:Playwright.Browser.Screen.{ width = viewport.width; height = viewport.height }
      ~has_touch:(viewport.width < 840) ~is_mobile:(viewport.width < 600)
      ~color_scheme:`Light ~reduced_motion:`No_preference ~record_video browser
  in
  let context_open = ref true in
  Fun.protect
    ~finally:(fun () -> if !context_open then Playwright.BrowserContext.close context)
    (fun () ->
      let tracing = Playwright.BrowserContext.tracing context in
      Playwright.Tracing.tracing_start ~name:viewport.name ~snapshots:true ~screenshots:true
        tracing;
      ignore
        (Playwright.Tracing.tracing_start_chunk ~name:viewport.name
           ~title:("InfraNodus responsive evidence: " ^ viewport.name) tracing);
      let page = Playwright.BrowserContext.new_page context in
      let video_artifact = Playwright.Page.video page in
      ignore (Playwright.Page.goto ~url ~timeout:15000. page);
      Playwright.Page.locator ~selector:".app-shell" page
      |> Playwright.Locator.wait_for ~state:`Visible ~timeout:15000.;
      let lifecycle_screenshot =
        run_project_lifecycle ~artifact_dir ~run_id ~viewport page
      in
      let capability_screenshot =
        run_capability_workbench ~artifact_dir ~run_id ~viewport page
      in
      let observation =
        observe ~artifact_dir ~viewport ~lifecycle_screenshot
          ~capability_screenshot page
      in
      let trace_result = Playwright.Tracing.tracing_stop_chunk ~mode:`Archive tracing in
      (match trace_result.artifact with
      | Some artifact ->
          Playwright.Artifact.save_as ~path:observation.trace artifact;
          Playwright.Artifact.delete artifact
      | None -> failwith ("Playwright did not produce trace artifact for " ^ viewport.name));
      Playwright.Tracing.tracing_stop tracing;
      Playwright.BrowserContext.close context;
      context_open := false;
      (match video_artifact with
      | Some artifact ->
          Playwright.Artifact.save_as ~path:observation.video artifact;
          Playwright.Artifact.delete artifact
      | None -> failwith ("Playwright did not produce video artifact for " ^ viewport.name));
      (observation, orient observation |> decide))

let run_matrix ~engine ~executable_path ~url ~artifact_dir ~run_id viewports =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let playwright = Playwright.create ~env ~sw () in
  Fun.protect
    ~finally:(fun () -> Playwright.destroy playwright)
    (fun () ->
      let browser =
        Playwright.BrowserType.launch ~executable_path ~headless:true ~timeout:30000.
          (browser_type engine playwright)
      in
      Fun.protect
        ~finally:(fun () -> Playwright.Browser.close browser)
        (fun () ->
          List.map (run_viewport ~browser ~url ~artifact_dir ~run_id) viewports))

let violation_name = function
  | Horizontal_overflow pixels -> Printf.sprintf "horizontal-overflow(%.2fpx)" pixels
  | Undersized_control (index, box) ->
      Printf.sprintf "undersized-control(%d,%.1fx%.1f)" index box.width box.height
  | Pane_relation -> "pane-relation"
  | Missing_tabs count -> Printf.sprintf "missing-tabs(%d)" count
  | Console_error message -> "console-error(" ^ message ^ ")"
  | Page_error message -> "page-error(" ^ message ^ ")"

let result_json (observation, decision) =
  let decision_json =
    match decision with
    | `Accept -> `Assoc [ ("status", `String "pass"); ("violations", `List []) ]
    | `Reject violations ->
        `Assoc
          [
            ("status", `String "fail");
            ("violations", `List (List.map (fun value -> `String (violation_name value)) violations));
          ]
  in
  `Assoc
    [
      ("viewport", `String observation.viewport.name);
      ("width", `Int observation.viewport.width);
      ("height", `Int observation.viewport.height);
      ("window_class", `String (window_class_name observation.window_class));
      ("control_count", `Int (List.length observation.controls));
      ("screenshot", `String observation.screenshot);
      ("lifecycle_screenshot", `String observation.lifecycle_screenshot);
      ("capability_screenshot", `String observation.capability_screenshot);
      ("video", `String observation.video);
      ("trace", `String observation.trace);
      ("verdict", decision_json);
    ]

let write_manifest path results =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () ->
      results |> List.map result_json |> fun rows ->
      Yojson.Safe.pretty_to_channel channel (`List rows);
      output_char channel '\n')
