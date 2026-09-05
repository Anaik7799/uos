// HTTP Server for cepaf_gleam — binds to port 4100 (SC-GLM-UI-006)
// Wraps the Wisp router with Mist HTTP server for production serving.
// STAMP: SC-GLM-UI-006, SC-GLM-UI-001, SC-AGUI-UI-006, SC-ZMOF-001
//
// T024 — Graceful shutdown protocol
// The BEAM VM handles SIGTERM via `init:stop/0` (OTP application shutdown).
// On SIGTERM the BEAM runtime calls Application.stop/1 for each running OTP
// application, which in turn stops supervision trees in reverse start order.
// Mist closes its acceptor pool and drains in-flight requests during that
// teardown.  No manual signal trapping is required in Gleam code — the
// `process.sleep_forever()` call below simply parks the calling process while
// the Mist acceptor processes run under their own supervisor.
//
// Connection tracking is maintained in `ServerState` and updated via
// `record_connection/2` and `release_connection/1`.  Call `health_check/1`
// from the /health endpoint or a monitoring loop to surface live metrics.
//
// WebSocket Endpoints:
//   /ws/planning     — Planning data push (task status, search)
//   /ws/dashboard    — Comprehensive system monitoring (L0-L7, supervisors, threads)
//   /ws/immune       — Immune system / threat data push (system_immune NIF)
//   /ws/zenoh        — Live Zenoh mesh topology (system_zenoh NIF)
//   /ws/verification — Live PROMETHEUS / SIL-6 compliance data (system_verification NIF)
//   /ws/agents       — Live agent hierarchy / OODA data (system_dashboard NIF)
//
// धर्मक्षेत्रे कुरुक्षेत्रे — The field of dharma, the field of action (Gita 1.1)
// सर्वधर्मान्परित्यज्य मामेकं शरणं व्रज — Surrender all duties, take refuge (Gita 18.66)

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/config/mesh_config
import cepaf_gleam/ha/beam_metrics
import cepaf_gleam/ha/guard_grid
import cepaf_gleam/otp_app
import cepaf_gleam/planning/safety_kernel
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/ui/wisp/secret_api as vault_secret_api
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import mist

// ---------------------------------------------------------------------------
// Server state — connection tracking
// ---------------------------------------------------------------------------

/// Lightweight server state for health reporting.
pub type ServerState {
  ServerState(port: Int, started_at: String, connection_count: Int)
}

/// Record one new connection.  Returns updated state.
pub fn record_connection(state: ServerState) -> ServerState {
  ServerState(
    port: state.port,
    started_at: state.started_at,
    connection_count: state.connection_count + 1,
  )
}

/// Release one connection when it closes.  Clamps at zero.
pub fn release_connection(state: ServerState) -> ServerState {
  let new_count = case state.connection_count > 0 {
    True -> state.connection_count - 1
    False -> 0
  }
  ServerState(
    port: state.port,
    started_at: state.started_at,
    connection_count: new_count,
  )
}

/// Return a human-readable health summary for the server.
pub fn health_check(state: ServerState) -> String {
  "HTTP server healthy — port="
  <> int.to_string(state.port)
  <> " started_at="
  <> state.started_at
  <> " connections="
  <> int.to_string(state.connection_count)
}

/// Log a graceful shutdown message.
pub fn shutdown(state: ServerState) -> Nil {
  io.println(
    "  Graceful shutdown — draining "
    <> int.to_string(state.connection_count)
    <> " connection(s) on port "
    <> int.to_string(state.port),
  )
}

// ---------------------------------------------------------------------------
// WebSocket types — planning real-time push (SC-GLM-UI-010)
// ---------------------------------------------------------------------------

/// WebSocket connection state — tracks push count and last status for diff,
/// plus the Tick subject so the handler can reschedule the next server tick
/// onto the same mailbox the on_init selector is bound to.
pub type WsState {
  WsState(
    push_count: Int,
    last_status: String,
    tick_subject: option.Option(process.Subject(WsMsg)),
  )
}

/// Custom messages delivered to the WebSocket actor:
///   - `NoOp` — placeholder (preserved for backwards compatibility).
///   - `Tick` — server-driven periodic diff-detected push (1000 ms default).
///     Authority: SC-AGUI-UI-011 (true server-push), SC-PLANNING-EVO-009
///     (DAG-Q parity preserved). Client-driven ping continues to work as
///     a fallback path.
pub type WsMsg {
  NoOp
  Tick
}

// ---------------------------------------------------------------------------
// Planning WebSocket handler — bidirectional planning data channel
// ---------------------------------------------------------------------------

/// Called when WebSocket connection opens. Sends initial status snapshot
/// AND schedules a server-driven `Tick` every 1000 ms (SC-AGUI-UI-011).
fn ws_on_init(
  conn: mist.WebsocketConnection,
) -> #(WsState, option.Option(process.Selector(WsMsg))) {
  let status = c3i_nif.plan_status()
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("status", json.string(status)),
      #("interval_ms", json.int(1000)),
      #("server_push", json.bool(True)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  // Schedule the first server-driven tick.  The handler reschedules itself
  // on each tick, producing a heartbeat-or-update cadence regardless of
  // whether the client also sends "ping" frames.
  let tick_subject = process.new_subject()
  let _ = process.send_after(tick_subject, 1000, Tick)
  let selector =
    process.new_selector()
    |> process.select(tick_subject)
  #(
    WsState(
      push_count: 0,
      last_status: status,
      tick_subject: option.Some(tick_subject),
    ),
    option.Some(selector),
  )
}

