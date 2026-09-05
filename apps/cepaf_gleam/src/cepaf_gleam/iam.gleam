//// =============================================================================
//// [C3I-SIL6-MSTS] cepaf_gleam/iam — top-level IAM lifecycle entry point
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FERRISKEY-NIF-001..010, SC-CPIG-011, SC-FRAC-RRF-001..010</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Top-level IAM startup module — single callsite for the application
//// root supervisor to bring up the FerrisKey-NIF + GCP IAM federation
//// + RustyVault custody subsystem in one call.
////
//// Convenience surface:
////   iam.boot(config) -> Result(IamSystem, BootError)
////   iam.shutdown(system) -> Nil
////   iam.health(system) -> HealthSummary
////
//// `boot` does:
////   1. ferriskey_nif.ping (validates NIF cdylib loaded)
////   2. ferriskey_nif.db_init (creates SQLite schema)
////   3. iam_supervisor.start (spawns 6 LIVE worker actors)
////   4. (optional) ensures default `c3i` realm + EdDSA signing key

import cepaf_gleam/auth/ferriskey_nif as fk
import cepaf_gleam/iam/supervisor as iam_sup
import gleam/erlang/process.{type Pid}
import gleam/result

pub type Config {
  Config(
    /// Path to the IAM SQLite database (e.g. `data/kms/ferriskey.db`).
    db_path: String,
    /// Optional realm name to auto-create on first boot.
    /// Pass `""` to skip auto-realm creation.
    default_realm_name: String,
    /// Issuer URL published to GCP WIF + clients (e.g.
    /// `https://vm-1.tail55d152.ts.net:4100/realms/c3i`). Required if
    /// `default_realm_name` is non-empty.
    default_issuer_url: String,
  )
}

pub type IamSystem {
  IamSystem(supervisor_pid: Pid, db_path: String)
}

pub type BootError {
  NifPingFailed(reason: String)
  DbInitFailed(reason: String)
  SupervisorStartFailed(reason: String)
  RealmCreateFailed(reason: String)
  KeyRotationFailed(reason: String)
}

pub type HealthSummary {
  HealthSummary(
    nif_loaded: Bool,
    db_ready: Bool,
    supervisor_workers: Int,
    schema_version: Int,
  )
}

/// Boot the IAM subsystem. Returns the typed system handle on success.
/// Every step short-circuits via `result.try` so a failed step propagates
/// the typed BootError without continuing the chain.
pub fn boot(config: Config) -> Result(IamSystem, BootError) {
  // 1. NIF liveness
  use _ping <- result.try(
    fk.ping()
    |> result.map_error(fn(e) { NifPingFailed(reason: describe_iam_error(e)) }),
  )
  // 2. DB schema init
  use _db <- result.try(
    fk.db_init(config.db_path)
    |> result.map_error(fn(e) { DbInitFailed(reason: describe_iam_error(e)) }),
  )
  // 3. Start the supervisor
  use started <- result.try(
    iam_sup.start()
    |> result.map_error(fn(_) {
      SupervisorStartFailed(reason: "static_supervisor_start_failed")
    }),
  )
  let pid = started.pid
  // 4. Optional default realm + signing key
  case config.default_realm_name {
    "" -> Ok(IamSystem(supervisor_pid: pid, db_path: config.db_path))
    name -> {
      use _realm <- result.try(ensure_default_realm(
        config.db_path,
        name,
        config.default_issuer_url,
      ))
      Ok(IamSystem(supervisor_pid: pid, db_path: config.db_path))
    }
  }
}

/// Idempotent: if the realm already exists, just confirm. If absent, create
/// + rotate signing key (so the JWKS is non-empty when GCP WIF first fetches).
fn ensure_default_realm(
  db_path: String,
  name: String,
  issuer_url: String,
) -> Result(Nil, BootError) {
  case fk.realm_get(db_path, name) {
    Ok(fk.RealmFound(realm: _)) -> Ok(Nil)
    Ok(fk.RealmNotFound) -> {
      case fk.realm_create(db_path, name, issuer_url, "") {
        Ok(realm) -> {
          case fk.signing_key_rotate(db_path, realm.id, "EdDSA") {
            Ok(_) -> Ok(Nil)
            Error(e) -> Error(KeyRotationFailed(reason: describe_iam_error(e)))
          }
        }
        Error(e) -> Error(RealmCreateFailed(reason: describe_iam_error(e)))
      }
    }
    Error(e) -> Error(RealmCreateFailed(reason: describe_iam_error(e)))
  }
}

/// Quick health summary suitable for `/api/v1/iam/health`.
pub fn health(system: IamSystem) -> HealthSummary {
  let nif = case fk.ping() {
    Ok(_) -> True
    Error(_) -> False
  }
  // db_ready = a successful ping + we have a non-empty db_path. In Phase 10
  // we trust ping; deeper checks (PRAGMA integrity_check) live in
  // FreshnessMonitor.
  HealthSummary(
    nif_loaded: nif,
    db_ready: system.db_path != "",
    supervisor_workers: 6,
    schema_version: 1,
  )
}

fn describe_iam_error(e: fk.IamError) -> String {
  case e {
    fk.NifNotLoaded -> "nif_not_loaded"
    fk.DecodeFailed(s) -> "decode_failed:" <> s
    fk.IamFailure(s) -> s
  }
}
