module Feature = Infranodus_feature

type viewport = { name : string; width : int; height : int }

type action =
  | Navigate of string
  | Click of string
  | Fill of { control : string; value : string }
  | Expect_ui of string
  | Expect_api of string
  | Screenshot of string
  | Video_chapter of string

type t = {
  id : string;
  feature_id : string option;
  title : string;
  precondition : string;
  actions : action list;
  viewports : viewport list;
}

type evidence_state =
  | Declared
  | Executed_pass
  | Executed_fail of string list
  | Unavailable_observed of string

type evidence = {
  scenario_id : string;
  feature_id : string option;
  viewport : viewport;
  screenshot : string;
  video : string;
  trace : string;
  state : evidence_state;
}

let canonical_viewports =
  [
    { name = "mobile-390x844"; width = 390; height = 844 };
    { name = "tablet-768x1024"; width = 768; height = 1024 };
    { name = "desktop-1440x900"; width = 1440; height = 900 };
    { name = "large-1920x1080"; width = 1920; height = 1080 };
  ]

let id (scenario : t) = scenario.id

let feature_id (scenario : t) =
  match scenario.feature_id with Some value -> value | None -> "workflow"

let viewports (scenario : t) = scenario.viewports
let actions (scenario : t) = scenario.actions

let has_action predicate (scenario : t) = List.exists predicate scenario.actions
let has_screenshot = has_action (function Screenshot _ -> true | Navigate _ | Click _ | Fill _ | Expect_ui _ | Expect_api _ | Video_chapter _ -> false)
let has_video = has_action (function Video_chapter _ -> true | Navigate _ | Click _ | Fill _ | Expect_ui _ | Expect_api _ | Screenshot _ -> false)
let has_state_expectation = has_action (function Expect_ui _ | Expect_api _ -> true | Navigate _ | Click _ | Fill _ | Screenshot _ | Video_chapter _ -> false)

let slug value =
  String.map
    (fun character ->
      match character with
      | 'A' .. 'Z' -> Char.lowercase_ascii character
      | 'a' .. 'z' | '0' .. '9' | '-' -> character
      | ' ' | '.' | '/' | ':' | '_' -> '-'
      | _ -> '-')
    value

let scenario_of_feature feature =
  let feature_id = Feature.id feature in
  let scenario_id = "scenario-" ^ slug feature_id in
  let control = List.hd (Feature.ui_controls feature) in
  {
    id = scenario_id;
    feature_id = Some feature_id;
    title = Feature.title feature;
    precondition = "deterministic local fixture and explicit feature status";
    actions =
      [
        Navigate "/bonsai";
        Click control;
        Expect_ui (feature_id ^ " renders its typed success, unavailable, or planned state honestly");
        Expect_api (feature_id ^ " state agrees with its typed OCaml observation");
        Screenshot (scenario_id ^ "-checkpoint");
        Video_chapter (scenario_id ^ "-interaction");
      ];
    viewports = canonical_viewports;
  }

let feature_scenarios = List.map scenario_of_feature Feature.all

let workflow id title feature_ids actions =
  {
    id;
    feature_id = None;
    title;
    precondition = "seeded workspace fixture with provider outcomes fixed";
    actions =
      Navigate "/bonsai"
      :: actions
      @ [
          Expect_ui ("workflow state covers " ^ String.concat "," feature_ids);
          Expect_api "visible revision, filter, evidence, and API observations agree";
          Screenshot (id ^ "-checkpoint");
          Video_chapter (id ^ "-interaction");
        ];
    viewports = canonical_viewports;
  }

