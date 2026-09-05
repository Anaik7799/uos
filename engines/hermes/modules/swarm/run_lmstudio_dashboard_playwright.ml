type config = {
  url : string;
  executable : string;
  artifacts : string;
  run_id : string;
}

type viewport = { name : string; width : int; height : int }

let viewports =
  [ { name = "compact"; width = 390; height = 844 };
    { name = "medium"; width = 1024; height = 768 };
    { name = "expanded"; width = 1440; height = 900 } ]

let contains text fragment =
  let n = String.length text and m = String.length fragment in
  let rec loop index =
    index + m <= n
    && (String.sub text index m = fragment || loop (index + 1))
  in
  m = 0 || loop 0

let parse_arguments arguments =
  let fields = Hashtbl.create 4 in
  let rec loop index =
    if index = Array.length arguments then Ok ()
    else if index + 1 >= Array.length arguments then
      Error ("missing value for " ^ arguments.(index))
    else
      let key = arguments.(index) and value = arguments.(index + 1) in
      if not (List.mem key [ "--url"; "--executable"; "--artifacts"; "--run-id" ])
      then Error ("unknown argument: " ^ key)
      else if Hashtbl.mem fields key then Error ("duplicate argument: " ^ key)
      else begin
        Hashtbl.add fields key value;
        loop (index + 2)
      end
  in
  let required name =
    match Hashtbl.find_opt fields name with
    | Some value when value <> "" -> Ok value
    | _ -> Error ("required argument is absent: " ^ name)
  in
  match loop 1 with
  | Error _ as error -> error
  | Ok () ->
      (match required "--url", required "--executable",
             required "--artifacts", required "--run-id" with
       | Ok url, Ok executable, Ok artifacts, Ok run_id ->
           Ok { url; executable; artifacts; run_id }
       | Error diagnostic, _, _, _ | _, Error diagnostic, _, _
       | _, _, Error diagnostic, _ | _, _, _, Error diagnostic ->
           Error diagnostic)

let valid_artifact_path path =
  Filename.is_relative path
  && String.starts_with ~prefix:"state/browser/" path
  && not (List.mem ".." (String.split_on_char '/' path))

let validate_config config =
  match Lmstudio_dashboard_web.validate_public_url config.url,
        Lmstudio_dashboard_web.validate_timestamp config.run_id with
  | Error diagnostic, _ | _, Error diagnostic -> Error diagnostic
  | Ok (), Ok () when not (valid_artifact_path config.artifacts) ->
      Error "artifact directory must be a relative child of state/browser"
  | Ok (), Ok () when not (Sys.file_exists config.executable) ->
      Error "managed Chromium executable does not exist"
  | Ok (), Ok () when Sys.is_directory config.executable ->
      Error "managed Chromium executable is a directory"
  | Ok (), Ok () ->
      (try Unix.access config.executable [ Unix.X_OK ]; Ok ()
       with Unix.Unix_error _ -> Error "managed Chromium is not executable")

let rec ensure_directory path =
  if Sys.file_exists path then begin
    if not (Sys.is_directory path) then invalid_arg (path ^ " is not a directory")
  end
  else begin
    let parent = Filename.dirname path in
    if not (String.equal parent path) then ensure_directory parent;
    Unix.mkdir path 0o755
  end

let write_screenshot path payload =
  let bytes =
    if String.length payload >= 8
       && String.sub payload 0 8 = "\137PNG\r\n\026\n"
    then payload else Base64.decode_exn payload
  in
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel bytes)

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

