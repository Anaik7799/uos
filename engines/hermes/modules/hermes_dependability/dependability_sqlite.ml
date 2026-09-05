type database_state =
  | Database_open
  | Database_close_v2_deferred
  | Database_released

type storage_posture = Durable_registered | Volatile_test

type step_outcome = Row | Done

let string_of_step_outcome = function
  | Row -> "row"
  | Done -> "done"

type native_close_observation =
  | Native_close_reported_busy
  | Native_close_v2_deferred
  | Native_close_immediate

type finalize_error =
  | Finalize_rc of string
  | Finalize_exception of string
  | Finalize_already_consumed
  | Finalize_wrong_database

type finalize_interval_outcome =
  | Finalize_interval_succeeded
  | Finalize_interval_failed of finalize_error

type finalize_interval_observation = {
  database_identity : int;
  statement_identity : int;
  interval_identity : int;
  live_statements_at_enter : int;
  live_statements_at_exit : int;
  finalize_interval_outcome : finalize_interval_outcome;
}

type statement_error =
  | Prepare_failed of string
  | Body_failed of string
  | Statement_finalize_failed of finalize_error
  | Body_and_finalize_failed of string * finalize_error

type statement_use_error =
  | Statement_scope_closed
  | Statement_step_failed of string
  | Statement_step_raised of string
  | Statement_bind_failed of {
      index : int;
      binding : string;
      rc : string;
    }
  | Statement_bind_raised of {
      index : int;
      binding : string;
      detail : string;
    }
  | Statement_column_without_row of int
  | Statement_column_type_mismatch of {
      column : int;
      expected : string;
      actual : string;
    }
  | Statement_column_raised of {
      column : int;
      projection : string;
      detail : string;
    }

let step_outcome_of_rc = function
  | Sqlite3.Rc.ROW -> Ok Row
  | Sqlite3.Rc.DONE -> Ok Done
  | other -> Error (Statement_step_failed (Sqlite3.Rc.to_string other))

type transaction_status =
  | Transaction_idle
  | Transaction_active
  | Transaction_indeterminate

type database_error =
  | Database_operation_not_open of database_state
  | Invalid_schema_statement of string
  | Database_exec_failed of { operation : string; rc : string }
  | Database_exec_raised of { operation : string; detail : string }
  | Database_changes_raised of string
  | Database_transaction_active
  | Database_transaction_indeterminate

type 'body transaction_error =
  | Transaction_unavailable of database_error
  | Transaction_already_active
  | Transaction_poisoned
  | Transaction_begin_failed of database_error
  | Transaction_body_failed of 'body
  | Transaction_body_and_rollback_failed of 'body * database_error
  | Transaction_body_raised of string
  | Transaction_exception_and_rollback_failed of string * database_error
  | Transaction_commit_failed of database_error
  | Transaction_commit_and_rollback_failed of database_error * database_error

type schema_statement = Schema_statement of string

type close_behavior =
  | Native_close
  | Inject_close_failure
  | Inject_busy_once of bool Atomic.t

type closed_family_internal =
  | Authority_store_family
  | Completion_history_family
  | Completion_store_family
  | Dispatch_store_family
  | Effect_ledger_family
  | Event_store_family
  | Lifecycle_test_family

type statement_operation = {
  native_statement : Sqlite3.stmt;
  statement_owner : owned_database;
  statement_identity : int;
  mutable statement_scope_open : bool;
  mutable statement_row_available : bool;
}

and owned_database = {
  native : Sqlite3.db;
  registered_location : Dependability_sqlite_location.registration option;
  closed_family_claim : closed_family_internal option Atomic.t;
  storage_posture_value : storage_posture;
  close_behavior : close_behavior;
  cleanup_after_release : unit -> unit;
  identity : int;
  maximum_total_attempts : int;
  mutable total_attempts : int;
  mutable active_generation : int;
  mutable generation_open : bool;
  mutable state : database_state;
  mutable live_statements : int;
  mutable last_consumed_quiescence_epoch : int;
  mutable activity_revision : int;
  mutable next_statement_identity : int;
  mutable next_finalize_interval_identity : int;
  finalize_active : int Atomic.t;
  mutable finalize_intervals_rev : finalize_interval_observation list;
  mutable transaction_status : transaction_status;
}

type close_generation = {
  database : owned_database;
  id : int;
  mutable attempts : int;
}

type quiescence_witness = {
  generation : close_generation;
  epoch : int;
  live_statements : int;
  active_handlers : int;
  queued_requests : int;
  activity_revision : int;
}

type close_error =
  | Invalid_close_budget of int
  | Database_location_released
  | Database_open_failed of string
  | Database_already_released
  | Lifetime_close_budget_exhausted of { attempts : int; maximum : int }
  | Close_generation_still_active of int
  | Terminal_close_generation of int
  | Superseded_close_generation of { observed : int; active : int }
  | Invalid_quiescence_witness of string
  | Wrong_close_generation of { observed : int; expected : int }
  | Database_busy of { attempts : int; remaining : int }
  | Database_close_raised of string

let next_database_identity = Atomic.make 0

let fresh_database_identity () =
  Atomic.fetch_and_add next_database_identity 1 + 1

let physical_location_of_registration = function
  | Dependability_sqlite_location.Event_store ->
      "state/hermes/event-store.sqlite3"
  | Dependability_sqlite_location.Effect_store ->
      "state/hermes/effect-store.sqlite3"
  | Dependability_sqlite_location.Jujutsu_authority_store ->
      "state/hermes/jujutsu-authority-store.sqlite3"
  | Dependability_sqlite_location.Dispatch_store ->
      "state/hermes/dispatch-store.sqlite3"
  | Dependability_sqlite_location.Completion_store ->
      "state/hermes/completion-store.sqlite3"
  | Dependability_sqlite_location.Completion_history_store ->
      "state/hermes/completion-history.sqlite3"

let no_cleanup () = ()

let resolve_open_target location =
  match Dependability_sqlite_location.For_sqlite_owner.resolve location with
  | Error Dependability_sqlite_location.For_sqlite_owner.Released_test_fixture ->
      Error Database_location_released
  | Ok (Dependability_sqlite_location.For_sqlite_owner.Production registration) ->
      Ok
        ( physical_location_of_registration registration,
          Some registration,
          Durable_registered,
          Native_close,
          no_cleanup )
  | Ok (Dependability_sqlite_location.For_sqlite_owner.Test_fixture identity) ->
      match
        Dependability_sqlite_location.For_sqlite_owner.fixture_profile identity
      with
      | Dependability_sqlite_location.For_sqlite_owner.In_memory ->
          Ok (":memory:", None, Volatile_test, Native_close, no_cleanup)
      | Dependability_sqlite_location.For_sqlite_owner.Temporary_file ->
          Error
            (Database_open_failed
               "temporary-file location unavailable until filesystem owner is current")
      | Dependability_sqlite_location.For_sqlite_owner.Fault_open ->
          Error (Database_open_failed "injected registered-location open failure")
      | Dependability_sqlite_location.For_sqlite_owner.Fault_close ->
          Ok
            ( ":memory:", None, Volatile_test, Inject_close_failure,
              no_cleanup )
      | Dependability_sqlite_location.For_sqlite_owner.Fault_busy_once ->
          Ok
            ( ":memory:", None, Volatile_test,
              Inject_busy_once (Atomic.make false), no_cleanup )

let open_database ~location ~maximum_total_attempts =
  if maximum_total_attempts <= 0 then
    Error (Invalid_close_budget maximum_total_attempts)
  else
    match resolve_open_target location with
    | Error _ as error -> error
    | Ok
        (physical_location, registered_location, storage_posture_value,
         close_behavior,
         cleanup_after_release) ->
        match Sqlite3.db_open physical_location with
        | native ->
            Ok
              { native;
                registered_location;
                closed_family_claim = Atomic.make None;
                storage_posture_value; close_behavior; cleanup_after_release;
                maximum_total_attempts; total_attempts = 0;
                identity = fresh_database_identity ();
                active_generation = 0; generation_open = false;
                state = Database_open; live_statements = 0;
                last_consumed_quiescence_epoch = 0; activity_revision = 0;
                next_statement_identity = 0;
                next_finalize_interval_identity = 0;
                finalize_active = Atomic.make 0; finalize_intervals_rev = [];
                transaction_status = Transaction_idle }
        | exception _ ->
            cleanup_after_release ();
            Error (Database_open_failed "registered location could not be opened")

let database_state (database : owned_database) = database.state
let storage_posture (database : owned_database) = database.storage_posture_value
let database_identity (database : owned_database) = database.identity
let live_statement_count (database : owned_database) = database.live_statements
let finalize_interval_active (database : owned_database) =
  Atomic.get database.finalize_active > 0
let finalize_interval_observations (database : owned_database) =
  List.rev database.finalize_intervals_rev
let transaction_status (database : owned_database) = database.transaction_status

let string_of_finalize_error = function
  | Finalize_rc rc -> "finalize returned " ^ rc
  | Finalize_exception detail -> "finalize raised " ^ detail
  | Finalize_already_consumed -> "statement finalization already consumed"
  | Finalize_wrong_database -> "statement belongs to another database"

let string_of_statement_error = function
  | Prepare_failed detail -> "prepare failed: " ^ detail
  | Body_failed detail -> "statement body failed: " ^ detail
  | Statement_finalize_failed error -> string_of_finalize_error error
  | Body_and_finalize_failed (body, finalize) ->
      Printf.sprintf "statement body failed: %s; %s" body
        (string_of_finalize_error finalize)

let string_of_statement_use_error = function
  | Statement_scope_closed -> "statement scope is closed"
  | Statement_step_failed detail -> "statement step returned " ^ detail
  | Statement_step_raised detail -> "statement step raised: " ^ detail
  | Statement_bind_failed { index; binding; rc } ->
      Printf.sprintf "bind %s at index %d returned %s" binding index rc
  | Statement_bind_raised { index; binding; detail } ->
      Printf.sprintf "bind %s at index %d raised: %s" binding index detail
  | Statement_column_without_row column ->
      Printf.sprintf "column %d requested without a current row" column
  | Statement_column_type_mismatch { column; expected; actual } ->
      Printf.sprintf "column %d expected %s but contained %s" column expected
        actual
  | Statement_column_raised { column; projection; detail } ->
      Printf.sprintf "column %d projection %s raised: %s" column projection
        detail

let string_of_database_state = function
  | Database_open -> "open"
  | Database_close_v2_deferred -> "close_v2_deferred"
  | Database_released -> "released"

let string_of_database_error = function
  | Database_operation_not_open state ->
      "database operation unavailable while " ^ string_of_database_state state
  | Invalid_schema_statement detail -> "invalid schema statement: " ^ detail
  | Database_exec_failed { operation; rc } ->
      Printf.sprintf "%s returned %s" operation rc
  | Database_exec_raised { operation; detail } ->
      Printf.sprintf "%s raised: %s" operation detail
  | Database_changes_raised detail -> "changes raised: " ^ detail
  | Database_transaction_active -> "database transaction is already active"
  | Database_transaction_indeterminate ->
      "database transaction state is indeterminate"

let string_of_transaction_error string_of_body = function
  | Transaction_unavailable error -> string_of_database_error error
  | Transaction_already_active -> "transaction is already active"
  | Transaction_poisoned -> "transaction authority is poisoned"
  | Transaction_begin_failed error ->
      "transaction begin failed: " ^ string_of_database_error error
  | Transaction_body_failed body ->
      "transaction body failed: " ^ string_of_body body
  | Transaction_body_and_rollback_failed (body, rollback) ->
      Printf.sprintf "transaction body failed: %s; rollback failed: %s"
        (string_of_body body) (string_of_database_error rollback)
  | Transaction_body_raised detail ->
      "transaction body raised: " ^ detail
  | Transaction_exception_and_rollback_failed (detail, rollback) ->
      Printf.sprintf "transaction body raised: %s; rollback failed: %s" detail
        (string_of_database_error rollback)
  | Transaction_commit_failed error ->
      "transaction commit failed: " ^ string_of_database_error error
  | Transaction_commit_and_rollback_failed (commit, rollback) ->
      Printf.sprintf "transaction commit failed: %s; rollback failed: %s"
        (string_of_database_error commit) (string_of_database_error rollback)

let string_of_close_error = function
  | Invalid_close_budget maximum ->
      Printf.sprintf "invalid close budget %d" maximum
  | Database_location_released ->
      "database location reference is released"
  | Database_open_failed detail -> "database open failed: " ^ detail
  | Database_already_released -> "database is already released"
  | Lifetime_close_budget_exhausted { attempts; maximum } ->
      Printf.sprintf "lifetime close budget exhausted (%d/%d)" attempts maximum
  | Close_generation_still_active generation ->
      Printf.sprintf "close generation %d is still active" generation
  | Terminal_close_generation generation ->
      Printf.sprintf "close generation %d is terminal" generation
  | Superseded_close_generation { observed; active } ->
      Printf.sprintf "close generation %d was superseded by %d" observed active
  | Invalid_quiescence_witness detail ->
      "invalid quiescence witness: " ^ detail
  | Wrong_close_generation { observed; expected } ->
      Printf.sprintf "witness generation %d does not match %d" observed expected
  | Database_busy { attempts; remaining } ->
      Printf.sprintf "database busy after %d attempt; %d lifetime attempts remain"
        attempts remaining
  | Database_close_raised detail -> "database close raised: " ^ detail

let begin_generation (database : owned_database) =
  match database.state with
  | Database_close_v2_deferred | Database_released ->
      Error Database_already_released
  | Database_open when database.generation_open ->
      Error (Close_generation_still_active database.active_generation)
  | Database_open
    when database.total_attempts >= database.maximum_total_attempts ->
      Error
        (Lifetime_close_budget_exhausted
           { attempts = database.total_attempts;
             maximum = database.maximum_total_attempts })
  | Database_open ->
      database.active_generation <- database.active_generation + 1;
      database.generation_open <- true;
      Ok { database; id = database.active_generation; attempts = 0 }

let close_attempts generation = generation.attempts
let close_maximum _generation = 1

let remaining_close_attempts generation =
  if generation.attempts = 0
     && generation.database.state = Database_open
     && generation.database.generation_open
     && generation.database.total_attempts
        < generation.database.maximum_total_attempts
  then 1
  else 0

let close_generation generation = generation.id
let total_close_attempts database = database.total_attempts

let remaining_total_close_attempts database =
  max 0 (database.maximum_total_attempts - database.total_attempts)

let observe_quiescence generation ~epoch ~live_statements ~active_handlers
    ~queued_requests =
  let database = generation.database in
  if database.state <> Database_open then Error Database_already_released
  else if generation.id <> database.active_generation then
    Error
      (Superseded_close_generation
         { observed = generation.id; active = database.active_generation })
  else if not database.generation_open || generation.attempts <> 0 then
    Error (Terminal_close_generation generation.id)
  else if database.transaction_status = Transaction_active then
    Error (Invalid_quiescence_witness "transaction is active")
  else if database.transaction_status = Transaction_indeterminate then
    Error (Invalid_quiescence_witness "transaction state is indeterminate")
  else if Atomic.get database.finalize_active <> 0 then
    Error (Invalid_quiescence_witness "statement finalization is active")
  else if epoch <= database.last_consumed_quiescence_epoch then
    Error
      (Invalid_quiescence_witness
         (Printf.sprintf
            "epoch=%d is not newer than lifetime-consumed epoch=%d"
            epoch database.last_consumed_quiescence_epoch))
  else if live_statements <> database.live_statements then
    Error
      (Invalid_quiescence_witness
         (Printf.sprintf "declared live statements=%d but authority observes=%d"
            live_statements database.live_statements))
  else if live_statements <> 0 then
    Error (Invalid_quiescence_witness "live statements remain")
  else if active_handlers <> 0 then
    Error (Invalid_quiescence_witness "active handlers remain")
  else if queued_requests <> 0 then
    Error (Invalid_quiescence_witness "queued requests remain")
  else
    Ok
      { generation; epoch; live_statements; active_handlers; queued_requests;
        activity_revision = database.activity_revision }

let observe_internal_quiescence generation ~epoch ~active_handlers
    ~queued_requests =
  observe_quiescence generation ~epoch
    ~live_statements:generation.database.live_statements ~active_handlers
    ~queued_requests

let contains_substring text needle =
  let text_length = String.length text in
  let needle_length = String.length needle in
  let rec loop offset =
    if offset + needle_length > text_length then false
    else if String.sub text offset needle_length = needle then true
    else loop (offset + 1)
  in
  needle_length = 0 || loop 0

let strip_one_trailing_semicolon text =
  let trimmed = String.trim text in
  let length = String.length trimmed in
  if length > 0 && trimmed.[length - 1] = ';' then
    String.trim (String.sub trimmed 0 (length - 1))
  else trimmed

let admitted_create_prefix text =
  let uppercase = String.uppercase_ascii text in
  let prefixes =
    [ "CREATE TABLE "; "CREATE TEMP TABLE "; "CREATE TEMPORARY TABLE ";
      "CREATE INDEX "; "CREATE UNIQUE INDEX ";
      "CREATE TEMP INDEX "; "CREATE TEMPORARY INDEX " ]
  in
  List.exists
    (fun prefix ->
      let prefix_length = String.length prefix in
      String.length uppercase >= prefix_length
      && String.sub uppercase 0 prefix_length = prefix)
    prefixes

let schema_statement sql =
  let stripped = strip_one_trailing_semicolon sql in
  if stripped = "" then Error (Invalid_schema_statement "empty input")
  else if String.contains stripped '\000' then
    Error (Invalid_schema_statement "NUL byte is forbidden")
  else if
    contains_substring stripped "--"
    || contains_substring stripped "/*"
    || contains_substring stripped "*/"
  then Error (Invalid_schema_statement "comments are forbidden")
  else if String.contains stripped ';' then
    Error (Invalid_schema_statement "multiple statements are forbidden")
  else if not (admitted_create_prefix stripped) then
    Error (Invalid_schema_statement "only one CREATE TABLE/INDEX is admitted")
  else Ok (Schema_statement stripped)

let database_operation_error (database : owned_database) =
  match database.state, database.transaction_status with
  | (Database_close_v2_deferred | Database_released), _ ->
      Some (Database_operation_not_open database.state)
  | Database_open, Transaction_indeterminate ->
      Some Database_transaction_indeterminate
  | Database_open, (Transaction_idle | Transaction_active) -> None

let exec_native (database : owned_database) ~operation sql =
  match Sqlite3.exec database.native sql with
  | rc when Sqlite3.Rc.is_success rc ->
      database.activity_revision <- database.activity_revision + 1;
      Ok ()
  | rc -> Error (Database_exec_failed { operation; rc = Sqlite3.Rc.to_string rc })
  | exception exn ->
      Error
        (Database_exec_raised
           { operation; detail = Printexc.to_string exn })

let changes (database : owned_database) =
  match database_operation_error database with
  | Some error -> Error error
  | None ->
      match Sqlite3.changes database.native with
      | count -> Ok count
      | exception exn -> Error (Database_changes_raised (Printexc.to_string exn))

let finalize_native_statement statement =
  match Sqlite3.finalize statement with
  | rc ->
      (* sqlite3-ocaml releases the runtime lock around sqlite3_finalize.  Keep
         the custom block reachable until the foreign call has returned. *)
      ignore (Sys.opaque_identity statement);
      if Sqlite3.Rc.is_success rc then Ok ()
      else Error (Finalize_rc (Sqlite3.Rc.to_string rc))
  | exception exn ->
      ignore (Sys.opaque_identity statement);
      Error (Finalize_exception (Printexc.to_string exn))

let prepare_native (database : owned_database) sql =
  match database.state, database.transaction_status with
  | Database_released, _ -> Error (Prepare_failed "database is released")
  | Database_close_v2_deferred, _ ->
      Error (Prepare_failed "database close_v2 release is deferred")
  | Database_open, Transaction_indeterminate ->
      Error (Prepare_failed "database transaction state is indeterminate")
  | Database_open, (Transaction_idle | Transaction_active) ->
      match Sqlite3.prepare database.native sql with
      | statement ->
          database.next_statement_identity <-
            database.next_statement_identity + 1;
          database.live_statements <- database.live_statements + 1;
          database.activity_revision <- database.activity_revision + 1;
          Ok (statement, database.next_statement_identity)
      | exception exn -> Error (Prepare_failed (Printexc.to_string exn))