let workflows =
  [
    workflow "workflow-paste-analyze-export" "Paste, process, inspect, and export"
      [ "F2.1"; "F3.5"; "F4.1"; "F4.3"; "F5.1"; "F7.4" ]
      [ Fill { control = "research-text"; value = "Networks reveal structural gaps and source evidence." }; Click "analyze"; Click "graph-node"; Click "export" ];
    workflow "workflow-survey-segments" "Import and compare survey segments"
      [ "F2.3"; "F3.7"; "F5.7"; "F4.11"; "F5.14" ]
      [ Click "import-csv"; Click "metadata-filter"; Click "compare"; Click "analytics-download" ];
    workflow "workflow-corpus-gap-question" "Find a corpus gap and generate a grounded question"
      [ "F2.2"; "F5.4"; "F6.6"; "F6.3" ]
      [ Click "import-documents"; Click "gaps"; Click "retrieve"; Click "generate-question" ];
    workflow "workflow-live-brainstorm" "Edit, reveal, note, and replay a brainstorm"
      [ "F2.1"; "F4.6"; "F1.6"; "F4.9" ]
      [ Fill { control = "research-text"; value = "adaptive systems feedback resilience" }; Click "reveal-underlying"; Click "save-note"; Click "playback" ];
    workflow "workflow-supply-demand" "Compare deterministic search supply and demand"
      [ "F2.6"; "F4.11"; "F5.4"; "F6.3" ]
      [ Click "search-fixture"; Click "compare-difference"; Click "gaps"; Click "generate-idea" ];
    workflow "workflow-knowledge-notes" "Import notes and export a reasoning packet"
      [ "F2.9"; "F3.4"; "F4.4"; "F6.5" ]
      [ Click "import-notes"; Click "entity-mode"; Click "focus"; Click "export-prompt" ];
    workflow "workflow-failure-envelope" "Exercise unavailable, quota, retry, conflict, and delete paths"
      [ "F6.9"; "F7.9"; "F7.10" ]
      [ Click "provider-unavailable"; Click "quota-limit"; Click "retry"; Click "revision-conflict"; Click "delete-confirm" ];
    workflow "workflow-share-revoke" "Share and revoke a graph"
      [ "F1.5"; "F7.10" ]
      [ Click "share"; Click "confirm-public"; Click "revoke"; Click "confirm-private" ];
    workflow "workflow-capability-70" "Exercise the complete local and provider-bounded workbench"
      (List.map Feature.id Feature.all)
      [ Click "processing-profile"; Click "graph-camera"; Click "analytics-grid";
        Click "acquisition-workbench"; Click "provider-unavailable";
        Click "intelligence-workbench"; Click "host-adapters";
        Click "source-backup"; Click "share-visibility" ];
  ]

let duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop previous found = function
    | [] -> List.rev found |> List.sort_uniq String.compare
    | value :: rest ->
        let found = match previous with Some previous when String.equal previous value -> value :: found | None | Some _ -> found in
        loop (Some value) found rest
  in
  loop None [] sorted

let validate_feature_coverage (scenarios : t list) =
  let expected = List.map Feature.id Feature.all in
  let actual = List.filter_map (fun (scenario : t) -> scenario.feature_id) scenarios in
  if actual = expected then Ok ()
  else Error [ "feature scenarios do not form the canonical F1.1-F7.10 coverage sequence" ]

let validate (scenarios : t list) =
  let errors = ref [] in
  let add message = errors := message :: !errors in
  List.iter (fun value -> add ("duplicate scenario: " ^ value))
    (duplicates (List.map (fun (scenario : t) -> scenario.id) scenarios));
  List.iter
    (fun (scenario : t) ->
      if String.trim scenario.id = "" || String.trim scenario.title = "" || String.trim scenario.precondition = "" then
        add (scenario.id ^ " has blank metadata");
      if scenario.viewports <> canonical_viewports then add (scenario.id ^ " does not use canonical viewports");
      if not (has_screenshot scenario) then add (scenario.id ^ " has no screenshot");
      if not (has_video scenario) then add (scenario.id ^ " has no video");
      if not (has_state_expectation scenario) then add (scenario.id ^ " has no state expectation"))
    scenarios;
  let rows =
    List.concat_map
      (fun (scenario : t) -> List.map (fun viewport -> scenario.id ^ "/" ^ viewport.name) scenario.viewports)
      scenarios
  in
  List.iter (fun value -> add ("duplicate evidence row: " ^ value)) (duplicates rows);
  match List.rev !errors with [] -> Ok () | values -> Error values

