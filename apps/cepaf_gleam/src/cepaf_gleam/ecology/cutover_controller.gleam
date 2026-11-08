//// Supervised interpretation of cutover_protocol with a real isolated native
//// file/checkpoint port. No ReleaseAuthority issuer exists here. Root adapters
//// must supply authentic current observations and actual reader/health effects.
//// The effect-time boundary is the final checked dispatch; OS scheduling and
//// physical fsync may cross lease expiry. Native same-UID/filesystem ownership
//// and bounded, BEAM-preemptible control adapters are explicit premises.
//// Control adapters must not trap exits or spawn untracked descendants.

import cepaf_gleam/ecology/cutover_protocol as p
import cepaf_gleam/ecology/cutover_transport as wire
import cepaf_gleam/harness/telegram_store_transport as framed
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/admission
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result

pub type ClockUnit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic(unit: ClockUnit) -> Int

@external(erlang, "erlang", "system_time")
fn host_utc(unit: ClockUnit) -> Int

pub fn monotonic_ms() -> Int {
  monotonic(Millisecond)
}

pub type Binding {
  Binding(
    transaction_id: String,
    candidate: String,
    previous_candidate: String,
    manifest: String,
    physical_count: Int,
    initial_epoch: Int,
    execution: p.ExecutionBinding,
  )
}

pub type Configuration {
  Configuration(
    binding: Binding,
    native: framed.LocalConfiguration,
    edits: List(wire.Edit),
    command_timeout_ms: Int,
  )
}

pub type CommandContext {
  CommandContext(
    transaction_id: String,
    candidate: String,
    previous_candidate: String,
    manifest: String,
    epoch: Int,
    generation: Int,
    physical_count: Int,
    command: p.Command,
    phase: p.Phase,
    family: String,
    execution: p.ExecutionBinding,
    native_configuration: framed.LocalConfiguration,
    deadline_monotonic_ms: Int,
  )
}

/// observed_utc_ms is the evidence's UTC timestamp, never the dispatch clock.
/// Existing admission/runtime lease fields are UTC milliseconds.
/// The command deadline is BEAM-local monotonic time and may be negative.
pub type LiveEvidence {
  LiveEvidence(
    context: admission.AdmissionContext,
    call: admission.ValidatedCall,
    task: Option(admission.TaskFence),
    runtime: p.RuntimeObservation,
    observed_utc_ms: Int,
  )
}

pub type ControlResult {
  ControlObserved(ack: p.Acknowledgement, cleanup: wire.Cleanup)
  ControlUnknown(reason: String)
}

pub type Boundary {
  Boundary(
    read_live: fn(CommandContext) -> Result(LiveEvidence, String),
    control: fn(CommandContext) -> ControlResult,
    inspect_control: fn(CommandContext) -> ControlResult,
    // Observation logging is distinct from permission to actuate. A trusted
    // owner may allow factual result logging after a deployment grant expires.
    may_log_observation: fn(CommandContext) -> Bool,
    // Must observe actual old worker/native group quiescence, not infer it from
    // actor DOWN or a checkpoint. Required for a new recovery epoch.
    confirm_quiescence: fn(CommandContext) -> Result(Nil, String),
  )
}

pub fn unavailable_boundary() -> Boundary {
  Boundary(
    fn(_) { Error("MISSING_RELEASE_AUTHORITY") },
    fn(_) { ControlUnknown("CONTROL_ADAPTER_UNAVAILABLE") },
    fn(_) { ControlUnknown("CONTROL_INSPECTION_UNAVAILABLE") },
    fn(_) { False },
    fn(_) { Error("QUIESCENCE_UNVERIFIED") },
  )
}

pub type Outcome {
  Starting
  ReadyForCommand
  CommandRunning
  Refused(reason: String)
  Held(reason: String)
  Finished
}

pub type Snapshot {
  Snapshot(
    phase: p.Phase,
    epoch: Int,
    generation: Int,
    outcome: Outcome,
    in_flight: Bool,
    cleanup: wire.Cleanup,
    completed_commands: Int,
  )
}

pub type Step {
  Step(epoch: Int, generation: Int)
}

type Work {
  InspectLog
  ExecuteNext
  RecoverEpoch(Int)
  Reconcile
}

type WorkResult {
  Reconstructed(p.Transaction, Bool, wire.Cleanup)
  Advanced(p.Transaction, wire.Cleanup)
  Denied(String)
  Uncertain(String)
}

type Completion {
  Completion(sequence: Int, result: WorkResult, cleanup: wire.Cleanup)
}

