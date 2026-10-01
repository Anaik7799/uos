//// =============================================================================
//// [UOS-L2-COMP] Provider Service Extension & Old 3 Compat Test Suite
//// =============================================================================

import gleam/dict
import gleam/string
import gleeunit/should
import session_store_cli
import simplifile
import uos_swarm/session_authority as authority
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

fn fixture_isolated_db() -> #(String, String) {
  let root = "/tmp/uos-telegram-provider-stage-" <> unique_id()
  let assert Ok(_) = simplifile.create_directory_all(root)
  let assert Ok(_) = simplifile.set_permissions_octal(root, 0o700)
  let db = root <> "/coordinator.sqlite3"
  let assert Ok(opened) = store.open(db)
  let assert Ok(_) =
    store.append(
      opened,
      sync.Register("bootstrap-admin", "codex", root, "rev-0", []),
      "bootstrap-register",
    )
  let assert Ok(_) = store.close(opened)
  let assert Ok(_) = simplifile.set_permissions_octal(db, 0o600)
  #(root, db)
}

pub fn provider_parse_and_render_test() {
  sync.parse_provider("claude") |> should.equal(Ok(sync.Claude))
  sync.parse_provider("codex") |> should.equal(Ok(sync.Codex))
  sync.parse_provider("agy") |> should.equal(Ok(sync.Agy))
  sync.parse_provider("service") |> should.equal(Ok(sync.Service))

  sync.parse_provider("unknown")
  |> should.equal(Error("provider must be claude, codex, agy, or service"))

  sync.parse_provider("root")
  |> should.equal(Error("provider must be claude, codex, agy, or service"))

  sync.provider_to_string(sync.Claude) |> should.equal("claude")
  sync.provider_to_string(sync.Codex) |> should.equal("codex")
  sync.provider_to_string(sync.Agy) |> should.equal("agy")
  sync.provider_to_string(sync.Service) |> should.equal("service")
}

pub fn isolated_db_service_registration_and_replay_test() {
  let #(root, db) = fixture_isolated_db()

  // 1. Verify that open_existing succeeds on un-migrated v1 DB
  let assert Ok(v1_store) = store.open_existing(db)
  let assert Ok(v1_report) = store.verify(v1_store)
  v1_report.ok |> should.equal(True)
  let assert Ok(_) = store.close(v1_store)

  // 2. Old 3 providers register successfully on v1 DB
  let assert Ok(claude_resp) =
    authority.run_at(db, [
      "register",
      "claude-worker",
      "claude",
      root,
      "rev-c",
      "-",
      "op-reg-claude",
    ])
  string.contains(claude_resp, "\"ok\":true") |> should.equal(True)

  // 3. Service provider is refused on v1 DB before migration (trigger aborts with SQLITE_CONSTRAINT_TRIGGER 1811)
  case
    authority.run_at(db, [
      "register",
      "telegram-service",
      "service",
      root,
      "rev-service-1",
      "-",
      "op-reg-service-premature",
    ])
  {
    Error(err) -> {
      // Must fail because v1 trigger rejects 'service' with storage constraint 1811
      string.contains(err, "1811") |> should.equal(True)
    }
    Ok(_) ->
      panic as "Service provider must be refused on v1 DB before migration"
  }

  // 4. Invalid provider is strictly refused on v1 DB
  case
    authority.run_at(db, [
      "register",
      "bad-worker",
      "unauthorized_agent",
      root,
      "rev-bad",
      "-",
      "op-reg-bad-1",
    ])
  {
    Error(err) -> {
      string.contains(err, "provider must be claude, codex, agy, or service")
      |> should.equal(True)
    }
    Ok(_) -> panic as "Invalid provider registration must be refused"
  }

  // 5. Explicit staged migration to v2
  let assert Ok(Nil) = store.migrate_to_service_provider(db)

  // 6. Verify that open_existing succeeds on migrated v2 DB
  let assert Ok(v2_store) = store.open_existing(db)
  let assert Ok(v2_report) = store.verify(v2_store)
  v2_report.ok |> should.equal(True)
  let assert Ok(_) = store.close(v2_store)

  // 7. Service provider registration now succeeds on migrated v2 DB
  let assert Ok(service_resp) =
    authority.run_at(db, [
      "register",
      "telegram-service",
      "service",
      root,
      "rev-service-1",
      "-",
      "op-reg-service",
    ])
  string.contains(service_resp, "\"ok\":true") |> should.equal(True)

  // 8. Other providers still register successfully after migration
  let assert Ok(codex_resp) =
    authority.run_at(db, [
      "register",
      "codex-worker",
      "codex",
      root,
      "rev-x",
      "-",
      "op-reg-codex",
    ])
  string.contains(codex_resp, "\"ok\":true") |> should.equal(True)

  let assert Ok(agy_resp) =
    authority.run_at(db, [
      "register",
      "agy-worker",
      "agy",
      root,
      "rev-a",
      "-",
      "op-reg-agy",
    ])
  string.contains(agy_resp, "\"ok\":true") |> should.equal(True)

  // 9. Invalid provider is still strictly refused after migration
  case
    authority.run_at(db, [
      "register",
      "bad-worker-2",
      "unauthorized_agent",
      root,
      "rev-bad-2",
      "-",
      "op-reg-bad-2",
    ])
  {
    Error(err) -> {
      string.contains(err, "provider must be claude, codex, agy, or service")
      |> should.equal(True)
    }
    Ok(_) ->
      panic as "Invalid provider registration must still be refused after migration"
  }

  // 10. Replay from isolated database succeeds and recovers registered service
  let assert Ok(service_session) =
    authority.query_at(db, fn(state, _boot, _now) {
      case dict.get(state.sessions, "telegram-service") {
        Ok(s) -> Ok(s)
        Error(Nil) -> Error("telegram-service session not found in state")
      }
    })

  service_session.provider |> should.equal("service")
  service_session.workspace |> should.equal(root)

  // 11. Migration is idempotent
  let assert Ok(Nil) = store.migrate_to_service_provider(db)
}

