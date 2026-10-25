# RustyVault Vendoring Notes (C3I)

**Vendored**: 2026-04-30 from https://github.com/Tongsuo-Project/RustyVault @ `main` (shallow clone)
**License**: Apache-2.0 (upstream LICENSE retained)
**Maintainer**: C3I (`abhijit.naik@bountytek.com`)
**Method**: vendor-copy (shallow clone, `.git/` removed). Not git-subtree — operator default Q1 was subtree, but vendor-copy is safer here because:
- `[patch.crates-io]` Tongsuo redirect must remain scrubbed permanently
- No risk of accidental upstream pulls re-introducing the patch

## Modifications from upstream

### 1. Removed `[patch.crates-io]` block (Cargo.toml lines 91-93 upstream)

**Upstream had**:
```toml
[patch.crates-io]
openssl     = { git = "https://github.com/Tongsuo-Project/rust-tongsuo.git" }
openssl-sys = { git = "https://github.com/Tongsuo-Project/rust-tongsuo.git" }
```

**This silently redirected the `openssl` crate to Tongsuo's fork**, which adds SM2/SM3/SM4
(Chinese national crypto algorithms) to the OpenSSL build. Our crate name says "openssl"
but the linker pulls Tongsuo binaries.

**Replaced with**: an inline comment block referencing **SC-VAULT-CRYPTO-001** and warning
against re-introducing any patch redirect.

### 2. Source files containing Tongsuo (DOES NOT COMPILE under our feature set)

The following files still exist in `src/` but are **feature-gated behind `crypto_adaptor_tongsuo`**:

```
src/modules/crypto/crypto_adaptors/tongsuo_adaptor.rs    ← #[cfg(feature = "crypto_adaptor_tongsuo")]
src/modules/crypto/mod.rs                                 ← cfg-gated route
src/modules/pki/path_{roles,keys,config_ca}.rs            ← cfg-gated branches
src/modules/pki/util.rs, mod.rs                           ← cfg-gated branches
src/utils/{key,salt,cert,chain}.rs                        ← cfg-gated branches
```

**Why kept**: removing source-level Tongsuo references would require diverging significantly
from upstream and would block clean future syncs. Feature gating is sufficient: under our
`default-features = false, features = ["crypto_adaptor_openssl"]` integration, none of these
files are compiled into the NIF binary.

**Verified at build time** (in Slice B) via:
```bash
cd lib/cepaf_gleam/native/rusty_vault_nif && cargo tree | grep -iE 'tongsuo|sm[234]'
# MUST return empty — this is the SC-VAULT-CRYPTO-001 enforcement gate.
```

## How to use

The integrating NIF (`lib/cepaf_gleam/native/rusty_vault_nif/`) depends on this crate via:

```toml
[dependencies]
rusty_vault = {
  path = "../../../sub-projects/rusty_vault_vendored",
  default-features = false,
  features = ["crypto_adaptor_openssl"]
}

# Workspace-level safety net — secondary defense if any transitive dep tries to patch openssl.
[patch.crates-io]
openssl     = { version = "0.10" }
openssl-sys = { version = "0.9" }
```

## How to update from upstream

1. Pull upstream RustyVault into a temp dir
2. Diff against current vendored tree
3. **Critical**: re-strip `[patch.crates-io]` before merging
4. Re-run `cargo tree | grep -iE 'tongsuo|sm[234]'` audit
5. Re-run NIF integration tests
6. Bump VENDORING_NOTES.md upstream SHA

## Audit history

| Date | Action | Operator | SHA |
|---|---|---|---|
| 2026-04-30 | Initial vendor + scrub | abhijit.naik@bountytek.com | (shallow, no SHA) |
