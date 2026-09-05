type transport_state = Fresh | Stale | Unavailable
type projection = Table | Tyxml | Webgl_neutral | Otel | Fpp | Mbse
type completion = Unmapped | Blocked | Verified
type failure_effect = Blocks_credit | Denies_credit
type semantic_projection = { summary : Run_snapshot.summary; receipt_digest : string }
type table_surface = { semantic : semantic_projection; columns : string list }
type tyxml_surface = { semantic : semantic_projection; root_role : string }
type webgl_surface = { semantic : semantic_projection; scene_schema : string }
type otel_surface = { semantic : semantic_projection; scope_name : string }
type fpp_surface = { semantic : semantic_projection; channel : string }
type mbse_surface = { semantic : semantic_projection; element_kind : string }
type surface_projection = Table_surface of table_surface
  | Tyxml_surface of tyxml_surface | Webgl_surface of webgl_surface
  | Otel_surface of otel_surface | Fpp_surface of fpp_surface
  | Mbse_surface of mbse_surface
type ooda_step = { run_id : string; coordinate : Ops_capability.coordinate;
  occurred_at_ns : int64; consumes_receipt_digest : string option;
  produces_receipt_digest : string }

let split_at count values =
  let rec loop left reversed = function
    | rest when left = 0 -> Some (List.rev reversed, rest)
    | [] -> None
    | value :: rest -> loop (left - 1) (value :: reversed) rest
  in
  if count < 0 then None else loop count [] values

let apply_suffix snapshot events =
  let rec loop snapshot = function
    | [] -> Some snapshot
    | event :: rest ->
        begin match Run_snapshot.apply snapshot event with
        | Ok (Run_snapshot.Applied next) | Ok (Duplicate next) -> loop next rest
        | Ok (Gap _) | Error _ -> None
        end
  in
  loop snapshot events

let snapshot_suffix_equivalent ~split_at:index events =
  match split_at index events, Run_snapshot.fold events with
  | Some (prefix, suffix), Ok full ->
      let incrementally =
        match prefix with
        | [] -> Run_snapshot.fold suffix |> Result.to_option
        | _ ->
            begin match Run_snapshot.fold prefix with
            | Error _ -> None
            | Ok snapshot -> apply_suffix snapshot suffix
            end
      in
      begin match incrementally with
      | Some incremental -> Run_snapshot.summary incremental = Run_snapshot.summary full
      | None -> false
      end
  | _ -> false

let duplicate_identity snapshot event =
  match Run_snapshot.apply snapshot event with
  | Ok (Run_snapshot.Duplicate same) -> Run_snapshot.summary same = Run_snapshot.summary snapshot
  | _ -> false

let gap_requires_resync snapshot event =
  match Run_snapshot.apply snapshot event with Ok (Run_snapshot.Gap _) -> true | _ -> false

let transport_state ~now_ns ~max_age_ns ~future_tolerance_ns ~last_seen_ns =
  match last_seen_ns with
  | None -> Unavailable
  | Some _ when now_ns < 0L || max_age_ns < 0L || future_tolerance_ns < 0L -> Stale
  | Some last_seen when last_seen < 0L -> Stale
  | Some last_seen when last_seen > now_ns ->
      if Int64.sub last_seen now_ns <= future_tolerance_ns then Fresh else Stale
  | Some last_seen ->
      if Int64.sub now_ns last_seen <= max_age_ns then Fresh else Stale

let lifecycle_string = Run_model.string_of_lifecycle

let counts_json counts =
  `Assoc
    [ ("attempts_ready", `Int counts.Run_snapshot.attempts_ready);
      ("attempts_running", `Int counts.attempts_running);
      ("attempts_terminal", `Int counts.attempts_terminal);
      ("diagnostics", `Int counts.diagnostics);
      ("events", `Int counts.events);
      ("phases_finished", `Int counts.phases_finished);
      ("phases_started", `Int counts.phases_started);
      ("receipts", `Int counts.receipts);
      ("residuals", `Int counts.residuals);
      ("suites_discovered", `Int counts.suites_discovered);
      ("suites_failed", `Int counts.suites_failed);
      ("suites_started", `Int counts.suites_started);
      ("suites_succeeded", `Int counts.suites_succeeded) ]

let summary_json summary =
  `Assoc
    [ ("authority_digest", `String summary.Run_snapshot.authority_digest);
      ("configuration_digest", `String summary.configuration_digest);
      ("counts", counts_json summary.counts);
      ("executable_digest", `String summary.executable_digest);
      ("last_digest", match summary.last_digest with None -> `Null | Some value -> `String value);
      ("last_sequence", `Intlit (Int64.to_string summary.last_sequence));
      ("lifecycle", `String (lifecycle_string summary.lifecycle));
      ("run_id", `String summary.run_id);
      ("source_clean", `Bool summary.source_clean);
      ("source_revision", `String summary.source_revision);
      ("terminal", `Bool summary.terminal) ]

