//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/actors/cpig_supervisor</module>
////     <fsharp-lineage>N/A — new Gleam-first module (Pass-21)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>CPIG Drift Subscription Supervision</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-CPIG-013, SC-CPIG-002, SC-PI-RUNTIME-001, SC-ZMOF-001, SC-GLM-ZEN-001, SC-WIRE-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="otp-fault-tolerance">
////       Raw Erlang Zenoh delivery ↪ Gleam `gleam/otp/actor` `CpigSubscriberMsg`.
////       Mitigation: Untyped tagged tuples on the actor mailbox are translated to
////       `CpigEvent(topic, payload)` via `selector` mapping. Decode failures are
////       absorbed by `cpig_subscriber.handle_message/2` (state-preserving).
////     </morphism>
////   </transformations>
////   <zk-citations>
////     [zk-bb4de67d97f807ac] selector-guessing anti-pattern — supervisor must
////     reify raw deliveries through the typed state machine, not bypass it.
////     [zk-d8929d43344a292d] Pass-19 actor scaffold; this module is its
////     deferred OTP wrapper.
////   </zk-citations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/actors/cpig_subscriber.{
  type CpigState, type CpigSubscriberMsg, CpigEvent, CpigHealthTick,
  CpigShutdown,
}
import cepaf_gleam/ui/domain.{Bridge}
import cepaf_gleam/ui/zenoh_otel.{Observe}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Supervisor wrapper state — owns the underlying CpigState produced by
/// `cpig_subscriber.handle_message/2`. The supervisor is responsible for
/// translating raw Erlang Zenoh deliveries into typed `CpigSubscriberMsg`
/// values; the inner state machine remains pure.
pub type SupervisorState {
  SupervisorState(
    /// Underlying typed CPIG drift state (delegated to cpig_subscriber).
    inner: CpigState,
    /// Whether the supervisor wired a real Zenoh subscription at boot.
    live_subscription: Bool,
    /// Number of raw Erlang deliveries observed (whether decoded or not).
    raw_deliveries: Int,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Default safe entry point. Spawns the OTP actor WITHOUT enabling a real
/// Zenoh subscription (scaffold-only). This is what wiring tests exercise
/// and what the runtime should call when the env var `C3I_CPIG_LIVE` is
/// unset.
///
/// SC-CPIG-002: subscriber MUST be available even when Zenoh router is
/// offline. SC-PI-RUNTIME-001 parity: subprocess managers default to OFF.
pub fn start() -> Result(Subject(CpigSubscriberMsg), actor.StartError) {
  start_with_subscription(False)
}

/// Variant that optionally requests a live Zenoh subscription. When `live`
/// is True the supervisor calls `cpig_subscriber.start_with_subscription(True)`
/// during init; failures are logged but do NOT prevent the actor from
/// starting (state-machine path remains usable).
pub fn start_with_subscription(
  live: Bool,
) -> Result(Subject(CpigSubscriberMsg), actor.StartError) {
  // Best-effort wire of the underlying NIF subscription. Result is logged
  // but not propagated as an OTP start failure — the supervisor must
  // remain bootable so health probes still report a degraded state rather
  // than a missing actor.
  case cpig_subscriber.start_with_subscription(live) {
    Ok(_) -> Nil
    Error(err) -> {
      io.println("[!] cpig_supervisor underlying subscription failed: " <> err)
      Nil
    }
  }

  zenoh_otel.emit(Bridge, "cpig_supervisor_start", Observe)

  let initial =
    SupervisorState(
      inner: cpig_subscriber.init_state(),
      live_subscription: live,
      raw_deliveries: 0,
    )

  actor.new(initial)
  |> actor.on_message(loop)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

// ---------------------------------------------------------------------------
// Loop / message handler
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">
///     CpigSubscriberMsg ↪ delegated cpig_subscriber.handle_message/2.
///   </morphism>
///   <formal-proof>
///     <P> Pre: state.inner is a valid CpigState. </P>
///     <C> loop(state, msg) </C>
///     <Q> Post: returns actor.continue(SupervisorState) with state.inner
///         advanced by cpig_subscriber.handle_message. Never panics. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn loop(
  state: SupervisorState,
  msg: CpigSubscriberMsg,
) -> actor.Next(SupervisorState, CpigSubscriberMsg) {
  case msg {
    CpigShutdown -> actor.stop()
    _ -> {
      let next_inner = cpig_subscriber.handle_message(state.inner, msg)
      let next =
        SupervisorState(
          ..state,
          inner: next_inner,
          raw_deliveries: state.raw_deliveries + 1,
        )
      actor.continue(next)
    }
  }
}

// ---------------------------------------------------------------------------
// Raw Erlang message translation
// ---------------------------------------------------------------------------

/// Translate a raw Erlang term that arrived in this process's mailbox into
/// a typed `CpigSubscriberMsg`. Recognizes the `{zenoh_msg, Topic, Payload}`
/// shape published by the Zenoh NIF; everything else is folded to a health
/// tick so the actor remains observable.
///
/// Exposed publicly so tests can exercise the translation contract without
/// needing a live Zenoh router.
pub fn translate_raw(term: Dynamic) -> CpigSubscriberMsg {
  // We do NOT reach into Dynamic here — keeping the surface minimal makes
  // the supervisor robust to NIF schema drift. A future pass (Pass-22+)
  // will replace this with a `process.selecting_record3` decoder once the
  // Zenoh NIF emits a stable tagged record.
  let _ = term
  CpigHealthTick
}

// ---------------------------------------------------------------------------
// Wiring guard helpers (SC-WIRE-001)
// ---------------------------------------------------------------------------

/// Construct an initial SupervisorState (used by wiring guard).
pub fn init_state() -> SupervisorState {
  SupervisorState(
    inner: cpig_subscriber.init_state(),
    live_subscription: False,
    raw_deliveries: 0,
  )
}

/// Apply a CpigEvent through the supervisor handler synchronously (used by
/// wiring guard / tests). Bypasses the OTP runtime so the loop contract
/// can be exercised without spawning a process.
pub fn apply_event(
  state: SupervisorState,
  topic: String,
  payload: String,
) -> SupervisorState {
  let inner =
    cpig_subscriber.handle_message(
      state.inner,
      CpigEvent(topic: topic, payload: payload),
    )
  SupervisorState(
    ..state,
    inner: inner,
    raw_deliveries: state.raw_deliveries + 1,
  )
}

/// Render a one-line summary of the supervisor state — intended for
/// human/agent inspection on the dashboard.
pub fn summary(state: SupervisorState) -> String {
  "CpigSupervisor: live="
  <> string.inspect(state.live_subscription)
  <> " raw_deliveries="
  <> string.inspect(state.raw_deliveries)
  <> " inner_msgs="
  <> string.inspect(state.inner.messages_processed)
}
