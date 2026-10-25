import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_lifecycle_adapter as lifecycle
import cepaf_gleam/harness/telegram_loop as loop
import cepaf_gleam/harness/telegram_service as service
import gleam/erlang/process
import gleam/option.{None}
import gleam/otp/actor
import gleam/result

pub type StartMode {
  Fresh(writer: codec.WriterRegistration)
  Recover(
    previous: codec.WriterRegistration,
    writer: codec.WriterRegistration,
    receipt: lifecycle.UnitCleanupReceipt,
  )
}

type RuntimeEvent {
  TerminalReceived(loop.Terminal)
  DriverDown
}

const down_timeout_ms = 1000

pub fn run(
  config: service.ServiceConfiguration,
  current_path: String,
  mode: StartMode,
  budget: loop.Config,
) -> Result(loop.Terminal, String) {
  use _ <- result.try(loop.validate(budget))
  use svc <- result.try(start_service(config, current_path, mode))

  let observer = process.new_subject()
  case loop.start(svc.actor_subject, budget, observer) {
    Error(start_err) ->
      case service.stop_managed_service(svc) {
        Ok(_) -> Error(start_err)
        Error(cleanup_err) ->
          Error(start_err <> "; cleanup_failed: " <> cleanup_err)
      }

    Ok(driver) -> await_driver(svc, driver, observer, budget)
  }
}

fn start_service(
  config: service.ServiceConfiguration,
  current_path: String,
  mode: StartMode,
) -> Result(service.SupervisedService, String) {
  case mode {
    Fresh(writer) ->
      service.start_active_managed_service(config, current_path, writer, None)
    Recover(previous, writer, receipt) ->
      service.recover_active_managed_service(
        config,
        current_path,
        previous,
        writer,
        receipt,
      )
  }
}

fn await_driver(
  svc: service.SupervisedService,
  driver: actor.Started(process.Subject(loop.Message)),
  observer: process.Subject(loop.Terminal),
  budget: loop.Config,
) -> Result(loop.Terminal, String) {
  process.unlink(driver.pid)
  let monitor = process.monitor(driver.pid)

  let selector =
    process.new_selector()
    |> process.select_map(observer, TerminalReceived)
    |> process.select_specific_monitor(monitor, fn(_) { DriverDown })

  let down_selector =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_) { DriverDown })

  case
    process.selector_receive(
      from: selector,
      within: budget.lifetime_ms + down_timeout_ms,
    )
  {
    Ok(TerminalReceived(terminal)) ->
      case wait_for_down(down_selector) {
        Ok(Nil) -> {
          process.demonitor_process(monitor)
          use _ <- result.try(service.stop_managed_service(svc))
          Ok(terminal)
        }
        Error(Nil) ->
          force_kill_and_cleanup(
            svc,
            driver.pid,
            monitor,
            down_selector,
            "driver_down_unconfirmed_after_terminal",
          )
      }

    Ok(DriverDown) -> {
      process.demonitor_process(monitor)
      stop_managed_and_fail(svc, "driver_died_without_terminal")
    }

    Error(Nil) -> {
      process.send(driver.data, loop.Stop)
      case wait_for_down(down_selector) {
        Ok(Nil) -> {
          process.demonitor_process(monitor)
          stop_managed_and_fail(svc, "driver_lifetime_expired")
        }
        Error(Nil) ->
          force_kill_and_cleanup(
            svc,
            driver.pid,
            monitor,
            down_selector,
            "driver_lifetime_expired",
          )
      }
    }
  }
}

fn wait_for_down(
  down_selector: process.Selector(RuntimeEvent),
) -> Result(Nil, Nil) {
  case process.selector_receive(from: down_selector, within: down_timeout_ms) {
    Ok(DriverDown) -> Ok(Nil)
    Ok(TerminalReceived(_)) -> Error(Nil)
    Error(Nil) -> Error(Nil)
  }
}

fn force_kill_and_cleanup(
  svc: service.SupervisedService,
  driver_pid: process.Pid,
  monitor: process.Monitor,
  down_selector: process.Selector(RuntimeEvent),
  reason: String,
) -> Result(loop.Terminal, String) {
  process.kill(driver_pid)
  case wait_for_down(down_selector) {
    Ok(Nil) -> {
      process.demonitor_process(monitor)
      stop_managed_and_fail(svc, reason)
    }
    Error(Nil) -> {
      process.demonitor_process(monitor)
      case service.stop_supervised_service(svc) {
        Ok(_) -> Error("cleanup_unconfirmed: " <> reason)
        Error(stop_err) ->
          Error("cleanup_unconfirmed: " <> reason <> "; " <> stop_err)
      }
    }
  }
}

fn stop_managed_and_fail(
  svc: service.SupervisedService,
  reason: String,
) -> Result(loop.Terminal, String) {
  case service.stop_managed_service(svc) {
    Ok(_) -> Error(reason)
    Error(cleanup_err) ->
      Error(reason <> "; cleanup_failed: " <> cleanup_err)
  }
}