let semantic_projection summary =
  let receipt_digest =
    match Run_model.canonical_string (summary_json summary) with
    | Ok bytes -> bytes |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
    | Error error ->
        ("invalid-summary:" ^ error) |> Digestif.SHA256.digest_string
        |> Digestif.SHA256.to_hex
  in
  { summary; receipt_digest }

let table_columns =
  [ "run_id"; "lifecycle"; "last_sequence"; "last_digest"; "source_revision";
    "source_clean"; "configuration_digest"; "authority_digest";
    "executable_digest"; "terminal"; "counts" ]

let project projection summary =
  let semantic = semantic_projection summary in
  match projection with
  | Table -> Table_surface { semantic; columns = table_columns }
  | Tyxml -> Tyxml_surface { semantic; root_role = "main" }
  | Webgl_neutral -> Webgl_surface { semantic; scene_schema = "hermes.run.scene.v1" }
  | Otel -> Otel_surface { semantic; scope_name = "hermes.operations" }
  | Fpp -> Fpp_surface { semantic; channel = "ops.dashboard.run.summary" }
  | Mbse -> Mbse_surface { semantic; element_kind = "HermesOperationsRun" }

let validate_semantic semantic =
  let expected = semantic_projection semantic.summary in
  if String.equal semantic.receipt_digest expected.receipt_digest then Ok semantic
  else Error "surface semantic receipt drift"

let normalize_projection = function
  | Table_surface view when view.columns = table_columns -> validate_semantic view.semantic
  | Tyxml_surface view when String.equal view.root_role "main" -> validate_semantic view.semantic
  | Webgl_surface view when String.equal view.scene_schema "hermes.run.scene.v1" ->
      validate_semantic view.semantic
  | Otel_surface view when String.equal view.scope_name "hermes.operations" ->
      validate_semantic view.semantic
  | Fpp_surface view when String.equal view.channel "ops.dashboard.run.summary" ->
      validate_semantic view.semantic
  | Mbse_surface view when String.equal view.element_kind "HermesOperationsRun" ->
      validate_semantic view.semantic
  | _ -> Error "surface projection contract drift"

let surface_name = function
  | Table_surface _ -> "table" | Tyxml_surface _ -> "tyxml"
  | Webgl_surface _ -> "webgl" | Otel_surface _ -> "otel"
  | Fpp_surface _ -> "fpp" | Mbse_surface _ -> "mbse"

let projections_equivalent projections =
  let expected_surfaces = [ "fpp"; "mbse"; "otel"; "table"; "tyxml"; "webgl" ] in
  let surfaces = List.map surface_name projections |> List.sort_uniq String.compare in
  if surfaces <> expected_surfaces || List.length projections <> List.length expected_surfaces
  then false
  else
    match projections with
    | [] -> false
    | first :: rest ->
        begin match normalize_projection first with
        | Error _ -> false
        | Ok reference ->
            List.for_all
              (fun projection -> normalize_projection projection = Ok reference)
              rest
        end

let projection_homomorphism summary =
  let projections = [ Table; Tyxml; Webgl_neutral; Otel; Fpp; Mbse ] in
  projections_equivalent (List.map (fun projection -> project projection summary) projections)

let complete_required = function
  | [] -> Unmapped
  | requirements when List.for_all Fun.id requirements -> Verified
  | _ -> Blocked

let failure_effect = function
  | Ops_capability.Implementation -> Denies_credit
  | Specification | Environment | Evidence | Control -> Blocks_credit

let valid_receipt_digest value =
  String.length value = 64
  && String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) value

let closes_fast_ooda ~max_latency_ns steps =
  let phase step = step.coordinate.Ops_capability.phase in
  let consumes expected step =
    step.consumes_receipt_digest = Some expected.produces_receipt_digest
  in
  match steps with
  | [ observed; oriented; decided; acted; closed ] ->
      let receipts = List.map (fun step -> step.produces_receipt_digest) steps in
      max_latency_ns >= 0L
      && String.trim observed.run_id <> ""
      && List.for_all
           (fun step ->
             String.equal step.run_id observed.run_id
             && step.coordinate.level = observed.coordinate.level
             && step.occurred_at_ns >= 0L
             && valid_receipt_digest step.produces_receipt_digest)
           steps
      && List.length receipts = List.length (List.sort_uniq String.compare receipts)
      && phase observed = Ops_capability.Observe
      && phase oriented = Orient
      && phase decided = Decide
      && phase acted = Act
      && phase closed = Observe
      && observed.consumes_receipt_digest = None
      && consumes observed oriented
      && consumes oriented decided
      && consumes decided acted
      && consumes acted closed
      && observed.occurred_at_ns <= oriented.occurred_at_ns
      && oriented.occurred_at_ns <= decided.occurred_at_ns
      && decided.occurred_at_ns <= acted.occurred_at_ns
      && acted.occurred_at_ns <= closed.occurred_at_ns
      && Int64.sub closed.occurred_at_ns observed.occurred_at_ns <= max_latency_ns
  | _ -> false
