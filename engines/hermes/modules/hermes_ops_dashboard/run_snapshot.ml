type phase_state = Phase_not_started | Phase_active | Phase_complete
type suite_state = Suite_pending | Suite_active | Suite_terminal of Run_model.lifecycle
type attempt_state =
  | Attempt_ready
  | Attempt_running
  | Attempt_terminal of Run_model.lifecycle

type counts = {
  events : int;
  phases_started : int;
  phases_finished : int;
  suites_discovered : int;
  suites_started : int;
  suites_succeeded : int;
  suites_failed : int;
  diagnostics : int;
  receipts : int;
  residuals : int;
  attempts_ready : int;
  attempts_running : int;
  attempts_terminal : int;
}

module String_map = Map.Make (String)
module Int64_map = Map.Make (Int64)
module Phase_map = Map.Make (struct type t = Run_model.phase let compare = compare end)
module Attempt_map = Map.Make (struct type t = string * int let compare = compare end)

type t = {
  run_id_value : string;
  provenance_value : Run_model.provenance;
  lifecycle_value : Run_model.lifecycle;
  declared : bool;
  last_sequence_value : int64;
  last_digest_value : string option;
  event_digests : string String_map.t;
  sequence_digests : string Int64_map.t;
  phases : phase_state Phase_map.t;
  suites : suite_state String_map.t;
  attempts : attempt_state Attempt_map.t;
  counts_value : counts;
}

type summary = {
  run_id : string;
  lifecycle : Run_model.lifecycle;
  last_sequence : int64;
  last_digest : string option;
  source_revision : string;
  source_clean : bool;
  configuration_digest : string;
  authority_digest : string;
  executable_digest : string;
  terminal : bool;
  counts : counts;
}

type apply_result = Applied of t | Duplicate of t
  | Gap of { expected : int64; observed : int64 }

let ( let* ) value f = match value with Ok result -> f result | Error _ as error -> error

let first_sequence = 0L

let zero_counts = {
  events = 0; phases_started = 0; phases_finished = 0;
  suites_discovered = 0; suites_started = 0; suites_succeeded = 0;
  suites_failed = 0; diagnostics = 0; receipts = 0; residuals = 0;
  attempts_ready = 0; attempts_running = 0; attempts_terminal = 0;
}

let empty ~run_id ~provenance =
  let* () = Run_model.validate_head ~run_id ~provenance in
  Ok {
    run_id_value = run_id; provenance_value = provenance; lifecycle_value = Run_model.Declared;
    declared = false; last_sequence_value = Int64.pred first_sequence;
    last_digest_value = None; event_digests = String_map.empty;
    sequence_digests = Int64_map.empty; phases = Phase_map.empty;
    suites = String_map.empty; attempts = Attempt_map.empty; counts_value = zero_counts;
  }

let run_id t = t.run_id_value
let lifecycle t = t.lifecycle_value
let last_sequence t = t.last_sequence_value
let last_digest t = t.last_digest_value
let provenance t = t.provenance_value
let counts t = t.counts_value
let is_terminal t = t.declared && Run_model.terminal_lifecycle t.lifecycle_value

let phase_state t phase =
  match Phase_map.find_opt phase t.phases with Some state -> state | None -> Phase_not_started

let suite_state t suite = String_map.find_opt suite t.suites
let attempt_state t ~step ~attempt = Attempt_map.find_opt (step, attempt) t.attempts

let phase_predecessor = function
  | Run_model.Admission -> None
  | Authority_preflight -> Some Run_model.Admission
  | Discovery -> Some Run_model.Authority_preflight
  | Build -> Some Run_model.Discovery
  | Dispatch -> Some Run_model.Build
  | Suite_execution -> Some Run_model.Dispatch
  | Aggregation -> Some Run_model.Suite_execution
  | Completion_admission -> Some Run_model.Aggregation
  | Publication -> Some Run_model.Completion_admission

let phase_ready t phase =
  match phase_predecessor phase with
  | None -> true
  | Some predecessor -> phase_state t predecessor = Phase_complete

let summary t = {
  run_id = t.run_id_value; lifecycle = t.lifecycle_value;
  last_sequence = t.last_sequence_value; last_digest = t.last_digest_value;
  source_revision = t.provenance_value.source_revision;
  source_clean = t.provenance_value.source_clean;
  configuration_digest = t.provenance_value.configuration_digest;
  authority_digest = t.provenance_value.authority_digest;
  executable_digest = t.provenance_value.executable_digest;
  terminal = is_terminal t;
  counts = t.counts_value;
}

