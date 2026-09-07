//// Fast OODA (Observe-Orient-Decide-Act) loop controller for the uos_tui
//// driver. Bounds each cycle to a fixed microsecond budget and tracks a
//// Lyapunov-style windowed health trend to pick a display mode and the
//// actions the driver should take this cycle.
////
//// Reference: Textual `App` render/refresh scheduling loop; Lyapunov
//// windowed trend detectors (`ha/lyapunov_proof.gleam`).
//// STAMP id: SC-TUI-W08-001

import gleam/int
import gleam/list

/// One sampled observation of the driver's runtime state.
pub type Observation {
  Observation(
    ts_ms: Int,
    frame_us: Int,
    events: Int,
    aspects_failed: Int,
    health: Float,
  )
}

/// Direction of the windowed health trend.
pub type Trend {
  Rising
  Falling
  Stable
}

/// Display mode selected by the loop's decide phase.
pub type Mode {
  Dark
  Dim
  Normal
  Bright
  Emergency
}

/// Actions the driver should perform this cycle.
pub type Action {
  Repaint
  AuditAspects
  RaiseAndon
  HaltAdmission
  NoAction
}

/// Controller state: bounded observation window, budget, and counters.
pub type Loop {
  Loop(
    window: List(Observation),
    window_size: Int,
    budget_us: Int,
    mode: Mode,
    cycles: Int,
    overruns: Int,
  )
}

/// Build a new loop. Non-positive `window_size` defaults to 16 and
/// non-positive `budget_us` defaults to 100_000 (100ms).
pub fn new(window_size: Int, budget_us: Int) -> Loop {
  let ws = case window_size <= 0 {
    True -> 16
    False -> window_size
  }
  let budget = case budget_us <= 0 {
    True -> 100_000
    False -> budget_us
  }
  Loop(
    window: [],
    window_size: ws,
    budget_us: budget,
    mode: Dark,
    cycles: 0,
    overruns: 0,
  )
}

fn clamp(x: Float, lo: Float, hi: Float) -> Float {
  case x <. lo {
    True -> lo
    False -> {
      case x >. hi {
        True -> hi
        False -> x
      }
    }
  }
}

/// Mean of consecutive differences of `values`. Empty and singleton lists
/// yield 0.0. Negative results indicate a converging (falling) series,
/// positive results a diverging (rising) series.
pub fn lyapunov(values: List(Float)) -> Float {
  case values {
    [] -> 0.0
    [_] -> 0.0
    [first, ..rest] -> {
      let #(diffs, _) =
        list.fold(rest, #([], first), fn(acc, v) {
          let #(ds, prev) = acc
          #([v -. prev, ..ds], v)
        })
      let n = list.length(diffs)
      case n {
        0 -> 0.0
        _ -> {
          let total = list.fold(diffs, 0.0, fn(acc, d) { acc +. d })
          total /. int.to_float(n)
        }
      }
    }
  }
}

fn push_bounded(
  window: List(Observation),
  item: Observation,
  size: Int,
) -> List(Observation) {
  let appended = list.append(window, [item])
  let len = list.length(appended)
  case len > size {
    True -> list.drop(appended, len - size)
    False -> appended
  }
}

/// Compute the trend of the health signal across the window, using a
/// 0.01 dead-band around zero to call the trend Stable.
pub fn orient(loop: Loop) -> #(Trend, Float) {
  let values = list.map(loop.window, fn(o) { o.health })
  let l = lyapunov(values)
  let trend = case l >. 0.01 {
    True -> Rising
    False -> {
      case l <. -0.01 {
        True -> Falling
        False -> Stable
      }
    }
  }
  #(trend, l)
}

fn with_andon(actions: List(Action), over_budget: Bool) -> List(Action) {
  case over_budget {
    True -> [RaiseAndon, ..actions]
    False -> actions
  }
}

/// Decide the mode and actions for this cycle from the current trend and
/// latest observation.
pub fn decide(
  loop: Loop,
  trend: Trend,
  latest: Observation,
) -> #(Mode, List(Action)) {
  let over_budget = latest.frame_us > loop.budget_us
  case latest.aspects_failed > 3 {
    True -> #(Emergency, [HaltAdmission, RaiseAndon, Repaint])
    False -> {
      case latest.aspects_failed > 0 {
        True -> #(Bright, with_andon([AuditAspects, Repaint], over_budget))
        False -> {
          case latest.health <. 0.5 {
            True -> #(Normal, with_andon([Repaint], over_budget))
            False -> {
              case trend == Falling {
                True -> #(Dim, with_andon([Repaint], over_budget))
                False -> #(Dark, with_andon([Repaint], over_budget))
              }
            }
          }
        }
      }
    }
  }
}

/// Run one OODA cycle: fold `obs` into the loop, orient, decide, and
/// report whether the cycle stayed within budget. `obs.health` is clamped
/// to `0.0..1.0` before being stored or evaluated.
pub fn step(loop: Loop, obs: Observation) -> #(Loop, Mode, List(Action), Bool) {
  let clamped =
    Observation(
      ts_ms: obs.ts_ms,
      frame_us: obs.frame_us,
      events: obs.events,
      aspects_failed: obs.aspects_failed,
      health: clamp(obs.health, 0.0, 1.0),
    )
  let within_budget = clamped.frame_us <= loop.budget_us
  let window = push_bounded(loop.window, clamped, loop.window_size)
  let cycles = loop.cycles + 1
  let overruns = case within_budget {
    True -> loop.overruns
    False -> loop.overruns + 1
  }
  let scratch = Loop(..loop, window: window)
  let #(trend, _) = orient(scratch)
  let #(mode, actions) = decide(scratch, trend, clamped)
  let next =
    Loop(
      window: window,
      window_size: loop.window_size,
      budget_us: loop.budget_us,
      mode: mode,
      cycles: cycles,
      overruns: overruns,
    )
  #(next, mode, actions, within_budget)
}

/// Human-readable label for a mode.
pub fn mode_label(mode: Mode) -> String {
  case mode {
    Dark -> "DARK"
    Dim -> "DIM"
    Normal -> "NORMAL"
    Bright -> "BRIGHT"
    Emergency -> "EMERGENCY"
  }
}

/// `#(cycles, overruns, overrun_ratio)`. Ratio is 0.0 when no cycles ran.
pub fn stats(loop: Loop) -> #(Int, Int, Float) {
  case loop.cycles {
    0 -> #(0, 0, 0.0)
    c -> #(c, loop.overruns, int.to_float(loop.overruns) /. int.to_float(c))
  }
}
