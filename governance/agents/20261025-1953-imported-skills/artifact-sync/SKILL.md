---
name: artifact-sync
description: Daily synchronization of .gemini and .claude artifacts to OpenCode. Uses Rust binary for automated sync. Maintains rules, agents, skills, and AGENTS.md with fractal layer mappings. Runs daily without prompting.
---
# Artifact Sync Skill
This skill performs daily synchronization of all Gemini and Claude artifacts to OpenCode using the Rust binary, ensuring OpenCode has access to the complete system context without manual prompting.
# Core Mandates
1.  **Daily Automation**: Run automatically at session start to sync all artifacts
2.  **Rust Binary**: Use `~/.config/opencode/bin/artifact-sync` for reliable sync
3.  **Fractal Layer Mapping**: Maintain L0-L7 x Artifacts mapping in AGENTS.md
4.  **Gleam/Rust Compliance**: Ensure all artifacts reference C3I development environment
5.  **Comprehensive Coverage**: Sync rules (42), agents (27), skills (10-11) = 80+ total
# Binary Location
```
~/.config/opencode/bin/artifact-sync/target/release/artifact-sync
```
# Commands
# Sync All Artifacts
```bash
~/.config/opencode/bin/artifact-sync/target/release/artifact-sync --action sync --verbose
```
# Verify Artifacts
```bash
~/.config/opencode/bin/artifact-sync/target/release/artifact-sync --action verify
```
# Show Status
```bash
~/.config/opencode/bin/artifact-sync/target/release/artifact-sync --action status
```
# Dry Run (Preview)
```bash
~/.config/opencode/bin/artifact-sync/target/release/artifact-sync --action sync --dry-run
```
# Source Locations
| Source | Location | Count |
|--------|----------|-------|
| `.gemini/GEMINI.md` | `~/.gemini/` | 1 |
| Skills | `dev/ver/c3i/.gemini/skills/` | 10 |
| Rules | `dev/ver/c3i/.claude/rules/` | 42 |
| Agents | `dev/ver/c3i/.claude/agents/` | 27 |
# Target Locations (OpenCode Global)
| Target | Location |
|--------|----------|
| AGENTS.md | `~/.config/opencode/AGENTS.md` |
| Agents | `~/.config/opencode/agents/` |
| Rules | `~/.config/opencode/rules/` |
| Skills | `~/.config/opencode/skills/` |
# Automated Execution
This skill runs automatically at OpenCode session start. The agent `daily-artifact-sync` invokes this skill to perform the sync.
```bash
# From daily-artifact-sync agent
skill({ name: "artifact-sync" })
# Run the binary
~/.config/opencode/bin/artifact-sync/target/release/artifact-sync --action sync
```
# Shell Script Wrapper
For convenience, use the wrapper script:
```bash
~/.config/opencode/bin/sync-artifacts.sh
```
# Fractal Layer Mapping
The binary maintains this mapping in AGENTS.md:
```
L0 CONSTITUTIONAL → constitutional-verifier, safety-validator, sil6-validator
L1 ATOMIC/DEBUG → code-debugger, observability-analyzer, cepaf-zenoh-expert
L2 COMPONENT → build-supervisor, design-supervisor, gleam-expert
L3 TRANSACTION → holon-analyzer, robustness-analyzer, cepaf-planning-expert
L4 SYSTEM → deploy-supervisor, cpu-governor-supervisor, cepaf-podman-expert
L5 COGNITIVE → fmea-analyzer, cepaf-bridge-analyzer, lustre-gleam-ui-expert
L6 ECOSYSTEM → zenoh-mesh-analyzer, swarm-verification-expert
L7 FEDERATION → master-supervisor, fractal-architect, multilayer-swarm
```
# Gleam/Rust Compliance
The binary ensures:
- Build Order: Rust → Gleam → Elixir → F#
- SC-GLM-* constraints (Gleam compilation)
- AOR-GLM-* rules (Gleam development)
- FRACTAL LAYERS x ARTIFACTS mapping
# Verification Checklist
After sync, verify:
- [ ] Agents: 27+ in `~/.config/opencode/agents/`
- [ ] Rules: 42 in `~/.config/opencode/rules/`
- [ ] Skills: 10+ in `~/.config/opencode/skills/`
- [ ] AGENTS.md: 250+ lines with FRACTAL LAYERS section
- [ ] Gleam compliance: SC-GLM-* and AOR-GLM-* present
# Troubleshooting
- **Binary not found**: Build with `cargo build --release` in `~/.config/opencode/bin/artifact-sync/`
- **Missing artifacts**: Run sync again
- **Agent naming issues**: Binary handles .md removal
- **Fractal mapping stale**: Sync regenerates AGENTS.md
# Related Skills
- `gleam-expert` - Gleam development
- `mesh-resurrection` - Fractal RCA for sync failures
- `swarm-verification-expert` - Verify sync completeness