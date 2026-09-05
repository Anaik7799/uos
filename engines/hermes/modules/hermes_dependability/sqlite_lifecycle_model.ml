type wrapper_reachability = Live | Collectible
type native_statement = Prepared | Finalizing | Finalized
type runtime_ownership = Held | Released_for_finalize
type finalize_outcome = Not_finished | Finalize_succeeded | Finalize_failed_reported

type statement_state = {
  wrapper : wrapper_reachability;
  native : native_statement;
  runtime : runtime_ownership;
  explicit_finalize_count : int;
  custom_finalize_count : int;
  outcome : finalize_outcome;
}

type statement_event =
  | Begin_explicit_finalize
  | Explicit_finalize_succeeded
  | Explicit_finalize_failed
  | Become_collectible
  | Begin_custom_finalize
  | Custom_finalize_returned

type close_v2_release =
  | Close_v2_handle_open
  | Close_v2_deferred_release
  | Close_v2_physical_release

type close_v2_state = {
  close_v2_release : close_v2_release;
  retained_statements : int;
  close_authority_terminal : bool;
  native_close_calls : int;
  finalize_failure_observed : bool;
  finalize_failure_reported : bool;
}

type close_v2_event =
  | Retain_statement
  | Accept_close_v2
  | Finalize_retained_succeeded
  | Finalize_retained_failed
  | Retry_close_v2

type actor_lifecycle = Open | Closing | Closed | Failed
type database_ownership = Owned_open | Owned_busy | Released
type writer_state = Not_spawned | Running | Joined
type stop_acknowledgement = No_ack | Success_ack | Failure_ack of string

type cleanup_origin =
  | No_cleanup
  | Configure_cleanup
  | Schema_cleanup
  | Spawn_cleanup
  | Enqueue_cleanup
  | Failure_drain_cleanup
  | Close_busy_cleanup

type cleanup_owner =
  | No_cleanup_owner
  | Opening_domain_owner
  | Writer_generation_owner of int

type quiescence_freshness =
  | No_quiescence_receipt
  | Strictly_newer_quiescence
  | Stale_or_older_quiescence

type actor_state = {
  lifecycle : actor_lifecycle;
  database : database_ownership;
  writer : writer_state;
  acknowledgement : stop_acknowledgement;
  close_attempts : int;
  remaining_global_budget : int;
  remaining_generation_budget : int;
  close_owner_count : int;
  elected_generation : int;
  generation_quiescence_epoch : int;
  generation_quiescence_freshness : quiescence_freshness;
  quiescence_epoch : int;
  authorized_quiescence_epoch : int;
  terminal_generation_receipt : int;
  writer_terminal_receipt : stop_acknowledgement;
  writer_terminal : bool;
  external_join_observed : bool;
  followers_waiting : int;
  followers_receipted : int;
  follower_acknowledgement : stop_acknowledgement;
  admitted : int;
  current : int;
  queued : int;
  results : int;
  late_admissions : int;
  retry_budget_resets : int;
  cleanup_obligation : cleanup_origin;
  cleanup_owner : cleanup_owner;
}

type actor_event =
  | Spawn_writer
  | Configure_failed_released
  | Configure_failed_retained
  | Schema_failed_released
  | Schema_failed_retained
  | Spawn_failed
  | Post_spawn_failed_released
  | Post_spawn_failed_retained
  | Enqueue_request
  | Enqueue_failed_released
  | Enqueue_failed_retained
  | Start_request
  | Complete_request
  | Fail_request
  | Failure_drain_failed_released
  | Failure_drain_failed_retained
  | Observe_quiescence
  | Authorize_close
  | Elect_close_owner
  | Observe_competing_close
  | Close_reported_busy
  | Close_succeeded
  | Join_writer

type law_result = {
  id : string;
  premise_reachable : bool;
  premise_witness : string option;
  holds : bool;
  counterexample : string option;
}

type mutant_result = {
  id : string;
  premise_reachable : bool;
  premise_witness : string option;
  killed : bool;
  witness : string option;
}

type report = {
  statement_states : int;
  close_v2_states : int;
  actor_states : int;
  healthy_statement_trace : bool;
  healthy_close_v2_trace : bool;
  healthy_close_trace : bool;
  laws : law_result list;
  mutants : mutant_result list;
}

type solver_answer = Sat | Unsat
type verdict = Proved | Refuted of string | Unavailable of string
type obligation_kind =
  | Theorem_negation
  | Premise_control
  | Healthy_control
  | Mutant_witness

type obligation = {
  id : string;
  kind : obligation_kind;
  expected : solver_answer;
}

type relation_metric = {
  relation_id : string;
  relation_states : int;
  relation_edges : int;
  relation_path_bound : int;
}

type smt_metrics = {
  script_bytes : int;
  path_assertions : int;
  obligation_count : int;
  relations : relation_metric list;
}

type smt_batch = {
  batch_id : string;
  batch_digest : string;
  batch_obligations : obligation list;
  batch_script : string;
  batch_relation : relation_metric;
}

exception Smt_script_limit_exceeded of int * int

let initial_statement =
  { wrapper = Live; native = Prepared; runtime = Held;
    explicit_finalize_count = 0; custom_finalize_count = 0;
    outcome = Not_finished }

let statement_events =
  [ Begin_explicit_finalize; Explicit_finalize_succeeded;
    Explicit_finalize_failed; Become_collectible; Begin_custom_finalize;
    Custom_finalize_returned ]

let statement_step state event =
  match event, state.wrapper, state.native, state.runtime with
  | Begin_explicit_finalize, Live, Prepared, Held ->
      Some
        { state with native = Finalizing; runtime = Released_for_finalize;
          explicit_finalize_count = state.explicit_finalize_count + 1 }
  | Explicit_finalize_succeeded, Live, Finalizing, Released_for_finalize
    when state.explicit_finalize_count = 1 && state.custom_finalize_count = 0 ->
      Some
        { state with native = Finalized; runtime = Held;
          outcome = Finalize_succeeded }
  | Explicit_finalize_failed, Live, Finalizing, Released_for_finalize
    when state.explicit_finalize_count = 1 && state.custom_finalize_count = 0 ->
      Some
        { state with native = Finalized; runtime = Held;
          outcome = Finalize_failed_reported }
  | Become_collectible, Live, Prepared, Held ->
      Some { state with wrapper = Collectible }
  | Begin_custom_finalize, Collectible, Prepared, Held ->
      Some
        { state with native = Finalizing; runtime = Released_for_finalize;
          custom_finalize_count = state.custom_finalize_count + 1 }
  | Custom_finalize_returned, Collectible, Finalizing, Released_for_finalize
    when state.explicit_finalize_count = 0 && state.custom_finalize_count = 1 ->
      Some
        { state with native = Finalized; runtime = Held;
          outcome = Finalize_succeeded }
  | ( Begin_explicit_finalize | Explicit_finalize_succeeded
    | Explicit_finalize_failed | Become_collectible | Begin_custom_finalize
    | Custom_finalize_returned ), _, _, _ -> None

let initial_close_v2 =
  { close_v2_release = Close_v2_handle_open; retained_statements = 0;
    close_authority_terminal = false; native_close_calls = 0;
    finalize_failure_observed = false; finalize_failure_reported = false }

let close_v2_events =
  [ Retain_statement; Accept_close_v2; Finalize_retained_succeeded;
    Finalize_retained_failed; Retry_close_v2 ]

let close_v2_step state event =
  match event, state.close_v2_release with
  | Retain_statement, Close_v2_handle_open
    when state.retained_statements = 0 && not state.close_authority_terminal ->
      Some { state with retained_statements = 1 }
  | Accept_close_v2, Close_v2_handle_open
    when not state.close_authority_terminal && state.native_close_calls = 0 ->
      Some
        { state with
          close_v2_release =
            (if state.retained_statements = 0 then Close_v2_physical_release
             else Close_v2_deferred_release);
          close_authority_terminal = true; native_close_calls = 1 }
  | Finalize_retained_succeeded, Close_v2_deferred_release
    when state.retained_statements = 1 && state.close_authority_terminal ->
      Some
        { state with close_v2_release = Close_v2_physical_release;
          retained_statements = 0 }
  | Finalize_retained_failed, Close_v2_deferred_release
    when state.retained_statements = 1 && state.close_authority_terminal ->
      Some
        { state with retained_statements = 0;
          finalize_failure_observed = true;
          finalize_failure_reported = true }
  | ( Retain_statement | Accept_close_v2 | Finalize_retained_succeeded
    | Finalize_retained_failed | Retry_close_v2 ), _ -> None

let initial_actor =
  { lifecycle = Open; database = Owned_open; writer = Not_spawned;
    acknowledgement = No_ack; close_attempts = 0; close_owner_count = 0;
    remaining_global_budget = 3; remaining_generation_budget = 0;
    elected_generation = 0; generation_quiescence_epoch = 0;
    generation_quiescence_freshness = No_quiescence_receipt;
    quiescence_epoch = 0; authorized_quiescence_epoch = 0;
    terminal_generation_receipt = 0; writer_terminal_receipt = No_ack;
    writer_terminal = false; external_join_observed = false;
    followers_waiting = 0; followers_receipted = 0;
    follower_acknowledgement = No_ack;
    admitted = 0; current = 0; queued = 0; results = 0;
    late_admissions = 0; retry_budget_resets = 0;
    cleanup_obligation = No_cleanup; cleanup_owner = No_cleanup_owner }

let actor_events =
  [ Spawn_writer; Configure_failed_released; Configure_failed_retained;
    Schema_failed_released; Schema_failed_retained; Spawn_failed;
    Post_spawn_failed_released; Post_spawn_failed_retained; Enqueue_request;
    Enqueue_failed_released; Enqueue_failed_retained; Start_request;
    Complete_request; Fail_request; Failure_drain_failed_released;
    Failure_drain_failed_retained; Observe_quiescence; Authorize_close;
    Elect_close_owner;
    Observe_competing_close; Close_reported_busy; Close_succeeded;
    Join_writer ]

let named_failure origin =
  let label =
    match origin with
    | No_cleanup -> "unspecified-cleanup"
    | Configure_cleanup -> "configure-cleanup"
    | Schema_cleanup -> "schema-cleanup"
    | Spawn_cleanup -> "spawn-cleanup"
    | Enqueue_cleanup -> "enqueue-cleanup"
    | Failure_drain_cleanup -> "failure-drain-cleanup"
    | Close_busy_cleanup -> "database-close-busy"
  in
  Failure_ack label

let fail_released state origin writer =
  let failure = named_failure origin in
  { state with lifecycle = Failed; database = Released; writer;
    acknowledgement = failure; cleanup_obligation = No_cleanup;
    cleanup_owner = No_cleanup_owner;
    terminal_generation_receipt =
      if state.lifecycle = Closing then state.elected_generation
      else state.terminal_generation_receipt;
    followers_receipted =
      if state.lifecycle = Closing then state.followers_waiting
      else state.followers_receipted;
    follower_acknowledgement =
      if state.lifecycle = Closing && state.followers_waiting > 0 then failure
      else state.follower_acknowledgement }

let fail_retained state origin owner =
  let failure = named_failure origin in
  { state with lifecycle = Failed; database = Owned_busy;
    acknowledgement = failure; cleanup_obligation = origin;
    cleanup_owner = owner;
    terminal_generation_receipt =
      if state.lifecycle = Closing then state.elected_generation
      else state.terminal_generation_receipt;
    followers_receipted =
      if state.lifecycle = Closing then state.followers_waiting
      else state.followers_receipted;
    follower_acknowledgement =
      if state.lifecycle = Closing && state.followers_waiting > 0 then failure
      else state.follower_acknowledgement }

let actor_step state event =
  match event, state.lifecycle, state.writer with
  | Spawn_writer, Open, Not_spawned -> Some { state with writer = Running }
  | Configure_failed_released, Open, Not_spawned ->
      Some (fail_released state Configure_cleanup Not_spawned)
  | Configure_failed_retained, Open, Not_spawned ->
      Some (fail_retained state Configure_cleanup Opening_domain_owner)
  | Schema_failed_released, Open, Not_spawned ->
      Some (fail_released state Schema_cleanup Not_spawned)
  | Schema_failed_retained, Open, Not_spawned ->
      Some (fail_retained state Schema_cleanup Opening_domain_owner)
  | Spawn_failed, Open, Not_spawned ->
      Some (fail_released state Spawn_cleanup Not_spawned)
  | Post_spawn_failed_released, Open, Running ->
      Some (fail_released state Spawn_cleanup Joined)
  | Post_spawn_failed_retained, Open, Running ->
      Some
        (fail_retained { state with writer = Running } Spawn_cleanup
           (Writer_generation_owner (max 1 state.elected_generation)))
  | Enqueue_request, Open, Running when state.admitted < 1 ->
      Some
        { state with admitted = state.admitted + 1;
          queued = state.queued + 1; authorized_quiescence_epoch = 0 }
  | Enqueue_failed_released, Open, Running ->
      Some (fail_released state Enqueue_cleanup Joined)
  | Enqueue_failed_retained, Open, Running ->
      Some
        (fail_retained state Enqueue_cleanup
           (Writer_generation_owner (max 1 state.elected_generation)))
  | Start_request, (Open | Closing), Running when state.queued > 0 ->
      Some { state with queued = state.queued - 1; current = state.current + 1 }
  | (Complete_request | Fail_request), (Open | Closing), Running
    when state.current > 0 ->
      Some { state with current = state.current - 1; results = state.results + 1 }
  | Failure_drain_failed_released, (Open | Closing), Running ->
      Some (fail_released state Failure_drain_cleanup Joined)
  | Failure_drain_failed_retained, (Open | Closing), Running ->
      Some
        (fail_retained state Failure_drain_cleanup
           (Writer_generation_owner (max 1 state.elected_generation)))
  | Observe_quiescence, (Open | Failed), Running
    when state.current = 0 && state.queued = 0 && state.quiescence_epoch < 3 ->
      Some
        { state with quiescence_epoch = state.quiescence_epoch + 1;
          authorized_quiescence_epoch = 0 }
  | Authorize_close, (Open | Failed), Running
    when state.current = 0 && state.queued = 0 && state.quiescence_epoch > 0
         && state.authorized_quiescence_epoch = 0 ->
      Some { state with authorized_quiescence_epoch = state.quiescence_epoch }
  | Elect_close_owner, Open, Running
    when state.authorized_quiescence_epoch = state.quiescence_epoch
         && state.quiescence_epoch > 0 && state.remaining_global_budget > 0 ->
      Some
        { state with lifecycle = Closing; close_owner_count = 1;
          elected_generation = state.elected_generation + 1;
          generation_quiescence_freshness = Strictly_newer_quiescence;
          generation_quiescence_epoch = state.quiescence_epoch;
          remaining_generation_budget = 1;
          terminal_generation_receipt = 0; acknowledgement = No_ack;
          writer_terminal_receipt = No_ack; writer_terminal = false;
          external_join_observed = false; followers_waiting = 0;
          followers_receipted = 0; follower_acknowledgement = No_ack;
          cleanup_obligation = No_cleanup; cleanup_owner = No_cleanup_owner }
  | Elect_close_owner, Failed, Running
    when state.cleanup_owner <> No_cleanup_owner
         && state.authorized_quiescence_epoch = state.quiescence_epoch
         && state.quiescence_epoch > state.generation_quiescence_epoch
         && state.remaining_global_budget > 0 ->
      Some
        { state with lifecycle = Closing; close_owner_count = 1;
          elected_generation = state.elected_generation + 1;
          generation_quiescence_freshness = Strictly_newer_quiescence;
          generation_quiescence_epoch = state.quiescence_epoch;
          remaining_generation_budget = 1;
          terminal_generation_receipt = 0; acknowledgement = No_ack;
          writer_terminal_receipt = No_ack; writer_terminal = false;
          external_join_observed = false; followers_waiting = 0;
          followers_receipted = 0; follower_acknowledgement = No_ack;
          cleanup_obligation = No_cleanup; cleanup_owner = No_cleanup_owner }
  | Observe_competing_close, Closing, Running when state.followers_waiting < 1 ->
      Some { state with followers_waiting = state.followers_waiting + 1 }
  | Close_reported_busy, Closing, Running
    when state.current = 0 && state.queued = 0
         && state.database <> Released
         && state.authorized_quiescence_epoch = state.generation_quiescence_epoch
         && state.remaining_generation_budget = 1
         && state.remaining_global_budget > 0 ->
      let failure = named_failure Close_busy_cleanup in
      Some
        { state with lifecycle = Failed; database = Owned_busy;
          close_attempts = state.close_attempts + 1;
          remaining_generation_budget = 0;
          remaining_global_budget = state.remaining_global_budget - 1;
          acknowledgement = failure; terminal_generation_receipt = state.elected_generation;
          followers_receipted = state.followers_waiting;
          follower_acknowledgement = if state.followers_waiting = 0 then No_ack else failure;
          cleanup_obligation = Close_busy_cleanup;
          cleanup_owner = Writer_generation_owner state.elected_generation }
  | Close_succeeded, Closing, Running
    when state.current = 0 && state.queued = 0
         && state.database <> Released
         && state.authorized_quiescence_epoch = state.generation_quiescence_epoch
         && state.remaining_generation_budget > 0
         && state.remaining_global_budget > 0 ->
      Some
        { state with database = Released; writer_terminal = true;
          writer_terminal_receipt = Success_ack;
          close_attempts = state.close_attempts + 1;
          remaining_generation_budget = state.remaining_generation_budget - 1;
          remaining_global_budget = state.remaining_global_budget - 1;
          cleanup_obligation = No_cleanup; cleanup_owner = No_cleanup_owner }
  | Join_writer, Closing, Running
    when state.database = Released && state.writer_terminal
         && state.writer_terminal_receipt = Success_ack ->
      Some
        { state with lifecycle = Closed; writer = Joined;
          acknowledgement = Success_ack; external_join_observed = true;
          terminal_generation_receipt = state.elected_generation;
          followers_receipted = state.followers_waiting;
          follower_acknowledgement =
            if state.followers_waiting = 0 then No_ack else Success_ack }
  | ( Spawn_writer | Configure_failed_released | Configure_failed_retained
    | Schema_failed_released | Schema_failed_retained | Spawn_failed
    | Post_spawn_failed_released | Post_spawn_failed_retained | Enqueue_request
    | Enqueue_failed_released | Enqueue_failed_retained | Start_request
    | Complete_request | Fail_request | Failure_drain_failed_released
    | Failure_drain_failed_retained | Observe_quiescence | Authorize_close
    | Elect_close_owner
    | Observe_competing_close | Close_reported_busy | Close_succeeded
    | Join_writer ), _, _ -> None

exception State_space_limit_exceeded of string * int