let lifecycle_from_payload payload =
  match payload with
  | `Assoc fields ->
      begin match List.assoc_opt "lifecycle" fields with
      | Some (`String value) ->
          begin match Run_model.lifecycle_of_string value with
          | Ok lifecycle when Run_model.terminal_lifecycle lifecycle -> Ok lifecycle
          | Ok _ -> Error "finished event lifecycle must be terminal"
          | Error _ as error -> error
          end
      | Some _ -> Error "finished event lifecycle must be a string"
      | None -> Error "finished event payload is missing lifecycle"
      end
  | _ -> Error "finished event payload must be an object"

let require_subject expected event =
  if expected event.Run_model.subject then Ok ()
  else Error "event kind and subject disagree"

let active_run t =
  match t.lifecycle_value with
  | Run_model.Running | Aggregating -> true
  | Declared | Admitted | Succeeded | Failed | Cancelled | Blocked | Unavailable -> false

let suite_execution_active t =
  phase_state t Run_model.Suite_execution = Phase_active

let all_suites_terminal t =
  String_map.for_all
    (fun _ state -> match state with Suite_terminal _ -> true | Suite_pending | Suite_active -> false)
    t.suites

let all_suites_succeeded t =
  String_map.for_all
    (fun _ state -> match state with Suite_terminal Run_model.Succeeded -> true | _ -> false)
    t.suites

let all_attempts_terminal t =
  Attempt_map.for_all
    (fun _ state -> match state with Attempt_terminal _ -> true | Attempt_ready | Attempt_running -> false)
    t.attempts

let all_attempts_succeeded t =
  Attempt_map.for_all
    (fun _ state -> match state with Attempt_terminal Run_model.Succeeded -> true | _ -> false)
    t.attempts

let swarm_execution_active t =
  phase_state t Run_model.Dispatch = Phase_active || suite_execution_active t

