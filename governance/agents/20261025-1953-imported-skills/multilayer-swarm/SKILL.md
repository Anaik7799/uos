---
name: multilayer-swarm
description: Full parallelization Multilayer Swarm mode for Panoptic Ignition. This is the default mode for running ALL commands and orchestrations, ensuring 15-container mesh homeostasis and maximum resource saturation.
---
# Multilayer Swarm Parallelization Skill
This skill enforces the Multilayer Swarm paradigm, ensuring that all system execution, planning, and testing operate in FULL PARALLELIZATION mode.
# Core Mandates
1. **Full Parallelization**: All compilation, tests, and orchestrations MUST utilize maximum available hardware concurrency.
- Example: `ELIXIR_ERL_OPTIONS="+S 16:16 +SDio 16"` and `mix compile --jobs 16`.
2. **Panoptic Ignition**: The 15-container swarm MUST be bootstrapped using the wave-based DAG via the Rust ignition daemon (`./sub-projects/c3i/target/release/sa-plan-daemon` / `native/ignition_daemon/`). The F# cepaf engine is LEGACY and REDUNDANT for this function.
3. **Supervisor Agent**: A supervisor agent MUST monitor the swarm's homeostasis via MCP tools over Zenoh (MoZ protocol) and Zenoh telemetry (`indrajaal/ignition/progress`). All Rust operational components are accessible as MCP tools via `indrajaal/l4/system/mcp/req/**`.
4. **Rust sa-plan-daemon Planning**: ALL task planning and status tracking MUST use `sa-plan` (Rust binary: `./sub-projects/c3i/target/release/sa-plan-daemon`). The F# Planning CLI is DEPRECATED. Elixir `mix todo` is strictly FORBIDDEN.
# OODA Loop Integration
- **Observe**: Query Swarm Health via MCP and Zenoh (`indrajaal/health/*`).
- **Orient**: Analyze if the 15 nodes are in Homeostasis. If degraded, identify the fractal layer.
- **Decide**: Choose the fastest parallel path to state reification.
- **Act**: Execute `sa-up` or perform Genetic Re-Synthesis if config drift is detected.
# Execution Directives
- **Autonomous Mode**: Continue in FULL AUTONOMOUS MODE until Goal completion.
- **Permissions Mode**: Continue in FULL PERMISSIONS MODE.
- **Task Hierarchy**: ALWAYS use hierarchical numbering for tasks in `sa-plan`. Tasks MUST NEVER be deleted and overwritten, only transitioned to `Completed`, `Blocked`, or `Failed`.