let closure ?(terminal = fun _ -> false) ~relation ~events ~step _seen initial =
  let maximum_states = 250_000 in
  let visited = Hashtbl.create 257 in
  let frontier = Queue.create () in
  let ordered = ref [] in
  List.iter
    (fun state ->
      if not (Hashtbl.mem visited state) then begin
        Hashtbl.add visited state ();
        Queue.add state frontier
      end)
    initial;
  while not (Queue.is_empty frontier) do
    let state = Queue.take frontier in
    ordered := state :: !ordered;
    if not (terminal state) then
      List.iter
        (fun event ->
          match step state event with
          | None -> ()
          | Some next when Hashtbl.mem visited next -> ()
          | Some next ->
              if Hashtbl.length visited >= maximum_states then
                raise (State_space_limit_exceeded (relation, maximum_states));
              Hashtbl.add visited next ();
              Queue.add next frontier)
        events
  done;
  List.rev !ordered

let reachable_statements () =
  closure ~relation:"real_statement" ~events:statement_events
    ~step:statement_step [] [ initial_statement ]

let reachable_close_v2 () =
  closure ~relation:"real_close_v2" ~events:close_v2_events
    ~step:close_v2_step [] [ initial_close_v2 ]

let reachable_actors () =
  closure ~relation:"real_actor" ~events:actor_events ~step:actor_step []
    [ initial_actor ]

let total_finalize_calls state =
  state.explicit_finalize_count + state.custom_finalize_count

let string_of_statement state =
  let wrapper = match state.wrapper with Live -> "Live" | Collectible -> "Collectible" in
  let native =
    match state.native with Prepared -> "Prepared" | Finalizing -> "Finalizing"
    | Finalized -> "Finalized"
  in
  let runtime = match state.runtime with Held -> "Held" | Released_for_finalize -> "Released" in
  Printf.sprintf "%s/%s/%s explicit=%d custom=%d" wrapper native runtime
    state.explicit_finalize_count state.custom_finalize_count

let string_of_close_v2 state =
  let release =
    match state.close_v2_release with
    | Close_v2_handle_open -> "Handle_open"
    | Close_v2_deferred_release -> "Deferred_release"
    | Close_v2_physical_release -> "Physical_release"
  in
  Printf.sprintf
    "%s retained=%d terminal=%b calls=%d finalize_failure=%b/%b"
    release state.retained_statements state.close_authority_terminal
    state.native_close_calls state.finalize_failure_observed
    state.finalize_failure_reported

let string_of_actor state =
  let lifecycle =
    match state.lifecycle with Open -> "Open" | Closing -> "Closing"
    | Closed -> "Closed" | Failed -> "Failed"
  in
  let database =
    match state.database with Owned_open -> "Owned_open" | Owned_busy -> "Owned_busy"
    | Released -> "Released"
  in
  let writer =
    match state.writer with Not_spawned -> "Not_spawned" | Running -> "Running"
    | Joined -> "Joined"
  in
  Printf.sprintf
    "%s/%s/%s attempts=%d global=%d generation=%d epoch=%d/%d owners=%d admitted=%d current=%d queued=%d results=%d followers=%d/%d"
    lifecycle database writer state.close_attempts state.remaining_global_budget
    state.elected_generation
    state.generation_quiescence_epoch state.authorized_quiescence_epoch
    state.close_owner_count state.admitted state.current state.queued state.results
    state.followers_receipted state.followers_waiting

let statement_law_premise id state =
  match id with
  | "SQL.STMT.NO_DOUBLE_FINALIZE" ->
      state.explicit_finalize_count + state.custom_finalize_count > 0
  | "SQL.STMT.KEEPALIVE" ->
      state.native = Finalizing && state.explicit_finalize_count = 1
  | "SQL.STMT.EXPLICIT_TOTAL" ->
      state.outcome = Finalize_succeeded
  | "SQL.STMT.FINALIZE_FAILURE_REPORTED" ->
      state.explicit_finalize_count = 1 && state.native = Finalized
  | _ -> true

let actor_law_premise id state =
  match id with
  | "SQL.ACTOR.CLOSED_OWNS_NOTHING" | "SQL.ACTOR.SUCCESS_DRAINS"
  | "SQL.ACTOR.WRITER_TERMINAL_JOIN" -> state.lifecycle = Closed
  | "SQL.ACTOR.BUSY_NOT_SUCCESS" | "SQL.ACTOR.EXHAUSTION_FAILS_NAMED" ->
      state.database = Owned_busy
  | "SQL.ACTOR.ONE_CLOSE_OWNER" | "SQL.ACTOR.NO_ADMIT_AFTER_CLOSE"
  | "SQL.ACTOR.PROGRESS_TOTAL" -> state.lifecycle = Closing
  | "SQL.ACTOR.SETUP_OWNERSHIP" | "SQL.ACTOR.FAILURE_CLEANUP_TRACKED" ->
      state.lifecycle = Failed
  | "SQL.ACTOR.BOUNDED_TERMINAL" -> state.lifecycle <> Open
  | "SQL.ACTOR.NO_LOST_RESULTS" -> state.admitted > 0
  | "SQL.ACTOR.QUIESCENCE_AUTHORIZED" -> state.elected_generation > 0
  | "SQL.ACTOR.FRESH_QUIESCENCE_EPOCH" -> state.elected_generation > 0
  | "SQL.ACTOR.GLOBAL_BUDGET_MONOTONE" -> state.close_attempts > 0
  | "SQL.ACTOR.GENERATION_RECEIPT" ->
      state.elected_generation > 0
      && (state.lifecycle = Closed || state.lifecycle = Failed)
  | "SQL.ACTOR.FOLLOWERS_SAME_RECEIPT" ->
      state.followers_waiting > 0
      && (state.lifecycle = Closed || state.lifecycle = Failed)
  | "SQL.ACTOR.CLEANUP_OWNER_REACHABLE" ->
      state.lifecycle = Failed && state.database <> Released
  | _ -> true

let law ~premise id states violates render =
  let premise_states = List.filter premise states in
  let premise_witness =
    match premise_states with [] -> None | state :: _ -> Some (render state)
  in
  match List.find_opt violates premise_states with
  | None ->
      { id; premise_reachable = premise_states <> []; premise_witness;
        holds = true; counterexample = None }
  | Some state ->
      { id; premise_reachable = true; premise_witness;
        holds = false; counterexample = Some (render state) }

let statement_law id states violates render =
  law ~premise:(statement_law_premise id) id states violates render

let close_v2_law_premise id state =
  match id with
  | "SQL.CLOSE_V2.TERMINAL_ON_ACCEPT" -> state.native_close_calls > 0
  | "SQL.CLOSE_V2.PHYSICAL_AFTER_FINALIZE" ->
      state.close_v2_release = Close_v2_physical_release
  | "SQL.CLOSE_V2.FINALIZE_FAILURE_TYPED" ->
      state.finalize_failure_observed
  | _ -> true

let close_v2_law id states violates render =
  law ~premise:(close_v2_law_premise id) id states violates render

let actor_law id states violates render =
  law ~premise:(actor_law_premise id) id states violates render

let failure_is_named = function Failure_ack message -> String.trim message <> "" | No_ack | Success_ack -> false

let cleanup_honest state =
  match state.lifecycle with
  | Open | Closing | Closed -> true
  | Failed ->
      failure_is_named state.acknowledgement
      && (match state.database, state.writer, state.cleanup_obligation,
                state.cleanup_owner with
          | Released, (Not_spawned | Joined), No_cleanup, No_cleanup_owner -> true
          | (Owned_open | Owned_busy), Not_spawned, origin, Opening_domain_owner ->
              origin <> No_cleanup
          | (Owned_open | Owned_busy), Running, origin,
            Writer_generation_owner generation ->
              origin <> No_cleanup && generation > 0
          | Released, _, _, _ | (Owned_open | Owned_busy), _, _, _ -> false)

let healthy_statement_trace () =
  match statement_step initial_statement Begin_explicit_finalize with
  | None -> false
  | Some in_flight ->
      begin match statement_step in_flight Explicit_finalize_succeeded with
      | Some terminal ->
          terminal.native = Finalized && terminal.runtime = Held
          && terminal.explicit_finalize_count = 1
          && terminal.custom_finalize_count = 0
      | None -> false
      end

let healthy_close_v2_trace () =
  let apply state event = Option.bind state (fun value -> close_v2_step value event) in
  let terminal =
    Some initial_close_v2
    |> fun state -> apply state Retain_statement
    |> fun state -> apply state Accept_close_v2
    |> fun state -> apply state Finalize_retained_succeeded
  in
  match terminal with
  | Some state ->
      state.close_v2_release = Close_v2_physical_release
      && state.retained_statements = 0 && state.close_authority_terminal
      && state.native_close_calls = 1
  | None -> false

let healthy_close_trace () =
  let apply state event = Option.bind state (fun value -> actor_step value event) in
  let terminal =
    Some initial_actor
    |> fun state -> apply state Spawn_writer
    |> fun state -> apply state Enqueue_request
    |> fun state -> apply state Start_request
    |> fun state -> apply state Complete_request
    |> fun state -> apply state Observe_quiescence
    |> fun state -> apply state Authorize_close
    |> fun state -> apply state Elect_close_owner
    |> fun state -> apply state Close_succeeded
    |> fun state -> apply state Join_writer
  in
  match terminal with
  | Some state ->
      state.lifecycle = Closed && state.database = Released
      && state.writer = Joined && state.acknowledgement = Success_ack
      && state.writer_terminal && state.external_join_observed
      && state.terminal_generation_receipt = state.elected_generation
      && state.admitted = state.results
  | None -> false

type mutation =
  | Drop_keepalive
  | Discard_finalize_failure
  | Ignore_busy
  | Close_before_join
  | Abandon_spawned
  | Double_elect
  | Admit_during_closing
  | Reset_retry_budget
  | Busy_without_quiescence
  | Reset_global_budget
  | Split_follower_receipt
  | False_external_join
  | Drop_cleanup_owner
  | Abandon_enqueue_failure
  | Abandon_failure_drain
  | Reuse_stale_quiescence
  | Retry_deferred_close_v2
  | Release_before_finalize
  | Discard_close_v2_finalize_failure

let mutant_close_v2_step mutation state event =
  match mutation, event, state.close_v2_release with
  | Retry_deferred_close_v2, Retry_close_v2, Close_v2_deferred_release
    when state.native_close_calls = 1 ->
      Some { state with native_close_calls = state.native_close_calls + 1 }
  | Release_before_finalize, Accept_close_v2, Close_v2_handle_open
    when state.retained_statements = 1 && not state.close_authority_terminal ->
      Some
        { state with close_v2_release = Close_v2_physical_release;
          close_authority_terminal = true; native_close_calls = 1 }
  | Discard_close_v2_finalize_failure, Finalize_retained_failed,
    Close_v2_deferred_release when state.retained_statements = 1 ->
      Some
        { state with close_v2_release = Close_v2_physical_release;
          retained_statements = 0; finalize_failure_observed = true;
          finalize_failure_reported = false }
  | _ -> close_v2_step state event

let mutant_statement_step mutation state event =
  match mutation, event, state.wrapper, state.native, state.runtime with
  | Drop_keepalive, Begin_explicit_finalize, Live, Prepared, Held ->
      Some
        { state with wrapper = Collectible; native = Finalizing;
          runtime = Released_for_finalize;
          explicit_finalize_count = state.explicit_finalize_count + 1 }
  | Drop_keepalive, Begin_custom_finalize, Collectible, Finalizing,
    Released_for_finalize
    when state.explicit_finalize_count = 1
         && state.custom_finalize_count = 0 ->
      Some { state with custom_finalize_count = state.custom_finalize_count + 1 }
  | Drop_keepalive, Explicit_finalize_succeeded, Collectible, Finalizing,
    Released_for_finalize when state.explicit_finalize_count = 1 ->
      Some { state with native = Finalized; runtime = Held; outcome = Finalize_succeeded }
  | Discard_finalize_failure, Explicit_finalize_failed, Live, Finalizing,
    Released_for_finalize ->
      (* A discarded failure is represented by a terminal statement with no
         reported outcome.  The native object is still consumed. *)
      Some { state with native = Finalized; runtime = Held; outcome = Not_finished }
  | _ -> statement_step state event

let mutant_actor_step mutation state event =
  match mutation, event, state.lifecycle, state.writer with
  | Ignore_busy, Close_reported_busy, Closing, Running
    when state.current = 0 && state.queued = 0 ->
      Some
        { state with lifecycle = Closed; database = Owned_busy; writer = Joined;
          acknowledgement = Success_ack; close_attempts = state.close_attempts + 1 }
  | Close_before_join, Close_succeeded, Closing, Running
    when state.current = 0 && state.queued = 0 ->
      Some
        { state with lifecycle = Closed; database = Released;
          acknowledgement = Success_ack }
  | Abandon_spawned, Post_spawn_failed_released, Open, Running ->
      Some
        { state with lifecycle = Failed; acknowledgement = named_failure Spawn_cleanup;
          cleanup_obligation = No_cleanup }
  | Double_elect, Observe_competing_close, Closing, Running ->
      if state.close_owner_count < 2 then
        Some { state with close_owner_count = state.close_owner_count + 1 }
      else None
  | Admit_during_closing, Enqueue_request, Closing, Running
    when state.admitted < 1 ->
      Some
        { state with admitted = state.admitted + 1; queued = state.queued + 1;
          late_admissions = state.late_admissions + 1 }
  | Reset_retry_budget, Close_reported_busy, Closing, Running
    when state.current = 0 && state.queued = 0
         && state.remaining_generation_budget = 1
         && state.retry_budget_resets = 0 ->
      Some
        { state with database = Owned_busy;
          close_attempts = state.close_attempts + 1;
          remaining_generation_budget = 3;
          remaining_global_budget = max 0 (state.remaining_global_budget - 1);
          retry_budget_resets = 1 }
  | Busy_without_quiescence, Elect_close_owner, Open, Running
    when state.current = 0 && state.queued = 0 ->
      Some
        { state with lifecycle = Closing; close_owner_count = 1;
          elected_generation = 1; generation_quiescence_epoch = 0;
          remaining_generation_budget = 3 }
  | Busy_without_quiescence, Close_reported_busy, Closing, Running
    when state.current = 0 && state.queued = 0
         && state.generation_quiescence_epoch = 0
         && state.remaining_generation_budget > 0 ->
      Some
        { state with database = Owned_busy; close_attempts = state.close_attempts + 1;
          remaining_generation_budget = max 0 (state.remaining_generation_budget - 1);
          remaining_global_budget = max 0 (state.remaining_global_budget - 1) }
  | Reset_global_budget, Close_reported_busy, Closing, Running
    when state.current = 0 && state.queued = 0
         && state.remaining_generation_budget > 0 ->
      Some
        { state with database = Owned_busy; close_attempts = state.close_attempts + 1;
          remaining_generation_budget = state.remaining_generation_budget - 1;
          remaining_global_budget = 3 }
  | Split_follower_receipt, Join_writer, Closing, Running
    when state.database = Released && state.writer_terminal
         && state.followers_waiting > 0 ->
      Some
        { state with lifecycle = Closed; writer = Joined;
          acknowledgement = Success_ack; external_join_observed = true;
          terminal_generation_receipt = state.elected_generation;
          followers_receipted = state.followers_waiting;
          follower_acknowledgement = named_failure Close_busy_cleanup }
  | False_external_join, Close_succeeded, Closing, Running
    when state.current = 0 && state.queued = 0 ->
      Some
        { state with lifecycle = Closed; database = Released; writer = Joined;
          acknowledgement = Success_ack; external_join_observed = true;
          terminal_generation_receipt = state.elected_generation }
  | Drop_cleanup_owner, Close_reported_busy, Closing, Running
    when state.current = 0 && state.queued = 0
         && state.remaining_generation_budget = 1 ->
      Some
        { state with lifecycle = Failed; database = Owned_busy;
          close_attempts = state.close_attempts + 1;
          remaining_generation_budget = 0;
          remaining_global_budget = max 0 (state.remaining_global_budget - 1);
          acknowledgement = named_failure Close_busy_cleanup;
          cleanup_obligation = Close_busy_cleanup;
          cleanup_owner = No_cleanup_owner }
  | Abandon_enqueue_failure, Enqueue_failed_released, Open, Running ->
      Some
        { state with lifecycle = Failed; acknowledgement = named_failure Enqueue_cleanup;
          cleanup_obligation = No_cleanup }
  | Abandon_failure_drain, Failure_drain_failed_released, (Open | Closing), Running ->
      Some
        { state with lifecycle = Failed;
          acknowledgement = named_failure Failure_drain_cleanup;
          cleanup_obligation = No_cleanup }
  | Reuse_stale_quiescence, Elect_close_owner, Failed, Running
    when state.elected_generation = 1 && state.close_attempts = 1
         && state.admitted = 0 && state.results = 0
         && state.followers_waiting = 0
         && state.cleanup_owner <> No_cleanup_owner
         && state.authorized_quiescence_epoch = state.quiescence_epoch
         && state.quiescence_epoch = state.generation_quiescence_epoch
         && state.remaining_global_budget > 0 ->
      Some
        { state with lifecycle = Closing; close_owner_count = 1;
          elected_generation = state.elected_generation + 1;
          generation_quiescence_freshness = Stale_or_older_quiescence;
          generation_quiescence_epoch = state.quiescence_epoch;
          remaining_generation_budget = 1; terminal_generation_receipt = 0;
          acknowledgement = No_ack; writer_terminal_receipt = No_ack;
          writer_terminal = false; external_join_observed = false;
          followers_waiting = 0; followers_receipted = 0;
          follower_acknowledgement = No_ack; cleanup_obligation = No_cleanup;
          cleanup_owner = No_cleanup_owner }
  | _ -> actor_step state event

let bounded_mutation_evidence ~events ~real_step ~mutant_step ~initial
    ~violates =
  let maximum_states = 100_000 in
  let visited = Hashtbl.create 257 in
  let frontier = Queue.create () in
  let premise = ref None in
  let witness = ref None in
  let explored = ref 0 in
  Hashtbl.add visited initial ();
  Queue.add initial frontier;
  while
    not (Queue.is_empty frontier)
    && (Option.is_none !premise || Option.is_none !witness)
    && !explored < maximum_states
  do
    let state = Queue.take frontier in
    incr explored;
    if Option.is_none !witness && violates state then witness := Some state;
    List.iter
      (fun event ->
        let real = real_step state event in
        let mutated = mutant_step state event in
        if Option.is_none !premise && mutated <> real then premise := Some state;
        match mutated with
        | None -> ()
        | Some next when Hashtbl.mem visited next -> ()
        | Some next ->
            Hashtbl.add visited next ();
            Queue.add next frontier)
      events
  done;
  (!premise, !witness)

let statement_mutant_result id mutation violates =
  let step = mutant_statement_step mutation in
  let premise, witness =
    bounded_mutation_evidence ~events:statement_events
      ~real_step:statement_step ~mutant_step:step ~initial:initial_statement
      ~violates
  in
  match witness with
  | Some witness ->
      { id; premise_reachable = Option.is_some premise;
        premise_witness = Option.map string_of_statement premise;
        killed = true; witness = Some (string_of_statement witness) }
  | None ->
      { id; premise_reachable = Option.is_some premise;
        premise_witness = Option.map string_of_statement premise;
        killed = false; witness = None }

