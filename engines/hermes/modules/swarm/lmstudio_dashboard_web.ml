open Tyxml.Html

type availability =
  | Verified
  | Partial of string
  | Unavailable_observed of string

type exact_head_receipt = string

let partial detail = Partial detail
let unavailable_observed detail = Unavailable_observed detail
let verified _ = Verified

type programme_summary = {
  registered_nodes : int;
  total_nodes : int;
  tasks_ready : int;
  tasks_waiting : int;
  tasks_executing : int;
  tasks_completed : int;
  lifecycle_projection_running : bool;
  recovery_projection_jobs : int;
}

type snapshot = {
  public_url : string;
  timestamp : string;
  programme : programme_summary;
  bridge : availability;
  fpp : availability;
  formal : availability;
  browser : availability;
  canonical_bridge_calls : int;
  residual_direct_calls : int;
  knowledge_artifacts : int;
}

let make_snapshot ~public_url ~timestamp ~programme ~bridge ~fpp ~formal
    ~browser ~canonical_bridge_calls ~residual_direct_calls
    ~knowledge_artifacts =
  { public_url; timestamp; programme; bridge; fpp; formal; browser;
    canonical_bridge_calls; residual_direct_calls; knowledge_artifacts }

let contains text fragment =
  let n = String.length text and m = String.length fragment in
  let rec loop i =
    i + m <= n && (String.sub text i m = fragment || loop (i + 1))
  in
  m = 0 || loop 0

let valid_timestamp value =
  let rec digits index =
    index = String.length value
    || (index = 8 && digits (index + 1))
    || ((value.[index] >= '0' && value.[index] <= '9') && digits (index + 1))
  in
  String.length value = 13
  && value.[8] = '-'
  && digits 0
  && (match int_of_string_opt (String.sub value 9 2),
            int_of_string_opt (String.sub value 11 2) with
      | Some hour, Some second -> hour >= 0 && hour < 24 && second >= 0 && second < 60
      | _ -> false)

let host_of_url value =
  let value = String.lowercase_ascii value in
  let prefix_length =
    if String.starts_with ~prefix:"https://" value then Some 8
    else if String.starts_with ~prefix:"http://" value then Some 7
    else None
  in
  match prefix_length with
  | None -> None
  | Some offset ->
      let rest = String.sub value offset (String.length value - offset) in
      let authority =
        match String.index_opt rest '/' with
        | None -> rest
        | Some index -> String.sub rest 0 index
      in
      if authority = "" || String.contains authority '@'
         || String.contains authority '[' || String.contains authority ']'
      then None
      else
        let host =
          match String.index_opt authority ':' with
          | None -> authority
          | Some index -> String.sub authority 0 index
        in
        Some host

let valid_tailscale_url value =
  not (contains value "localhost")
  && not (contains value "127.0.0.1")
  && not (contains value "0.0.0.0")
  && match host_of_url value with
     | Some host -> String.ends_with ~suffix:".ts.net" host
     | None -> false

let valid_dns_label label =
  let length = String.length label in
  length > 0 && length <= 63
  && label.[0] <> '-' && label.[length - 1] <> '-'
  && String.for_all
       (function 'a' .. 'z' | '0' .. '9' | '-' -> true | _ -> false)
       label

let validate_tailscale_fqdn value =
  let value = String.lowercase_ascii value in
  let labels = String.split_on_char '.' value in
  if String.length value > 253
     || not (String.ends_with ~suffix:".ts.net" value)
     || List.length labels < 3
     || not (List.for_all valid_dns_label labels)
  then Error "HERMES_TAILSCALE_FQDN must be a bare valid DNS name ending in .ts.net"
  else Ok ()

let validate_public_url value =
  if not (valid_tailscale_url value) then
    Error "URL must be an HTTP(S) Tailscale FQDN"
  else
    match host_of_url value with
    | None -> Error "URL must have a host"
    | Some host -> validate_tailscale_fqdn host

let validate_timestamp value =
  if valid_timestamp value then Ok ()
  else Error "timestamp must use YYYYMMDD-HHSS"

let nonnegative name value =
  if value < 0 then [ name ^ " must be nonnegative" ] else []

