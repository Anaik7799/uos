# Apps Subsystem (`apps/`)

- **Ownership & Language Authority**: Pure Gleam / OTP.
- **Scope**: Live operational applications, agent swarm orchestration, CEPAF coordinator (`apps/cepaf_gleam`), TUI, and operational API endpoints.
- **Invariants**: All supervision, state machines, lease management, and high-level routing live here. Zero native blocking code.