pub fn main() {
  provider_parse_and_render_test()
  isolated_db_service_registration_and_replay_test()
}

pub fn operational_and_alias_paths_refused_test() {
  store.migrate_to_service_provider(
    "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3",
  )
  |> should.be_error
  session_store_cli.run([
    "migrate-service-provider",
    "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3",
  ])
  |> should.be_error
  let #(root, db) = fixture_isolated_db()
  store.migrate_to_service_provider(root <> "/./coordinator.sqlite3")
  |> should.be_error
  let alias_root = "/tmp/uos-telegram-provider-stage-" <> unique_id()
  let assert Ok(_) = simplifile.create_symlink(root, alias_root)
  store.migrate_to_service_provider(alias_root <> "/coordinator.sqlite3")
  |> should.be_error
  let assert Ok(before) = store.open_existing(db)
  let assert Ok(journal) = store.journal(before)
  let assert Ok(_) = store.close(before)
  let assert Ok(_) =
    simplifile.write(db <> ".recovery-lock", "private_test_lock")
  store.migrate_to_service_provider(db) |> should.be_error
  store.migrate_to_service_provider(alias_root <> "/coordinator.sqlite3")
  |> should.be_error
  let assert Ok(_) = simplifile.delete(db <> ".recovery-lock")
  let assert Ok(after) = store.open_existing(db)
  store.journal(after) |> should.equal(Ok(journal))
  let assert Ok(_) = store.close(after)
}

pub fn stage_permissions_refused_test() {
  let #(root, db) = fixture_isolated_db()
  let assert Ok(_) = simplifile.set_permissions_octal(root, 0o755)
  store.migrate_to_service_provider(db) |> should.be_error
  let assert Ok(_) = simplifile.set_permissions_octal(root, 0o700)
  let assert Ok(_) = simplifile.set_permissions_octal(db, 0o644)
  store.migrate_to_service_provider(db) |> should.be_error
  let assert Ok(_) = simplifile.set_permissions_octal(db, 0o600)
  store.migrate_to_service_provider(db) |> should.be_ok
}

pub fn migration_preserves_full_journal_test() {
  let #(_root, db) = fixture_isolated_db()
  let assert Ok(before) = store.open_existing(db)
  let assert Ok(bytes) = store.journal(before)
  let assert Ok(head) = store.head(before)
  let assert Ok(_) = store.close(before)
  store.migrate_to_service_provider(db) |> should.be_ok
  let assert Ok(after) = store.open_existing(db)
  store.journal(after) |> should.equal(Ok(bytes))
  store.head(after) |> should.equal(Ok(head))
  let assert Ok(report) = store.verify(after)
  report.ok |> should.be_true
  let assert Ok(_) = store.close(after)
}

pub fn file_symlink_and_hardlink_refused_test() {
  let #(_root, db) = fixture_isolated_db()
  let other = "/tmp/uos-telegram-provider-stage-" <> unique_id()
  let assert Ok(_) = simplifile.create_directory(other)
  let assert Ok(_) = simplifile.set_permissions_octal(other, 0o700)
  let alias = other <> "/coordinator.sqlite3"
  let assert Ok(_) = simplifile.create_symlink(db, alias)
  store.migrate_to_service_provider(alias) |> should.be_error
  let assert Ok(_) = simplifile.delete(alias)
  let assert Ok(_) = simplifile.create_link(db, alias)
  store.migrate_to_service_provider(alias) |> should.be_error
  store.migrate_to_service_provider(db) |> should.be_error
  let assert Ok(_) = simplifile.delete(alias)
  store.migrate_to_service_provider(db) |> should.be_ok
}
