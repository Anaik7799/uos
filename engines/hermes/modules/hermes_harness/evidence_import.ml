module String_map = Map.Make (String)

type table_delta = {
  source_rows : int;
  target_rows : int;
  missing_from_target : int;
  target_only : int;
  conflicts : int;
}

type plan = {
  source_store_digest : string;
  target_store_digest : string;
  plan_digest : string;
  snapshot_digest : string option;
  source_entry_count : int option;
  source_snapshot_consistent : bool;
  schema_compatible : bool;
  scenarios : table_delta;
  traces : table_delta;
  verifications : table_delta;
  source_passed : int;
  source_failed : int;
}

let encode fields =
  fields
  |> List.map (fun value -> Printf.sprintf "%d:%s" (String.length value) value)
  |> String.concat ""

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let canonical_rows label rows =
  label :: List.map (fun (key, payload) -> encode [ key; payload ]) rows

let logical_store_digest ~schema ~snapshot_digest ~entry_count ~scenarios
    ~traces ~verifications =
  let optional = function None -> "none" | Some value -> "some:" ^ value in
  let entry_count = Option.map string_of_int entry_count in
  [ [ "schema" ]; canonical_rows "schema-rows" schema;
    [ "snapshot"; optional snapshot_digest; optional entry_count ];
    canonical_rows "scenarios" scenarios;
    canonical_rows "traces" traces;
    canonical_rows "verifications" verifications ]
  |> List.concat |> encode |> sha256

let first_encoded_field encoded =
  match String.index_opt encoded ':' with
  | None -> None
  | Some separator ->
      let length_text = String.sub encoded 0 separator in
      (match int_of_string_opt length_text with
      | Some length when separator + 1 + length <= String.length encoded ->
          Some (String.sub encoded (separator + 1) length)
      | _ -> None)

let row_values statement =
  List.init (Sqlite3.column_count statement) (fun index ->
      Sqlite3.column statement index |> Sqlite3.Data.to_string_coerce)

let query_rows db ~context ~key_columns sql =
  let statement = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement))
    (fun () ->
      let rec read rows =
        match Sqlite3.step statement with
        | Sqlite3.Rc.ROW ->
            let values = row_values statement in
            let key, payload =
              let rec split count left right =
                match (count, right) with
                | 0, _ -> (List.rev left, right)
                | _, value :: rest -> split (count - 1) (value :: left) rest
                | _, [] -> (List.rev left, [])
              in
              split key_columns [] values
            in
            read ((encode key, encode payload) :: rows)
        | Sqlite3.Rc.DONE -> Ok (List.rev rows)
        | rc ->
            Error
              (Printf.sprintf "%s: %s: %s" context
                 (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))
      in
      read [])

let map_of_rows rows =
  List.fold_left
    (fun map (key, payload) -> String_map.add key payload map)
    String_map.empty rows

let delta source target =
  let source_map = map_of_rows source and target_map = map_of_rows target in
  let missing_from_target, conflicts =
    String_map.fold
      (fun key payload (missing, conflicts) ->
        match String_map.find_opt key target_map with
        | None -> (missing + 1, conflicts)
        | Some target_payload when String.equal payload target_payload ->
            (missing, conflicts)
        | Some _ -> (missing, conflicts + 1))
      source_map (0, 0)
  in
  let target_only =
    String_map.fold
      (fun key _ count ->
        if String_map.mem key source_map then count else count + 1)
      target_map 0
  in
  { source_rows = String_map.cardinal source_map;
    target_rows = String_map.cardinal target_map;
    missing_from_target;
    target_only;
    conflicts }

let schema_sql db =
  query_rows db ~context:"read evidence import schema" ~key_columns:1
    "SELECT name, sql FROM sqlite_master WHERE type='table' AND name IN \
     ('source_snapshot','parity_scenario','parity_trace_pair','parity_verification') \
     ORDER BY name"

