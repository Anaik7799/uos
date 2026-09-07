//// Intelligent F´ managing agent for the system: an `Active` component (`UosManager`) that runs
//// a fast OODA loop over the board, leases, heartbeats, Zenoh infra and the system audit.
//// Observe -> Orient (Lyapunov trend via `ooda`) -> Decide (mode + actions) -> Act, where every
//// act is a tracked board message posted with L1 authority through `coord` (never a raw side
//// effect: Rocha cut). `step` is pure and tested; `start` wraps it in an OTP actor.
//// Health with no PASS/FAIL evidence is `Unknown`, never silently treated as green (see
//// `health_status`); Zenoh reconcile/share-state/authorization failures hit in `live_cycle` are
//// recorded on `Manager.faults` and fail closed — posting stops at the first authorization
//// refusal, and a failed reconcile drives an Andon on the following cycle.
//// STAMP: SC-TUI-MANAGER-001, SC-FPP-INTENT-001.

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/string
import uos_tui/board.{
  type Board, type Message, Agent, Causality, Draft, Semantics,
}
import uos_tui/coord.{type Coord}
import uos_tui/fprime
import uos_tui/ooda
import uos_tui/system_audit.{type Subject as AuditSubject}

pub const agent = Agent("uos-manager", "L1", "fprime-active")

/// The manager's own F´ dictionary (ground segment, base 0x2040, next 64-id window after the TUI).
pub fn component() -> fprime.Component {
  fprime.Component(
    comp_name: "UosManager",
    kind: fprime.Active,
    ports: [
      fprime.General(
        "board_in",
        "Uos.Board",
        fprime.AsyncInput(None, fprime.Drop),
        1,
      ),
      fprime.General(
        "audit_in",
        "Uos.Audit",
        fprime.AsyncInput(None, fprime.Drop),
        1,
      ),
      fprime.General(
        "heartbeat_in",
        "Uos.Heartbeat",
        fprime.AsyncInput(None, fprime.Drop),
        1,
      ),
      fprime.General("board_out", "Uos.Board", fprime.Output, 1),
      fprime.General("intent_out", "Uos.Intent", fprime.Output, 1),
      fprime.Special(fprime.CommandRecv),
      fprime.Special(fprime.CommandReg),
      fprime.Special(fprime.CommandResp),
      fprime.Special(fprime.EventPort),
      fprime.Special(fprime.TelemetryPort),
      fprime.Special(fprime.TimeGet),
    ],
    commands: [
      fprime.Command("MGR_AUDIT", 0x01, fprime.AsyncCmd(None, fprime.Drop), []),
      fprime.Command(
        "MGR_RECONCILE",
        0x02,
        fprime.AsyncCmd(None, fprime.Drop),
        [],
      ),
      fprime.Command(
        "MGR_SHARE_STATE",
        0x03,
        fprime.AsyncCmd(None, fprime.Drop),
        [],
      ),
      fprime.Command("MGR_EXPIRE_LEASES", 0x04, fprime.GuardedCmd, []),
      fprime.Command("MGR_SET_MODE", 0x05, fprime.AsyncCmd(None, fprime.Drop), [
        #("mode", fprime.U8),
      ]),
    ],
    events: [
      fprime.Event(
        "MgrCycle",
        0x01,
        fprime.ActivityLo,
        "cycle %d mode %s",
        Some(20),
      ),
      fprime.Event("MgrAndon", 0x02, fprime.WarningHi, "andon %s: %s", None),
      fprime.Event(
        "MgrJidoka",
        0x03,
        fprime.WarningHi,
        "line stopped: %s",
        None,
      ),
      fprime.Event(
        "MgrStaleAgent",
        0x04,
        fprime.WarningLo,
        "stale agent %s",
        Some(5),
      ),
      fprime.Event(
        "MgrIntentEmitted",
        0x05,
        fprime.CommandSev,
        "intent %s -> %s",
        None,
      ),
    ],
    channels: [
      fprime.Channel("Cycles", 0x01, fprime.U64, fprime.Always),
      fprime.Channel("AuditPass", 0x02, fprime.U16, fprime.OnChange),
      fprime.Channel("AuditFail", 0x03, fprime.U16, fprime.OnChange),
      fprime.Channel("BoardCount", 0x04, fprime.U32, fprime.OnChange),
      fprime.Channel("StaleAgents", 0x05, fprime.U8, fprime.OnChange),
      fprime.Channel("LiveLeases", 0x06, fprime.U8, fprime.OnChange),
      fprime.Channel("Mode", 0x07, fprime.U8, fprime.OnChange),
    ],
    parameters: [
      fprime.Parameter("TickMs", 0x01, fprime.U16, Some("250"), 0x10, 0x11),
      fprime.Parameter(
        "HeartbeatTtlMs",
        0x02,
        fprime.U32,
        Some("120000"),
        0x12,
        0x13,
      ),
    ],
  )
}