let transition t (event : Run_model.event) =
  if not t.declared then
    match event.kind, event.subject with
    | Run_model.Run_declared, Run_model.Run -> Ok { t with declared = true }
    | _ -> Error "first run event must declare the run"
  else
    match event.kind with
    | Run_model.Run_declared -> Error "run is already declared"
    | Run_started ->
        let* () = require_subject (function Run_model.Run -> true | _ -> false) event in
        if t.lifecycle_value = Admitted
           && phase_state t Run_model.Admission = Phase_complete
        then Ok { t with lifecycle_value = Running }
        else Error "run start requires completed Admission"
    | Run_finished ->
        let* () = require_subject (function Run_model.Run -> true | _ -> false) event in
        if phase_state t Run_model.Publication <> Phase_complete then
          Error "run finish requires completed Publication"
        else if active_run t then
          let* terminal = lifecycle_from_payload event.payload in
          if terminal = Run_model.Succeeded
             && (not (all_suites_succeeded t) || not (all_attempts_succeeded t))
          then
            Error "Succeeded requires every suite and admitted attempt to be terminal-Succeeded"
          else Ok { t with lifecycle_value = terminal }
        else Error "run finish is illegal before running"
    | Phase_started ->
        begin match event.subject with
        | Run_model.Phase phase ->
            if phase_state t phase <> Phase_not_started then Error "phase has already started"
            else if not (phase_ready t phase) then Error "phase predecessor is not complete"
            else
              begin match phase, t.lifecycle_value with
              | Admission, Declared ->
                  Ok { t with lifecycle_value = Admitted;
                              phases = Phase_map.add phase Phase_active t.phases }
              | Authority_preflight, Running
              | Discovery, Running
              | Build, Running
              | Dispatch, Running
              | Suite_execution, Running ->
                  Ok { t with phases = Phase_map.add phase Phase_active t.phases }
              | Aggregation, Running ->
                  Ok { t with lifecycle_value = Aggregating;
                              phases = Phase_map.add phase Phase_active t.phases }
              | Completion_admission, Aggregating
              | Publication, Aggregating ->
                  Ok { t with phases = Phase_map.add phase Phase_active t.phases }
              | _, (Succeeded | Failed | Cancelled | Blocked | Unavailable) ->
                  Error "terminal run cannot start a phase"
              | _ -> Error "phase is illegal in the current run lifecycle"
              end
        | _ -> Error "phase event requires a phase subject"
        end
    | Phase_finished ->
        begin match event.subject with
        | Run_model.Phase ((Run_model.Dispatch | Run_model.Suite_execution) as phase)
          when phase_state t phase = Phase_active && not (all_attempts_terminal t) ->
            Error "execution phase cannot finish before every admitted attempt is terminal"
        | Run_model.Phase Run_model.Suite_execution
          when phase_state t Run_model.Suite_execution = Phase_active
               && not (all_suites_terminal t) ->
            Error "Suite_execution cannot finish before every discovered suite is terminal"
        | Run_model.Phase phase when phase_state t phase = Phase_active ->
            Ok { t with phases = Phase_map.add phase Phase_complete t.phases }
        | Run_model.Phase _ -> Error "phase cannot finish unless active"
        | _ -> Error "phase event requires a phase subject"
        end
    | Suite_discovered ->
        begin match event.subject with
        | Run_model.Suite name when active_run t && suite_execution_active t ->
            if String_map.mem name t.suites then Error "suite is already discovered"
            else Ok { t with suites = String_map.add name Suite_pending t.suites }
        | Run_model.Suite _ -> Error "suite discovery requires active Suite_execution"
        | _ -> Error "suite event requires a suite subject"
        end
    | Suite_started ->
        begin match event.subject with
        | Run_model.Suite name when active_run t && suite_execution_active t ->
            begin match String_map.find_opt name t.suites with
            | Some Suite_pending -> Ok { t with suites = String_map.add name Suite_active t.suites }
            | Some Suite_active | Some (Suite_terminal _) -> Error "suite cannot start in its current state"
            | None -> Error "suite must be discovered before it starts"
            end
        | Run_model.Suite _ -> Error "suite start requires active Suite_execution"
        | _ -> Error "suite event requires a suite subject"
        end
    | Suite_finished ->
        begin match event.subject with
        | Run_model.Suite name when active_run t && suite_execution_active t ->
            begin match String_map.find_opt name t.suites with
            | Some Suite_active ->
                let* terminal = lifecycle_from_payload event.payload in
                Ok { t with suites = String_map.add name (Suite_terminal terminal) t.suites }
            | Some Suite_pending | Some (Suite_terminal _) -> Error "suite cannot finish in its current state"
            | None -> Error "suite must be discovered before it finishes"
            end
        | Run_model.Suite _ -> Error "suite finish requires active Suite_execution"
        | _ -> Error "suite event requires a suite subject"
        end
    | Swarm_step_ready | Swarm_step_running | Swarm_step_terminal ->
        begin match event.subject with
        | Run_model.Attempt (step, attempt) when active_run t && swarm_execution_active t ->
            let key = (step, attempt) in
            begin match event.kind, Attempt_map.find_opt key t.attempts with
            | Swarm_step_ready, None ->
                Ok { t with attempts = Attempt_map.add key Attempt_ready t.attempts }
            | Swarm_step_running, Some Attempt_ready ->
                Ok { t with attempts = Attempt_map.add key Attempt_running t.attempts }
            | Swarm_step_terminal, Some Attempt_running ->
                let* outcome = lifecycle_from_payload event.payload in
                Ok { t with attempts = Attempt_map.add key (Attempt_terminal outcome) t.attempts }
            | Swarm_step_ready, Some (Attempt_terminal _) ->
                Error "terminal swarm attempt absorbs reuse"
            | Swarm_step_ready, Some (Attempt_ready | Attempt_running) ->
                Error "swarm attempt is already admitted"
            | Swarm_step_running, (None | Some Attempt_running | Some (Attempt_terminal _)) ->
                Error "swarm attempt running requires exactly one ready transition"
            | Swarm_step_terminal, (None | Some Attempt_ready | Some (Attempt_terminal _)) ->
                Error "swarm attempt terminal requires exactly one running transition"
            | _ -> Error "invalid swarm attempt transition"
            end
        | Run_model.Attempt _ -> Error "swarm step requires active Dispatch or Suite_execution"
        | _ -> Error "swarm step event requires an attempt subject"
        end
    | Resource_sampled | Diagnostic_emitted | Safety_evaluated
    | Intelligence_evaluated | Analysis_recorded | Trace_recorded | Profile_recorded
    | Fast_path_selected | Command_observed | Receipt_admitted | Residual_recorded
    | Heartbeat -> Ok t