let snapshot db =
  match
    query_rows db ~context:"read source snapshot" ~key_columns:1
      "SELECT digest, entry_count FROM source_snapshot ORDER BY id DESC LIMIT 1"
  with
  | Error _ as error -> error
  | Ok [] -> Ok (None, None)
  | Ok [ (digest_key, entry_count_payload) ] ->
      let digest = first_encoded_field digest_key in
      let entry_count =
        match first_encoded_field entry_count_payload with
        | Some value -> int_of_string_opt value
        | None -> None
      in
      Ok (digest, entry_count)
  | Ok _ -> Error "source snapshot query returned more than one latest row"

let verification_outcomes rows =
  List.fold_left
    (fun counts (_, payload) ->
      match (counts, first_encoded_field payload) with
      | Error _ as error, _ -> error
      | Ok (passed, failed), Some "1" -> Ok (passed + 1, failed)
      | Ok (passed, failed), Some "0" -> Ok (passed, failed + 1)
      | Ok _, Some value ->
          Error ("invalid parity_verification.passed value: " ^ value)
      | Ok _, None -> Error "malformed parity_verification row")
    (Ok (0, 0)) rows

let rows_match_snapshot snapshot_digest rows =
  match snapshot_digest with
  | None -> false
  | Some expected ->
      List.for_all
        (fun (key, _) -> first_encoded_field key = Some expected)
        rows

