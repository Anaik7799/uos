module Controller = Playwright_control.Playwright_controller
module Contract = Playwright_control.Journal_playwright_contract
module Bundle = Journal_bundle_core.Journal_bundle

let find_arg name default =
  let rec loop index =
    if index + 1 >= Array.length Sys.argv then default
    else if String.equal Sys.argv.(index) name then Sys.argv.(index + 1)
    else loop (index + 1)
  in
  loop 1

let count_substring ~needle value =
  let rec loop offset count =
    if String.length needle = 0 || offset + String.length needle > String.length value
    then count
    else if String.sub value offset (String.length needle) = needle then
      loop (offset + String.length needle) (count + 1)
    else loop (offset + 1) count
  in
  loop 0 0

let remote_css_count page =
  let remote_patterns =
    [ "url(http:"; "url(https:"; "url(//"; "@import \"http";
      "@import 'http"; "@import url(http" ]
  in
  let count_text text =
    let lowered = String.lowercase_ascii text in
    List.fold_left
      (fun count pattern -> count + count_substring ~needle:pattern lowered)
      0 remote_patterns
  in
  let style_text =
    Playwright.Page.locator ~selector:"style" page
    |> Playwright.Locator.all_text_contents
    |> List.fold_left (fun count text -> count + count_text text) 0
  in
  let inline = Playwright.Page.locator ~selector:"[style]" page in
  let inline_count = Playwright.Locator.count inline in
  let rec count_inline index count =
    if index >= inline_count then count
    else
      let value =
        Playwright.Locator.nth index inline
        |> Playwright.Locator.get_attribute ~name:"style"
        |> Option.value ~default:""
      in
      count_inline (index + 1) (count + count_text value)
  in
  style_text + count_inline 0 0

let rec ensure_directory path =
  if Sys.file_exists path then begin
    if not (Sys.is_directory path) then failwith (path ^ " is not a directory")
  end else begin
    let parent = Filename.dirname path in
    if not (String.equal parent path) then ensure_directory parent;
    Unix.mkdir path 0o755
  end

let require_box label locator =
  match Playwright.Locator.bounding_box ~timeout:10000. locator with
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