let increment_counts counts kind suite_terminal =
  let counts = { counts with events = counts.events + 1 } in
  match kind with
  | Run_model.Phase_started -> { counts with phases_started = counts.phases_started + 1 }
  | Phase_finished -> { counts with phases_finished = counts.phases_finished + 1 }
  | Suite_discovered -> { counts with suites_discovered = counts.suites_discovered + 1 }
  | Suite_started -> { counts with suites_started = counts.suites_started + 1 }
  | Suite_finished ->
      begin match suite_terminal with
      | Some Run_model.Succeeded -> { counts with suites_succeeded = counts.suites_succeeded + 1 }
      | Some (Failed | Cancelled | Blocked | Unavailable) ->
          { counts with suites_failed = counts.suites_failed + 1 }
      | Some (Declared | Admitted | Running | Aggregating) | None -> counts
      end
  | Diagnostic_emitted -> { counts with diagnostics = counts.diagnostics + 1 }
  | Receipt_admitted -> { counts with receipts = counts.receipts + 1 }
  | Residual_recorded -> { counts with residuals = counts.residuals + 1 }
  | Swarm_step_ready -> { counts with attempts_ready = counts.attempts_ready + 1 }
  | Swarm_step_running -> { counts with attempts_running = counts.attempts_running + 1 }
  | Swarm_step_terminal -> { counts with attempts_terminal = counts.attempts_terminal + 1 }
  | Run_declared | Run_started | Run_finished | Resource_sampled | Safety_evaluated | Intelligence_evaluated
  | Analysis_recorded | Trace_recorded | Profile_recorded | Fast_path_selected
  | Command_observed | Heartbeat -> counts

let apply t (event : Run_model.event) =
  if not (String.equal event.run_id t.run_id_value) then Error "event run_id disagrees with snapshot"
  else if not (Run_model.equal_provenance event.provenance t.provenance_value) then
    Error "event provenance disagrees with the exact snapshot head"
  else
    match String_map.find_opt event.event_id t.event_digests with
    | Some digest when String.equal digest event.digest -> Ok (Duplicate t)
    | Some _ -> Error ("divergent event replay: " ^ event.event_id)
    | None ->
        begin match Int64_map.find_opt event.sequence t.sequence_digests with
        | Some digest when not (String.equal digest event.digest) ->
            Error ("divergent sequence replay: " ^ Int64.to_string event.sequence)
        | Some _ -> Error ("sequence already has another event identity: " ^ Int64.to_string event.sequence)
        | None ->
            let expected = Int64.succ t.last_sequence_value in
            let order = Int64.compare event.sequence expected in
            if order > 0 then Ok (Gap { expected; observed = event.sequence })
            else if order < 0 then Error ("stale event sequence: " ^ Int64.to_string event.sequence)
            else
              let* () =
                if event.previous_digest = t.last_digest_value then Ok ()
                else Error "event previous_digest disagrees with snapshot head"
              in
              if is_terminal t then Error "terminal lifecycle absorbs new events"
              else
                let* transitioned = transition t event in
                let suite_terminal =
                  match event.kind, event.subject with
                  | Run_model.Suite_finished, Run_model.Suite name ->
                      begin match String_map.find_opt name transitioned.suites with
                      | Some (Suite_terminal lifecycle) -> Some lifecycle | _ -> None
                      end
                  | _ -> None
                in
                let next = {
                  transitioned with
                  last_sequence_value = event.sequence;
                  last_digest_value = Some event.digest;
                  event_digests = String_map.add event.event_id event.digest t.event_digests;
                  sequence_digests = Int64_map.add event.sequence event.digest t.sequence_digests;
                  counts_value = increment_counts t.counts_value event.kind suite_terminal;
                }
                in
                Ok (Applied next)
        end

let fold events =
  match events with
  | [] -> Error "cannot fold an empty run-event stream"
  | first :: _ ->
      let* initial = empty ~run_id:first.Run_model.run_id ~provenance:first.provenance in
      let rec loop snapshot = function
        | [] -> Ok snapshot
        | event :: rest ->
            begin match apply snapshot event with
            | Ok (Applied next) | Ok (Duplicate next) -> loop next rest
            | Ok (Gap { expected; observed }) ->
                Error (Printf.sprintf "event sequence gap: expected %Ld observed %Ld" expected observed)
            | Error _ as error -> error
            end
      in
      loop initial events