let close_v2_mutant_result id mutation violates =
  let step = mutant_close_v2_step mutation in
  let premise, witness =
    bounded_mutation_evidence ~events:close_v2_events
      ~real_step:close_v2_step ~mutant_step:step ~initial:initial_close_v2
      ~violates
  in
  match witness with
  | Some witness ->
      { id; premise_reachable = Option.is_some premise;
        premise_witness = Option.map string_of_close_v2 premise;
        killed = true; witness = Some (string_of_close_v2 witness) }
  | None ->
      { id; premise_reachable = Option.is_some premise;
        premise_witness = Option.map string_of_close_v2 premise;
        killed = false; witness = None }

let actor_mutant_result id mutation violates =
  let step = mutant_actor_step mutation in
  let premise, witness =
    bounded_mutation_evidence ~events:actor_events ~real_step:actor_step
      ~mutant_step:step ~initial:initial_actor ~violates
  in
  match witness with
  | Some witness ->
      { id; premise_reachable = Option.is_some premise;
        premise_witness = Option.map string_of_actor premise;
        killed = true; witness = Some (string_of_actor witness) }
  | None ->
      { id; premise_reachable = Option.is_some premise;
        premise_witness = Option.map string_of_actor premise;
        killed = false; witness = None }

let progress_events =
  [ Start_request; Complete_request; Fail_request; Close_reported_busy;
    Close_succeeded; Join_writer ]

let progress_successors state =
  List.filter_map (actor_step state) progress_events
  |> List.sort_uniq compare

let rec all_progress_paths_terminal visiting state =
  match state.lifecycle with
  | Closed | Failed -> state.acknowledgement <> No_ack
  | Open -> false
  | Closing ->
      if List.mem state visiting then false
      else
        let successors = progress_successors state in
        successors <> []
        && List.for_all (all_progress_paths_terminal (state :: visiting)) successors

let explore () =
  let statements = reachable_statements () in
  let close_v2_states = reachable_close_v2 () in
  let actors = reachable_actors () in
  let statement_laws =
    [ statement_law "SQL.STMT.NO_DOUBLE_FINALIZE" statements
        (fun state -> total_finalize_calls state > 1) string_of_statement;
      statement_law "SQL.STMT.KEEPALIVE" statements
        (fun state ->
          state.native = Finalizing && state.runtime = Released_for_finalize
          && state.explicit_finalize_count = 1
          && (state.wrapper <> Live || state.custom_finalize_count <> 0))
        string_of_statement;
      statement_law "SQL.STMT.EXPLICIT_TOTAL" statements
        (fun state ->
          state.outcome = Finalize_succeeded
          && state.explicit_finalize_count = 1
          && (state.native <> Finalized || state.runtime <> Held
              || total_finalize_calls state <> 1))
        string_of_statement;
      statement_law "SQL.STMT.FINALIZE_FAILURE_REPORTED" statements
        (fun state ->
          state.native = Finalized && state.explicit_finalize_count = 1
          && state.outcome = Not_finished)
        string_of_statement ]
  in
  let close_v2_laws =
    [ close_v2_law "SQL.CLOSE_V2.TERMINAL_ON_ACCEPT" close_v2_states
        (fun state ->
          state.native_close_calls > 0
          && (not state.close_authority_terminal
              || state.native_close_calls <> 1))
        string_of_close_v2;
      close_v2_law "SQL.CLOSE_V2.PHYSICAL_AFTER_FINALIZE" close_v2_states
        (fun state ->
          state.close_v2_release = Close_v2_physical_release
          && (state.retained_statements <> 0
              || not state.close_authority_terminal))
        string_of_close_v2;
      close_v2_law "SQL.CLOSE_V2.FINALIZE_FAILURE_TYPED" close_v2_states
        (fun state ->
          state.finalize_failure_observed
          && (not state.finalize_failure_reported
              || state.close_v2_release = Close_v2_physical_release))
        string_of_close_v2 ]
  in
  let actor_laws =
    [ actor_law "SQL.ACTOR.CLOSED_OWNS_NOTHING" actors
        (fun state ->
          state.lifecycle = Closed
          && (state.database <> Released || state.writer <> Joined
              || state.acknowledgement <> Success_ack))
        string_of_actor;
      actor_law "SQL.ACTOR.BUSY_NOT_SUCCESS" actors
        (fun state -> state.database = Owned_busy && state.acknowledgement = Success_ack)
        string_of_actor;
      actor_law "SQL.ACTOR.EXHAUSTION_FAILS_NAMED" actors
        (fun state ->
          state.remaining_generation_budget = 0 && state.database = Owned_busy
          && state.elected_generation > 0
          && (state.lifecycle <> Failed || state.acknowledgement = Success_ack
              || not (failure_is_named state.acknowledgement)))
        string_of_actor;
      actor_law "SQL.ACTOR.ONE_CLOSE_OWNER" actors
        (fun state -> state.close_owner_count > 1) string_of_actor;
      actor_law "SQL.ACTOR.SUCCESS_DRAINS" actors
        (fun state -> state.lifecycle = Closed && state.admitted <> state.results)
        string_of_actor;
      actor_law "SQL.ACTOR.SETUP_OWNERSHIP" actors
        (fun state -> state.lifecycle = Failed && not (cleanup_honest state))
        string_of_actor;
      actor_law "SQL.ACTOR.NO_ADMIT_AFTER_CLOSE" actors
        (fun state -> state.late_admissions <> 0) string_of_actor;
      actor_law "SQL.ACTOR.BOUNDED_TERMINAL" actors
        (fun state ->
          (state.lifecycle = Closed || state.lifecycle = Failed)
          && state.acknowledgement = No_ack
          || state.lifecycle = Closing
             && not (all_progress_paths_terminal [] state))
        string_of_actor;
      actor_law "SQL.ACTOR.FAILURE_CLEANUP_TRACKED" actors
        (fun state -> state.lifecycle = Failed && not (cleanup_honest state))
        string_of_actor;
      actor_law "SQL.ACTOR.NO_LOST_RESULTS" actors
        (fun state ->
          state.results > state.admitted
          || state.current + state.queued + state.results <> state.admitted)
        string_of_actor;
      actor_law "SQL.ACTOR.QUIESCENCE_AUTHORIZED" actors
        (fun state ->
          state.elected_generation > 0
          && (state.generation_quiescence_epoch <= 0
              || state.lifecycle = Closing
                 && state.authorized_quiescence_epoch
                    <> state.generation_quiescence_epoch))
        string_of_actor;
      actor_law "SQL.ACTOR.FRESH_QUIESCENCE_EPOCH" actors
        (fun state ->
          state.elected_generation > 0
          && state.generation_quiescence_freshness
             <> Strictly_newer_quiescence)
        string_of_actor;
      actor_law "SQL.ACTOR.GLOBAL_BUDGET_MONOTONE" actors
        (fun state ->
          state.remaining_global_budget < 0
          || state.remaining_global_budget > 3
          || state.remaining_global_budget + state.close_attempts <> 3
          || state.remaining_generation_budget < 0
          || state.remaining_generation_budget > 1)
        string_of_actor;
      actor_law "SQL.ACTOR.GENERATION_RECEIPT" actors
        (fun state ->
          state.elected_generation > 0
          && (state.lifecycle = Closed || state.lifecycle = Failed)
          && state.terminal_generation_receipt <> state.elected_generation)
        string_of_actor;
      actor_law "SQL.ACTOR.FOLLOWERS_SAME_RECEIPT" actors
        (fun state ->
          state.elected_generation > 0
          && (state.lifecycle = Closed || state.lifecycle = Failed)
          && (state.followers_receipted <> state.followers_waiting
              || (state.followers_waiting = 0
                  && state.follower_acknowledgement <> No_ack)
              || (state.followers_waiting > 0
                  && state.follower_acknowledgement
                     <> state.acknowledgement)))
        string_of_actor;
      actor_law "SQL.ACTOR.WRITER_TERMINAL_JOIN" actors
        (fun state ->
          state.lifecycle = Closed
          && (not state.writer_terminal || not state.external_join_observed
              || state.writer <> Joined
              || state.writer_terminal_receipt <> Success_ack))
        string_of_actor;
      actor_law "SQL.ACTOR.CLEANUP_OWNER_REACHABLE" actors
        (fun state ->
          state.lifecycle = Failed && state.database <> Released
          && (state.cleanup_owner = No_cleanup_owner
              || state.cleanup_obligation = No_cleanup))
        string_of_actor;
      actor_law "SQL.ACTOR.PROGRESS_TOTAL" actors
        (fun state ->
          state.lifecycle = Closing
          && not (all_progress_paths_terminal [] state))
        string_of_actor ]
  in
  let mutants =
    [ statement_mutant_result "MUT.STMT.DROP_KEEPALIVE" Drop_keepalive
        (fun state -> total_finalize_calls state > 1);
      statement_mutant_result "MUT.STMT.DISCARD_FINALIZE_FAILURE"
        Discard_finalize_failure
        (fun state ->
          state.native = Finalized && state.explicit_finalize_count = 1
          && state.outcome = Not_finished);
      close_v2_mutant_result "MUT.CLOSE_V2.RETRY_DEFERRED"
        Retry_deferred_close_v2
        (fun state -> state.native_close_calls > 1);
      close_v2_mutant_result "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE"
        Release_before_finalize
        (fun state ->
          state.close_v2_release = Close_v2_physical_release
          && state.retained_statements > 0);
      close_v2_mutant_result "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE"
        Discard_close_v2_finalize_failure
        (fun state ->
          state.finalize_failure_observed
          && (not state.finalize_failure_reported
              || state.close_v2_release = Close_v2_physical_release));
      actor_mutant_result "MUT.ACTOR.IGNORE_BUSY" Ignore_busy
        (fun state -> state.lifecycle = Closed && state.database <> Released);
      actor_mutant_result "MUT.ACTOR.CLOSE_BEFORE_JOIN" Close_before_join
        (fun state -> state.lifecycle = Closed && state.writer <> Joined);
      actor_mutant_result "MUT.ACTOR.ABANDON_SPAWNED" Abandon_spawned
        (fun state -> state.lifecycle = Failed && not (cleanup_honest state));
      actor_mutant_result "MUT.ACTOR.DOUBLE_ELECT" Double_elect
        (fun state -> state.close_owner_count > 1);
      actor_mutant_result "MUT.ACTOR.ADMIT_DURING_CLOSING" Admit_during_closing
        (fun state -> state.late_admissions > 0);
      actor_mutant_result "MUT.ACTOR.RESET_RETRY_BUDGET" Reset_retry_budget
        (fun state -> state.retry_budget_resets > 0 && state.close_attempts >= 3);
      actor_mutant_result "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE"
        Busy_without_quiescence
        (fun state ->
          state.close_attempts > 0 && state.generation_quiescence_epoch = 0);
      actor_mutant_result "MUT.ACTOR.REUSE_STALE_QUIESCENCE"
        Reuse_stale_quiescence
        (fun state ->
          state.elected_generation > 1
          && state.generation_quiescence_freshness
             = Stale_or_older_quiescence);
      actor_mutant_result "MUT.ACTOR.RESET_GLOBAL_BUDGET" Reset_global_budget
        (fun state -> state.remaining_global_budget + state.close_attempts > 3);
      actor_mutant_result "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT"
        Split_follower_receipt
        (fun state ->
          state.followers_waiting > 0
          && state.follower_acknowledgement <> state.acknowledgement);
      actor_mutant_result "MUT.ACTOR.FALSE_EXTERNAL_JOIN" False_external_join
        (fun state ->
          state.external_join_observed && not state.writer_terminal);
      actor_mutant_result "MUT.ACTOR.DROP_CLEANUP_OWNER" Drop_cleanup_owner
        (fun state ->
          state.lifecycle = Failed && state.database <> Released
          && state.cleanup_owner = No_cleanup_owner);
      actor_mutant_result "MUT.ACTOR.ABANDON_ENQUEUE_FAILURE"
        Abandon_enqueue_failure
        (fun state -> state.lifecycle = Failed && not (cleanup_honest state));
      actor_mutant_result "MUT.ACTOR.ABANDON_FAILURE_DRAIN"
        Abandon_failure_drain
        (fun state -> state.lifecycle = Failed && not (cleanup_honest state)) ]
  in
  { statement_states = List.length statements;
    close_v2_states = List.length close_v2_states;
    actor_states = List.length actors;
    healthy_statement_trace = healthy_statement_trace ();
    healthy_close_v2_trace = healthy_close_v2_trace ();
    healthy_close_trace = healthy_close_trace ();
    laws = statement_laws @ close_v2_laws @ actor_laws; mutants }

let theorem_ids =
  [ "SQL.STMT.NO_DOUBLE_FINALIZE"; "SQL.STMT.KEEPALIVE";
    "SQL.STMT.EXPLICIT_TOTAL"; "SQL.STMT.FINALIZE_FAILURE_REPORTED";
    "SQL.CLOSE_V2.TERMINAL_ON_ACCEPT";
    "SQL.CLOSE_V2.PHYSICAL_AFTER_FINALIZE";
    "SQL.CLOSE_V2.FINALIZE_FAILURE_TYPED";
    "SQL.ACTOR.CLOSED_OWNS_NOTHING"; "SQL.ACTOR.BUSY_NOT_SUCCESS";
    "SQL.ACTOR.EXHAUSTION_FAILS_NAMED"; "SQL.ACTOR.ONE_CLOSE_OWNER";
    "SQL.ACTOR.SUCCESS_DRAINS"; "SQL.ACTOR.SETUP_OWNERSHIP";
    "SQL.ACTOR.NO_ADMIT_AFTER_CLOSE"; "SQL.ACTOR.BOUNDED_TERMINAL";
    "SQL.ACTOR.FAILURE_CLEANUP_TRACKED"; "SQL.ACTOR.NO_LOST_RESULTS";
    "SQL.ACTOR.QUIESCENCE_AUTHORIZED";
    "SQL.ACTOR.FRESH_QUIESCENCE_EPOCH";
    "SQL.ACTOR.GLOBAL_BUDGET_MONOTONE";
    "SQL.ACTOR.GENERATION_RECEIPT";
    "SQL.ACTOR.FOLLOWERS_SAME_RECEIPT";
    "SQL.ACTOR.WRITER_TERMINAL_JOIN";
    "SQL.ACTOR.CLEANUP_OWNER_REACHABLE"; "SQL.ACTOR.PROGRESS_TOTAL" ]

let mutant_ids =
  [ "MUT.STMT.DROP_KEEPALIVE"; "MUT.STMT.DISCARD_FINALIZE_FAILURE";
    "MUT.CLOSE_V2.RETRY_DEFERRED";
    "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE";
    "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE";
    "MUT.ACTOR.IGNORE_BUSY"; "MUT.ACTOR.CLOSE_BEFORE_JOIN";
    "MUT.ACTOR.ABANDON_SPAWNED"; "MUT.ACTOR.DOUBLE_ELECT";
    "MUT.ACTOR.ADMIT_DURING_CLOSING"; "MUT.ACTOR.RESET_RETRY_BUDGET";
    "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE";
    "MUT.ACTOR.REUSE_STALE_QUIESCENCE";
    "MUT.ACTOR.RESET_GLOBAL_BUDGET";
    "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT";
    "MUT.ACTOR.FALSE_EXTERNAL_JOIN";
    "MUT.ACTOR.DROP_CLEANUP_OWNER";
    "MUT.ACTOR.ABANDON_ENQUEUE_FAILURE";
    "MUT.ACTOR.ABANDON_FAILURE_DRAIN" ]

let obligations =
  let real prefix healthy =
    let ids = List.filter (String.starts_with ~prefix) theorem_ids in
    List.map
      (fun id -> { id; kind = Theorem_negation; expected = Unsat })
      ids
    @ List.map
        (fun id ->
          { id = "CONTROL.PREMISE." ^ id; kind = Premise_control;
            expected = Sat })
        ids
    @ [ { id = healthy; kind = Healthy_control; expected = Sat } ]
  in
  real "SQL.STMT." "CONTROL.HEALTHY_STATEMENT"
  @ real "SQL.CLOSE_V2." "CONTROL.HEALTHY_CLOSE_V2"
  @ real "SQL.ACTOR." "CONTROL.HEALTHY_CLOSE"
  @ List.map
      (fun id -> { id; kind = Mutant_witness; expected = Sat })
      mutant_ids

let string_of_answer = function Sat -> "sat" | Unsat -> "unsat"

let expected_solver_output () =
  obligations
  |> List.concat_map (fun obligation -> [ obligation.id; string_of_answer obligation.expected ])
  |> String.concat "\n"
  |> fun text -> text ^ "\n"

let mutate_expected_output ~id ~actual =
  if not (List.exists (fun obligation -> String.equal obligation.id id) obligations)
  then Error ("unknown obligation: " ^ id)
  else
    Ok
      (obligations
       |> List.concat_map (fun obligation ->
              [ obligation.id;
                string_of_answer
                  (if String.equal obligation.id id then actual else obligation.expected) ])
       |> String.concat "\n"
       |> fun text -> text ^ "\n")

let normalized_lines output =
  output |> String.split_on_char '\n' |> List.map String.trim
  |> List.filter (fun line -> not (String.equal line ""))

let answer_of_string = function "sat" -> Some Sat | "unsat" -> Some Unsat | _ -> None

let validate_obligation_output expected_obligations output =
  let rec parse seen expected lines =
    match expected, lines with
    | [], [] -> Ok (List.rev seen)
    | obligation :: rest, id :: answer :: tail
      when String.equal id obligation.id ->
        begin match answer_of_string answer with
        | Some actual -> parse ((obligation, actual) :: seen) rest tail
        | None -> Error (Printf.sprintf "%s returned %s" id answer)
        end
    | obligation :: _, id :: _ ->
        Error
          (Printf.sprintf "expected obligation %s, received %s" obligation.id id)
    | _ -> Error "solver output is truncated, duplicated, or has extra lines"
  in
  match parse [] expected_obligations (normalized_lines output) with
  | Error detail -> Unavailable detail
  | Ok observations ->
      begin match
        List.find_opt
          (fun (obligation, actual) -> actual <> obligation.expected)
          observations
      with
      | None -> Proved
      | Some (obligation, actual) ->
          Refuted
            (Printf.sprintf "%s expected %s, received %s" obligation.id
               (string_of_answer obligation.expected) (string_of_answer actual))
      end

let validate_solver_output output = validate_obligation_output obligations output

let int_of_wrapper = function Live -> 0 | Collectible -> 1
let int_of_native = function Prepared -> 0 | Finalizing -> 1 | Finalized -> 2
let int_of_runtime = function Held -> 0 | Released_for_finalize -> 1
let int_of_outcome = function Not_finished -> 0 | Finalize_succeeded -> 1 | Finalize_failed_reported -> 2
let int_of_close_v2_release = function
  | Close_v2_handle_open -> 0
  | Close_v2_deferred_release -> 1
  | Close_v2_physical_release -> 2
