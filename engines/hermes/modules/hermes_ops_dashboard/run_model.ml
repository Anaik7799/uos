type phase = Admission | Authority_preflight | Discovery | Build | Dispatch
  | Suite_execution | Aggregation | Completion_admission | Publication

type lifecycle = Declared | Admitted | Running | Aggregating | Succeeded
  | Failed | Cancelled | Blocked | Unavailable

type subject = Run | Phase of phase | Suite of string | Attempt of string * int
  | Resource of string | Safety_gate of string | Intelligence_gate of string
  | Analysis of string | Trace_span of string | Profile of string
  | Command of string | Receipt of string | Residual of string

type availability = Measured | Unavailable_observed of string

type event_kind = Run_declared | Run_started | Run_finished | Phase_started
  | Phase_finished | Suite_discovered | Suite_started | Suite_finished
  | Swarm_step_ready | Swarm_step_running | Swarm_step_terminal
  | Resource_sampled | Diagnostic_emitted | Safety_evaluated
  | Intelligence_evaluated | Analysis_recorded | Trace_recorded
  | Profile_recorded | Fast_path_selected | Command_observed | Receipt_admitted
  | Residual_recorded | Heartbeat

type plane = Ops_capability.plane = Control_plane | Data_plane

type provenance = { source_revision : string; source_clean : bool;
  configuration_digest : string; authority_digest : string;
  executable_digest : string }

type event = { run_id : string; sequence : int64; event_id : string;
  kind : event_kind; subject : subject; plane : plane;
  coordinate : Ops_capability.coordinate; rca_origin : Ops_capability.rca_origin;
  occurred_at_ns : int64; monotonic_at_ns : int64; provenance : provenance;
  payload : Yojson.Safe.t; previous_digest : string option; digest : string }

module String_set = Set.Make (String)

let ( let* ) value f = match value with Ok result -> f result | Error _ as error -> error

let nonempty label value =
  if String.trim value = "" then Error (label ^ " must be nonempty") else Ok value

let is_hex = function
  | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
  | _ -> false

let digest_text label value =
  let* _ = nonempty label value in
  if String.length value <> 64 || not (String.for_all is_hex value) then
    Error (label ^ " must be a 64-character hexadecimal SHA-256 digest")
  else Ok value

let distinct_fields fields =
  let rec loop seen = function
    | [] -> Ok ()
    | (name, _) :: _ when String_set.mem name seen ->
        Error ("duplicate JSON field: " ^ name)
    | (name, _) :: rest -> loop (String_set.add name seen) rest
  in
  loop String_set.empty fields

