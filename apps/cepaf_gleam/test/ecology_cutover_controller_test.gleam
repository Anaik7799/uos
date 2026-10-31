//// Model grants below are fixture inputs, never production admission.
//// Native tests use actual files, the compiled port and existing OS guardian.

import cepaf_gleam/ecology/cutover_controller as c
import cepaf_gleam/ecology/cutover_protocol as p
import cepaf_gleam/ecology/cutover_transport as wire
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/admission as a
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/types
import envoy
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

const digest = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

const previous = "sha256:2222222222222222222222222222222222222222222222222222222222222222"

const hex = "1111111111111111111111111111111111111111111111111111111111111111"

fn range(n: Int) -> List(Int) {
  case n <= 0 {
    True -> []
    False -> list.append(range(n - 1), [n - 1])
  }
}

fn execution() {
  p.ExecutionBinding(
    "plan",
    "OI02",
    "fixture-worker",
    1,
    "/fixture",
    "fixture-owner",
  )
}

fn binding() {
  c.Binding(digest, digest, previous, digest, 14, 7, execution())
}

fn config() {
  c.Configuration(
    binding(),
    wire.local_configuration(
      "/private/guardian",
      hex,
      "/private/worker",
      hex,
      "/private/config",
    ),
    list.map(range(14), fn(i) {
      wire.Edit("targets/f" <> int.to_string(i), "new" <> int.to_string(i))
    }),
    30_000,
  )
}

fn intent(epoch, generation, command) {
  wire.LogRecord(
    "checkpoint_pending",
    epoch,
    generation,
    wire.pending_payload(command),
    "pending",
  )
}

fn ack(epoch, generation, command, observation) {
  wire.LogRecord(
    "checkpoint_result",
    epoch,
    generation,
    wire.result_payload(command, observation),
    "result",
  )
}

fn first_records() {
  [intent(7, 0, p.StageFiles), ack(7, 0, p.StageFiles, p.Prepared(digest, 14))]
}

