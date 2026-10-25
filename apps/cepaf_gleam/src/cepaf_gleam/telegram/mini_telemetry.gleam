//// Local Mini backend collector; two-level supervision contains restart exhaustion.
//// Only fixed page enums/outcomes are retained. No identity, initData or payload.

import cepaf_gleam/ha/beam_metrics as beam
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_telemetry_state as state
import cepaf_gleam/telegram/types
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/otp/supervision
import gleam/result
import gleam/string

type Unit {
  Microsecond
  Second
}

type RuntimeName {
  UosTelegramMiniTelemetry
}

pub type Message {
  Begin(types.MiniAppPage, process.Subject(Result(state.Ticket, String)))
  Finish(state.Ticket, state.Outcome, process.Subject(Result(Nil, String)))
  Read(process.Subject(Result(state.Snapshot, String)))
}

@external(erlang, "gleam_erlang_ffi", "identity")
fn name(value: RuntimeName) -> process.Name(Message)

@external(erlang, "erlang", "monotonic_time")
fn mono(unit: Unit) -> Int

@external(erlang, "erlang", "system_time")
fn wall(unit: Unit) -> Int

@external(erlang, "mini_telemetry_ffi", "safe_call")
fn safe_call(call: fn() -> a) -> Result(a, String)

@external(erlang, "mini_telemetry_ffi", "protect_backend")
fn protect_backend(
  call: fn() -> api.Observation,
) -> Result(api.Observation, Nil)

@external(erlang, "beam_metrics_ffi", "snapshot_checked")
fn metrics(budget_ms: Int) -> Result(beam.BeamMetrics, String)

@external(erlang, "mini_telemetry_ffi", "logger_level")
fn logger_level() -> Result(String, String)