let canonical_integer_literal value =
  let length = String.length value in
  let first_digit = if length > 0 && value.[0] = '-' then 1 else 0 in
  let digits = length > first_digit in
  let all_digits =
    digits
    && let rec loop index =
         index = length
         || (match value.[index] with '0' .. '9' -> loop (index + 1) | _ -> false)
       in
       loop first_digit
  in
  let no_leading_zero =
    not (length - first_digit > 1 && value.[first_digit] = '0')
  in
  if String.equal value "-0" then Error "negative zero is not a canonical JSON integer"
  else if all_digits && no_leading_zero then Ok (`Intlit value)
  else Error "non-canonical JSON integer literal"

let rec canonical_json (json : Yojson.Safe.t) =
  match json with
  | `Assoc fields ->
      let* () = distinct_fields fields in
      let rec map acc = function
        | [] -> Ok (`Assoc (List.sort (fun (a, _) (b, _) -> String.compare a b) acc))
        | (name, value) :: rest ->
            let* value = canonical_json value in
            map ((name, value) :: acc) rest
      in
      map [] fields
  | `List values ->
      let rec map acc = function
        | [] -> Ok (`List (List.rev acc))
        | value :: rest ->
            let* value = canonical_json value in
            map (value :: acc) rest
      in
      map [] values
  | `Float value ->
      begin match classify_float value with
      | FP_nan | FP_infinite -> Error "non-finite JSON number"
      | FP_normal | FP_subnormal | FP_zero -> Ok json
      end
  | `Intlit value -> canonical_integer_literal value
  | (`Null | `Bool _ | `Int _ | `String _) -> Ok json

let canonical_string json =
  let* canonical = canonical_json json in
  Ok (Yojson.Safe.to_string canonical)

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let string_of_phase = function
  | Admission -> "admission" | Authority_preflight -> "authority-preflight"
  | Discovery -> "discovery" | Build -> "build" | Dispatch -> "dispatch"
  | Suite_execution -> "suite-execution" | Aggregation -> "aggregation"
  | Completion_admission -> "completion-admission" | Publication -> "publication"

let phase_of_string = function
  | "admission" -> Ok Admission
  | "authority-preflight" -> Ok Authority_preflight
  | "discovery" -> Ok Discovery | "build" -> Ok Build | "dispatch" -> Ok Dispatch
  | "suite-execution" -> Ok Suite_execution | "aggregation" -> Ok Aggregation
  | "completion-admission" -> Ok Completion_admission
  | "publication" -> Ok Publication
  | value -> Error ("unknown run phase: " ^ value)

let string_of_lifecycle = function
  | Declared -> "declared" | Admitted -> "admitted" | Running -> "running"
  | Aggregating -> "aggregating" | Succeeded -> "succeeded" | Failed -> "failed"
  | Cancelled -> "cancelled" | Blocked -> "blocked" | Unavailable -> "unavailable"

let lifecycle_of_string = function
  | "declared" -> Ok Declared | "admitted" -> Ok Admitted | "running" -> Ok Running
  | "aggregating" -> Ok Aggregating | "succeeded" -> Ok Succeeded
  | "failed" -> Ok Failed | "cancelled" -> Ok Cancelled | "blocked" -> Ok Blocked
  | "unavailable" -> Ok Unavailable
  | value -> Error ("unknown run lifecycle: " ^ value)

let terminal_lifecycle = function
  | Succeeded | Failed | Cancelled | Blocked | Unavailable -> true
  | Declared | Admitted | Running | Aggregating -> false

let string_of_event_kind = function
  | Run_declared -> "run-declared" | Run_started -> "run-started"
  | Run_finished -> "run-finished" | Phase_started -> "phase-started"
  | Phase_finished -> "phase-finished" | Suite_discovered -> "suite-discovered"
  | Suite_started -> "suite-started" | Suite_finished -> "suite-finished"
  | Swarm_step_ready -> "swarm-step-ready" | Swarm_step_running -> "swarm-step-running"
  | Swarm_step_terminal -> "swarm-step-terminal" | Resource_sampled -> "resource-sampled"
  | Diagnostic_emitted -> "diagnostic-emitted" | Safety_evaluated -> "safety-evaluated"
  | Intelligence_evaluated -> "intelligence-evaluated"
  | Analysis_recorded -> "analysis-recorded" | Trace_recorded -> "trace-recorded"
  | Profile_recorded -> "profile-recorded" | Fast_path_selected -> "fast-path-selected"
  | Command_observed -> "command-observed" | Receipt_admitted -> "receipt-admitted"
  | Residual_recorded -> "residual-recorded" | Heartbeat -> "heartbeat"

let event_kind_of_string = function
  | "run-declared" -> Ok Run_declared | "run-started" -> Ok Run_started
  | "run-finished" -> Ok Run_finished | "phase-started" -> Ok Phase_started
  | "phase-finished" -> Ok Phase_finished | "suite-discovered" -> Ok Suite_discovered
  | "suite-started" -> Ok Suite_started | "suite-finished" -> Ok Suite_finished
  | "swarm-step-ready" -> Ok Swarm_step_ready
  | "swarm-step-running" -> Ok Swarm_step_running
  | "swarm-step-terminal" -> Ok Swarm_step_terminal
  | "resource-sampled" -> Ok Resource_sampled
  | "diagnostic-emitted" -> Ok Diagnostic_emitted
  | "safety-evaluated" -> Ok Safety_evaluated
  | "intelligence-evaluated" -> Ok Intelligence_evaluated
  | "analysis-recorded" -> Ok Analysis_recorded
  | "trace-recorded" -> Ok Trace_recorded
  | "profile-recorded" -> Ok Profile_recorded
  | "fast-path-selected" -> Ok Fast_path_selected
  | "command-observed" -> Ok Command_observed
  | "receipt-admitted" -> Ok Receipt_admitted
  | "residual-recorded" -> Ok Residual_recorded
  | "heartbeat" -> Ok Heartbeat
  | value -> Error ("unknown event kind: " ^ value)

let named_subject kind name = `Assoc [ ("kind", `String kind); ("name", `String name) ]

let subject_to_json = function
  | Run -> `Assoc [ ("kind", `String "run") ]
  | Phase phase -> `Assoc [ ("kind", `String "phase"); ("phase", `String (string_of_phase phase)) ]
  | Suite name -> named_subject "suite" name
  | Attempt (name, attempt) ->
      `Assoc [ ("attempt", `Int attempt); ("kind", `String "attempt"); ("name", `String name) ]
  | Resource name -> named_subject "resource" name
  | Safety_gate name -> named_subject "safety-gate" name
  | Intelligence_gate name -> named_subject "intelligence-gate" name
  | Analysis name -> named_subject "analysis" name
  | Trace_span name -> named_subject "trace-span" name
  | Profile name -> named_subject "profile" name
  | Command name -> named_subject "command" name
  | Receipt name -> named_subject "receipt" name
  | Residual name -> named_subject "residual" name

let plane_to_string = function Control_plane -> "control" | Data_plane -> "data"

let level_to_string = Ops_capability.string_of_level
let ooda_to_string = Ops_capability.string_of_phase
let rca_to_string = Ops_capability.string_of_rca_origin

let provenance_to_json provenance =
  `Assoc
    [ ("authority_digest", `String provenance.authority_digest);
      ("configuration_digest", `String provenance.configuration_digest);
      ("executable_digest", `String provenance.executable_digest);
      ("source_clean", `Bool provenance.source_clean);
      ("source_revision", `String provenance.source_revision) ]

let coordinate_to_json (coordinate : Ops_capability.coordinate) =
  `Assoc
    [ ("level", `String (level_to_string coordinate.level));
      ("ooda_phase", `String (ooda_to_string coordinate.phase)) ]

let json_without_digest event =
  `Assoc
    [ ("coordinate", coordinate_to_json event.coordinate);
      ("event_id", `String event.event_id);
      ("kind", `String (string_of_event_kind event.kind));
      ("monotonic_at_ns", `Intlit (Int64.to_string event.monotonic_at_ns));
      ("occurred_at_ns", `Intlit (Int64.to_string event.occurred_at_ns));
      ("payload", event.payload);
      ("plane", `String (plane_to_string event.plane));
      ("previous_digest",
       match event.previous_digest with None -> `Null | Some value -> `String value);
      ("provenance", provenance_to_json event.provenance);
      ("rca_origin", `String (rca_to_string event.rca_origin));
      ("run_id", `String event.run_id);
      ("sequence", `Intlit (Int64.to_string event.sequence));
      ("subject", subject_to_json event.subject) ]

let digest event =
  match canonical_string (json_without_digest event) with
  | Ok text -> sha256 text
  | Error error -> sha256 ("invalid-event:" ^ error)

let to_json event =
  match json_without_digest event with
  | `Assoc (("coordinate", coordinate) :: fields) ->
      `Assoc (("coordinate", coordinate) :: ("digest", `String event.digest) :: fields)
  | json -> json

let equal_provenance left right =
  String.equal left.source_revision right.source_revision
  && Bool.equal left.source_clean right.source_clean
  && String.equal left.configuration_digest right.configuration_digest
  && String.equal left.authority_digest right.authority_digest
  && String.equal left.executable_digest right.executable_digest

let validate_provenance provenance =
  let* _ = nonempty "source_revision" provenance.source_revision in
  let* _ = digest_text "configuration_digest" provenance.configuration_digest in
  let* _ = digest_text "authority_digest" provenance.authority_digest in
  let* _ = digest_text "executable_digest" provenance.executable_digest in
  Ok ()

let validate_head ~run_id ~provenance =
  let* _ = nonempty "run_id" run_id in
  validate_provenance provenance

let subject_name = function
  | Run | Phase _ -> None
  | Suite value | Resource value | Safety_gate value | Intelligence_gate value
  | Analysis value | Trace_span value | Profile value | Command value
  | Receipt value | Residual value | Attempt (value, _) -> Some value

let validate_subject subject =
  let* () =
    match subject_name subject with
    | None -> Ok ()
    | Some value -> let* _ = nonempty "subject name" value in Ok ()
  in
  match subject with
  | Attempt (_, attempt) when attempt < 0 -> Error "attempt number must be nonnegative"
  | _ -> Ok ()

let make ~run_id ~sequence ~event_id ~kind ~subject ~plane ~coordinate
    ~rca_origin ~occurred_at_ns ~monotonic_at_ns ~provenance ~payload
    ~previous_digest =
  let* () = validate_head ~run_id ~provenance in
  let* _ = nonempty "event_id" event_id in
  let* () = if Int64.compare sequence 0L < 0 then Error "sequence must be nonnegative" else Ok () in
  let* () = if Int64.compare occurred_at_ns 0L < 0 then Error "occurred_at_ns must be nonnegative" else Ok () in
  let* () = if Int64.compare monotonic_at_ns 0L < 0 then Error "monotonic_at_ns must be nonnegative" else Ok () in
  let* () = validate_subject subject in
  let* () =
    match previous_digest with None -> Ok () | Some value -> let* _ = digest_text "previous_digest" value in Ok ()
  in
  let* payload = canonical_json payload in
  let provisional = { run_id; sequence; event_id; kind; subject; plane; coordinate;
    rca_origin; occurred_at_ns; monotonic_at_ns; provenance; payload;
    previous_digest; digest = "" }
  in
  Ok { provisional with digest = digest provisional }

let strict_object label expected = function
  | `Assoc fields ->
      let names = List.map fst fields |> List.sort String.compare in
      let expected = List.sort String.compare expected in
      if names = expected then Ok fields
      else Error (Printf.sprintf "%s fields do not match the closed schema" label)
  | _ -> Error (label ^ " must be a JSON object")

let field name fields =
  match List.assoc_opt name fields with Some value -> Ok value | None -> Error ("missing field: " ^ name)

let string_field name fields =
  let* value = field name fields in
  match value with `String text -> Ok text | _ -> Error (name ^ " must be a string")

let bool_field name fields =
  let* value = field name fields in
  match value with `Bool flag -> Ok flag | _ -> Error (name ^ " must be a boolean")

let int64_json label = function
  | `Int value -> Ok (Int64.of_int value)
  | `Intlit value ->
      begin match Int64.of_string_opt value with Some parsed -> Ok parsed | None -> Error (label ^ " is outside int64") end
  | _ -> Error (label ^ " must be an integer")

let phase_from_subject fields =
  let* value = string_field "phase" fields in phase_of_string value

let named_subject_from_json constructor fields =
  let* name = string_field "name" fields in Ok (constructor name)

let subject_of_json json =
  match json with
  | `Assoc fields as object_json ->
      let* () = distinct_fields fields in
      let* kind = string_field "kind" fields in
      begin match kind with
      | "run" -> let* _ = strict_object "run subject" [ "kind" ] object_json in Ok Run
      | "phase" ->
          let* fields = strict_object "phase subject" [ "kind"; "phase" ] object_json in
          let* phase = phase_from_subject fields in Ok (Phase phase)
      | "attempt" ->
          let* fields = strict_object "attempt subject" [ "attempt"; "kind"; "name" ] object_json in
          let* name = string_field "name" fields in
          let* attempt_json = field "attempt" fields in
          let* attempt64 = int64_json "attempt" attempt_json in
          if Int64.compare attempt64 0L < 0 || Int64.compare attempt64 (Int64.of_int max_int) > 0 then
            Error "attempt is outside nonnegative int range"
          else Ok (Attempt (name, Int64.to_int attempt64))
      | value ->
          let constructor =
            match value with
            | "suite" -> Some (fun name -> Suite name)
            | "resource" -> Some (fun name -> Resource name)
            | "safety-gate" -> Some (fun name -> Safety_gate name)
            | "intelligence-gate" -> Some (fun name -> Intelligence_gate name)
            | "analysis" -> Some (fun name -> Analysis name)
            | "trace-span" -> Some (fun name -> Trace_span name)
            | "profile" -> Some (fun name -> Profile name)
            | "command" -> Some (fun name -> Command name)
            | "receipt" -> Some (fun name -> Receipt name)
            | "residual" -> Some (fun name -> Residual name)
            | _ -> None
          in
          begin match constructor with
          | None -> Error ("unknown subject kind: " ^ value)
          | Some constructor ->
              let* fields = strict_object (value ^ " subject") [ "kind"; "name" ] object_json in
              named_subject_from_json constructor fields
          end
      end
  | _ -> Error "subject must be a JSON object"

let plane_of_string = function
  | "control" -> Ok Control_plane | "data" -> Ok Data_plane
  | value -> Error ("unknown plane: " ^ value)

let level_of_string = function
  | "L0" -> Ok Ops_capability.L0 | "L1" -> Ok L1 | "L2" -> Ok L2
  | "L3" -> Ok L3 | "L4" -> Ok L4 | "L5" -> Ok L5 | "L6" -> Ok L6
  | "LX" -> Ok LX | value -> Error ("unknown fractal level: " ^ value)

let ooda_of_string = function
  | "observe" -> Ok Ops_capability.Observe | "orient" -> Ok Orient
  | "decide" -> Ok Decide | "act" -> Ok Act
  | value -> Error ("unknown OODA phase: " ^ value)

let coordinate_of_json json =
  let* fields = strict_object "coordinate" [ "level"; "ooda_phase" ] json in
  let* level_text = string_field "level" fields in
  let* phase_text = string_field "ooda_phase" fields in
  let* level = level_of_string level_text in
  let* phase = ooda_of_string phase_text in
  Ok ({ level; phase } : Ops_capability.coordinate)

let rca_of_string = function
  | "Specification" -> Ok Ops_capability.Specification
  | "Implementation" -> Ok Implementation | "Environment" -> Ok Environment
  | "Evidence" -> Ok Evidence | "Control" -> Ok Control
  | value -> Error ("unknown RCA origin: " ^ value)

let provenance_of_json json =
  let* fields = strict_object "provenance"
      [ "authority_digest"; "configuration_digest"; "executable_digest";
        "source_clean"; "source_revision" ] json in
  let* source_revision = string_field "source_revision" fields in
  let* source_clean = bool_field "source_clean" fields in
  let* configuration_digest = string_field "configuration_digest" fields in
  let* authority_digest = string_field "authority_digest" fields in
  let* executable_digest = string_field "executable_digest" fields in
  Ok { source_revision; source_clean; configuration_digest; authority_digest; executable_digest }

let of_json json =
  let* json = canonical_json json in
  let* fields = strict_object "event"
      [ "coordinate"; "digest"; "event_id"; "kind"; "monotonic_at_ns";
        "occurred_at_ns"; "payload"; "plane"; "previous_digest";
        "provenance"; "rca_origin"; "run_id"; "sequence"; "subject" ] json in
  let* run_id = string_field "run_id" fields in
  let* sequence_json = field "sequence" fields in
  let* sequence = int64_json "sequence" sequence_json in
  let* event_id = string_field "event_id" fields in
  let* kind_text = string_field "kind" fields in
  let* kind = event_kind_of_string kind_text in
  let* subject_json = field "subject" fields in
  let* subject = subject_of_json subject_json in
  let* plane_text = string_field "plane" fields in
  let* plane = plane_of_string plane_text in
  let* coordinate_json = field "coordinate" fields in
  let* coordinate = coordinate_of_json coordinate_json in
  let* rca_text = string_field "rca_origin" fields in
  let* rca_origin = rca_of_string rca_text in
  let* occurred_json = field "occurred_at_ns" fields in
  let* occurred_at_ns = int64_json "occurred_at_ns" occurred_json in
  let* monotonic_json = field "monotonic_at_ns" fields in
  let* monotonic_at_ns = int64_json "monotonic_at_ns" monotonic_json in
  let* provenance_json = field "provenance" fields in
  let* provenance = provenance_of_json provenance_json in
  let* payload = field "payload" fields in
  let* previous_json = field "previous_digest" fields in
  let* previous_digest =
    match previous_json with `Null -> Ok None | `String value -> Ok (Some value)
    | _ -> Error "previous_digest must be null or a string"
  in
  let* recorded_digest = string_field "digest" fields in
  let* event = make ~run_id ~sequence ~event_id ~kind ~subject ~plane ~coordinate
      ~rca_origin ~occurred_at_ns ~monotonic_at_ns ~provenance ~payload ~previous_digest in
  if String.equal recorded_digest event.digest then Ok event
  else Error (Printf.sprintf "event digest mismatch: recorded %s recomputed %s"
                recorded_digest event.digest)
