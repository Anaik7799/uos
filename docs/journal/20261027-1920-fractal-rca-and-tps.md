# 20261027-1920 — Fractal RCA + TPS of the harness-integration defects

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This RCA](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-1920-fractal-rca-and-tps.md) · [Sweep](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1810-harness-tool-sweep.md)

Status: bounded, evidence-backed RCA across L0/L1/L3/L4/L9 of the defects observed this session. Not an exhaustive whole-system RCA; unobserved subsystems remain UNKNOWN.

## D1 — `preflight_check` rejected integer args (L3 transaction / L4 service)
- Cause: strict `gleam/json` `decode.float` (rejects JSON int) vs `inputSchema` `"number"` (allows int+float). Schema/handler disagreement.
- Fix: lenient `number_decoder` (Poka-Yoke — accepts the full declared type). Jidoka — the validation refusal surfaced the mismatch instead of a silent wrong answer.
- Evidence: canary `approved` with `benefit:1, cost:0`.

## D2 — `verification_run` ECHILD (L4 service)
- Cause: Rust NIF `std::process::Command::output()` fork/wait conflicts with BEAM SIGCHLD reaping (`No child processes`, errno 10) + stale cwd fallback to `/home/an/dev/ver/c3i`.
- Fix: move subprocess to BEAM `open_port` (`run_bounded_cd`; BEAM owns/reaps the child) + cwd→UOS. Poka-Yoke (BEAM-native port), Muda (reuse existing guardian).
- Evidence: source fix compiles; live canary pending server restart.

## D3 — `c3i_nif` "corrupt atom table" — 11 test failures (L0 kernel / L1 atomic)
- Cause: `priv/c3i_nif.so` built 2026-09-06 against an older ERTS; current OTP 29.0.5 (ERTS 17.0.5) rejects the NIF ABI on load. Cascades: 10× `actors_test` (`Undef`) + 1× `agui_cockpit_test` (`ModuleNotFound`).
- Fix (governed): rebuild all Rust NIFs under pinned `devenv` toolchain + re-pin `*.so` + `*.sha256` + canary. Jidoka — failures are loud, not silently passed; Heijunka — rebuild as one bounded slice with binary retention.
- Evidence: full `gleam test` = 619/630, the 11 failures all root in `Error loading module c3i_nif: corrupt atom table`.

## D4 — Rule-mirror drift (L3 transaction)
- Cause: no projection policy; 29 canonical contracts absent from all four vendor `rules/` surfaces; 8 stale short-name shadows.
- Fix: `SC-MIRROR-PROJ-001` (project-everything, preserve shadows, 4-mirror isomorphism gate). Poka-Yoke (mechanical validation gate).

## D5 — UOS harness not connected to Pi (L9 federation)
- Cause: `~/.pi/agent/mcp.json` registered only external `zigvm-harness`/`hermes-ops`, not the UOS Gleam harness.
- Fix: `uos-harness` + `uos-harness-dev` entries; 53-tool surface now connected, Zenoh active.

## Testing-standards mapping (9-modality + 4 gates) — honest
| Modality | State |
|---|---|
| Unit | ✅ 619 passed (full `gleam test`) |
| TDD | ✅ preflight: failing case → fix → green |
| System / BDD / Performance / Scalability / Property / Fuzz / Chaos | ⬜ UNRUN (not executed this session) |
| H≥2.50 · CCM≥90% · D_EA≤10% · ITQS≥0.85 | ⬜ UNRUN (no fresh measurement) |

Full-coverage instrumentation, cross-toolchain suites (OCaml/Hermes, Rust NIFs, Lean 4, Quint, Mojo, Zig) and the remaining seven modalities are a separate governed effort — recorded, not claimed.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this RCA grants no admission.