pub fn replay_requires_exact_intent_result_and_command_generation_test() {
  let assert Ok(#(t, False)) = c.replay(config(), first_records())
  p.phase(t) |> should.equal(p.Quiescing)
  let assert Error(_) =
    c.replay(config(), [ack(7, 0, p.StageFiles, p.Prepared(digest, 14))])
  let assert Error(_) =
    c.replay(config(), [
      intent(7, 0, p.FenceReaders),
      ack(7, 0, p.StageFiles, p.Prepared(digest, 14)),
    ])
  let assert Error(_) =
    c.replay(config(), [
      intent(7, 0, p.StageFiles),
      ack(7, 1, p.StageFiles, p.Prepared(digest, 14)),
    ])
  let assert Error(_) =
    c.replay(config(), list.append(first_records(), first_records()))
  let assert Ok(#(_, True)) = c.replay(config(), [intent(7, 0, p.StageFiles)])
}

pub fn native_file_results_never_advance_the_control_model_test() {
  let native =
    wire.LogRecord(
      "stage",
      7,
      0,
      v.Object([
        #("index", v.Null),
        #("files_verified", v.Boolean(False)),
        #("prepared", v.Boolean(True)),
        #("count", v.Integer(14)),
      ]),
      "result",
    )
  let assert Ok(#(t, False)) = c.replay(config(), [native])
  p.phase(t) |> should.equal(p.Preparing)
  let assert Ok(#(_, True)) =
    c.replay(config(), [wire.LogRecord("stage", 7, 0, v.Object([]), "pending")])
}

pub fn recovery_epoch_replay_requires_prepared_set_and_new_epoch_test() {
  let marker =
    wire.LogRecord("recovery_epoch", 8, 2, wire.empty_payload(), "result")
  let assert Ok(#(t, False)) =
    c.replay(config(), list.append(first_records(), [marker]))
  p.phase(t) |> should.equal(p.RecoveryQuiescing)
  p.epoch(t) |> should.equal(8)
  let assert Error(_) = c.replay(config(), [marker])
  let assert Error(_) =
    c.replay(
      config(),
      list.append(first_records(), [wire.LogRecord(..marker, epoch: 7)]),
    )
  let assert Error(_) =
    c.replay(
      config(),
      list.append(first_records(), [wire.LogRecord(..marker, generation: 3)]),
    )
}

pub fn replay_missing_out_of_order_and_wrong_observation_refuse_test() {
  let assert Error(_) =
    c.replay(config(), [
      intent(7, 0, p.StageFiles),
      ack(7, 0, p.StageFiles, p.Succeeded),
    ])
  let assert Error(_) =
    c.replay(config(), [
      intent(7, 0, p.StageFiles),
      ack(7, 0, p.StageFiles, p.Prepared(previous, 14)),
    ])
  let assert Error(_) =
    c.replay(
      config(),
      list.append(first_records(), [
        intent(7, 2, p.ReplaceFile(0)),
        ack(7, 2, p.ReplaceFile(0), p.Succeeded),
      ]),
    )
  let assert Error(_) =
    c.replay(config(), list.repeat(intent(7, 0, p.StageFiles), 257))
}

fn required(name) {
  let assert Ok(value) = envoy.get(name)
  value
}

fn get(controller, within) {
  let assert Ok(s) = c.get(controller, within)
  s
}

fn advance(controller, within) {
  let s = get(controller, 2000)
  c.advance(controller, c.Step(s.epoch, s.generation), within)
}

fn recover_epoch(controller, epoch, within) {
  let s = get(controller, 2000)
  c.recover_epoch(controller, c.Step(s.epoch, s.generation), epoch, within)
}

fn fixture(name) {
  required("UOS_CUTOVER_TEST_FIXTURES") <> "/" <> name
}

fn native_config(name) {
  c.Configuration(
    ..config(),
    native: wire.local_configuration(
      required("UOS_CUTOVER_TEST_GUARDIAN"),
      required("UOS_CUTOVER_TEST_GUARDIAN_SHA"),
      required("UOS_CUTOVER_TEST_WORKER"),
      required("UOS_CUTOVER_TEST_WORKER_SHA"),
      fixture(name) <> "/config.json",
    ),
  )
}

pub type Unit {
  Millisecond
}

pub type TestTimeout {
  Timeout
}

@external(erlang, "erlang", "system_time")
fn utc_ms(unit: Unit) -> Int

fn live(request: c.CommandContext) -> Result(c.LiveEvidence, String) {
  let now = utc_ms(Millisecond)
  let task =
    a.TaskFence(
      "plan",
      "OI02",
      "fixture-worker",
      1,
      a.TaskExecuting,
      now + 60_000,
      Some(a.GrantTicket(
        "fixture-grant",
        types.ReleaseAuthority,
        False,
        now + 60_000,
        "/fixture",
      )),
    )
  let context =
    a.AdmissionContext(
      principal.from_launcher_env(
        "fixture-worker",
        types.ClientProfile("codex"),
        "/fixture",
        "synthetic-development-fixture",
      ),
      a.EnforcedMode,
      now,
      "/fixture",
      Some(task),
    )
  let spec =
    types.ToolSpec(
      "private_fixture",
      "cutover",
      "fixture only",
      request.family,
      "OI02",
      1,
      json.object([]),
      digest,
      types.ControlActuation,
      "private",
      1000,
    )
  use call <- result.try(
    a.admit(
      context,
      spec,
      dict.from_list([
        #("transaction_id", request.transaction_id),
        #("candidate", request.candidate),
        #("manifest", request.manifest),
        #("runtime_epoch", int.to_string(request.epoch)),
        #("generation", int.to_string(request.generation)),
        #("command", p.command_key(request.command)),
      ]),
    )
    |> result.map_error(fn(error) { error.code }),
  )
  Ok(c.LiveEvidence(
    context,
    call,
    Some(task),
    p.RuntimeObservation(
      request.candidate,
      request.manifest,
      request.transaction_id,
      request.epoch,
      "fixture-owner",
      now,
      now + 60_000,
      True,
      True,
      True,
    ),
    now,
  ))
}

fn observed(request: c.CommandContext, observation: p.Observation) {
  c.ControlObserved(
    p.Acknowledgement(
      request.transaction_id,
      request.manifest,
      request.epoch,
      request.generation,
      request.command,
      observation,
    ),
    wire.Confirmed(0, utc_ms(Millisecond) * 1000),
  )
}

fn fixture_boundary(name: String) -> c.Boundary {
  let control = fn(request: c.CommandContext) {
    case request.command {
      p.FenceReaders | p.ResumeReaders -> observed(request, p.Succeeded)
      p.VerifyCandidate ->
        case simplifile.read(fixture(name) <> "/targets/f0") {
          Ok("new-0") -> observed(request, p.Verified(digest))
          _ -> observed(request, p.Failed)
        }
      p.VerifyPrevious ->
        case simplifile.read(fixture(name) <> "/targets/f0") {
          Ok("old-0") -> observed(request, p.Verified(previous))
          _ -> observed(request, p.Failed)
        }
      _ -> c.ControlUnknown("unexpected_control_command")
    }
  }
  c.Boundary(live, control, control, fn(_) { True }, fn(_) { Ok(Nil) })
}

fn ready(controller, deadline) {
  let s = get(controller, 2000)
  case s.in_flight {
    False -> s
    True -> {
      let assert True = c.monotonic_ms() < deadline
      process.sleep(5)
      ready(controller, deadline)
    }
  }
}

fn start(name, boundary) {
  let assert Ok(owner) = c.start_controller(native_config(name), boundary)
  let s = ready(owner.data, c.monotonic_ms() + 10_000)
  s.outcome |> should.equal(c.ReadyForCommand)
  owner
}

fn steps(controller, count) {
  list.each(range(count), fn(_) {
    let assert Ok(s) = advance(controller, 40_000)
    case s.outcome {
      c.Held(reason) | c.Refused(reason) -> panic as reason
      _ -> Nil
    }
  })
}

fn actual_images(name, prefix) {
  list.each(range(14), fn(i) {
    simplifile.read(fixture(name) <> "/targets/f" <> int.to_string(i))
    |> should.equal(Ok(prefix <> "-" <> int.to_string(i)))
  })
}

pub fn actual_native_guardian_success_and_restart_replay_test_() {
  #(Timeout, 60, fn() {
    let owner = start("success", fixture_boundary("success"))
    steps(owner.data, 5)
    let before = get(owner.data, 2000)
    before.phase |> should.equal(p.Replacing(3))
    c.advance(owner.data, c.Step(7, 0), 2000)
    |> should.equal(Error("STALE_CONTROLLER_STEP"))
    c.advance(owner.data, c.Step(7, 5), 0)
    |> should.equal(Error("CONTROLLER_REPLY_BOUND"))
    get(owner.data, 2000).generation |> should.equal(5)
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
    let restarted = start("success", fixture_boundary("success"))
    get(restarted.data, 2000).generation |> should.equal(before.generation)
    steps(restarted.data, 13)
    get(restarted.data, 2000).phase |> should.equal(p.Committed)
    let assert wire.Confirmed(0, observed_utc_us) =
      get(restarted.data, 2000).cleanup
    let positive = observed_utc_us > 0
    positive |> should.be_true
    actual_images("success", "new")
    let assert Ok(s) = advance(restarted.data, 2000)
    s.outcome |> should.equal(c.Refused("TRANSACTION_TERMINAL"))
    c.stop(restarted.data, 2000) |> should.equal(Ok(Nil))
  })
}

pub fn no_grant_actual_native_path_refuses_before_checkpoint_or_target_effect_test_() {
  #(Timeout, 30, fn() {
    let owner =
      start(
        "no-grant",
        c.Boundary(..c.unavailable_boundary(), confirm_quiescence: fn(_) {
          Ok(Nil)
        }),
      )
    let assert Ok(s) = advance(owner.data, 2000)
    s.outcome |> should.equal(c.Refused("MISSING_RELEASE_AUTHORITY"))
    s.generation |> should.equal(0)
    actual_images("no-grant", "old")
    let cfg = native_config("no-grant")
    let out =
      wire.exchange(
        cfg.native,
        wire.Binding(digest, digest, digest, 7, 0),
        "inspect",
        wire.empty_payload(),
      )
    let assert Ok(reply) = out.result
    reply.records |> should.equal([])
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
  })
}

pub fn actual_recovery_new_epoch_restores_all_files_and_replays_marker_test_() {
  #(Timeout, 60, fn() {
    let owner = start("recovery", fixture_boundary("recovery"))
    steps(owner.data, 7)
    let assert Ok(s) = recover_epoch(owner.data, 8, 20_000)
    s.phase |> should.equal(p.RecoveryQuiescing)
    steps(owner.data, 1)
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
    let restarted = start("recovery", fixture_boundary("recovery"))
    get(restarted.data, 2000).phase |> should.equal(p.Restoring(13))
    steps(restarted.data, 16)
    get(restarted.data, 2000).phase |> should.equal(p.RolledBack)
    actual_images("recovery", "old")
    c.stop(restarted.data, 2000) |> should.equal(Ok(Nil))
  })
}