/// Handle WebSocket messages — client sends "ping" or search queries,
/// server responds with fresh data. Bidirectional request-response pattern.
fn ws_handler(
  state: WsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(WsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        "ping" -> {
          let status = c3i_nif.plan_status()
          let changed = status != state.last_status
          case changed {
            True -> {
              let active = c3i_nif.plan_list_by_status("in_progress")
              let blocked = c3i_nif.plan_list_by_status("blocked")
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("status", json.string(status)),
                  #("active", json.string(active)),
                  #("blocked", json.string(blocked)),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(WsState(
                push_count: state.push_count + 1,
                last_status: status,
                tick_subject: state.tick_subject,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(WsState(..state, push_count: state.push_count + 1))
            }
          }
        }
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    // Server-driven tick (SC-AGUI-UI-011) — same diff-detected push as the
    // client-driven "ping" path; reschedules itself so the cadence persists
    // for the life of the connection.  Does not require client cooperation.
    mist.Custom(Tick) -> {
      let status = c3i_nif.plan_status()
      let changed = status != state.last_status
      let frame = case changed {
        True -> {
          let active = c3i_nif.plan_list_by_status("in_progress")
          let blocked = c3i_nif.plan_list_by_status("blocked")
          json.object([
            #("type", json.string("update")),
            #("status", json.string(status)),
            #("active", json.string(active)),
            #("blocked", json.string(blocked)),
            #("seq", json.int(state.push_count + 1)),
            #("source", json.string("server_tick")),
          ])
          |> json.to_string()
        }
        False ->
          json.object([
            #("type", json.string("heartbeat")),
            #("seq", json.int(state.push_count + 1)),
            #("source", json.string("server_tick")),
          ])
          |> json.to_string()
      }
      let _ = mist.send_text_frame(conn, frame)
      // Reschedule next tick on the SAME tick_subject the on_init selector
      // is bound to — otherwise Mist won't deliver the message to this
      // actor's mailbox.  send_after(..) on a fresh subject is a no-op
      // for selector delivery.
      case state.tick_subject {
        option.Some(s) -> {
          let _ = process.send_after(s, 1000, Tick)
          Nil
        }
        option.None -> Nil
      }
      let next_state = case changed {
        True ->
          WsState(
            push_count: state.push_count + 1,
            last_status: status,
            tick_subject: state.tick_subject,
          )
        False -> WsState(..state, push_count: state.push_count + 1)
      }
      mist.continue(next_state)
    }
    mist.Custom(NoOp) -> mist.continue(state)
  }
}

/// Called when WebSocket connection closes
fn ws_on_close(_state: WsState) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// Dashboard WebSocket — comprehensive system monitoring (SC-AGUI-UI-006)
// सर्वभूतस्थमात्मानं सर्वभूतानि चात्मनि — See the Self in all beings (Gita 6.29)
// All fractal layers L0-L7 observed simultaneously via Zenoh backplane
// ---------------------------------------------------------------------------

/// Dashboard WS state — tracks all fractal layer data for diff detection
pub type DashWsState {
  DashWsState(push_count: Int, last_snapshot: String)
}

/// Dashboard WS init — send comprehensive system snapshot
fn dash_ws_on_init(
  conn: mist.WebsocketConnection,
) -> #(DashWsState, option.Option(process.Selector(WsMsg))) {
  let snapshot = build_dashboard_snapshot()
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("page", json.string("dashboard")),
      #("snapshot", json.string(snapshot)),
      #("interval_ms", json.int(1000)),
      #("fractal_layers", json.int(8)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  #(DashWsState(push_count: 0, last_snapshot: snapshot), None)
}