let int_of_lifecycle = function Open -> 0 | Closing -> 1 | Closed -> 2 | Failed -> 3
let int_of_database = function Owned_open -> 0 | Owned_busy -> 1 | Released -> 2
let int_of_writer = function Not_spawned -> 0 | Running -> 1 | Joined -> 2
let int_of_ack = function No_ack -> 0 | Success_ack -> 1 | Failure_ack _ -> 2
let int_of_cleanup = function
  | No_cleanup -> 0 | Configure_cleanup -> 1 | Schema_cleanup -> 2
  | Spawn_cleanup -> 3 | Enqueue_cleanup -> 4 | Failure_drain_cleanup -> 5
  | Close_busy_cleanup -> 6
let int_of_cleanup_owner_kind = function
  | No_cleanup_owner -> 0
  | Opening_domain_owner -> 1
  | Writer_generation_owner _ -> 2
let cleanup_owner_generation = function
  | Writer_generation_owner generation -> generation
  | No_cleanup_owner | Opening_domain_owner -> 0
let acknowledgement_failure_name_length = function
  | Failure_ack detail -> String.length (String.trim detail)
  | No_ack | Success_ack -> 0
let int_of_quiescence_freshness = function
  | No_quiescence_receipt -> 0
  | Strictly_newer_quiescence -> 1
  | Stale_or_older_quiescence -> 2

let emit_int_table buffer name values =
  Buffer.add_string buffer (Printf.sprintf "(declare-fun %s (Int) Int)\n" name);
  List.iteri
    (fun index value ->
      Buffer.add_string buffer
        (Printf.sprintf "(assert (= (%s %d) %d))\n" name index value))
    values

type sparse_int_table = {
  sparse_default : int;
  sparse_state_count : int;
  sparse_value_groups : (int * int list) list;
}

let make_sparse_int_table ~default values =
  let value_groups =
    values |> List.filter (fun value -> value <> default)
    |> List.sort_uniq compare
    |> List.map (fun value ->
           let indices =
             values
             |> List.mapi (fun index candidate ->
                    if candidate = value then Some index else None)
             |> List.filter_map Fun.id
           in
           (value, indices))
  in
  { sparse_default = default; sparse_state_count = List.length values;
    sparse_value_groups = value_groups }

let sparse_int_table_value table state =
  match
    List.find_map
      (fun (value, indices) ->
        if List.mem state indices then Some value else None)
      table.sparse_value_groups
  with
  | Some value -> value
  | None -> table.sparse_default

let validate_sparse_int_table ~values table =
  table.sparse_state_count = List.length values
  && List.for_all
       (fun (value, indices) ->
         value <> table.sparse_default && indices <> []
         && List.for_all
              (fun state -> state >= 0 && state < table.sparse_state_count)
              indices)
       table.sparse_value_groups
  && let all_indices =
       List.concat_map snd table.sparse_value_groups |> List.sort compare
     in
     all_indices = List.sort_uniq compare all_indices
     && let rec values_match state = function
          | [] -> true
          | value :: rest ->
              sparse_int_table_value table state = value
              && values_match (state + 1) rest
        in
        values_match 0 values

let canonical_sparse_int_table_rows relation field table =
  Printf.sprintf "%s:SPARSE:%s:default=%d,count=%d" relation field
    table.sparse_default table.sparse_state_count
  :: List.map
       (fun (value, indices) ->
         Printf.sprintf "%s:SPARSE:%s:value=%d,states=%s" relation field value
           (indices |> List.map string_of_int |> String.concat ","))
       table.sparse_value_groups

let actor_raw_cleanup_fields states =
  [ ("ack_failure_name_length",
     List.map
       (fun state ->
         acknowledgement_failure_name_length state.acknowledgement)
       states);
    ("cleanup_origin",
     List.map (fun state -> int_of_cleanup state.cleanup_obligation) states);
    ("cleanup_owner_kind",
     List.map
       (fun state -> int_of_cleanup_owner_kind state.cleanup_owner)
       states);
    ("cleanup_owner_generation",
     List.map
       (fun state -> cleanup_owner_generation state.cleanup_owner)
       states) ]

let canonical_actor_sparse_rows relation states =
  actor_raw_cleanup_fields states
  |> List.concat_map (fun (field, values) ->
         make_sparse_int_table ~default:0 values
         |> canonical_sparse_int_table_rows relation field)

let emit_sparse_int_table buffer name ~default values =
  let table = make_sparse_int_table ~default values in
  if not (validate_sparse_int_table ~values table) then
    invalid_arg (name ^ ": invalid sparse integer table");
  let expression =
    List.fold_right
      (fun (value, indices) fallback ->
        let clauses =
          List.map (fun index -> Printf.sprintf "(= state %d)" index) indices
        in
        let selected =
          match clauses with
          | [] -> "false"
          | [ clause ] -> clause
          | clauses -> "(or " ^ String.concat " " clauses ^ ")"
        in
        Printf.sprintf "(ite %s %d %s)" selected value fallback)
      table.sparse_value_groups (string_of_int default)
  in
  Buffer.add_string buffer
    (Printf.sprintf "(define-fun %s ((state Int)) Int %s)\n" name expression)

let string_of_statement_event = function
  | Begin_explicit_finalize -> "Begin_explicit_finalize"
  | Explicit_finalize_succeeded -> "Explicit_finalize_succeeded"
  | Explicit_finalize_failed -> "Explicit_finalize_failed"
  | Become_collectible -> "Become_collectible"
  | Begin_custom_finalize -> "Begin_custom_finalize"
  | Custom_finalize_returned -> "Custom_finalize_returned"

let string_of_actor_event = function
  | Spawn_writer -> "Spawn_writer"
  | Configure_failed_released -> "Configure_failed_released"
  | Configure_failed_retained -> "Configure_failed_retained"
  | Schema_failed_released -> "Schema_failed_released"
  | Schema_failed_retained -> "Schema_failed_retained"
  | Spawn_failed -> "Spawn_failed"
  | Post_spawn_failed_released -> "Post_spawn_failed_released"
  | Post_spawn_failed_retained -> "Post_spawn_failed_retained"
  | Enqueue_request -> "Enqueue_request"
  | Enqueue_failed_released -> "Enqueue_failed_released"
  | Enqueue_failed_retained -> "Enqueue_failed_retained"
  | Start_request -> "Start_request"
  | Complete_request -> "Complete_request"
  | Fail_request -> "Fail_request"
  | Failure_drain_failed_released -> "Failure_drain_failed_released"
  | Failure_drain_failed_retained -> "Failure_drain_failed_retained"
  | Observe_quiescence -> "Observe_quiescence"
  | Authorize_close -> "Authorize_close"
  | Elect_close_owner -> "Elect_close_owner"
  | Observe_competing_close -> "Observe_competing_close"
  | Close_reported_busy -> "Close_reported_busy"
  | Close_succeeded -> "Close_succeeded"
  | Join_writer -> "Join_writer"

let string_of_close_v2_event = function
  | Retain_statement -> "Retain_statement"
  | Accept_close_v2 -> "Accept_close_v2"
  | Finalize_retained_succeeded -> "Finalize_retained_succeeded"
  | Finalize_retained_failed -> "Finalize_retained_failed"
  | Retry_close_v2 -> "Retry_close_v2"

let index_of value values =
  let rec find index = function
    | [] -> -1
    | candidate :: rest ->
        if candidate = value then index else find (index + 1) rest
  in
  find 0 values

let canonical_statement state =
  Printf.sprintf "%d,%d,%d,%d,%d,%d"
    (int_of_wrapper state.wrapper) (int_of_native state.native)
    (int_of_runtime state.runtime) state.explicit_finalize_count
    state.custom_finalize_count (int_of_outcome state.outcome)

let canonical_close_v2 state =
  Printf.sprintf "%d,%d,%d,%d,%d,%d"
    (int_of_close_v2_release state.close_v2_release)
    state.retained_statements
    (if state.close_authority_terminal then 1 else 0)
    state.native_close_calls
    (if state.finalize_failure_observed then 1 else 0)
    (if state.finalize_failure_reported then 1 else 0)

let canonical_actor state =
  [ int_of_lifecycle state.lifecycle; int_of_database state.database;
    int_of_writer state.writer; int_of_ack state.acknowledgement;
    acknowledgement_failure_name_length state.acknowledgement;
    state.close_attempts; state.remaining_global_budget;
    state.remaining_generation_budget; state.close_owner_count;
    state.elected_generation; state.generation_quiescence_epoch;
    int_of_quiescence_freshness state.generation_quiescence_freshness;
    state.quiescence_epoch; state.authorized_quiescence_epoch;
    state.terminal_generation_receipt;
    int_of_ack state.writer_terminal_receipt;
    (if state.writer_terminal then 1 else 0);
    (if state.external_join_observed then 1 else 0);
    state.followers_waiting; state.followers_receipted;
    int_of_ack state.follower_acknowledgement;
    state.admitted; state.current; state.queued; state.results;
    state.late_admissions; state.retry_budget_resets;
    int_of_cleanup state.cleanup_obligation;
    int_of_cleanup_owner_kind state.cleanup_owner;
    cleanup_owner_generation state.cleanup_owner ]
  |> List.map string_of_int |> String.concat ","

let statement_mutant_violation id state =
  match id with
  | "MUT.STMT.DROP_KEEPALIVE" -> total_finalize_calls state > 1
  | "MUT.STMT.DISCARD_FINALIZE_FAILURE" ->
      state.native = Finalized && state.explicit_finalize_count = 1
      && state.outcome = Not_finished
  | _ -> false

let close_v2_mutant_violation id state =
  match id with
  | "MUT.CLOSE_V2.RETRY_DEFERRED" -> state.native_close_calls > 1
  | "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE" ->
      state.close_v2_release = Close_v2_physical_release
      && state.retained_statements > 0
  | "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE" ->
      state.finalize_failure_observed
      && (not state.finalize_failure_reported
          || state.close_v2_release = Close_v2_physical_release)
  | _ -> false

let actor_mutant_violation id state =
  match id with
  | "MUT.ACTOR.IGNORE_BUSY" ->
      state.lifecycle = Closed && state.database <> Released
  | "MUT.ACTOR.CLOSE_BEFORE_JOIN" ->
      state.lifecycle = Closed && state.writer <> Joined
  | "MUT.ACTOR.ABANDON_SPAWNED"
  | "MUT.ACTOR.ABANDON_ENQUEUE_FAILURE"
  | "MUT.ACTOR.ABANDON_FAILURE_DRAIN" ->
      state.lifecycle = Failed && not (cleanup_honest state)
  | "MUT.ACTOR.DOUBLE_ELECT" -> state.close_owner_count > 1
  | "MUT.ACTOR.ADMIT_DURING_CLOSING" -> state.late_admissions > 0
  | "MUT.ACTOR.RESET_RETRY_BUDGET" ->
      state.retry_budget_resets > 0 && state.close_attempts >= 3
  | "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE" ->
      state.close_attempts > 0 && state.generation_quiescence_epoch = 0
  | "MUT.ACTOR.REUSE_STALE_QUIESCENCE" ->
      state.elected_generation > 1
      && state.generation_quiescence_freshness = Stale_or_older_quiescence
  | "MUT.ACTOR.RESET_GLOBAL_BUDGET" ->
      state.remaining_global_budget + state.close_attempts > 3
  | "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT" ->
      state.followers_waiting > 0
      && state.follower_acknowledgement <> state.acknowledgement
  | "MUT.ACTOR.FALSE_EXTERNAL_JOIN" ->
      state.external_join_observed && not state.writer_terminal
  | "MUT.ACTOR.DROP_CLEANUP_OWNER" ->
      state.lifecycle = Failed && state.database <> Released
      && state.cleanup_owner = No_cleanup_owner
  | _ -> false

type mutant_space =
  | Mutant_statement_space of statement_state list
  | Mutant_close_v2_space of close_v2_state list
  | Mutant_actor_space of actor_state list

let mutant_space id =
  let statement mutation =
    Mutant_statement_space
      (closure ~terminal:(statement_mutant_violation id) ~relation:id
         ~events:statement_events
         ~step:(mutant_statement_step mutation) [] [ initial_statement ])
  in
  let actor mutation =
    Mutant_actor_space
      (closure ~terminal:(actor_mutant_violation id) ~relation:id
         ~events:actor_events
         ~step:(mutant_actor_step mutation) [] [ initial_actor ])
  in
  let close_v2 mutation =
    Mutant_close_v2_space
      (closure ~terminal:(close_v2_mutant_violation id) ~relation:id
         ~events:close_v2_events
         ~step:(mutant_close_v2_step mutation) [] [ initial_close_v2 ])
  in
  match id with
  | "MUT.STMT.DROP_KEEPALIVE" -> statement Drop_keepalive
  | "MUT.STMT.DISCARD_FINALIZE_FAILURE" -> statement Discard_finalize_failure
  | "MUT.CLOSE_V2.RETRY_DEFERRED" -> close_v2 Retry_deferred_close_v2
  | "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE" -> close_v2 Release_before_finalize
  | "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE" ->
      close_v2 Discard_close_v2_finalize_failure
  | "MUT.ACTOR.IGNORE_BUSY" -> actor Ignore_busy
  | "MUT.ACTOR.CLOSE_BEFORE_JOIN" -> actor Close_before_join
  | "MUT.ACTOR.ABANDON_SPAWNED" -> actor Abandon_spawned
  | "MUT.ACTOR.DOUBLE_ELECT" -> actor Double_elect
  | "MUT.ACTOR.ADMIT_DURING_CLOSING" -> actor Admit_during_closing
  | "MUT.ACTOR.RESET_RETRY_BUDGET" -> actor Reset_retry_budget
  | "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE" -> actor Busy_without_quiescence
  | "MUT.ACTOR.REUSE_STALE_QUIESCENCE" -> actor Reuse_stale_quiescence
  | "MUT.ACTOR.RESET_GLOBAL_BUDGET" -> actor Reset_global_budget
  | "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT" -> actor Split_follower_receipt
  | "MUT.ACTOR.FALSE_EXTERNAL_JOIN" -> actor False_external_join
  | "MUT.ACTOR.DROP_CLEANUP_OWNER" -> actor Drop_cleanup_owner
  | "MUT.ACTOR.ABANDON_ENQUEUE_FAILURE" -> actor Abandon_enqueue_failure
  | "MUT.ACTOR.ABANDON_FAILURE_DRAIN" -> actor Abandon_failure_drain
  | _ -> Mutant_actor_space []

let mutation_for_statement_id = function
  | "MUT.STMT.DROP_KEEPALIVE" -> Some Drop_keepalive
  | "MUT.STMT.DISCARD_FINALIZE_FAILURE" -> Some Discard_finalize_failure
  | _ -> None

let mutation_for_close_v2_id = function
  | "MUT.CLOSE_V2.RETRY_DEFERRED" -> Some Retry_deferred_close_v2
  | "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE" -> Some Release_before_finalize
  | "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE" ->
      Some Discard_close_v2_finalize_failure
  | _ -> None

let mutation_for_actor_id = function
  | "MUT.ACTOR.IGNORE_BUSY" -> Some Ignore_busy
  | "MUT.ACTOR.CLOSE_BEFORE_JOIN" -> Some Close_before_join
  | "MUT.ACTOR.ABANDON_SPAWNED" -> Some Abandon_spawned
  | "MUT.ACTOR.DOUBLE_ELECT" -> Some Double_elect
  | "MUT.ACTOR.ADMIT_DURING_CLOSING" -> Some Admit_during_closing
  | "MUT.ACTOR.RESET_RETRY_BUDGET" -> Some Reset_retry_budget
  | "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE" -> Some Busy_without_quiescence
  | "MUT.ACTOR.REUSE_STALE_QUIESCENCE" -> Some Reuse_stale_quiescence
  | "MUT.ACTOR.RESET_GLOBAL_BUDGET" -> Some Reset_global_budget
  | "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT" -> Some Split_follower_receipt
  | "MUT.ACTOR.FALSE_EXTERNAL_JOIN" -> Some False_external_join
  | "MUT.ACTOR.DROP_CLEANUP_OWNER" -> Some Drop_cleanup_owner
  | "MUT.ACTOR.ABANDON_ENQUEUE_FAILURE" -> Some Abandon_enqueue_failure
  | "MUT.ACTOR.ABANDON_FAILURE_DRAIN" -> Some Abandon_failure_drain
  | _ -> None

let transition_edges ~terminal ~states ~events ~step =
  states
  |> List.mapi (fun source state ->
         if terminal state then []
         else
           events
           |> List.mapi (fun event_index event ->
                  match step state event with
                  | None -> None
                  | Some target ->
                      let target_index = index_of target states in
                      if target_index < 0 then
                        invalid_arg "transition target escaped its finite closure"
                      else Some (source, event_index, target_index))
           |> List.filter_map Fun.id)
  |> List.concat

type bfs_certificate = {
  certificate_depths : int list;
  certificate_parents : int list;
  certificate_parent_events : int list;
}

let validate_bfs_certificate ~state_count ~edges certificate =
  let depths = Array.of_list certificate.certificate_depths in
  let parents = Array.of_list certificate.certificate_parents in
  let parent_events = Array.of_list certificate.certificate_parent_events in
  Array.length depths = state_count
  && Array.length parents = state_count
  && Array.length parent_events = state_count
  && state_count > 0
  && depths.(0) = 0
  && parents.(0) = 0
  && List.for_all
       (fun (source, _, target) ->
         source >= 0 && source < state_count
         && target >= 0 && target < state_count)
       edges
  && let rec validate_state state =
       if state = state_count then true
       else if state = 0 then validate_state 1
       else
         let parent = parents.(state) in
         let event = parent_events.(state) in
         depths.(state) > 0
         && parent >= 0 && parent < state_count
         && depths.(parent) = depths.(state) - 1
         && List.mem (parent, event, state) edges
         && validate_state (state + 1)
     in
     validate_state 0

let make_bfs_certificate ~relation ~state_count edges =
  if state_count <= 0 then invalid_arg (relation ^ ": empty relation")
  else
    let adjacency = Array.make state_count [] in
    List.iter
      (fun (source, event, target) ->
        if source < 0 || source >= state_count || target < 0
           || target >= state_count
        then invalid_arg (relation ^ ": edge endpoint outside relation")
        else adjacency.(source) <- (target, event) :: adjacency.(source))
      edges;
    let depths = Array.make state_count (-1) in
    let parents = Array.make state_count (-1) in
    let parent_events = Array.make state_count (-1) in
    let frontier = Queue.create () in
    depths.(0) <- 0;
    parents.(0) <- 0;
    parent_events.(0) <- 0;
    Queue.add 0 frontier;
    while not (Queue.is_empty frontier) do
      let source = Queue.take frontier in
      List.iter
        (fun (target, event) ->
          if depths.(target) < 0 then begin
            depths.(target) <- depths.(source) + 1;
            parents.(target) <- source;
            parent_events.(target) <- event;
            Queue.add target frontier
          end)
        adjacency.(source)
    done;
    if Array.exists (fun value -> value < 0) depths then
      invalid_arg (relation ^ ": admitted state is unreachable from initial")
    else
      let certificate =
        { certificate_depths = Array.to_list depths;
          certificate_parents = Array.to_list parents;
          certificate_parent_events = Array.to_list parent_events }
      in
      if validate_bfs_certificate ~state_count ~edges certificate then certificate
      else invalid_arg (relation ^ ": invalid BFS certificate")

