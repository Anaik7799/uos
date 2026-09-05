module H = Tyxml.Html

type stage =
  | Decode
  | Validate
  | Materialize
  | Discover
  | Acquire
  | Zk
  | Wiki
  | Render
  | Publish
  | Report

type status =
  | Started
  | Completed of { duration_ms : int }
  | Skipped of { reason : string; duration_ms : int }
  | Failed of { message : string; duration_ms : int }

type measurement = {
  work_items : int option;
  bytes : int option;
  domains : int option;
  wiki_notes : int option;
  artifacts : int option;
}

type event = {
  sequence : int;
  timestamp_ns : int64;
  stage : stage;
  status : status;
  measurement : measurement;
}

type summary = {
  events : event list;
  started_count : int;
  terminal_count : int;
  failed_count : int;
  work_items_total : int;
  bytes_total : int;
  duration_ms_total : int;
  max_domains : int;
  max_wiki_notes : int option;
  max_artifacts : int option;
}

type violation =
  | Missing_terminal of stage
  | Duplicate_terminal of stage
  | Terminal_without_start of stage

type budget_violation = {
  budget_stage : stage;
  actual_ms : int;
  budget_ms : int;
}

let empty_measurement =
  { work_items = None; bytes = None; domains = None;
    wiki_notes = None; artifacts = None }

let make ~sequence ~timestamp_ns ~stage ~status ~measurement () =
  { sequence; timestamp_ns; stage; status; measurement }

let event_stage event = event.stage
let event_status event = event.status

let stage_name = function
  | Decode -> "decode"
  | Validate -> "validate"
  | Materialize -> "materialize"
  | Discover -> "discover"
  | Acquire -> "acquire"
  | Zk -> "zk"
  | Wiki -> "wiki"
  | Render -> "render"
  | Publish -> "publish"
  | Report -> "report"

let stage_budget_ms = function
  | Decode -> 100
  | Validate -> 250
  | Materialize -> 1_000
  | Discover -> 1_000
  | Acquire -> 2_000
  | Zk -> 30_000
  | Wiki -> 30_000
  | Render -> 2_000
  | Publish -> 2_000
  | Report -> 500

let warm_path_budget_ms = 1_500
let within_warm_path_budget ~duration_ms = duration_ms < warm_path_budget_ms

let terminal = function Started -> false | Completed _ | Skipped _ | Failed _ -> true

let duration = function
  | Started -> 0
  | Completed { duration_ms }
  | Skipped { duration_ms; _ }
  | Failed { duration_ms; _ } -> duration_ms

let option_value = Option.value ~default:0

let max_option current candidate =
  match current, candidate with
  | value, None -> value
  | None, Some value -> Some value
  | Some left, Some right -> Some (max left right)

let fold events =
  List.fold_left
    (fun summary event ->
      { events = event :: summary.events;
        started_count =
          summary.started_count + if event.status = Started then 1 else 0;
        terminal_count =
          summary.terminal_count + if terminal event.status then 1 else 0;
        failed_count =
          summary.failed_count +
          (match event.status with Failed _ -> 1 | _ -> 0);
        work_items_total =
          summary.work_items_total + option_value event.measurement.work_items;
        bytes_total = summary.bytes_total + option_value event.measurement.bytes;
        duration_ms_total = summary.duration_ms_total + duration event.status;
        max_domains =
          max summary.max_domains (option_value event.measurement.domains);
        max_wiki_notes =
          max_option summary.max_wiki_notes event.measurement.wiki_notes;
        max_artifacts =
          max_option summary.max_artifacts event.measurement.artifacts })
    { events = []; started_count = 0; terminal_count = 0; failed_count = 0;
      work_items_total = 0; bytes_total = 0; duration_ms_total = 0;
      max_domains = 0; max_wiki_notes = None; max_artifacts = None }
    events
  |> fun summary -> { summary with events = List.rev summary.events }

let all_stages =
  [ Decode; Validate; Materialize; Discover; Acquire; Zk; Wiki; Render;
    Publish; Report ]

let violations summary =
  List.fold_left
    (fun found stage ->
      let starts, terminals =
        List.fold_left
          (fun (starts, terminals) event ->
            if event.stage <> stage then starts, terminals
            else if event.status = Started then starts + 1, terminals
            else starts, terminals + 1)
          (0, 0) summary.events
      in
      if starts = 0 && terminals = 0 then found
      else if starts = 0 then Terminal_without_start stage :: found
      else if terminals = 0 then Missing_terminal stage :: found
      else if terminals > 1 then Duplicate_terminal stage :: found
      else found)
    [] all_stages
  |> List.rev