let finalize_owned_statement (database : owned_database) ~statement_identity
    native_statement =
  let live_statements_at_enter = database.live_statements in
  database.next_finalize_interval_identity <-
    database.next_finalize_interval_identity + 1;
  let interval_identity = database.next_finalize_interval_identity in
  ignore (Atomic.fetch_and_add database.finalize_active 1);
  let result = finalize_native_statement native_statement in
  database.live_statements <- max 0 (database.live_statements - 1);
  database.activity_revision <- database.activity_revision + 1;
  let live_statements_at_exit = database.live_statements in
  let finalize_interval_outcome =
    match result with
    | Ok () -> Finalize_interval_succeeded
    | Error error -> Finalize_interval_failed error
  in
  database.finalize_intervals_rev <-
    { database_identity = database.identity; statement_identity;
      interval_identity; live_statements_at_enter; live_statements_at_exit;
      finalize_interval_outcome }
    :: database.finalize_intervals_rev;
  ignore (Atomic.fetch_and_add database.finalize_active (-1));
  if
    database.state = Database_close_v2_deferred
    && database.live_statements = 0
    && (match result with Ok () -> true | Error _ -> false)
  then begin
    database.state <- Database_released;
    database.cleanup_after_release ()
  end;
  result

let step_statement statement =
  if not statement.statement_scope_open then Error Statement_scope_closed
  else
    match Sqlite3.step statement.native_statement with
    | rc ->
        let outcome = step_outcome_of_rc rc in
        statement.statement_row_available <- outcome = Ok Row;
        statement.statement_owner.activity_revision <-
          statement.statement_owner.activity_revision + 1;
        outcome
    | exception exn ->
        statement.statement_row_available <- false;
        Error (Statement_step_raised (Printexc.to_string exn))

let bind_value statement ~index ~binding bind =
  if not statement.statement_scope_open then Error Statement_scope_closed
  else
    match bind statement.native_statement index with
    | rc when Sqlite3.Rc.is_success rc ->
        statement.statement_row_available <- false;
        statement.statement_owner.activity_revision <-
          statement.statement_owner.activity_revision + 1;
        Ok ()
    | rc ->
        Error
          (Statement_bind_failed
             { index; binding; rc = Sqlite3.Rc.to_string rc })
    | exception exn ->
        Error
          (Statement_bind_raised
             { index; binding; detail = Printexc.to_string exn })

let bind_text statement ~index value =
  bind_value statement ~index ~binding:"text" (fun native index ->
      Sqlite3.bind_text native index value)

let bind_blob statement ~index value =
  bind_value statement ~index ~binding:"blob" (fun native index ->
      Sqlite3.bind_blob native index value)

let bind_int statement ~index value =
  bind_value statement ~index ~binding:"int" (fun native index ->
      Sqlite3.bind_int native index value)

let bind_int64 statement ~index value =
  bind_value statement ~index ~binding:"int64" (fun native index ->
      Sqlite3.bind_int64 native index value)

let bind_null statement ~index =
  bind_value statement ~index ~binding:"null" (fun native index ->
      Sqlite3.bind native index Sqlite3.Data.NULL)

let string_of_data = function
  | Sqlite3.Data.NONE -> "none"
  | Sqlite3.Data.NULL -> "null"
  | Sqlite3.Data.INT _ -> "integer"
  | Sqlite3.Data.FLOAT _ -> "float"
  | Sqlite3.Data.TEXT _ -> "text"
  | Sqlite3.Data.BLOB _ -> "blob"

let read_column statement ~column ~projection decode =
  if not statement.statement_scope_open then Error Statement_scope_closed
  else if not statement.statement_row_available then
    Error (Statement_column_without_row column)
  else
    match Sqlite3.column statement.native_statement column with
    | data -> decode data
    | exception exn ->
        Error
          (Statement_column_raised
             { column; projection; detail = Printexc.to_string exn })

let column_text statement ~column =
  read_column statement ~column ~projection:"text" (function
    | Sqlite3.Data.NULL -> Ok None
    | Sqlite3.Data.TEXT value -> Ok (Some value)
    | actual ->
        Error
          (Statement_column_type_mismatch
             { column; expected = "text or null"; actual = string_of_data actual }))

let column_blob statement ~column =
  read_column statement ~column ~projection:"blob" (function
    | Sqlite3.Data.NULL -> Ok None
    | Sqlite3.Data.BLOB value -> Ok (Some value)
    | actual ->
        Error
          (Statement_column_type_mismatch
             { column; expected = "blob or null"; actual = string_of_data actual }))

let column_int64 statement ~column =
  read_column statement ~column ~projection:"int64" (function
    | Sqlite3.Data.NULL -> Ok None
    | Sqlite3.Data.INT value -> Ok (Some value)
    | actual ->
        Error
          (Statement_column_type_mismatch
             { column; expected = "integer or null";
               actual = string_of_data actual }))

let column_int statement ~column =
  read_column statement ~column ~projection:"int" (function
    | Sqlite3.Data.NULL -> Ok None
    | Sqlite3.Data.INT value
      when value >= Int64.of_int min_int && value <= Int64.of_int max_int ->
        Ok (Some (Int64.to_int value))
    | Sqlite3.Data.INT value ->
        Error
          (Statement_column_raised
             { column; projection = "int";
               detail = Printf.sprintf "integer %Ld is outside OCaml int range" value })
    | actual ->
        Error
          (Statement_column_type_mismatch
             { column; expected = "integer or null";
               actual = string_of_data actual }))

let column_is_null statement ~column =
  read_column statement ~column ~projection:"null" (function
    | Sqlite3.Data.NULL -> Ok true
    | _ -> Ok false)

let with_statement database sql body =
  match prepare_native database sql with
  | Error _ as error -> error
  | Ok (native_statement, statement_identity) ->
      let statement =
        { native_statement; statement_owner = database; statement_identity;
          statement_scope_open = true; statement_row_available = false }
      in
      let body_result =
        match body statement with
        | result -> result
        | exception exn -> Error (Printexc.to_string exn)
      in
      statement.statement_scope_open <- false;
      statement.statement_row_available <- false;
      let finalize_result =
        finalize_owned_statement database ~statement_identity native_statement
      in
      begin match body_result, finalize_result with
      | Ok value, Ok () -> Ok value
      | Error message, Ok () -> Error (Body_failed message)
      | Ok _, Error finalize -> Error (Statement_finalize_failed finalize)
      | Error message, Error finalize ->
          Error (Body_and_finalize_failed (message, finalize))
      end

type transaction_fault_injection =
  | No_transaction_fault
  | Inject_transaction_begin_failure
  | Inject_transaction_commit_failure
  | Inject_transaction_rollback_failure
  | Inject_transaction_commit_and_rollback_failure

let injected_boundary_error operation =
  Database_exec_failed { operation; rc = "injected failure" }

let begin_transaction (database : owned_database) fault =
  match fault with
  | Inject_transaction_begin_failure ->
      Error (injected_boundary_error "BEGIN IMMEDIATE")
  | No_transaction_fault
  | Inject_transaction_commit_failure
  | Inject_transaction_rollback_failure
  | Inject_transaction_commit_and_rollback_failure ->
      exec_native database ~operation:"BEGIN IMMEDIATE" "BEGIN IMMEDIATE"

let rollback_transaction (database : owned_database) ~inject_failure =
  let native_result =
    exec_native database ~operation:"ROLLBACK" "ROLLBACK"
  in
  match native_result, inject_failure with
  | Ok (), false ->
      database.transaction_status <- Transaction_idle;
      Ok ()
  | Ok (), true ->
      database.transaction_status <- Transaction_indeterminate;
      Error (injected_boundary_error "ROLLBACK")
  | Error error, _ ->
      database.transaction_status <- Transaction_indeterminate;
      Error error