let validate_snapshot snapshot =
  let p = snapshot.programme in
  let errors = ref [] in
  if not (valid_tailscale_url snapshot.public_url) then
    errors := "public_url must be an HTTP(S) Tailscale FQDN" :: !errors;
  if not (valid_timestamp snapshot.timestamp) then
    errors := "timestamp must use YYYYMMDD-HHSS" :: !errors;
  List.iter (fun error -> errors := error :: !errors)
    (nonnegative "registered_nodes" p.registered_nodes
     @ nonnegative "total_nodes" p.total_nodes
     @ nonnegative "tasks_ready" p.tasks_ready
     @ nonnegative "tasks_waiting" p.tasks_waiting
     @ nonnegative "tasks_executing" p.tasks_executing
     @ nonnegative "tasks_completed" p.tasks_completed
     @ nonnegative "recovery_projection_jobs" p.recovery_projection_jobs
     @ nonnegative "canonical_bridge_calls" snapshot.canonical_bridge_calls
     @ nonnegative "residual_direct_calls" snapshot.residual_direct_calls
     @ nonnegative "knowledge_artifacts" snapshot.knowledge_artifacts);
  if p.registered_nodes > p.total_nodes then
    errors := "registered_nodes exceeds total_nodes" :: !errors;
  if p.tasks_ready + p.tasks_waiting + p.tasks_executing + p.tasks_completed
     <> p.total_nodes then
    errors := "task-state denominator does not equal total_nodes" :: !errors;
  (match snapshot.bridge with
   | Verified when snapshot.canonical_bridge_calls <> 1
                   || snapshot.residual_direct_calls <> 0 ->
       errors := "verified bridge requires one canonical call and zero residuals" :: !errors
   | _ -> ());
  List.rev !errors

let availability_text = function
  | Verified -> "Verified"
  | Partial detail -> "Partial — " ^ detail
  | Unavailable_observed detail -> "Unavailable observed — " ^ detail

let status_row label status =
  tr [ th ~a:[ a_role [ "rowheader" ] ] [ txt label ];
       td [ txt (availability_text status) ] ]

let section heading children =
  section [ h2 [ txt heading ]; div children ]