let certificate_diameter certificate =
  List.fold_left max 0 certificate.certificate_depths

type progress_certificate = {
  progress_edges : (int * int * int) list;
  progress_ranks : int list;
}

let terminal_has_named_ack state =
  match state.lifecycle, state.acknowledgement with
  | Closed, Success_ack -> true
  | Failed, Failure_ack detail -> String.trim detail <> ""
  | (Open | Closing | Closed | Failed), _ -> false

let expected_actor_progress_edges states =
  states
  |> List.mapi (fun source state ->
         if state.lifecycle <> Closing then []
         else
           progress_events
           |> List.filter_map (fun event ->
                  match actor_step state event with
                  | None -> None
                  | Some target ->
                      let target_index = index_of target states in
                      let event_index = index_of event actor_events in
                      if target_index < 0 || event_index < 0 then
                        invalid_arg
                          "actor progress transition escaped its finite authority"
                      else Some (source, event_index, target_index)))
  |> List.concat

let validate_progress_certificate ~states certificate =
  let state_count = List.length states in
  let ranks = Array.of_list certificate.progress_ranks in
  let expected_edges = expected_actor_progress_edges states in
  Array.length ranks = state_count
  && certificate.progress_edges = expected_edges
  && List.for_all
       (fun (source, event, target) ->
         source >= 0 && source < state_count
         && target >= 0 && target < state_count
         && event >= 0 && event < List.length actor_events
         && (List.nth states source).lifecycle = Closing
         && ranks.(target) >= 0
         && ranks.(source) > ranks.(target))
       certificate.progress_edges
  && let outgoing = Array.make state_count 0 in
     List.iter
       (fun (source, _, _) -> outgoing.(source) <- outgoing.(source) + 1)
       certificate.progress_edges;
     let rec validate_state state =
       if state = state_count then true
       else
         let actor = List.nth states state in
         let valid =
           match actor.lifecycle with
           | Open -> ranks.(state) = -1 && outgoing.(state) = 0
           | Closing -> ranks.(state) > 0 && outgoing.(state) > 0
           | Closed | Failed ->
               ranks.(state) = 0 && outgoing.(state) = 0
               && terminal_has_named_ack actor
         in
         valid && validate_state (state + 1)
     in
     validate_state 0

let make_progress_certificate states =
  let edges = expected_actor_progress_edges states in
  let state_count = List.length states in
  let successors = Array.make state_count [] in
  List.iter
    (fun (source, _, target) ->
      successors.(source) <- target :: successors.(source))
    edges;
  let marks = Array.make state_count 0 in
  let ranks = Array.make state_count (-2) in
  let rec rank state =
    match marks.(state) with
    | 2 -> ranks.(state)
    | 1 -> invalid_arg "actor progress relation contains a cycle"
    | _ ->
        marks.(state) <- 1;
        let actor = List.nth states state in
        let value =
          match actor.lifecycle with
          | Open -> -1
          | Closed | Failed ->
              if terminal_has_named_ack actor then 0
              else invalid_arg "terminal actor has no named acknowledgement"
          | Closing ->
              begin match successors.(state) with
              | [] -> invalid_arg "closing actor has no progress successor"
              | targets ->
                  let target_ranks = List.map rank targets in
                  if List.exists (fun target_rank -> target_rank < 0) target_ranks
                  then invalid_arg "closing actor progresses outside close authority"
                  else 1 + List.fold_left max 0 target_ranks
              end
        in
        ranks.(state) <- value;
        marks.(state) <- 2;
        value
  in
  List.iteri (fun state _ -> ignore (rank state)) states;
  let certificate =
    { progress_edges = edges; progress_ranks = Array.to_list ranks }
  in
  if validate_progress_certificate ~states certificate then certificate
  else invalid_arg "invalid actor progress certificate"

type cached_mutant_relation = {
  cached_mutant_id : string;
  cached_mutant_space : mutant_space;
  cached_mutant_edges : (int * int * int) list;
  cached_mutant_metric : relation_metric;
  cached_mutant_certificate : bfs_certificate;
}

type relational_campaign = {
  campaign_statements : statement_state list;
  campaign_statement_edges : (int * int * int) list;
  campaign_statement_metric : relation_metric;
  campaign_statement_certificate : bfs_certificate;
  campaign_close_v2_states : close_v2_state list;
  campaign_close_v2_edges : (int * int * int) list;
  campaign_close_v2_metric : relation_metric;
  campaign_close_v2_certificate : bfs_certificate;
  campaign_actors : actor_state list;
  campaign_actor_edges : (int * int * int) list;
  campaign_actor_metric : relation_metric;
  campaign_actor_certificate : bfs_certificate;
  campaign_actor_progress_certificate : progress_certificate;
  campaign_mutants : cached_mutant_relation list;
  campaign_transition_digest : string;
}

let mutant_edges id space =
  match space with
  | Mutant_statement_space states ->
      begin match mutation_for_statement_id id with
      | None -> []
      | Some mutation ->
          transition_edges ~terminal:(statement_mutant_violation id)
            ~states ~events:statement_events
            ~step:(mutant_statement_step mutation)
      end
  | Mutant_close_v2_space states ->
      begin match mutation_for_close_v2_id id with
      | None -> []
      | Some mutation ->
          transition_edges ~terminal:(close_v2_mutant_violation id)
            ~states ~events:close_v2_events
            ~step:(mutant_close_v2_step mutation)
      end
  | Mutant_actor_space states ->
      begin match mutation_for_actor_id id with
      | None -> []
      | Some mutation ->
          transition_edges ~terminal:(actor_mutant_violation id)
            ~states ~events:actor_events
            ~step:(mutant_actor_step mutation)
      end

let state_count_of_mutant_space = function
  | Mutant_statement_space states -> List.length states
  | Mutant_close_v2_space states -> List.length states
  | Mutant_actor_space states -> List.length states

let canonical_relation_rows ~relation_id ~node_name ~canonical_state
    ~event_name states edges =
  List.mapi
    (fun index state ->
      Printf.sprintf "%s:%s%d=%s" relation_id node_name index
        (canonical_state state))
    states
  @ List.map
      (fun (source, event, target) ->
        Printf.sprintf "%s:%s%d-%s-%s%d" relation_id node_name source
          (event_name event) node_name target)
      edges

let canonical_certificate_rows relation_id certificate =
  List.mapi
    (fun state parent ->
      let depth = List.nth certificate.certificate_depths state in
      let event = List.nth certificate.certificate_parent_events state in
      Printf.sprintf "%s:C%d=depth:%d,parent:%d,event:%d" relation_id state
        depth parent event)
    certificate.certificate_parents

let build_relational_campaign () =
  let metric relation_id state_count edges =
    let certificate =
      make_bfs_certificate ~relation:relation_id ~state_count edges
    in
    ({ relation_id; relation_states = state_count;
       relation_edges = List.length edges;
       relation_path_bound = certificate_diameter certificate }, certificate)
  in
  let statements = reachable_statements () in
  let statement_edges =
    transition_edges ~terminal:(fun _ -> false) ~states:statements
      ~events:statement_events ~step:statement_step
  in
  let statement_metric, statement_certificate =
    metric "real_statement" (List.length statements) statement_edges
  in
  let close_v2_states = reachable_close_v2 () in
  let close_v2_edges =
    transition_edges ~terminal:(fun _ -> false) ~states:close_v2_states
      ~events:close_v2_events ~step:close_v2_step
  in
  let close_v2_metric, close_v2_certificate =
    metric "real_close_v2" (List.length close_v2_states) close_v2_edges
  in
  let actors = reachable_actors () in
  let actor_edges =
    transition_edges ~terminal:(fun _ -> false) ~states:actors
      ~events:actor_events ~step:actor_step
  in
  let actor_metric, actor_certificate =
    metric "real_actor" (List.length actors) actor_edges
  in
  let actor_progress_certificate = make_progress_certificate actors in
  let mutants =
    List.map
      (fun id ->
        let space = mutant_space id in
        let edges = mutant_edges id space in
        let state_count = state_count_of_mutant_space space in
        let relation_metric, certificate = metric id state_count edges in
        { cached_mutant_id = id; cached_mutant_space = space;
          cached_mutant_edges = edges; cached_mutant_metric = relation_metric;
          cached_mutant_certificate = certificate })
      mutant_ids
  in
  let real_rows =
    canonical_relation_rows ~relation_id:"real_statement" ~node_name:"S"
      ~canonical_state:canonical_statement
      ~event_name:(fun index ->
        string_of_statement_event (List.nth statement_events index))
      statements statement_edges
    @ canonical_relation_rows ~relation_id:"real_close_v2" ~node_name:"V"
        ~canonical_state:canonical_close_v2
        ~event_name:(fun index ->
          string_of_close_v2_event (List.nth close_v2_events index))
        close_v2_states close_v2_edges
    @ canonical_relation_rows ~relation_id:"real_actor" ~node_name:"A"
        ~canonical_state:canonical_actor
        ~event_name:(fun index ->
          string_of_actor_event (List.nth actor_events index))
        actors actor_edges
    @ canonical_certificate_rows "real_statement" statement_certificate
    @ canonical_certificate_rows "real_close_v2" close_v2_certificate
    @ canonical_certificate_rows "real_actor" actor_certificate
    @ List.mapi
        (fun state rank ->
          Printf.sprintf "real_actor:P%d=rank:%d" state rank)
        actor_progress_certificate.progress_ranks
    @ List.map
        (fun (source, event, target) ->
          Printf.sprintf "real_actor:P%d-%s-P%d" source
            (string_of_actor_event (List.nth actor_events event)) target)
        actor_progress_certificate.progress_edges
    @ canonical_actor_sparse_rows "real_actor" actors
  in
  let mutant_rows =
    List.concat_map
      (fun cached ->
        let state_rows =
          match cached.cached_mutant_space with
        | Mutant_statement_space states ->
            canonical_relation_rows
              ~relation_id:cached.cached_mutant_id ~node_name:"S"
              ~canonical_state:canonical_statement
              ~event_name:(fun index ->
                string_of_statement_event (List.nth statement_events index))
              states cached.cached_mutant_edges
        | Mutant_close_v2_space states ->
            canonical_relation_rows
              ~relation_id:cached.cached_mutant_id ~node_name:"V"
              ~canonical_state:canonical_close_v2
              ~event_name:(fun index ->
                string_of_close_v2_event (List.nth close_v2_events index))
              states cached.cached_mutant_edges
        | Mutant_actor_space states ->
            canonical_relation_rows
              ~relation_id:cached.cached_mutant_id ~node_name:"A"
              ~canonical_state:canonical_actor
              ~event_name:(fun index ->
                string_of_actor_event (List.nth actor_events index))
              states cached.cached_mutant_edges
        in
        let sparse_rows =
          match cached.cached_mutant_space with
          | Mutant_actor_space states ->
              canonical_actor_sparse_rows cached.cached_mutant_id states
          | Mutant_statement_space _ | Mutant_close_v2_space _ -> []
        in
        state_rows
        @ canonical_certificate_rows cached.cached_mutant_id
            cached.cached_mutant_certificate
        @ sparse_rows)
      mutants
  in
  let digest =
    real_rows @ mutant_rows |> String.concat "\n"
    |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
  in
  { campaign_statements = statements;
    campaign_statement_edges = statement_edges;
    campaign_statement_metric = statement_metric;
    campaign_statement_certificate = statement_certificate;
    campaign_close_v2_states = close_v2_states;
    campaign_close_v2_edges = close_v2_edges;
    campaign_close_v2_metric = close_v2_metric;
    campaign_close_v2_certificate = close_v2_certificate;
    campaign_actors = actors;
    campaign_actor_edges = actor_edges;
    campaign_actor_metric = actor_metric;
    campaign_actor_certificate = actor_certificate;
    campaign_actor_progress_certificate = actor_progress_certificate;
    campaign_mutants = mutants;
    campaign_transition_digest = digest }

let relational_campaign_value = lazy (build_relational_campaign ())

let relational_campaign () = Lazy.force relational_campaign_value

let bfs_certificates_valid () =
  let campaign = relational_campaign () in
  validate_bfs_certificate
    ~state_count:(List.length campaign.campaign_statements)
    ~edges:campaign.campaign_statement_edges
    campaign.campaign_statement_certificate
  && validate_bfs_certificate
       ~state_count:(List.length campaign.campaign_close_v2_states)
       ~edges:campaign.campaign_close_v2_edges
       campaign.campaign_close_v2_certificate
  && validate_bfs_certificate
       ~state_count:(List.length campaign.campaign_actors)
       ~edges:campaign.campaign_actor_edges campaign.campaign_actor_certificate
  && List.for_all
       (fun cached ->
         validate_bfs_certificate
           ~state_count:(state_count_of_mutant_space cached.cached_mutant_space)
           ~edges:cached.cached_mutant_edges cached.cached_mutant_certificate)
       campaign.campaign_mutants

let replace_nth index replacement values =
  List.mapi (fun offset value -> if offset = index then replacement else value)
    values

let bfs_certificate_mutant_results () =
  let campaign = relational_campaign () in
  let certificate = campaign.campaign_actor_certificate in
  let edges = campaign.campaign_actor_edges in
  let state_count = List.length campaign.campaign_actors in
  if state_count < 2 then
    [ ("CERT.BROKEN_PARENT", false); ("CERT.MISSING_EDGE", false);
      ("CERT.MISSING_STATE", false); ("CERT.FALSE_DEPTH", false) ]
  else
    let parent = List.nth certificate.certificate_parents 1 in
    let event = List.nth certificate.certificate_parent_events 1 in
    let broken_parent =
      { certificate with
        certificate_parents =
          replace_nth 1 state_count certificate.certificate_parents }
    in
    let missing_state =
      { certificate_depths = List.tl certificate.certificate_depths;
        certificate_parents = List.tl certificate.certificate_parents;
        certificate_parent_events =
          List.tl certificate.certificate_parent_events }
    in
    let false_depth =
      { certificate with
        certificate_depths =
          replace_nth 1
            (List.nth certificate.certificate_depths 1 + 1)
            certificate.certificate_depths }
    in
    let missing_parent_edge =
      List.filter (fun edge -> edge <> (parent, event, 1)) edges
    in
    let rejected candidate_edges candidate_certificate =
      not
        (validate_bfs_certificate ~state_count ~edges:candidate_edges
           candidate_certificate)
    in
    [ ("CERT.BROKEN_PARENT", rejected edges broken_parent);
      ("CERT.MISSING_EDGE", rejected missing_parent_edge certificate);
      ("CERT.MISSING_STATE", rejected edges missing_state);
      ("CERT.FALSE_DEPTH", rejected edges false_depth) ]

let bfs_certificate_mutants_rejected () =
  List.for_all snd (bfs_certificate_mutant_results ())

let progress_certificate_valid () =
  let campaign = relational_campaign () in
  validate_progress_certificate ~states:campaign.campaign_actors
    campaign.campaign_actor_progress_certificate

let progress_certificate_mutant_results () =
  let campaign = relational_campaign () in
  let states = campaign.campaign_actors in
  let certificate = campaign.campaign_actor_progress_certificate in
  match certificate.progress_edges with
  | [] ->
      [ ("PROGRESS_CERT.BROKEN_RANK", false);
        ("PROGRESS_CERT.MISSING_EDGE", false);
        ("PROGRESS_CERT.CYCLE", false) ]
  | (source, event, target) :: remaining_edges ->
      let broken_rank =
        { certificate with
          progress_ranks =
            replace_nth source (List.nth certificate.progress_ranks target)
              certificate.progress_ranks }
      in
      let missing_edge =
        { certificate with progress_edges = remaining_edges }
      in
      let cycle =
        { certificate with
          progress_edges =
            (source, event, source) :: certificate.progress_edges }
      in
      let rejected candidate =
        not (validate_progress_certificate ~states candidate)
      in
      [ ("PROGRESS_CERT.BROKEN_RANK", rejected broken_rank);
        ("PROGRESS_CERT.MISSING_EDGE", rejected missing_edge);
        ("PROGRESS_CERT.CYCLE", rejected cycle) ]

let progress_certificate_mutants_rejected () =
  List.for_all snd (progress_certificate_mutant_results ())

let raw_cleanup_encodings_valid () =
  let campaign = relational_campaign () in
  let actor_relations =
    campaign.campaign_actors
    :: List.filter_map
         (fun cached ->
           match cached.cached_mutant_space with
           | Mutant_actor_space states -> Some states
           | Mutant_statement_space _ | Mutant_close_v2_space _ -> None)
         campaign.campaign_mutants
  in
  let saw_default = ref false in
  let saw_nondefault = ref false in
  let relation_valid states =
    actor_raw_cleanup_fields states
    |> List.for_all (fun (_, values) ->
           if List.exists (( = ) 0) values then saw_default := true;
           if List.exists (fun value -> value <> 0) values then
             saw_nondefault := true;
           let table = make_sparse_int_table ~default:0 values in
           validate_sparse_int_table ~values table)
  in
  List.for_all relation_valid actor_relations
  && !saw_default && !saw_nondefault

let raw_cleanup_encoding_mutant_results () =
  let campaign = relational_campaign () in
  let values =
    List.map
      (fun state -> int_of_cleanup state.cleanup_obligation)
      campaign.campaign_actors
  in
  let table = make_sparse_int_table ~default:0 values in
  match table.sparse_value_groups with
  | [] ->
      [ ("RAW_CLEANUP.OMITTED_NONZERO", false);
        ("RAW_CLEANUP.WRONG_DEFAULT", false);
        ("RAW_CLEANUP.WRONG_NONZERO", false) ]
  | (value, first :: remaining) :: rest ->
      let omitted_nonzero =
        { table with
          sparse_value_groups = (value, remaining) :: rest }
      in
      let wrong_default =
        { table with sparse_default = table.sparse_default + 1 }
      in
      let wrong_nonzero =
        { table with
          sparse_value_groups = (value + 17, first :: remaining) :: rest }
      in
      let rejected candidate =
        not (validate_sparse_int_table ~values candidate)
      in
      [ ("RAW_CLEANUP.OMITTED_NONZERO", rejected omitted_nonzero);
        ("RAW_CLEANUP.WRONG_DEFAULT", rejected wrong_default);
        ("RAW_CLEANUP.WRONG_NONZERO", rejected wrong_nonzero) ]
  | (_, []) :: _ ->
      [ ("RAW_CLEANUP.OMITTED_NONZERO", false);
        ("RAW_CLEANUP.WRONG_DEFAULT", false);
        ("RAW_CLEANUP.WRONG_NONZERO", false) ]

