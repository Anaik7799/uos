//// =============================================================================
//// [C3I-SIL6-MSTS] Signing-key rotation scheduler actor
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/key_rotation_actor</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FERRISKEY-NIF-008</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// LIVE OTP actor that decides when to rotate signing keys per realm.
//// SC-FERRISKEY-NIF-008: rotation ≤ 90 days, 7-day overlap window.
////
//// Decision pure function: `decide_rotation(now, last_rotated_at) -> Decision`.
//// Phase 7.5 substrate ships the decision logic + actor message wiring.
//// Phase 8+ wires the periodic timer that drives `Tick` messages.

import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision

/// 90 days in seconds (SC-FERRISKEY-NIF-008).
pub const rotation_age_seconds: Int = 7_776_000

/// 7 days in seconds — overlap window during which both old + new keys
/// are in the JWKS.
pub const overlap_window_seconds: Int = 604_800

pub type Decision {
  /// Key is still fresh — no action.
  KeepCurrent(age_seconds: Int)
  /// Key is past rotation_age — rotate now.
  RotateNow(age_seconds: Int)
  /// Key was just rotated and is in overlap — track for retire eligibility.
  InOverlap(remaining_seconds: Int)
  /// Key has aged out of overlap — retire (purge from JWKS).
  RetireOld(age_past_overlap_seconds: Int)
}

/// Decision logic for one realm's signing key.
/// `created_at` and `rotated_at` are unix-second timestamps; `rotated_at`
/// is None for the current key, Some(t) for keys in overlap.
pub fn decide_rotation(
  now: Int,
  created_at: Int,
  rotated_at: OptionInt,
) -> Decision {
  case rotated_at {
    OptInt(t) -> {
      // Key was rotated at `t`; it is in overlap until t + overlap_window.
      let age_in_overlap = now - t
      case age_in_overlap >= overlap_window_seconds {
        True ->
          RetireOld(
            age_past_overlap_seconds: age_in_overlap - overlap_window_seconds,
          )
        False ->
          InOverlap(remaining_seconds: overlap_window_seconds - age_in_overlap)
      }
    }
    OptNone -> {
      // Current key — has it aged past rotation_age?
      let age = now - created_at
      case age >= rotation_age_seconds {
        True -> RotateNow(age_seconds: age)
        False -> KeepCurrent(age_seconds: age)
      }
    }
  }
}

/// Custom Maybe wrapper so we don't depend on `gleam/option`.
pub type OptionInt {
  OptInt(value: Int)
  OptNone
}

pub type State {
  State(decisions: Int, rotations_triggered: Int)
}

pub type Msg {
  /// Caller asks for a decision on a single key, given current epoch + key state.
  Decide(
    now: Int,
    created_at: Int,
    rotated_at: OptionInt,
    reply_to: Subject(Decision),
  )
  /// Read counters.
  Metrics(reply_to: Subject(State))
}

pub fn supervised() -> supervision.ChildSpecification(Subject(Msg)) {
  supervision.worker(start)
  |> supervision.restart(supervision.Permanent)
}

pub fn start() -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  actor.new(State(decisions: 0, rotations_triggered: 0))
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Decide(now, created_at, rotated_at, reply) -> {
      let d = decide_rotation(now, created_at, rotated_at)
      let triggered = case d {
        RotateNow(_) -> state.rotations_triggered + 1
        _ -> state.rotations_triggered
      }
      process.send(reply, d)
      actor.continue(State(
        decisions: state.decisions + 1,
        rotations_triggered: triggered,
      ))
    }
    Metrics(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
  }
}