let budget_violations summary =
  summary.events
  |> List.filter_map (fun event ->
       if not (terminal event.status) then None
       else
         let actual_ms = duration event.status in
         let budget_ms = stage_budget_ms event.stage in
         if actual_ms <= budget_ms then None
         else Some { budget_stage = event.stage; actual_ms; budget_ms })

let budget_violation_name violation =
  Printf.sprintf "stage-budget-exceeded(%s:%dms>%dms)"
    (stage_name violation.budget_stage) violation.actual_ms violation.budget_ms

let violation_name = function
  | Missing_terminal stage -> "missing-terminal(" ^ stage_name stage ^ ")"
  | Duplicate_terminal stage -> "duplicate-terminal(" ^ stage_name stage ^ ")"
  | Terminal_without_start stage ->
      "terminal-without-start(" ^ stage_name stage ^ ")"

let status_name = function
  | Started -> "START"
  | Completed _ -> "DONE"
  | Skipped _ -> "SKIP"
  | Failed _ -> "FAIL"

let status_colour = function
  | Started -> "\027[36m"
  | Completed _ -> "\027[32m"
  | Skipped _ -> "\027[33m"
  | Failed _ -> "\027[31m"

let render_tui events =
  events
  |> List.map (fun event ->
       let actual_ms = duration event.status in
       let budget_ms = stage_budget_ms event.stage in
       let budget_state =
         if event.status = Started then "PENDING"
         else if actual_ms <= budget_ms then "IN"
         else "OVER"
       in
       Printf.sprintf "%s[%04d] %-5s\027[0m  %-12s %6d/%-6dms %-7s work=%d bytes=%d domains=%d"
         (status_colour event.status) event.sequence (status_name event.status)
         (stage_name event.stage) actual_ms budget_ms budget_state
         (option_value event.measurement.work_items)
         (option_value event.measurement.bytes)
         (option_value event.measurement.domains))
  |> String.concat "\n"

(* Static stylesheet: a compile-time constant, never data. Emitted with
   Unsafe.data, not txt — TyXML escapes text content, so a child combinator in a
   selector would emit escaped and the rule would silently stop matching. *)
let dashboard_css =
  String.concat ""
    [ ":root{color-scheme:dark;--bg:#0b1117;--panel:#121c26;--ink:#e8f0f7;--muted:#93a4b5;--ok:#53d18b;--line:#294052}";
      "*{box-sizing:border-box}";
      "body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 ui-monospace,SFMono-Regular,monospace}";
      "main{width:min(1180px,calc(100% - 24px));margin:24px auto}";
      ".grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}";
      ".card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px}";
      ".n{font-size:2rem;color:var(--ok)}";
      "table{width:100%;margin-top:18px;border-collapse:collapse;background:var(--panel)}";
      "th,td{padding:9px;border:1px solid var(--line);text-align:left}";
      "small{color:var(--muted)}";
      "@media(max-width:720px){table{display:block;overflow-x:auto;white-space:nowrap}}" ]

let event_row event =
  let actual_ms = duration event.status in
  let budget_ms = stage_budget_ms event.stage in
  let budget_state =
    if event.status = Started then "pending"
    else if actual_ms <= budget_ms then "in budget"
    else "over budget"
  in
  let cell value = H.td [ H.txt value ] in
  H.tr
    [ cell (string_of_int event.sequence);
      cell (stage_name event.stage);
      cell (status_name event.status);
      cell (string_of_int actual_ms);
      cell (string_of_int budget_ms);
      cell budget_state;
      cell (string_of_int (option_value event.measurement.work_items));
      cell (string_of_int (option_value event.measurement.bytes));
      cell (string_of_int (option_value event.measurement.domains)) ]

let render_dashboard ~title summary =
  let card label value =
    H.div
      ~a:[ H.a_class [ "card" ] ]
      [ H.txt label;
        H.div ~a:[ H.a_class [ "n" ] ] [ H.txt (string_of_int value) ] ]
  in
  let head_row =
    H.tr
      (List.map
         (fun label -> H.th [ H.txt label ])
         [ "#"; "stage"; "state"; "actual ms"; "budget ms"; "budget state";
           "work"; "bytes"; "domains" ])
  in
  (* tablex, NOT table: TyXML's `table` content is [ `Tr ] only, and a literal
     <tbody> needs `tablex`. The Playwright observation counts `tbody tr`, so the
     tbody must survive in the source rather than rely on the browser inserting
     one implicitly. *)
  let page =
    H.html
      ~a:[ H.a_lang "en" ]
      (H.head
         (H.title (H.txt title))
         [ H.meta ~a:[ H.a_charset "utf-8" ] ();
           H.meta
             ~a:[ H.a_name "viewport"; H.a_content "width=device-width,initial-scale=1" ]
             ();
           H.meta ~a:[ H.a_http_equiv "refresh"; H.a_content "2" ] ();
           H.style [ H.Unsafe.data dashboard_css ] ])
      (H.body
         [ H.main
             [ H.h1 [ H.txt title ];
               H.small
                 [ H.txt
                     "OCaml bundle pipeline \194\183 report-only observation plane \194\183 refresh 2s \194\183 every stage shows actual / budget" ];
               H.div
                 ~a:[ H.a_class [ "grid" ] ]
                 [ card "events" (List.length summary.events);
                   card "started" summary.started_count;
                   card "terminal" summary.terminal_count;
                   card "failed" summary.failed_count;
                   card "duration ms" summary.duration_ms_total;
                   card "bytes" summary.bytes_total;
                   card "work items" summary.work_items_total;
                   card "max domains" summary.max_domains ];
               H.tablex
                 ~thead:(H.thead [ head_row ])
                 [ H.tbody (List.map event_row summary.events) ] ] ])
  in
  Format.asprintf "%a" (H.pp ()) page