let with_transaction_internal fault (database : owned_database) body =
  match database.state, database.transaction_status with
  | (Database_close_v2_deferred | Database_released), _ ->
      Error
        (Transaction_unavailable
           (Database_operation_not_open database.state))
  | Database_open, Transaction_active -> Error Transaction_already_active
  | Database_open, Transaction_indeterminate -> Error Transaction_poisoned
  | Database_open, Transaction_idle ->
      begin match begin_transaction database fault with
      | Error error -> Error (Transaction_begin_failed error)
      | Ok () ->
          database.transaction_status <- Transaction_active;
          let body_result =
            match body database with
            | result -> `Returned result
            | exception exn -> `Raised (Printexc.to_string exn)
          in
          let rollback_is_injected =
            match fault with
            | Inject_transaction_rollback_failure
            | Inject_transaction_commit_and_rollback_failure -> true
            | No_transaction_fault
            | Inject_transaction_begin_failure
            | Inject_transaction_commit_failure -> false
          in
          begin match body_result with
          | `Returned (Error body_error) ->
              begin match
                rollback_transaction database
                  ~inject_failure:rollback_is_injected
              with
              | Ok () -> Error (Transaction_body_failed body_error)
              | Error rollback ->
                  Error
                    (Transaction_body_and_rollback_failed
                       (body_error, rollback))
              end
          | `Raised detail ->
              begin match
                rollback_transaction database
                  ~inject_failure:rollback_is_injected
              with
              | Ok () -> Error (Transaction_body_raised detail)
              | Error rollback ->
                  Error
                    (Transaction_exception_and_rollback_failed
                       (detail, rollback))
              end
          | `Returned (Ok value) ->
              let commit_result =
                match fault with
                | Inject_transaction_commit_failure
                | Inject_transaction_commit_and_rollback_failure ->
                    Error (injected_boundary_error "COMMIT")
                | No_transaction_fault
                | Inject_transaction_begin_failure
                | Inject_transaction_rollback_failure ->
                    exec_native database ~operation:"COMMIT" "COMMIT"
              in
              begin match commit_result with
              | Ok () ->
                  database.transaction_status <- Transaction_idle;
                  Ok value
              | Error commit ->
                  begin match
                    rollback_transaction database
                      ~inject_failure:rollback_is_injected
                  with
                  | Ok () -> Error (Transaction_commit_failed commit)
                  | Error rollback ->
                      Error
                        (Transaction_commit_and_rollback_failed
                           (commit, rollback))
                  end
              end
          end
      end

let with_transaction database body =
  with_transaction_internal No_transaction_fault database body

module Closed_operation = struct
  type family =
    | Authority_store
    | Completion_history
    | Completion_store
    | Dispatch_store
    | Effect_ledger
    | Event_store
    | Lifecycle_test
  type mode = Read_only | Read_write

  type completion_verdict = Succeeded | Blocked
  type completion_receipt = {
    receipt_digest : string;
    request_id : string;
    action : string;
    scope : string;
    verdict : completion_verdict;
    output : string;
    source_revision : string;
    source_clean : bool;
    configuration_digest : string;
    authority_digest : string;
    run_id : string;
    recorded_at_ns : int64;
  }

  type completion_observation = {
    receipt_digest : string;
    surface : string;
    plane : string;
    fractal_coordinate : string;
    ooda_phase : string;
    rca_origin : string option;
    mediation : string;
    resource : string;
    duration_ns : int64;
    observed_at_ns : int64;
    event_json : string;
  }

  type completion_interaction_kind =
    | Prompt
    | Agent_message
    | Command
    | Decision
    | Residual

  type completion_interaction = {
    interaction_id : string;
    run_id : string;
    actor : string;
    kind : completion_interaction_kind;
    body : string;
    body_digest : string;
    recorded_at_ns : int64;
  }

  type current_source = {
    source_revision : string;
    source_clean : bool;
    configuration_digest : string;
    authority_digest : string;
  }

  type completion_counts = {
    receipts : int;
    observations : int;
    interactions : int;
  }

  type effect_row = {
    schema_version : int;
    stored_key : string;
    stored_request_digest : string;
    stored_target_digest : string;
    stored_target_authority_digest : string;
    stored_effect_kind : string;
    stored_state : string;
    stored_disposition : string option;
    stored_output : string option;
    stored_output_digest : string option;
    stored_receipt_digest : string option;
    stored_diagnostic : string option;
    stored_no_replay : bool;
    stored_row_digest : string;
  }

  type effect_cas = {
    expected : effect_row;
    replacement : effect_row;
  }

  type event_row = {
    run_id : string;
    sequence : int64;
    event_id : string;
    event_digest : string;
    event_json : string;
  }

  type event_conflict = {
    conflict_run_id : string;
    conflict_sequence : int64;
    conflict_event_id : string;
  }

  type completion_store_owner = {
    completion_owner_session : string;
    completion_store_epoch : string;
    completion_authority_session : string;
    completion_authority_epoch : string;
    completion_opened_time_digest : string;
  }

  type completion_store_row = {
    completion_row_id : string;
    completion_row_state : string;
    completion_reservation_payload_digest : string;
    completion_reserve_request_digest : string;
    completion_reserve_time_digest : string;
    completion_reserve_receipt_digest : string;
    completion_finalize_request_digest : string option;
    completion_finalize_time_digest : string option;
    completion_finalize_receipt_digest : string option;
    completion_conflict_digest : string option;
  }

  type completion_store_conflict = {
    completion_conflict_id : string;
    completion_conflict_value : string;
  }

  type completion_store_finalize = {
    completion_finalize_id : string;
    completion_finalize_reservation_payload_digest : string;
    completion_finalize_request_value : string;
    completion_finalize_time_value : string;
    completion_finalize_receipt_value : string;
  }

  type completion_store_owner_cas = {
    completion_owner_from_state : string;
    completion_owner_to_state : string;
    completion_owner_cas_session : string;
    completion_owner_cas_epoch : string;
  }

  type dispatch_store_initial_owner = {
    dispatch_initial_session : string;
    dispatch_initial_recovery_attempt : int;
    dispatch_initial_store_epoch : string;
    dispatch_initial_bootstrap_digest : string;
    dispatch_initial_time_digest : string;
    dispatch_initial_transition_id : string;
  }

  type dispatch_store_pointer = {
    dispatch_pointer_key : string;
    dispatch_pointer_ordinal : int;
    dispatch_pointer_session : string;
    dispatch_pointer_attempt : int;
  }

  type dispatch_store_lookup = {
    dispatch_lookup_key : string;
    dispatch_lookup_ordinal : int;
  }

  type dispatch_store_row = {
    dispatch_row_key : string;
    dispatch_row_ordinal : int;
    dispatch_row_status : string;
    dispatch_row_transition_id : string;
    dispatch_row_request_digest : string;
    dispatch_row_time_digest : string;
    dispatch_row_owner_session : string;
    dispatch_row_recovery_attempt : int;
  }

  type dispatch_store_decision = {
    dispatch_decision_key : string;
    dispatch_decision_status : string;
    dispatch_decision_id : string;
    dispatch_decision_plan_digest : string;
    dispatch_decision_time_digest : string;
    dispatch_decision_owner_session : string;
    dispatch_decision_recovery_attempt : int;
  }

  type dispatch_store_pointer_cas = {
    dispatch_pointer_cas_key : string;
    dispatch_pointer_expected_ordinal : int;
    dispatch_pointer_replacement_ordinal : int;
    dispatch_pointer_cas_session : string;
    dispatch_pointer_cas_attempt : int;
  }

  type dispatch_store_abandonment = {
    dispatch_abandonment_commitment_id : string;
    dispatch_abandonment_evidence_digest : string;
  }

  type dispatch_store_inventory = {
    dispatch_inventory_owner_rows : string list;
    dispatch_inventory_transition_rows : string list;
    dispatch_inventory_decision_rows : string list;
    dispatch_inventory_abandonment_rows : string list;
  }

  type dispatch_store_owner_transition = {
    dispatch_owner_transition_ordinal : int;
    dispatch_owner_transition_state : string;
    dispatch_owner_transition_session : string;
    dispatch_owner_transition_attempt : int;
    dispatch_owner_transition_epoch : string;
    dispatch_owner_transition_bootstrap_digest : string;
    dispatch_owner_transition_time_digest : string;
    dispatch_owner_transition_id : string;
  }

  type authority_store_initial_owner = {
    authority_initial_session : string;
    authority_initial_epoch : string;
    authority_initial_bootstrap_digest : string;
    authority_initial_time_digest : string;
    authority_initial_transition_id : string;
  }

  type authority_store_pointer = {
    authority_pointer_generation : int;
    authority_pointer_ordinal : int;
  }

  type authority_store_lookup = {
    authority_lookup_key : string;
    authority_lookup_generation : int;
    authority_lookup_ordinal : int;
  }

  type authority_store_transition = {
    authority_transition_key : string;
    authority_transition_generation : int;
    authority_transition_ordinal : int;
    authority_transition_status : string;
    authority_transition_id : string;
    authority_transition_request_digest : string;
    authority_transition_evidence_digest : string;
    authority_transition_context_digest : string;
    authority_transition_time_digest : string;
  }

  type authority_store_campaign = {
    authority_campaign_key : string;
    authority_campaign_approval_identity : string;
    authority_campaign_plan_digest : string;
    authority_campaign_request_digest : string;
    authority_campaign_verification_digest : string;
    authority_campaign_denominator_digest : string;
    authority_campaign_occurrence_count : int;
    authority_campaign_session : string;
    authority_campaign_epoch : string;
    authority_campaign_time_digest : string;
    authority_campaign_registration_id : string;
  }

  type authority_store_nonce = {
    authority_nonce_key : string;
    authority_nonce_occurrence_ordinal : int;
    authority_nonce_occurrence_identity : string;
    authority_nonce_identity : string;
    authority_nonce_transition_ordinal : int;
    authority_nonce_state : string;
    authority_nonce_request_digest : string;
    authority_nonce_verification_digest : string;
    authority_nonce_session : string;
    authority_nonce_epoch : string;
    authority_nonce_time_digest : string;
    authority_nonce_transition_id : string;
  }

  type authority_store_nonce_lookup = {
    authority_nonce_lookup_key : string;
    authority_nonce_lookup_identity : string;
  }

  type authority_store_pointer_cas = {
    authority_pointer_cas_key : string;
    authority_pointer_cas_generation : int;
    authority_pointer_expected_ordinal : int;
    authority_pointer_replacement_ordinal : int;
  }

  type authority_store_owner_transition = {
    authority_owner_transition_generation : int;
    authority_owner_transition_ordinal : int;
    authority_owner_transition_state : string;
    authority_owner_transition_session : string;
    authority_owner_transition_epoch : string;
    authority_owner_transition_bootstrap_digest : string;
    authority_owner_transition_time_digest : string;
    authority_owner_transition_id : string;
  }

  type authority_store_owner_cas = {
    authority_owner_cas_generation : int;
    authority_owner_cas_expected_ordinal : int;
    authority_owner_cas_replacement_ordinal : int;
    authority_owner_cas_state : string;
    authority_owner_cas_session : string;
    authority_owner_cas_epoch : string;
  }

  type lifecycle_scoped_input = {
    lifecycle_literal_key : string;
    lifecycle_literal_blob : string;
    lifecycle_literal_wide : int64;
    lifecycle_literal_small : int;
  }

  type lifecycle_scoped_observation = {
    lifecycle_selected_key : string;
    lifecycle_selected_blob : string;
    lifecycle_selected_wide : int64;
    lifecycle_selected_small : int;
    lifecycle_change_count : int;
    lifecycle_column_before_row_rejected : bool;
    lifecycle_type_mismatch_rejected : bool;
    lifecycle_invalid_column_rejected : bool;
    lifecycle_escaped_bind_rejected : bool;
    lifecycle_escaped_column_rejected : bool;
  }

  type lifecycle_composition_observation = {
    lifecycle_scope_closed : bool;
    lifecycle_finalize_failure_composed : bool;
    lifecycle_body_and_finalize_failure_composed : bool;
  }

  type lifecycle_live_observation = {
    lifecycle_live_count : int;
    lifecycle_quiescence_refused : bool;
  }

  type write_outcome = Inserted | Replayed

  type error =
    | Family_mismatch of {
        operation_family : family;
        registered_location : Dependability_sqlite_location.registration option;
        claimed_family : family option;
      }
    | Transaction_scope_closed
    | Write_in_read_only_scope
    | Divergent_replay
    | Operation_failed of string

  type _ t =
    | Authority_store_initialize_v1 : unit t
    | Authority_store_insert_initial_owner : authority_store_initial_owner -> unit t
    | Authority_store_read_pointer : string -> authority_store_pointer option t
    | Authority_store_read_transition : authority_store_lookup -> authority_store_transition option t
    | Authority_store_insert_transition : authority_store_transition -> unit t
    | Authority_store_insert_pointer : string -> unit t
    | Authority_store_read_campaign : string -> authority_store_campaign option t
    | Authority_store_read_nonces : string -> authority_store_nonce list t
    | Authority_store_insert_campaign : authority_store_campaign -> unit t
    | Authority_store_insert_nonce : authority_store_nonce -> unit t
    | Authority_store_read_current_nonce : authority_store_nonce_lookup -> authority_store_nonce option t
    | Authority_store_pointer_cas : authority_store_pointer_cas -> bool t
    | Authority_store_inventory_ids : string list t
    | Authority_store_insert_owner_transition : authority_store_owner_transition -> unit t
    | Authority_store_owner_pointer_cas : authority_store_owner_cas -> bool t
    | Completion_initialize_v1 : unit t
    | Completion_record :
        completion_receipt * completion_observation -> write_outcome t
    | Completion_append_interaction :
        completion_interaction -> write_outcome t
    | Completion_counts : completion_counts t
    | Completion_receipt_current : current_source * string -> bool t
    | Completion_has_current_success :
        current_source * string * string -> bool t
    | Completion_store_initialize_v1 : unit t
    | Completion_store_insert_owner : completion_store_owner -> unit t
    | Completion_store_read : string -> completion_store_row option t
    | Completion_store_insert_reservation : completion_store_row -> unit t
    | Completion_store_mark_conflict : completion_store_conflict -> bool t
    | Completion_store_finalize : completion_store_finalize -> bool t
    | Completion_store_all_rows : completion_store_row list t
    | Completion_store_owner_cas : completion_store_owner_cas -> bool t
    | Dispatch_store_initialize_v1 : unit t
    | Dispatch_store_insert_initial_owner : dispatch_store_initial_owner -> unit t
    | Dispatch_store_read_pointer : string -> dispatch_store_pointer option t
    | Dispatch_store_read_transition :
        dispatch_store_lookup -> dispatch_store_row option t
    | Dispatch_store_read_decision : string -> dispatch_store_decision option t
    | Dispatch_store_insert_transition : dispatch_store_row -> unit t
    | Dispatch_store_insert_pointer : dispatch_store_pointer -> unit t
    | Dispatch_store_insert_decision : dispatch_store_decision -> unit t
    | Dispatch_store_pointer_cas : dispatch_store_pointer_cas -> bool t
    | Dispatch_store_read_abandonment :
        string -> dispatch_store_abandonment option t
    | Dispatch_store_inventory_ids : dispatch_store_inventory t
    | Dispatch_store_owner_transition :
        dispatch_store_owner_transition -> bool t
    | Effect_initialize_v1 : unit t
    | Effect_read : string -> effect_row option t
    | Effect_insert_pending : effect_row -> effect_row t
    | Effect_cas_pending : effect_cas -> effect_row t
    | Event_configure : unit t
    | Event_verify_configuration : unit t
    | Event_initialize_v1 : unit t
    | Event_read_stream : string -> event_row list t
    | Event_conflicts : event_conflict -> event_row list t
    | Event_insert : event_row -> unit t
    | Event_run_ids : int -> string list t
    | Event_test_initialize_unsupported_schema : unit t
    | Event_test_finalize_failure : unit t
    | Event_test_insert_malformed : string -> unit t
    | Event_test_verify_append_only : unit t
    | Lifecycle_observe_changes : int t
    | Lifecycle_setup_finalize_failure : unit t
    | Lifecycle_statement_composition : lifecycle_composition_observation t
    | Lifecycle_scoped_data_contract : lifecycle_scoped_input -> lifecycle_scoped_observation t
    | Lifecycle_schema_rejection_contract : bool t
    | Lifecycle_transaction_initialize : unit t
    | Lifecycle_transaction_insert : string -> unit t
    | Lifecycle_transaction_count : int t
    | Lifecycle_live_statement_observation : close_generation -> lifecycle_live_observation t

  type transaction_scope = {
    scope_database : owned_database;
    scope_mode : mode;
    scope_active : bool Atomic.t;
  }

  type binding =
    | Bind_text of string
    | Bind_blob of string
    | Bind_int of int
    | Bind_int64 of int64
    | Bind_null

  let string_of_family = function
    | Authority_store -> "authority-store"
    | Completion_history -> "completion-history"
    | Completion_store -> "completion-store"
    | Dispatch_store -> "dispatch-store"
    | Effect_ledger -> "effect-ledger"
    | Event_store -> "event-store"
    | Lifecycle_test -> "lifecycle-test"

  let string_of_error = function
    | Family_mismatch { operation_family; registered_location; claimed_family } ->
        let registered =
          match registered_location with
          | None -> "test-fixture"
          | Some Dependability_sqlite_location.Event_store -> "event-store"
          | Some Dependability_sqlite_location.Effect_store -> "effect-store"
          | Some Dependability_sqlite_location.Jujutsu_authority_store ->
              "jujutsu-authority-store"
          | Some Dependability_sqlite_location.Dispatch_store -> "dispatch-store"
          | Some Dependability_sqlite_location.Completion_store -> "completion-store"
          | Some Dependability_sqlite_location.Completion_history_store ->
              "completion-history-store"
        in
        let claimed =
          match claimed_family with
          | None -> "unclaimed"
          | Some family -> string_of_family family
        in
        Printf.sprintf "closed operation family %s refused by %s (%s)"
          (string_of_family operation_family) registered claimed
    | Transaction_scope_closed -> "closed transaction scope is inactive"
    | Write_in_read_only_scope -> "write refused in read-only transaction scope"
    | Divergent_replay -> "closed operation replay diverged"
    | Operation_failed detail -> "closed operation failed: " ^ detail

  let operation_family : type a. a t -> family = function
    | Authority_store_initialize_v1
    | Authority_store_insert_initial_owner _
    | Authority_store_read_pointer _
    | Authority_store_read_transition _
    | Authority_store_insert_transition _
    | Authority_store_insert_pointer _
    | Authority_store_read_campaign _
    | Authority_store_read_nonces _
    | Authority_store_insert_campaign _
    | Authority_store_insert_nonce _
    | Authority_store_read_current_nonce _
    | Authority_store_pointer_cas _
    | Authority_store_inventory_ids
    | Authority_store_insert_owner_transition _
    | Authority_store_owner_pointer_cas _ -> Authority_store
    | Completion_initialize_v1
    | Completion_record _
    | Completion_append_interaction _
    | Completion_counts
    | Completion_receipt_current _
    | Completion_has_current_success _ -> Completion_history
    | Completion_store_initialize_v1
    | Completion_store_insert_owner _
    | Completion_store_read _
    | Completion_store_insert_reservation _
    | Completion_store_mark_conflict _
    | Completion_store_finalize _
    | Completion_store_all_rows
    | Completion_store_owner_cas _ -> Completion_store
    | Dispatch_store_initialize_v1
    | Dispatch_store_insert_initial_owner _
    | Dispatch_store_read_pointer _
    | Dispatch_store_read_transition _
    | Dispatch_store_read_decision _
    | Dispatch_store_insert_transition _
    | Dispatch_store_insert_pointer _
    | Dispatch_store_insert_decision _
    | Dispatch_store_pointer_cas _
    | Dispatch_store_read_abandonment _
    | Dispatch_store_inventory_ids
    | Dispatch_store_owner_transition _ -> Dispatch_store
    | Effect_initialize_v1
    | Effect_read _
    | Effect_insert_pending _
    | Effect_cas_pending _ -> Effect_ledger
    | Event_configure
    | Event_verify_configuration
    | Event_initialize_v1
    | Event_read_stream _
    | Event_conflicts _
    | Event_insert _
    | Event_run_ids _
    | Event_test_initialize_unsupported_schema
    | Event_test_finalize_failure
    | Event_test_insert_malformed _
    | Event_test_verify_append_only -> Event_store
    | Lifecycle_observe_changes
    | Lifecycle_setup_finalize_failure
    | Lifecycle_statement_composition
    | Lifecycle_scoped_data_contract _
    | Lifecycle_schema_rejection_contract
    | Lifecycle_transaction_initialize
    | Lifecycle_transaction_insert _
    | Lifecycle_transaction_count
    | Lifecycle_live_statement_observation _ -> Lifecycle_test

  let operation_is_write : type a. a t -> bool = function
    | Authority_store_initialize_v1
    | Authority_store_insert_initial_owner _
    | Authority_store_insert_transition _
    | Authority_store_insert_pointer _
    | Authority_store_insert_campaign _
    | Authority_store_insert_nonce _
    | Authority_store_pointer_cas _
    | Authority_store_insert_owner_transition _
    | Authority_store_owner_pointer_cas _
    | Completion_initialize_v1
    | Completion_record _
    | Completion_append_interaction _
    | Completion_store_initialize_v1
    | Completion_store_insert_owner _
    | Completion_store_insert_reservation _
    | Completion_store_mark_conflict _
    | Completion_store_finalize _
    | Completion_store_owner_cas _
    | Dispatch_store_initialize_v1
    | Dispatch_store_insert_initial_owner _
    | Dispatch_store_insert_transition _
    | Dispatch_store_insert_pointer _
    | Dispatch_store_insert_decision _
    | Dispatch_store_pointer_cas _
    | Dispatch_store_owner_transition _
    | Effect_initialize_v1
    | Effect_insert_pending _
    | Effect_cas_pending _
    | Event_configure
    | Event_initialize_v1
    | Event_insert _
    | Event_test_initialize_unsupported_schema
    | Event_test_finalize_failure
    | Event_test_insert_malformed _
    | Event_test_verify_append_only -> true
    | Lifecycle_setup_finalize_failure
    | Lifecycle_statement_composition
    | Lifecycle_scoped_data_contract _
    | Lifecycle_transaction_initialize
    | Lifecycle_transaction_insert _ -> true
    | Authority_store_read_pointer _
    | Authority_store_read_transition _
    | Authority_store_read_campaign _
    | Authority_store_read_nonces _
    | Authority_store_read_current_nonce _
    | Authority_store_inventory_ids
    | Completion_counts
    | Completion_receipt_current _
    | Completion_has_current_success _
    | Completion_store_read _
    | Completion_store_all_rows
    | Dispatch_store_read_pointer _
    | Dispatch_store_read_transition _
    | Dispatch_store_read_decision _
    | Dispatch_store_read_abandonment _
    | Dispatch_store_inventory_ids
    | Effect_read _
    | Event_verify_configuration
    | Event_read_stream _
    | Event_conflicts _
    | Event_run_ids _
    | Lifecycle_observe_changes -> false
    | Lifecycle_schema_rejection_contract
    | Lifecycle_transaction_count
    | Lifecycle_live_statement_observation _ -> false

  let internal_family = function
    | Authority_store -> Authority_store_family
    | Completion_history -> Completion_history_family
    | Completion_store -> Completion_store_family
    | Dispatch_store -> Dispatch_store_family
    | Effect_ledger -> Effect_ledger_family
    | Event_store -> Event_store_family
    | Lifecycle_test -> Lifecycle_test_family

  let public_family = function
    | Authority_store_family -> Authority_store
    | Completion_history_family -> Completion_history
    | Completion_store_family -> Completion_store
    | Dispatch_store_family -> Dispatch_store
    | Effect_ledger_family -> Effect_ledger
    | Event_store_family -> Event_store
    | Lifecycle_test_family -> Lifecycle_test

  let registration_accepts registration family =
    match registration, family with
    | Dependability_sqlite_location.Jujutsu_authority_store,
      Authority_store -> true
    | Dependability_sqlite_location.Completion_history_store,
      Completion_history -> true
    | Dependability_sqlite_location.Completion_store, Completion_store -> true
    | Dependability_sqlite_location.Dispatch_store, Dispatch_store -> true
    | Dependability_sqlite_location.Effect_store, Effect_ledger -> true
    | Dependability_sqlite_location.Event_store, Event_store -> true
    | ( Dependability_sqlite_location.Event_store
      | Dependability_sqlite_location.Effect_store
      | Dependability_sqlite_location.Jujutsu_authority_store
      | Dependability_sqlite_location.Dispatch_store
      | Dependability_sqlite_location.Completion_store
      | Dependability_sqlite_location.Completion_history_store ),
      (Authority_store | Completion_history | Completion_store | Dispatch_store | Effect_ledger
      | Event_store | Lifecycle_test) -> false

  let family_mismatch database family =
    Error
      (Family_mismatch
         { operation_family = family;
           registered_location = database.registered_location;
           claimed_family =
             Option.map public_family
               (Atomic.get database.closed_family_claim) })

  let claim_family database family =
    match database.registered_location with
    | Some registration ->
        if registration_accepts registration family then Ok ()
        else family_mismatch database family
    | None ->
        let requested = internal_family family in
        let rec claim () =
          match Atomic.get database.closed_family_claim with
          | Some observed when observed = requested -> Ok ()
          | Some _ -> family_mismatch database family
          | None ->
              if Atomic.compare_and_set database.closed_family_claim None
                   (Some requested)
              then Ok ()
              else claim ()
        in
        claim ()

  let statement database sql body =
    match
      with_statement database sql (fun statement ->
        match body statement with
        | Ok value -> Ok value
        | Error error -> Error (string_of_error error))
    with
    | Ok value -> Ok value
    | Error error -> Error (Operation_failed (string_of_statement_error error))

  let bind_values statement values =
    let rec loop index = function
      | [] -> Ok ()
      | binding :: remaining ->
          let result =
            match binding with
            | Bind_text value -> bind_text statement ~index value
            | Bind_blob value -> bind_blob statement ~index value
            | Bind_int value -> bind_int statement ~index value
            | Bind_int64 value -> bind_int64 statement ~index value
            | Bind_null -> bind_null statement ~index
          in
          begin match result with
          | Ok () -> loop (index + 1) remaining
          | Error error ->
              Error (Operation_failed (string_of_statement_use_error error))
          end
    in
    loop 1 values

  let step statement =
    match step_statement statement with
    | Ok outcome -> Ok outcome
    | Error error -> Error (Operation_failed (string_of_statement_use_error error))

  let step_done statement =
    match step statement with
    | Ok Done -> Ok ()
    | Ok Row -> Error (Operation_failed "write unexpectedly returned a row")
    | Error _ as error -> error

  let text_column statement column =
    match column_text statement ~column with
    | Ok value -> Ok value
    | Error error -> Error (Operation_failed (string_of_statement_use_error error))

  let int64_column statement column =
    match column_int64 statement ~column with
    | Ok value -> Ok value
    | Error error -> Error (Operation_failed (string_of_statement_use_error error))

  let int_column statement column =
    match column_int statement ~column with
    | Ok value -> Ok value
    | Error error -> Error (Operation_failed (string_of_statement_use_error error))

  let changed database expected =
    match changes database with
    | Ok observed when observed = expected -> Ok ()
    | Ok observed ->
        Error
          (Operation_failed
             (Printf.sprintf "expected %d changed row(s), observed %d" expected
                observed))
    | Error error -> Error (Operation_failed (string_of_database_error error))

  let execute_sql database sql =
    statement database sql step_done

  let completion_schema =
    [ {|CREATE TABLE IF NOT EXISTS schema_version (
          version INTEGER PRIMARY KEY CHECK(version = 1)
        )|};
      {|CREATE TABLE IF NOT EXISTS completion_receipt (
          receipt_digest TEXT PRIMARY KEY,
          request_id TEXT NOT NULL UNIQUE,
          action TEXT NOT NULL,
          scope TEXT NOT NULL,
          verdict TEXT NOT NULL CHECK(verdict IN ('succeeded','blocked')),
          output TEXT NOT NULL,
          source_revision TEXT NOT NULL,
          source_clean INTEGER NOT NULL CHECK(source_clean IN (0,1)),
          configuration_digest TEXT NOT NULL,
          authority_digest TEXT NOT NULL,
          run_id TEXT NOT NULL,
          recorded_at_ns INTEGER NOT NULL
        )|};
      {|CREATE TABLE IF NOT EXISTS surface_observation (
          observation_id INTEGER PRIMARY KEY AUTOINCREMENT,
          receipt_digest TEXT NOT NULL,
          surface TEXT NOT NULL,
          plane TEXT NOT NULL,
          fractal_coordinate TEXT NOT NULL,
          ooda_phase TEXT NOT NULL,
          rca_origin TEXT,
          mediation TEXT NOT NULL,
          resource TEXT NOT NULL,
          duration_ns INTEGER NOT NULL CHECK(duration_ns >= 0),
          observed_at_ns INTEGER NOT NULL,
          event_json TEXT NOT NULL,
          FOREIGN KEY(receipt_digest) REFERENCES completion_receipt(receipt_digest)
        )|};
      {|CREATE TABLE IF NOT EXISTS interaction_history (
          interaction_id TEXT PRIMARY KEY,
          run_id TEXT NOT NULL,
          actor TEXT NOT NULL,
          kind TEXT NOT NULL,
          body TEXT NOT NULL,
          body_digest TEXT NOT NULL,
          recorded_at_ns INTEGER NOT NULL
        )|} ]

  let completion_triggers =
    [ {|CREATE TRIGGER IF NOT EXISTS completion_receipt_no_update
         BEFORE UPDATE ON completion_receipt BEGIN
           SELECT RAISE(ABORT, 'completion_receipt is append-only');
         END|};
      {|CREATE TRIGGER IF NOT EXISTS completion_receipt_no_delete
         BEFORE DELETE ON completion_receipt BEGIN
           SELECT RAISE(ABORT, 'completion_receipt is append-only');
         END|};
      {|CREATE TRIGGER IF NOT EXISTS surface_observation_no_update
         BEFORE UPDATE ON surface_observation BEGIN
           SELECT RAISE(ABORT, 'surface_observation is append-only');
         END|};
      {|CREATE TRIGGER IF NOT EXISTS surface_observation_no_delete
         BEFORE DELETE ON surface_observation BEGIN
           SELECT RAISE(ABORT, 'surface_observation is append-only');
         END|};
      {|CREATE TRIGGER IF NOT EXISTS interaction_history_no_update
         BEFORE UPDATE ON interaction_history BEGIN
           SELECT RAISE(ABORT, 'interaction_history is append-only');
         END|};
      {|CREATE TRIGGER IF NOT EXISTS interaction_history_no_delete
         BEFORE DELETE ON interaction_history BEGIN
           SELECT RAISE(ABORT, 'interaction_history is append-only');
         END|} ]

  let rec execute_all database = function
    | [] -> Ok ()
    | sql :: remaining ->
        begin match execute_sql database sql with
        | Ok () -> execute_all database remaining
        | Error _ as error -> error
        end

  let authority_store_schema =
    [ {|CREATE TABLE IF NOT EXISTS authority_schema (
          version INTEGER PRIMARY KEY CHECK(version = 1))|};
      {|CREATE TABLE IF NOT EXISTS owner_session_pointer (
          singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
          session_generation INTEGER NOT NULL CHECK(session_generation >= 1),
          current_ordinal INTEGER NOT NULL CHECK(current_ordinal >= 0),
          state TEXT NOT NULL CHECK(state IN ('active','draining','retired')),
          session_digest TEXT NOT NULL, store_epoch TEXT NOT NULL)|};
      {|CREATE TABLE IF NOT EXISTS owner_session_transition (
          session_generation INTEGER NOT NULL CHECK(session_generation >= 1),
          ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
          state TEXT NOT NULL CHECK(state IN ('active','draining','retired')),
          session_digest TEXT NOT NULL, store_epoch TEXT NOT NULL,
          bootstrap_digest TEXT NOT NULL, time_digest TEXT NOT NULL,
          transition_id TEXT NOT NULL UNIQUE,
          PRIMARY KEY(session_generation,ordinal))|};
      {|CREATE TABLE IF NOT EXISTS activation_pointer (
          key_digest TEXT PRIMARY KEY,
          current_generation INTEGER NOT NULL CHECK(current_generation >= 0),
          current_ordinal INTEGER NOT NULL CHECK(current_ordinal >= 0))|};
      {|CREATE TABLE IF NOT EXISTS activation_transition (
          key_digest TEXT NOT NULL,
          generation INTEGER NOT NULL CHECK(generation >= 0),
          ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
          status TEXT NOT NULL CHECK(status IN
            ('missing','root-active','classified-active')),
          activation_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
          evidence_digest TEXT NOT NULL, context_digest TEXT NOT NULL,
          time_digest TEXT NOT NULL,
          PRIMARY KEY(key_digest,generation,ordinal))|};
      {|CREATE TABLE IF NOT EXISTS approval_campaign (
          key_digest TEXT PRIMARY KEY, approval_identity TEXT NOT NULL,
          plan_digest TEXT NOT NULL, request_digest TEXT NOT NULL,
          verification_digest TEXT NOT NULL, denominator_digest TEXT NOT NULL,
          occurrence_count INTEGER NOT NULL CHECK(occurrence_count > 0),
          session_digest TEXT NOT NULL, store_epoch TEXT NOT NULL,
          time_digest TEXT NOT NULL, registration_id TEXT NOT NULL UNIQUE)|};
      {|CREATE TABLE IF NOT EXISTS approval_nonce_pointer (
          key_digest TEXT NOT NULL, nonce_identity TEXT NOT NULL,
          current_ordinal INTEGER NOT NULL CHECK(current_ordinal >= 0),
          PRIMARY KEY(key_digest,nonce_identity))|};
      {|CREATE TABLE IF NOT EXISTS approval_nonce_transition (
          key_digest TEXT NOT NULL,
          occurrence_ordinal INTEGER NOT NULL CHECK(occurrence_ordinal >= 0),
          occurrence_identity TEXT NOT NULL, nonce_identity TEXT NOT NULL,
          transition_ordinal INTEGER NOT NULL CHECK(transition_ordinal >= 0),
          state TEXT NOT NULL CHECK(state IN
            ('available','consumed','dormant-closed','abandoned-closed')),
          request_digest TEXT NOT NULL, verification_digest TEXT NOT NULL,
          session_digest TEXT NOT NULL, store_epoch TEXT NOT NULL,
          time_digest TEXT NOT NULL, transition_id TEXT NOT NULL UNIQUE,
          PRIMARY KEY(key_digest,nonce_identity,transition_ordinal))|} ]

  let initialize_authority_store database =
    match execute_all database authority_store_schema with
    | Error _ as error -> error
    | Ok () -> execute_sql database
        "INSERT OR IGNORE INTO authority_schema(version) VALUES(1)"

  let insert_authority_initial_owner database
      (owner : authority_store_initial_owner) =
    match statement database
      {|INSERT INTO owner_session_transition(
          session_generation,ordinal,state,session_digest,store_epoch,
          bootstrap_digest,time_digest,transition_id)
        VALUES(1,0,'active',?1,?2,?3,?4,?5)|}
      (fun statement ->
        match bind_values statement
          [ Bind_text owner.authority_initial_session;
            Bind_text owner.authority_initial_epoch;
            Bind_text owner.authority_initial_bootstrap_digest;
            Bind_text owner.authority_initial_time_digest;
            Bind_text owner.authority_initial_transition_id ] with
        | Error _ as error -> error | Ok () -> step_done statement) with
    | Error _ as error -> error
    | Ok () -> statement database
        {|INSERT INTO owner_session_pointer(
            singleton,session_generation,current_ordinal,state,session_digest,
            store_epoch) VALUES(1,1,0,'active',?1,?2)|}
        (fun statement ->
          match bind_values statement
            [ Bind_text owner.authority_initial_session;
              Bind_text owner.authority_initial_epoch ] with
          | Error _ as error -> error | Ok () -> step_done statement)

  let read_authority_pointer database key =
    statement database
      "SELECT current_generation,current_ordinal FROM activation_pointer WHERE key_digest=?1"
      (fun statement ->
        match bind_values statement [ Bind_text key ] with
        | Error _ as error -> error
        | Ok () -> begin match step statement with
          | Ok Done -> Ok None | Error _ as error -> error
          | Ok Row -> begin match int_column statement 0, int_column statement 1 with
            | Ok (Some authority_pointer_generation),
              Ok (Some authority_pointer_ordinal) ->
                Ok (Some { authority_pointer_generation; authority_pointer_ordinal })
            | Ok _, Ok _ -> Error (Operation_failed "authority pointer contains null")
            | Error error, _ | _, Error error -> Error error
            end
          end)

  let authority_transition_of_statement lookup statement =
    match text_column statement 0, text_column statement 1,
          text_column statement 2, text_column statement 3,
          text_column statement 4, text_column statement 5 with
    | Ok (Some authority_transition_status), Ok (Some authority_transition_id),
      Ok (Some authority_transition_request_digest),
      Ok (Some authority_transition_evidence_digest),
      Ok (Some authority_transition_context_digest),
      Ok (Some authority_transition_time_digest) ->
        Ok { authority_transition_key = lookup.authority_lookup_key;
             authority_transition_generation = lookup.authority_lookup_generation;
             authority_transition_ordinal = lookup.authority_lookup_ordinal;
             authority_transition_status; authority_transition_id;
             authority_transition_request_digest;
             authority_transition_evidence_digest;
             authority_transition_context_digest;
             authority_transition_time_digest }
    | Ok _, Ok _, Ok _, Ok _, Ok _, Ok _ ->
        Error (Operation_failed "authority transition contains null")
    | Error error, _, _, _, _, _ | _, Error error, _, _, _, _
    | _, _, Error error, _, _, _ | _, _, _, Error error, _, _
    | _, _, _, _, Error error, _ | _, _, _, _, _, Error error -> Error error

  let read_authority_transition database lookup =
    statement database
      {|SELECT status,activation_id,request_digest,evidence_digest,
               context_digest,time_digest FROM activation_transition
        WHERE key_digest=?1 AND generation=?2 AND ordinal=?3|}
      (fun statement ->
        match bind_values statement
          [ Bind_text lookup.authority_lookup_key;
            Bind_int lookup.authority_lookup_generation;
            Bind_int lookup.authority_lookup_ordinal ] with
        | Error _ as error -> error
        | Ok () -> begin match step statement with
          | Ok Done -> Ok None | Error _ as error -> error
          | Ok Row -> begin match authority_transition_of_statement lookup statement with
            | Ok row -> Ok (Some row) | Error _ as error -> error end
          end)

  let insert_authority_transition database (row : authority_store_transition) =
    statement database
      {|INSERT INTO activation_transition(
          key_digest,generation,ordinal,status,activation_id,request_digest,
          evidence_digest,context_digest,time_digest)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)|}
      (fun statement -> match bind_values statement
        [ Bind_text row.authority_transition_key;
          Bind_int row.authority_transition_generation;
          Bind_int row.authority_transition_ordinal;
          Bind_text row.authority_transition_status;
          Bind_text row.authority_transition_id;
          Bind_text row.authority_transition_request_digest;
          Bind_text row.authority_transition_evidence_digest;
          Bind_text row.authority_transition_context_digest;
          Bind_text row.authority_transition_time_digest ] with
        | Error _ as error -> error | Ok () -> step_done statement)

  let insert_authority_pointer database key =
    statement database
      "INSERT INTO activation_pointer(key_digest,current_generation,current_ordinal) VALUES(?1,0,0)"
      (fun statement -> match bind_values statement [ Bind_text key ] with
        | Error _ as error -> error | Ok () -> step_done statement)

  let read_authority_campaign database key =
    statement database
      {|SELECT approval_identity,plan_digest,request_digest,verification_digest,
               denominator_digest,occurrence_count,session_digest,store_epoch,
               time_digest,registration_id FROM approval_campaign
        WHERE key_digest=?1|}
      (fun statement -> match bind_values statement [ Bind_text key ] with
        | Error _ as error -> error
        | Ok () -> begin match step statement with
          | Ok Done -> Ok None | Error _ as error -> error
          | Ok Row -> begin match
              text_column statement 0, text_column statement 1,
              text_column statement 2, text_column statement 3,
              text_column statement 4, int_column statement 5,
              text_column statement 6, text_column statement 7,
              text_column statement 8, text_column statement 9 with
            | Ok (Some authority_campaign_approval_identity),
              Ok (Some authority_campaign_plan_digest),
              Ok (Some authority_campaign_request_digest),
              Ok (Some authority_campaign_verification_digest),
              Ok (Some authority_campaign_denominator_digest),
              Ok (Some authority_campaign_occurrence_count),
              Ok (Some authority_campaign_session), Ok (Some authority_campaign_epoch),
              Ok (Some authority_campaign_time_digest),
              Ok (Some authority_campaign_registration_id) ->
                Ok (Some { authority_campaign_key = key;
                  authority_campaign_approval_identity;
                  authority_campaign_plan_digest; authority_campaign_request_digest;
                  authority_campaign_verification_digest;
                  authority_campaign_denominator_digest;
                  authority_campaign_occurrence_count; authority_campaign_session;
                  authority_campaign_epoch; authority_campaign_time_digest;
                  authority_campaign_registration_id })
            | Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _ ->
                Error (Operation_failed "authority campaign contains null")
            | Error error, _, _, _, _, _, _, _, _, _
            | _, Error error, _, _, _, _, _, _, _, _
            | _, _, Error error, _, _, _, _, _, _, _
            | _, _, _, Error error, _, _, _, _, _, _
            | _, _, _, _, Error error, _, _, _, _, _
            | _, _, _, _, _, Error error, _, _, _, _
            | _, _, _, _, _, _, Error error, _, _, _
            | _, _, _, _, _, _, _, Error error, _, _
            | _, _, _, _, _, _, _, _, Error error, _
            | _, _, _, _, _, _, _, _, _, Error error -> Error error
            end
          end)

  let authority_nonce_of_statement ~key ~identity statement offset =
    match int_column statement offset, text_column statement (offset + 1),
          int_column statement (offset + 2), text_column statement (offset + 3),
          text_column statement (offset + 4), text_column statement (offset + 5),
          text_column statement (offset + 6), text_column statement (offset + 7),
          text_column statement (offset + 8), text_column statement (offset + 9) with
    | Ok (Some authority_nonce_occurrence_ordinal),
      Ok (Some authority_nonce_occurrence_identity),
      Ok (Some authority_nonce_transition_ordinal),
      Ok (Some authority_nonce_state), Ok (Some authority_nonce_request_digest),
      Ok (Some authority_nonce_verification_digest),
      Ok (Some authority_nonce_session), Ok (Some authority_nonce_epoch),
      Ok (Some authority_nonce_time_digest),
      Ok (Some authority_nonce_transition_id) ->
        Ok { authority_nonce_key = key; authority_nonce_identity = identity;
             authority_nonce_occurrence_ordinal;
             authority_nonce_occurrence_identity;
             authority_nonce_transition_ordinal; authority_nonce_state;
             authority_nonce_request_digest; authority_nonce_verification_digest;
             authority_nonce_session; authority_nonce_epoch;
             authority_nonce_time_digest; authority_nonce_transition_id }
    | Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _ ->
        Error (Operation_failed "authority nonce contains null")
    | Error error, _, _, _, _, _, _, _, _, _
    | _, Error error, _, _, _, _, _, _, _, _
    | _, _, Error error, _, _, _, _, _, _, _
    | _, _, _, Error error, _, _, _, _, _, _
    | _, _, _, _, Error error, _, _, _, _, _
    | _, _, _, _, _, Error error, _, _, _, _
    | _, _, _, _, _, _, Error error, _, _, _
    | _, _, _, _, _, _, _, Error error, _, _
    | _, _, _, _, _, _, _, _, Error error, _
    | _, _, _, _, _, _, _, _, _, Error error -> Error error

  let read_authority_nonces database key =
    statement database
      {|SELECT nonce_identity,occurrence_ordinal,occurrence_identity,
               transition_ordinal,state,request_digest,verification_digest,
               session_digest,store_epoch,time_digest,transition_id
        FROM approval_nonce_transition WHERE key_digest=?1
        ORDER BY occurrence_ordinal,transition_ordinal|}
      (fun statement -> match bind_values statement [ Bind_text key ] with
        | Error _ as error -> error
        | Ok () ->
          let rec loop rows = match step statement with
            | Ok Done -> Ok (List.rev rows) | Error _ as error -> error
            | Ok Row -> begin match text_column statement 0 with
              | Ok (Some identity) -> begin match
                  authority_nonce_of_statement ~key ~identity statement 1 with
                | Ok row -> loop (row :: rows) | Error _ as error -> error end
              | Ok None -> Error (Operation_failed "authority nonce identity is null")
              | Error _ as error -> error end
          in loop [])

  let insert_authority_campaign database (row : authority_store_campaign) =
    statement database
      {|INSERT INTO approval_campaign(
          key_digest,approval_identity,plan_digest,request_digest,
          verification_digest,denominator_digest,occurrence_count,
          session_digest,store_epoch,time_digest,registration_id)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)|}
      (fun statement -> match bind_values statement
        [ Bind_text row.authority_campaign_key;
          Bind_text row.authority_campaign_approval_identity;
          Bind_text row.authority_campaign_plan_digest;
          Bind_text row.authority_campaign_request_digest;
          Bind_text row.authority_campaign_verification_digest;
          Bind_text row.authority_campaign_denominator_digest;
          Bind_int row.authority_campaign_occurrence_count;
          Bind_text row.authority_campaign_session;
          Bind_text row.authority_campaign_epoch;
          Bind_text row.authority_campaign_time_digest;
          Bind_text row.authority_campaign_registration_id ] with
        | Error _ as error -> error | Ok () -> step_done statement)

  let insert_authority_nonce database (row : authority_store_nonce) =
    match statement database
      {|INSERT INTO approval_nonce_transition(
          key_digest,occurrence_ordinal,occurrence_identity,nonce_identity,
          transition_ordinal,state,request_digest,verification_digest,
          session_digest,store_epoch,time_digest,transition_id)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)|}
      (fun statement -> match bind_values statement
        [ Bind_text row.authority_nonce_key;
          Bind_int row.authority_nonce_occurrence_ordinal;
          Bind_text row.authority_nonce_occurrence_identity;
          Bind_text row.authority_nonce_identity;
          Bind_int row.authority_nonce_transition_ordinal;
          Bind_text row.authority_nonce_state;
          Bind_text row.authority_nonce_request_digest;
          Bind_text row.authority_nonce_verification_digest;
          Bind_text row.authority_nonce_session;
          Bind_text row.authority_nonce_epoch;
          Bind_text row.authority_nonce_time_digest;
          Bind_text row.authority_nonce_transition_id ] with
        | Error _ as error -> error | Ok () -> step_done statement) with
    | Error _ as error -> error
    | Ok () -> statement database
      {|INSERT INTO approval_nonce_pointer(key_digest,nonce_identity,current_ordinal)
        VALUES(?1,?2,?3)|}
      (fun statement -> match bind_values statement
        [ Bind_text row.authority_nonce_key; Bind_text row.authority_nonce_identity;
          Bind_int row.authority_nonce_transition_ordinal ] with
        | Error _ as error -> error | Ok () -> step_done statement)

  let read_authority_current_nonce database lookup =
    statement database
      {|SELECT t.occurrence_ordinal,t.occurrence_identity,t.transition_ordinal,
               t.state,t.request_digest,t.verification_digest,t.session_digest,
               t.store_epoch,t.time_digest,t.transition_id
        FROM approval_nonce_pointer p JOIN approval_nonce_transition t
          ON t.key_digest=p.key_digest AND t.nonce_identity=p.nonce_identity
         AND t.transition_ordinal=p.current_ordinal
        WHERE p.key_digest=?1 AND p.nonce_identity=?2|}
      (fun statement -> match bind_values statement
        [ Bind_text lookup.authority_nonce_lookup_key;
          Bind_text lookup.authority_nonce_lookup_identity ] with
        | Error _ as error -> error
        | Ok () -> begin match step statement with
          | Ok Done -> Ok None | Error _ as error -> error
          | Ok Row -> begin match authority_nonce_of_statement
              ~key:lookup.authority_nonce_lookup_key
              ~identity:lookup.authority_nonce_lookup_identity statement 0 with
            | Ok row -> Ok (Some row) | Error _ as error -> error end
          end)

  let cas_authority_pointer database (cas : authority_store_pointer_cas) =
    match statement database
      {|UPDATE activation_pointer SET current_ordinal=?1
        WHERE key_digest=?2 AND current_generation=?3 AND current_ordinal=?4|}
      (fun statement -> match bind_values statement
        [ Bind_int cas.authority_pointer_replacement_ordinal;
          Bind_text cas.authority_pointer_cas_key;
          Bind_int cas.authority_pointer_cas_generation;
          Bind_int cas.authority_pointer_expected_ordinal ] with
        | Error _ as error -> error | Ok () -> step_done statement) with
    | Error _ as error -> error
    | Ok () -> begin match changes database with
      | Ok count -> Ok (count = 1)
      | Error error -> Error (Operation_failed (string_of_database_error error)) end

  let authority_inventory_ids database =
    statement database
      "SELECT activation_id FROM activation_transition ORDER BY key_digest,generation,ordinal"
      (fun statement ->
        let rec loop rows = match step statement with
          | Ok Done -> Ok (List.rev rows) | Error _ as error -> error
          | Ok Row -> begin match text_column statement 0 with
            | Ok (Some id) -> loop (id :: rows)
            | Ok None -> Error (Operation_failed "authority activation id is null")
            | Error _ as error -> error end
        in loop [])

  let insert_authority_owner_transition database
      (row : authority_store_owner_transition) =
    statement database
      {|INSERT INTO owner_session_transition(
          session_generation,ordinal,state,session_digest,store_epoch,
          bootstrap_digest,time_digest,transition_id)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8)|}
      (fun statement -> match bind_values statement
        [ Bind_int row.authority_owner_transition_generation;
          Bind_int row.authority_owner_transition_ordinal;
          Bind_text row.authority_owner_transition_state;
          Bind_text row.authority_owner_transition_session;
          Bind_text row.authority_owner_transition_epoch;
          Bind_text row.authority_owner_transition_bootstrap_digest;
          Bind_text row.authority_owner_transition_time_digest;
          Bind_text row.authority_owner_transition_id ] with
        | Error _ as error -> error | Ok () -> step_done statement)

  let cas_authority_owner_pointer database (cas : authority_store_owner_cas) =
    match statement database
      {|UPDATE owner_session_pointer SET current_ordinal=?1,state=?2
        WHERE singleton=1 AND session_generation=?3 AND current_ordinal=?4
          AND session_digest=?5 AND store_epoch=?6|}
      (fun statement -> match bind_values statement
        [ Bind_int cas.authority_owner_cas_replacement_ordinal;
          Bind_text cas.authority_owner_cas_state;
          Bind_int cas.authority_owner_cas_generation;
          Bind_int cas.authority_owner_cas_expected_ordinal;
          Bind_text cas.authority_owner_cas_session;
          Bind_text cas.authority_owner_cas_epoch ] with
        | Error _ as error -> error | Ok () -> step_done statement) with
    | Error _ as error -> error
    | Ok () -> begin match changes database with
      | Ok count -> Ok (count = 1)
      | Error error -> Error (Operation_failed (string_of_database_error error)) end

  let initialize_completion database =
    match execute_all database completion_schema with
    | Error _ as error -> error
    | Ok () ->
        begin match
          execute_sql database
            "INSERT OR IGNORE INTO schema_version(version) VALUES(1)"
        with
        | Error _ as error -> error
        | Ok () -> execute_all database completion_triggers
        end

  let existing_receipt database request_id =
    statement database
      "SELECT receipt_digest FROM completion_receipt WHERE request_id=?1"
      (fun statement ->
        match bind_values statement [ Bind_text request_id ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Ok Row ->
                begin match text_column statement 0 with
                | Ok (Some digest) ->
                    begin match step statement with
                    | Ok Done -> Ok (Some digest)
                    | Ok Row -> Error (Operation_failed "receipt request is not unique")
                    | Error _ as error -> error
                    end
                | Ok None -> Error (Operation_failed "receipt digest is null")
                | Error _ as error -> error
                end
            | Error _ as error -> error
            end)

  let verdict_name = function Succeeded -> "succeeded" | Blocked -> "blocked"

  let insert_receipt database (receipt : completion_receipt) =
    statement database
      {|INSERT INTO completion_receipt(
          receipt_digest,request_id,action,scope,verdict,output,
          source_revision,source_clean,configuration_digest,authority_digest,
          run_id,recorded_at_ns)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)|}
      (fun statement ->
        match
          bind_values statement
            [ Bind_text receipt.receipt_digest; Bind_text receipt.request_id;
              Bind_text receipt.action; Bind_text receipt.scope;
              Bind_text (verdict_name receipt.verdict); Bind_text receipt.output;
              Bind_text receipt.source_revision;
              Bind_int64 (if receipt.source_clean then 1L else 0L);
              Bind_text receipt.configuration_digest;
              Bind_text receipt.authority_digest; Bind_text receipt.run_id;
              Bind_int64 receipt.recorded_at_ns ]
        with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let insert_observation database (observation : completion_observation) =
    statement database
      {|INSERT INTO surface_observation(
          receipt_digest,surface,plane,fractal_coordinate,ooda_phase,
          rca_origin,mediation,resource,duration_ns,observed_at_ns,event_json)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)|}
      (fun statement ->
        match
          bind_values statement
            [ Bind_text observation.receipt_digest; Bind_text observation.surface;
              Bind_text observation.plane;
              Bind_text observation.fractal_coordinate;
              Bind_text observation.ooda_phase;
              (match observation.rca_origin with
               | None -> Bind_null | Some value -> Bind_text value);
              Bind_text observation.mediation; Bind_text observation.resource;
              Bind_int64 observation.duration_ns;
              Bind_int64 observation.observed_at_ns;
              Bind_text observation.event_json ]
        with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let record_completion database (receipt : completion_receipt)
      (observation : completion_observation) =
    match existing_receipt database receipt.request_id with
    | Error _ as error -> error
    | Ok (Some digest) when digest <> receipt.receipt_digest ->
        Error Divergent_replay
    | Ok existing ->
        if observation.receipt_digest <> receipt.receipt_digest then
          Error (Operation_failed "observation receipt identity mismatch")
        else
          let outcome =
            match existing with None -> Inserted | Some _ -> Replayed
          in
          let receipt_result =
            match outcome with
            | Replayed -> Ok ()
            | Inserted ->
                begin match insert_receipt database receipt with
                | Error _ as error -> error
                | Ok () ->
                    begin match changed database 1 with
                    | Error _ as error -> error
                    | Ok () ->
                        begin match existing_receipt database receipt.request_id with
                        | Ok (Some digest) when digest = receipt.receipt_digest -> Ok ()
                        | Ok _ -> Error (Operation_failed "receipt insert readback mismatch")
                        | Error _ as error -> error
                        end
                    end
                end
          in
          begin match receipt_result with
          | Error _ as error -> error
          | Ok () ->
              begin match insert_observation database observation with
              | Error _ as error -> error
              | Ok () ->
                  begin match changed database 1 with
                  | Ok () -> Ok outcome
                  | Error _ as error -> error
                  end
              end
          end

  let interaction_kind_name = function
    | Prompt -> "prompt"
    | Agent_message -> "agent-message"
    | Command -> "command"
    | Decision -> "decision"
    | Residual -> "residual"

  let existing_interaction database interaction_id =
    statement database
      {|SELECT run_id,actor,kind,body_digest,recorded_at_ns
          FROM interaction_history WHERE interaction_id=?1|}
      (fun statement ->
        match bind_values statement [ Bind_text interaction_id ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Ok Row ->
                begin match text_column statement 0, text_column statement 1,
                            text_column statement 2, text_column statement 3,
                            int64_column statement 4 with
                | Ok (Some run_id), Ok (Some actor), Ok (Some kind),
                  Ok (Some body_digest), Ok (Some recorded_at_ns) ->
                    Ok (Some (run_id, actor, kind, body_digest, recorded_at_ns))
                | Ok _, Ok _, Ok _, Ok _, Ok _ ->
                    Error (Operation_failed "interaction row contains null")
                | Error error, _, _, _, _ | _, Error error, _, _, _
                | _, _, Error error, _, _ | _, _, _, Error error, _
                | _, _, _, _, Error error -> Error error
                end
            | Error _ as error -> error
            end)

  let insert_interaction database (interaction : completion_interaction) =
    statement database
      {|INSERT INTO interaction_history(
          interaction_id,run_id,actor,kind,body,body_digest,recorded_at_ns)
        VALUES(?1,?2,?3,?4,?5,?6,?7)|}
      (fun statement ->
        match
          bind_values statement
            [ Bind_text interaction.interaction_id; Bind_text interaction.run_id;
              Bind_text interaction.actor;
              Bind_text (interaction_kind_name interaction.kind);
              Bind_text interaction.body; Bind_text interaction.body_digest;
              Bind_int64 interaction.recorded_at_ns ]
        with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let append_interaction database (interaction : completion_interaction) =
    match existing_interaction database interaction.interaction_id with
    | Error _ as error -> error
    | Ok (Some (run_id, actor, kind, body_digest, recorded_at_ns)) ->
        if
          run_id = interaction.run_id && actor = interaction.actor
          && kind = interaction_kind_name interaction.kind
          && body_digest = interaction.body_digest
          && recorded_at_ns = interaction.recorded_at_ns
        then Ok Replayed
        else Error Divergent_replay
    | Ok None ->
        begin match insert_interaction database interaction with
        | Error _ as error -> error
        | Ok () ->
            begin match changed database 1 with
            | Error _ as error -> error
            | Ok () ->
                begin match existing_interaction database interaction.interaction_id with
                | Ok (Some _) -> Ok Inserted
                | Ok None -> Error (Operation_failed "interaction insert has no readback")
                | Error _ as error -> error
                end
            end
        end

  let scalar_count database sql =
    statement database sql (fun statement ->
      match step statement with
      | Ok Row ->
          begin match int_column statement 0 with
          | Ok (Some count) -> Ok count
          | Ok None -> Error (Operation_failed "count is null")
          | Error _ as error -> error
          end
      | Ok Done -> Error (Operation_failed "count returned no row")
      | Error _ as error -> error)

  let completion_counts database =
    match scalar_count database "SELECT COUNT(*) FROM completion_receipt" with
    | Error _ as error -> error
    | Ok receipts ->
        begin match scalar_count database "SELECT COUNT(*) FROM surface_observation" with
        | Error _ as error -> error
        | Ok observations ->
            begin match scalar_count database "SELECT COUNT(*) FROM interaction_history" with
            | Error _ as error -> error
            | Ok interactions -> Ok { receipts; observations; interactions }
            end
        end

  let count_predicate database sql values =
    statement database sql (fun statement ->
      match bind_values statement values with
      | Error _ as error -> error
      | Ok () ->
          begin match step statement with
          | Ok Row ->
              begin match int_column statement 0 with
              | Ok (Some count) -> Ok count
              | Ok None -> Error (Operation_failed "predicate count is null")
              | Error _ as error -> error
              end
          | Ok Done -> Error (Operation_failed "predicate count returned no row")
          | Error _ as error -> error
          end)

  let receipt_current database (source : current_source) receipt_digest =
    if not source.source_clean then Ok false
    else
      match
        count_predicate database
          {|SELECT COUNT(*) FROM completion_receipt
              WHERE receipt_digest=?1 AND source_revision=?2 AND source_clean=1
                AND configuration_digest=?3 AND authority_digest=?4|}
          [ Bind_text receipt_digest; Bind_text source.source_revision;
            Bind_text source.configuration_digest;
            Bind_text source.authority_digest ]
      with
      | Ok count -> Ok (count = 1)
      | Error _ as error -> error

  let has_current_success database (source : current_source) action scope =
    if not source.source_clean then Ok false
    else
      match
        count_predicate database
          {|SELECT COUNT(*) FROM completion_receipt
              WHERE action=?1 AND scope=?2 AND verdict='succeeded'
                AND source_revision=?3 AND source_clean=1
                AND configuration_digest=?4 AND authority_digest=?5|}
          [ Bind_text action; Bind_text scope; Bind_text source.source_revision;
            Bind_text source.configuration_digest;
            Bind_text source.authority_digest ]
      with
      | Ok count -> Ok (count > 0)
      | Error _ as error -> error

  let effect_schema =
    {|CREATE TABLE IF NOT EXISTS run_effect_ledger(
        schema_version INTEGER NOT NULL CHECK(schema_version=1),
        idempotency_key TEXT PRIMARY KEY NOT NULL,
        request_digest TEXT NOT NULL,
        target_digest TEXT NOT NULL,
        target_authority_digest TEXT NOT NULL,
        effect_kind TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('pending','applied','indeterminate')),
        disposition TEXT,
        committed_output BLOB,
        committed_output_digest TEXT,
        receipt_digest TEXT,
        diagnostic_bytes BLOB,
        no_replay INTEGER NOT NULL CHECK(no_replay IN (0,1)),
        row_digest TEXT NOT NULL
      )|}

  let effect_expected_schema_columns =
    [ ("schema_version", "INTEGER", 1, 0);
      ("idempotency_key", "TEXT", 1, 1);
      ("request_digest", "TEXT", 1, 0);
      ("target_digest", "TEXT", 1, 0);
      ("target_authority_digest", "TEXT", 1, 0);
      ("effect_kind", "TEXT", 1, 0);
      ("state", "TEXT", 1, 0);
      ("disposition", "TEXT", 0, 0);
      ("committed_output", "BLOB", 0, 0);
      ("committed_output_digest", "TEXT", 0, 0);
      ("receipt_digest", "TEXT", 0, 0);
      ("diagnostic_bytes", "BLOB", 0, 0);
      ("no_replay", "INTEGER", 1, 0);
      ("row_digest", "TEXT", 1, 0) ]

  let effect_schema_columns database =
    statement database "PRAGMA table_info(run_effect_ledger)" (fun statement ->
      let rec loop rows =
        match step statement with
        | Ok Done -> Ok (List.rev rows)
        | Ok Row ->
            begin match text_column statement 1, text_column statement 2,
                        int_column statement 3, int_column statement 5 with
            | Ok (Some name), Ok (Some declared_type), Ok (Some not_null),
              Ok (Some primary_key) ->
                loop ((name, declared_type, not_null, primary_key) :: rows)
            | Ok _, Ok _, Ok _, Ok _ ->
                Error (Operation_failed "effect schema metadata contains null")
            | Error error, _, _, _ | _, Error error, _, _
            | _, _, Error error, _ | _, _, _, Error error -> Error error
            end
        | Error _ as error -> error
      in
      loop [])

  let initialize_effect database =
    match execute_sql database effect_schema with
    | Error _ as error -> error
    | Ok () ->
        begin match effect_schema_columns database with
        | Ok columns when columns = effect_expected_schema_columns -> Ok ()
        | Ok _ -> Error (Operation_failed "run_effect_ledger schema is not canonical v1")
        | Error _ as error -> error
        end

  let optional_blob_column statement column =
    match column_blob statement ~column with
    | Ok value -> Ok value
    | Error error -> Error (Operation_failed (string_of_statement_use_error error))

  let effect_read database idempotency_key =
    statement database
      {|SELECT schema_version,idempotency_key,request_digest,target_digest,
               target_authority_digest,effect_kind,state,disposition,
               committed_output,committed_output_digest,receipt_digest,
               diagnostic_bytes,no_replay,row_digest
          FROM run_effect_ledger WHERE idempotency_key=?1|}
      (fun statement ->
        match bind_values statement [ Bind_text idempotency_key ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Ok Row ->
                begin match
                  int_column statement 0, text_column statement 1,
                  text_column statement 2, text_column statement 3,
                  text_column statement 4, text_column statement 5,
                  text_column statement 6, text_column statement 7,
                  optional_blob_column statement 8, text_column statement 9,
                  text_column statement 10, optional_blob_column statement 11,
                  int_column statement 12, text_column statement 13
                with
                | Ok (Some schema_version), Ok (Some stored_key),
                  Ok (Some stored_request_digest), Ok (Some stored_target_digest),
                  Ok (Some stored_target_authority_digest),
                  Ok (Some stored_effect_kind), Ok (Some stored_state),
                  Ok stored_disposition, Ok stored_output,
                  Ok stored_output_digest, Ok stored_receipt_digest,
                  Ok stored_diagnostic, Ok (Some no_replay),
                  Ok (Some stored_row_digest) ->
                    if no_replay <> 0 && no_replay <> 1 then
                      Error
                        (Operation_failed
                           "effect ledger no_replay is outside 0..1")
                    else
                      begin match step statement with
                      | Ok Done ->
                          Ok
                            (Some
                               { schema_version; stored_key;
                                 stored_request_digest; stored_target_digest;
                                 stored_target_authority_digest;
                                 stored_effect_kind; stored_state;
                                 stored_disposition; stored_output;
                                 stored_output_digest; stored_receipt_digest;
                                 stored_diagnostic;
                                 stored_no_replay = no_replay = 1;
                                 stored_row_digest })
                      | Ok Row ->
                          Error
                            (Operation_failed
                               "effect ledger key is not unique")
                      | Error _ as error -> error
                      end
                | Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _,
                  Ok _, Ok _, Ok _, Ok _ ->
                    Error (Operation_failed "effect ledger required column is null")
                | Error error, _, _, _, _, _, _, _, _, _, _, _, _, _
                | _, Error error, _, _, _, _, _, _, _, _, _, _, _, _
                | _, _, Error error, _, _, _, _, _, _, _, _, _, _, _
                | _, _, _, Error error, _, _, _, _, _, _, _, _, _, _
                | _, _, _, _, Error error, _, _, _, _, _, _, _, _, _
                | _, _, _, _, _, Error error, _, _, _, _, _, _, _, _
                | _, _, _, _, _, _, Error error, _, _, _, _, _, _, _
                | _, _, _, _, _, _, _, Error error, _, _, _, _, _, _
                | _, _, _, _, _, _, _, _, Error error, _, _, _, _, _
                | _, _, _, _, _, _, _, _, _, Error error, _, _, _, _
                | _, _, _, _, _, _, _, _, _, _, Error error, _, _, _
                | _, _, _, _, _, _, _, _, _, _, _, Error error, _, _
                | _, _, _, _, _, _, _, _, _, _, _, _, Error error, _
                | _, _, _, _, _, _, _, _, _, _, _, _, _, Error error ->
                    Error error
                end
            | Error _ as error -> error
            end)

  let insert_effect_pending database (row : effect_row) =
    match
      statement database
        {|INSERT OR IGNORE INTO run_effect_ledger(
            schema_version,idempotency_key,request_digest,target_digest,
            target_authority_digest,effect_kind,state,disposition,
            committed_output,committed_output_digest,receipt_digest,
            diagnostic_bytes,no_replay,row_digest)
           VALUES(?1,?2,?3,?4,?5,?6,?7,NULL,NULL,NULL,NULL,NULL,?8,?9)|}
        (fun statement ->
          match
            bind_values statement
              [ Bind_int row.schema_version; Bind_text row.stored_key;
                Bind_text row.stored_request_digest;
                Bind_text row.stored_target_digest;
                Bind_text row.stored_target_authority_digest;
                Bind_text row.stored_effect_kind; Bind_text row.stored_state;
                Bind_int (if row.stored_no_replay then 1 else 0);
                Bind_text row.stored_row_digest ]
          with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () ->
        begin match changes database with
        | Ok changed when changed = 0 || changed = 1 ->
            begin match effect_read database row.stored_key with
            | Ok (Some readback) -> Ok readback
            | Ok None ->
                Error (Operation_failed "Pending insert has no readback")
            | Error _ as error -> error
            end
        | Ok _ ->
            Error
              (Operation_failed
                 "Pending insert changed an impossible row count")
        | Error error -> Error (Operation_failed (string_of_database_error error))
        end

  let bind_optional_text = function
    | None -> Bind_null
    | Some value -> Bind_text value

  let bind_optional_blob = function
    | None -> Bind_null
    | Some value -> Bind_blob value

  let cas_effect_pending database (cas : effect_cas) =
    let expected = cas.expected in
    let replacement = cas.replacement in
    match
      statement database
        {|UPDATE run_effect_ledger
              SET state=?1,disposition=?2,committed_output=?3,
                  committed_output_digest=?4,receipt_digest=?5,
                  diagnostic_bytes=?6,no_replay=?7,row_digest=?8
            WHERE idempotency_key=?9 AND request_digest=?10
              AND target_digest=?11 AND state='pending' AND row_digest=?12|}
        (fun statement ->
          match
            bind_values statement
              [ Bind_text replacement.stored_state;
                bind_optional_text replacement.stored_disposition;
                bind_optional_blob replacement.stored_output;
                bind_optional_text replacement.stored_output_digest;
                bind_optional_text replacement.stored_receipt_digest;
                bind_optional_blob replacement.stored_diagnostic;
                Bind_int (if replacement.stored_no_replay then 1 else 0);
                Bind_text replacement.stored_row_digest;
                Bind_text expected.stored_key;
                Bind_text expected.stored_request_digest;
                Bind_text expected.stored_target_digest;
                Bind_text expected.stored_row_digest ]
          with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () ->
        begin match changed database 1 with
        | Error _ ->
            Error
              (Operation_failed
                 "effect ledger Pending CAS did not change exactly one row")
        | Ok () ->
            begin match effect_read database expected.stored_key with
            | Ok None -> Error (Operation_failed "effect ledger CAS has no readback")
            | Ok (Some readback)
              when readback.stored_row_digest = replacement.stored_row_digest ->
                Ok readback
            | Ok (Some _) ->
                Error
                  (Operation_failed
                     "effect ledger CAS readback digest mismatch")
            | Error _ as error -> error
            end
        end

  let completion_store_schema =
    [ {|CREATE TABLE IF NOT EXISTS completion_schema (
          version INTEGER PRIMARY KEY CHECK(version = 1)
        )|};
      {|CREATE TABLE IF NOT EXISTS completion_owner (
          singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
          state TEXT NOT NULL CHECK(state IN ('active','draining','retired')),
          owner_session TEXT NOT NULL,
          store_epoch TEXT NOT NULL,
          authority_session TEXT NOT NULL,
          authority_epoch TEXT NOT NULL,
          opened_time_digest TEXT NOT NULL
        )|};
      {|CREATE TABLE IF NOT EXISTS completion_row (
          completion_id TEXT PRIMARY KEY,
          state TEXT NOT NULL CHECK(state IN
            ('reserved','finalized','indeterminate','conflict')),
          reservation_payload_digest TEXT NOT NULL,
          reserve_request_digest TEXT NOT NULL,
          reserve_time_digest TEXT NOT NULL,
          reserve_receipt_digest TEXT NOT NULL,
          finalize_request_digest TEXT,
          finalize_time_digest TEXT,
          finalize_receipt_digest TEXT,
          conflict_digest TEXT
        )|} ]

  let initialize_completion_store database =
    match execute_all database completion_store_schema with
    | Error _ as error -> error
    | Ok () ->
        execute_sql database
          "INSERT OR IGNORE INTO completion_schema(version) VALUES(1)"

  let insert_completion_store_owner database
      (owner : completion_store_owner) =
    statement database
      {|INSERT INTO completion_owner(
          singleton,state,owner_session,store_epoch,authority_session,
          authority_epoch,opened_time_digest)
        VALUES(1,'active',?1,?2,?3,?4,?5)|}
      (fun statement ->
        match
          bind_values statement
            [ Bind_text owner.completion_owner_session;
              Bind_text owner.completion_store_epoch;
              Bind_text owner.completion_authority_session;
              Bind_text owner.completion_authority_epoch;
              Bind_text owner.completion_opened_time_digest ]
        with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let completion_store_row_of_statement ~completion_row_id statement offset =
    match text_column statement offset, text_column statement (offset + 1),
          text_column statement (offset + 2), text_column statement (offset + 3),
          text_column statement (offset + 4), text_column statement (offset + 5),
          text_column statement (offset + 6), text_column statement (offset + 7),
          text_column statement (offset + 8) with
    | Ok (Some completion_row_state),
      Ok (Some completion_reservation_payload_digest),
      Ok (Some completion_reserve_request_digest),
      Ok (Some completion_reserve_time_digest),
      Ok (Some completion_reserve_receipt_digest),
      Ok completion_finalize_request_digest,
      Ok completion_finalize_time_digest,
      Ok completion_finalize_receipt_digest,
      Ok completion_conflict_digest ->
        Ok
          { completion_row_id; completion_row_state;
            completion_reservation_payload_digest;
            completion_reserve_request_digest; completion_reserve_time_digest;
            completion_reserve_receipt_digest;
            completion_finalize_request_digest; completion_finalize_time_digest;
            completion_finalize_receipt_digest; completion_conflict_digest }
    | Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _, Ok _ ->
        Error (Operation_failed "completion store required column is null")
    | Error error, _, _, _, _, _, _, _, _
    | _, Error error, _, _, _, _, _, _, _
    | _, _, Error error, _, _, _, _, _, _
    | _, _, _, Error error, _, _, _, _, _
    | _, _, _, _, Error error, _, _, _, _
    | _, _, _, _, _, Error error, _, _, _
    | _, _, _, _, _, _, Error error, _, _
    | _, _, _, _, _, _, _, Error error, _
    | _, _, _, _, _, _, _, _, Error error -> Error error

  let read_completion_store database completion_id =
    statement database
      {|SELECT state,reservation_payload_digest,reserve_request_digest,
               reserve_time_digest,reserve_receipt_digest,
               finalize_request_digest,finalize_time_digest,
               finalize_receipt_digest,conflict_digest
          FROM completion_row WHERE completion_id=?1|}
      (fun statement ->
        match bind_values statement [ Bind_text completion_id ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Error _ as error -> error
            | Ok Row ->
                begin match
                  completion_store_row_of_statement
                    ~completion_row_id:completion_id statement 0
                with
                | Error _ as error -> error
                | Ok row ->
                    begin match step statement with
                    | Ok Done -> Ok (Some row)
                    | Ok Row ->
                        Error (Operation_failed "completion id is not unique")
                    | Error _ as error -> error
                    end
                end
            end)

  let insert_completion_reservation database (row : completion_store_row) =
    statement database
      {|INSERT INTO completion_row(
          completion_id,state,reservation_payload_digest,reserve_request_digest,
          reserve_time_digest,reserve_receipt_digest,finalize_request_digest,
          finalize_time_digest,finalize_receipt_digest,conflict_digest)
        VALUES(?1,'reserved',?2,?3,?4,?5,NULL,NULL,NULL,NULL)|}
      (fun statement ->
        match
          bind_values statement
            [ Bind_text row.completion_row_id;
              Bind_text row.completion_reservation_payload_digest;
              Bind_text row.completion_reserve_request_digest;
              Bind_text row.completion_reserve_time_digest;
              Bind_text row.completion_reserve_receipt_digest ]
        with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let completion_store_mark_conflict database
      (conflict : completion_store_conflict) =
    match
      statement database
        {|UPDATE completion_row SET state='conflict',conflict_digest=?1
            WHERE completion_id=?2 AND state<>'conflict'|}
        (fun statement ->
          match
            bind_values statement
              [ Bind_text conflict.completion_conflict_value;
                Bind_text conflict.completion_conflict_id ]
          with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () ->
        begin match changes database with
        | Ok count -> Ok (count = 1)
        | Error error -> Error (Operation_failed (string_of_database_error error))
        end

  let finalize_completion_store database
      (finalize : completion_store_finalize) =
    match
      statement database
        {|UPDATE completion_row
              SET state='finalized',finalize_request_digest=?1,
                  finalize_time_digest=?2,finalize_receipt_digest=?3
            WHERE completion_id=?4 AND state='reserved'
              AND reservation_payload_digest=?5|}
        (fun statement ->
          match
            bind_values statement
              [ Bind_text finalize.completion_finalize_request_value;
                Bind_text finalize.completion_finalize_time_value;
                Bind_text finalize.completion_finalize_receipt_value;
                Bind_text finalize.completion_finalize_id;
                Bind_text
                  finalize.completion_finalize_reservation_payload_digest ]
          with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () ->
        begin match changes database with
        | Ok count -> Ok (count = 1)
        | Error error -> Error (Operation_failed (string_of_database_error error))
        end

  let all_completion_store_rows database =
    statement database
      {|SELECT completion_id,state,reservation_payload_digest,
               reserve_request_digest,reserve_time_digest,reserve_receipt_digest,
               finalize_request_digest,finalize_time_digest,
               finalize_receipt_digest,conflict_digest
          FROM completion_row ORDER BY completion_id|}
      (fun statement ->
        let rec loop rows =
          match step statement with
          | Ok Done -> Ok (List.rev rows)
          | Error _ as error -> error
          | Ok Row ->
              begin match text_column statement 0 with
              | Ok (Some completion_row_id) ->
                  begin match
                    completion_store_row_of_statement ~completion_row_id
                      statement 1
                  with
                  | Ok row -> loop (row :: rows)
                  | Error _ as error -> error
                  end
              | Ok None -> Error (Operation_failed "completion id is null")
              | Error _ as error -> error
              end
        in
        loop [])

  let completion_store_owner_cas database
      (cas : completion_store_owner_cas) =
    match
      statement database
        {|UPDATE completion_owner SET state=?1
            WHERE singleton=1 AND state=?2 AND owner_session=?3 AND store_epoch=?4|}
        (fun statement ->
          match
            bind_values statement
              [ Bind_text cas.completion_owner_to_state;
                Bind_text cas.completion_owner_from_state;
                Bind_text cas.completion_owner_cas_session;
                Bind_text cas.completion_owner_cas_epoch ]
          with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () ->
        begin match changes database with
        | Ok count -> Ok (count = 1)
        | Error error -> Error (Operation_failed (string_of_database_error error))
        end

  let dispatch_store_schema =
    [ {|CREATE TABLE IF NOT EXISTS dispatch_schema (
          version INTEGER PRIMARY KEY CHECK(version = 1))|};
      {|CREATE TABLE IF NOT EXISTS dispatch_owner_session_pointer (
          singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
          current_ordinal INTEGER NOT NULL CHECK(current_ordinal >= 0),
          state TEXT NOT NULL CHECK(state IN ('active','draining','retired')),
          session_digest TEXT NOT NULL,
          recovery_attempt INTEGER NOT NULL CHECK(recovery_attempt >= 1),
          store_epoch TEXT NOT NULL)|};
      {|CREATE TABLE IF NOT EXISTS dispatch_owner_session_transition (
          ordinal INTEGER PRIMARY KEY CHECK(ordinal >= 0),
          state TEXT NOT NULL CHECK(state IN ('active','draining','retired')),
          session_digest TEXT NOT NULL,
          recovery_attempt INTEGER NOT NULL CHECK(recovery_attempt >= 1),
          store_epoch TEXT NOT NULL, bootstrap_digest TEXT NOT NULL,
          time_digest TEXT NOT NULL, transition_id TEXT NOT NULL UNIQUE)|};
      {|CREATE TABLE IF NOT EXISTS dispatch_pointer (
          key_digest TEXT PRIMARY KEY,
          current_ordinal INTEGER NOT NULL CHECK(current_ordinal >= 0),
          owner_session TEXT NOT NULL,
          recovery_attempt INTEGER NOT NULL CHECK(recovery_attempt >= 1))|};
      {|CREATE TABLE IF NOT EXISTS dispatch_transition (
          key_digest TEXT NOT NULL,
          ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
          status TEXT NOT NULL CHECK(status IN
            ('not-dispatched','dispatch-claimed','terminal','indeterminate')),
          transition_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
          time_digest TEXT NOT NULL, owner_session TEXT NOT NULL,
          recovery_attempt INTEGER NOT NULL CHECK(recovery_attempt >= 1),
          PRIMARY KEY(key_digest, ordinal))|};
      {|CREATE TABLE IF NOT EXISTS conditional_decision (
          key_digest TEXT PRIMARY KEY,
          status TEXT NOT NULL CHECK(status IN
            ('undecided','decided','decision-indeterminate')),
          decision_id TEXT NOT NULL UNIQUE, plan_digest TEXT NOT NULL,
          time_digest TEXT NOT NULL, owner_session TEXT NOT NULL,
          recovery_attempt INTEGER NOT NULL CHECK(recovery_attempt >= 1))|};
      {|CREATE TABLE IF NOT EXISTS abandonment_commitment (
          key_digest TEXT PRIMARY KEY,
          purpose TEXT NOT NULL CHECK(purpose IN
            ('global-no-effect','fenced-unentered-tail')),
          evidence_digest TEXT NOT NULL, commitment_id TEXT NOT NULL UNIQUE,
          owner_session TEXT NOT NULL,
          recovery_attempt INTEGER NOT NULL CHECK(recovery_attempt >= 1))|} ]

  let initialize_dispatch_store database =
    match execute_all database dispatch_store_schema with
    | Error _ as error -> error
    | Ok () ->
        execute_sql database
          "INSERT OR IGNORE INTO dispatch_schema(version) VALUES(1)"

  let insert_dispatch_initial_owner database
      (owner : dispatch_store_initial_owner) =
    match
      statement database
        {|INSERT INTO dispatch_owner_session_transition(
            ordinal,state,session_digest,recovery_attempt,store_epoch,
            bootstrap_digest,time_digest,transition_id)
          VALUES(0,'active',?1,?2,?3,?4,?5,?6)|}
        (fun statement ->
          match bind_values statement
              [ Bind_text owner.dispatch_initial_session;
                Bind_int owner.dispatch_initial_recovery_attempt;
                Bind_text owner.dispatch_initial_store_epoch;
                Bind_text owner.dispatch_initial_bootstrap_digest;
                Bind_text owner.dispatch_initial_time_digest;
                Bind_text owner.dispatch_initial_transition_id ] with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () ->
        statement database
          {|INSERT INTO dispatch_owner_session_pointer(
              singleton,current_ordinal,state,session_digest,
              recovery_attempt,store_epoch)
            VALUES(1,0,'active',?1,?2,?3)|}
          (fun statement ->
            match bind_values statement
                [ Bind_text owner.dispatch_initial_session;
                  Bind_int owner.dispatch_initial_recovery_attempt;
                  Bind_text owner.dispatch_initial_store_epoch ] with
            | Error _ as error -> error
            | Ok () -> step_done statement)

  let read_dispatch_pointer database key =
    statement database
      {|SELECT current_ordinal,owner_session,recovery_attempt
          FROM dispatch_pointer WHERE key_digest=?1|}
      (fun statement ->
        match bind_values statement [ Bind_text key ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Error _ as error -> error
            | Ok Row ->
                begin match int_column statement 0, text_column statement 1,
                            int_column statement 2 with
                | Ok (Some dispatch_pointer_ordinal),
                  Ok (Some dispatch_pointer_session),
                  Ok (Some dispatch_pointer_attempt) ->
                    Ok
                      (Some
                         { dispatch_pointer_key = key;
                           dispatch_pointer_ordinal;
                           dispatch_pointer_session;
                           dispatch_pointer_attempt })
                | Ok _, Ok _, Ok _ ->
                    Error (Operation_failed "dispatch pointer contains null")
                | Error error, _, _ | _, Error error, _ | _, _, Error error ->
                    Error error
                end
            end)

  let dispatch_row_of_statement lookup statement =
    match text_column statement 0, text_column statement 1,
          text_column statement 2, text_column statement 3,
          text_column statement 4, int_column statement 5 with
    | Ok (Some dispatch_row_status), Ok (Some dispatch_row_transition_id),
      Ok (Some dispatch_row_request_digest),
      Ok (Some dispatch_row_time_digest),
      Ok (Some dispatch_row_owner_session),
      Ok (Some dispatch_row_recovery_attempt) ->
        Ok
          { dispatch_row_key = lookup.dispatch_lookup_key;
            dispatch_row_ordinal = lookup.dispatch_lookup_ordinal;
            dispatch_row_status; dispatch_row_transition_id;
            dispatch_row_request_digest; dispatch_row_time_digest;
            dispatch_row_owner_session; dispatch_row_recovery_attempt }
    | Ok _, Ok _, Ok _, Ok _, Ok _, Ok _ ->
        Error (Operation_failed "dispatch transition contains null")
    | Error error, _, _, _, _, _ | _, Error error, _, _, _, _
    | _, _, Error error, _, _, _ | _, _, _, Error error, _, _
    | _, _, _, _, Error error, _ | _, _, _, _, _, Error error -> Error error

  let read_dispatch_transition database lookup =
    statement database
      {|SELECT status,transition_id,request_digest,time_digest,
               owner_session,recovery_attempt
          FROM dispatch_transition WHERE key_digest=?1 AND ordinal=?2|}
      (fun statement ->
        match bind_values statement
            [ Bind_text lookup.dispatch_lookup_key;
              Bind_int lookup.dispatch_lookup_ordinal ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Error _ as error -> error
            | Ok Row ->
                begin match dispatch_row_of_statement lookup statement with
                | Ok row -> Ok (Some row)
                | Error _ as error -> error
                end
            end)

  let read_dispatch_decision database key =
    statement database
      {|SELECT status,decision_id,plan_digest,time_digest,
               owner_session,recovery_attempt
          FROM conditional_decision WHERE key_digest=?1|}
      (fun statement ->
        match bind_values statement [ Bind_text key ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Error _ as error -> error
            | Ok Row ->
                begin match text_column statement 0, text_column statement 1,
                            text_column statement 2, text_column statement 3,
                            text_column statement 4, int_column statement 5 with
                | Ok (Some dispatch_decision_status),
                  Ok (Some dispatch_decision_id),
                  Ok (Some dispatch_decision_plan_digest),
                  Ok (Some dispatch_decision_time_digest),
                  Ok (Some dispatch_decision_owner_session),
                  Ok (Some dispatch_decision_recovery_attempt) ->
                    Ok
                      (Some
                         { dispatch_decision_key = key;
                           dispatch_decision_status; dispatch_decision_id;
                           dispatch_decision_plan_digest;
                           dispatch_decision_time_digest;
                           dispatch_decision_owner_session;
                           dispatch_decision_recovery_attempt })
                | Ok _, Ok _, Ok _, Ok _, Ok _, Ok _ ->
                    Error (Operation_failed "dispatch decision contains null")
                | Error error, _, _, _, _, _ | _, Error error, _, _, _, _
                | _, _, Error error, _, _, _ | _, _, _, Error error, _, _
                | _, _, _, _, Error error, _ | _, _, _, _, _, Error error ->
                    Error error
                end
            end)

  let insert_dispatch_transition database (row : dispatch_store_row) =
    statement database
      {|INSERT INTO dispatch_transition(
          key_digest,ordinal,status,transition_id,request_digest,
          time_digest,owner_session,recovery_attempt)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8)|}
      (fun statement ->
        match bind_values statement
            [ Bind_text row.dispatch_row_key; Bind_int row.dispatch_row_ordinal;
              Bind_text row.dispatch_row_status;
              Bind_text row.dispatch_row_transition_id;
              Bind_text row.dispatch_row_request_digest;
              Bind_text row.dispatch_row_time_digest;
              Bind_text row.dispatch_row_owner_session;
              Bind_int row.dispatch_row_recovery_attempt ] with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let insert_dispatch_pointer database (pointer : dispatch_store_pointer) =
    statement database
      {|INSERT INTO dispatch_pointer(
          key_digest,current_ordinal,owner_session,recovery_attempt)
        VALUES(?1,?2,?3,?4)|}
      (fun statement ->
        match bind_values statement
            [ Bind_text pointer.dispatch_pointer_key;
              Bind_int pointer.dispatch_pointer_ordinal;
              Bind_text pointer.dispatch_pointer_session;
              Bind_int pointer.dispatch_pointer_attempt ] with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let insert_dispatch_decision database (row : dispatch_store_decision) =
    statement database
      {|INSERT INTO conditional_decision(
          key_digest,status,decision_id,plan_digest,time_digest,
          owner_session,recovery_attempt)
        VALUES(?1,?2,?3,?4,?5,?6,?7)|}
      (fun statement ->
        match bind_values statement
            [ Bind_text row.dispatch_decision_key;
              Bind_text row.dispatch_decision_status;
              Bind_text row.dispatch_decision_id;
              Bind_text row.dispatch_decision_plan_digest;
              Bind_text row.dispatch_decision_time_digest;
              Bind_text row.dispatch_decision_owner_session;
              Bind_int row.dispatch_decision_recovery_attempt ] with
        | Error _ as error -> error
        | Ok () -> step_done statement)

  let cas_dispatch_pointer database (cas : dispatch_store_pointer_cas) =
    match statement database
      {|UPDATE dispatch_pointer SET current_ordinal=?1
          WHERE key_digest=?2 AND current_ordinal=?3
            AND owner_session=?4 AND recovery_attempt=?5|}
      (fun statement ->
        match bind_values statement
            [ Bind_int cas.dispatch_pointer_replacement_ordinal;
              Bind_text cas.dispatch_pointer_cas_key;
              Bind_int cas.dispatch_pointer_expected_ordinal;
              Bind_text cas.dispatch_pointer_cas_session;
              Bind_int cas.dispatch_pointer_cas_attempt ] with
        | Error _ as error -> error
        | Ok () -> step_done statement) with
    | Error _ as error -> error
    | Ok () ->
        begin match changes database with
        | Ok count -> Ok (count = 1)
        | Error error -> Error (Operation_failed (string_of_database_error error))
        end

  let read_dispatch_abandonment database key =
    statement database
      {|SELECT commitment_id,evidence_digest
          FROM abandonment_commitment WHERE key_digest=?1|}
      (fun statement ->
        match bind_values statement [ Bind_text key ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Error _ as error -> error
            | Ok Row ->
                begin match text_column statement 0, text_column statement 1 with
                | Ok (Some dispatch_abandonment_commitment_id),
                  Ok (Some dispatch_abandonment_evidence_digest) ->
                    Ok
                      (Some
                         { dispatch_abandonment_commitment_id;
                           dispatch_abandonment_evidence_digest })
                | Ok _, Ok _ ->
                    Error (Operation_failed "abandonment row contains null")
                | Error error, _ | _, Error error -> Error error
                end
            end)

  let collect_dispatch_ids database sql =
    statement database sql (fun statement ->
      let rec loop values =
        match step statement with
        | Ok Done -> Ok (List.rev values)
        | Error _ as error -> error
        | Ok Row ->
            begin match text_column statement 0 with
            | Ok (Some value) -> loop (value :: values)
            | Ok None -> Error (Operation_failed "dispatch identity is null")
            | Error _ as error -> error
            end
      in
      loop [])

  let dispatch_inventory_ids database =
    match collect_dispatch_ids database
      "SELECT transition_id FROM dispatch_owner_session_transition ORDER BY ordinal"
    with
    | Error _ as error -> error
    | Ok dispatch_inventory_owner_rows ->
        begin match collect_dispatch_ids database
          "SELECT transition_id FROM dispatch_transition ORDER BY key_digest,ordinal"
        with
        | Error _ as error -> error
        | Ok dispatch_inventory_transition_rows ->
            begin match collect_dispatch_ids database
              "SELECT decision_id FROM conditional_decision ORDER BY key_digest"
            with
            | Error _ as error -> error
            | Ok dispatch_inventory_decision_rows ->
                begin match collect_dispatch_ids database
                  "SELECT commitment_id FROM abandonment_commitment ORDER BY key_digest"
                with
                | Error _ as error -> error
                | Ok dispatch_inventory_abandonment_rows ->
                    Ok
                      { dispatch_inventory_owner_rows;
                        dispatch_inventory_transition_rows;
                        dispatch_inventory_decision_rows;
                        dispatch_inventory_abandonment_rows }
                end
            end
        end

  let dispatch_owner_transition database
      (transition : dispatch_store_owner_transition) =
    match statement database
      {|INSERT INTO dispatch_owner_session_transition(
          ordinal,state,session_digest,recovery_attempt,store_epoch,
          bootstrap_digest,time_digest,transition_id)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8)|}
      (fun statement ->
        match bind_values statement
            [ Bind_int transition.dispatch_owner_transition_ordinal;
              Bind_text transition.dispatch_owner_transition_state;
              Bind_text transition.dispatch_owner_transition_session;
              Bind_int transition.dispatch_owner_transition_attempt;
              Bind_text transition.dispatch_owner_transition_epoch;
              Bind_text transition.dispatch_owner_transition_bootstrap_digest;
              Bind_text transition.dispatch_owner_transition_time_digest;
              Bind_text transition.dispatch_owner_transition_id ] with
        | Error _ as error -> error
        | Ok () -> step_done statement) with
    | Error _ as error -> error
    | Ok () ->
        begin match statement database
          {|UPDATE dispatch_owner_session_pointer
              SET current_ordinal=?1,state=?2
            WHERE singleton=1 AND current_ordinal=?3
              AND session_digest=?4 AND recovery_attempt=?5 AND store_epoch=?6|}
          (fun statement ->
            match bind_values statement
                [ Bind_int transition.dispatch_owner_transition_ordinal;
                  Bind_text transition.dispatch_owner_transition_state;
                  Bind_int (transition.dispatch_owner_transition_ordinal - 1);
                  Bind_text transition.dispatch_owner_transition_session;
                  Bind_int transition.dispatch_owner_transition_attempt;
                  Bind_text transition.dispatch_owner_transition_epoch ] with
            | Error _ as error -> error
            | Ok () -> step_done statement) with
        | Error _ as error -> error
        | Ok () ->
            begin match changes database with
            | Ok count -> Ok (count = 1)
            | Error error ->
                Error (Operation_failed (string_of_database_error error))
            end
        end

  let drain_sql database sql =
    statement database sql (fun statement ->
      let rec drain () =
        match step statement with
        | Ok Row -> drain ()
        | Ok Done -> Ok ()
        | Error _ as error -> error
      in
      drain ())

  let query_texts database sql =
    statement database sql (fun statement ->
      let rec loop values =
        match step statement with
        | Ok Row ->
            begin match text_column statement 0 with
            | Ok (Some value) -> loop (value :: values)
            | Ok None -> Error (Operation_failed "text result is null")
            | Error _ as error -> error
            end
        | Ok Done -> Ok (List.rev values)
        | Error _ as error -> error
      in
      loop [])

  let query_int64s database sql =
    statement database sql (fun statement ->
      let rec loop values =
        match step statement with
        | Ok Row ->
            begin match int64_column statement 0 with
            | Ok (Some value) -> loop (value :: values)
            | Ok None -> Error (Operation_failed "integer result is null")
            | Error _ as error -> error
            end
        | Ok Done -> Ok (List.rev values)
        | Error _ as error -> error
      in
      loop [])

  let verify_event_configuration database =
    match query_int64s database "PRAGMA synchronous" with
    | Error _ as error -> error
    | Ok synchronous ->
        begin match query_int64s database "PRAGMA foreign_keys" with
        | Error _ as error -> error
        | Ok foreign_keys ->
            begin match query_int64s database "PRAGMA busy_timeout" with
            | Error _ as error -> error
            | Ok busy_timeout ->
                if synchronous <> [ 1L ] then
                  Error
                    (Operation_failed
                       "actor connection synchronous mode is not NORMAL")
                else if foreign_keys <> [ 1L ] then
                  Error
                    (Operation_failed
                       "actor connection foreign_keys is not ON")
                else if busy_timeout <> [ 5000L ] then
                  Error
                    (Operation_failed
                       "actor connection busy_timeout is not 5000ms")
                else Ok ()
            end
        end

  let configure_event database =
    match drain_sql database "PRAGMA busy_timeout=5000" with
    | Error _ as error -> error
    | Ok () ->
        begin match drain_sql database "PRAGMA journal_mode=WAL" with
        | Error _ as error -> error
        | Ok () ->
            begin match query_texts database "PRAGMA journal_mode" with
            | Error _ as error -> error
            | Ok modes ->
                let posture = storage_posture database in
                let accepted =
                  match posture, modes with
                  | Durable_registered, [ mode ]
                    when String.lowercase_ascii mode = "wal" -> Ok ()
                  | Volatile_test, [ mode ]
                    when String.lowercase_ascii mode = "memory" -> Ok ()
                  | Durable_registered, [ mode ] ->
                      Error
                        (Operation_failed
                           ("WAL unavailable for durable registered storage: journal_mode="
                            ^ mode))
                  | Volatile_test, [ mode ] ->
                      Error
                        (Operation_failed
                           ("volatile test storage must report memory journal mode: journal_mode="
                            ^ mode))
                  | Durable_registered, _ ->
                      Error
                        (Operation_failed
                           "WAL unavailable: journal_mode returned no single value")
                  | Volatile_test, _ ->
                      Error
                        (Operation_failed
                           "volatile test storage journal_mode returned no single value")
                in
                begin match accepted with
                | Error _ as error -> error
                | Ok () ->
                    begin match drain_sql database "PRAGMA synchronous=NORMAL" with
                    | Error _ as error -> error
                    | Ok () ->
                        begin match drain_sql database "PRAGMA foreign_keys=ON" with
                        | Error _ as error -> error
                        | Ok () -> verify_event_configuration database
                        end
                    end
                end
            end
        end

  let event_table_sql =
    {|CREATE TABLE run_event (
        run_id TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        event_id TEXT NOT NULL,
        event_digest TEXT NOT NULL,
        event_json TEXT NOT NULL,
        UNIQUE(run_id, event_id),
        PRIMARY KEY(run_id, sequence)
      )|}

  let event_update_trigger_sql =
    {|CREATE TRIGGER run_event_no_update
       BEFORE UPDATE ON run_event BEGIN
         SELECT RAISE(ABORT, 'run_event is append-only');
       END|}

  let event_delete_trigger_sql =
    {|CREATE TRIGGER run_event_no_delete
       BEFORE DELETE ON run_event BEGIN
         SELECT RAISE(ABORT, 'run_event is append-only');
       END|}

  let event_marker_sql =
    "CREATE TABLE run_event_schema(version INTEGER PRIMARY KEY)"

  type event_table_column = {
    column_cid : int64;
    column_name : string;
    column_declared_type : string;
    column_not_null : int64;
    column_primary_key_position : int64;
  }

  let event_expected_columns =
    [ { column_cid = 0L; column_name = "run_id";
        column_declared_type = "TEXT"; column_not_null = 1L;
        column_primary_key_position = 1L };
      { column_cid = 1L; column_name = "sequence";
        column_declared_type = "INTEGER"; column_not_null = 1L;
        column_primary_key_position = 2L };
      { column_cid = 2L; column_name = "event_id";
        column_declared_type = "TEXT"; column_not_null = 1L;
        column_primary_key_position = 0L };
      { column_cid = 3L; column_name = "event_digest";
        column_declared_type = "TEXT"; column_not_null = 1L;
        column_primary_key_position = 0L };
      { column_cid = 4L; column_name = "event_json";
        column_declared_type = "TEXT"; column_not_null = 1L;
        column_primary_key_position = 0L } ]

  type event_index = { index_origin : string; index_columns : string list }

  let normalize_sql sql =
    let buffer = Buffer.create (String.length sql) in
    let rec loop quoted index =
      if index = String.length sql then Buffer.contents buffer
      else
        let character = sql.[index] in
        if character = '\'' then begin
          Buffer.add_char buffer character;
          loop (not quoted) (index + 1)
        end else if
          (not quoted)
          && (character = ' ' || character = '\n' || character = '\r'
              || character = '\t')
        then loop quoted (index + 1)
        else begin
          Buffer.add_char buffer (Char.lowercase_ascii character);
          loop quoted (index + 1)
        end
    in
    loop false 0

  let event_table_columns database =
    statement database "PRAGMA table_info(run_event)" (fun statement ->
      let rec loop columns =
        match step statement with
        | Ok Done -> Ok (List.rev columns)
        | Ok Row ->
            begin match int64_column statement 0, text_column statement 1,
                        text_column statement 2, int64_column statement 3,
                        int64_column statement 5 with
            | Ok (Some column_cid), Ok (Some column_name),
              Ok (Some column_declared_type), Ok (Some column_not_null),
              Ok (Some column_primary_key_position) ->
                loop
                  ({ column_cid; column_name; column_declared_type;
                     column_not_null; column_primary_key_position }
                   :: columns)
            | Ok _, Ok _, Ok _, Ok _, Ok _ ->
                Error (Operation_failed "run_event schema metadata contains null")
            | Error error, _, _, _, _ | _, Error error, _, _, _
            | _, _, Error error, _, _ | _, _, _, Error error, _
            | _, _, _, _, Error error -> Error error
            end
        | Error _ as error -> error
      in
      loop [])

  let event_index_columns database index_name =
    let sql = "PRAGMA index_info(" ^ Printf.sprintf "%S" index_name ^ ")" in
    statement database sql (fun statement ->
      let rec loop columns =
        match step statement with
        | Ok Done -> Ok (List.rev columns)
        | Ok Row ->
            begin match text_column statement 2 with
            | Ok (Some name) -> loop (name :: columns)
            | Ok None -> Error (Operation_failed "event index column is null")
            | Error _ as error -> error
            end
        | Error _ as error -> error
      in
      loop [])

  let event_indexes database =
    statement database "PRAGMA index_list(run_event)" (fun statement ->
      let rec loop indexes =
        match step statement with
        | Ok Done -> Ok (List.rev indexes)
        | Ok Row ->
            begin match text_column statement 1, int64_column statement 2,
                        text_column statement 3, int64_column statement 4 with
            | Ok (Some name), Ok (Some unique), Ok (Some origin),
              Ok (Some partial) ->
                if unique <> 1L || partial <> 0L then
                  Error
                    (Operation_failed
                       ("run_event has a noncanonical index: " ^ name))
                else
                  begin match event_index_columns database name with
                  | Ok index_columns ->
                      loop ({ index_origin = origin; index_columns } :: indexes)
                  | Error _ as error -> error
                  end
            | Ok _, Ok _, Ok _, Ok _ ->
                Error (Operation_failed "event index metadata contains null")
            | Error error, _, _, _ | _, Error error, _, _
            | _, _, Error error, _ | _, _, _, Error error -> Error error
            end
        | Error _ as error -> error
      in
      loop [])

  let event_schema_object database kind name =
    statement database
      "SELECT sql FROM sqlite_master WHERE type=?1 AND name=?2"
      (fun statement ->
        match bind_values statement [ Bind_text kind; Bind_text name ] with
        | Error _ as error -> error
        | Ok () ->
            begin match step statement with
            | Ok Done -> Ok None
            | Ok Row ->
                begin match text_column statement 0 with
                | Ok (Some sql) ->
                    begin match step statement with
                    | Ok Done -> Ok (Some sql)
                    | Ok Row ->
                        Error
                          (Operation_failed
                             ("duplicate schema metadata: " ^ name))
                    | Error _ as error -> error
                    end
                | Ok None -> Error (Operation_failed "schema SQL is null")
                | Error _ as error -> error
                end
            | Error _ as error -> error
            end)

  let event_triggers database =
    statement database
      "SELECT name, sql FROM sqlite_master WHERE type='trigger' AND tbl_name='run_event' ORDER BY name"
      (fun statement ->
        let rec loop triggers =
          match step statement with
          | Ok Done -> Ok (List.rev triggers)
          | Ok Row ->
              begin match text_column statement 0, text_column statement 1 with
              | Ok (Some name), Ok (Some sql) ->
                  loop ((name, normalize_sql sql) :: triggers)
              | Ok _, Ok _ ->
                  Error (Operation_failed "event trigger metadata contains null")
              | Error error, _ | _, Error error -> Error error
              end
          | Error _ as error -> error
        in
        loop [])

  let validate_event_schema database =
    match event_schema_object database "table" "run_event_schema" with
    | Error _ as error -> error
    | Ok marker_definition ->
        begin match event_schema_object database "table" "run_event" with
        | Error _ as error -> error
        | Ok table_definition ->
            if
              Option.map normalize_sql marker_definition
              <> Some (normalize_sql event_marker_sql)
            then
              Error
                (Operation_failed
                   "run_event_schema marker definition is not canonical v1")
            else if
              Option.map normalize_sql table_definition
              <> Some (normalize_sql event_table_sql)
            then
              Error
                (Operation_failed
                   "run_event table SQL has unversioned semantic drift")
            else
              begin match event_table_columns database with
              | Error _ as error -> error
              | Ok columns when columns <> event_expected_columns ->
                  Error
                    (Operation_failed
                       "run_event table columns or primary key are not canonical v1")
              | Ok _ ->
                  begin match event_indexes database with
                  | Error _ as error -> error
                  | Ok indexes ->
                      let indexes = List.sort compare indexes in
                      let expected =
                        List.sort compare
                          [ { index_origin = "pk";
                              index_columns = [ "run_id"; "sequence" ] };
                            { index_origin = "u";
                              index_columns = [ "run_id"; "event_id" ] } ]
                      in
                      if indexes <> expected then
                        Error
                          (Operation_failed
                             "run_event primary/unique indexes are not canonical v1")
                      else
                        begin match event_triggers database with
                        | Error _ as error -> error
                        | Ok triggers ->
                            let expected_triggers =
                              [ ("run_event_no_delete",
                                 normalize_sql event_delete_trigger_sql);
                                ("run_event_no_update",
                                 normalize_sql event_update_trigger_sql) ]
                            in
                            if triggers = expected_triggers then Ok ()
                            else
                              Error
                                (Operation_failed
                                   "run_event trigger set is not exactly the canonical v1 authority")
                        end
                  end
              end
        end

  let event_transaction database body =
    match with_transaction database (fun _ -> body ()) with
    | Ok value -> Ok value
    | Error (Transaction_body_failed error) -> Error error
    | Error error ->
        Error
          (Operation_failed
             (string_of_transaction_error string_of_error error))

  let initialize_event database =
    match
      drain_sql database
        "CREATE TABLE IF NOT EXISTS run_event_schema(version INTEGER PRIMARY KEY)"
    with
    | Error _ as error -> error
    | Ok () ->
        begin match
          query_texts database
            "SELECT CAST(version AS TEXT) FROM run_event_schema ORDER BY version"
        with
        | Error _ as error -> error
        | Ok [ "1" ] -> validate_event_schema database
        | Ok [] ->
            event_transaction database (fun () ->
              match
                drain_sql database
                  "INSERT INTO run_event_schema(version) VALUES(1)"
              with
              | Error _ as error -> error
              | Ok () ->
                  let rec create = function
                    | [] -> validate_event_schema database
                    | sql :: rest ->
                        begin match drain_sql database sql with
                        | Ok () -> create rest
                        | Error _ as error -> error
                        end
                  in
                  create
                    [ event_table_sql; event_update_trigger_sql;
                      event_delete_trigger_sql ])
        | Ok versions ->
            Error
              (Operation_failed
                 ("unsupported run-event schema version(s): "
                  ^ String.concat "," versions))
        end

  let event_row_of_statement statement =
    match text_column statement 0, int64_column statement 1,
          text_column statement 2, text_column statement 3,
          text_column statement 4 with
    | Ok (Some run_id), Ok (Some sequence), Ok (Some event_id),
      Ok (Some event_digest), Ok (Some event_json) ->
        Ok { run_id; sequence; event_id; event_digest; event_json }
    | Ok _, Ok _, Ok _, Ok _, Ok _ ->
        Error (Operation_failed "run_event row contains null")
    | Error error, _, _, _, _ | _, Error error, _, _, _
    | _, _, Error error, _, _ | _, _, _, Error error, _
    | _, _, _, _, Error error -> Error error

  let query_event_rows database sql bindings =
    statement database sql (fun statement ->
      match bind_values statement bindings with
      | Error _ as error -> error
      | Ok () ->
          let rec loop rows =
            match step statement with
            | Ok Done -> Ok (List.rev rows)
            | Ok Row ->
                begin match event_row_of_statement statement with
                | Ok row -> loop (row :: rows)
                | Error _ as error -> error
                end
            | Error _ as error -> error
          in
          loop [])

  let event_read_stream database run_id =
    query_event_rows database
      {|SELECT run_id,sequence,event_id,event_digest,event_json
          FROM run_event WHERE run_id=?1 ORDER BY sequence ASC|}
      [ Bind_text run_id ]

  let event_conflicts database (conflict : event_conflict) =
    query_event_rows database
      {|SELECT run_id,sequence,event_id,event_digest,event_json
          FROM run_event
         WHERE run_id=?1 AND (event_id=?2 OR sequence=?3)
         ORDER BY sequence ASC,event_id ASC|}
      [ Bind_text conflict.conflict_run_id;
        Bind_text conflict.conflict_event_id;
        Bind_int64 conflict.conflict_sequence ]

  let event_insert database (row : event_row) =
    match
      statement database
        {|INSERT INTO run_event(run_id,sequence,event_id,event_digest,event_json)
            VALUES(?1,?2,?3,?4,?5)|}
        (fun statement ->
          match
            bind_values statement
              [ Bind_text row.run_id; Bind_int64 row.sequence;
                Bind_text row.event_id; Bind_text row.event_digest;
                Bind_text row.event_json ]
          with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () -> changed database 1

  let event_run_ids database limit =
    statement database
      {|SELECT run_id FROM run_event
          GROUP BY run_id
          ORDER BY MAX(sequence) DESC,run_id ASC
          LIMIT ?1|}
      (fun statement ->
        match bind_values statement [ Bind_int64 (Int64.of_int limit) ] with
        | Error _ as error -> error
        | Ok () ->
            let rec loop run_ids =
              match step statement with
              | Ok Done -> Ok (List.rev run_ids)
              | Ok Row ->
                  begin match text_column statement 0 with
                  | Ok (Some run_id) -> loop (run_id :: run_ids)
                  | Ok None -> Error (Operation_failed "run id is null")
                  | Error _ as error -> error
                  end
              | Error _ as error -> error
            in
            loop [])

  let initialize_unsupported_event_schema database =
    event_transaction database (fun () ->
      match drain_sql database event_marker_sql with
      | Error _ as error -> error
      | Ok () ->
          drain_sql database
            "INSERT INTO run_event_schema(version) VALUES(2)")

  let test_event_finalize_failure database =
    match
      drain_sql database
        "CREATE TEMP TABLE IF NOT EXISTS run_event_finalize_fault(value INTEGER UNIQUE)"
    with
    | Error _ as error -> error
    | Ok () ->
        begin match drain_sql database "DELETE FROM run_event_finalize_fault" with
        | Error _ as error -> error
        | Ok () ->
            begin match
              drain_sql database
                "INSERT INTO run_event_finalize_fault(value) VALUES(1)"
            with
            | Error _ as error -> error
            | Ok () ->
                drain_sql database
                  "INSERT INTO run_event_finalize_fault(value) VALUES(1)"
            end
        end

  let test_event_insert_malformed database run_id =
    match
      statement database
        {|INSERT INTO run_event(run_id,sequence,event_id,event_digest,event_json)
            VALUES(?1,0,'malformed-test-event','malformed','{broken')|}
        (fun statement ->
          match bind_values statement [ Bind_text run_id ] with
          | Error _ as error -> error
          | Ok () -> step_done statement)
    with
    | Error _ as error -> error
    | Ok () -> changed database 1

  let rejected_append_only database context sql =
    match drain_sql database sql with
    | Error _ -> Ok ()
    | Ok () -> Error (Operation_failed (context ^ " unexpectedly succeeded"))

  let test_event_append_only database =
    match validate_event_schema database with
    | Error _ as error -> error
    | Ok () ->
        begin match
          rejected_append_only database "append-only update guard"
            "UPDATE run_event SET event_json='{}' WHERE 1=1"
        with
        | Error _ as error -> error
        | Ok () ->
            rejected_append_only database "append-only delete guard"
              "DELETE FROM run_event WHERE 1=1"
        end

  let lifecycle_setup_finalize_failure database =
    match execute_sql database
      "CREATE TABLE close_failure(value INTEGER UNIQUE)" with
    | Error _ as error -> error
    | Ok () -> execute_sql database
        "INSERT INTO close_failure(value) VALUES (1)"

  let lifecycle_statement_composition database =
    let run sql = statement database sql (fun statement ->
      match step statement with Ok (Row | Done) -> Ok ()
      | Error _ -> Error (Operation_failed "step-operation-failed"))
    in
    match run "CREATE TABLE unique_values(value INTEGER UNIQUE)" with
    | Error _ as error -> error
    | Ok () -> begin match run "INSERT INTO unique_values(value) VALUES (1)" with
      | Error _ as error -> error
      | Ok () ->
          let escaped = ref None in
          let scoped = statement database "SELECT 1" (fun operation ->
            escaped := Some operation; Ok ()) in
          let scope_closed = match !escaped with
            | Some operation ->
                step_statement operation = Error Statement_scope_closed
            | None -> false
          in
          let finalize_only =
            with_statement database "INSERT INTO unique_values(value) VALUES (1)"
              (fun operation -> match step_statement operation with
                | Ok _ -> Ok () | Error _ -> Error "step-operation-failed")
          in
          let body_and_finalize =
            with_statement database "INSERT INTO unique_values(value) VALUES (1)"
              (fun operation -> match step_statement operation with
                | Ok _ -> Error "body-observed-constraint"
                | Error _ -> Error "step-operation-failed")
          in
          let composed = function Error (Body_and_finalize_failed _) -> true | _ -> false in
          begin match scoped with
          | Error _ as error -> error
          | Ok () -> Ok { lifecycle_scope_closed = scope_closed;
                          lifecycle_finalize_failure_composed = composed finalize_only;
                          lifecycle_body_and_finalize_failure_composed = composed body_and_finalize }
          end
      end

  let lifecycle_scoped_data_contract database input =
    match execute_sql database
      "CREATE TABLE ledger(key TEXT PRIMARY KEY, payload BLOB NOT NULL, wide INTEGER NOT NULL, small INTEGER NOT NULL, nullable TEXT)" with
    | Error _ as error -> error
    | Ok () ->
      let escaped = ref None in
      let before_row = ref false in
      let insert = statement database
        "INSERT INTO ledger(key,payload,wide,small,nullable) VALUES(?1,?2,?3,?4,?5)"
        (fun operation ->
          escaped := Some operation;
          match bind_values operation
            [ Bind_text input.lifecycle_literal_key;
              Bind_blob input.lifecycle_literal_blob;
              Bind_int64 input.lifecycle_literal_wide;
              Bind_int input.lifecycle_literal_small; Bind_null ] with
          | Error _ as error -> error
          | Ok () ->
              before_row := (match column_text operation ~column:0 with
                | Error (Statement_column_without_row 0) -> true | _ -> false);
              step_done operation)
      in
      begin match insert, changes database with
      | Error _ as error, _ -> error
      | _, Error error -> Error (Operation_failed (string_of_database_error error))
      | Ok (), Ok lifecycle_change_count ->
          let selected = statement database
            "SELECT key,payload,wide,small,nullable FROM ledger WHERE key=?1"
            (fun operation -> match bind_values operation
              [ Bind_text input.lifecycle_literal_key ] with
              | Error _ as error -> error
              | Ok () -> begin match step operation with
                | Error _ as error -> error | Ok Done -> Error (Operation_failed "row missing")
                | Ok Row -> begin match
                    text_column operation 0, column_blob operation ~column:1,
                    int64_column operation 2, int_column operation 3,
                    text_column operation 4, column_is_null operation ~column:4,
                    column_blob operation ~column:0 with
                  | Ok (Some key), Ok (Some blob), Ok (Some wide), Ok (Some small),
                    Ok None, Ok true, Error (Statement_column_type_mismatch _) ->
                      Ok (key, blob, wide, small, true)
                  | _ -> Error (Operation_failed "scoped column contract") end
                end)
          in
          let invalid = statement database "SELECT 1" (fun operation ->
            match step operation with
            | Ok Row -> begin match column_int64 operation ~column:9 with
              | Error (Statement_column_raised _) -> Ok true
              | _ -> Ok false end
            | Ok Done | Error _ -> Ok false)
          in
          begin match selected, invalid with
          | Ok (key, blob, wide, small, mismatch), Ok invalid_column ->
              let escaped_bind, escaped_column = match !escaped with
                | None -> false, false
                | Some operation ->
                    (bind_text operation ~index:1 "late" = Error Statement_scope_closed,
                     column_text operation ~column:0 = Error Statement_scope_closed)
              in
              Ok { lifecycle_selected_key = key; lifecycle_selected_blob = blob;
                   lifecycle_selected_wide = wide; lifecycle_selected_small = small;
                   lifecycle_change_count;
                   lifecycle_column_before_row_rejected = !before_row;
                   lifecycle_type_mismatch_rejected = mismatch;
                   lifecycle_invalid_column_rejected = invalid_column;
                   lifecycle_escaped_bind_rejected = escaped_bind;
                   lifecycle_escaped_column_rejected = escaped_column }
          | (Error _ as error), _ -> error
          | _, (Error _ as error) -> error
          end
      end

  let lifecycle_schema_rejection_contract _database =
    let injection = schema_statement
      "CREATE TABLE injected(value TEXT); DROP TABLE injected" in
    let dml = schema_statement "INSERT INTO ledger(key) VALUES ('not-schema')" in
    Ok (match injection, dml with
      | Error (Invalid_schema_statement _), Error (Invalid_schema_statement _) -> true
      | _ -> false)

  let lifecycle_transaction_initialize database =
    execute_sql database "CREATE TABLE tx_values(value TEXT NOT NULL)"

  let lifecycle_transaction_insert database value =
    statement database "INSERT INTO tx_values(value) VALUES(?1)"
      (fun operation -> match bind_values operation [ Bind_text value ] with
        | Error _ as error -> error | Ok () -> step_done operation)

  let lifecycle_transaction_count database =
    statement database "SELECT COUNT(*) FROM tx_values" (fun operation ->
      match step operation with
      | Error _ as error -> error | Ok Done -> Error (Operation_failed "count missing")
      | Ok Row -> begin match int_column operation 0 with
        | Ok (Some count) -> Ok count
        | Ok None -> Error (Operation_failed "count is null")
        | Error _ as error -> error end)

  let lifecycle_live_statement_observation database generation =
    statement database "SELECT 1" (fun _ ->
      let lifecycle_live_count = live_statement_count database in
      let lifecycle_quiescence_refused =
        match observe_internal_quiescence generation ~epoch:1
          ~active_handlers:0 ~queued_requests:0 with
        | Error (Invalid_quiescence_witness _) -> true | _ -> false
      in
      Ok { lifecycle_live_count; lifecycle_quiescence_refused })

  let execute_operation : type a. owned_database -> a t -> (a, error) result =
    fun database operation ->
      match operation with
      | Authority_store_initialize_v1 -> initialize_authority_store database
      | Authority_store_insert_initial_owner owner ->
          insert_authority_initial_owner database owner
      | Authority_store_read_pointer key -> read_authority_pointer database key
      | Authority_store_read_transition lookup ->
          read_authority_transition database lookup
      | Authority_store_insert_transition row ->
          insert_authority_transition database row
      | Authority_store_insert_pointer key -> insert_authority_pointer database key
      | Authority_store_read_campaign key -> read_authority_campaign database key
      | Authority_store_read_nonces key -> read_authority_nonces database key
      | Authority_store_insert_campaign row ->
          insert_authority_campaign database row
      | Authority_store_insert_nonce row -> insert_authority_nonce database row
      | Authority_store_read_current_nonce lookup ->
          read_authority_current_nonce database lookup
      | Authority_store_pointer_cas cas -> cas_authority_pointer database cas
      | Authority_store_inventory_ids -> authority_inventory_ids database
      | Authority_store_insert_owner_transition row ->
          insert_authority_owner_transition database row
      | Authority_store_owner_pointer_cas cas ->
          cas_authority_owner_pointer database cas
      | Completion_initialize_v1 -> initialize_completion database
      | Completion_record (receipt, observation) ->
          record_completion database receipt observation
      | Completion_append_interaction interaction ->
          append_interaction database interaction
      | Completion_counts -> completion_counts database
      | Completion_receipt_current (source, receipt_digest) ->
          receipt_current database source receipt_digest
      | Completion_has_current_success (source, action, scope) ->
          has_current_success database source action scope
      | Completion_store_initialize_v1 -> initialize_completion_store database
      | Completion_store_insert_owner owner ->
          insert_completion_store_owner database owner
      | Completion_store_read completion_id ->
          read_completion_store database completion_id
      | Completion_store_insert_reservation row ->
          insert_completion_reservation database row
      | Completion_store_mark_conflict conflict ->
          completion_store_mark_conflict database conflict
      | Completion_store_finalize finalize ->
          finalize_completion_store database finalize
      | Completion_store_all_rows -> all_completion_store_rows database
      | Completion_store_owner_cas cas ->
          completion_store_owner_cas database cas
      | Dispatch_store_initialize_v1 -> initialize_dispatch_store database
      | Dispatch_store_insert_initial_owner owner ->
          insert_dispatch_initial_owner database owner
      | Dispatch_store_read_pointer key -> read_dispatch_pointer database key
      | Dispatch_store_read_transition lookup ->
          read_dispatch_transition database lookup
      | Dispatch_store_read_decision key -> read_dispatch_decision database key
      | Dispatch_store_insert_transition row ->
          insert_dispatch_transition database row
      | Dispatch_store_insert_pointer pointer ->
          insert_dispatch_pointer database pointer
      | Dispatch_store_insert_decision row ->
          insert_dispatch_decision database row
      | Dispatch_store_pointer_cas cas -> cas_dispatch_pointer database cas
      | Dispatch_store_read_abandonment key ->
          read_dispatch_abandonment database key
      | Dispatch_store_inventory_ids -> dispatch_inventory_ids database
      | Dispatch_store_owner_transition transition ->
          dispatch_owner_transition database transition
      | Effect_initialize_v1 -> initialize_effect database
      | Effect_read idempotency_key -> effect_read database idempotency_key
      | Effect_insert_pending row -> insert_effect_pending database row
      | Effect_cas_pending cas -> cas_effect_pending database cas
      | Event_configure -> configure_event database
      | Event_verify_configuration -> verify_event_configuration database
      | Event_initialize_v1 -> initialize_event database
      | Event_read_stream run_id -> event_read_stream database run_id
      | Event_conflicts conflict -> event_conflicts database conflict
      | Event_insert row -> event_insert database row
      | Event_run_ids limit -> event_run_ids database limit
      | Event_test_initialize_unsupported_schema ->
          initialize_unsupported_event_schema database
      | Event_test_finalize_failure -> test_event_finalize_failure database
      | Event_test_insert_malformed run_id ->
          test_event_insert_malformed database run_id
      | Event_test_verify_append_only -> test_event_append_only database
      | Lifecycle_observe_changes ->
          begin match changes database with
          | Ok count -> Ok count
          | Error error -> Error (Operation_failed (string_of_database_error error))
          end
      | Lifecycle_setup_finalize_failure ->
          lifecycle_setup_finalize_failure database
      | Lifecycle_statement_composition ->
          lifecycle_statement_composition database
      | Lifecycle_scoped_data_contract input ->
          lifecycle_scoped_data_contract database input
      | Lifecycle_schema_rejection_contract ->
          lifecycle_schema_rejection_contract database
      | Lifecycle_transaction_initialize ->
          lifecycle_transaction_initialize database
      | Lifecycle_transaction_insert value ->
          lifecycle_transaction_insert database value
      | Lifecycle_transaction_count -> lifecycle_transaction_count database
      | Lifecycle_live_statement_observation generation ->
          lifecycle_live_statement_observation database generation

  let execute_in scope operation =
    if not (Atomic.get scope.scope_active) then Error Transaction_scope_closed
    else if scope.scope_mode = Read_only && operation_is_write operation then
      Error Write_in_read_only_scope
    else
      let family = operation_family operation in
      match claim_family scope.scope_database family with
      | Error _ as error -> error
      | Ok () -> execute_operation scope.scope_database operation

  let with_transaction database ~mode body =
    let scope =
      { scope_database = database; scope_mode = mode;
        scope_active = Atomic.make true }
    in
    let result =
      match with_transaction database (fun _ -> body scope) with
      | Ok value -> Ok value
      | Error (Transaction_body_failed error) -> Error error
      | Error error ->
          Error (Operation_failed (string_of_transaction_error string_of_error error))
    in
    Atomic.set scope.scope_active false;
    result

  let operation_owns_scope : type a. a t -> bool = function
    | Event_configure
    | Event_initialize_v1
    | Event_test_initialize_unsupported_schema
    | Event_test_finalize_failure -> true
    | Lifecycle_setup_finalize_failure
    | Lifecycle_statement_composition
    | Lifecycle_scoped_data_contract _
    | Lifecycle_schema_rejection_contract
    | Lifecycle_live_statement_observation _ -> true
    | Authority_store_initialize_v1
    | Authority_store_insert_initial_owner _
    | Authority_store_read_pointer _
    | Authority_store_read_transition _
    | Authority_store_insert_transition _
    | Authority_store_insert_pointer _
    | Authority_store_read_campaign _
    | Authority_store_read_nonces _
    | Authority_store_insert_campaign _
    | Authority_store_insert_nonce _
    | Authority_store_read_current_nonce _
    | Authority_store_pointer_cas _
    | Authority_store_inventory_ids
    | Authority_store_insert_owner_transition _
    | Authority_store_owner_pointer_cas _
    | Completion_initialize_v1
    | Completion_record _
    | Completion_append_interaction _
    | Completion_counts
    | Completion_receipt_current _
    | Completion_has_current_success _
    | Completion_store_initialize_v1
    | Completion_store_insert_owner _
    | Completion_store_read _
    | Completion_store_insert_reservation _
    | Completion_store_mark_conflict _
    | Completion_store_finalize _
    | Completion_store_all_rows
    | Completion_store_owner_cas _
    | Dispatch_store_initialize_v1
    | Dispatch_store_insert_initial_owner _
    | Dispatch_store_read_pointer _
    | Dispatch_store_read_transition _
    | Dispatch_store_read_decision _
    | Dispatch_store_insert_transition _
    | Dispatch_store_insert_pointer _
    | Dispatch_store_insert_decision _
    | Dispatch_store_pointer_cas _
    | Dispatch_store_read_abandonment _
    | Dispatch_store_inventory_ids
    | Dispatch_store_owner_transition _
    | Effect_initialize_v1
    | Effect_read _
    | Effect_insert_pending _
    | Effect_cas_pending _
    | Event_verify_configuration
    | Event_read_stream _
    | Event_conflicts _
    | Event_insert _
    | Event_run_ids _
    | Event_test_insert_malformed _
    | Event_test_verify_append_only
    | Lifecycle_observe_changes
    | Lifecycle_transaction_initialize
    | Lifecycle_transaction_insert _
    | Lifecycle_transaction_count -> false

  let execute database operation =
    if operation_owns_scope operation then
      let family = operation_family operation in
      match claim_family database family with
      | Error _ as error -> error
      | Ok () -> execute_operation database operation
    else
      let mode = if operation_is_write operation then Read_write else Read_only in
      with_transaction database ~mode (fun scope -> execute_in scope operation)

  let operation_ids =
    [ "authority-store-initialize-v1";
      "authority-store-insert-initial-owner";
      "authority-store-read-pointer";
      "authority-store-read-transition";
      "authority-store-insert-transition";
      "authority-store-insert-pointer";
      "authority-store-read-campaign";
      "authority-store-read-nonces";
      "authority-store-insert-campaign";
      "authority-store-insert-nonce";
      "authority-store-read-current-nonce";
      "authority-store-pointer-cas";
      "authority-store-inventory-ids";
      "authority-store-insert-owner-transition";
      "authority-store-owner-pointer-cas";
      "completion-initialize-v1"; "completion-record";
      "completion-append-interaction"; "completion-counts";
      "completion-receipt-current"; "completion-has-current-success";
      "completion-store-initialize-v1"; "completion-store-insert-owner";
      "completion-store-read"; "completion-store-insert-reservation";
      "completion-store-mark-conflict"; "completion-store-finalize";
      "completion-store-all-rows"; "completion-store-owner-cas";
      "dispatch-store-initialize-v1"; "dispatch-store-insert-initial-owner";
      "dispatch-store-read-pointer"; "dispatch-store-read-transition";
      "dispatch-store-read-decision"; "dispatch-store-insert-transition";
      "dispatch-store-insert-pointer"; "dispatch-store-insert-decision";
      "dispatch-store-pointer-cas"; "dispatch-store-read-abandonment";
      "dispatch-store-inventory-ids"; "dispatch-store-owner-transition";
      "effect-initialize-v1"; "effect-read"; "effect-insert-pending";
      "effect-cas-pending";
      "event-configure"; "event-verify-configuration";
      "event-initialize-v1"; "event-read-stream"; "event-conflicts";
      "event-insert"; "event-run-ids";
      "event-test-initialize-unsupported-schema";
      "event-test-finalize-failure"; "event-test-insert-malformed";
      "event-test-verify-append-only";
      "lifecycle-observe-changes";
      "lifecycle-setup-finalize-failure";
      "lifecycle-statement-composition";
      "lifecycle-scoped-data-contract";
      "lifecycle-schema-rejection-contract";
      "lifecycle-transaction-initialize";
      "lifecycle-transaction-insert";
      "lifecycle-transaction-count";
      "lifecycle-live-statement-observation" ]

  let frame value = string_of_int (String.length value) ^ ":" ^ value

  let digest_for ids =
    ("dependability-sqlite-closed-operation-v1" :: ids)
    |> List.map frame
    |> String.concat "|"
    |> Digestif.SHA256.digest_string
    |> Digestif.SHA256.to_hex

  let source_digest = digest_for operation_ids

  module For_test = struct
    type mutation =
      | Drop_completion_counts
      | Drop_effect_cas_pending
      | Drop_event_insert
      | Drop_completion_store_owner_cas
      | Drop_dispatch_store_pointer_cas
      | Drop_authority_store_pointer_cas

    let source_digest_with_mutation = function
      | Drop_completion_counts ->
          digest_for
            (List.filter
               (fun id -> not (String.equal id "completion-counts"))
               operation_ids)
      | Drop_effect_cas_pending ->
          digest_for
            (List.filter
               (fun id -> not (String.equal id "effect-cas-pending"))
               operation_ids)
      | Drop_event_insert ->
          digest_for
            (List.filter
               (fun id -> not (String.equal id "event-insert"))
               operation_ids)
      | Drop_completion_store_owner_cas ->
          digest_for
            (List.filter
               (fun id ->
                 not (String.equal id "completion-store-owner-cas"))
               operation_ids)
      | Drop_dispatch_store_pointer_cas ->
          digest_for
            (List.filter
               (fun id -> not (String.equal id "dispatch-store-pointer-cas"))
               operation_ids)
      | Drop_authority_store_pointer_cas ->
          digest_for
            (List.filter
               (fun id -> not (String.equal id "authority-store-pointer-cas"))
               operation_ids)
  end
end

type native_close = Native_closed | Native_busy | Native_close_exception of string

let close_once database =
  match Sqlite3.db_close database.native with
  | closed ->
      ignore (Sys.opaque_identity database.native);
      if closed then Native_closed else Native_busy
  | exception exn ->
      ignore (Sys.opaque_identity database.native);
      Native_close_exception (Printexc.to_string exn)

let close_with ~(generation : close_generation)
    ~(witness : quiescence_witness) native_attempt =
  let database = generation.database in
  if database.state <> Database_open then
    Error (Database_already_released, generation)
  else if generation.id <> database.active_generation then
    Error
      ( Superseded_close_generation
          { observed = generation.id; active = database.active_generation },
        generation )
  else if not database.generation_open || generation.attempts <> 0 then
    Error (Terminal_close_generation generation.id, generation)
  else if witness.generation != generation then
    Error
      ( Wrong_close_generation
          { observed = witness.generation.id; expected = generation.id },
        generation )
  else if witness.epoch <= database.last_consumed_quiescence_epoch then
    Error
      ( Invalid_quiescence_witness
          (Printf.sprintf
             "epoch=%d is not newer than lifetime-consumed epoch=%d"
             witness.epoch database.last_consumed_quiescence_epoch),
        generation )
  else if database.transaction_status <> Transaction_idle then
    Error
      ( Invalid_quiescence_witness
          (match database.transaction_status with
           | Transaction_active -> "transaction became active"
           | Transaction_indeterminate ->
               "transaction state became indeterminate"
           | Transaction_idle -> assert false),
        generation )
  else if Atomic.get database.finalize_active <> 0 then
    Error
      (Invalid_quiescence_witness "statement finalization became active",
       generation)
  else if witness.activity_revision <> database.activity_revision then
    Error
      ( Invalid_quiescence_witness
          (Printf.sprintf "activity revision changed from %d to %d"
             witness.activity_revision database.activity_revision),
        generation )
  else if witness.live_statements <> 0 || database.live_statements <> 0 then
    Error
      (Invalid_quiescence_witness "live statements changed after observation",
       generation)
  else if witness.active_handlers <> 0 || witness.queued_requests <> 0 then
    Error
      (Invalid_quiescence_witness "non-quiescent witness fields", generation)
  else if database.total_attempts >= database.maximum_total_attempts then
    Error
      ( Lifetime_close_budget_exhausted
          { attempts = database.total_attempts;
            maximum = database.maximum_total_attempts },
        generation )
  else begin
    (* Consume authority before the foreign call.  Every alias observes the
       monotone mutation and this generation becomes terminal on every result. *)
    generation.attempts <- 1;
    database.total_attempts <- database.total_attempts + 1;
    database.last_consumed_quiescence_epoch <- witness.epoch;
    database.generation_open <- false;
    match native_attempt database with
    | Native_closed ->
        database.state <-
          if database.live_statements = 0 then Database_released
          else Database_close_v2_deferred;
        Ok generation
    | Native_close_exception message ->
        Error (Database_close_raised message, generation)
    | Native_busy
      when database.total_attempts >= database.maximum_total_attempts ->
        Error
          ( Lifetime_close_budget_exhausted
              { attempts = database.total_attempts;
                maximum = database.maximum_total_attempts },
            generation )
    | Native_busy ->
        Error
          ( Database_busy
              { attempts = generation.attempts;
                remaining = remaining_total_close_attempts database },
            generation )
  end

let close_database ~generation ~witness =
  let database = generation.database in
  let close_attempt =
    match database.close_behavior with
    | Native_close -> close_once
    | Inject_close_failure ->
        (fun _ -> Native_close_exception "injected registered-location close failure")
    | Inject_busy_once consumed ->
        (fun database ->
          if Atomic.compare_and_set consumed false true then Native_busy
          else close_once database)
  in
  let result = close_with ~generation ~witness close_attempt in
  if database.state = Database_released then database.cleanup_after_release ();
  result

module For_test = struct
  type retained_statement = {
    retained_native : Sqlite3.stmt;
    retained_owner : owned_database;
    retained_identity : int;
    mutable retained_consumed : bool;
  }

  type transaction_fault =
    | Fail_transaction_begin
    | Fail_transaction_commit
    | Fail_transaction_rollback
    | Fail_transaction_commit_and_rollback

  type retained_statement_kind =
    | Retain_select_one
    | Retain_select_two
    | Retain_duplicate_failure

  let prepare database kind =
    let sql = match kind with
      | Retain_select_one -> "SELECT 1"
      | Retain_select_two -> "SELECT 2"
      | Retain_duplicate_failure ->
          "INSERT INTO close_failure(value) VALUES (1)"
    in
    match prepare_native database sql with
    | Error _ as error -> error
    | Ok (retained_native, retained_identity) ->
        Ok
          { retained_native; retained_owner = database; retained_identity;
            retained_consumed = false }

  let step statement =
    if statement.retained_consumed then Error Statement_scope_closed
    else match Sqlite3.step statement.retained_native with
    | rc ->
        statement.retained_owner.activity_revision <-
          statement.retained_owner.activity_revision + 1;
        step_outcome_of_rc rc
    | exception exn -> Error (Statement_step_raised (Printexc.to_string exn))

  let finalize database statement =
    if statement.retained_owner != database then Error Finalize_wrong_database
    else if statement.retained_consumed then Error Finalize_already_consumed
    else begin
      statement.retained_consumed <- true;
      finalize_owned_statement database
        ~statement_identity:statement.retained_identity
        statement.retained_native
    end

  let native_close_probe database =
    if database.state <> Database_open then Error "database handle is not open"
    else
      match close_once database with
      | Native_busy -> Ok Native_close_reported_busy
      | Native_close_exception message -> Error message
      | Native_closed when database.live_statements = 0 ->
          database.state <- Database_released;
          database.generation_open <- false;
          database.cleanup_after_release ();
          Ok Native_close_immediate
      | Native_closed ->
          database.state <- Database_close_v2_deferred;
          database.generation_open <- false;
          Ok Native_close_v2_deferred

  let close_as_busy ~generation ~witness =
    close_with ~generation ~witness (fun _ -> Native_busy)

  let with_transaction_fault fault database body =
    let injection =
      match fault with
      | Fail_transaction_begin -> Inject_transaction_begin_failure
      | Fail_transaction_commit -> Inject_transaction_commit_failure
      | Fail_transaction_rollback -> Inject_transaction_rollback_failure
      | Fail_transaction_commit_and_rollback ->
          Inject_transaction_commit_and_rollback_failure
    in
    let scope : Closed_operation.transaction_scope =
      { scope_database = database; scope_mode = Closed_operation.Read_write;
        scope_active = Atomic.make true }
    in
    let result =
      with_transaction_internal injection database (fun _ -> body scope)
    in
    Atomic.set scope.scope_active false;
    result

  let dispose database =
    match database.state with
    | Database_released -> true
    | Database_close_v2_deferred -> false
    | Database_open ->
        match close_once database with
        | Native_closed ->
            database.state <- Database_released;
            database.generation_open <- false;
            database.cleanup_after_release ();
            true
        | Native_busy | Native_close_exception _ -> false
end
