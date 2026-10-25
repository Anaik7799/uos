---
name: mesh-resurrection
description: Autonomous Fractal RCA and resurrection sequence for the SIL-6 Biomorphic Mesh. Use when containers fail health checks, NIFs fail to load, or substrate drift is detected.
---
# Mesh Resurrection Skill
This skill provides a high-fidelity, autonomous workflow for diagnosing and fixing SIL-6 Biomorphic Mesh failures using Order-1 Fractal RCA.
# Specialized Workflow: Panoptic Ignition
# 1. Fractal RCA (Observe & Orient)
When the mesh is unhealthy, execute a 5-layer audit:
- **L1 (Function)**: Check for shadowed configuration volumes.
- **L2 (Component)**: Verify Zenoh gossip pulse (not just port checks).
- **L3 (Holon)**: Check `smriti.db` integrity (detect 0-byte memory).
- **L4 (Container)**: Detect glibc/musl NIF conflicts caused by host artifact leakage.
- **L5 (System)**: Verify quorum and Tailscale identity plane.
# 2. Substrate Purge (Act)
- **Host Cleanup**: ALWAYS `rm -rf _build deps` on the host to clear glibc contamination.
- **Surgical Scour**: Use `sa-scour` or manual `podman rm -fa` to clear ghost networks.
# 3. State Reification (Act)
- **SMRITI Initialization**: Ensure `smriti.db` is seeded with canonical schema using `sqlite3`.
- **Image Re-Synthesis**: Rebuild `obs` and `app` images if configuration drift is detected.
# 4. Panoptic Boot (Act)
- **Canonical Ignition**: Use `sa-up` binary (MANDATORY: MUST be pre-compiled, independent of dotnet at runtime) for wave-based mesh startup.
- **Quorum Verification**: Confirm 2oo3 consensus via `sa-verify` binary.
# Safety Constraints
- **SC-RES-001**: NEVER skip the host `_build` purge; it is the primary cause of NIF failures.
- **SC-RES-002**: Verification MUST be biological (Zenoh pulse), not just status-based.
# Task & Planning (RUST sa-plan-daemon MANDATE)
- **AOR-RES-PLAN**: ALL tasks related to resurrection MUST be tracked via `sa-plan`, which resolves to the Rust binary `./sub-projects/c3i/target/release/sa-plan-daemon`.
- **Forbidden**: NEVER use `mix todo`, the F# Planning CLI, or manual markdown edits during a resurrection sequence. State MUST be preserved in the authoritative Rust SQLite/DuckDB store via sa-plan-daemon.
- **MCP+Zenoh**: Resurrection actions (ignition, health checks, rule evaluation) are accessible as MCP tools over Zenoh (MoZ protocol) — see `indrajaal/l4/system/mcp/req/**` topics.