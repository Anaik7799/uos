import gleeunit/should
import main.{execute, file_exists, parse_args}

pub fn mirage_core_inventory_is_complete_and_cli_returns_hold_exit_1_test() {
  // 1. Explicitly verify complete inventory is present on disk
  file_exists("engines/hermes/modules/hermes_mirage/mirage_signatures.ml")
  |> should.be_true
  file_exists("engines/hermes/modules/hermes_mirage/mirage_memory_block.ml")
  |> should.be_true
  file_exists("engines/hermes/modules/hermes_mirage/mirage_merkle_kv.ml")
  |> should.be_true
  file_exists("engines/hermes/modules/hermes_mirage/mirage_solo5_tender.ml")
  |> should.be_true
  file_exists("engines/hermes/modules/hermes_mirage/mirage_interceptor.ml")
  |> should.be_true
  file_exists(
    "apps/cepaf_gleam/src/cepaf_gleam/services/mirage_unikernel_daemon.gleam",
  )
  |> should.be_true
  file_exists("apps/cepaf_gleam/test/mirage_unikernel_daemon_test.gleam")
  |> should.be_true

  // 2. Actual CLI execution must report HOLD and return exit code 1 (file presence does not grant admission)
  parse_args(["gate", "G-MIRAGE"])
  |> execute
  |> should.equal(1)
}

pub fn mirage_migration_inventory_is_complete_and_cli_returns_hold_exit_1_test() {
  file_exists(
    "engines/hermes/modules/hermes_mirage/mirage_migration_catalog.ml",
  )
  |> should.be_true
  file_exists("engines/hermes/modules/hermes_mirage/mirage_dns_resolver.ml")
  |> should.be_true
  file_exists("engines/hermes/modules/hermes_mirage/mirage_tls_ingress.ml")
  |> should.be_true
  file_exists("engines/hermes/modules/hermes_mirage/test_mirage_migration.ml")
  |> should.be_true
  file_exists(
    "apps/cepaf_gleam/src/cepaf_gleam/services/mirage_migration_engine.gleam",
  )
  |> should.be_true
  file_exists("apps/cepaf_gleam/test/mirage_migration_engine_test.gleam")
  |> should.be_true
  file_exists("contracts/rules/mirage-migration-policy.md")
  |> should.be_true
  file_exists(
    "docs/design/20260907-1120-mirageos-comprehensive-migration-and-subsystem-spec.md",
  )
  |> should.be_true

  parse_args(["gate", "G-MIRAGE-MIGRATE"])
  |> execute
  |> should.equal(1)
  parse_args(["gate", "mirage-migration"])
  |> execute
  |> should.equal(1)
}

pub fn mirage_prod_inventory_is_complete_and_cli_returns_hold_exit_1_test() {
  file_exists("engines/hermes/modules/hermes_mirage/hermes_mirage_runner.ml")
  |> should.be_true
  file_exists("apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/mirage_cockpit.gleam")
  |> should.be_true
  file_exists("apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/mirage_api.gleam")
  |> should.be_true
  file_exists("apps/cepaf_gleam/src/cepaf_gleam/ui/tui/mirage_view.gleam")
  |> should.be_true
  file_exists("apps/cepaf_gleam/test/mirage_cockpit_test.gleam")
  |> should.be_true
  file_exists("contracts/rules/mirage-production-integration-contract.md")
  |> should.be_true
  file_exists(
    "docs/design/20260907-1215-mirageos-triple-surface-cockpit-and-solo5-cutover-spec.md",
  )
  |> should.be_true
  file_exists(
    "docs/journal/20260907-1215-mirageos-triple-surface-cockpit-and-solo5-cutover-journal.md",
  )
  |> should.be_true

  parse_args(["gate", "G-MIRAGE-PROD"])
  |> execute
  |> should.equal(1)
  parse_args(["gate", "mirage-prod"])
  |> execute
  |> should.equal(1)
}
