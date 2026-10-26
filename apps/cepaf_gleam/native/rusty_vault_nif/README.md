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

### Independent review and hardening (wave 6w)

- VAULT_NIF_REVIEW was completed by `agy-review-v-20261026` with APPROVE: seven laws VERIFIED (persistence across BEAMs, wrong key, disk secrecy, audit append-only, fail-closed reads, pinned library, barred dependencies), 66 cargo and 75 eunit tests, eight hostile probes. The reviewer's rebuild produced a different digest (debuginfo carries the workspace path), so V-LAW-06 rests on the identical test outcome, not on byte equality.
- VAULT_NIF_REVIEW2 (`agy-review-v2-20261026`, APPROVE, 4/4 laws, 143 tests) re-checked the predecessor laws at 96ab356f and found a spaces-only name accepted (a contract decision, left as is).
- VAULT_NIF_REVIEW3 (`agy-review-v3-20261026`, adversarial, APPROVE, 6/6 laws at 28d0d752) proved durability under `kill -9`, four concurrent writers, the verifier race (one winner, one `wrong_key`), zeroization after seal, and found two defects, both closed in wave 6x: a `vault_seal` between the active check and the key lock panicked inside the lock and poisoned it, after which the handle only answered `nif_panicked`; and direct sqlite access could drop the triggers and rewrite or forge audit rows without `vault_audit_tail` noticing.

### Wave 6x hardening (VAULT_NIF_HARDEN2)

- Every lock tolerates poison (`unwrap_or_else(|p| p.into_inner())`) and every key read takes the lock first and answers `Sealed` when the key is absent; the race is pinned by a cargo law that seals and unseals from a second thread for 400 iterations while reads and writes proceed, and by the handle still serving afterwards.
- `audit_log` rows carry a blake2s-256 `digest` over the previous digest and the row's fields; appends run under `BEGIN IMMEDIATE` with a 5 s busy timeout so concurrent writers serialize; `vault_audit_tail` verifies the whole chain first and answers `{error, {audit_chain_broken, Id}}` for a rewritten, inserted, deleted or pre-chain row. Files that predate the column receive it through `ALTER TABLE` at open; their pre-chain rows make the tail refuse until the file is re-created (no deployed NIF vault exists yet).
- Laws: 69 cargo tests (12 `vf01_laws`), two mutants killed (verifier ignores mismatch; append forgets the predecessor), `rusty_vault_persistence_test.erl` tamper law through the host `sqlite3`. Pin a5b63b75 supersedes 6db27c1e. Residual: a tamperer who rewrites the whole chain consistently from the first row is not detected by the chain alone; a root digest kept outside the file would be the next step.
### Wave 6y: the external root (VAULT_NIF_HARDEN3)

- VAULT_NIF_REVIEW4 (`agy-review-v4-20261026`, APPROVE, 6/6 laws at d75aa8f1: 190,661 seal cycles against 4,960,940 operations with zero panics; four-writer chain integrity; tamper-evidence with correct first ids; pre-chain file migration) left one residual: a tamperer who recomputes every digest from the first row passes the in-file verification.
- `vault_audit_root/1` answers the verified chain head as `{ok, #{rows => N, digest => Hex}}`; `vault_audit_verify_root/2` answers `{ok, Rows}`, `{error, {audit_chain_broken, Id}}` or `{error, {audit_root_mismatch, Expected, Actual}}`. A caller that keeps the head outside the file (a Sa-plan evidence row, a ledger entry) detects a consistent full rewrite, a truncation or a replaced file. Where the root is kept is the caller's decision; this crate provides the primitive.
- Laws: a cargo law performs the consistent rewrite itself and shows the in-file verification passing while the external root fails; an eunit law shows the head moving with every append, a stale root reported with both digests and a fresh handle seeing the same head; one mutant (root verification ignores the mismatch) killed. Pin ab61df88 supersedes a5b63b75.
- Probes 7 and 8 showed an empty name and a name carrying a NUL byte were stored. `valid_name` (non-empty, at most 512 bytes, no control byte) is now checked before any disk access in `vault_kv_put`, `vault_kv_get`, `vault_kv_versions` and `vault_kv_destroy`, which answer `{error, {invalid_name, Name}}`; a cargo law, an eunit law and a killed mutant pin it. Pin 6db27c1e supersedes 73be69d9.

UOS footer: `nas-1.tail55d152.ts.net:4100` · source presence and a pinned digest grant no admission.