pub fn actual_unlogged_prepared_outcome_reconciles_without_repeating_stage_test_() {
  #(Timeout, 60, fn() {
    let original = fixture_boundary("lost-log")
    let owner =
      start(
        "lost-log",
        c.Boundary(..original, may_log_observation: fn(_) { False }),
      )
    let assert Ok(held) = advance(owner.data, 20_000)
    held.outcome
    |> should.equal(c.Held("OBSERVED_OUTCOME_PENDING_LOG_AUTHORITY"))
    held.phase |> should.equal(p.Preparing)
    advance(owner.data, 2000)
    |> should.equal(Error("CUTOVER_REQUIRES_RECONCILIATION"))
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
    let assert Ok(restarted) =
      c.start_controller(native_config("lost-log"), original)
    let s = ready(restarted.data, c.monotonic_ms() + 10_000)
    s.outcome |> should.equal(c.Held("DURABLE_PENDING_REQUIRES_INSPECTION"))
    let assert Ok(reconciled) = c.reconcile_now(restarted.data, 20_000)
    reconciled.phase |> should.equal(p.Quiescing)
    actual_images("lost-log", "old")
    let cfg = native_config("lost-log")
    let out =
      wire.exchange(
        cfg.native,
        wire.Binding(digest, digest, digest, 7, 1),
        "inspect",
        wire.empty_payload(),
      )
    let assert Ok(reply) = out.result
    list.count(reply.records, fn(r) {
      r.operation == "stage" && r.status == "pending"
    })
    |> should.equal(1)
    list.count(reply.records, fn(r) { r.operation == "checkpoint_result" })
    |> should.equal(1)
    c.stop(restarted.data, 2000) |> should.equal(Ok(Nil))
  })
}

