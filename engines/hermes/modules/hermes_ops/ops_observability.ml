type source_context = {
  source_revision : string;
  source_clean : bool;
  configuration_digest : string;
  authority_digest : string;
}

type event = {
  run_id : string;
  request_id : string;
  recorded_at_ns : int64;
  source : source_context;
  plane : string;
  surface : string;
  fractal_coordinate : string;
  ooda_phase : string;
  rca_origin : Ops_capability.rca_origin option;
  mediation : string;
  resource : string;
  duration_ns : int64;
  verdict : string;
  receipt_digest : string;
}

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let supply_name = function
  | Ops_config.Environment -> "environment"
  | Toolchain -> "toolchain"
  | Derived -> "derived"

let secrecy_name = function
  | Ops_config.Not_secret -> "not-secret"
  | Presence_only -> "presence-only"
  | Value_used -> "value-used"

let necessity_name = function
  | Ops_config.Required -> "required"
  | Optional_flag -> "optional-flag"
  | Override -> "override"

let configuration_digest () =
  Ops_config.elements
  |> List.map (fun (item : Ops_config.element) ->
         `Assoc
           [ ("key", `String item.key);
             ("layer", `String (Ops_config.layer_name item.layer));
             ("supply", `String (supply_name item.supply));
             ("secrecy", `String (secrecy_name item.secrecy));
             ("necessity", `String (necessity_name item.necessity));
             ("purpose", `String item.purpose);
             ("consumer", `String item.consumer);
             ("note", `String item.note) ])
  |> fun values -> `List values |> Yojson.Safe.to_string |> sha256

let evidence_name = function
  | Ops_capability.Structural -> "structural"
  | Functional -> "functional"
  | Differential -> "differential"
  | Formal -> "formal"
  | Mutation -> "mutation"
  | Resource -> "resource"
  | Publication -> "publication"

let coordinate_json (coordinate : Ops_capability.coordinate) =
  `Assoc
    [ ("level", `String (Ops_capability.string_of_level coordinate.level));
      ("phase", `String (Ops_capability.string_of_phase coordinate.phase)) ]

let declaration_json (item : Ops_capability.declaration) =
  `Assoc
    [ ("id", `String item.id);
      ("kind", `String (Ops_capability.string_of_kind item.kind));
      ("purpose", `String item.purpose);
      ("authority", `String item.authority);
      ("owner", `String item.owner);
      ("dependencies", `List (List.map (fun value -> `String value) item.dependencies));
      ("path", `List (List.map coordinate_json item.path));
      ("evidence", `List (List.map (fun value -> `String (evidence_name value)) item.evidence));
      ("plane", `String (Ops_capability.string_of_plane item.plane));
      ("surfaces",
       `List
         (List.map
            (fun (surface, applicability) ->
              `Assoc
                [ ("surface", `String (Ops_capability.string_of_surface surface));
                  ("applicability",
                   `String
                     (match applicability with
                     | Ops_capability.Applicable -> "applicable"
                     | Not_applicable reason -> "not-applicable:" ^ reason)) ])
            item.surfaces)) ]

let obligation_json (item : Ops_governance.obligation) =
  `Assoc
    [ ("id", `String item.id);
      ("domain", `String (Ops_governance.string_of_domain item.domain));
      ("declaration_id", `String item.declaration_id);
      ("command", `String item.command);
      ("path", `List (List.map coordinate_json item.path));
      ("metric", `String item.metric);
      ("criterion", `String item.completion_criterion) ]

let authority_digest () =
  `Assoc
    [ ("declarations", `List (List.map declaration_json Ops_capability.all));
      ("governance", `List (List.map obligation_json Ops_governance.obligations)) ]
  |> Yojson.Safe.to_string |> sha256

let run_command command =
  match Unix.open_process_in command with
  | exception exn -> Error (Printexc.to_string exn)
  | channel ->
      let lines = ref [] in
      let rec drain () =
        match input_line channel with
        | line -> lines := line :: !lines; drain ()
        | exception End_of_file -> ()
      in
      drain ();
      begin match Unix.close_process_in channel with
      | Unix.WEXITED 0 -> Ok (List.rev !lines)
      | Unix.WEXITED code -> Error (Printf.sprintf "process exited %d" code)
      | Unix.WSIGNALED signal -> Error (Printf.sprintf "process signalled %d" signal)
      | Unix.WSTOPPED signal -> Error (Printf.sprintf "process stopped %d" signal)
      end

let source_context ~root =
  let quoted = Filename.quote root in
  let source_revision =
    match run_command ("git -C " ^ quoted ^ " rev-parse HEAD") with
    | Ok [ value ] -> String.trim value
    | Ok _ | Error _ -> "unavailable"
  in
  let source_clean =
    match run_command ("git -C " ^ quoted ^ " status --porcelain --untracked-files=all") with
    | Ok [] -> true
    | Ok (_ :: _) | Error _ -> false
  in
  { source_revision; source_clean;
    configuration_digest = configuration_digest ();
    authority_digest = authority_digest () }

let surface_name = function
  | Ops_command.Ocaml_api -> "ocaml-api"
  | Cli -> "cli"
  | Mcp -> "mcp"
  | Zenoh -> "zenoh"

let phase_coordinate action =
  let direct level phase = (level, phase) in
  if String.equal action "inventory" then direct Ops_capability.L0 Ops_capability.Observe
  else if String.equal action "plan" then direct Ops_capability.L1 Ops_capability.Orient
  else if String.equal action "run" then direct Ops_capability.L3 Ops_capability.Act
  else if String.equal action "check" then direct Ops_capability.L0 Ops_capability.Observe
  else if String.starts_with ~prefix:"explain:" action then
    direct Ops_capability.LX Ops_capability.Orient
  else if String.starts_with ~prefix:"invoke:" action then
    let id = String.sub action 7 (String.length action - 7) in
    begin match List.find_opt (fun (item : Ops_capability.declaration) -> item.id = id) Ops_capability.all with
    | Some { path = coordinate :: _; _ } -> (coordinate.level, coordinate.phase)
    | _ -> direct Ops_capability.LX Ops_capability.Observe
    end
  else if List.mem action [ "mbse-check"; "fpp-check"; "formal-check" ] then
    direct Ops_capability.L3 Ops_capability.Observe
  else direct Ops_capability.LX Ops_capability.Observe

let event ?rca_origin ~run_id ~started_ns ~finished_ns ~source observation =
  let receipt = observation.Ops_command.receipt in
  let level, phase = phase_coordinate receipt.action in
  { run_id;
    request_id = receipt.request_id;
    recorded_at_ns = finished_ns;
    source;
    plane = receipt.scope;
    surface = surface_name observation.surface;
    fractal_coordinate =
      Ops_capability.string_of_level level ^ "/" ^ Ops_capability.string_of_phase phase;
    ooda_phase = Ops_capability.string_of_phase phase;
    rca_origin;
    mediation = "Sop_execution.execute_sop_workflow";
    resource = "local-runtime";
    duration_ns = Int64.max 0L (Int64.sub finished_ns started_ns);
    verdict =
      (match receipt.verdict with Ops_command.Succeeded -> "succeeded" | Blocked -> "blocked");
    receipt_digest = receipt.digest }

let validate item =
  let errors = ref [] in
  let require name value = if String.trim value = "" then errors := (name ^ " is empty") :: !errors in
  List.iter (fun (name, value) -> require name value)
    [ ("run_id", item.run_id); ("request_id", item.request_id);
      ("source_revision", item.source.source_revision);
      ("configuration_digest", item.source.configuration_digest);
      ("authority_digest", item.source.authority_digest);
      ("plane", item.plane); ("surface", item.surface);
      ("fractal_coordinate", item.fractal_coordinate); ("ooda_phase", item.ooda_phase);
      ("mediation", item.mediation); ("resource", item.resource);
      ("verdict", item.verdict); ("receipt_digest", item.receipt_digest) ];
  List.iter
    (fun (name, digest) ->
      if String.length digest <> 64 then errors := (name ^ " is not SHA-256") :: !errors)
    [ ("configuration_digest", item.source.configuration_digest);
      ("authority_digest", item.source.authority_digest);
      ("receipt_digest", item.receipt_digest) ];
  if item.duration_ns < 0L then errors := "duration_ns is negative" :: !errors;
  List.rev !errors

let to_json item =
  `Assoc
    [ ("run_id", `String item.run_id); ("request_id", `String item.request_id);
      ("recorded_at_ns", `Intlit (Int64.to_string item.recorded_at_ns));
      ("source_revision", `String item.source.source_revision);
      ("source_clean", `Bool item.source.source_clean);
      ("configuration_digest", `String item.source.configuration_digest);
      ("authority_digest", `String item.source.authority_digest);
      ("plane", `String item.plane); ("surface", `String item.surface);
      ("fractal_coordinate", `String item.fractal_coordinate);
      ("ooda_phase", `String item.ooda_phase);
      ("rca_origin",
       match item.rca_origin with
       | None -> `Null
       | Some origin -> `String (Ops_capability.string_of_rca_origin origin));
      ("mediation", `String item.mediation); ("resource", `String item.resource);
      ("duration_ns", `Intlit (Int64.to_string item.duration_ns));
      ("verdict", `String item.verdict);
      ("receipt_digest", `String item.receipt_digest) ]

let to_otel_json item =
  let attribute key value =
    `Assoc
      [ ("key", `String key);
        ("value", `Assoc [ ("stringValue", `String value) ]) ]
  in
  let rca =
    match item.rca_origin with
    | None -> "none"
    | Some origin -> Ops_capability.string_of_rca_origin origin
  in
  let severity_number, severity_text =
    if item.verdict = "succeeded" then (9, "INFO") else (13, "WARN")
  in
  `Assoc
    [ ("timeUnixNano", `String (Int64.to_string item.recorded_at_ns));
      ("severityNumber", `Int severity_number);
      ("severityText", `String severity_text);
      ("body", `Assoc [ ("stringValue", `String "Hermes declarative command observation") ]);
      ("attributes",
       `List
         (List.map (fun (key, value) -> attribute key value)
            [ ("run.id", item.run_id); ("request.id", item.request_id);
              ("source.revision", item.source.source_revision);
              ("source.clean", string_of_bool item.source.source_clean);
              ("configuration.digest", item.source.configuration_digest);
              ("authority.digest", item.source.authority_digest);
              ("hermes.plane", item.plane); ("hermes.surface", item.surface);
              ("hermes.fractal.coordinate", item.fractal_coordinate);
              ("hermes.ooda.phase", item.ooda_phase);
              ("hermes.rca.origin", rca); ("hermes.mediation", item.mediation);
              ("hermes.resource", item.resource);
              ("duration.ns", Int64.to_string item.duration_ns);
              ("hermes.verdict", item.verdict);
              ("receipt.digest", item.receipt_digest) ])) ]
