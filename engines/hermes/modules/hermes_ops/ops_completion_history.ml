type t = { database : Dependability_sqlite.owned_database }
type counts = { receipts : int; observations : int; interactions : int }
type interaction_kind = Prompt | Agent_message | Command | Decision | Residual
type interaction = {
  interaction_id : string; run_id : string; actor : string;
  kind : interaction_kind; body : string; recorded_at_ns : int64;
}

module Closed_operation = Dependability_sqlite.Closed_operation

let closed_error = Closed_operation.string_of_error

let close_database database =
  match Dependability_sqlite.begin_generation database with
  | Error _ -> ()
  | Ok generation ->
      begin match
        Dependability_sqlite.observe_internal_quiescence generation ~epoch:1
          ~active_handlers:0 ~queued_requests:0
      with
      | Error _ -> ()
      | Ok witness -> ignore (Dependability_sqlite.close_database ~generation ~witness)
      end

let open_store location =
  match Dependability_sqlite.open_database ~location ~maximum_total_attempts:1 with
  | Error error ->
      Error ("open completion history: " ^ Dependability_sqlite.string_of_close_error error)
  | Ok database ->
      begin match
        Closed_operation.execute database Closed_operation.Completion_initialize_v1
      with
      | Ok () -> Ok { database }
      | Error error ->
          close_database database;
          Error ("initialize completion history: " ^ closed_error error)
      end

let close store = close_database store.database

let completion_verdict = function
  | Ops_command.Succeeded -> Closed_operation.Succeeded
  | Ops_command.Blocked -> Closed_operation.Blocked

let completion_receipt event (receipt : Ops_command.receipt) =
  ({ receipt_digest = receipt.digest;
     request_id = receipt.request_id;
     action = receipt.action;
     scope = receipt.scope;
     verdict = completion_verdict receipt.verdict;
     output = receipt.output;
     source_revision = event.Ops_observability.source.source_revision;
     source_clean = event.source.source_clean;
     configuration_digest = event.source.configuration_digest;
     authority_digest = event.source.authority_digest;
     run_id = event.run_id;
     recorded_at_ns = event.recorded_at_ns }
    : Closed_operation.completion_receipt)

let completion_observation event =
  ({ receipt_digest = event.Ops_observability.receipt_digest;
     surface = event.surface;
     plane = event.plane;
     fractal_coordinate = event.fractal_coordinate;
     ooda_phase = event.ooda_phase;
     rca_origin =
       Option.map Ops_capability.string_of_rca_origin event.rca_origin;
     mediation = event.mediation;
     resource = event.resource;
     duration_ns = event.duration_ns;
     observed_at_ns = event.recorded_at_ns;
     event_json = Yojson.Safe.to_string (Ops_observability.to_otel_json event) }
    : Closed_operation.completion_observation)

let record store event (receipt : Ops_command.receipt) =
  match Ops_observability.validate event with
  | gap :: _ -> Error ("invalid observability event: " ^ gap)
  | [] when event.request_id <> receipt.request_id || event.receipt_digest <> receipt.digest ->
      Error "observability event does not identify its receipt"
  | [] ->
      begin match
        Closed_operation.execute store.database
          (Closed_operation.Completion_record
             (completion_receipt event receipt, completion_observation event))
      with
      | Ok (Closed_operation.Inserted | Closed_operation.Replayed) -> Ok ()
      | Error error -> Error (closed_error error)
      end

let interaction_kind_name = function
  | Prompt -> Closed_operation.Prompt
  | Agent_message -> Closed_operation.Agent_message
  | Command -> Closed_operation.Command
  | Decision -> Closed_operation.Decision
  | Residual -> Closed_operation.Residual

let digest text = text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let completion_interaction interaction =
  ({ interaction_id = interaction.interaction_id;
     run_id = interaction.run_id;
     actor = interaction.actor;
     kind = interaction_kind_name interaction.kind;
     body = interaction.body;
     body_digest = digest interaction.body;
     recorded_at_ns = interaction.recorded_at_ns }
    : Closed_operation.completion_interaction)

let append_interaction store interaction =
  if String.trim interaction.interaction_id = "" || String.trim interaction.run_id = ""
     || String.trim interaction.actor = "" || String.trim interaction.body = ""
  then Error "interaction identity, run, actor, and body must be nonempty"
  else
    begin match
      Closed_operation.execute store.database
        (Closed_operation.Completion_append_interaction
           (completion_interaction interaction))
    with
    | Ok (Closed_operation.Inserted | Closed_operation.Replayed) -> Ok ()
    | Error error -> Error (closed_error error)
    end

let counts store =
  match Closed_operation.execute store.database Closed_operation.Completion_counts with
  | Error error -> Error (closed_error error)
  | Ok counts ->
      Ok
        { receipts = counts.receipts;
          observations = counts.observations;
          interactions = counts.interactions }

let current_source (source : Ops_observability.source_context) =
  ({ source_revision = source.source_revision;
     source_clean = source.source_clean;
     configuration_digest = source.configuration_digest;
     authority_digest = source.authority_digest }
    : Closed_operation.current_source)

let receipt_is_current store ~source ~receipt_digest =
  match
    Closed_operation.execute store.database
      (Closed_operation.Completion_receipt_current
         (current_source source, receipt_digest))
  with
  | Ok value -> Ok value
  | Error error -> Error (closed_error error)

let has_current_success store ~source ~action ~scope =
  match
    Closed_operation.execute store.database
      (Closed_operation.Completion_has_current_success
         (current_source source, action, scope))
  with
  | Ok value -> Ok value
  | Error error -> Error (closed_error error)