fn random_hex(bytes: Int) -> String {
  crypto.strong_random_bytes(bytes)
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn subject() -> process.Subject(Message) {
  process.named_subject(name(UosTelegramMiniTelemetry))
}

fn on_message(
  current: state.State,
  message: Message,
) -> actor.Next(state.State, Message) {
  let now = mono(Microsecond)
  case message {
    Begin(page, reply) -> {
      case
        state.begin(
          current,
          page,
          random_hex(16),
          random_hex(8),
          now,
          wall(Second),
        )
      {
        Ok(#(next, Some(ticket))) -> {
          process.send(reply, Ok(ticket))
          actor.continue(next)
        }
        Ok(#(next, None)) -> {
          process.send(reply, Error("telemetry_capacity"))
          actor.continue(next)
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(current)
        }
      }
    }
    Finish(ticket, outcome, reply) -> {
      // Retain expiry even if this finish targets an already expired ticket.
      let pruned = state.prune(current, now) |> result.unwrap(current)
      case state.finish(pruned, ticket, outcome, now) {
        Ok(next) -> {
          process.send(reply, Ok(Nil))
          actor.continue(next)
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(pruned)
        }
      }
    }
    Read(reply) -> {
      case state.prune(current, now) {
        Ok(next) -> {
          process.send(reply, Ok(state.snapshot(next)))
          actor.continue(next)
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(current)
        }
      }
    }
  }
}

fn start_collector() -> actor.StartResult(process.Subject(Message)) {
  // Executed by supervisor on every restart, not captured at first startup.
  let assert Ok(initial) =
    state.new(random_hex(16), mono(Microsecond), wall(Second))
  actor.new(initial)
  |> actor.on_message(on_message)
  |> actor.named(name(UosTelegramMiniTelemetry))
  |> actor.start
}

fn start_restart_supervisor() -> actor.StartResult(sup.Supervisor) {
  sup.new(sup.OneForOne)
  |> sup.restart_tolerance(3, 60)
  |> sup.add(supervision.worker(start_collector) |> supervision.timeout(1000))
  |> sup.start
}

pub fn start() -> actor.StartResult(sup.Supervisor) {
  // Temporary inner supervisor: restart-budget exhaustion leaves telemetry
  // unavailable without escalating to the linked HTTP caller.
  sup.new(sup.OneForOne)
  |> sup.add(
    supervision.supervisor(start_restart_supervisor)
    |> supervision.restart(supervision.Temporary),
  )
  |> sup.start
}

pub fn read() -> Result(state.Snapshot, String) {
  safe_call(fn() { process.call(subject(), 60, Read) }) |> result.flatten
}

pub fn with_span(
  page: types.MiniAppPage,
  run: fn() -> api.Observation,
) -> api.Observation {
  let ticket =
    safe_call(fn() {
      process.call(subject(), 60, fn(reply) { Begin(page, reply) })
    })
    |> result.flatten
  // Exceptions cannot retain a slot indefinitely. A crash is explicit unavailable.
  let observed =
    protect_backend(run)
    |> result.unwrap(api.Unavailable("backend_exception"))
  let outcome = case observed {
    api.Observed(_, _, _) -> state.Observed
    api.Unavailable(_) -> state.Unavailable
    api.Forbidden -> state.Forbidden
  }
  case ticket {
    Ok(t) -> {
      let _ =
        safe_call(fn() {
          process.call(subject(), 60, fn(reply) { Finish(t, outcome, reply) })
        })
      observed
    }
    Error(_) -> observed
  }
}

fn number(value: Int) -> String {
  int.to_string(value)
}

fn yes(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

pub fn observe() -> api.Observation {
  let observation = {
    use snapshot <- result.try(read())
    use vm <- result.try(metrics(100))
    use _ <- result.try(
      case
        list.all(
          [
            vm.scheduler_count, vm.process_count, vm.memory_total_mb,
            vm.memory_processes_mb, vm.memory_ets_mb, vm.memory_binary_mb,
            vm.run_queue_length, vm.uptime_seconds, vm.io_input_mb,
            vm.io_output_mb, vm.atom_count, vm.port_count,
          ],
          fn(n) { n >= 0 && n <= state.counter_limit },
        )
      {
        True -> Ok(Nil)
        False -> Error("invalid_vm_metrics")
      },
    )
    let level = logger_level() |> result.unwrap("UNAVAILABLE")
    let spans =
      list.index_map(snapshot.recent, fn(s, index) {
        #(
          "Span " <> number(index + 1),
          types.page_to_path(s.page)
            <> " | "
            <> state.outcome_name(s.outcome)
            <> " | duration_us="
            <> number(s.duration_us)
            <> " | started_at_unix="
            <> number(s.started_at)
            <> " | trace_id="
            <> s.trace_id
            <> " | span_id="
            <> s.span_id,
        )
      })
    let fields = [
      #("Runtime admission", "NOT_GRANTED"),
      #(
        "Scope",
        "This Mini App server VM; authorized backend reads only. No fleet or distributed trace coverage.",
      ),
      #("Collector epoch", snapshot.epoch),
      #("Collector started at Unix seconds", number(snapshot.started_at)),
      #(
        "Persistence",
        "Volatile bounded buffer; collector restart resets counts and changes epoch.",
      ),
      #("Active traces", number(snapshot.active)),
      #("Accepted spans", number(snapshot.accepted)),
      #("Completed spans", number(snapshot.completed)),
      #("Dropped spans", number(snapshot.dropped)),
      #("Expired spans", number(snapshot.expired)),
      #("Counters saturated", yes(snapshot.saturated)),
      #("Retained spans", number(list.length(snapshot.recent))),
      #(
        "Retention",
        "20 newest completed spans; 128 inflight; 30-second inflight expiry.",
      ),
      #("VM logger level", level),
      #("Log level controls", "Not implemented; displayed level is read-only."),
      #("Distributed span ingestion", "Not implemented."),
      #(
        "Rate limit configuration",
        "Not established by this telemetry observation.",
      ),
      #("VM schedulers", number(vm.scheduler_count)),
      #("VM processes", number(vm.process_count)),
      #("VM total memory MiB", number(vm.memory_total_mb)),
      #("VM process memory MiB", number(vm.memory_processes_mb)),
      #("VM ETS memory MiB", number(vm.memory_ets_mb)),
      #("VM binary memory MiB", number(vm.memory_binary_mb)),
      #("VM run queue", number(vm.run_queue_length)),
      #("VM uptime seconds", number(vm.uptime_seconds)),
      #("VM cumulative input MiB", number(vm.io_input_mb)),
      #("VM cumulative output MiB", number(vm.io_output_mb)),
      #("VM atoms", number(vm.atom_count)),
      #("VM ports", number(vm.port_count)),
      #(
        "Metric sampling",
        "Sequential VM counters; not atomic, CPU percentage, or per-second rates.",
      ),
      ..spans
    ]
    Ok(api.Observed(
      wall(Second),
      "local_mini_telemetry",
      dict.from_list(fields),
    ))
  }
  observation |> result.unwrap(api.Unavailable("telemetry_unavailable"))
}