let run_viewport ~browser ~url ~artifact_dir ~expected_prompt_markers
    ~expected_title ~expected_sha256
    (viewport : Controller.viewport) =
  let dimensions = Playwright.Browser.Viewport.{ width = viewport.width; height = viewport.height } in
  let context =
    Playwright.Browser.new_context ~viewport:dimensions
      ~screen:Playwright.Browser.Screen.{ width = viewport.width; height = viewport.height }
      ~has_touch:(viewport.width < 840) ~is_mobile:(viewport.width < 600)
      ~color_scheme:`Light ~reduced_motion:`Reduce browser
  in
  Fun.protect
      ~finally:(fun () -> Playwright.BrowserContext.close context)
    (fun () ->
      let page = Playwright.BrowserContext.new_page context in
      let response =
        match Playwright.Page.goto ~url ~timeout:30000. page with
        | Some response -> response
        | None -> failwith ("route produced no HTTP response: " ^ url)
      in
      let observed_title = Playwright.Page.title page in
      let observed_sha256 =
        Playwright.Response.body response |> Bundle.fingerprint
      in
      let route_violations =
        Contract.orient_route_identity
          { expected_title; observed_title; expected_sha256; observed_sha256 }
      in
      let root =
        Playwright.Page.locator ~selector:"html" page |> require_box "html"
      in
      let count selector =
        Playwright.Page.locator ~selector page |> Playwright.Locator.count
      in
      let observation =
        Contract.
          { viewport_width = float viewport.width;
            root_width = root.width;
            heading_count = count "main h1";
            artifact_count = count ".artifact";
            prompt_ledger_count =
              count "details.artifact summary:has-text('Canonical verbatim prompt ledger')";
            remote_resource_count =
              count
                "link[href^='http:'],link[href^='https:'],link[href^='//'],base[href^='http:'],base[href^='https:'],base[href^='//'],script[src^='http:'],script[src^='https:'],script[src^='//'],iframe[src^='http:'],iframe[src^='https:'],iframe[src^='//'],frame[src^='http:'],frame[src^='https:'],frame[src^='//'],img[src^='http:'],img[src^='https:'],img[src^='//'],audio[src^='http:'],audio[src^='https:'],audio[src^='//'],video[src^='http:'],video[src^='https:'],video[src^='//'],video[poster^='http:'],video[poster^='https:'],video[poster^='//'],source[src^='http:'],source[src^='https:'],source[src^='//'],track[src^='http:'],track[src^='https:'],track[src^='//'],object[data^='http:'],object[data^='https:'],object[data^='//'],embed[src^='http:'],embed[src^='https:'],embed[src^='//'],form[action^='http:'],form[action^='https:'],form[action^='//'],input[type='image'][src^='http:'],input[type='image'][src^='https:'],input[type='image'][src^='//'],use[href^='http:'],use[href^='https:'],use[href^='//'],use[xlink\\:href^='http:'],use[xlink\\:href^='https:'],use[xlink\\:href^='//'],image[href^='http:'],image[href^='https:'],image[href^='//'],meta[http-equiv='refresh'][content*='http:'],meta[http-equiv='refresh'][content*='https:'],meta[http-equiv='refresh'][content*='//']";
            remote_css_reference_count = remote_css_count page;
            required_prompt_marker_count =
              (Playwright.Page.locator
                 ~selector:"details.artifact:has(summary:has-text('Canonical verbatim prompt ledger'))"
                 page
               |> Playwright.Locator.all_text_contents
               |> List.fold_left
                    (fun total content ->
                      total + count_substring ~needle:"\"ordinal\":" content)
                    0);
            expected_prompt_marker_count = expected_prompt_markers;
            console_errors = console_errors page;
            page_errors = page_errors page }
      in
      let screenshot = Filename.concat artifact_dir (viewport.name ^ ".png") in
      Playwright.Page.screenshot ~full_page:false ~timeout:30000. page
      |> Controller.write_screenshot screenshot;
      let violations = route_violations @ Contract.orient observation in
      let json =
        `Assoc
          [ ("viewport", `String viewport.name);
            ("width", `Int viewport.width);
            ("height", `Int viewport.height);
            ("artifact_count", `Int observation.artifact_count);
            ("prompt_ledger_count", `Int observation.prompt_ledger_count);
            ("remote_resource_count", `Int observation.remote_resource_count);
            ("expected_title", `String expected_title);
            ("observed_title", `String observed_title);
            ("expected_sha256", `String expected_sha256);
            ("observed_sha256", `String observed_sha256);
            ("screenshot", `String screenshot);
            ("status", `String (if violations = [] then "pass" else "fail"));
            ("violations",
             `List (List.map (fun value -> `String (Contract.violation_name value)) violations)) ]
      in
      (json, violations))

let () =
  let url = find_arg "--url" "" in
  let executable_path = find_arg "--executable" "" in
  let artifact_dir = find_arg "--artifacts" "/tmp/journal-playwright" in
  let expected_prompt_markers =
    find_arg "--expected-prompt-markers" "0" |> int_of_string
  in
  let expected_title = find_arg "--expected-title" "" in
  let expected_source = find_arg "--expected-source" "" in
  if String.equal url "" || String.equal executable_path "" ||
     String.equal expected_title "" || String.equal expected_source ""
  then begin
    Printf.eprintf
      "--url, --executable, --expected-title, and --expected-source are required\n%!";
    exit 2
  end;
  let expected_sha256 =
    let channel = open_in_bin expected_source in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () ->
        really_input_string channel (in_channel_length channel)
        |> Bundle.fingerprint)
  in
  ensure_directory artifact_dir;
  let results =
    Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw ->
    let playwright = Playwright.create ~env ~sw () in
    Fun.protect ~finally:(fun () -> Playwright.destroy playwright) (fun () ->
      let browser =
        Playwright.BrowserType.launch ~executable_path ~headless:true ~timeout:30000.
          (Playwright.Playwright.chromium playwright)
      in
      Fun.protect ~finally:(fun () -> Playwright.Browser.close browser) (fun () ->
        List.map
          (run_viewport ~browser ~url ~artifact_dir ~expected_prompt_markers
             ~expected_title ~expected_sha256)
          Controller.default_viewports))
  in
  let manifest = `List (List.map fst results) in
  let manifest_path = Filename.concat artifact_dir "manifest.json" in
  let channel = open_out_bin manifest_path in
  Yojson.Safe.pretty_to_channel channel manifest;
  output_char channel '\n';
  close_out channel;
  Yojson.Safe.pretty_to_channel stdout manifest;
  output_char stdout '\n';
  if List.exists (fun (_, violations) -> violations <> []) results then exit 1
