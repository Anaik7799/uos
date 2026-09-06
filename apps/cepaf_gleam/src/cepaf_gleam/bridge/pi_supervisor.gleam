//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_supervisor</module>
////     <fsharp-lineage>No F# lineage — Gleam-native OTP supervisor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Pi-mono RPC Daemon Supervisor</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-RUNTIME-001, SC-PI-RUNTIME-003, SC-PI-RUNTIME-006,
////       SC-ARCH-SPLIT-003, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="erlang-otp-supervisor">
////       Pi-mono Node.js lifecycle ↪ BEAM OTP static supervisor
////       (gleam_otp static_supervisor, OneForOne, intensity=5, period=10s).
////       Mitigation: max 5 restarts per 10 seconds; after threshold the
////       supervisor itself exits so the parent tree can escalate.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi Supervisor — OTP supervisor wrapping the Pi daemon actor.
////
//// Architecture:
////   - Strategy: OneForOne  (only the crashed child restarts)
////   - Max restarts: 5 per 10 seconds  (SC-PI-RUNTIME-003)
////   - Child: pi_daemon worker (permanent restart policy)
////   - Exposes: start/0, start_with_config/1

import cepaf_gleam/bridge/pi_daemon
import cepaf_gleam/bridge/pi_runtime.{type RuntimeConfig}
import cepaf_gleam/ui/domain.{Bridge}
import cepaf_gleam/ui/zenoh_otel.{Observe}
import gleam/erlang/process.{type Pid}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

// =============================================================================
// Types
// =============================================================================

/// The supervisor's subject type — opaque wrapper around the static supervisor.
pub type PiSupervisor {
  PiSupervisor(sv: supervisor.Supervisor)
}

// =============================================================================
// Public API
// =============================================================================

/// Start the Pi supervisor with default config.
/// Intensity = 5, period = 10s (SC-PI-RUNTIME-003).
pub fn start() -> Result(PiSupervisor, String) {
  start_with_config(pi_runtime.default_config())
}

/// Start the Pi supervisor with a custom RuntimeConfig.
pub fn start_with_config(
  config: RuntimeConfig,
) -> Result(PiSupervisor, String) {
  zenoh_otel.emit(Bridge, "pi_supervisor_start", Observe)

  let child_spec = supervision.worker(fn() { daemon_start_child(config) })

  let result =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.restart_tolerance(intensity: 5, period: 10)
    |> supervisor.add(child_spec)
    |> supervisor.start()

  case result {
    Ok(started) -> Ok(PiSupervisor(sv: started.data))
    Error(err) ->
      Error("pi_supervisor failed to start: " <> start_error_to_string(err))
  }
}

// =============================================================================
// Internal helpers
// =============================================================================

/// Adapts pi_daemon.start to the signature expected by supervision.worker.
/// Returns actor.Started(Nil) with the daemon's PID on success.
fn daemon_start_child(
  config: RuntimeConfig,
) -> Result(actor.Started(Nil), actor.StartError) {
  case pi_daemon.start(config) {
    Ok(daemon) -> Ok(actor.Started(pid: daemon_pid(daemon), data: Nil))
    Error(reason) -> Error(actor.InitFailed(reason))
  }
}

/// Extract the BEAM Pid from a PiDaemon for OTP supervision tracking.
fn daemon_pid(daemon: pi_daemon.PiDaemon) -> Pid {
  pi_daemon.pid(daemon)
}

fn start_error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitFailed(reason) -> "init_failed: " <> reason
    actor.InitTimeout -> "init_timeout"
    actor.InitExited(_) -> "init_exited"
  }
}
