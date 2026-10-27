# 20261027-1830 — verification_run NIF diagnosis (ECHILD)

#fractal-l0 #fractal-l3 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This note](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1830-verification-run-nif-diagnosis.md) · [Sweep](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1810-harness-tool-sweep.md)

## Observation
`mcp__uos_harness.verification_run` returns `{"ok":false,"output":"Failed to run gleam check: No child processes (os error 10)","warnings":0,"errors":1}`.

## Root cause (source: `apps/cepaf_gleam/native/c3i_nif/src/verification.rs`)
```rust
#[rustler::nif(schedule = "DirtyCpu")]
pub fn verification_run() -> NifResult<String> {
    let gleam_dir = if Path::new("lib/cepaf_gleam/gleam.toml").exists() { "lib/cepaf_gleam" }
        else if Path::new("gleam.toml").exists() { "." }
        else { "/home/an/dev/ver/c3i/lib/cepaf_gleam" };   // ← stale external fallback
    let output = Command::new("gleam").arg("check").current_dir(gleam_dir).output();
    ...
}
```
Two defects:
1. **Wrong cwd fallback** — from the UOS MCP cwd (`/home/an/NAS-setup/uos`, where `apps/cepaf_gleam/gleam.toml` is the real project), none of the first two branches match, so it falls back to the old external `/home/an/dev/ver/c3i/lib/cepaf_gleam`.
2. **`ECHILD`** — `std::process::Command::output()` forks+waits; the BEAM VM's SIGCHLD reaping reclaims the child, so `wait` returns errno 10. This is the classic NIF-subprocess/beam reaping conflict.

## Repair proposal (needs Rust NIF rebuild — do NOT hand-edit the .so)
1. Add a UOS branch: `apps/cepaf_gleam/gleam.toml` → `"apps/cepaf_gleam"`, then absolute `/home/an/NAS-setup/uos/apps/cepaf_gleam` before the c3i fallback.
2. Replace fork/exec `Command::output()` with a BEAM-safe spawn: `posix_spawn` (e.g. `rustix::process::posix_spawn`) or move the `gleam check` invocation to an Erlang `open_port({spawn_executable, ...})` FFI (pattern already used by `clock_guard_ffi.erl`/`uos_jj_ffi.erl`), which the BEAM reaps correctly.

## Governance weight
Rebuild repins `apps/cepaf_gleam/priv/c3i_nif.so` + its `c3i_nif.sha256` (pinned binary identity). Per the release SOP: retain the exact serving binary first, build under the pinned Rust/rustler toolchain, and re-run the canary. Deferred pending operator go-ahead; the read surface is otherwise healthy.

## Residual (post-fix acceptance)
After rebuild: `verification_run` should return `{"ok":true,...}` with `warnings`/`errors` from `gleam check` in `apps/cepaf_gleam`.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Diagnosis only; this note grants no admission.