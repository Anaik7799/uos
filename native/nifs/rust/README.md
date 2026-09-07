# Native RUST Bounded Kernels (`native/nifs/rust/`)
- **Authority**: Bounded, deterministic computational kernel.
- **Invariants**: Zero blocking calls; failsafe timeouts; bounded memory envelopes.

## ferriskey_nif (imported 2026-09-07, operator permission)

- **Source**: `native/nifs/rust/ferriskey_nif/` — FerrisKey IAM NIF crate (rustler 0.37 cdylib, crates.io dependencies only), imported byte-for-byte from the C3I evidence tree; every file digest is recorded in `governance/sources/20260907-1330-ferriskey-nif-source-ingestion.json` (snapshot digest `a2eb0cda…`).
- **Build**: `cd native/nifs/rust/ferriskey_nif && cargo build --release` (rustc ≥ 1.95, OTP 27 headers via rustler). `target/` is ignored by the repository.
- **Install**: copy `target/release/libferriskey_nif.so` to `apps/cepaf_gleam/priv/ferriskey_nif.so`; the artifact is a host-provisioned build product matched by the `*.so` ignore rule and is never committed.
- **Pin**: `apps/cepaf_gleam/priv/ferriskey_nif.sha256` holds the expected sha256 with provenance. A rebuild that changes the digest must re-pin with a new provenance line; never overwrite the pin silently.
- **Loader**: `apps/cepaf_gleam/src/ferriskey_nif.erl` (`-on_load`), Gleam bindings `apps/cepaf_gleam/src/cepaf_gleam/auth/ferriskey_nif.gleam`, IAM supervisor `apps/cepaf_gleam/src/cepaf_gleam/iam/`.
- **Rule**: `.claude/rules/20260907-1330-iam-ferriskey-nif-rule.md` (SC-FERRISKEY-NIF-001..010, SC-GCP-IAM-001..020), mirrored to `.gemini`, `.agents`, `.codex`.
- **Formal evidence**: `formal/tla/20260907-1340-ferriskey-iam-c3i-evidence.tla` (C3I TLA+ spec, evidence only; Lean 4 and Quint remain the authorities).
- **Status**: development candidate; Codex R5 sovereign security review required before any admission claim (IAM, tokens, JWKS, GCP STS, SCIM).