pub type CountMessage {
  Bump(process.Subject(Int))
  Peek(process.Subject(Int))
  Set(Int, process.Subject(Nil))
}

fn counter() {
  let assert Ok(owner) =
    actor.new(0)
    |> actor.on_message(fn(n, message) {
      case message {
        Bump(reply) -> {
          process.send(reply, n + 1)
          actor.continue(n + 1)
        }
        Peek(reply) -> {
          process.send(reply, n)
          actor.continue(n)
        }
        Set(value, reply) -> {
          process.send(reply, Nil)
          actor.continue(value)
        }
      }
    })
    |> actor.start
  owner
}

pub fn actual_fence_is_read_again_after_durable_intent_before_native_effect_test_() {
  #(Timeout, 30, fn() {
    let counts = counter()
    let boundary = fixture_boundary("stale-fence")
    let checked =
      c.Boundary(..boundary, read_live: fn(request) {
        let n = actor.call(counts.data, 2000, Bump)
        use e <- result.try(live(request))
        case n >= 3 {
          False -> Ok(e)
          True -> {
            let assert Some(task) = e.task
            let assert Some(grant) = task.grant
            Ok(
              c.LiveEvidence(
                ..e,
                task: Some(
                  a.TaskFence(
                    ..task,
                    grant: Some(a.GrantTicket(..grant, revoked: True)),
                  ),
                ),
              ),
            )
          }
        }
      })
    let owner = start("stale-fence", checked)
    let assert Ok(s) = advance(owner.data, 20_000)
    s.outcome |> should.equal(c.Held("GRANT_REVOKED_AT_EFFECT_TIME"))
    actual_images("stale-fence", "old")
    let cfg = native_config("stale-fence")
    let out =
      wire.exchange(
        cfg.native,
        wire.Binding(digest, digest, digest, 7, 0),
        "inspect",
        wire.empty_payload(),
      )
    let assert Ok(reply) = out.result
    list.count(reply.records, fn(r) { r.operation == "checkpoint_pending" })
    |> should.equal(1)
    list.count(reply.records, fn(r) { r.operation == "stage" })
    |> should.equal(0)
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
    process.unlink(counts.pid)
    process.kill(counts.pid)
  })
}

pub fn actual_single_flight_timeout_and_unknown_cleanup_fence_test_() {
  #(Timeout, 30, fn() {
    let base = fixture_boundary("single-flight")
    let events = process.new_subject()
    let boundary =
      c.Boundary(
        ..base,
        control: fn(_) {
          process.send(events, process.self())
          process.sleep(10_000)
          c.ControlUnknown("late")
        },
        confirm_quiescence: fn(request: c.CommandContext) {
          case request.phase {
            p.RecoveryQuiescing -> Error("fixture_quiescence_unknown")
            _ -> Ok(Nil)
          }
        },
      )
    let cfg =
      c.Configuration(
        ..native_config("single-flight"),
        command_timeout_ms: 1000,
      )
    let assert Ok(owner) = c.start_controller(cfg, boundary)
    ready(owner.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.ReadyForCommand)
    steps(owner.data, 1)
    advance(owner.data, 20) |> should.equal(Error("CONTROLLER_REPLY_TIMEOUT"))
    let assert Ok(worker) = process.receive(events, 2000)
    let worker_monitor = process.monitor(worker)
    advance(owner.data, 2000) |> should.equal(Error("CUTOVER_SINGLE_FLIGHT"))
    let settled = ready(owner.data, c.monotonic_ms() + 10_000)
    settled.outcome |> should.equal(c.Held("CUTOVER_WORKER_TIMEOUT_UNKNOWN"))
    settled.cleanup |> should.equal(wire.Unconfirmed)
    process.is_alive(owner.pid) |> should.be_true
    process.is_alive(worker) |> should.be_false
    await_down(worker, worker_monitor)
    advance(owner.data, 2000)
    |> should.equal(Error("CUTOVER_REQUIRES_RECONCILIATION"))
    let assert Ok(held) = recover_epoch(owner.data, 8, 2000)
    held.outcome |> should.equal(c.Held("QUIESCENCE_UNVERIFIED"))
    actual_images("single-flight", "old")
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
  })
}

