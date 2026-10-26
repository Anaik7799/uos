# rusty_vault_nif (tracked source of `apps/cepaf_gleam/priv/rusty_vault_nif.so`)

#fractal-l1 #fractal-l3 #fractal-l6 #fractal-l9 #zero-muda

[This file](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/native/rusty_vault_nif/README.md) · [Ingestion manifest 2026-10-25](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20261025-2230-nif-in-project-build.json) · [Source-control verification 2026-10-26](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20261026-1420-vault-source-control-verification-and-c3i-telegram-gateway-ingestion.json) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

- **Source**: this crate, ingested from `/home/an/dev/ver/c3i/lib/cepaf_gleam/native/rusty_vault_nif` (C3I rev 47f93223) and verified byte-identical on 2026-10-26 (`src/` and Cargo files; C3I's empty `tests/` directory is omitted).
- **Dependency**: `sub-projects/rusty_vault_vendored` (upstream Tongsuo RustyVault 0.3.1, Apache-2.0), tracked with its two recorded test-module redactions (`src/utils/cert.rs`, `src/modules/pki/mod.rs`: embedded PEM private-key fixtures removed) and without `docs/`, `.github/`, `.vscode/`, `target/`.
- **Build**: `cargo build --release --offline --locked` from `toolchains/cargo` (rustc 1.95.0, OTP 29.0.5 headers). `target/` is ignored.
- **Install and pin**: `apps/cepaf_gleam/priv/rusty_vault_nif.so`, pinned by `apps/cepaf_gleam/priv/rusty_vault_nif.sha256`. A rebuild that changes the digest must re-pin with provenance.
- **Loader**: `apps/cepaf_gleam/src/rusty_vault_nif.erl` (`-on_load`), safe wrapper `rusty_vault_safe.erl`.

## Finding VF-01 (recorded 2026-10-26, status RECORDED_FOR_SOVEREIGN_REVIEW)

Observed at runtime (Telegram wave 6r): the loaded NIF persists nothing under its storage path (a `put` in one BEAM is `not_found` in the next) and unseals with any 32-byte key, including one never used to seal.

The source explains it exactly; this is the stub in the source, not a build or provisioning drift:

- `src/lib.rs` `VaultHandle` (the NIF resource) keeps `kv_store` as `Mutex<HashMap<String, Vec<KvEntry>>>` in RAM and `audit_log` as `Mutex<Vec<AuditEntry>>`.
- `vault_unseal` carries the comment `TODO Slice B+: integrate RustyVault::core::Core::unseal(master_key)` and only checks `master_key.len() == 32` before storing the key in RAM.
- `src/vault_handle.rs` defines a separate disk-backed `VaultHandle` over `src/sqlite_backend.rs` (rusqlite, WAL pragma) with unit tests, but no NIF entry point in `lib.rs` constructs or calls it.

Until the NIF is completed, rebuilt from this crate, re-pinned and sovereign-reviewed (R5), the only persistent vault path in UOS is the durable file store `apps/cepaf_gleam/src/uos_vault_file.erl` with its OCaml twin `tools/uos_vault.ml` (same `UOSV1` format; cross-read verified both ways in wave 6r). Required follow-up: wire the disk-backed handle or RustyVault Core into the entry points, add a persistence law (put in one BEAM, get in the next) and a wrong-key law, rebuild, re-pin, review.

UOS footer: `nas-1.tail55d152.ts.net:4100` · source presence and a pinned digest grant no admission.