pub fn instance() -> fprime.Instance {
  fprime.Instance("uosManager", "UosManager", 0x2040, Some(64))
}

pub type Observation {
  Observation(
    now_us: Int,
    board_count: Int,
    stale_agents: List(String),
    live_leases: Int,
    audit_pass: Int,
    audit_fail: Int,
    audit_declared: Int,
    zenoh_ok: Bool,
    last_frame_us: Int,
  )
}

pub type Act {
  PostAndon(String)
  PostJidoka(String)
  PostProgress(String)
  ExpireLeases
  RequestAudit
  RequestReconcile
  RequestShareState
}

pub type Manager {
  Manager(
    loop: ooda.Loop,
    cycles: Int,
    last_mode: ooda.Mode,
    history: List(#(Int, ooda.Mode, List(Act))),
    last_observation: option.Option(Observation),
    faults: List(String),
  )
}

pub fn new() -> Manager {
  Manager(ooda.new(16, 100_000), 0, ooda.Dark, [], None, [])
}

/// Health computed from audit evidence. `Unknown` means no PASS/FAIL evidence has been seen
/// yet — only `Declared` verdicts, or none at all — and must never be treated as green.
pub type Health {
  Known(Float)
  Unknown
}

/// Health from the audit: `Known(pass / (pass + fail))` when there is PASS/FAIL evidence,
/// `Unknown` when only declared (untested) verdicts exist. Declared verdicts are evidence-free
/// and are never silently counted as healthy.
pub fn health_status(o: Observation) -> Health {
  case o.audit_pass + o.audit_fail {
    0 -> Unknown
    n -> Known(int.to_float(o.audit_pass) /. int.to_float(n))
  }
}

/// Health in 0..1 from the audit (pass / (pass+fail)); declared verdicts are neutral. Fail
/// closed: `Unknown` health (no PASS/FAIL evidence) reads as `0.0`, never as healthy. Use
/// `health_status` when "no evidence yet" must be distinguished from "genuinely 0%".
pub fn health(o: Observation) -> Float {
  case health_status(o) {
    Known(h) -> h
    Unknown -> 0.0
  }
}

/// True when `o` carries the same pass/fail/declared/board/stale/lease counts as the previous
/// cycle's observation — the signal a repeated `PostProgress` would just restate.
fn repeats(prev: option.Option(Observation), o: Observation) -> Bool {
  case prev {
    None -> False
    Some(p) ->
      p.audit_pass == o.audit_pass
      && p.audit_fail == o.audit_fail
      && p.audit_declared == o.audit_declared
      && p.board_count == o.board_count
      && p.stale_agents == o.stale_agents
      && p.live_leases == o.live_leases
  }
}

/// Pure OODA step: observe -> orient -> decide, producing the acts for this cycle. Health
/// `Unknown` (no PASS/FAIL evidence yet) is itself a Jidoka/andon condition: the manager never
/// proceeds as though everything is green just because nothing has failed yet. A `PostProgress`
/// is suppressed when the observation is materially unchanged from the previous cycle, to avoid
/// unnecessary board traffic at the fast tick.
pub fn step(m: Manager, o: Observation) -> #(Manager, ooda.Mode, List(Act)) {
  let obs =
    ooda.Observation(
      o.now_us / 1000,
      o.last_frame_us,
      o.board_count,
      o.audit_fail,
      health(o),
    )
  let #(loop, mode, actions, within) = ooda.step(m.loop, obs)
  let unchanged = repeats(m.last_observation, o)
  let acts =
    list.flatten([
      list.flat_map(actions, fn(a) {
        case a {
          ooda.HaltAdmission -> [
            PostJidoka(
              "audit failures " <> int.to_string(o.audit_fail) <> " > 3",
            ),
          ]
          ooda.RaiseAndon -> [
            PostAndon(
              "mode "
              <> ooda.mode_label(mode)
              <> case within {
                True -> ""
                False -> " (frame over budget)"
              },
            ),
          ]
          ooda.AuditAspects -> [RequestAudit]
          ooda.Repaint | ooda.NoAction -> []
        }
      }),
      case o.stale_agents {
        [] -> []
        s -> [PostAndon("stale agents: " <> string.join(s, ","))]
      },
      case o.live_leases > 0 && m.cycles % 8 == 7 {
        True -> [ExpireLeases]
        False -> []
      },
      case o.zenoh_ok {
        True ->
          case m.cycles % 16 == 15 {
            True -> [RequestReconcile, RequestShareState]
            False -> []
          }
        False -> [PostAndon("zenoh unavailable")]
      },
      case health_status(o) {
        Unknown -> [
          PostAndon(
            "health unknown: no PASS/FAIL evidence, "
            <> int.to_string(o.audit_declared)
            <> " declared",
          ),
        ]
        Known(_) -> []
      },
      case unchanged {
        True -> []
        False -> [
          PostProgress(
            "cycle "
            <> int.to_string(m.cycles + 1)
            <> " mode "
            <> ooda.mode_label(mode)
            <> " health "
            <> health_pct(o),
          ),
        ]
      },
    ])
  #(
    Manager(
      loop,
      m.cycles + 1,
      mode,
      list.take([#(m.cycles + 1, mode, acts), ..m.history], 64),
      Some(o),
      m.faults,
    ),
    mode,
    acts,
  )
}

fn health_pct(o: Observation) -> String {
  int.to_string(float_to_pct(health(o))) <> "%"
}

fn float_to_pct(f: Float) -> Int {
  float_round(f *. 100.0)
}

@external(erlang, "erlang", "round")
fn float_round(f: Float) -> Int

/// Draft a tracked message for an act (semantics reference real control actions and aspects).
pub fn draft_for(act: Act, cycle: Int) -> option.Option(board.Draft) {
  let base = fn(kind, payload, cas, asp) {
    Some(Draft(
      agent,
      "broadcast",
      kind,
      [#("cycle", int.to_string(cycle)), ..payload],
      Semantics(["Worker", "17 Aspect audit"], asp, cas, [], 1),
      Causality(None, []),
      None,
      None,
    ))
  }
  case act {
    PostAndon(reason) ->
      base(board.Andon, [#("reason", reason)], ["CA-audit_screen"], [1, 13])
    PostJidoka(reason) ->
      base(board.Jidoka, [#("reason", reason)], ["CA-integrate_slice"], [15, 17])
    PostProgress(text) ->
      base(board.Progress, [#("text", text)], ["CA-paint_frame"], [4, 13])
    ExpireLeases ->
      base(board.LeaseRelease, [#("action", "expire")], ["CA-integrate_slice"], [
        17,
      ])
    RequestAudit ->
      base(board.Progress, [#("action", "audit")], ["CA-audit_screen"], [15])
    RequestReconcile ->
      base(board.Progress, [#("action", "reconcile")], ["CA-integrate_slice"], [
        10,
      ])
    RequestShareState ->
      base(board.Progress, [#("action", "share-state")], ["CA-paint_frame"], [
        16,
      ])
  }
}

/// Telemetry channel values for one cycle (F´ channel names from `component()`).
pub fn channels(m: Manager, o: Observation) -> List(#(String, String)) {
  [
    #("Cycles", int.to_string(m.cycles)),
    #("AuditPass", int.to_string(o.audit_pass)),
    #("AuditFail", int.to_string(o.audit_fail)),
    #("BoardCount", int.to_string(o.board_count)),
    #("StaleAgents", int.to_string(list.length(o.stale_agents))),
    #("LiveLeases", int.to_string(o.live_leases)),
    #("Mode", ooda.mode_label(m.last_mode)),
  ]
}

pub fn to_json(m: Manager, o: Observation) -> Json {
  json.object([
    #("component", json.string("UosManager")),
    #("instance", json.string("uosManager")),
    #(
      "channels",
      json.object(list.map(channels(m, o), fn(c) { #(c.0, json.string(c.1)) })),
    ),
    #(
      "history",
      json.array(list.take(m.history, 8), fn(h) {
        json.object([
          #("cycle", json.int(h.0)),
          #("mode", json.string(ooda.mode_label(h.1))),
          #("acts", json.int(list.length(h.2))),
        ])
      }),
    ),
  ])
}

// ---------------------------------------------------------------------------
// Live actor: observes the real board/coord/infra and acts through coord.post
// ---------------------------------------------------------------------------

pub type Msg {
  Cycle
  Snapshot(Subject(#(Manager, Coord, List(Message))))
  Stop
}

type State {
  State(
    manager: Manager,
    board: Board,
    coord: Coord,
    zenoh_base: option.Option(String),
    audit: fn() -> List(AuditSubject),
    tick_ms: Int,
    self: Subject(Msg),
  )
}

/// True only when the Zenoh REST plugin answers with live, well-formed evidence that it is
/// actually the REST plugin (its admin-space entry mentions `"rest"`): any connection/HTTP
/// error, or a body that doesn't, is treated as unhealthy. Fail-closed — a refused connection,
/// or no base configured at all, is never silently promoted to "healthy".
pub fn zenoh_healthy(zenoh_base: option.Option(String)) -> Bool {
  case zenoh_base {
    Some(base) ->
      case board.http_get(base <> "/@/*/router/plugins/rest") {
        Ok(body) -> body != "" && string.contains(body, "\"rest\"")
        Error(_) -> False
      }
    None -> False
  }
}

/// Publish the manager's available state on Zenoh (`coord.share_state`) when a base is
/// configured; otherwise record why sharing was skipped instead of silently succeeding.
pub fn share(
  zenoh_base: option.Option(String),
  entries: List(#(String, Json)),
) -> #(Int, List(String)) {
  case zenoh_base {
    Some(base) -> coord.share_state(base, entries)
    None -> #(0, ["share-state skipped: no zenoh base"])
  }
}

/// Perform the side effect (if any) for one already-authorized act. Returns any new faults the
/// effect hit; never posts a board message itself (that is `coord.post`'s job in `run_acts`).
fn perform(
  act: Act,
  b: Board,
  c: Coord,
  zenoh_base: option.Option(String),
  m: Manager,
  o: Observation,
) -> #(Board, Coord, List(String)) {
  case act {
    ExpireLeases -> {
      let #(c, _) = coord.expire(c, o.now_us)
      #(b, c, [])
    }
    RequestReconcile ->
      case coord.reconcile(b, c) {
        Ok(#(b, c, r)) -> #(b, c, case r.conflicts {
          0 -> []
          n -> ["reconcile conflicts: " <> int.to_string(n)]
        })
        Error(reason) -> #(b, c, ["reconcile: " <> reason])
      }
    RequestShareState -> {
      let #(_shared, fails) = share(zenoh_base, [#("manager", to_json(m, o))])
      #(b, c, fails)
    }
    PostAndon(_) | PostJidoka(_) | PostProgress(_) | RequestAudit -> #(b, c, [])
  }
}

/// Post each act in order, stopping fail-closed at the first authorization failure so nothing
/// further is attempted once `coord.post` refuses a draft. An act's own side effect (lease
/// expiry, reconcile, share-state) only runs once its draft has been authorized and posted.
fn run_acts(
  acts: List(Act),
  cycle: Int,
  b: Board,
  c: Coord,
  zenoh_base: option.Option(String),
  m: Manager,
  o: Observation,
) -> #(Board, Coord, List(String)) {
  list.fold_until(acts, #(b, c, []), fn(acc, act) {
    let #(b, c, faults) = acc
    case draft_for(act, cycle) {
      None -> list.Continue(#(b, c, faults))
      Some(d) -> {
        let #(b, c, posted) = coord.post(b, c, d)
        case posted {
          Ok(_) -> {
            let #(b, c, new_faults) = perform(act, b, c, zenoh_base, m, o)
            list.Continue(#(b, c, list.append(faults, new_faults)))
          }
          Error(v) ->
            list.Stop(#(
              b,
              c,
              list.append(faults, [
                "post refused: " <> coord.violation_label(v),
              ]),
            ))
        }
      }
    }
  })
}

/// Run one live cycle against real state; returns the updated pieces and the acts taken this
/// cycle (including any Andon carried forward from a fault recorded last cycle). Stops posting
/// further acts fail-closed on the first `coord.post` authorization refusal (recorded in
/// `faults`); a failed `coord.reconcile` is likewise recorded in `faults` and surfaces as an
/// Andon on the *next* cycle (Zenoh health is unknown until reconcile next succeeds).
pub fn live_cycle(
  m: Manager,
  b: Board,
  c: Coord,
  zenoh_base: option.Option(String),
  audit: fn() -> List(AuditSubject),
) -> #(Manager, Board, Coord, List(Act)) {
  let now = board.system_time_us()
  let subjects = audit()
  let #(p, dcl, f) = system_audit.totals(subjects)
  let zenoh_ok = zenoh_healthy(zenoh_base)
  let o =
    Observation(
      now,
      b.count,
      coord.stale(c, now, 120_000_000),
      list.length(coord.live_leases(c, now)),
      p,
      f,
      dcl,
      zenoh_ok,
      0,
    )
  let #(m1, _, own_acts) = step(m, o)
  let carried =
    m.faults
    |> list.filter(fn(fault) { string.starts_with(fault, "reconcile: ") })
    |> list.map(fn(fault) { PostAndon("zenoh health unknown: " <> fault) })
  let acts = list.append(carried, own_acts)
  let #(b, c, cycle_faults) = run_acts(acts, m1.cycles, b, c, zenoh_base, m1, o)
  let m2 = Manager(..m1, last_observation: Some(o), faults: cycle_faults)
  #(m2, b, c, acts)
}

/// Start the manager actor, returning its subject (kept for compatibility with earlier
/// callers). Prefer `start_actor` when the caller needs the actor's own pid, e.g. to supervise
/// or monitor it.
pub fn start(
  b: Board,
  c: Coord,
  zenoh_base: option.Option(String),
  audit: fn() -> List(AuditSubject),
  tick_ms: Int,
) -> Result(Subject(Msg), actor.StartError) {
  start_actor(b, c, zenoh_base, audit, tick_ms)
  |> result.map(fn(started) { started.data })
}

/// Start the manager actor, returning both its pid and subject. The actor owns its own `Cycle`
/// timer (`process.send_after`), rearmed after every cycle it handles, so there is no detached
/// ticker process left running independently of the actor: killing the actor's pid stops the
/// cycle loop for good.
pub fn start_actor(
  b: Board,
  c: Coord,
  zenoh_base: option.Option(String),
  audit: fn() -> List(AuditSubject),
  tick_ms: Int,
) -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    process.send_after(self, int.max(tick_ms, 50), Cycle)
    State(new(), b, c, zenoh_base, audit, tick_ms, self)
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn child_spec(
  b: Board,
  c: Coord,
  zenoh_base: option.Option(String),
  audit: fn() -> List(AuditSubject),
  tick_ms: Int,
) -> ChildSpecification(Subject(Msg)) {
  supervision.worker(fn() { start_actor(b, c, zenoh_base, audit, tick_ms) })
}

fn handle(s: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Cycle -> {
      let #(m, b, c, _) =
        live_cycle(s.manager, s.board, s.coord, s.zenoh_base, s.audit)
      process.send_after(s.self, int.max(s.tick_ms, 50), Cycle)
      actor.continue(State(..s, manager: m, board: b, coord: c))
    }
    Snapshot(reply) -> {
      process.send(reply, #(s.manager, s.coord, board.timeline(s.board)))
      actor.continue(s)
    }
    Stop -> actor.stop()
  }
}