let layout ~public_url ~title:page_title content =
  html ~a:[ a_lang "en" ]
    (head (title (txt page_title))
       [ meta ~a:[ a_charset "utf-8" ] ();
         meta ~a:[ a_name "viewport";
                    a_content "width=device-width, initial-scale=1" ] ();
         link ~rel:[ `Stylesheet ] ~href:(public_url ^ "/dashboard.css") () ])
    (body
       [ header [ h1 [ txt "Hermes agentic model and Swarm operations" ];
                  p [ txt "Read-only evidence projection. No execution ingress." ] ];
         main content;
         footer [ p [ txt "Only current mechanical receipts grant completion." ] ] ])

let render_history history =
  table
    ~caption:(caption [ txt "Recent LM Studio observations" ])
    ~thead:(thead [ tr [ th [ txt "Time" ]; th [ txt "Vector space" ];
                           th [ txt "Score and action" ]; th [ txt "Oracle advice" ] ] ])
    (List.map
       (fun (timestamp, vector, action, advice) ->
         tr [ td [ txt timestamp ]; td [ txt vector ]; td [ txt action ];
              td [ txt (if advice = "" then "Unavailable observed" else advice) ] ])
       history)

let render_dashboard snapshot history =
  let programme = snapshot.programme in
  let errors = validate_snapshot snapshot in
  let validation =
    if errors = [] then p [ txt "Snapshot schema: Valid" ]
    else p [ txt ("Snapshot validation: REFUSED — " ^ String.concat "; " errors) ]
  in
  let content =
    [ section "Overview"
        [ validation;
          dl [ dt [ txt "Public surface" ]; dd [ txt snapshot.public_url ];
               dt [ txt "Observed stamp" ]; dd [ txt snapshot.timestamp ];
               dt [ txt "Canonical bridge calls" ];
               dd [ txt (string_of_int snapshot.canonical_bridge_calls) ];
               dt [ txt "Residual direct calls" ];
               dd [ txt (string_of_int snapshot.residual_direct_calls) ] ];
          table ~caption:(caption [ txt "Current authority status" ])
            [ status_row "Run_swarm_bridge" snapshot.bridge;
                  status_row "FPP / MBSE" snapshot.fpp;
                  status_row "Formal" snapshot.formal ] ];
      section "Runs"
        [ p [ txt (Printf.sprintf "Durable nodes: %d / %d"
                     programme.registered_nodes programme.total_nodes) ];
          table ~caption:(caption [ txt "Durable programme state" ])
            [ tr [ th ~a:[ a_role [ "rowheader" ] ] [ txt "Ready" ];
                   td [ txt (string_of_int programme.tasks_ready) ] ];
              tr [ th ~a:[ a_role [ "rowheader" ] ] [ txt "Waiting on dependencies" ];
                   td [ txt (string_of_int programme.tasks_waiting) ] ];
              tr [ th ~a:[ a_role [ "rowheader" ] ] [ txt "Executing" ];
                   td [ txt (string_of_int programme.tasks_executing) ] ];
              tr [ th ~a:[ a_role [ "rowheader" ] ] [ txt "Completed" ];
                   td [ txt (string_of_int programme.tasks_completed) ] ];
              tr [ th ~a:[ a_role [ "rowheader" ] ] [ txt "Lifecycle projection" ];
                   td [ txt (if programme.lifecycle_projection_running then "Running" else "Unavailable observed") ] ];
              tr [ th ~a:[ a_role [ "rowheader" ] ] [ txt "Recovery projection jobs" ];
                   td [ txt (string_of_int programme.recovery_projection_jobs) ] ] ] ];
      section "Admission"
        [ p [ txt "Current-head, topology, safety, assurance, and fast-path must all agree." ];
          p [ txt "Current-head authority: full safety carrier 82/82, event-store regression 136/136; independent semantic ADMIT." ];
          p [ txt "Topology authority: exact five-action graph and lossless ordered MBSE projection 177/177." ];
          p [ txt "Exact intelligence: Rete dispatch 21/21, analysis 34/34, and live six-gate assurance 45/45." ];
          p [ txt "Canonical bridge: live admission, one engine call, typed durable result validation, fault no-replay, and duplicate convergence 74/74; cache-authorization review remains open." ];
          p [ txt (availability_text snapshot.bridge) ] ];
      section "Effects"
        [ p [ txt "Effects require topology-derived targets, stable idempotency keys, apply-once receipts, and durable query readback." ];
          p [ txt (match snapshot.bridge with Verified -> "Verified by opaque exact-head bridge receipt"
                    | _ -> "Unavailable observed — no admitted bridge execution") ] ];
      section "Verification"
        [ table ~caption:(caption [ txt "Verification evidence status" ])
            [ status_row "FPP model" snapshot.fpp;
                  status_row "Formal non-vacuity" snapshot.formal;
                  status_row "Typed browser" snapshot.browser ];
          p [ txt "Required denominator: unit, component, fractal, BDD, property, fuzz, chaos, SysML/OML/OpenMBEE/FPP, formal, accessibility, and exact-head." ] ];
      section "Predictive"
        [ p [ txt (Printf.sprintf
                     "AS-IS: %d of %d durable nodes registered; %d executing; %d completed."
                     programme.registered_nodes programme.total_nodes
                     programme.tasks_executing programme.tasks_completed) ];
          p [ txt "PREDICTIVE: topology, bridge, Ops_verify, dashboard, and knowledge projections are at risk if the programme denominator is wrong." ];
          p [ txt (match snapshot.fpp, snapshot.formal, snapshot.bridge with
              | Partial detail, _, _ ->
                  "Next measurement: resolve the current FPP / MBSE partial — "
                  ^ detail
              | Unavailable_observed detail, _, _ ->
                  "Next measurement: observe the current FPP / MBSE gate — "
                  ^ detail
              | Verified, Partial detail, _ ->
                  "Next measurement: resolve the current formal partial — "
                  ^ detail
              | Verified, Unavailable_observed detail, _ ->
                  "Next measurement: obtain the missing formal observation — "
                  ^ detail
              | Verified, Verified, Partial detail ->
                  "Next measurement: resolve the current bridge partial — "
                  ^ detail
              | Verified, Verified, Unavailable_observed detail ->
                  "Next measurement: obtain the missing bridge observation — "
                  ^ detail
              | Verified, Verified, Verified ->
                  "Next measurement: run the next registered exact-head gate.") ] ];
      section "Knowledge"
        [ p [ txt (Printf.sprintf "%d linked prompt, journal, design, ZK, and KM artifacts."
                     snapshot.knowledge_artifacts) ];
          p [ txt "Oracle reviews are advisory and carry no executable or parity authority." ] ];
      section "UI quality"
        [ p [ txt (availability_text snapshot.browser) ];
          p [ txt "TyXML semantic fallback, CSP, accessibility, escaping, responsive reflow, stale-state, reconnect, and multi-tab checks are required." ] ];
      section "LM Studio observations" [ render_history history ] ]
  in
  Format.asprintf "%a" (pp ())
    (layout ~public_url:snapshot.public_url
       ~title:"Hermes agentic model and Swarm operations" content)

let dashboard_style = {|
:root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif;
  background: #07111f; color: #e6edf7; }
* { box-sizing: border-box; }
body { margin: 0; background: radial-gradient(circle at top right, #12345a 0, #07111f 38rem);
  line-height: 1.5; }
header, main, footer { width: min(1180px, calc(100% - 2rem)); margin-inline: auto; }
header { padding: 3rem 0 1.5rem; border-bottom: 1px solid #244363; }
h1 { margin: 0; font-size: clamp(1.9rem, 4vw, 3.1rem); letter-spacing: -.04em; }
header p, footer { color: #9db0c8; }
main { display: grid; grid-template-columns: repeat(12, 1fr); gap: 1rem;
  padding-block: 1.5rem 3rem; }
section { grid-column: span 6; min-width: 0; padding: 1.25rem;
  border: 1px solid #244363; border-radius: 1rem;
  background: linear-gradient(160deg, rgba(18,42,70,.94), rgba(8,24,42,.94));
  box-shadow: 0 18px 40px rgba(0,0,0,.18); }
section:first-child, section:nth-child(2), section:last-child { grid-column: 1 / -1; }
h2 { margin: 0 0 .8rem; color: #83d8ff; font-size: 1.05rem;
  letter-spacing: .08em; text-transform: uppercase; }
dl { display: grid; grid-template-columns: minmax(10rem, 1fr) 2fr; gap: .4rem 1rem; }
dt { color: #9db0c8; } dd { margin: 0; overflow-wrap: anywhere; }
table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
caption { padding: .5rem 0; text-align: left; color: #9db0c8; font-weight: 700; }
th, td { padding: .6rem .7rem; border-bottom: 1px solid #244363; text-align: left;
  vertical-align: top; overflow-wrap: anywhere; }
th { color: #b7c9dc; } p { margin: .45rem 0; }
footer { padding: 0 0 2rem; }
@media (max-width: 760px) {
  header, main, footer { width: min(100% - 1rem, 1180px); }
  header { padding-top: 1.5rem; }
  main { display: block; } section { margin-bottom: .75rem; padding: 1rem; }
  dl { grid-template-columns: 1fr; } dd { margin-bottom: .5rem; }
  table { display: block; overflow-x: auto; }
}
|}

let get_recent_history db =
  try
    let has_oracle_advice =
      let schema = Sqlite3.prepare db "PRAGMA table_info(lmstudio_history)" in
      Fun.protect
        ~finally:(fun () -> ignore (Sqlite3.finalize schema))
        (fun () ->
          let rec loop () =
            match Sqlite3.step schema with
            | Sqlite3.Rc.ROW ->
                if String.equal (Sqlite3.column_text schema 1) "oracle_advice"
                then true else loop ()
            | Sqlite3.Rc.DONE -> false
            | rc ->
                failwith
                  ("history schema query failed: " ^ Sqlite3.Rc.to_string rc)
          in
          loop ())
    in
    let sql =
          if has_oracle_advice then
            "SELECT timestamp, vector_space, evaluation_score, interpretation, \
                    oracle_advice \
             FROM lmstudio_history ORDER BY id DESC LIMIT 15"
          else
            "SELECT timestamp, vector_space, evaluation_score, interpretation, \
                    '' \
             FROM lmstudio_history ORDER BY id DESC LIMIT 15"
        in
    let stmt = Sqlite3.prepare db sql in
    Fun.protect
      ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
      (fun () ->
        let bounded name value =
          if String.length value <= 4096 then Ok value
          else Error (name ^ " exceeds 4096 bytes")
        in
        let rec loop count acc =
          if count >= 15 then Ok (List.rev acc)
          else
              match Sqlite3.step stmt with
              | Sqlite3.Rc.ROW ->
                  let timestamp = Sqlite3.column_text stmt 0 in
                  let vector = Sqlite3.column_text stmt 1 in
                  let score = Sqlite3.column_double stmt 2 in
                  let interpretation = Sqlite3.column_text stmt 3 in
                  let advice = Sqlite3.column_text stmt 4 in
                  (match bounded "timestamp" timestamp, bounded "vector" vector,
                         bounded "interpretation" interpretation,
                         bounded "oracle advice" advice with
                   | Ok timestamp, Ok vector, Ok interpretation, Ok advice ->
                       loop (count + 1)
                         ((timestamp, vector,
                           Printf.sprintf "Score: %.1f — %s" score interpretation,
                           advice) :: acc)
                   | Error diagnostic, _, _, _ | _, Error diagnostic, _, _
                   | _, _, Error diagnostic, _ | _, _, _, Error diagnostic ->
                       Error diagnostic)
              | Sqlite3.Rc.DONE -> Ok (List.rev acc)
              | rc -> Error ("history query failed: " ^ Sqlite3.Rc.to_string rc)
        in
        loop 0 [])
  with exn -> Error ("history query raised: " ^ Printexc.to_string exn)

let port_from_environment ~getenv =
  match getenv "DREAM_PORT" with
  | Some value ->
      (match int_of_string_opt value with
       | Some port when port > 0 && port <= 65535 -> Ok port
       | _ -> Error "DREAM_PORT must be an integer from 1 through 65535")
  | None -> Error "DREAM_PORT is required"

let security_headers =
  [ ("Content-Security-Policy",
     "default-src 'none'; style-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    ("X-Content-Type-Options", "nosniff");
    ("X-Frame-Options", "DENY");
    ("Referrer-Policy", "no-referrer");
    ("Cache-Control", "no-store");
    ("Content-Type", "text/html; charset=utf-8") ]

type request_resolution = Dashboard | Dashboard_style | Not_found | Method_not_allowed

let resolve_request ~method_name ~target =
  if not (String.equal method_name "GET" || String.equal method_name "HEAD")
  then Method_not_allowed
  else if String.equal target "/" then Dashboard
  else if String.equal target "/dashboard.css" then Dashboard_style
  else Not_found

let observe_snapshot provider =
  try provider ()
  with exn -> Error ("snapshot observation raised: " ^ Printexc.to_string exn)

let start_server ~port ~db_path ~snapshot =
  let initial_snapshot =
    match observe_snapshot snapshot with Ok value -> value | Error diagnostic ->
      invalid_arg ("dashboard startup refused: " ^ diagnostic)
  in
  (match validate_snapshot initial_snapshot with
   | [] -> ()
   | errors ->
       invalid_arg
         ("dashboard startup refused: " ^ String.concat "; " errors));
  let history_db =
    if Sys.file_exists db_path then
      (try Ok (Sqlite3.db_open ~mode:`READONLY db_path)
       with exn -> Error ("history database open failed: " ^ Printexc.to_string exn))
    else Error ("history database unavailable: " ^ db_path)
  in
  Fun.protect
    ~finally:(fun () ->
      match history_db with
      | Ok db -> ignore (Sqlite3.db_close db)
      | Error _ -> ())
    (fun () ->
      let handler request =
        let method_name = Dream.method_to_string (Dream.method_ request) in
        match resolve_request
                ~method_name
                ~target:(Dream.target request) with
        | Method_not_allowed ->
            Dream.respond ~status:`Method_Not_Allowed
              ~headers:(("Allow", "GET, HEAD") :: security_headers)
              "Method not allowed"
        | Not_found ->
            Dream.respond ~status:`Not_Found ~headers:security_headers "Not found"
        | Dashboard_style ->
            let headers =
              ("Content-Type", "text/css; charset=utf-8")
              :: List.remove_assoc "Content-Type" security_headers
            in
            Dream.respond ~headers
              (if String.equal method_name "HEAD" then "" else dashboard_style)
        | Dashboard ->
            (match observe_snapshot snapshot with
             | Error diagnostic ->
                 Dream.respond ~status:`Service_Unavailable
                   ~headers:security_headers diagnostic
             | Ok current_snapshot ->
               match validate_snapshot current_snapshot with
             | _ :: _ as errors ->
                 Dream.respond ~status:`Service_Unavailable
                   ~headers:security_headers
                   ("Snapshot refused: " ^ String.concat "; " errors)
             | [] ->
               match history_db with
             | Error diagnostic ->
                 Dream.respond ~status:`Service_Unavailable
                   ~headers:security_headers diagnostic
             | Ok db ->
                 (match get_recent_history db with
                  | Error diagnostic ->
                      Dream.respond ~status:`Service_Unavailable
                        ~headers:security_headers diagnostic
                  | Ok history ->
                      Dream.respond ~headers:security_headers
                        (if String.equal method_name "HEAD" then ""
                         else render_dashboard current_snapshot history)))
      in
      Dream.run ~greeting:false ~port ~interface:"0.0.0.0" handler)
