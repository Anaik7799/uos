# rusty_vault_nif (tracked source of `apps/cepaf_gleam/priv/rusty_vault_nif.so`)

#fractal-l1 #fractal-l3 #fractal-l6 #fractal-l9 #zero-muda

[This file](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/native/rusty_vault_nif/README.md) · [Ingestion manifest 2026-10-25](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20261025-2230-nif-in-project-build.json) · [Source-control verification 2026-10-26](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20261026-1420-vault-source-control-verification-and-c3i-telegram-gateway-ingestion.json) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

- **Source**: this crate, ingested from `/home/an/dev/ver/c3i/lib/cepaf_gleam/native/rusty_vault_nif` (C3I rev 47f93223) and verified byte-identical on 2026-10-26 (`src/` and Cargo files; C3I's empty `tests/` directory is omitted).
- **Dependency**: `sub-projects/rusty_vault_vendored` (upstream Tongsuo RustyVault 0.3.1, Apache-2.0), tracked with its two recorded test-module redactions (`src/utils/cert.rs`, `src/modules/pki/mod.rs`: embedded PEM private-key fixtures removed) and without `docs/`, `.github/`, `.vscode/`, `target/`.
- **Build**: `cargo build --release --offline --locked` from `toolchains/cargo` (rustc 1.95.0, OTP 29.0.5 headers). `target/` is ignored.
- **Install and pin**: `apps/cepaf_gleam/priv/rusty_vault_nif.so`, pinned by `apps/cepaf_gleam/priv/rusty_vault_nif.sha256`. A rebuild that changes the digest must re-pin with provenance.
- **Loader**: `apps/cepaf_gleam/src/rusty_vault_nif.erl` (`-on_load`), safe wrapper `rusty_vault_safe.erl`.

## Finding VF-01 (recorded 2026-10-26; FIXED at the wave 6v revision; sovereign review VAULT_NIF_REVIEW pending)

Observed at runtime (Telegram wave 6r): the loaded NIF persisted nothing under its storage path (a `put` in one BEAM was `not_found` in the next) and unsealed with any 32-byte key, including one never used to seal.

The source explained it exactly; it was the stub in the source, not a build or provisioning drift:

- `src/lib.rs` `VaultHandle` (the NIF resource) kept `kv_store` as `Mutex<HashMap<String, Vec<KvEntry>>>` in RAM and `audit_log` as `Mutex<Vec<AuditEntry>>`.
- `vault_unseal` carried the comment `TODO Slice B+: integrate RustyVault::core::Core::unseal(master_key)` and only checked `master_key.len() == 32` before storing the key in RAM.
- `src/vault_handle.rs` defined a disk-backed handle over `src/sqlite_backend.rs` (rusqlite, WAL pragma) with unit tests, but no NIF entry point in `lib.rs` constructed or called it.

### The closure (wave 6v)

- The NIF resource now owns `DiskVaultHandle`; every secret is stored as an AES-256-GCM envelope (`crypto.rs`) in `kv_entries`, the audit trail is the `audit_log` table with triggers that refuse `UPDATE` and `DELETE`, and nothing is cached in the handle beyond the master key.
- The first unseal of an empty vault writes an encrypted verifier row in `vault_meta`; every later unseal must decrypt it, so a wrong key returns `{error, wrong_key}` and the vault stays sealed. A verifier row that is not an envelope marks the handle `corrupt`.
- `vault_init` accepts a directory (resolves to `<dir>/vault.sqlite3`) or a file path; paths and names are binaries.
- Laws: 9 `vf01_laws` cargo tests (66 in the crate), 2 mutants killed (verifier skipped; plaintext stored), `test/rusty_vault_persistence_test.erl` through the loaded NIF, and a three-process OTP 29 observation (put in one BEAM, get in the next, wrong key in a third, no plaintext on disk) recorded in the wave 6v journal.
- The durable file store `apps/cepaf_gleam/src/uos_vault_file.erl` with its OCaml twin `tools/uos_vault.ml` remains the path the Telegram staging and production secrets use; switching them to the NIF is a separate decision after the review.

UOS footer: `nas-1.tail55d152.ts.net:4100` · source presence and a pinned digest grant no admission.
