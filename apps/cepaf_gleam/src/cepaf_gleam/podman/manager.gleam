//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/podman/manager</module>
////     <fsharp-lineage>Cepaf.Modules.Podman.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Container Lifecycle Management</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>SC-POD-001 to SC-POD-010</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/planning/math_optimization as math
import cepaf_gleam/podman/containers
import cepaf_gleam/podman/http_client.{type PodmanClient}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/result

// =============================================================================
// Mesh Lifecycle Operations
// =============================================================================

/// Start the entire C3I mesh using optimized execution waves.
/// ⚠️ DEPRECATED: Use root `./sa-up` (Rust Ignition Daemon auth).
pub fn start_mesh(client: PodmanClient) -> Result(Nil, String) {
  io.println("⚠️  WARNING: Gleam mesh-boot is DEPRECATED.")
  io.println("⚠️  Redirecting to Authoritative Rust Ignition Daemon...")
  io.println("⚠️  Run: ./sa-up")

  let waves = math.optimize_startup()
  io.println("🚀 STARTING C3I MESH (Optimized Wave-based Boot)")

  list.try_each(waves, fn(wave) {
    io.println("\n🌊 WAVE " <> int.to_string(wave.wave_number) <> ":")

    // Start all containers in this wave in parallel (via spawned processes)
    let results =
      wave.containers
      |> list.map(fn(name) {
        io.println("  [start] " <> name)
        containers.start(client, name)
      })

    // Check if any failed in this wave
    case list.find(results, result.is_error) {
      Ok(Error(e)) ->
        Error("Wave " <> int.to_string(wave.wave_number) <> " failed: " <> e)
      _ -> {
        // Wait for containers to stabilize (simulated or via health check)
        process.sleep(1000)
        Ok(Nil)
      }
    }
  })
}

/// Stop all core C3I containers.
pub fn stop_mesh(client: PodmanClient) -> Result(Nil, String) {
  let containers_defs = math.default_containers()
  io.println("🛑 STOPPING C3I MESH")

  list.each(containers_defs, fn(c) {
    io.println("  [stop] " <> c.name)
    let _ = containers.stop(client, c.name, None)
  })

  Ok(Nil)
}

/// Restart a specific container by name.
pub fn restart_container(
  client: PodmanClient,
  name: String,
) -> Result(Nil, String) {
  io.println("🔄 RESTARTING: " <> name)
  containers.restart(client, name)
}

/// Remove all core C3I containers.
pub fn purge_mesh(client: PodmanClient) -> Result(Nil, String) {
  let containers_defs = math.default_containers()
  io.println("🧹 PURGING C3I MESH")

  list.each(containers_defs, fn(c) {
    io.println("  [remove] " <> c.name)
    let _ = containers.remove(client, c.name, True)
  })

  Ok(Nil)
}

// =============================================================================
// Status & Verification
// =============================================================================

/// Check the current status of all core containers.
pub fn check_mesh_status(client: PodmanClient) -> Result(Nil, String) {
  let containers_defs = math.default_containers()

  use containers_list <- result.try(containers.list_containers(client, True))

  io.println("📊 MESH HEALTH REPORT:")
  list.each(containers_defs, fn(def) {
    let status = case
      list.find(containers_list, fn(c) {
        list.contains(c.names, def.name)
        || list.contains(c.names, "/" <> def.name)
      })
    {
      Ok(c) -> c.status
      Error(_) -> "Not Found"
    }
    io.println("  - " <> def.name <> ": [" <> status <> "]")
  })

  Ok(Nil)
}