let evidence_manifest (scenarios : t list) =
  List.concat_map
    (fun (scenario : t) ->
      List.map
        (fun viewport ->
          let base = scenario.id ^ "-" ^ viewport.name in
          {
            scenario_id = scenario.id;
            feature_id = scenario.feature_id;
            viewport;
            screenshot = "screenshots/" ^ base ^ ".png";
            video = "video/" ^ base ^ ".webm";
            trace = "traces/" ^ base ^ ".zip";
            state = Declared;
          })
        scenario.viewports)
    scenarios

let evidence_state_name = function
  | Declared -> "Declared"
  | Executed_pass -> "Executed_pass"
  | Executed_fail _ -> "Executed_fail"
  | Unavailable_observed _ -> "Unavailable_observed"

let validate_evidence ~exists rows =
  let errors = ref [] in
  let add message = errors := message :: !errors in
  List.iter
    (fun row ->
      let paths = [ row.screenshot; row.video; row.trace ] in
      (match row.state with
       | Declared -> ()
       | Executed_pass | Executed_fail _ ->
           List.iter (fun path -> if not (exists path) then add ("missing executed artifact: " ^ path)) paths;
           Option.iter
             (fun feature_id ->
               let normalized = slug feature_id in
               if not (List.exists (fun path ->
                   let name = String.lowercase_ascii (Filename.basename path) in
                   String.length normalized = 0 ||
                   let rec contains offset =
                     if offset + String.length normalized > String.length name then false
                     else if String.sub name offset (String.length normalized) = normalized then true
                     else contains (offset + 1)
                   in contains 0) paths)
               then add ("executed artifact feature mismatch: " ^ feature_id))
             row.feature_id
       | Unavailable_observed reason ->
           if String.trim reason = "" then add "blank unavailable evidence observation"))
    rows;
  match List.rev !errors with [] -> Ok () | found -> Error found

let action_to_yojson = function
  | Navigate path -> `Assoc [ ("kind", `String "navigate"); ("path", `String path) ]
  | Click control -> `Assoc [ ("kind", `String "click"); ("control", `String control) ]
  | Fill { control; value } -> `Assoc [ ("kind", `String "fill"); ("control", `String control); ("value", `String value) ]
  | Expect_ui value -> `Assoc [ ("kind", `String "expect_ui"); ("value", `String value) ]
  | Expect_api value -> `Assoc [ ("kind", `String "expect_api"); ("value", `String value) ]
  | Screenshot value -> `Assoc [ ("kind", `String "screenshot"); ("name", `String value) ]
  | Video_chapter value -> `Assoc [ ("kind", `String "video_chapter"); ("name", `String value) ]

let viewport_to_yojson viewport =
  `Assoc [ ("name", `String viewport.name); ("width", `Int viewport.width); ("height", `Int viewport.height) ]

let to_yojson (scenario : t) =
  `Assoc
    [
      ("id", `String scenario.id);
      ("feature_id", match scenario.feature_id with Some value -> `String value | None -> `Null);
      ("title", `String scenario.title);
      ("precondition", `String scenario.precondition);
      ("actions", `List (List.map action_to_yojson scenario.actions));
      ("viewports", `List (List.map viewport_to_yojson scenario.viewports));
    ]

let evidence_to_yojson evidence =
  `Assoc
    [
      ("scenario_id", `String evidence.scenario_id);
      ("feature_id", match evidence.feature_id with Some value -> `String value | None -> `Null);
      ("viewport", viewport_to_yojson evidence.viewport);
      ("screenshot", `String evidence.screenshot);
      ("video", `String evidence.video);
      ("trace", `String evidence.trace);
      ("verdict", `String (evidence_state_name evidence.state));
      ("violations",
       match evidence.state with
       | Executed_fail violations -> `List (List.map (fun value -> `String value) violations)
       | Unavailable_observed reason -> `List [ `String reason ]
       | Declared | Executed_pass -> `List []);
    ]