let render_metrics summary =
  let option_int = function None -> `Null | Some value -> `Int value in
  `Assoc
    [ ("events", `Int (List.length summary.events));
      ("started", `Int summary.started_count);
      ("terminal", `Int summary.terminal_count);
      ("failed", `Int summary.failed_count);
      ("work_items_total", `Int summary.work_items_total);
      ("bytes_total", `Int summary.bytes_total);
      ("duration_ms_total", `Int summary.duration_ms_total);
      ("max_domains", `Int summary.max_domains);
      ("wiki_notes", option_int summary.max_wiki_notes);
      ("artifacts", option_int summary.max_artifacts);
      ("warm_path_budget_ms", `Int warm_path_budget_ms);
      ("stage_budgets_ms",
       `Assoc
         (List.map
            (fun stage -> stage_name stage, `Int (stage_budget_ms stage))
            all_stages));
      ("budget_violations",
       `List
         (List.map
            (fun violation -> `String (budget_violation_name violation))
            (budget_violations summary)));
      ("complexity_acquisition", `String "O(files + bytes)");
      ("complexity_discovery", `String "O(paths)");
      ("complexity_zk", `String "O(notes^2 + edges)");
      ("complexity_wiki", `String "O(notes + edges)");
      ("complexity_assembly", `String "O(artifacts + bytes)") ]

let attribute key value =
  `Assoc [ ("key", `String key); ("value", `Assoc [ ("intValue", `String (string_of_int value)) ]) ]

let log_record ~trace_id event =
  let severity_number, severity_text =
    match event.status with Failed _ -> 17, "ERROR" | _ -> 9, "INFO"
  in
  let span_seed =
    Journal_bundle_core.Journal_bundle_digest.sha256_string
      (trace_id ^ stage_name event.stage ^ string_of_int event.sequence)
  in
  let span_id = String.sub span_seed 0 16 in
  `Assoc
    [ ("timeUnixNano", `String (Int64.to_string event.timestamp_ns));
      ("observedTimeUnixNano", `String (Int64.to_string event.timestamp_ns));
      ("severityNumber", `Int severity_number);
      ("severityText", `String severity_text);
      ("body",
       `Assoc
         [ ("stringValue",
            `String (stage_name event.stage ^ " " ^ status_name event.status)) ]);
      ("eventName", `String ("zigvm.journal_bundle." ^ stage_name event.stage));
      ("attributes",
       `List
         [ attribute "bundle.sequence" event.sequence;
           attribute "bundle.duration_ms" (duration event.status);
           attribute "bundle.stage_budget_ms" (stage_budget_ms event.stage);
           attribute "bundle.work_items" (option_value event.measurement.work_items);
           attribute "bundle.bytes" (option_value event.measurement.bytes);
           attribute "bundle.domains" (option_value event.measurement.domains) ]);
      ("traceId", `String trace_id);
      ("spanId", `String span_id);
      ("flags", `Int 1) ]

let render_otel_file ~trace_id events =
  `Assoc
    [ ("resourceLogs",
       `List
         [ `Assoc
             [ ("resource",
                `Assoc
                  [ ("attributes",
                     `List
                       [ `Assoc
                           [ ("key", `String "service.name");
                             ("value",
                              `Assoc
                                [ ("stringValue",
                                   `String "zigvm-journal-bundle") ]) ] ]) ]);
               ("scopeLogs",
                `List
                  [ `Assoc
                      [ ("scope",
                         `Assoc
                           [ ("name", `String "zigvm.journal_bundle");
                             ("version", `String "1") ]);
                        ("logRecords",
                         `List (List.map (log_record ~trace_id) events)) ] ]) ] ]) ]

let preserve_bundle_violations violations _summary = violations