let raw_cleanup_encoding_mutants_rejected () =
  List.for_all snd (raw_cleanup_encoding_mutant_results ())

let transition_table_digest () =
  (relational_campaign ()).campaign_transition_digest

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let smt_symbol id =
  String.map
    (fun character -> match character with '.' | '-' -> '_' | other -> other)
    id

let actor_attribute_name prefix field =
  if String.equal prefix "" then "actor_" ^ field
  else prefix ^ "_actor_" ^ field

let emit_actor_cleanup_attributes buffer ~prefix states =
  List.iter
    (fun (field, values) ->
      emit_sparse_int_table buffer (actor_attribute_name prefix field)
        ~default:0 values)
    (actor_raw_cleanup_fields states)

let actor_attribute prefix field variable =
  Printf.sprintf "(%s %s)" (actor_attribute_name prefix field) variable

let actor_terminal_named_formula ~prefix variable =
  let lifecycle = actor_attribute prefix "lifecycle" variable in
  let ack = actor_attribute prefix "ack" variable in
  let failure_name_length =
    actor_attribute prefix "ack_failure_name_length" variable
  in
  Printf.sprintf
    "(or (and (= %s 2) (= %s 1)) (and (= %s 3) (= %s 2) (> %s 0)))"
    lifecycle ack lifecycle ack failure_name_length

let actor_cleanup_honesty_formula ~prefix variable =
  let lifecycle = actor_attribute prefix "lifecycle" variable in
  let database = actor_attribute prefix "database" variable in
  let writer = actor_attribute prefix "writer" variable in
  let origin = actor_attribute prefix "cleanup_origin" variable in
  let owner_kind = actor_attribute prefix "cleanup_owner_kind" variable in
  let owner_generation =
    actor_attribute prefix "cleanup_owner_generation" variable
  in
  let named_ack = actor_terminal_named_formula ~prefix variable in
  Printf.sprintf
    "(or (not (= %s 3)) (and %s (or (and (= %s 2) (or (= %s 0) (= %s 2)) (= %s 0) (= %s 0) (= %s 0)) (and (or (= %s 0) (= %s 1)) (= %s 0) (> %s 0) (= %s 1) (= %s 0)) (and (or (= %s 0) (= %s 1)) (= %s 1) (> %s 0) (= %s 2) (> %s 0)))))"
    lifecycle named_ack database writer writer origin owner_kind
    owner_generation database database writer origin owner_kind
    owner_generation database database writer origin owner_kind
    owner_generation

let emit_mutant_space buffer id space =
  let prefix = smt_symbol id in
  match space with
  | Mutant_statement_space states ->
      emit_int_table buffer (prefix ^ "_mut_trace_id")
        (List.init (List.length states) Fun.id);
      emit_int_table buffer (prefix ^ "_stmt_wrapper")
        (List.map (fun state -> int_of_wrapper state.wrapper) states);
      emit_int_table buffer (prefix ^ "_stmt_native")
        (List.map (fun state -> int_of_native state.native) states);
      emit_int_table buffer (prefix ^ "_stmt_runtime")
        (List.map (fun state -> int_of_runtime state.runtime) states);
      emit_int_table buffer (prefix ^ "_stmt_explicit")
        (List.map (fun state -> state.explicit_finalize_count) states);
      emit_int_table buffer (prefix ^ "_stmt_custom")
        (List.map (fun state -> state.custom_finalize_count) states);
      emit_int_table buffer (prefix ^ "_stmt_outcome")
        (List.map (fun state -> int_of_outcome state.outcome) states)
  | Mutant_close_v2_space states ->
      emit_int_table buffer (prefix ^ "_mut_trace_id")
        (List.init (List.length states) Fun.id);
      emit_int_table buffer (prefix ^ "_close_v2_release")
        (List.map (fun state -> int_of_close_v2_release state.close_v2_release) states);
      emit_int_table buffer (prefix ^ "_close_v2_retained")
        (List.map (fun state -> state.retained_statements) states);
      emit_int_table buffer (prefix ^ "_close_v2_terminal")
        (List.map (fun state -> if state.close_authority_terminal then 1 else 0) states);
      emit_int_table buffer (prefix ^ "_close_v2_calls")
        (List.map (fun state -> state.native_close_calls) states);
      emit_int_table buffer (prefix ^ "_close_v2_failure_observed")
        (List.map (fun state -> if state.finalize_failure_observed then 1 else 0) states);
      emit_int_table buffer (prefix ^ "_close_v2_failure_reported")
        (List.map (fun state -> if state.finalize_failure_reported then 1 else 0) states)
  | Mutant_actor_space states ->
      emit_int_table buffer (prefix ^ "_mut_trace_id")
        (List.init (List.length states) Fun.id);
      emit_int_table buffer (prefix ^ "_actor_lifecycle")
        (List.map (fun state -> int_of_lifecycle state.lifecycle) states);
      emit_int_table buffer (prefix ^ "_actor_database")
        (List.map (fun state -> int_of_database state.database) states);
      emit_int_table buffer (prefix ^ "_actor_writer")
        (List.map (fun state -> int_of_writer state.writer) states);
      emit_int_table buffer (prefix ^ "_actor_ack")
        (List.map (fun state -> int_of_ack state.acknowledgement) states);
      emit_int_table buffer (prefix ^ "_actor_attempts")
        (List.map (fun state -> state.close_attempts) states);
      emit_int_table buffer (prefix ^ "_actor_global_budget")
        (List.map (fun state -> state.remaining_global_budget) states);
      emit_int_table buffer (prefix ^ "_actor_owners")
        (List.map (fun state -> state.close_owner_count) states);
      emit_int_table buffer (prefix ^ "_actor_generation")
        (List.map (fun state -> state.elected_generation) states);
      emit_int_table buffer (prefix ^ "_actor_generation_epoch")
        (List.map (fun state -> state.generation_quiescence_epoch) states);
      emit_int_table buffer (prefix ^ "_actor_generation_freshness")
        (List.map
           (fun state ->
             int_of_quiescence_freshness state.generation_quiescence_freshness)
           states);
      emit_int_table buffer (prefix ^ "_actor_late")
        (List.map (fun state -> state.late_admissions) states);
      emit_int_table buffer (prefix ^ "_actor_resets")
        (List.map (fun state -> state.retry_budget_resets) states);
      emit_int_table buffer (prefix ^ "_actor_followers_waiting")
        (List.map (fun state -> state.followers_waiting) states);
      emit_int_table buffer (prefix ^ "_actor_follower_ack")
        (List.map (fun state -> int_of_ack state.follower_acknowledgement) states);
      emit_int_table buffer (prefix ^ "_actor_external_join")
        (List.map (fun state -> if state.external_join_observed then 1 else 0) states);
      emit_int_table buffer (prefix ^ "_actor_writer_terminal")
        (List.map (fun state -> if state.writer_terminal then 1 else 0) states);
      emit_actor_cleanup_attributes buffer ~prefix states

let domain variable count =
  List.init count (fun index -> Printf.sprintf "(= %s %d)" variable index)
  |> String.concat " " |> Printf.sprintf "(or %s)"

let disjunction = function
  | [] -> "false"
  | [ clause ] -> clause
  | clauses -> "(or " ^ String.concat " " clauses ^ ")"

let emit_transition_relation buffer ~prefix edges =
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_initial ((state Int)) Bool (= state 0))\n" prefix);
  let clauses =
    List.map
      (fun (source, event, target) ->
        Printf.sprintf
          "(and (= source %d) (= event %d) (= target %d))"
          source event target)
      edges
  in
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_edge ((source Int) (event Int) (target Int)) Bool %s)\n"
       prefix (disjunction clauses));
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_next ((source Int) (event Int) (target Int)) Bool (%s_edge source event target))\n"
       prefix prefix)

let emit_actor_progress_certificate buffer ~prefix ~states certificate =
  if not (validate_progress_certificate ~states certificate) then
    invalid_arg (prefix ^ ": invalid progress certificate");
  let edge_clauses =
    List.map
      (fun (source, event, target) ->
        Printf.sprintf
          "(and (= source %d) (= event %d) (= target %d))"
          source event target)
      certificate.progress_edges
  in
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_progress_edge ((source Int) (event Int) (target Int)) Bool (and (%s_next source event target) %s))\n"
       prefix prefix (disjunction edge_clauses));
  emit_int_table buffer (prefix ^ "_progress_rank")
    certificate.progress_ranks;
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_terminal_named ((state Int)) Bool %s)\n"
       prefix (actor_terminal_named_formula ~prefix:"" "state"));
  let successor_clauses =
    List.map
      (fun (source, event, target) ->
        Printf.sprintf
          "(and (= state %d) (%s_progress_edge %d %d %d))"
          source prefix source event target)
      certificate.progress_edges
  in
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_progress_has_successor ((state Int)) Bool %s)\n"
       prefix (disjunction successor_clauses));
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_progress_certified ((state Int)) Bool (and %s (or (and (= (actor_lifecycle state) 0) (= (%s_progress_rank state) (- 1))) (and (= (actor_lifecycle state) 1) (> (%s_progress_rank state) 0) (%s_progress_has_successor state)) (and (or (= (actor_lifecycle state) 2) (= (actor_lifecycle state) 3)) (= (%s_progress_rank state) 0) (%s_terminal_named state)))))\n"
       prefix (domain "state" (List.length states)) prefix prefix prefix prefix
       prefix);
  List.iter
    (fun (source, event, target) ->
      Buffer.add_string buffer
        (Printf.sprintf
           "(assert (and (%s_progress_edge %d %d %d) (> (%s_progress_rank %d) (%s_progress_rank %d))))\n"
           prefix source event target prefix source prefix target))
    certificate.progress_edges;
  List.iteri
    (fun state _ ->
      Buffer.add_string buffer
        (Printf.sprintf "(assert (%s_progress_certified %d))\n" prefix state))
    states

let emit_bfs_certificate buffer ~prefix ~state_count certificate =
  emit_int_table buffer (prefix ^ "_bfs_depth") certificate.certificate_depths;
  emit_int_table buffer (prefix ^ "_bfs_parent") certificate.certificate_parents;
  emit_int_table buffer (prefix ^ "_bfs_parent_event")
    certificate.certificate_parent_events;
  Buffer.add_string buffer
    (Printf.sprintf
       "(assert (and (%s_initial 0) (= (%s_bfs_depth 0) 0)))\n"
       prefix prefix);
  List.iteri
    (fun state parent ->
      if state > 0 then
        let event = List.nth certificate.certificate_parent_events state in
        Buffer.add_string buffer
          (Printf.sprintf
             "(assert (and (%s_next %d %d %d) (= (%s_bfs_depth %d) (+ (%s_bfs_depth %d) 1))))\n"
             prefix parent event state prefix state prefix parent))
    certificate.certificate_parents;
  Buffer.add_string buffer
    (Printf.sprintf
       "(define-fun %s_certified_reachable ((state Int)) Bool (and %s (<= 0 (%s_bfs_depth state))))\n"
       prefix (domain "state" state_count) prefix)

let mutant_prefixes_closed report =
  let closed states edges terminal =
    let state_count = List.length states in
    state_count > 0
    && List.exists terminal states
    && List.for_all
         (fun (source, _, target) ->
           source >= 0 && source < state_count
           && target >= 0 && target < state_count
           && not (terminal (List.nth states source)))
         edges
  in
  let inspect id space edges =
    match space with
    | Mutant_statement_space states ->
        closed states edges (statement_mutant_violation id)
    | Mutant_close_v2_space states ->
        closed states edges (close_v2_mutant_violation id)
    | Mutant_actor_space states ->
        closed states edges (actor_mutant_violation id)
  in
  let report_ids =
    List.map (fun (mutant : mutant_result) -> mutant.id) report.mutants
  in
  let cached = (relational_campaign ()).campaign_mutants in
  report_ids = List.map (fun item -> item.cached_mutant_id) cached
  && List.for_all
       (fun item ->
         inspect item.cached_mutant_id item.cached_mutant_space
           item.cached_mutant_edges)
       cached

let mutant_formula id space =
  let prefix = smt_symbol id in
  let count =
    match space with
    | Mutant_statement_space states -> List.length states
    | Mutant_close_v2_space states -> List.length states
    | Mutant_actor_space states -> List.length states
  in
  let selected predicate = Printf.sprintf "(and %s %s)" (domain "m" count) predicate in
  match id with
  | "MUT.STMT.DROP_KEEPALIVE" ->
      selected
        (Printf.sprintf "(> (+ (%s_stmt_explicit m) (%s_stmt_custom m)) 1)"
           prefix prefix)
  | "MUT.STMT.DISCARD_FINALIZE_FAILURE" ->
      selected
        (Printf.sprintf
           "(and (= (%s_stmt_native m) 2) (= (%s_stmt_explicit m) 1) (= (%s_stmt_outcome m) 0))"
           prefix prefix prefix)
  | "MUT.CLOSE_V2.RETRY_DEFERRED" ->
      selected (Printf.sprintf "(> (%s_close_v2_calls m) 1)" prefix)
  | "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE" ->
      selected
        (Printf.sprintf
           "(and (= (%s_close_v2_release m) 2) (> (%s_close_v2_retained m) 0))"
           prefix prefix)
  | "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE" ->
      selected
        (Printf.sprintf
           "(and (= (%s_close_v2_failure_observed m) 1) (or (= (%s_close_v2_failure_reported m) 0) (= (%s_close_v2_release m) 2)))"
           prefix prefix prefix)
  | "MUT.ACTOR.IGNORE_BUSY" ->
      selected
        (Printf.sprintf
           "(and (= (%s_actor_lifecycle m) 2) (not (= (%s_actor_database m) 2)))"
           prefix prefix)
  | "MUT.ACTOR.CLOSE_BEFORE_JOIN" ->
      selected
        (Printf.sprintf
           "(and (= (%s_actor_lifecycle m) 2) (not (= (%s_actor_writer m) 2)))"
           prefix prefix)
  | "MUT.ACTOR.ABANDON_SPAWNED" | "MUT.ACTOR.ABANDON_ENQUEUE_FAILURE"
  | "MUT.ACTOR.ABANDON_FAILURE_DRAIN" ->
      selected
        (Printf.sprintf
           "(and (= (%s_actor_lifecycle m) 3) (not %s))"
           prefix (actor_cleanup_honesty_formula ~prefix "m"))
  | "MUT.ACTOR.DOUBLE_ELECT" ->
      selected (Printf.sprintf "(> (%s_actor_owners m) 1)" prefix)
  | "MUT.ACTOR.ADMIT_DURING_CLOSING" ->
      selected (Printf.sprintf "(> (%s_actor_late m) 0)" prefix)
  | "MUT.ACTOR.RESET_RETRY_BUDGET" ->
      selected
        (Printf.sprintf "(and (> (%s_actor_resets m) 0) (>= (%s_actor_attempts m) 3))"
           prefix prefix)
  | "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE" ->
      selected
        (Printf.sprintf
           "(and (> (%s_actor_attempts m) 0) (= (%s_actor_generation_epoch m) 0))"
           prefix prefix)
  | "MUT.ACTOR.REUSE_STALE_QUIESCENCE" ->
      selected
        (Printf.sprintf
           "(and (> (%s_actor_generation m) 1) (= (%s_actor_generation_freshness m) 2))"
           prefix prefix)
  | "MUT.ACTOR.RESET_GLOBAL_BUDGET" ->
      selected
        (Printf.sprintf
           "(> (+ (%s_actor_global_budget m) (%s_actor_attempts m)) 3)"
           prefix prefix)
  | "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT" ->
      selected
        (Printf.sprintf
           "(and (> (%s_actor_followers_waiting m) 0) (not (= (%s_actor_follower_ack m) (%s_actor_ack m))))"
           prefix prefix prefix)
  | "MUT.ACTOR.FALSE_EXTERNAL_JOIN" ->
      selected
        (Printf.sprintf
           "(and (= (%s_actor_external_join m) 1) (= (%s_actor_writer_terminal m) 0))"
           prefix prefix)
  | "MUT.ACTOR.DROP_CLEANUP_OWNER" ->
      selected
        (Printf.sprintf
           "(and (= (%s_actor_lifecycle m) 3) (not (= (%s_actor_database m) 2)) (not %s))"
           prefix prefix (actor_cleanup_honesty_formula ~prefix "m"))
  | _ -> "false"

