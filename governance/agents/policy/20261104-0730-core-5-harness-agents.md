# UOS 5-Harness Core Agent Policy (Zero-Muda Token-Optimized Edition)

- **Authoritative Policy & Unified Spec**: Defer to `/home/an/NAS-setup/uos/AGENTS.md` and `governance/agents/policy/20261104-0730-unified-5-harness-agents.md` (Lean 4 functional equivalence proof: `formal/lean/FiveHarnessUnifiedAndCorePolicyEquivalence.lean`).
- **On-Demand Old File Recall**: All pre-optimization user/project files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) are retained in `var/backups/zero-muda-20261101/`, `var/backups/agents-md-vault-20261104/`, and `governance/sources/20261001-1118-symbiosis-history/`. Inspect via `read` on need basis.
- **Pure Lean 4 Infrastructure & Digital Twins**: Use Lean 4 (`4.29.0`) for all base scripting, environment, SOPs, SDLC/SRE, and operations orchestration (`formal/lean/*.lean`); Gleam/OTP 29, Mojo 0.26.2, OCaml 5.5.0, Zig 0.16.0, and Rust maintain their domain roles.
- **5-Harness Symbiosis & `uos-harness` MCP**: AGY (`Caste01`), Pi (`Caste02`), Codex (`Caste03`), Claude (`Caste04`), DeepSeek DSH (`Caste05`) operate through `uos-harness` (`/home/an/NAS-setup/uos/tools/uos-mcp-stdio`, 104 routes) with 28 canonical skills (`.agents/skills`), 14 superpowers, and 2 plugins loaded on demand.
- **Core Mandates (`L0..L9`)**:
  1. **DMC/TCM & Two-Key**: `Trust = Fresh Empirical Behavior ∧ Formal Spec`; fail-closed interception; NVMe `25503L801736` locked; clock drift `< 2.0s`.
  2. **Provenance & VCS**: Standalone Jujutsu (`.jj/`) only (`0` git mutations). Admitted ceiling `EV-93` (`SC-PROVENANCE-001`); `EV-94..109` are `NOT_ADMITTED`.
  3. **Sa-Plan, KM-Triad & POODAVR**: `sa-plan` is sole execution authority (`SC-SA-PLAN-001`). Bind `uos://km/triad`, execute 7-stage `POODAVR`, prefix docs with `YYYYMMDD-HHSS-`, include ASCII+Mermaid diagrams, 6-domain checklist (`SC-CHECKLIST-001`), and 13-section `SC-JOURNAL-v3`.
  4. **Secrets & Zero-Muda**: Secrets in `/etc/pi-vault/*.cred` only; `0` Bevy/Graphite/Graphene NIF.