fn await_down(pid, monitor) {
  let selector =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(d) { d })
  let assert Ok(process.ProcessDown(_, observed, _)) =
    process.selector_receive(selector, 3000)
  observed |> should.equal(pid)
}

pub type OwnerEvent {
  OwnerReady(process.Pid, process.Subject(c.Message), process.Subject(Nil))
  WorkerStarted(process.Pid)
}

fn owner_loss_case(name, abrupt) {
  let events = process.new_subject()
  let boundary =
    c.Boundary(
      ..fixture_boundary(name),
      control: fn(_) {
        process.send(events, WorkerStarted(process.self()))
        process.sleep_forever()
        c.ControlUnknown("unreachable")
      },
      inspect_control: fn(_) {
        c.ControlUnknown("fixture_reader_state_unknown")
      },
    )
  let parent =
    process.spawn_unlinked(fn() {
      let quit = process.new_subject()
      let assert Ok(owner) = c.start_controller(native_config(name), boundary)
      process.send(events, OwnerReady(owner.pid, owner.data, quit))
      let _ = process.receive(quit, 30_000)
      Nil
    })
  let assert Ok(OwnerReady(owner_pid, controller, quit)) =
    process.receive(events, 2000)
  ready(controller, c.monotonic_ms() + 10_000).outcome
  |> should.equal(c.ReadyForCommand)
  steps(controller, 1)
  advance(controller, 50) |> should.equal(Error("CONTROLLER_REPLY_TIMEOUT"))
  let assert Ok(WorkerStarted(worker)) = process.receive(events, 2000)
  let wm = process.monitor(worker)
  let om = process.monitor(owner_pid)
  let pm = process.monitor(parent)
  case abrupt {
    True -> process.kill(parent)
    False -> process.send(quit, Nil)
  }
  await_down(parent, pm)
  await_down(worker, wm)
  await_down(owner_pid, om)
  process.is_alive(worker) |> should.be_false
  let assert Ok(restarted) = c.start_controller(native_config(name), boundary)
  ready(restarted.data, c.monotonic_ms() + 10_000).outcome
  |> should.equal(c.Held("DURABLE_PENDING_REQUIRES_INSPECTION"))
  advance(restarted.data, 2000)
  |> should.equal(Error("CUTOVER_REQUIRES_RECONCILIATION"))
  let assert Ok(held) = c.reconcile_now(restarted.data, 20_000)
  held.outcome
  |> should.equal(c.Held("CONTROL_OUTCOME_UNKNOWN"))
  actual_images(name, "old")
  c.stop(restarted.data, 2000) |> should.equal(Ok(Nil))
}

pub fn actual_normal_and_abrupt_owner_loss_reaps_worker_and_restart_holds_test_() {
  #(Timeout, 60, fn() {
    owner_loss_case("owner-loss-normal", False)
    owner_loss_case("owner-loss-abrupt", True)
  })
}

pub fn actual_fifteen_physical_targets_full_controller_run_test_() {
  #(Timeout, 60, fn() {
    let cfg =
      c.Configuration(
        ..native_config("success15"),
        binding: c.Binding(..binding(), physical_count: 15),
        edits: list.map(range(15), fn(i) {
          wire.Edit("targets/f" <> int.to_string(i), "new" <> int.to_string(i))
        }),
      )
    let assert Ok(owner) =
      c.start_controller(cfg, fixture_boundary("success15"))
    ready(owner.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.ReadyForCommand)
    steps(owner.data, 19)
    get(owner.data, 2000).phase |> should.equal(p.Committed)
    actual_images("success15", "new")
    simplifile.read(fixture("success15") <> "/targets/f14")
    |> should.equal(Ok("new-14"))
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
  })
}

fn replace_fixture_images(name, prefix) {
  list.each(range(14), fn(i) {
    simplifile.write(
      fixture(name) <> "/targets/f" <> int.to_string(i),
      prefix <> "-" <> int.to_string(i),
    )
    |> should.equal(Ok(Nil))
  })
}