let run_viewport ~browser ~config (viewport : viewport) =
  let dimensions =
    Playwright.Browser.Viewport.{ width = viewport.width; height = viewport.height }
  in
  let context =
    Playwright.Browser.new_context ~viewport:dimensions
      ~screen:Playwright.Browser.Screen.{ width = viewport.width; height = viewport.height }
      ~has_touch:(viewport.width < 840) ~is_mobile:(viewport.width < 600)
      ~color_scheme:`Dark ~reduced_motion:`Reduce browser
  in
  Fun.protect ~finally:(fun () -> Playwright.BrowserContext.close context)
    (fun () ->
      let page = Playwright.BrowserContext.new_page context in
      ignore (Playwright.Page.goto ~url:config.url ~timeout:30_000. page);
      let main = Playwright.Page.locator ~selector:"main" page in
      Playwright.Locator.wait_for ~state:`Visible ~timeout:30_000. main;
      let count selector =
        Playwright.Page.locator ~selector page |> Playwright.Locator.count
      in
      let root_box =
        Playwright.Page.locator ~selector:"html" page
        |> Playwright.Locator.bounding_box ~timeout:30_000.
      in
      let html = Playwright.Page.content page in
      let violations = ref [] in
      let require predicate diagnostic =
        if not predicate then violations := diagnostic :: !violations
      in
      require (count "html[lang='en']" = 1) "document-language";
      require (count "header" = 1 && count "main" = 1 && count "footer" = 1)
        "landmark-denominator";
      require (count "h1" = 1 && count "main h2" = 9) "heading-denominator";
      require
        (match root_box with
         | Some box -> box.width <= float viewport.width +. 0.5
         | None -> false)
        "horizontal-overflow";
      require (count "table" = count "table caption") "table-caption-denominator";
      require (count "th[role='rowheader']" >= 12) "row-header-denominator";
      let absolute_resources =
        count
          "link[href^='http'],script[src^='http'],iframe[src^='http'],img[src^='http'],video[src^='http'],audio[src^='http']"
      in
      let expected_stylesheet =
        count (Printf.sprintf "link[rel='stylesheet'][href='%s/dashboard.css']"
                 config.url)
      in
      require (absolute_resources = 1 && expected_stylesheet = 1)
        "non-same-origin-runtime-resource";
      require
        (not (contains html "localhost") && not (contains html "127.0.0.1")
         && not (contains html "0.0.0.0"))
        "forbidden-url-generated";
      require (contains html "Snapshot schema: Valid") "invalid-live-snapshot";
      List.iter
        (fun diagnostic -> violations := ("console-error:" ^ diagnostic) :: !violations)
        (console_errors page);
      List.iter
        (fun diagnostic -> violations := ("page-error:" ^ diagnostic) :: !violations)
        (page_errors page);
      let screenshot = Filename.concat config.artifacts (viewport.name ^ ".png") in
      Playwright.Page.screenshot ~full_page:true ~timeout:30_000. page
      |> write_screenshot screenshot;
      let violations = List.rev !violations in
      (`Assoc
         [ ("viewport", `String viewport.name);
           ("width", `Int viewport.width);
           ("height", `Int viewport.height);
           ("url", `String config.url);
           ("h2_count", `Int (count "main h2"));
           ("table_count", `Int (count "table"));
           ("row_header_count", `Int (count "th[role='rowheader']"));
           ("screenshot", `String screenshot);
           ("status", `String (if violations = [] then "pass" else "fail"));
           ("violations", `List (List.map (fun value -> `String value) violations)) ],
       violations))

let write_manifest path json =
  let temporary = path ^ ".tmp" in
  let channel = open_out_bin temporary in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> Yojson.Safe.pretty_to_channel channel json; output_char channel '\n');
  Sys.rename temporary path

let run config =
  let config =
    { config with artifacts = Filename.concat (Sys.getcwd ()) config.artifacts }
  in
  ensure_directory config.artifacts;
  let results =
    Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw ->
    let playwright = Playwright.create ~env ~sw () in
    Fun.protect ~finally:(fun () -> Playwright.destroy playwright) (fun () ->
      let args =
        [| "--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessRespectPreflightResults,PrivateNetworkAccessSendPreflights" |]
      in
      let browser =
        Playwright.BrowserType.launch ~executable_path:config.executable ~args
          ~headless:true ~timeout:30_000.
          (Playwright.Playwright.chromium playwright)
      in
      Fun.protect ~finally:(fun () -> Playwright.Browser.close browser) (fun () ->
        List.map (run_viewport ~browser ~config) viewports))
  in
  let manifest =
    `Assoc
      [ ("schema", `String "hermes-dashboard-playwright-v1");
        ("run_id", `String config.run_id);
        ("public_url", `String config.url);
        ("managed_chromium", `String config.executable);
        ("results", `List (List.map fst results)) ]
  in
  write_manifest (Filename.concat config.artifacts "manifest.json") manifest;
  Yojson.Safe.pretty_to_channel stdout manifest;
  output_char stdout '\n';
  if List.exists (fun (_, violations) -> violations <> []) results then 1 else 0

let () =
  match parse_arguments Sys.argv with
  | Error diagnostic -> prerr_endline diagnostic; exit 2
  | Ok config ->
      (match validate_config config with
       | Error diagnostic -> prerr_endline diagnostic; exit 2
       | Ok () -> exit (run config))