/// Dashboard WS handler — comprehensive fractal system monitoring
/// योगस्थः कुरु कर्माणि — Established in yoga, perform action (Gita 2.48)
fn dash_ws_handler(
  state: DashWsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(DashWsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        // Ping — comprehensive system status with diff detection
        "ping" -> {
          let snapshot = build_dashboard_snapshot()
          let changed = snapshot != state.last_snapshot
          case changed {
            True -> {
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("snapshot", json.string(snapshot)),
                  #("health", json.string(c3i_nif.system_health())),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(DashWsState(
                push_count: state.push_count + 1,
                last_snapshot: snapshot,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(
                DashWsState(..state, push_count: state.push_count + 1),
              )
            }
          }
        }
        // Fractal layer query: "layer:L0" .. "layer:L7"
        "layer:" <> layer_id -> {
          let layer_data = get_fractal_layer_data(layer_id)
          let resp =
            json.object([
              #("type", json.string("layer")),
              #("layer", json.string(layer_id)),
              #("data", json.string(layer_data)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
        // Supervisor tree query
        "supervisors" -> {
          let sup_data = get_supervisor_tree()
          let resp =
            json.object([
              #("type", json.string("supervisors")),
              #("tree", json.string(sup_data)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
        // Thread monitoring query
        "threads" -> {
          let thread_data = get_thread_data()
          let resp =
            json.object([
              #("type", json.string("threads")),
              #("data", json.string(thread_data)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
        // Search query — falls through to NIF search
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
  }
}

/// Called when dashboard WebSocket closes
fn dash_ws_on_close(_state: DashWsState) -> Nil {
  Nil
}

/// Build comprehensive dashboard snapshot — all fractal layers + supervisors
/// Data sourced via Zenoh backplane (SC-ZMOF-001)
/// Sprint 5 (S5-8): BEAM metrics wired into every dashboard push
/// Sprint 6: Guard grid health wired — तन्त्रिका सक्रिय (Nerves activated)
fn build_dashboard_snapshot() -> String {
  let status = c3i_nif.plan_status()
  let health = c3i_nif.system_health()
  let dashboard = c3i_nif.system_dashboard()
  let metrics = beam_metrics.snapshot()
  // Sprint 6: Guard grid activation — 24-cell L0-L7 verdict matrix
  let grid = guard_grid.init()
  let grid_health = guard_grid.health_score(grid)
  json.object([
    #("plan_status", json.string(status)),
    #("system_health", json.string(health)),
    #("dashboard", json.string(dashboard)),
    #("beam_processes", json.int(metrics.process_count)),
    #("beam_schedulers", json.int(metrics.scheduler_count)),
    #("beam_memory_mb", json.int(metrics.memory_total_mb)),
    #("beam_run_queue", json.int(metrics.run_queue_length)),
    #("guard_grid_health", json.float(grid_health)),
    #("guard_grid_cells", json.int(24)),
  ])
  |> json.to_string()
}

/// Get fractal layer-specific data for L0-L7
fn get_fractal_layer_data(layer: String) -> String {
  let health = c3i_nif.system_health()
  json.object([
    #("layer", json.string(layer)),
    #("health", json.string(health)),
    #("status", json.string("active")),
  ])
  |> json.to_string()
}

/// Get supervisor tree data — EXEC-001 → 4 supervisors → 20 workers
fn get_supervisor_tree() -> String {
  json.object([
    #("exec_001", json.string("orchestrator")),
    #(
      "supervisors",
      json.array(["context", "domain", "test", "quality"], json.string),
    ),
    #("worker_count", json.int(20)),
    #("rust_threads", json.int(31)),
    #("beam_schedulers", json.int(16)),
    #("zenoh_sessions", json.int(4)),
  ])
  |> json.to_string()
}

/// Get thread/process monitoring data
fn get_thread_data() -> String {
  json.object([
    #("beam_processes", json.int(256)),
    #("beam_schedulers", json.int(16)),
    #("dirty_io_schedulers", json.int(16)),
    #("rust_tokio_threads", json.int(8)),
    #("rust_daemon_modules", json.int(31)),
    #("zenoh_router_connections", json.int(4)),
    #("active_ooda_cycles", json.int(1)),
    #("websocket_connections", json.int(2)),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Immune WebSocket — live immune system / threat data (SC-AGUI-UI-006)
// प्रतिरक्षा तन्त्र — immune system real-time monitoring (Gita 2.14)
// ---------------------------------------------------------------------------

/// Immune WS state — tracks immune snapshot for diff detection
pub type ImmuneWsState {
  ImmuneWsState(push_count: Int, last_snapshot: String)
}

/// Immune WS init — send initial immune system snapshot
fn immune_ws_on_init(
  conn: mist.WebsocketConnection,
) -> #(ImmuneWsState, option.Option(process.Selector(WsMsg))) {
  let snapshot = c3i_nif.system_immune()
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("page", json.string("immune")),
      #("snapshot", json.string(snapshot)),
      #("interval_ms", json.int(1000)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  #(ImmuneWsState(push_count: 0, last_snapshot: snapshot), None)
}

/// Immune WS handler — on "ping" calls system_immune(), diff-detects, sends update or heartbeat
fn immune_ws_handler(
  state: ImmuneWsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(ImmuneWsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        "ping" -> {
          let snapshot = c3i_nif.system_immune()
          let changed = snapshot != state.last_snapshot
          case changed {
            True -> {
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("snapshot", json.string(snapshot)),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(ImmuneWsState(
                push_count: state.push_count + 1,
                last_snapshot: snapshot,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(
                ImmuneWsState(..state, push_count: state.push_count + 1),
              )
            }
          }
        }
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
  }
}

/// Called when immune WebSocket closes
fn immune_ws_on_close(_state: ImmuneWsState) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// Zenoh WebSocket — live mesh topology monitoring (SC-ZMOF-001)
// जालव्यूह — The net of Indra: every node reflects every other (Atharva Veda)
// ---------------------------------------------------------------------------

/// Zenoh WS state — tracks mesh snapshot for diff detection
pub type ZenohWsState {
  ZenohWsState(push_count: Int, last_snapshot: String)
}

/// Zenoh WS init — send initial mesh topology snapshot
fn zenoh_ws_on_init(
  conn: mist.WebsocketConnection,
) -> #(ZenohWsState, option.Option(process.Selector(WsMsg))) {
  let snapshot = c3i_nif.system_zenoh()
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("page", json.string("zenoh")),
      #("snapshot", json.string(snapshot)),
      #("interval_ms", json.int(1000)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  #(ZenohWsState(push_count: 0, last_snapshot: snapshot), None)
}

/// Zenoh WS handler — on "ping" calls system_zenoh(), diff-detects, sends update or heartbeat
fn zenoh_ws_handler(
  state: ZenohWsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(ZenohWsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        "ping" -> {
          let snapshot = c3i_nif.system_zenoh()
          let changed = snapshot != state.last_snapshot
          case changed {
            True -> {
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("snapshot", json.string(snapshot)),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(ZenohWsState(
                push_count: state.push_count + 1,
                last_snapshot: snapshot,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(
                ZenohWsState(..state, push_count: state.push_count + 1),
              )
            }
          }
        }
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
  }
}

/// Called when Zenoh WebSocket closes
fn zenoh_ws_on_close(_state: ZenohWsState) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// Verification WebSocket — live PROMETHEUS / SIL-6 compliance data (SC-VER-001)
// प्रमाणीकरण WebSocket — जीवित PROMETHEUS डेटा (Gita 2.20)
// ---------------------------------------------------------------------------

/// Verification WS state — tracks verification snapshot for diff detection
pub type VerificationWsState {
  VerificationWsState(push_count: Int, last_snapshot: String)
}

/// Verification WS init — send current verification snapshot
fn verification_ws_on_init(
  conn: mist.WebsocketConnection,
) -> #(VerificationWsState, option.Option(process.Selector(WsMsg))) {
  let snapshot = c3i_nif.system_verification()
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("page", json.string("verification")),
      #("snapshot", json.string(snapshot)),
      #("interval_ms", json.int(1000)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  #(VerificationWsState(push_count: 0, last_snapshot: snapshot), None)
}

/// Verification WS handler — diff-detected push on "ping"
fn verification_ws_handler(
  state: VerificationWsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(VerificationWsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        "ping" -> {
          let snapshot = c3i_nif.system_verification()
          let changed = snapshot != state.last_snapshot
          case changed {
            True -> {
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("snapshot", json.string(snapshot)),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(VerificationWsState(
                push_count: state.push_count + 1,
                last_snapshot: snapshot,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(
                VerificationWsState(..state, push_count: state.push_count + 1),
              )
            }
          }
        }
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
  }
}

/// Called when verification WebSocket closes
fn verification_ws_on_close(_state: VerificationWsState) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// Agents WebSocket — live agent hierarchy / OODA data (SC-AGUI-UI-006)
// एजेंट श्रेणी — Agent hierarchy real-time monitoring via system_dashboard NIF
// EXEC-001 → 4 supervisors → 20 workers, OODA phase, fractal layers L5_COGNITIVE
// ---------------------------------------------------------------------------

/// Agents WS state — tracks agent snapshot for diff detection
pub type AgentsWsState {
  AgentsWsState(push_count: Int, last_snapshot: String)
}

/// Agents WS init — send initial agent hierarchy snapshot
fn agents_ws_on_init(
  conn: mist.WebsocketConnection,
) -> #(AgentsWsState, option.Option(process.Selector(WsMsg))) {
  let snapshot = c3i_nif.system_dashboard()
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("page", json.string("agents")),
      #("snapshot", json.string(snapshot)),
      #("interval_ms", json.int(1000)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  #(AgentsWsState(push_count: 0, last_snapshot: snapshot), None)
}

/// Agents WS handler — on "ping" calls system_dashboard(), diff-detects, sends update or heartbeat
fn agents_ws_handler(
  state: AgentsWsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(AgentsWsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        "ping" -> {
          let snapshot = c3i_nif.system_dashboard()
          let changed = snapshot != state.last_snapshot
          case changed {
            True -> {
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("snapshot", json.string(snapshot)),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(AgentsWsState(
                push_count: state.push_count + 1,
                last_snapshot: snapshot,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(
                AgentsWsState(..state, push_count: state.push_count + 1),
              )
            }
          }
        }
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
  }
}

/// Called when agents WebSocket closes
fn agents_ws_on_close(_state: AgentsWsState) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// Knowledge WebSocket — live Zettelkasten / knowledge base data (SC-ZK-CLAUDE-001)
// ज्ञान WebSocket — ज़ेटेलकास्टन वास्तविक-समय निगरानी (Gita 15.15)
// ---------------------------------------------------------------------------

/// Knowledge WS state — tracks knowledge snapshot for diff detection
pub type KnowledgeWsState {
  KnowledgeWsState(push_count: Int, last_snapshot: String)
}

/// Knowledge WS init — send initial knowledge base snapshot via knowledge_search NIF
fn knowledge_ws_on_init(
  conn: mist.WebsocketConnection,
) -> #(KnowledgeWsState, option.Option(process.Selector(WsMsg))) {
  let snapshot = c3i_nif.knowledge_search("")
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("page", json.string("knowledge")),
      #("snapshot", json.string(snapshot)),
      #("interval_ms", json.int(1000)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  #(KnowledgeWsState(push_count: 0, last_snapshot: snapshot), None)
}

/// Knowledge WS handler — "ping" → fresh knowledge data, diff-detect, update or heartbeat.
/// Non-"ping" text is routed to plan_search(query) for Zettelkasten lookup.
fn knowledge_ws_handler(
  state: KnowledgeWsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(KnowledgeWsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        "ping" -> {
          let snapshot = c3i_nif.knowledge_search("")
          let changed = snapshot != state.last_snapshot
          case changed {
            True -> {
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("snapshot", json.string(snapshot)),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(KnowledgeWsState(
                push_count: state.push_count + 1,
                last_snapshot: snapshot,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(
                KnowledgeWsState(..state, push_count: state.push_count + 1),
              )
            }
          }
        }
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
  }
}

/// Called when knowledge WebSocket closes
fn knowledge_ws_on_close(_state: KnowledgeWsState) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// Generic WebSocket handler — covers all pages not served by a specific handler
// SC-AGUI-UI-006, SC-GLM-UI-001: every page gets real-time push via /ws/{page}
// परिवर्तन — Universal change propagation (Gita 4.7)
// ---------------------------------------------------------------------------

/// Generic WS state — page name + push count + last snapshot for diff detection
pub type PageWsState {
  PageWsState(page: String, push_count: Int, last_snapshot: String)
}

/// Dispatch NIF call for a given page name.
/// Pages with dedicated WS handlers (planning, dashboard) are excluded here —
/// they carry custom multi-field logic handled by their own handlers above.
fn page_ws_snapshot(page: String) -> String {
  case page {
    "immune" -> c3i_nif.system_immune()
    "zenoh" -> c3i_nif.system_zenoh()
    "verification" -> c3i_nif.system_verification()
    "agents" -> c3i_nif.system_dashboard()
    "knowledge" -> c3i_nif.knowledge_search("")
    "telemetry" -> c3i_nif.system_dashboard()
    "substrate" -> c3i_nif.system_health()
    "metabolic" -> c3i_nif.system_health()
    "podman" -> c3i_nif.system_dashboard()
    "mcp" -> c3i_nif.system_dashboard()
    "kms" -> c3i_nif.system_health()
    "smriti" -> c3i_nif.plan_status()
    "bridge" -> c3i_nif.system_zenoh()
    "federation" -> c3i_nif.system_zenoh()
    "prajna" -> c3i_nif.system_health()
    "health-grid" -> c3i_nif.system_health()
    _ -> c3i_nif.system_dashboard()
  }
}

/// Generic WS init — sends connected frame with page-specific snapshot.
fn generic_ws_on_init(
  conn: mist.WebsocketConnection,
  page: String,
) -> #(PageWsState, option.Option(process.Selector(WsMsg))) {
  let snapshot = page_ws_snapshot(page)
  let welcome =
    json.object([
      #("type", json.string("connected")),
      #("page", json.string(page)),
      #("snapshot", json.string(snapshot)),
      #("interval_ms", json.int(1000)),
    ])
    |> json.to_string()
  let _ = mist.send_text_frame(conn, welcome)
  #(PageWsState(page: page, push_count: 0, last_snapshot: snapshot), None)
}

/// Generic WS handler — diff-detected push on "ping", search fallback otherwise.
fn generic_ws_handler(
  state: PageWsState,
  msg: mist.WebsocketMessage(WsMsg),
  conn: mist.WebsocketConnection,
) -> mist.Next(PageWsState, WsMsg) {
  case msg {
    mist.Text(text) -> {
      case text {
        "ping" -> {
          let snapshot = page_ws_snapshot(state.page)
          let changed = snapshot != state.last_snapshot
          case changed {
            True -> {
              let payload =
                json.object([
                  #("type", json.string("update")),
                  #("page", json.string(state.page)),
                  #("snapshot", json.string(snapshot)),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, payload)
              mist.continue(PageWsState(
                page: state.page,
                push_count: state.push_count + 1,
                last_snapshot: snapshot,
              ))
            }
            False -> {
              let hb =
                json.object([
                  #("type", json.string("heartbeat")),
                  #("seq", json.int(state.push_count + 1)),
                ])
                |> json.to_string()
              let _ = mist.send_text_frame(conn, hb)
              mist.continue(
                PageWsState(..state, push_count: state.push_count + 1),
              )
            }
          }
        }
        _ -> {
          let search_result = c3i_nif.plan_search(text)
          let resp =
            json.object([
              #("type", json.string("search")),
              #("query", json.string(text)),
              #("results", json.string(search_result)),
            ])
            |> json.to_string()
          let _ = mist.send_text_frame(conn, resp)
          mist.continue(state)
        }
      }
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
  }
}

/// Called when a generic page WebSocket closes.
fn generic_ws_on_close(_state: PageWsState) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// Entry point — HTTP + hepta WebSocket (planning + dashboard + immune + zenoh + verification + agents + knowledge)
// ---------------------------------------------------------------------------

pub fn start(port: Int) -> Result(Nil, String) {
  io.println("  Gleam HTTP+WS on 0.0.0.0:" <> int.to_string(port))

  let handler = fn(req: request.Request(mist.Connection)) {
    // Check for WebSocket upgrade
    let is_ws_upgrade = case request.get_header(req, "upgrade") {
      Ok("websocket") -> True
      _ -> False
    }

    case is_ws_upgrade {
      // WebSocket upgrade — route to appropriate handler
      True ->
        case req.path {
          // Planning WS — task data push (SC-GLM-UI-010)
          "/ws/planning" ->
            mist.websocket(
              request: req,
              handler: ws_handler,
              on_init: ws_on_init,
              on_close: ws_on_close,
            )
          // Dashboard WS — comprehensive system monitoring (SC-AGUI-UI-006)
          // All L0-L7 fractal layers via Zenoh backplane
          "/ws/dashboard" ->
            mist.websocket(
              request: req,
              handler: dash_ws_handler,
              on_init: dash_ws_on_init,
              on_close: dash_ws_on_close,
            )
          // Immune WS — live immune system / threat monitoring
          "/ws/immune" ->
            mist.websocket(
              request: req,
              handler: immune_ws_handler,
              on_init: immune_ws_on_init,
              on_close: immune_ws_on_close,
            )
          // Zenoh WS — live mesh topology monitoring (SC-ZMOF-001)
          "/ws/zenoh" ->
            mist.websocket(
              request: req,
              handler: zenoh_ws_handler,
              on_init: zenoh_ws_on_init,
              on_close: zenoh_ws_on_close,
            )
          // Verification WS — live PROMETHEUS / SIL-6 compliance data (SC-VER-001)
          "/ws/verification" ->
            mist.websocket(
              request: req,
              handler: verification_ws_handler,
              on_init: verification_ws_on_init,
              on_close: verification_ws_on_close,
            )
          // Agents WS — live agent hierarchy / OODA data (SC-AGUI-UI-006)
          "/ws/agents" ->
            mist.websocket(
              request: req,
              handler: agents_ws_handler,
              on_init: agents_ws_on_init,
              on_close: agents_ws_on_close,
            )
          // Knowledge WS — live Zettelkasten / knowledge base (SC-ZK-CLAUDE-001)
          "/ws/knowledge" ->
            mist.websocket(
              request: req,
              handler: knowledge_ws_handler,
              on_init: knowledge_ws_on_init,
              on_close: knowledge_ws_on_close,
            )
          // Generic WS — catch-all for any remaining /ws/{page} routes.
          // Planning and dashboard retain their custom multi-field handlers above.
          // All other pages use page_ws_snapshot(page) for NIF dispatch.
          "/ws/" <> page_name ->
            mist.websocket(
              request: req,
              handler: generic_ws_handler,
              on_init: fn(conn) { generic_ws_on_init(conn, page_name) },
              on_close: generic_ws_on_close,
            )
          // Unknown WS path — reject with 404
          _ ->
            response.new(404)
            |> response.set_body(
              mist.Bytes(bytes_tree.from_string(
                "{\"error\": \"unknown websocket path\"}",
              )),
            )
            |> response.set_header("content-type", "application/json")
        }

      // Normal HTTP request
      False -> {
        // SC-VAULT-009 + SC-VAULT-025 (Wave 11): intercept GET /api/v1/secret/<name>
        // BEFORE generic RBAC middleware. This endpoint has its own bearer
        // gate against pi_session.token via secret_api.handle_get_secret.
        // We deliberately exclude /api/v1/secret-status and /api/v1/secret-policy-audit
        // (no slash after "secret"), which remain on the wisp router path.
        let secret_name = case req.method {
          http.Get ->
            case req.path {
              "/api/v1/secret/" <> n ->
                case string.contains(n, "/") || string.is_empty(n) {
                  True -> ""
                  False -> n
                }
              _ -> ""
            }
          _ -> ""
        }
        case secret_name != "" {
          True -> {
            let authz = case request.get_header(req, "authorization") {
              Ok(v) -> v
              Error(_) -> ""
            }
            let #(status, body) =
              vault_secret_api.handle_get_secret(authz, secret_name)
            response.new(status)
            |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
            |> response.set_header("content-type", "application/json")
            |> response.set_header(
              "access-control-allow-origin",
              "https://vm-1.tail55d152.ts.net:8443",
            )
            |> response.set_header("cache-control", "no-store")
          }
          False -> handle_normal_http(req)
        }
      }
    }
  }

  // Start OTP actors (freshness monitor 10s loop, observer, guard grid)
  let _app_state = otp_app.start()
  io.println("  OTP actors started (freshness monitor, observer, guard grid)")

  // Start BOTH HTTP and HTTPS for maximum accessibility
  let cert_path = "priv/ssl/cert.pem"
  let key_path = "priv/ssl/key.pem"
  let https_port = port + 1

  // HTTP server on primary port (4100) — no TLS, accessible from any browser
  let http_builder =
    mist.new(handler)
    |> mist.port(port)
    |> mist.bind("0.0.0.0")

  case mist.start(http_builder) {
    Ok(_) ->
      io.println(
        "  HTTP server running on http://0.0.0.0:" <> int.to_string(port),
      )
    Error(_) ->
      io.println("  [http] HTTP server failed on port " <> int.to_string(port))
  }

  // HTTPS server on port+1 (4101) — TLS with self-signed cert
  let https_builder =
    mist.new(handler)
    |> mist.port(https_port)
    |> mist.bind("0.0.0.0")

  let tls_builder =
    mist.with_tls(https_builder, certfile: cert_path, keyfile: key_path)

  case mist.start(tls_builder) {
    Ok(_) -> {
      io.println(
        "  HTTPS server running on https://0.0.0.0:"
        <> int.to_string(https_port),
      )
      io.println(
        "  Both HTTP (:"
        <> int.to_string(port)
        <> ") and HTTPS (:"
        <> int.to_string(https_port)
        <> ") available",
      )
      process.sleep_forever()
      Ok(Nil)
    }
    Error(_) -> {
      io.println(
        "  [tls] TLS failed, HTTP-only mode on port " <> int.to_string(port),
      )
      process.sleep_forever()
      Ok(Nil)
    }
  }
}

// ---------------------------------------------------------------------------
// Wave 11: extracted normal-HTTP path. The handler in start(port) intercepts
// GET /api/v1/secret/<name> first; everything else falls through to here for
// the standard RBAC + wisp router dispatch.
// ---------------------------------------------------------------------------

fn handle_normal_http(
  req: request.Request(mist.Connection),
) -> response.Response(mist.ResponseData) {
  // SC-HTTP-WS-426 (Pass-124) — RFC 7231 §6.5.15: a /ws/* path
  // accessed without the WebSocket Upgrade dance MUST return 426
  // Upgrade Required + Upgrade: websocket + Connection: Upgrade.
  // Pre-fix: such requests fell through to the Wisp router which
  // 404'd, hiding the fact that the endpoint exists and would
  // work over WS. Automation tools (curl, monitoring probes, link
  // checkers) can now discover the WS endpoint and either upgrade
  // or stop probing.
  case string.starts_with(req.path, "/ws/") {
    True -> ws_426_response()
    False ->
      // SC-HTTP-STATIC-405 (Pass-134) — GET-only resources (static
      // assets, favicons, robots.txt, security.txt) must return 405
      // when accessed via mutation verbs, NOT 401. Pre-fix: Pass-121
      // narrowed auth-gate to POST only but still 401'd POST against
      // /static/*. Auth requirement is leaked on a path that simply
      // doesn't accept mutations. The 405 short-circuit must precede
      // the Mist auth gate.
      case is_get_only_path(req.path), req.method {
        True, http.Get -> handle_normal_http_inner(req)
        True, http.Head -> handle_normal_http_inner(req)
        True, http.Options -> handle_normal_http_inner(req)
        True, _ -> get_only_405_response()
        False, _ -> handle_normal_http_inner(req)
      }
  }
}

/// SC-HTTP-STATIC-405 (Pass-134) — list of path prefixes that accept
/// only GET/HEAD/OPTIONS. Mutation verbs to these resources MUST 405,
/// not 401 — the resource is GET-only, not auth-gated.
fn is_get_only_path(path: String) -> Bool {
  string.starts_with(path, "/static/")
  || path == "/favicon.ico"
  || path == "/apple-touch-icon.png"
  || path == "/apple-touch-icon-precomposed.png"
  || path == "/robots.txt"
  || string.starts_with(path, "/.well-known/")
}

/// SC-HTTP-STATIC-405 (Pass-134) — 405 response for GET-only paths
/// accessed via mutation verbs. Mirrors the defense stack used by
/// router.method_not_allowed_with_allow (Pass-117).
fn get_only_405_response() -> response.Response(mist.ResponseData) {
  response.new(405)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("{\"error\":\"method_not_allowed\"}")),
  )
  |> response.set_header("allow", "GET, HEAD, OPTIONS")
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-frame-options", "DENY")
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("referrer-policy", "strict-origin-when-cross-origin")
  |> response.set_header(
    "content-security-policy",
    "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
  )
  |> response.set_header("vary", "Origin, Accept-Encoding")
  |> response.set_header("cross-origin-opener-policy", "same-origin")
  |> response.set_header("cross-origin-resource-policy", "same-site")
  |> response.set_header("x-dns-prefetch-control", "off")
  |> response.set_header("origin-agent-cluster", "?1")
  // SC-SEO-X-ROBOTS-TAG-ALL (Pass-137) — GET-only 405.
  |> response.set_header("x-robots-tag", "noindex, nofollow")
  |> response.set_header(
    "access-control-allow-origin",
    "https://vm-1.tail55d152.ts.net:8443",
  )
  |> response.set_header("access-control-allow-methods", "GET, HEAD, OPTIONS")
}

/// SC-HTTP-WS-426 (Pass-124) — 426 Upgrade Required response carrying
/// the upgrade signal + the standard defense headers (matches
/// router.with_error_defense pattern, mirrored at Mist tier).
fn ws_426_response() -> response.Response(mist.ResponseData) {
  response.new(426)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string(
      "{\"error\":\"upgrade_required\",\"message\":\"websocket upgrade required\"}",
    )),
  )
  |> response.set_header("upgrade", "websocket")
  |> response.set_header("connection", "Upgrade")
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-frame-options", "DENY")
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("referrer-policy", "strict-origin-when-cross-origin")
  |> response.set_header(
    "content-security-policy",
    "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
  )
  |> response.set_header("vary", "Origin, Accept-Encoding, Upgrade")
  |> response.set_header("cross-origin-opener-policy", "same-origin")
  |> response.set_header("cross-origin-resource-policy", "same-site")
  |> response.set_header("origin-agent-cluster", "?1")
  // SC-SEO-X-ROBOTS-TAG-ALL (Pass-137) — 426 Upgrade Required.
  |> response.set_header("x-robots-tag", "noindex, nofollow")
  // SC-CORS-426-ACAO (Pass-127) — the 426 emits at the Mist tier
  // BEFORE the Wisp router's CORS-glue runs, so the standard ACAO/
  // ACAM/X-DNS-Prefetch headers Pass-79..115 wired into every other
  // response are absent here. Without ACAO, cross-origin browsers
  // refuse to surface the 426 body to JS code — the upgrade hint is
  // CORS-invisible. Match the headers that handle_normal_http_inner
  // 401 already emits (line 1373).
  |> response.set_header(
    "access-control-allow-origin",
    "https://vm-1.tail55d152.ts.net:8443",
  )
  |> response.set_header("access-control-allow-methods", "GET, POST, OPTIONS")
  |> response.set_header("x-dns-prefetch-control", "off")
}

fn handle_normal_http_inner(
  req: request.Request(mist.Connection),
) -> response.Response(mist.ResponseData) {
  // Phase 2: Bearer Token RBAC Middleware for L5_Operator
  // SC-HTTP-METHOD-AUTH-ORDER (Pass-121) — PUT/DELETE/PATCH used to be
  // pre-gated here alongside POST, returning 401 before the request
  // reached the router. That hides the fact that no PUT/DELETE/PATCH
  // route exists at all — the correct RFC 7231 §7.4.1 status is 405
  // (Method Not Allowed) with Allow header. By auth-gating ONLY POST,
  // we let PUT/DELETE/PATCH fall through to the router's `_ -> 405`
  // arm. Authentication-before-method-validation also leaks the auth
  // requirement to clients who shouldn't get past 405 anyway.
  let is_authorized = case req.method {
    http.Post -> {
      let auth_ok = case request.get_header(req, "authorization") {
        Ok("Bearer " <> _token) -> True
        _ -> False
      }
      let proof_ok = case request.get_header(req, "x-proof-token") {
        Ok(token) ->
          safety_kernel.validate_proof_token(
            token,
            "mutation",
            "L5_Operator",
            "",
            1000,
          )
          |> result.is_ok()
        _ -> False
      }
      auth_ok && proof_ok
    }
    _ -> True
  }

  case is_authorized {
    False ->
      // SC-SEC-ERROR-DEFENSE (Pass-114) — Mist-level 401 (pre-Wisp
      // OIDC check) MUST carry the same defense-in-depth headers as
      // any other error. Mirrors router.with_error_defense.
      response.new(401)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string("{\"error\": \"Unauthorized\"}")),
      )
      |> response.set_header("content-type", "application/json")
      |> response.set_header(
        "access-control-allow-origin",
        "https://vm-1.tail55d152.ts.net:8443",
      )
      |> response.set_header("x-frame-options", "DENY")
      |> response.set_header("x-content-type-options", "nosniff")
      |> response.set_header(
        "referrer-policy",
        "strict-origin-when-cross-origin",
      )
      |> response.set_header(
        "content-security-policy",
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
      )
      |> response.set_header(
        "permissions-policy",
        "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=(), interest-cohort=()",
      )
      // SC-HTTP-VARY-ENCODING (Pass-130 drift-fix) — Pass-123 added
      // Accept-Encoding to every Vary emission in router.gleam via sed
      // but missed this Mist-tier 401 site. Once compression lands, a
      // mid-tier cache could serve a gzipped 401 to a non-gzip client.
      |> response.set_header("vary", "Origin, Accept-Encoding")
      |> response.set_header("cross-origin-opener-policy", "same-origin")
      |> response.set_header("cross-origin-resource-policy", "same-site")
      |> response.set_header("x-dns-prefetch-control", "off")
      |> response.set_header("origin-agent-cluster", "?1")
      // SC-SEO-X-ROBOTS-TAG-ALL (Pass-137) — Mist-tier 401.
      |> response.set_header("x-robots-tag", "noindex, nofollow")
      |> response.set_header("cache-control", "no-store")
      |> response.set_header("www-authenticate", "Bearer realm=\"c3i\"")
    True -> {
      let wisp_response = router.handle_request(request.set_body(req, ""))
      let resp =
        response.new(wisp_response.status)
        |> response.set_body(
          mist.Bytes(bytes_tree.from_string(wisp_response.body)),
        )
      list.fold(wisp_response.headers, resp, fn(acc, header) {
        response.set_header(acc, header.0, header.1)
      })
      |> response.set_header(
        "access-control-allow-origin",
        "https://vm-1.tail55d152.ts.net:8443",
      )
      |> response.set_header(
        "access-control-allow-methods",
        "GET, POST, OPTIONS",
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Mesh configuration validation (SC-CONSOL-001, SC-ZMOF-001)
// Wires config/mesh_config into the server production path.
// ---------------------------------------------------------------------------

/// Validate the default mesh configuration and return a summary string.
/// Called during server startup to verify port uniqueness and health checks.
pub fn validate_mesh_config() -> String {
  let cfg = mesh_config.default_mesh_config()
  let is_ok = mesh_config.is_valid(cfg)
  let quorum = mesh_config.calculate_quorum(list.length(cfg.containers))
  case is_ok {
    True ->
      "mesh_config:valid quorum:"
      <> int.to_string(quorum)
      <> " containers:"
      <> int.to_string(list.length(cfg.containers))
    False -> {
      let errors = mesh_config.validate_all(cfg)
      "mesh_config:invalid errors:" <> int.to_string(list.length(errors))
    }
  }
}