pub fn actual_terminal_history_does_not_override_current_known_wrong_images_test_() {
  #(Timeout, 60, fn() {
    let committed = start("terminal-old", fixture_boundary("terminal-old"))
    steps(committed.data, 18)
    get(committed.data, 2000).phase |> should.equal(p.Committed)
    c.stop(committed.data, 2000) |> should.equal(Ok(Nil))
    // Explicit synthetic external writer restores the KNOWN old image. This
    // falsifies goal consistency even though kernel image identity is valid.
    replace_fixture_images("terminal-old", "old")
    let assert Ok(restarted) =
      c.start_controller(
        native_config("terminal-old"),
        fixture_boundary("terminal-old"),
      )
    ready(restarted.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.Held("CHECKPOINT_CURRENT_IMAGES_MISMATCH"))
    let assert Ok(still) = c.reconcile_now(restarted.data, 20_000)
    still.outcome |> should.equal(c.Held("CHECKPOINT_CURRENT_IMAGES_MISMATCH"))
    c.stop(restarted.data, 2000) |> should.equal(Ok(Nil))

    let rolled_back = start("terminal-new", fixture_boundary("terminal-new"))
    steps(rolled_back.data, 5)
    let assert Ok(_) = recover_epoch(rolled_back.data, 8, 20_000)
    steps(rolled_back.data, 17)
    get(rolled_back.data, 2000).phase |> should.equal(p.RolledBack)
    c.stop(rolled_back.data, 2000) |> should.equal(Ok(Nil))
    replace_fixture_images("terminal-new", "new")
    let assert Ok(restarted) =
      c.start_controller(
        native_config("terminal-new"),
        fixture_boundary("terminal-new"),
      )
    ready(restarted.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.Held("CHECKPOINT_CURRENT_IMAGES_MISMATCH"))
    c.stop(restarted.data, 2000) |> should.equal(Ok(Nil))
  })
}

fn fault_config(name) {
  c.Configuration(
    ..native_config(name),
    native: wire.local_configuration(
      required("UOS_CUTOVER_TEST_GUARDIAN"),
      required("UOS_CUTOVER_TEST_GUARDIAN_SHA"),
      required("UOS_CUTOVER_TEST_FAULT_WORKER"),
      required("UOS_CUTOVER_TEST_FAULT_SHA"),
      fixture(name) <> "/config.json",
    ),
  )
}

fn wait_marker(name, deadline) {
  case simplifile.read(fixture(name) <> "/native-blocked.pid") {
    Ok(pid) -> {
      let assert Ok(_) = int.parse(pid)
      pid
    }
    Error(simplifile.Enoent) -> {
      let assert True = c.monotonic_ms() < deadline
      process.sleep(5)
      wait_marker(name, deadline)
    }
    Error(_) -> panic as "private marker unavailable"
  }
}

fn native_spawns(name) {
  case simplifile.read(fixture(name) <> "/native-spawns.log") {
    Ok(bytes) -> string.split(string.trim(bytes), "\n") |> list.length
    Error(simplifile.Enoent) -> 0
    Error(_) -> panic as "private spawn log unavailable"
  }
}

fn os_gone(pid) {
  case simplifile.read("/proc/" <> pid <> "/stat") {
    Error(simplifile.Enoent) -> True
    Ok(_) -> False
    Error(_) -> panic as "OS process observation failed"
  }
}

fn wait_os_gone(pid, deadline) {
  case os_gone(pid) {
    True -> Nil
    False -> {
      let assert True = c.monotonic_ms() < deadline
      process.sleep(5)
      wait_os_gone(pid, deadline)
    }
  }
}

pub fn unknown_quiescence_prevents_even_startup_native_probe_test_() {
  #(Timeout, 30, fn() {
    let assert Ok(owner) =
      c.start_controller(
        fault_config("startup-no-probe"),
        c.unavailable_boundary(),
      )
    ready(owner.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.Held("QUIESCENCE_UNVERIFIED"))
    native_spawns("startup-no-probe") |> should.equal(0)
    let assert Ok(held) = c.reconcile_now(owner.data, 2000)
    held.outcome |> should.equal(c.Held("QUIESCENCE_UNVERIFIED"))
    native_spawns("startup-no-probe") |> should.equal(0)
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
  })
}