let theorem_formula id statement_count close_v2_count actor_count =
  let stmt predicate =
    Printf.sprintf "(and %s %s)" (domain "s" statement_count) predicate
  in
  let actor predicate =
    Printf.sprintf "(and %s %s)" (domain "a" actor_count) predicate
  in
  let close_v2 predicate =
    Printf.sprintf "(and %s %s)" (domain "v" close_v2_count) predicate
  in
  match id with
  | "SQL.STMT.NO_DOUBLE_FINALIZE" ->
      stmt "(> (+ (stmt_explicit s) (stmt_custom s)) 1)"
  | "SQL.STMT.KEEPALIVE" ->
      stmt
        "(and (= (stmt_native s) 1) (= (stmt_runtime s) 1) (= (stmt_explicit s) 1) (or (not (= (stmt_wrapper s) 0)) (not (= (stmt_custom s) 0))))"
  | "SQL.STMT.EXPLICIT_TOTAL" ->
      stmt
        "(and (= (stmt_outcome s) 1) (= (stmt_explicit s) 1) (or (not (= (stmt_native s) 2)) (not (= (stmt_runtime s) 0)) (not (= (+ (stmt_explicit s) (stmt_custom s)) 1))))"
  | "SQL.STMT.FINALIZE_FAILURE_REPORTED" ->
      stmt
        "(and (= (stmt_native s) 2) (= (stmt_explicit s) 1) (= (stmt_outcome s) 0))"
  | "SQL.CLOSE_V2.TERMINAL_ON_ACCEPT" ->
      close_v2
        "(and (> (close_v2_calls v) 0) (or (= (close_v2_terminal v) 0) (not (= (close_v2_calls v) 1))))"
  | "SQL.CLOSE_V2.PHYSICAL_AFTER_FINALIZE" ->
      close_v2
        "(and (= (close_v2_release v) 2) (or (not (= (close_v2_retained v) 0)) (= (close_v2_terminal v) 0)))"
  | "SQL.CLOSE_V2.FINALIZE_FAILURE_TYPED" ->
      close_v2
        "(and (= (close_v2_failure_observed v) 1) (or (= (close_v2_failure_reported v) 0) (= (close_v2_release v) 2)))"
  | "SQL.ACTOR.CLOSED_OWNS_NOTHING" ->
      actor
        "(and (= (actor_lifecycle a) 2) (or (not (= (actor_database a) 2)) (not (= (actor_writer a) 2)) (not (= (actor_ack a) 1))))"
  | "SQL.ACTOR.BUSY_NOT_SUCCESS" ->
      actor "(and (= (actor_database a) 1) (= (actor_ack a) 1))"
  | "SQL.ACTOR.EXHAUSTION_FAILS_NAMED" ->
      actor
        "(and (= (actor_generation_budget a) 0) (= (actor_database a) 1) (> (actor_generation a) 0) (or (not (= (actor_lifecycle a) 3)) (not (= (actor_ack a) 2))))"
  | "SQL.ACTOR.ONE_CLOSE_OWNER" -> actor "(> (actor_owners a) 1)"
  | "SQL.ACTOR.SUCCESS_DRAINS" ->
      actor
        "(and (= (actor_lifecycle a) 2) (not (= (actor_admitted a) (actor_results a))))"
  | "SQL.ACTOR.SETUP_OWNERSHIP" | "SQL.ACTOR.FAILURE_CLEANUP_TRACKED" ->
      actor
        (Printf.sprintf "(and (= (actor_lifecycle a) 3) (not %s))"
           (actor_cleanup_honesty_formula ~prefix:"" "a"))
  | "SQL.ACTOR.NO_ADMIT_AFTER_CLOSE" -> actor "(> (actor_late a) 0)"
  | "SQL.ACTOR.BOUNDED_TERMINAL" ->
      actor
        (Printf.sprintf
           "(or (and (or (= (actor_lifecycle a) 2) (= (actor_lifecycle a) 3)) (not %s)) (and (= (actor_lifecycle a) 1) (not (real_actor_progress_certified a))))"
           (actor_terminal_named_formula ~prefix:"" "a"))
  | "SQL.ACTOR.NO_LOST_RESULTS" ->
      actor
        "(or (> (actor_results a) (actor_admitted a)) (not (= (+ (actor_current a) (actor_queued a) (actor_results a)) (actor_admitted a))))"
  | "SQL.ACTOR.QUIESCENCE_AUTHORIZED" ->
      actor
        "(and (> (actor_generation a) 0) (or (<= (actor_generation_epoch a) 0) (and (= (actor_lifecycle a) 1) (not (= (actor_authorized_epoch a) (actor_generation_epoch a))))))"
  | "SQL.ACTOR.FRESH_QUIESCENCE_EPOCH" ->
      actor
        "(and (> (actor_generation a) 0) (not (= (actor_generation_freshness a) 1)))"
  | "SQL.ACTOR.GLOBAL_BUDGET_MONOTONE" ->
      actor
        "(or (< (actor_global_budget a) 0) (> (actor_global_budget a) 3) (not (= (+ (actor_global_budget a) (actor_attempts a)) 3)) (< (actor_generation_budget a) 0) (> (actor_generation_budget a) 1))"
  | "SQL.ACTOR.GENERATION_RECEIPT" ->
      actor
        "(and (> (actor_generation a) 0) (or (= (actor_lifecycle a) 2) (= (actor_lifecycle a) 3)) (not (= (actor_generation_receipt a) (actor_generation a))))"
  | "SQL.ACTOR.FOLLOWERS_SAME_RECEIPT" ->
      actor
        "(and (> (actor_generation a) 0) (or (= (actor_lifecycle a) 2) (= (actor_lifecycle a) 3)) (or (not (= (actor_followers_receipted a) (actor_followers_waiting a))) (and (= (actor_followers_waiting a) 0) (not (= (actor_follower_ack a) 0))) (and (> (actor_followers_waiting a) 0) (not (= (actor_follower_ack a) (actor_ack a))))))"
  | "SQL.ACTOR.WRITER_TERMINAL_JOIN" ->
      actor
        "(and (= (actor_lifecycle a) 2) (or (not (= (actor_writer_terminal a) 1)) (not (= (actor_external_join a) 1)) (not (= (actor_writer a) 2)) (not (= (actor_writer_terminal_receipt a) 1))))"
  | "SQL.ACTOR.CLEANUP_OWNER_REACHABLE" ->
      actor
        (Printf.sprintf
           "(and (= (actor_lifecycle a) 3) (not (= (actor_database a) 2)) (not %s))"
           (actor_cleanup_honesty_formula ~prefix:"" "a"))
  | "SQL.ACTOR.PROGRESS_TOTAL" ->
      actor
        "(and (= (actor_lifecycle a) 1) (not (real_actor_progress_certified a)))"
  | _ -> "false"

let premise_formula id statement_count close_v2_count actor_count =
  let stmt predicate =
    Printf.sprintf "(and %s %s)" (domain "s" statement_count) predicate
  in
  let actor predicate =
    Printf.sprintf "(and %s %s)" (domain "a" actor_count) predicate
  in
  let close_v2 predicate =
    Printf.sprintf "(and %s %s)" (domain "v" close_v2_count) predicate
  in
  match id with
  | "SQL.STMT.NO_DOUBLE_FINALIZE" ->
      stmt "(> (+ (stmt_explicit s) (stmt_custom s)) 0)"
  | "SQL.STMT.KEEPALIVE" ->
      stmt "(and (= (stmt_native s) 1) (= (stmt_explicit s) 1))"
  | "SQL.STMT.EXPLICIT_TOTAL" -> stmt "(= (stmt_outcome s) 1)"
  | "SQL.STMT.FINALIZE_FAILURE_REPORTED" ->
      stmt "(and (= (stmt_explicit s) 1) (= (stmt_native s) 2))"
  | "SQL.CLOSE_V2.TERMINAL_ON_ACCEPT" ->
      close_v2 "(> (close_v2_calls v) 0)"
  | "SQL.CLOSE_V2.PHYSICAL_AFTER_FINALIZE" ->
      close_v2 "(= (close_v2_release v) 2)"
  | "SQL.CLOSE_V2.FINALIZE_FAILURE_TYPED" ->
      close_v2 "(= (close_v2_failure_observed v) 1)"
  | "SQL.ACTOR.CLOSED_OWNS_NOTHING" | "SQL.ACTOR.SUCCESS_DRAINS"
  | "SQL.ACTOR.WRITER_TERMINAL_JOIN" ->
      actor "(= (actor_lifecycle a) 2)"
  | "SQL.ACTOR.BUSY_NOT_SUCCESS" | "SQL.ACTOR.EXHAUSTION_FAILS_NAMED" ->
      actor "(= (actor_database a) 1)"
  | "SQL.ACTOR.ONE_CLOSE_OWNER" | "SQL.ACTOR.NO_ADMIT_AFTER_CLOSE"
  | "SQL.ACTOR.PROGRESS_TOTAL" -> actor "(= (actor_lifecycle a) 1)"
  | "SQL.ACTOR.SETUP_OWNERSHIP" | "SQL.ACTOR.FAILURE_CLEANUP_TRACKED" ->
      actor "(= (actor_lifecycle a) 3)"
  | "SQL.ACTOR.BOUNDED_TERMINAL" ->
      actor "(not (= (actor_lifecycle a) 0))"
  | "SQL.ACTOR.NO_LOST_RESULTS" -> actor "(> (actor_admitted a) 0)"
  | "SQL.ACTOR.QUIESCENCE_AUTHORIZED" ->
      actor "(> (actor_generation a) 0)"
  | "SQL.ACTOR.FRESH_QUIESCENCE_EPOCH" ->
      actor "(> (actor_generation a) 0)"
  | "SQL.ACTOR.GLOBAL_BUDGET_MONOTONE" ->
      actor "(> (actor_attempts a) 0)"
  | "SQL.ACTOR.GENERATION_RECEIPT" ->
      actor
        "(and (> (actor_generation a) 0) (or (= (actor_lifecycle a) 2) (= (actor_lifecycle a) 3)))"
  | "SQL.ACTOR.FOLLOWERS_SAME_RECEIPT" ->
      actor
        "(and (> (actor_followers_waiting a) 0) (or (= (actor_lifecycle a) 2) (= (actor_lifecycle a) 3)))"
  | "SQL.ACTOR.CLEANUP_OWNER_REACHABLE" ->
      actor
        "(and (= (actor_lifecycle a) 3) (not (= (actor_database a) 2)))"
  | _ -> "false"

let premise_subject id =
  let prefix = "CONTROL.PREMISE." in
  if String.starts_with ~prefix id then
    String.sub id (String.length prefix) (String.length id - String.length prefix)
  else id

let monolithic_smt2_with_metrics report =
  let campaign = relational_campaign () in
  let statements = campaign.campaign_statements in
  let close_v2_states = campaign.campaign_close_v2_states in
  let actors = campaign.campaign_actors in
  let statement_edges = campaign.campaign_statement_edges in
  let close_v2_edges = campaign.campaign_close_v2_edges in
  let actor_edges = campaign.campaign_actor_edges in
  let statement_path_bound =
    campaign.campaign_statement_metric.relation_path_bound
  in
  let close_v2_path_bound =
    campaign.campaign_close_v2_metric.relation_path_bound
  in
  let actor_path_bound = campaign.campaign_actor_metric.relation_path_bound in
  let buffer = Buffer.create 32_768 in
  Buffer.add_string buffer
    ";; Generated from Sqlite_lifecycle_model's finite transition tables.\n\
     ;; Theorem queries assert a negation: unsat means no modeled counterexample.\n\
     ;; Controls and mutant queries must be sat. This proves only this model,\n\
     ;; never native C or OCaml GC behaviour.\n(set-logic ALL)\n";
  let table_digest = transition_table_digest () in
  Buffer.add_string buffer
    (Printf.sprintf
       ";; transition-table-sha256:%s\n(declare-const transition_table_digest String)\n(assert (= transition_table_digest \"%s\"))\n"
       table_digest table_digest);
  emit_transition_relation buffer ~prefix:"real_statement"
    statement_edges;
  emit_transition_relation buffer ~prefix:"real_close_v2"
    close_v2_edges;
  emit_transition_relation buffer ~prefix:"real_actor"
    actor_edges;
  emit_int_table buffer "stmt_wrapper" (List.map (fun state -> int_of_wrapper state.wrapper) statements);
  emit_int_table buffer "stmt_native" (List.map (fun state -> int_of_native state.native) statements);
  emit_int_table buffer "stmt_runtime" (List.map (fun state -> int_of_runtime state.runtime) statements);
  emit_int_table buffer "stmt_explicit" (List.map (fun state -> state.explicit_finalize_count) statements);
  emit_int_table buffer "stmt_custom" (List.map (fun state -> state.custom_finalize_count) statements);
  emit_int_table buffer "stmt_outcome" (List.map (fun state -> int_of_outcome state.outcome) statements);
  emit_int_table buffer "close_v2_release"
    (List.map (fun state -> int_of_close_v2_release state.close_v2_release) close_v2_states);
  emit_int_table buffer "close_v2_retained"
    (List.map (fun state -> state.retained_statements) close_v2_states);
  emit_int_table buffer "close_v2_terminal"
    (List.map (fun state -> if state.close_authority_terminal then 1 else 0) close_v2_states);
  emit_int_table buffer "close_v2_calls"
    (List.map (fun state -> state.native_close_calls) close_v2_states);
  emit_int_table buffer "close_v2_failure_observed"
    (List.map (fun state -> if state.finalize_failure_observed then 1 else 0) close_v2_states);
  emit_int_table buffer "close_v2_failure_reported"
    (List.map (fun state -> if state.finalize_failure_reported then 1 else 0) close_v2_states);
  emit_int_table buffer "actor_lifecycle" (List.map (fun state -> int_of_lifecycle state.lifecycle) actors);
  emit_int_table buffer "actor_database" (List.map (fun state -> int_of_database state.database) actors);
  emit_int_table buffer "actor_writer" (List.map (fun state -> int_of_writer state.writer) actors);
  emit_int_table buffer "actor_ack" (List.map (fun state -> int_of_ack state.acknowledgement) actors);
  emit_int_table buffer "actor_attempts" (List.map (fun state -> state.close_attempts) actors);
  emit_int_table buffer "actor_global_budget" (List.map (fun state -> state.remaining_global_budget) actors);
  emit_int_table buffer "actor_generation_budget" (List.map (fun state -> state.remaining_generation_budget) actors);
  emit_int_table buffer "actor_owners" (List.map (fun state -> state.close_owner_count) actors);
  emit_int_table buffer "actor_generation" (List.map (fun state -> state.elected_generation) actors);
  emit_int_table buffer "actor_generation_epoch" (List.map (fun state -> state.generation_quiescence_epoch) actors);
  emit_int_table buffer "actor_generation_freshness"
    (List.map
       (fun state ->
         int_of_quiescence_freshness state.generation_quiescence_freshness)
       actors);
  emit_int_table buffer "actor_authorized_epoch" (List.map (fun state -> state.authorized_quiescence_epoch) actors);
  emit_int_table buffer "actor_generation_receipt" (List.map (fun state -> state.terminal_generation_receipt) actors);
  emit_int_table buffer "actor_writer_terminal_receipt" (List.map (fun state -> int_of_ack state.writer_terminal_receipt) actors);
  emit_int_table buffer "actor_writer_terminal" (List.map (fun state -> if state.writer_terminal then 1 else 0) actors);
  emit_int_table buffer "actor_external_join" (List.map (fun state -> if state.external_join_observed then 1 else 0) actors);
  emit_int_table buffer "actor_followers_waiting" (List.map (fun state -> state.followers_waiting) actors);
  emit_int_table buffer "actor_followers_receipted" (List.map (fun state -> state.followers_receipted) actors);
  emit_int_table buffer "actor_follower_ack" (List.map (fun state -> int_of_ack state.follower_acknowledgement) actors);
  emit_int_table buffer "actor_admitted" (List.map (fun state -> state.admitted) actors);
  emit_int_table buffer "actor_current" (List.map (fun state -> state.current) actors);
  emit_int_table buffer "actor_queued" (List.map (fun state -> state.queued) actors);
  emit_int_table buffer "actor_results" (List.map (fun state -> state.results) actors);
  emit_int_table buffer "actor_late" (List.map (fun state -> state.late_admissions) actors);
  emit_int_table buffer "actor_resets" (List.map (fun state -> state.retry_budget_resets) actors);
  emit_actor_cleanup_attributes buffer ~prefix:"" actors;
  emit_actor_progress_certificate buffer ~prefix:"real_actor" ~states:actors
    campaign.campaign_actor_progress_certificate;
  emit_bfs_certificate buffer ~prefix:"real_statement"
    ~state_count:(List.length statements)
    campaign.campaign_statement_certificate;
  Buffer.add_string buffer
    "(declare-const s Int)\n(assert (real_statement_certified_reachable s))\n";
  emit_bfs_certificate buffer ~prefix:"real_close_v2"
    ~state_count:(List.length close_v2_states)
    campaign.campaign_close_v2_certificate;
  Buffer.add_string buffer
    "(declare-const v Int)\n(assert (real_close_v2_certified_reachable v))\n";
  emit_bfs_certificate buffer ~prefix:"real_actor"
    ~state_count:(List.length actors) campaign.campaign_actor_certificate;
  Buffer.add_string buffer
    "(declare-const a Int)\n(assert (real_actor_certified_reachable a))\n";
  let report_mutant_ids =
    List.map (fun (mutant : mutant_result) -> mutant.id) report.mutants
  in
  if report_mutant_ids <> mutant_ids then
    invalid_arg "monolithic SMT report differs from canonical mutant manifest";
  let mutant_spaces =
    List.map
      (fun cached ->
        (cached.cached_mutant_id, cached.cached_mutant_space,
         cached.cached_mutant_edges, cached.cached_mutant_metric,
         cached.cached_mutant_certificate))
      campaign.campaign_mutants
  in
  let mutant_relation_metrics = ref [] in
  List.iter
    (fun (id, space, edges, metric, certificate) ->
      emit_mutant_space buffer id space;
      let prefix = smt_symbol id in
      emit_transition_relation buffer ~prefix edges;
      emit_bfs_certificate buffer ~prefix ~state_count:metric.relation_states
        certificate;
      mutant_relation_metrics :=
        metric
        :: !mutant_relation_metrics)
    mutant_spaces;
  List.iter
    (fun obligation ->
      Buffer.add_string buffer (Printf.sprintf "(echo \"%s\")\n(push)\n" obligation.id);
      begin match obligation.kind with
      | Theorem_negation ->
          Buffer.add_string buffer
            (Printf.sprintf "(assert %s)\n"
               (theorem_formula obligation.id (List.length statements)
                  (List.length close_v2_states) (List.length actors)))
      | Premise_control ->
          let subject = premise_subject obligation.id in
          Buffer.add_string buffer
            (Printf.sprintf "(assert %s)\n"
               (premise_formula subject (List.length statements)
                  (List.length close_v2_states) (List.length actors)))
      | Healthy_control ->
          if String.equal obligation.id "CONTROL.HEALTHY_STATEMENT" then begin
            Buffer.add_string buffer
              (Printf.sprintf
                 "(assert (and %s (= (stmt_native s) 2) (= (stmt_runtime s) 0) (= (stmt_explicit s) 1) (= (stmt_custom s) 0) (= (stmt_outcome s) 1)))\n"
                 (domain "s" (List.length statements)))
          end else if String.equal obligation.id "CONTROL.HEALTHY_CLOSE_V2" then begin
            Buffer.add_string buffer
              (Printf.sprintf
                 "(assert (and %s (= (close_v2_release v) 2) (= (close_v2_retained v) 0) (= (close_v2_terminal v) 1) (= (close_v2_calls v) 1)))\n"
                 (domain "v" (List.length close_v2_states)))
          end else begin
            Buffer.add_string buffer
              (Printf.sprintf
                 "(assert (and %s (= (actor_lifecycle a) 2) (= (actor_database a) 2) (= (actor_writer a) 2) (= (actor_ack a) 1) (= (actor_admitted a) (actor_results a))))\n"
                 (domain "a" (List.length actors)))
          end
      | Mutant_witness ->
          let _, space, _, _, _ =
            List.find
              (fun (id, _, _, _, _) -> String.equal id obligation.id)
              mutant_spaces
          in
          let prefix = smt_symbol obligation.id in
          Buffer.add_string buffer
            (Printf.sprintf
               "(declare-const m Int)\n(assert (%s_certified_reachable m))\n"
               prefix);
          Buffer.add_string buffer
            (Printf.sprintf
               "(assert (= (%s_mut_trace_id m) m))\n" prefix);
          Buffer.add_string buffer
            (Printf.sprintf "(assert %s)\n" (mutant_formula obligation.id space))
      end;
      Buffer.add_string buffer "(check-sat)\n(pop)\n")
    obligations;
  let script = Buffer.contents buffer in
  let maximum_script_bytes = 16 * 1024 * 1024 in
  let relations =
    [ { relation_id = "real_statement";
        relation_states = List.length statements;
        relation_edges = List.length statement_edges;
        relation_path_bound = statement_path_bound };
      { relation_id = "real_close_v2";
        relation_states = List.length close_v2_states;
        relation_edges = List.length close_v2_edges;
        relation_path_bound = close_v2_path_bound };
      { relation_id = "real_actor";
        relation_states = List.length actors;
        relation_edges = List.length actor_edges;
        relation_path_bound = actor_path_bound } ]
    @ List.rev !mutant_relation_metrics
  in
  let metrics =
    { script_bytes = String.length script;
      path_assertions =
        List.fold_left
          (fun total metric ->
            total + 1 + (3 * metric.relation_states))
          0 relations;
      obligation_count = List.length obligations;
      relations }
  in
  if metrics.script_bytes > maximum_script_bytes then
    raise
      (Smt_script_limit_exceeded
         (metrics.script_bytes, maximum_script_bytes));
  (script, metrics)

