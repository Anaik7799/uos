module Controller = Playwright_control.Playwright_controller

type profile = Dashboard | Atlas | Benchmark

let profile_of_string = function
  | "dashboard" -> Dashboard
  | "atlas" -> Atlas
  | "benchmark" -> Benchmark
  | value -> invalid_arg ("unknown verification profile: " ^ value)

let profile_name = function
  | Dashboard -> "dashboard"
  | Atlas -> "atlas"
  | Benchmark -> "benchmark"

type observation = {
  viewport : string;
  viewport_width : float;
  root_width : float;
  heading_count : int;
  card_count : int;
  row_count : int;
  budget_header_count : int;
  remote_resource_count : int;
  console_errors : string list;
  page_errors : string list;
}

let find_arg name default =
  let rec loop index =
    if index + 1 >= Array.length Sys.argv then default
    else if String.equal Sys.argv.(index) name then Sys.argv.(index + 1)
    else loop (index + 1)
  in
  loop 1

let rec ensure_directory path =
  if Sys.file_exists path then begin
    if not (Sys.is_directory path) then failwith (path ^ " is not a directory")
  end else begin
    let parent = Filename.dirname path in
    if not (String.equal parent path) then ensure_directory parent;
    Unix.mkdir path 0o755
  end

let require_box label locator =
  match Playwright.Locator.bounding_box ~timeout:10_000. locator with
  | Some box -> box
  | None -> failwith ("missing bounding box: " ^ label)

let console_errors page =
  Playwright.Page.console_messages page
  |> Array.to_list
  |> List.filter_map (fun (message : Playwright.Page.Messages.t) ->
       if String.equal message.type_ "error" then Some message.text else None)

let page_errors page =
  Playwright.Page.page_errors page
  |> Array.to_list
  |> List.map (fun (error : Playwright.SerializedError.t) ->
       match error.error with
       | Some detail -> detail.message
       | None -> "unstructured page error")

let violations profile observation =
  let found = ref [] in
  if observation.root_width -. observation.viewport_width > 0.5 then
    found := "horizontal-overflow" :: !found;
  if observation.heading_count <> 1 then found := "heading-not-single" :: !found;
  (match profile with
   | Dashboard ->
       if observation.card_count < 8 then found := "missing-metric-cards" :: !found;
       if observation.row_count < 16 then found := "incomplete-stage-events" :: !found;
       if observation.budget_header_count < 2 then
         found := "missing-time-budget-columns" :: !found
   | Atlas ->
       if observation.card_count <> 36 then found := "atlas-diagram-count" :: !found;
       if observation.row_count < 72 then found := "atlas-edge-fallback-incomplete" :: !found;
       if observation.budget_header_count <> 36 then
         found := "atlas-keyboard-fallback-incomplete" :: !found
   | Benchmark ->
       if observation.card_count < 8 then found := "benchmark-sections-incomplete" :: !found;
       if observation.row_count < 20 then found := "benchmark-tables-incomplete" :: !found;
       if observation.budget_header_count < 1 then
         found := "benchmark-budget-column-missing" :: !found);
  if observation.remote_resource_count <> 0 then
    found := "remote-runtime-resource" :: !found;
  List.iter (fun error -> found := ("console-error:" ^ error) :: !found)
    observation.console_errors;
  List.iter (fun error -> found := ("page-error:" ^ error) :: !found)
    observation.page_errors;
  List.rev !found

let run_viewport ~profile ~browser ~url ~artifact_dir (viewport : Controller.viewport) =
  let dimensions =
    Playwright.Browser.Viewport.{ width = viewport.width; height = viewport.height }
  in
  let context =
    Playwright.Browser.new_context ~viewport:dimensions
      ~screen:Playwright.Browser.Screen.{ width = viewport.width; height = viewport.height }
      ~has_touch:(viewport.width < 840) ~is_mobile:(viewport.width < 600)
      ~color_scheme:`Dark ~reduced_motion:`Reduce browser
  in
  Fun.protect
    ~finally:(fun () -> Playwright.BrowserContext.close context)
    (fun () ->
      let page = Playwright.BrowserContext.new_page context in
      ignore (Playwright.Page.goto ~url ~timeout:30_000. page);
      let main = Playwright.Page.locator ~selector:"main" page in
      Playwright.Locator.wait_for ~state:`Visible ~timeout:30_000. main;
      let root =
        Playwright.Page.locator ~selector:"html" page |> require_box "html"
      in
      let count selector =
        Playwright.Page.locator ~selector page |> Playwright.Locator.count
      in
      let observation =
        { viewport = viewport.name;
          viewport_width = float viewport.width;
          root_width = root.width;
          heading_count = count "main h1";
          card_count = count (match profile with
            | Dashboard -> ".card" | Atlas -> ".diagram-card" | Benchmark -> "main h2");
          row_count = count "tbody tr";
          budget_header_count =
            count (match profile with
              | Dashboard -> "th:has-text('budget')"
              | Atlas -> "details table"
              | Benchmark -> "th:has-text('Budget')");
          remote_resource_count =
            count
              "link[href^='http'],script[src^='http'],iframe[src^='http'],img[src^='http'],video[src^='http'],audio[src^='http']";
          console_errors = console_errors page;
          page_errors = page_errors page }
      in
      let screenshot = Filename.concat artifact_dir (viewport.name ^ ".png") in
      Playwright.Page.screenshot ~full_page:false ~timeout:30_000. page
      |> Controller.write_screenshot screenshot;
      let violations = violations profile observation in
      (`Assoc
         [ ("profile", `String (profile_name profile));
           ("viewport", `String viewport.name);
           ("width", `Int viewport.width);
           ("height", `Int viewport.height);
           ("metric_cards", `Int observation.card_count);
           ("stage_event_rows", `Int observation.row_count);
           ("time_budget_headers", `Int observation.budget_header_count);
           ("screenshot", `String screenshot);
           ("status", `String (if violations = [] then "pass" else "fail"));
           ("violations", `List (List.map (fun value -> `String value) violations)) ],
       violations))

let write_atomic path json =
  let temporary = path ^ ".tmp" in
  let channel = open_out_bin temporary in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () ->
      Yojson.Safe.pretty_to_channel channel json;
      output_char channel '\n');
  Sys.rename temporary path

let () =
  let url = find_arg "--url" "" in
  let executable_path = find_arg "--executable" "" in
  let profile = find_arg "--profile" "dashboard" |> profile_of_string in
  let artifact_dir = find_arg "--artifacts" "/tmp/bundle-dashboard-playwright" in
  if String.equal url "" || String.equal executable_path "" then begin
    Printf.eprintf "--url and --executable are required\n%!";
    exit 2
  end;
  ensure_directory artifact_dir;
  let results =
    Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw ->
    let playwright = Playwright.create ~env ~sw () in
    Fun.protect ~finally:(fun () -> Playwright.destroy playwright) (fun () ->
      let browser =
        Playwright.BrowserType.launch ~executable_path ~headless:true
          ~timeout:30_000. (Playwright.Playwright.chromium playwright)
      in
      Fun.protect ~finally:(fun () -> Playwright.Browser.close browser) (fun () ->
        List.map (run_viewport ~profile ~browser ~url ~artifact_dir)
          Controller.default_viewports))
  in
  let manifest = `List (List.map fst results) in
  write_atomic (Filename.concat artifact_dir "manifest.json") manifest;
  Yojson.Safe.pretty_to_channel stdout manifest;
  output_char stdout '\n';
  if List.exists (fun (_, found) -> found <> []) results then exit 1