pub fn actual_blocked_native_timeout_reaps_os_worker_and_fences_new_probes_test_() {
  #(Timeout, 30, fn() {
    let name = "native-timeout"
    let events = process.new_subject()
    let base = fixture_boundary(name)
    let boundary =
      c.Boundary(
        ..base,
        read_live: fn(request) {
          process.send(events, process.self())
          live(request)
        },
        confirm_quiescence: fn(_) {
          case simplifile.read(fixture(name) <> "/native-blocked.pid") {
            Error(simplifile.Enoent) -> Ok(Nil)
            _ -> Error("unknown")
          }
        },
      )
    let cfg = c.Configuration(..fault_config(name), command_timeout_ms: 1000)
    let assert Ok(owner) = c.start_controller(cfg, boundary)
    ready(owner.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.ReadyForCommand)
    advance(owner.data, 20) |> should.equal(Error("CONTROLLER_REPLY_TIMEOUT"))
    let assert Ok(worker) = process.receive(events, 2000)
    let wm = process.monitor(worker)
    let pid = wait_marker(name, c.monotonic_ms() + 5000)
    let assert Ok(_) = simplifile.read("/proc/" <> pid <> "/stat")
    let spawns = native_spawns(name)
    let settled = ready(owner.data, c.monotonic_ms() + 10_000)
    settled.outcome |> should.equal(c.Held("CUTOVER_WORKER_TIMEOUT_UNKNOWN"))
    process.is_alive(owner.pid) |> should.be_true
    await_down(worker, wm)
    let assert Ok(held) = c.reconcile_now(owner.data, 2000)
    held.outcome |> should.equal(c.Held("QUIESCENCE_UNVERIFIED"))
    native_spawns(name) |> should.equal(spawns)
    wait_os_gone(pid, c.monotonic_ms() + 5000)
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
    let confirmed =
      c.Boundary(..base, confirm_quiescence: fn(_) {
        case os_gone(pid) {
          True -> Ok(Nil)
          False -> Error("old_group_present")
        }
      })
    let assert Ok(restarted) = c.start_controller(cfg, confirmed)
    ready(restarted.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.Held("DURABLE_PENDING_REQUIRES_INSPECTION"))
    native_spawns(name) |> should.equal(spawns + 1)
    advance(restarted.data, 2000)
    |> should.equal(Error("CUTOVER_REQUIRES_RECONCILIATION"))
    actual_images(name, "old")
    c.stop(restarted.data, 2000) |> should.equal(Ok(Nil))
  })
}

fn native_owner_loss(name, abrupt) {
  let events = process.new_subject()
  let boundary =
    c.Boundary(..fixture_boundary(name), read_live: fn(request) {
      process.send(events, WorkerStarted(process.self()))
      live(request)
    })
  let parent =
    process.spawn_unlinked(fn() {
      let quit = process.new_subject()
      let assert Ok(owner) = c.start_controller(fault_config(name), boundary)
      process.send(events, OwnerReady(owner.pid, owner.data, quit))
      let _ = process.receive(quit, 30_000)
      Nil
    })
  let assert Ok(OwnerReady(owner_pid, controller, quit)) =
    process.receive(events, 2000)
  ready(controller, c.monotonic_ms() + 10_000).outcome
  |> should.equal(c.ReadyForCommand)
  advance(controller, 20) |> should.equal(Error("CONTROLLER_REPLY_TIMEOUT"))
  let assert Ok(WorkerStarted(worker)) = process.receive(events, 2000)
  let pid = wait_marker(name, c.monotonic_ms() + 5000)
  let assert Ok(_) = simplifile.read("/proc/" <> pid <> "/stat")
  let wm = process.monitor(worker)
  let om = process.monitor(owner_pid)
  let pm = process.monitor(parent)
  case abrupt {
    True -> process.kill(parent)
    False -> process.send(quit, Nil)
  }
  await_down(parent, pm)
  await_down(worker, wm)
  await_down(owner_pid, om)
  wait_os_gone(pid, c.monotonic_ms() + 5000)
  actual_images(name, "old")
}

pub fn actual_normal_and_abrupt_owner_loss_reaches_native_guardian_reap_test_() {
  #(Timeout, 30, fn() {
    native_owner_loss("native-owner-normal", False)
    native_owner_loss("native-owner-abrupt", True)
  })
}

pub fn monotonic_dispatch_deadline_is_strict_with_negative_epochs_test() {
  c.monotonic_before_deadline(-5001, -5000) |> should.be_true
  c.monotonic_before_deadline(-5000, -5000) |> should.be_false
  c.monotonic_before_deadline(-4999, -5000) |> should.be_false
}