let monolithic_smt2 report = fst (monolithic_smt2_with_metrics report)

let obligation_relation_id (obligation : obligation) =
  match obligation.kind with
  | Mutant_witness -> obligation.id
  | Healthy_control ->
      if String.equal obligation.id "CONTROL.HEALTHY_STATEMENT" then
        "real_statement"
      else if String.equal obligation.id "CONTROL.HEALTHY_CLOSE_V2" then
        "real_close_v2"
      else "real_actor"
  | Theorem_negation | Premise_control ->
      let subject = premise_subject obligation.id in
      if String.starts_with ~prefix:"SQL.STMT." subject then "real_statement"
      else if String.starts_with ~prefix:"SQL.CLOSE_V2." subject then
        "real_close_v2"
      else "real_actor"

let obligations_for_relation relation_id =
  List.filter
    (fun (obligation : obligation) ->
      String.equal (obligation_relation_id obligation) relation_id)
    obligations

let batch_digest_slot = "__HERMES_BATCH_SHA256__"

let replace_all ~pattern ~replacement text =
  if String.equal pattern "" then invalid_arg "empty replacement pattern"
  else
    let pattern_length = String.length pattern in
    let text_length = String.length text in
    let buffer = Buffer.create text_length in
    let rec copy offset =
      if offset >= text_length then ()
      else if offset + pattern_length <= text_length
              && String.sub text offset pattern_length = pattern
      then begin
        Buffer.add_string buffer replacement;
        copy (offset + pattern_length)
      end else begin
        Buffer.add_char buffer text.[offset];
        copy (offset + 1)
      end
    in
    copy 0;
    Buffer.contents buffer

let count_occurrences ~pattern text =
  if String.equal pattern "" then 0
  else
    let pattern_length = String.length pattern in
    let text_length = String.length text in
    let rec count total offset =
      if offset + pattern_length > text_length then total
      else if String.sub text offset pattern_length = pattern then
        count (total + 1) (offset + pattern_length)
      else count total (offset + 1)
    in
    count 0 0

let digest_script_payload script =
  script |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let seal_batch_script payload =
  let digest = digest_script_payload payload in
  (digest, replace_all ~pattern:batch_digest_slot ~replacement:digest payload)

let emit_batch_header buffer ~table_digest ~batch_id ~digest =
  Buffer.add_string buffer
    ";; Deterministic SQLite lifecycle relation batch.\n\
     ;; This proves only the emitted finite model, never C or GC behaviour.\n\
     (set-logic ALL)\n";
  Buffer.add_string buffer
    (Printf.sprintf
       ";; transition-table-sha256:%s\n;; batch-id:%s\n;; batch-sha256:%s\n(declare-const transition_table_digest String)\n(assert (= transition_table_digest \"%s\"))\n(declare-const relation_batch_digest String)\n(assert (= relation_batch_digest \"%s\"))\n"
       table_digest batch_id digest table_digest digest)

let emit_statement_attributes buffer states =
  emit_int_table buffer "stmt_wrapper"
    (List.map (fun state -> int_of_wrapper state.wrapper) states);
  emit_int_table buffer "stmt_native"
    (List.map (fun state -> int_of_native state.native) states);
  emit_int_table buffer "stmt_runtime"
    (List.map (fun state -> int_of_runtime state.runtime) states);
  emit_int_table buffer "stmt_explicit"
    (List.map (fun state -> state.explicit_finalize_count) states);
  emit_int_table buffer "stmt_custom"
    (List.map (fun state -> state.custom_finalize_count) states);
  emit_int_table buffer "stmt_outcome"
    (List.map (fun state -> int_of_outcome state.outcome) states)

let emit_close_v2_attributes buffer states =
  emit_int_table buffer "close_v2_release"
    (List.map (fun state -> int_of_close_v2_release state.close_v2_release) states);
  emit_int_table buffer "close_v2_retained"
    (List.map (fun state -> state.retained_statements) states);
  emit_int_table buffer "close_v2_terminal"
    (List.map (fun state -> if state.close_authority_terminal then 1 else 0) states);
  emit_int_table buffer "close_v2_calls"
    (List.map (fun state -> state.native_close_calls) states);
  emit_int_table buffer "close_v2_failure_observed"
    (List.map (fun state -> if state.finalize_failure_observed then 1 else 0) states);
  emit_int_table buffer "close_v2_failure_reported"
    (List.map (fun state -> if state.finalize_failure_reported then 1 else 0) states)

let emit_actor_attributes buffer states =
  emit_int_table buffer "actor_lifecycle"
    (List.map (fun state -> int_of_lifecycle state.lifecycle) states);
  emit_int_table buffer "actor_database"
    (List.map (fun state -> int_of_database state.database) states);
  emit_int_table buffer "actor_writer"
    (List.map (fun state -> int_of_writer state.writer) states);
  emit_int_table buffer "actor_ack"
    (List.map (fun state -> int_of_ack state.acknowledgement) states);
  emit_int_table buffer "actor_attempts"
    (List.map (fun state -> state.close_attempts) states);
  emit_int_table buffer "actor_global_budget"
    (List.map (fun state -> state.remaining_global_budget) states);
  emit_int_table buffer "actor_generation_budget"
    (List.map (fun state -> state.remaining_generation_budget) states);
  emit_int_table buffer "actor_owners"
    (List.map (fun state -> state.close_owner_count) states);
  emit_int_table buffer "actor_generation"
    (List.map (fun state -> state.elected_generation) states);
  emit_int_table buffer "actor_generation_epoch"
    (List.map (fun state -> state.generation_quiescence_epoch) states);
  emit_int_table buffer "actor_generation_freshness"
    (List.map
       (fun state ->
         int_of_quiescence_freshness state.generation_quiescence_freshness)
       states);
  emit_int_table buffer "actor_authorized_epoch"
    (List.map (fun state -> state.authorized_quiescence_epoch) states);
  emit_int_table buffer "actor_generation_receipt"
    (List.map (fun state -> state.terminal_generation_receipt) states);
  emit_int_table buffer "actor_writer_terminal_receipt"
    (List.map (fun state -> int_of_ack state.writer_terminal_receipt) states);
  emit_int_table buffer "actor_writer_terminal"
    (List.map (fun state -> if state.writer_terminal then 1 else 0) states);
  emit_int_table buffer "actor_external_join"
    (List.map (fun state -> if state.external_join_observed then 1 else 0) states);
  emit_int_table buffer "actor_followers_waiting"
    (List.map (fun state -> state.followers_waiting) states);
  emit_int_table buffer "actor_followers_receipted"
    (List.map (fun state -> state.followers_receipted) states);
  emit_int_table buffer "actor_follower_ack"
    (List.map (fun state -> int_of_ack state.follower_acknowledgement) states);
  emit_int_table buffer "actor_admitted"
    (List.map (fun state -> state.admitted) states);
  emit_int_table buffer "actor_current"
    (List.map (fun state -> state.current) states);
  emit_int_table buffer "actor_queued"
    (List.map (fun state -> state.queued) states);
  emit_int_table buffer "actor_results"
    (List.map (fun state -> state.results) states);
  emit_int_table buffer "actor_late"
    (List.map (fun state -> state.late_admissions) states);
  emit_int_table buffer "actor_resets"
    (List.map (fun state -> state.retry_budget_resets) states);
  emit_actor_cleanup_attributes buffer ~prefix:"" states

let emit_real_obligation buffer ~statement_count ~close_v2_count ~actor_count
    obligation =
  Buffer.add_string buffer (Printf.sprintf "(echo \"%s\")\n(push)\n" obligation.id);
  begin match obligation.kind with
  | Theorem_negation ->
      Buffer.add_string buffer
        (Printf.sprintf "(assert %s)\n"
           (theorem_formula obligation.id statement_count close_v2_count
              actor_count))
  | Premise_control ->
      Buffer.add_string buffer
        (Printf.sprintf "(assert %s)\n"
           (premise_formula (premise_subject obligation.id) statement_count
              close_v2_count actor_count))
  | Healthy_control ->
      if String.equal obligation.id "CONTROL.HEALTHY_STATEMENT" then
        Buffer.add_string buffer
          (Printf.sprintf
             "(assert (and %s (= (stmt_native s) 2) (= (stmt_runtime s) 0) (= (stmt_explicit s) 1) (= (stmt_custom s) 0) (= (stmt_outcome s) 1)))\n"
             (domain "s" statement_count))
      else if String.equal obligation.id "CONTROL.HEALTHY_CLOSE_V2" then
        Buffer.add_string buffer
          (Printf.sprintf
             "(assert (and %s (= (close_v2_release v) 2) (= (close_v2_retained v) 0) (= (close_v2_terminal v) 1) (= (close_v2_calls v) 1)))\n"
             (domain "v" close_v2_count))
      else
        Buffer.add_string buffer
          (Printf.sprintf
             "(assert (and %s (= (actor_lifecycle a) 2) (= (actor_database a) 2) (= (actor_writer a) 2) (= (actor_ack a) 1) (= (actor_admitted a) (actor_results a))))\n"
             (domain "a" actor_count))
  | Mutant_witness -> invalid_arg "mutant obligation routed to real relation"
  end;
  Buffer.add_string buffer "(check-sat)\n(pop)\n"

let make_real_batch ~table_digest ~relation ~edges ~emit_attributes
    ~certificate ~endpoint_symbol ~statement_count ~close_v2_count ~actor_count
    obligations =
  let buffer = Buffer.create 65_536 in
  emit_batch_header buffer ~table_digest ~batch_id:relation.relation_id
    ~digest:batch_digest_slot;
  emit_transition_relation buffer ~prefix:relation.relation_id edges;
  emit_attributes buffer;
  emit_bfs_certificate buffer ~prefix:relation.relation_id
    ~state_count:relation.relation_states certificate;
  Buffer.add_string buffer
    (Printf.sprintf
       "(declare-const %s Int)\n(assert (%s_certified_reachable %s))\n"
       endpoint_symbol relation.relation_id endpoint_symbol);
  List.iter
    (emit_real_obligation buffer ~statement_count ~close_v2_count ~actor_count)
    obligations;
  let digest, script = seal_batch_script (Buffer.contents buffer) in
  { batch_id = relation.relation_id; batch_digest = digest;
    batch_obligations = obligations; batch_script = script;
    batch_relation = relation }

let make_mutant_batch ~table_digest ~relation ~edges ~certificate id space =
  let obligations = obligations_for_relation id in
  let buffer = Buffer.create 65_536 in
  let relation_buffer = Buffer.create 65_536 in
  emit_mutant_space relation_buffer id space;
  emit_transition_relation relation_buffer ~prefix:(smt_symbol id) edges;
  emit_batch_header buffer ~table_digest ~batch_id:id ~digest:batch_digest_slot;
  Buffer.add_buffer buffer relation_buffer;
  let prefix = smt_symbol id in
  emit_bfs_certificate buffer ~prefix ~state_count:relation.relation_states
    certificate;
  Buffer.add_string buffer
    (Printf.sprintf
       "(declare-const m Int)\n(assert (%s_certified_reachable m))\n"
       prefix);
  List.iter
    (fun (obligation : obligation) ->
      Buffer.add_string buffer
        (Printf.sprintf "(echo \"%s\")\n(push)\n" obligation.id);
      Buffer.add_string buffer
        (Printf.sprintf "(assert (= (%s_mut_trace_id m) m))\n" prefix);
      Buffer.add_string buffer
        (Printf.sprintf "(assert %s)\n" (mutant_formula id space));
      Buffer.add_string buffer "(check-sat)\n(pop)\n")
    obligations;
  let digest, script = seal_batch_script (Buffer.contents buffer) in
  { batch_id = id; batch_digest = digest; batch_obligations = obligations;
    batch_script = script; batch_relation = relation }

let build_smt_campaign () =
  let campaign = relational_campaign () in
  let statements = campaign.campaign_statements in
  let close_v2_states = campaign.campaign_close_v2_states in
  let actors = campaign.campaign_actors in
  let statement_edges = campaign.campaign_statement_edges in
  let close_v2_edges = campaign.campaign_close_v2_edges in
  let actor_edges = campaign.campaign_actor_edges in
  let statement_metric = campaign.campaign_statement_metric in
  let close_v2_metric = campaign.campaign_close_v2_metric in
  let actor_metric = campaign.campaign_actor_metric in
  let table_digest = campaign.campaign_transition_digest in
  let statement_batch =
    make_real_batch ~table_digest ~relation:statement_metric
      ~edges:statement_edges
      ~emit_attributes:(fun buffer -> emit_statement_attributes buffer statements)
      ~certificate:campaign.campaign_statement_certificate
      ~endpoint_symbol:"s"
      ~statement_count:(List.length statements)
      ~close_v2_count:(List.length close_v2_states)
      ~actor_count:(List.length actors)
      (obligations_for_relation "real_statement")
  in
  let close_v2_batch =
    make_real_batch ~table_digest ~relation:close_v2_metric
      ~edges:close_v2_edges
      ~emit_attributes:(fun buffer -> emit_close_v2_attributes buffer close_v2_states)
      ~certificate:campaign.campaign_close_v2_certificate
      ~endpoint_symbol:"v"
      ~statement_count:(List.length statements)
      ~close_v2_count:(List.length close_v2_states)
      ~actor_count:(List.length actors)
      (obligations_for_relation "real_close_v2")
  in
  let actor_batch =
    make_real_batch ~table_digest ~relation:actor_metric ~edges:actor_edges
      ~emit_attributes:(fun buffer ->
        emit_actor_attributes buffer actors;
        emit_actor_progress_certificate buffer ~prefix:"real_actor"
          ~states:actors campaign.campaign_actor_progress_certificate)
      ~certificate:campaign.campaign_actor_certificate ~endpoint_symbol:"a"
      ~statement_count:(List.length statements)
      ~close_v2_count:(List.length close_v2_states)
      ~actor_count:(List.length actors)
      (obligations_for_relation "real_actor")
  in
  let mutant_batches =
    List.map
      (fun cached ->
        make_mutant_batch ~table_digest
          ~relation:cached.cached_mutant_metric
          ~edges:cached.cached_mutant_edges
          ~certificate:cached.cached_mutant_certificate cached.cached_mutant_id
          cached.cached_mutant_space)
      campaign.campaign_mutants
  in
  let batches = statement_batch :: close_v2_batch :: actor_batch :: mutant_batches in
  let ordered_ids =
    List.concat_map
      (fun (batch : smt_batch) ->
        List.map
          (fun (obligation : obligation) -> obligation.id)
          batch.batch_obligations)
      batches
  in
  let canonical_ids =
    List.map (fun (obligation : obligation) -> obligation.id) obligations
  in
  if ordered_ids <> canonical_ids then
    invalid_arg "ordered SMT batch union differs from canonical obligation manifest";
  let unique_ids = List.sort_uniq String.compare ordered_ids in
  if List.length unique_ids <> List.length canonical_ids then
    invalid_arg "SMT batch union contains duplicate obligations";
  let relations =
    List.map (fun (batch : smt_batch) -> batch.batch_relation) batches
  in
  let metrics =
    { script_bytes =
        List.fold_left
          (fun total (batch : smt_batch) ->
            total + String.length batch.batch_script)
          0 batches;
      path_assertions =
        List.fold_left
          (fun total (relation : relation_metric) ->
            total + 1 + (3 * relation.relation_states))
          0 relations;
      obligation_count = List.length ordered_ids;
      relations }
  in
  let maximum_script_bytes = 16 * 1024 * 1024 in
  if metrics.script_bytes > maximum_script_bytes then
    raise
      (Smt_script_limit_exceeded
         (metrics.script_bytes, maximum_script_bytes));
  (batches, metrics)

let smt_campaign_value = lazy (build_smt_campaign ())

let smt_batches_with_metrics report =
  let report_mutant_ids =
    List.map (fun (mutant : mutant_result) -> mutant.id) report.mutants
  in
  if report_mutant_ids <> mutant_ids then
    invalid_arg "SMT campaign report differs from canonical mutant manifest"
  else Lazy.force smt_campaign_value

let validate_batch_output batch output =
  validate_obligation_output batch.batch_obligations output

let equal_smt_batch (left : smt_batch) (right : smt_batch) =
  String.equal left.batch_id right.batch_id
  && String.equal left.batch_digest right.batch_digest
  && left.batch_obligations = right.batch_obligations
  && String.equal left.batch_script right.batch_script
  && left.batch_relation = right.batch_relation

let batch_is_canonical (batch : smt_batch) =
  let canonical_batches, _ = Lazy.force smt_campaign_value in
  List.exists (equal_smt_batch batch) canonical_batches

let batch_manifest_complete batches =
  let contains text fragment =
    let text_length = String.length text in
    let fragment_length = String.length fragment in
    let rec search offset =
      offset + fragment_length <= text_length
      && (String.sub text offset fragment_length = fragment
          || search (offset + 1))
    in
    fragment_length = 0 || search 0
  in
  let ids =
    List.concat_map
      (fun (batch : smt_batch) ->
        List.map
          (fun (obligation : obligation) -> obligation.id)
          batch.batch_obligations)
      batches
  in
  let canonical_batch_ids =
    [ "real_statement"; "real_close_v2"; "real_actor" ] @ mutant_ids
  in
  let table_digest = transition_table_digest () in
  let canonical_batches, _ = Lazy.force smt_campaign_value in
  ids = List.map (fun (obligation : obligation) -> obligation.id) obligations
  && List.length (List.sort_uniq String.compare ids) = List.length obligations
  && List.map (fun (batch : smt_batch) -> batch.batch_id) batches
     = canonical_batch_ids
  && List.length batches = List.length canonical_batches
  && List.for_all2 equal_smt_batch batches canonical_batches
  && List.for_all
       (fun (batch : smt_batch) ->
         let expected_obligations = obligations_for_relation batch.batch_id in
         let normalized_script =
           replace_all ~pattern:batch.batch_digest
             ~replacement:batch_digest_slot batch.batch_script
         in
         batch.batch_relation.relation_id = batch.batch_id
         && batch.batch_obligations = expected_obligations
         && String.length batch.batch_digest = 64
         && count_occurrences ~pattern:batch.batch_digest batch.batch_script = 2
         && String.equal batch.batch_digest
              (digest_script_payload normalized_script)
         && String.length batch.batch_script > 0
         && contains batch.batch_script
              ("transition-table-sha256:" ^ table_digest)
         && contains batch.batch_script
              ("batch-id:" ^ batch.batch_id)
         && contains batch.batch_script
              ("batch-sha256:" ^ batch.batch_digest))
       batches

let smt2_with_metrics = monolithic_smt2_with_metrics

let smt2 = monolithic_smt2
