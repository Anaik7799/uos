//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam</module>
////     <fsharp-lineage>Cepaf.SIL6MeshOrchestrator.Program.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>Master Orchestrator Entry Point</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-MESH-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="otp-application">
////       F# `IHostBuilder.Run()` ↪ Gleam OTP Main Execution Thread.
////       Mitigation: `erlang/process.sleep_forever()` explicitly halts the main execution thread to sustain background worker processes, mimicking .NET's daemon loop.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/agents/cybernetic
import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/planning/cli
import cepaf_gleam/podman/containers
import cepaf_gleam/podman/domain.{PodmanClientConfig, Rootless}
import cepaf_gleam/podman/http_client
import cepaf_gleam/telemetry/exporter
import cepaf_gleam/uos_sup
import cepaf_gleam/verification/swarm
import cepaf_gleam/web/server as web_server
import cepaf_gleam/zenoh/client as zenoh
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "get_uid")
fn get_uid() -> String

@external(erlang, "cepaf_gleam_ffi", "get_arguments")
fn get_arguments() -> List(String)

pub fn main() {
  io.println("🚀 CEPAF Gleam Orchestrator - Unified Swarm Execution")
  io.println("=====================================================")

  let args = get_arguments()

  // 0. OTel Boot Span (SC-OTEL-002)
  case exporter.export_span("c3i.boot", 0.0, "ok", []) {
    Ok(Nil) -> io.println("  [otel] Boot span exported to collector")
    Error(e) -> io.println("  [otel] Boot span export failed: " <> e)
  }

  // 0.1 Start Biomorphic Agent Hierarchy (L7-L0)
  let _ = case
    list.contains(args, "--serve") || list.contains(args, "--daemon")
  {
    True -> {
      io.println("  [agents] Starting 3-layer autonomous hierarchy...")
      let _ = cybernetic.start_executive_supervisor()
      io.println("  [sup] Starting root OTP supervisor with homeostasis engine...")
      let assert Ok(_) = uos_sup.start_root_supervisor()
        as "Root supervision must start before autonomous serving"
      Nil
    }
    False -> Nil
  }

  // 1. Planning Module Execution
  case args {
    [] -> {
      io.println("\n📅 PLANNING & TASK STATUS:")
      cli.run(["status"])
    }
    _ -> cli.run(args)
  }

  // 2. Podman & Swarm Verification
  let uid = get_uid()
  let socket_path = "/run/user/" <> uid <> "/podman/podman.sock"
  let config =
    PodmanClientConfig(
      socket: Rootless(uid: uid, path: socket_path),
      api_version: "5.7.0",
      timeout_ms: 30_000,
      retry_count: 3,
      retry_delay_ms: 1000,
    )
  let client = http_client.create(config)

  io.println("\n🏢 FETCHING CONTAINER STATUS:")
  case containers.list_containers(client, True) {
    Ok(containers_list) -> {
      let names =
        list.map(containers_list, fn(c) {
          case list.first(c.names) {
            Ok(n) -> n
            Error(_) -> "unknown"
          }
        })

      list.each(containers_list, fn(c) {
        let name = case list.first(c.names) {
          Ok(n) -> n
          Error(_) -> "unknown"
        }
        io.println(
          "  - " <> name <> " (" <> c.image <> ") [" <> c.status <> "]",
        )
      })

      io.println("\n💊 RUNNING SIL-6 HEALTH VERIFICATION:")
      case swarm.verify_container_health(client, names) {
        Ok(#(healthy, total)) -> {
          io.println(
            "  Healthy Containers: "
            <> int.to_string(healthy)
            <> "/"
            <> int.to_string(total),
          )
        }
        Error(e) -> io.println("  ❌ Health check failed: " <> e)
      }
    }
    Error(_) -> io.println("  ❌ Error listing containers")
  }

  // 3. Zenoh IPC — Open session via native NIF first, fallback to FFI
  io.println("\n📡 ZENOH IPC INTEGRATION:")
  // Try native NIF first (SC-ZENOH-001)
  let nif_result = c3i_nif.zenoh_open("{}")
  let native_zenoh_connected =
    string.contains(nif_result, "\"status\":\"connected\"")
  let zenoh_session = case native_zenoh_connected {
    True -> {
      io.println("  ✅ Zenoh NIF connected: " <> nif_result)
      let _ = c3i_nif.zenoh_put("indrajaal/cepaf/gleam/status", "online")
      io.println("  ✅ Status published via NIF")
      // Try the FFI session for backward compat
      case zenoh.open("{\"mode\": \"client\"}") {
        Ok(session) -> option.Some(session)
        Error(_) -> option.None
      }
    }
    False -> {
      io.println("  ⚠️ Zenoh NIF: " <> nif_result)
      // Fallback to FFI
      case zenoh.open("{\"mode\": \"client\"}") {
        Ok(session) -> {
          io.println("  ✅ Zenoh FFI session opened")
          option.Some(session)
        }
        Error(e) -> {
          io.println("  ❌ Zenoh unavailable: " <> e)
          option.None
        }
      }
    }
  }
  // Log Zenoh session availability for agents
  case zenoh_session {
    option.Some(_) ->
      io.println("  [agents] Zenoh session available for AG-UI events")
    option.None ->
      case native_zenoh_connected {
        True ->
          io.println(
            "  [agents] Zenoh native NIF available for AG-UI status events",
          )
        False ->
          io.println("  [agents] Zenoh unavailable — AG-UI events will no-op")
      }
  }

  // 4. Runtime Mode Selection
  case list.contains(args, "--serve") {
    True -> {
      io.println("\n🌐 STARTING HTTP SERVER MODE (port 4100)...")
      case web_server.start(4100) {
        Ok(_) -> Nil
        Error(e) -> io.println("❌ Server failed: " <> e)
      }
    }
    False ->
      case list.contains(args, "--daemon") {
        True -> {
          io.println("\n🛑 ENTERING SIL-6 DAEMON MODE. Sleeping forever...")
          process.sleep_forever()
        }
        False -> {
          io.println("\n✅ Execution complete. Exiting...")
          Nil
        }
      }
  }
}