fn observer_config(name) {
  c.Configuration(
    ..native_config(name),
    native: wire.local_configuration(
      required("UOS_CUTOVER_TEST_GUARDIAN"),
      required("UOS_CUTOVER_TEST_GUARDIAN_SHA"),
      required("UOS_CUTOVER_TEST_OBSERVER_WORKER"),
      required("UOS_CUTOVER_TEST_OBSERVER_SHA"),
      fixture(name) <> "/config.json",
    ),
  )
}

pub fn expiry_during_quiescence_uses_actual_dispatch_clock_and_no_native_marker_test_() {
  #(Timeout, 30, fn() {
    let flag = counter()
    let base = fixture_boundary("recover-fence")
    let boundary =
      c.Boundary(
        ..base,
        read_live: fn(request) {
          use e <- result.try(live(request))
          let past = actor.call(flag.data, 2000, Peek)
          case past > 0 {
            False -> Ok(e)
            True -> {
              let assert Some(task) = e.task
              let assert Some(grant) = task.grant
              // A stale collector's fake 'now' would make all these leases appear
              // valid. The actual host dispatch clock must reject them.
              Ok(
                c.LiveEvidence(
                  ..e,
                  observed_utc_ms: past - 1,
                  context: a.AdmissionContext(..e.context, now_ms: past - 1),
                  task: Some(
                    a.TaskFence(
                      ..task,
                      lease_until_ms: past,
                      grant: Some(a.GrantTicket(..grant, expires_at_ms: past)),
                    ),
                  ),
                  runtime: p.RuntimeObservation(
                    ..e.runtime,
                    observed_ms: past - 2,
                    lease_until_ms: past,
                  ),
                ),
              )
            }
          }
        },
        confirm_quiescence: fn(request: c.CommandContext) {
          case request.phase {
            p.RecoveryQuiescing ->
              actor.call(flag.data, 2000, fn(reply) {
                Set(utc_ms(Millisecond) - 1, reply)
              })
            _ -> Nil
          }
          Ok(Nil)
        },
      )
    let cfg = observer_config("recover-fence")
    let assert Ok(owner) = c.start_controller(cfg, boundary)
    ready(owner.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.ReadyForCommand)
    steps(owner.data, 3)
    let count = native_spawns("recover-fence")
    let assert Ok(held) = recover_epoch(owner.data, 8, 20_000)
    held.outcome |> should.equal(c.Held("TASK_LEASE_EXPIRED"))
    native_spawns("recover-fence") |> should.equal(count)
    held.epoch |> should.equal(7)
    let out =
      wire.exchange(
        cfg.native,
        wire.Binding(digest, digest, digest, 7, 3),
        "inspect",
        wire.empty_payload(),
      )
    let assert Ok(reply) = out.result
    list.count(reply.records, fn(r) { r.operation == "recovery_epoch" })
    |> should.equal(0)
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
    process.unlink(flag.pid)
    process.kill(flag.pid)
  })
}

pub fn blocking_quiescence_past_monotonic_deadline_cannot_spawn_native_test_() {
  #(Timeout, 30, fn() {
    let cfg =
      c.Configuration(
        ..fault_config("startup-deadline"),
        command_timeout_ms: 1000,
      )
    let boundary =
      c.Boundary(
        ..fixture_boundary("startup-deadline"),
        confirm_quiescence: fn(_) {
          process.sleep(1500)
          Ok(Nil)
        },
      )
    let assert Ok(owner) = c.start_controller(cfg, boundary)
    let held = ready(owner.data, c.monotonic_ms() + 10_000)
    held.outcome |> should.equal(c.Held("CUTOVER_WORKER_TIMEOUT_UNKNOWN"))
    native_spawns("startup-deadline") |> should.equal(0)
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
  })
}

pub fn stale_collector_time_is_evidence_not_current_dispatch_time_test_() {
  #(Timeout, 30, fn() {
    let cfg = observer_config("evidence-clock")
    let boundary =
      c.Boundary(..fixture_boundary("evidence-clock"), read_live: fn(request) {
        use e <- result.try(live(request))
        Ok(c.LiveEvidence(..e, observed_utc_ms: e.observed_utc_ms - 2000))
      })
    let assert Ok(owner) = c.start_controller(cfg, boundary)
    ready(owner.data, c.monotonic_ms() + 10_000).outcome
    |> should.equal(c.ReadyForCommand)
    let count = native_spawns("evidence-clock")
    let assert Ok(refused) = advance(owner.data, 2000)
    refused.outcome |> should.equal(c.Refused("LIVE_EVIDENCE_STALE_OR_FUTURE"))
    native_spawns("evidence-clock") |> should.equal(count)
    actual_images("evidence-clock", "old")
    c.stop(owner.data, 2000) |> should.equal(Ok(Nil))
  })
}