type Flight {
  Flight(
    sequence: Int,
    pid: Pid,
    monitor: process.Monitor,
    deadline_monotonic_ms: Int,
    timer: process.Timer,
    reply: Option(Subject(Result(Snapshot, String))),
    completed: Option(Completion),
  )
}

pub opaque type Message {
  Advance(expected: Step, reply: Subject(Result(Snapshot, String)))
  Inspect(Subject(Result(Snapshot, String)))
  Recover(
    expected: Step,
    new_epoch: Int,
    reply: Subject(Result(Snapshot, String)),
  )
  Get(Subject(Snapshot))
  Stop(Subject(Result(Nil, String)))
  Returned(Completion)
  Timeout(Int)
  Down(process.Down)
  LinkedExit(process.ExitMessage)
}

type State {
  State(
    config: Configuration,
    boundary: Boundary,
    transaction: p.Transaction,
    self: Subject(Message),
    completion: Subject(Completion),
    parent: Pid,
    parent_monitor: process.Monitor,
    owner_lost: Bool,
    reaped_workers: List(Pid),
    flight: Option(Flight),
    sequence: Int,
    outcome: Outcome,
    cleanup: wire.Cleanup,
    completed: Int,
  )
}

fn initial(b: Binding) -> Result(p.Transaction, String) {
  p.new(
    b.transaction_id,
    b.candidate,
    b.previous_candidate,
    b.manifest,
    b.physical_count,
    b.initial_epoch,
    b.execution,
  )
}

fn bound(config: Configuration, t: p.Transaction) -> wire.Binding {
  let b = config.binding
  wire.Binding(
    b.transaction_id,
    b.candidate,
    b.manifest,
    p.epoch(t),
    p.generation(t),
  )
}

fn context(
  config: Configuration,
  t: p.Transaction,
  command: p.Command,
  deadline: Int,
) -> CommandContext {
  let b = config.binding
  CommandContext(
    b.transaction_id,
    b.candidate,
    b.previous_candidate,
    b.manifest,
    p.epoch(t),
    p.generation(t),
    p.physical_count(t),
    command,
    p.phase(t),
    p.family(t),
    b.execution,
    config.native,
    deadline,
  )
}

fn snapshot(s: State) -> Snapshot {
  Snapshot(
    p.phase(s.transaction),
    p.epoch(s.transaction),
    p.generation(s.transaction),
    s.outcome,
    s.flight != None,
    s.cleanup,
    s.completed,
  )
}

fn terminal(t: p.Transaction) -> Bool {
  p.phase(t) == p.Committed || p.phase(t) == p.RolledBack
}

fn deadline_ok(deadline: Int) -> Bool {
  monotonic_before_deadline(monotonic_ms(), deadline)
}

pub fn monotonic_before_deadline(now: Int, deadline: Int) -> Bool {
  now < deadline
}

fn authorize(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  command: p.Command,
  deadline: Int,
) -> Result(CommandContext, String) {
  use _ <- result.try(case deadline_ok(deadline) {
    True -> Ok(Nil)
    False -> Error("CONTROLLER_DEADLINE")
  })
  let c = context(config, t, command, deadline)
  use live <- result.try(
    boundary.read_live(c)
    |> result.map_error(fn(reason) {
      case reason {
        "MISSING_RELEASE_AUTHORITY" -> reason
        _ -> "LIVE_AUTHORITY_UNAVAILABLE"
      }
    }),
  )
  // Sample the actual host clock AFTER the last potentially blocking live read.
  // Collector-supplied timestamps establish evidence age, not current time.
  let dispatch_utc_ms = host_utc(Millisecond)
  use _ <- result.try(
    case
      live.observed_utc_ms >= 0
      && live.observed_utc_ms <= dispatch_utc_ms
      && dispatch_utc_ms - live.observed_utc_ms <= 1000
    {
      True -> Ok(Nil)
      False -> Error("LIVE_EVIDENCE_STALE_OR_FUTURE")
    },
  )
  use checked <- result.try(
    p.authorize_next(
      t,
      live.context,
      live.call,
      fn() { live.task },
      fn() { dispatch_utc_ms },
      fn() { live.runtime },
    ),
  )
  case checked == command && deadline_ok(deadline) {
    True -> Ok(c)
    False -> Error("COMMAND_OR_DEADLINE_CHANGED")
  }
}

fn confirmed(cleanup: wire.Cleanup) -> Bool {
  case cleanup {
    wire.Confirmed(_, _) -> True
    wire.Unconfirmed -> False
  }
}