let with_readonly path f =
  if not (Sys.file_exists path) then Error ("evidence database is absent: " ^ path)
  else
    try
      let db = Sqlite3.db_open ~mode:`READONLY path in
      Fun.protect
        ~finally:(fun () -> ignore (Sqlite3.db_close db))
        (fun () -> f db)
    with exception_ -> Error (Printexc.to_string exception_)

let analyze ~source_path ~target_path =
  with_readonly source_path (fun source ->
      with_readonly target_path (fun target ->
          match
            ( schema_sql source,
              schema_sql target,
              snapshot source,
              query_rows source ~context:"read source scenarios" ~key_columns:2
                "SELECT snapshot_digest,id,feature_id,contract_id,fixture_digest,reference_digest FROM parity_scenario ORDER BY snapshot_digest,id",
              query_rows target ~context:"read target scenarios" ~key_columns:2
                "SELECT snapshot_digest,id,feature_id,contract_id,fixture_digest,reference_digest FROM parity_scenario ORDER BY snapshot_digest,id",
              query_rows source ~context:"read source traces" ~key_columns:3
                "SELECT snapshot_digest,scenario_id,trace_id,reference_trace,candidate_trace,normalization_version FROM parity_trace_pair ORDER BY snapshot_digest,scenario_id,trace_id",
              query_rows target ~context:"read target traces" ~key_columns:3
                "SELECT snapshot_digest,scenario_id,trace_id,reference_trace,candidate_trace,normalization_version FROM parity_trace_pair ORDER BY snapshot_digest,scenario_id,trace_id",
              query_rows source ~context:"read source verifications" ~key_columns:6
                "SELECT snapshot_digest,scenario_id,trace_id,verifier,harness_revision,check_name,passed,evidence_digest FROM parity_verification ORDER BY snapshot_digest,scenario_id,trace_id,verifier,harness_revision,check_name",
              query_rows target ~context:"read target verifications" ~key_columns:6
                "SELECT snapshot_digest,scenario_id,trace_id,verifier,harness_revision,check_name,passed,evidence_digest FROM parity_verification ORDER BY snapshot_digest,scenario_id,trace_id,verifier,harness_revision,check_name" )
          with
          | ( Ok source_schema,
              Ok target_schema,
              Ok (snapshot_digest, source_entry_count),
              Ok source_scenarios,
              Ok target_scenarios,
              Ok source_traces,
              Ok target_traces,
              Ok source_verifications,
              Ok target_verifications ) ->
              (match verification_outcomes source_verifications with
              | Error _ as error -> error
              | Ok (source_passed, source_failed) ->
                  let source_store_digest =
                    logical_store_digest ~schema:source_schema ~snapshot_digest
                      ~entry_count:source_entry_count
                      ~scenarios:source_scenarios ~traces:source_traces
                      ~verifications:source_verifications
                  in
                  let target_store_digest =
                    logical_store_digest ~schema:target_schema
                      ~snapshot_digest:None ~entry_count:None
                      ~scenarios:target_scenarios ~traces:target_traces
                      ~verifications:target_verifications
                  in
                  let plan_digest =
                    sha256
                      (encode
                         [ "evidence-import-plan-v1"; source_store_digest;
                           target_store_digest ])
                  in
                  Ok
                    { source_store_digest;
                      target_store_digest;
                      plan_digest;
                      snapshot_digest;
                      source_entry_count;
                      source_snapshot_consistent =
                        rows_match_snapshot snapshot_digest source_scenarios
                        && rows_match_snapshot snapshot_digest source_traces
                        && rows_match_snapshot snapshot_digest source_verifications;
                      schema_compatible = source_schema = target_schema;
                      scenarios = delta source_scenarios target_scenarios;
                      traces = delta source_traces target_traces;
                      verifications =
                        delta source_verifications target_verifications;
                      source_passed;
                      source_failed })
          | Error diagnostic, _, _, _, _, _, _, _, _
          | _, Error diagnostic, _, _, _, _, _, _, _
          | _, _, Error diagnostic, _, _, _, _, _, _
          | _, _, _, Error diagnostic, _, _, _, _, _
          | _, _, _, _, Error diagnostic, _, _, _, _
          | _, _, _, _, _, Error diagnostic, _, _, _
          | _, _, _, _, _, _, Error diagnostic, _, _
          | _, _, _, _, _, _, _, Error diagnostic, _
          | _, _, _, _, _, _, _, _, Error diagnostic -> Error diagnostic))

let admissible plan =
  plan.schema_compatible
  && Option.is_some plan.snapshot_digest
  && plan.source_snapshot_consistent
  && plan.scenarios.conflicts = 0
  && plan.traces.conflicts = 0
  && plan.verifications.conflicts = 0

let render_delta name delta =
  Printf.sprintf
    "%s: source=%d target=%d missing=%d target_only=%d conflicts=%d"
    name delta.source_rows delta.target_rows delta.missing_from_target
    delta.target_only delta.conflicts

let render plan =
  let optional_string = function None -> "UNAVAILABLE" | Some value -> value in
  let optional_int = function None -> "UNAVAILABLE" | Some value -> string_of_int value in
  let decision =
    if admissible plan then "PLANNER_ADMISSIBLE" else "PLANNER_BLOCKED"
  in
  let next_measurement =
    if admissible plan then
      "admit this exact plan digest through Run_swarm_bridge; do not mutate either store directly"
    else
      "resolve schema, snapshot, or immutable-row conflicts and rerun the read-only planner"
  in
  String.concat "\n"
    [ "AS-IS evidence_import: read-only logical-store comparison";
      "source_store_digest: " ^ plan.source_store_digest;
      "target_store_digest: " ^ plan.target_store_digest;
      "plan_digest: " ^ plan.plan_digest;
      "snapshot_digest: " ^ optional_string plan.snapshot_digest;
      "source_entry_count: " ^ optional_int plan.source_entry_count;
      "source_snapshot_consistent: "
      ^ string_of_bool plan.source_snapshot_consistent;
      "schema_compatible: " ^ string_of_bool plan.schema_compatible;
      render_delta "scenarios" plan.scenarios;
      render_delta "traces" plan.traces;
      render_delta "verifications" plan.verifications;
      Printf.sprintf "source_historical_verdicts: %d passed, %d failed"
        plan.source_passed plan.source_failed;
      "decision: " ^ decision;
      "PREDICTIVE evidence_import: historical rows remain historical and grant no current parity credit";
      "recommended_next_measurement: " ^ next_measurement;
      "" ]
