//// Vault sync actor — OTP gen_server that reconciles local Vault with GCP
//// Secret Manager every 5 minutes when online.
////
//// Per .claude/rules/secrets-vault.md SC-VAULT-010 (circuit breaker), SC-VAULT-017
//// (europe-north1), SC-VAULT-019 (separate CMEK keyrings).
////
//// SLICE D SKELETON — actor surface compiles; pull/push body deferred.

import cepaf_gleam/vault.{type VaultHandle}

// =====================================================================
// Types
// =====================================================================

/// Actor state.
pub type State {
  State(
    handle: VaultHandle,
    last_sync_at: Int,
    consecutive_failures: Int,
    circuit_open_until: Int,
    online: Bool,
  )
}

/// Messages the actor responds to.
pub type Msg {
  /// Tick (every 5 min via timer or explicit).
  Tick
  /// Force immediate sync (operator action via CLI).
  ForceSync
  /// Network probe result.
  NetworkProbed(reachable: Bool)
  /// Stop the actor.
  Stop
}

/// Outcome of a single sync cycle (returned in a reply or telemetry).
pub type SyncOutcome {
  Nominal(pulled: Int, pushed: Int, duration_ms: Int)
  Degraded(reason: String)
  CircuitOpen(reset_in_seconds: Int)
}

// =====================================================================
// Circuit breaker — SC-VAULT-010 (3 fail / 60s cooldown)
// =====================================================================

pub fn circuit_should_open(consecutive_failures: Int) -> Bool {
  consecutive_failures >= 3
}

pub fn circuit_cooldown_seconds() -> Int {
  60
}

pub fn circuit_open_for(now_seconds: Int) -> Int {
  now_seconds + circuit_cooldown_seconds()
}

// =====================================================================
// Conflict resolution — SC-VAULT-011 (monotonic version vector + LWW)
// =====================================================================

/// For each secret name, decide direction based on version comparison.
pub type SyncDirection {
  Pull(remote_version: Int)
  Push(local_version: Int)
  NoOp
  Divergence(reason: String)
}

pub fn decide_direction(
  local_version: Int,
  remote_version: Int,
  has_unsynced_flag: Bool,
) -> SyncDirection {
  case local_version, remote_version, has_unsynced_flag {
    _, r, _ if r > local_version -> Pull(remote_version: r)
    l, _, True if l > remote_version -> Push(local_version: l)
    l, r, False if l > r ->
      Divergence(reason: "local advanced without sync flag")
    _, _, _ -> NoOp
  }
}

// =====================================================================
// Public API
// =====================================================================

/// Construct an idle (just-booted) sync actor state.
pub fn init(handle: VaultHandle) -> State {
  State(
    handle: handle,
    last_sync_at: 0,
    consecutive_failures: 0,
    circuit_open_until: 0,
    online: True,
  )
}

/// Process a Tick message. Returns new state + outcome to publish on Zenoh.
pub fn handle_tick(state: State, now_seconds: Int) -> #(State, SyncOutcome) {
  // Check circuit breaker first
  case state.circuit_open_until > now_seconds {
    True -> #(
      state,
      CircuitOpen(reset_in_seconds: state.circuit_open_until - now_seconds),
    )
    False ->
      case state.online {
        False -> #(state, Degraded(reason: "offline"))
        True -> {
          // SLICE D continuation: actually sync. Stub returns nominal 0/0.
          let new_state =
            State(..state, last_sync_at: now_seconds, consecutive_failures: 0)
          #(new_state, Nominal(pulled: 0, pushed: 0, duration_ms: 1))
        }
      }
  }
}

/// Process NetworkProbed — drives the online/offline flag.
pub fn handle_network_probe(state: State, reachable: Bool) -> State {
  State(..state, online: reachable)
}

/// Record a sync failure; bumps consecutive_failures and may open circuit.
pub fn record_failure(state: State, now_seconds: Int) -> State {
  let new_failures = state.consecutive_failures + 1
  case circuit_should_open(new_failures) {
    True ->
      State(
        ..state,
        consecutive_failures: new_failures,
        circuit_open_until: circuit_open_for(now_seconds),
      )
    False -> State(..state, consecutive_failures: new_failures)
  }
}

/// Reset failure counter on successful sync.
pub fn record_success(state: State, now_seconds: Int) -> State {
  State(
    ..state,
    consecutive_failures: 0,
    circuit_open_until: 0,
    last_sync_at: now_seconds,
  )
}