fn exchange(
  config: Configuration,
  t: p.Transaction,
  operation: String,
  payload: v.Value,
) -> Result(wire.Reply, String) {
  let out = wire.exchange(config.native, bound(config, t), operation, payload)
  use _ <- result.try(case confirmed(out.cleanup) {
    True -> Ok(Nil)
    False -> Error("NATIVE_CLEANUP_UNCONFIRMED")
  })
  use reply <- result.try(out.result)
  case reply.status {
    "ok" -> Ok(reply)
    "unknown" -> Error("NATIVE_OUTCOME_UNKNOWN")
    _ -> Error("NATIVE_HOLD")
  }
}

fn command_for(t: p.Transaction) -> Result(p.Command, String) {
  p.next(t)
}

fn native_operation(command: p.Command) -> Option(#(String, v.Value)) {
  case command {
    p.ReplaceFile(i) -> Some(#("replace_one", wire.index_payload(i)))
    p.RestoreFile(i) -> Some(#("restore_one", wire.index_payload(i)))
    p.VerifyCandidate -> Some(#("verify_new", wire.empty_payload()))
    p.VerifyPrevious -> Some(#("verify_old", wire.empty_payload()))
    p.StageFiles | p.FenceReaders | p.ResumeReaders -> None
  }
}

fn native_observation(
  config: Configuration,
  t: p.Transaction,
  command: p.Command,
  reply: wire.Reply,
) -> Result(p.Observation, String) {
  use _ <- result.try(
    case reply.prepared && reply.count == p.physical_count(t) {
      True -> Ok(Nil)
      False -> Error("NATIVE_BACKUP_SET_UNVERIFIED")
    },
  )
  case command {
    p.StageFiles -> Ok(p.Prepared(config.binding.manifest, reply.count))
    p.ReplaceFile(i) ->
      case list.drop(reply.images, i) |> list.first {
        Ok("new") | Ok("both") -> Ok(p.Succeeded)
        _ -> Error("REPLACEMENT_READBACK_UNVERIFIED")
      }
    p.RestoreFile(i) ->
      case list.drop(reply.images, i) |> list.first {
        Ok("old") | Ok("both") -> Ok(p.Succeeded)
        _ -> Error("RESTORATION_READBACK_UNVERIFIED")
      }
    p.VerifyCandidate | p.VerifyPrevious | p.FenceReaders | p.ResumeReaders ->
      Error("CONTROL_OBSERVATION_REQUIRED")
  }
}

fn checked_control(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  command: p.Command,
  deadline: Int,
  inspect: Bool,
) -> Result(p.Observation, String) {
  use c <- result.try(authorize(config, boundary, t, command, deadline))
  let observed = case inspect {
    True -> boundary.inspect_control(c)
    False -> boundary.control(c)
  }
  case observed {
    ControlUnknown(_) -> Error("CONTROL_OUTCOME_UNKNOWN")
    ControlObserved(ack, cleanup) -> {
      use _ <- result.try(
        case successful_control_cleanup(cleanup) && deadline_ok(deadline) {
          True -> Ok(Nil)
          False -> Error("CONTROL_CLEANUP_OR_DEADLINE_UNKNOWN")
        },
      )
      use _ <- result.try(p.observe(t, ack))
      Ok(ack.observation)
    }
  }
}

fn successful_control_cleanup(cleanup: wire.Cleanup) -> Bool {
  case cleanup {
    wire.Confirmed(0, observed) if observed > 0 -> True
    _ -> False
  }
}

fn confirm_quiescence(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  deadline: Int,
) -> Result(Nil, String) {
  use _ <- result.try(case deadline_ok(deadline) {
    True -> Ok(Nil)
    False -> Error("CONTROLLER_DEADLINE")
  })
  let command = p.next(t) |> result.unwrap(p.ResumeReaders)
  use _ <- result.try(
    boundary.confirm_quiescence(context(config, t, command, deadline))
    |> result.replace_error("QUIESCENCE_UNVERIFIED"),
  )
  case deadline_ok(deadline) {
    True -> Ok(Nil)
    False -> Error("CONTROLLER_DEADLINE")
  }
}

fn current_images_match(t: p.Transaction, reply: wire.Reply) -> Bool {
  let known =
    list.all(reply.images, fn(image) {
      image == "old" || image == "new" || image == "both"
    })
  case p.phase(t) {
    p.Preparing -> known
    p.Committed ->
      reply.prepared
      && reply.count == p.physical_count(t)
      && list.all(reply.images, fn(image) { image == "new" || image == "both" })
    p.RolledBack ->
      reply.prepared
      && reply.count == p.physical_count(t)
      && list.all(reply.images, fn(image) { image == "old" || image == "both" })
    _ -> reply.prepared && reply.count == p.physical_count(t) && known
  }
}

fn finish_checkpoint(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  command: p.Command,
  observation: p.Observation,
  deadline: Int,
) -> Result(#(p.Transaction, wire.Cleanup), String) {
  let c = context(config, t, command, deadline)
  use _ <- result.try(
    case boundary.may_log_observation(c) && deadline_ok(deadline) {
      True -> Ok(Nil)
      False -> Error("OBSERVED_OUTCOME_PENDING_LOG_AUTHORITY")
    },
  )
  let b = config.binding
  let ack =
    p.Acknowledgement(
      b.transaction_id,
      b.manifest,
      p.epoch(t),
      p.generation(t),
      command,
      observation,
    )
  use next <- result.try(p.observe(t, ack))
  use reply <- result.try(exchange(
    config,
    t,
    "checkpoint_result",
    wire.result_payload(command, observation),
  ))
  // Never advance from an ACK for some other operation/generation. The native
  // result must have been read back from the independent controller records.
  use stored <- result.try(
    list.find(reply.records, fn(r) {
      r.operation == "checkpoint_result"
      && r.epoch == p.epoch(t)
      && r.generation == p.generation(t)
    })
    |> result.replace_error("CHECKPOINT_RESULT_READBACK_MISSING"),
  )
  use durable <- result.try(wire.record_ack(bound(config, t), stored))
  case durable == ack {
    True -> Ok(#(next, reply.cleanup))
    False -> Error("CHECKPOINT_RESULT_READBACK_MISMATCH")
  }
}

fn execute(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  deadline: Int,
) -> WorkResult {
  let run = {
    use command <- result.try(command_for(t))
    use _ <- result.try(authorize(config, boundary, t, command, deadline))
    // Intent is durable before any native rename or reader/control actuation.
    use _ <- result.try(exchange(
      config,
      t,
      "checkpoint_pending",
      wire.pending_payload(command),
    ))
    use observation <- result.try(case command {
      p.StageFiles -> {
        use _ <- result.try(authorize(config, boundary, t, command, deadline))
        use reply <- result.try(exchange(
          config,
          t,
          "stage",
          wire.stage_payload(config.edits),
        ))
        native_observation(config, t, command, reply)
      }
      p.ReplaceFile(_) | p.RestoreFile(_) -> {
        use #(operation, payload) <- result.try(option.to_result(
          native_operation(command),
          "invalid_native_operation",
        ))
        use _ <- result.try(authorize(config, boundary, t, command, deadline))
        use reply <- result.try(exchange(config, t, operation, payload))
        native_observation(config, t, command, reply)
      }
      p.VerifyCandidate | p.VerifyPrevious -> {
        use #(operation, payload) <- result.try(option.to_result(
          native_operation(command),
          "invalid_native_operation",
        ))
        use _ <- result.try(authorize(config, boundary, t, command, deadline))
        let files = exchange(config, t, operation, payload)
        case files {
          Error(reason) -> Error(reason)
          Ok(_) ->
            checked_control(config, boundary, t, command, deadline, False)
        }
      }
      p.FenceReaders | p.ResumeReaders ->
        checked_control(config, boundary, t, command, deadline, False)
    })
    finish_checkpoint(config, boundary, t, command, observation, deadline)
  }
  case run {
    Ok(#(next, cleanup)) -> Advanced(next, cleanup)
    Error(reason) -> Uncertain(reason)
  }
}

fn matching_result(
  record: wire.LogRecord,
  records: List(wire.LogRecord),
) -> Bool {
  list.any(records, fn(r) {
    r.epoch == record.epoch
    && r.generation == record.generation
    && r.status == "result"
    && case record.operation {
      "checkpoint_pending" -> r.operation == "checkpoint_result"
      _ -> r.operation == record.operation
    }
  })
}

/// Reconstruct meaning from independently stored exact control ACKs. Native
/// file-operation results are deliberately not deployment-verification ACKs.
pub fn replay(
  config: Configuration,
  records: List(wire.LogRecord),
) -> Result(#(p.Transaction, Bool), String) {
  use _ <- result.try(
    case
      list.length(list.take(records, 257)) <= 256
      && list.all(records, fn(r) {
        list.count(records, fn(other) {
          wire.record_key(other) == wire.record_key(r)
        })
        == 1
      })
    {
      True -> Ok(Nil)
      False -> Error("CHECKPOINT_LOG_BOUND_OR_DUPLICATE")
    },
  )
  use t <- result.try(initial(config.binding))
  use t <- result.try(
    list.try_fold(records, t, fn(t, record) {
      case record.operation, record.status {
        "checkpoint_result", "result" -> {
          use ack <- result.try(wire.record_ack(bound(config, t), record))
          use pending <- result.try(
            list.find(records, fn(r) {
              r.operation == "checkpoint_pending"
              && r.status == "pending"
              && r.epoch == record.epoch
              && r.generation == record.generation
            })
            |> result.replace_error("CHECKPOINT_RESULT_WITHOUT_INTENT"),
          )
          use _ <- result.try(wire.closed(pending.payload, ["command"]))
          use intended <- result.try(
            v.get(pending.payload, "command") |> result.try(wire.decode_command),
          )
          use _ <- result.try(case intended == ack.command {
            True -> Ok(Nil)
            False -> Error("CHECKPOINT_INTENT_COMMAND_MISMATCH")
          })
          p.observe(t, ack)
        }
        "recovery_epoch", "result" -> {
          use _ <- result.try(wire.closed(record.payload, []))
          use recovered <- result.try(p.recover(t, record.epoch))
          case record.generation == p.generation(recovered) {
            True -> Ok(recovered)
            False -> Error("RECOVERY_MARKER_GENERATION_MISMATCH")
          }
        }
        _, _ -> Ok(t)
      }
    }),
  )
  let pending =
    list.any(records, fn(r) {
      r.status == "pending"
      && r.epoch >= p.epoch(t)
      && !matching_result(r, records)
    })
  Ok(#(t, pending))
}

fn inspect(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  deadline: Int,
) -> WorkResult {
  let checked = {
    use _ <- result.try(confirm_quiescence(config, boundary, t, deadline))
    exchange(config, t, "inspect", wire.empty_payload())
  }
  case checked {
    Error(reason) -> Uncertain(reason)
    Ok(reply) ->
      case replay(config, reply.records) {
        Error(reason) -> Uncertain(reason)
        Ok(#(restored, pending)) ->
          case current_images_match(restored, reply) {
            False -> Uncertain("CHECKPOINT_CURRENT_IMAGES_MISMATCH")
            True -> Reconstructed(restored, pending, reply.cleanup)
          }
      }
  }
}

fn reconcile(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  deadline: Int,
) -> WorkResult {
  let run = {
    use _ <- result.try(confirm_quiescence(config, boundary, t, deadline))
    use reply <- result.try(exchange(config, t, "inspect", wire.empty_payload()))
    use replayed <- result.try(replay(config, reply.records))
    use _ <- result.try(case current_images_match(replayed.0, reply) {
      True -> Ok(Nil)
      False -> Error("CHECKPOINT_CURRENT_IMAGES_MISMATCH")
    })
    case replayed.1 {
      False -> Ok(#(replayed.0, reply.cleanup))
      True -> {
        let t = replayed.0
        use command <- result.try(p.next(t))
        use c <- result.try(authorize(config, boundary, t, command, deadline))
        let _ = c
        use _ <- result.try(confirm_quiescence(config, boundary, t, deadline))
        // Reconciliation never repeats the original effect. Native metadata and
        // current known images or the root's read-only control inspector decide.
        use observation <- result.try(case command {
          p.StageFiles -> native_observation(config, t, command, reply)
          p.ReplaceFile(_) | p.RestoreFile(_) -> {
            use #(operation, _) <- result.try(option.to_result(
              native_operation(command),
              "invalid_native_operation",
            ))
            use native <- result.try(
              list.find(reply.records, fn(r) {
                r.operation == operation
                && r.status == "result"
                && r.epoch == p.epoch(t)
                && r.generation == p.generation(t)
              })
              |> result.replace_error("NATIVE_RESULT_STILL_UNKNOWN"),
            )
            let _ = native
            native_observation(config, t, command, reply)
          }
          p.VerifyCandidate
          | p.VerifyPrevious
          | p.FenceReaders
          | p.ResumeReaders ->
            checked_control(config, boundary, t, command, deadline, True)
        })
        finish_checkpoint(config, boundary, t, command, observation, deadline)
      }
    }
  }
  case run {
    Ok(#(next, cleanup)) -> Advanced(next, cleanup)
    Error(reason) -> Uncertain(reason)
  }
}

fn recover(
  config: Configuration,
  boundary: Boundary,
  t: p.Transaction,
  epoch: Int,
  deadline: Int,
) -> WorkResult {
  let run = {
    use next <- result.try(p.recover(t, epoch))
    use command <- result.try(p.next(next))
    use c <- result.try(authorize(config, boundary, next, command, deadline))
    let _ = c
    use _ <- result.try(confirm_quiescence(config, boundary, next, deadline))
    use _ <- result.try(authorize(config, boundary, next, command, deadline))
    use reply <- result.try(exchange(
      config,
      next,
      "recovery_epoch",
      wire.empty_payload(),
    ))
    Ok(#(next, reply.cleanup))
  }
  case run {
    Ok(#(next, cleanup)) -> Advanced(next, cleanup)
    Error(reason) -> Uncertain(reason)
  }
}

fn launch(
  s: State,
  work: Work,
  reply: Option(Subject(Result(Snapshot, String))),
) -> State {
  let sequence = s.sequence + 1
  let completion = s.completion
  let deadline = monotonic_ms() + s.config.command_timeout_ms
  let pid =
    process.spawn(fn() {
      let outcome = case work {
        InspectLog -> inspect(s.config, s.boundary, s.transaction, deadline)
        ExecuteNext -> {
          // Refuse before the first checkpoint/native invocation when no real
          // issuer/admission source is connected. This is the public default.
          let result = case p.next(s.transaction) {
            Error(reason) -> Denied(reason)
            Ok(command) ->
              case
                authorize(
                  s.config,
                  s.boundary,
                  s.transaction,
                  command,
                  deadline,
                )
              {
                Error(reason) -> Denied(reason)
                Ok(_) -> execute(s.config, s.boundary, s.transaction, deadline)
              }
          }
          result
        }
        RecoverEpoch(epoch) ->
          recover(s.config, s.boundary, s.transaction, epoch, deadline)
        Reconcile -> reconcile(s.config, s.boundary, s.transaction, deadline)
      }
      let cleanup = case outcome {
        Advanced(_, cleanup) | Reconstructed(_, _, cleanup) -> cleanup
        _ -> wire.Unconfirmed
      }
      process.send(completion, Completion(sequence, outcome, cleanup))
    })
  let monitor = process.monitor(pid)
  let timer =
    process.send_after(s.self, s.config.command_timeout_ms, Timeout(sequence))
  State(
    ..s,
    flight: Some(Flight(sequence, pid, monitor, deadline, timer, reply, None)),
    sequence: sequence,
    outcome: CommandRunning,
  )
}

fn settle(s: State, f: Flight, completion: Completion) -> State {
  let Completion(_, result, cleanup) = completion
  let next = case result {
    Advanced(t, _) ->
      State(
        ..s,
        transaction: t,
        completed: s.completed + 1,
        outcome: case terminal(t) {
          True -> Finished
          False -> ReadyForCommand
        },
      )
    Reconstructed(t, pending, _) ->
      State(..s, transaction: t, outcome: case pending {
        True -> Held("DURABLE_PENDING_REQUIRES_INSPECTION")
        False ->
          case terminal(t) {
            True -> Finished
            False -> ReadyForCommand
          }
      })
    Denied(reason) -> State(..s, outcome: Refused(reason))
    Uncertain(reason) -> State(..s, outcome: Held(reason))
  }
  let cleanup = case result {
    Denied(_) -> s.cleanup
    _ -> cleanup
  }
  let next = State(..next, flight: None, cleanup: cleanup)
  case f.reply {
    Some(reply) -> process.send(reply, Ok(snapshot(next)))
    None -> Nil
  }
  next
}

fn lose_owner(s: State) -> actor.Next(State, Message) {
  case s.flight {
    None -> actor.stop()
    Some(f) -> {
      let _ = process.cancel_timer(f.timer)
      process.kill(f.pid)
      case f.reply {
        Some(reply) -> process.send(reply, Error("CUTOVER_OWNER_LOST_UNKNOWN"))
        None -> Nil
      }
      // Keep the actor until the EXACT worker monitor confirms BEAM death.
      // Native cleanup remains UNKNOWN; independent durable pending state and
      // fresh actual quiescence checks prevent automatic replacement effects.
      actor.continue(
        State(
          ..s,
          owner_lost: True,
          flight: Some(Flight(..f, reply: None, completed: None)),
          outcome: Held("CUTOVER_OWNER_LOST_UNKNOWN"),
          cleanup: wire.Unconfirmed,
        ),
      )
    }
  }
}

fn same_step(s: State, step: Step) -> Bool {
  step.epoch == p.epoch(s.transaction)
  && step.generation == p.generation(s.transaction)
}

fn handle(s: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Get(reply) -> {
      process.send(reply, snapshot(s))
      actor.continue(s)
    }
    Advance(expected, reply) ->
      case same_step(s, expected) {
        False -> {
          process.send(reply, Error("STALE_CONTROLLER_STEP"))
          actor.continue(s)
        }
        True ->
          case s.flight, s.outcome {
            Some(_), _ -> {
              process.send(reply, Error("CUTOVER_SINGLE_FLIGHT"))
              actor.continue(s)
            }
            None, Held(_) -> {
              process.send(reply, Error("CUTOVER_REQUIRES_RECONCILIATION"))
              actor.continue(s)
            }
            None, Starting -> {
              process.send(reply, Error("CUTOVER_STARTUP_INSPECTION_PENDING"))
              actor.continue(s)
            }
            None, _ -> actor.continue(launch(s, ExecuteNext, Some(reply)))
          }
      }
    Inspect(reply) ->
      case s.flight {
        Some(_) -> {
          process.send(reply, Error("CUTOVER_SINGLE_FLIGHT"))
          actor.continue(s)
        }
        None -> actor.continue(launch(s, Reconcile, Some(reply)))
      }
    Recover(expected, epoch, reply) ->
      case same_step(s, expected) {
        False -> {
          process.send(reply, Error("STALE_CONTROLLER_STEP"))
          actor.continue(s)
        }
        True ->
          case s.flight {
            Some(_) -> {
              process.send(reply, Error("CUTOVER_SINGLE_FLIGHT"))
              actor.continue(s)
            }
            None -> actor.continue(launch(s, RecoverEpoch(epoch), Some(reply)))
          }
      }
    Returned(completion) ->
      case s.flight {
        Some(f) if f.sequence == completion.sequence && !s.owner_lost -> {
          let _ = process.cancel_timer(f.timer)
          case
            s.outcome,
            monotonic_before_deadline(monotonic_ms(), f.deadline_monotonic_ms)
          {
            Held(_), _ -> actor.continue(s)
            _, True ->
              actor.continue(
                State(
                  ..s,
                  flight: Some(Flight(..f, completed: Some(completion))),
                ),
              )
            _, False -> {
              process.kill(f.pid)
              actor.continue(
                State(
                  ..s,
                  flight: Some(Flight(..f, completed: None)),
                  outcome: Held("CUTOVER_WORKER_TIMEOUT_UNKNOWN"),
                  cleanup: wire.Unconfirmed,
                ),
              )
            }
          }
        }
        _ -> actor.continue(s)
      }
    Timeout(sequence) ->
      case s.flight {
        Some(f) if f.sequence == sequence -> {
          process.kill(f.pid)
          case f.reply {
            Some(reply) ->
              process.send(reply, Error("CUTOVER_WORKER_TIMEOUT_UNKNOWN"))
            None -> Nil
          }
          // Actor death is not native process-group cleanup evidence. Durable
          // pending state and explicit quiescence/reconciliation fence recovery.
          actor.continue(
            State(
              ..s,
              flight: Some(Flight(..f, reply: None, completed: None)),
              outcome: Held("CUTOVER_WORKER_TIMEOUT_UNKNOWN"),
              cleanup: wire.Unconfirmed,
            ),
          )
        }
        _ -> actor.continue(s)
      }
    Down(process.ProcessDown(monitor, pid, _))
      if pid == s.parent && monitor == s.parent_monitor
    -> lose_owner(s)
    Down(process.ProcessDown(monitor, pid, _)) ->
      case s.flight {
        Some(f) if f.pid == pid && f.monitor == monitor -> {
          let _ = process.cancel_timer(f.timer)
          case s.owner_lost, f.completed {
            True, _ -> actor.stop()
            False, Some(completion) ->
              actor.continue(settle(
                State(
                  ..s,
                  reaped_workers: list.take([pid, ..s.reaped_workers], 256),
                ),
                f,
                completion,
              ))
            False, None -> {
              case f.reply {
                Some(reply) ->
                  process.send(reply, Error("CUTOVER_WORKER_EXIT_UNKNOWN"))
                None -> Nil
              }
              let outcome = case s.outcome {
                Held(_) -> s.outcome
                _ -> Held("CUTOVER_WORKER_EXIT_UNKNOWN")
              }
              actor.continue(
                State(
                  ..s,
                  flight: None,
                  outcome: outcome,
                  cleanup: wire.Unconfirmed,
                  reaped_workers: list.take([pid, ..s.reaped_workers], 256),
                ),
              )
            }
          }
        }
        _ -> actor.continue(s)
      }
    Down(_) -> actor.continue(s)
    LinkedExit(process.ExitMessage(pid, _)) if pid == s.parent -> lose_owner(s)
    LinkedExit(process.ExitMessage(pid, _)) ->
      case s.flight {
        Some(f) if f.pid == pid -> actor.continue(s)
        _ ->
          case list.contains(s.reaped_workers, pid) {
            True -> actor.continue(s)
            False -> actor.stop_abnormal("CUTOVER_UNTRACKED_LINK_EXIT")
          }
      }
    Stop(reply) ->
      case s.flight {
        Some(_) -> {
          process.send(
            reply,
            Error("CUTOVER_IN_FLIGHT_STOP_REQUIRES_RECONCILIATION"),
          )
          actor.continue(s)
        }
        None -> {
          process.send(reply, Ok(Nil))
          actor.stop()
        }
      }
  }
}

pub fn start_controller(
  config: Configuration,
  boundary: Boundary,
) -> actor.StartResult(Subject(Message)) {
  let parent = process.self()
  actor.new_with_initialiser(2000, fn(self) {
    process.trap_exits(True)
    use t <- result.try(initial(config.binding))
    use _ <- result.try(
      case
        config.command_timeout_ms >= 1000
        && config.command_timeout_ms <= 60_000
        && list.length(config.edits) == config.binding.physical_count
      {
        True -> Ok(Nil)
        False -> Error("INVALID_CONTROLLER_CONFIG")
      },
    )
    let completion = process.new_subject()
    let parent_monitor = process.monitor(parent)
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_map(completion, Returned)
      |> process.select_monitors(Down)
      |> process.select_trapped_exits(LinkedExit)
    let s =
      State(
        config,
        boundary,
        t,
        self,
        completion,
        parent,
        parent_monitor,
        False,
        [],
        None,
        0,
        Starting,
        wire.Unconfirmed,
        0,
      )
    Ok(
      actor.initialised(launch(s, InspectLog, None))
      |> actor.selecting(selector)
      |> actor.returning(self),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn child_spec(
  config: Configuration,
  boundary: Boundary,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_controller(config, boundary) })
}

pub fn advance(
  controller: Subject(Message),
  expected: Step,
  within: Int,
) -> Result(Snapshot, String) {
  use _ <- result.try(wait_bound(within))
  let reply = process.new_subject()
  process.send(controller, Advance(expected, reply))
  process.receive(reply, within)
  |> result.replace_error("CONTROLLER_REPLY_TIMEOUT")
  |> result.flatten
}

pub fn reconcile_now(
  controller: Subject(Message),
  within: Int,
) -> Result(Snapshot, String) {
  use _ <- result.try(wait_bound(within))
  let reply = process.new_subject()
  process.send(controller, Inspect(reply))
  process.receive(reply, within)
  |> result.replace_error("CONTROLLER_REPLY_TIMEOUT")
  |> result.flatten
}

pub fn recover_epoch(
  controller: Subject(Message),
  expected: Step,
  epoch: Int,
  within: Int,
) -> Result(Snapshot, String) {
  use _ <- result.try(wait_bound(within))
  let reply = process.new_subject()
  process.send(controller, Recover(expected, epoch, reply))
  process.receive(reply, within)
  |> result.replace_error("CONTROLLER_REPLY_TIMEOUT")
  |> result.flatten
}

pub fn get(
  controller: Subject(Message),
  within: Int,
) -> Result(Snapshot, String) {
  use _ <- result.try(wait_bound(within))
  let reply = process.new_subject()
  process.send(controller, Get(reply))
  process.receive(reply, within)
  |> result.replace_error("CONTROLLER_REPLY_TIMEOUT")
}

pub fn stop(controller: Subject(Message), within: Int) -> Result(Nil, String) {
  use _ <- result.try(wait_bound(within))
  let reply = process.new_subject()
  process.send(controller, Stop(reply))
  process.receive(reply, within)
  |> result.replace_error("CONTROLLER_REPLY_TIMEOUT")
  |> result.flatten
}

fn wait_bound(within: Int) -> Result(Nil, String) {
  case within >= 1 && within <= 60_000 {
    True -> Ok(Nil)
    False -> Error("CONTROLLER_REPLY_BOUND")
  }
}
