# 20261027-1930 — NIF/OTP ABI root cause + test-runner correction

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This note](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-1930-nif-otp-abi-root-cause.md)

## Finding (supersedes the "stale .so" hypothesis)
- The 11 `c3i_nif` "corrupt atom table" failures were **not** a stale `.so`. They were an **OTP/ERTS mismatch**: `gleam test` resolves `erl` to the **system OTP 27** (`/usr/bin/erl`, ERTS 15.2.7.4), while the NIFs and the runtime MCP server run **OTP 29** (`toolchains/nix-profile/bin/erl`, ERTS 17.0.5).
- Correct test invocation: `PATH=/home/an/NAS-setup/uos/toolchains/nix-profile/bin:$PATH gleam test` → `corrupt atom table` occurrences drop to **0**.

## Item 1 actions taken (governed)
1. Retained serving `priv/c3i_nif.so` (`c6b6cd06…`) to `/tmp/nif-retain-20261027/`.
2. Rebuilt `c3i_nif` under pinned `devenv` (rustc 1.95.0, OTP 29 headers, `cargo build --release --offline`), incorporating the `verification.rs` cwd-resolution fix.
3. Re-pinned `priv/c3i_nif.sha256` (`30456630…`) with provenance incl. Cargo.lock sha256.
4. Verified the OTP-29 test VM loads the NIF cleanly.

## Remaining (separate from NIF ABI)
- Under OTP 29, `telegram_verify_service_test` fails/hangs with `gate_build:guardian_artifact_unavailable` — the `tools/validation/*.exe` guardian binaries are absent or hash-mismatched. This is the next test-suite blocker, unrelated to the NIF.

## Item 3 status
- `admission.gleam` `Grant` schema requires: `schema`, `role`, `grant_id`, `session`, `worker`, `host_id`, `boot_id`, `expires_utc_us`, `tasks[]` (each `{plan,task,read_paths,write_paths,source_paths,test_modules,risk_portfolio}`), `review_path`, `review_sha256`.
- `review_sha256` is a **peer signature** — a grant cannot be self-minted. Awaiting live Codex/Agy verdict + operator authorization.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Observation only; grants no admission.