# Unified Operational System (UOS) 5-Harness Canonical Agent Policy (Full Unified Edition)

- **Document ID**: `UOS-UNIFIED-5-HARNESS-AGENTS-MD-20261104`
- **Timestamp**: `2026-11-04T07:30:00Z`
- **Fractal Coverage**: `#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#km-triad` `#zk-adr` `#zero-muda`
- **Formal Lean 4 Equivalence Proof**: [`formal/lean/FiveHarnessUnifiedAndCorePolicyEquivalence.lean`](http://nas-1.tail55d152.ts.net:4100/files/formal/lean/FiveHarnessUnifiedAndCorePolicyEquivalence.lean)
- **Core Zero-Muda Edition**: [`governance/agents/policy/20261104-0730-core-5-harness-agents.md`](http://nas-1.tail55d152.ts.net:4100/files/governance/agents/policy/20261104-0730-core-5-harness-agents.md)
- **Backup Vault (Old & Active Retained)**: [`var/backups/agents-md-vault-20261104/`](http://nas-1.tail55d152.ts.net:4100/files/var/backups/agents-md-vault-20261104)
- **Live Cockpit**: [`http://nas-1.tail55d152.ts.net:4100/`](http://nas-1.tail55d152.ts.net:4100/)

## 1. Pure Lean 4 Infrastructure & Digital Twin Mandate

All UOS infrastructure code for base scripting, environment provisioning, SOP enforcement, SDLC/SRE environment management, and operations orchestration is authored, modeled, and verified in **Lean 4** (`4.29.0`) with Digital Lean Twins (`formal/lean/*.lean` and `var/benchmarks/20261103-1630-fractal-workload-suite/scripts/*.lean`), replacing ad-hoc Python, Bash, and `sed` scripts. Domain languages retain their strict architectural boundaries:
- **Lean 4 (`4.29.0`)**: Mathematical authority, Digital Twins of every subsystem, and pure `IO` SDLC/SRE infrastructure orchestration.
- **Gleam (`1.15.4`) / OTP 29 (`ERTS 17.0.5`)**: Supervision trees (`uos_sup.gleam`), 104-route `uos-harness` MCP gateway, 40-actor FPP mesh, POODAVR controllers, and Lustre/Wisp Cockpit.
- **Mojo (`0.26.2`) / Modular MAX**: AVX-512 SIMD Bionic Token Twin fastpath (`7.21 µs` for `315 KB`) and isolated AI inference.
- **OCaml (`5.5.0`) / Hermes**: Gospel contracts, Cryptokit SHA-256 zero-trust interception, Rete-UL forward-chaining, and differential oracles.
- **Zig (`0.16.0`) & Rust**: Deterministic ZigVM VFS kernel and hardware NVMe safety interlocks (`HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"`).

## 2. 5-Agent Symbiosis, Version Envelope & Retained Old/New User-Level Files (`L0..L9`)

| Harness | Binary Version | Default Model | Hive Caste | Active User/Project File | Retained Old File (On-Demand Recall) |
|---|---|---|---|---|---|
| **Pi (`pi`)** | `1.4.0` | `pi-argon` + `pi+deepseek`/`pi+gemini` | `Caste02ArchitectCoord` | `/home/an/.pi/agent/AGENTS.md` (`1,945 B`) | `var/backups/zero-muda-20261101/pi_agent_AGENTS.md.bak-20261102` (`15,861 B`) & `nas_setup_AGENTS.md.bak-20261102` (`12,553 B`) |
| **Claude (`claude`)** | `2.1.317` | `claude-opus-5` | `Caste04ScholarKnowledge` | `/home/an/NAS-setup/uos/CLAUDE.md` (`8,703 B`, compact Caste04 profile since `20261105-1007`; depth pulled from `governance/agents/20261001-1118-skills/uos-caste04-claude-harness-profile/SKILL.md`) | `governance/sources/20261001-1118-symbiosis-history/home-claude-CLAUDE.md` (`299 B`) & `var/backups/agents-md-vault-20261104/uos_project_CLAUDE.md.bak` & `var/core-evo/harnesses/claude/CLAUDE.md.orig` (`34,939 B`, the pre-compaction symlink target) |
| **Codex (`codex`)** | `0.123.0` | `codex-gpt-6.1-terra` | `Caste03SentinelVerifier` | `/home/an/.codex/rules/default.rules` (`12,666 B`) | `governance/sources/20261001-1118-symbiosis-history/home-codex-AGENTS.md` (`299 B`) & `var/backups/agents-md-vault-20261104/codex_user_default.rules.bak` |
| **AGY (`agy`/`gemini`)** | `0.36.0` | `agy-gemini-4-argon` | `Caste01SovereignGovernor` | `/home/an/NAS-setup/uos/GEMINI.md` (`5,312 B`) | `governance/sources/20261001-1118-symbiosis-history/GEMINI.md` (`7,828 B`) & `var/backups/agents-md-vault-20261104/uos_project_GEMINI.md.bak` |
| **DeepSeek (`dsh`)** | `0.4.2` | `deepseek-v3.2-chat` | `Caste05WorkerSwarm` | `/home/an/.agents/AGENTS.md` (`7,609 B`) + `var/core-evo/deepseek-home/AGENTS.md` | `var/backups/agents-md-vault-20261104/deepseek_dsh_user_AGENTS.md.old-7609B.bak` |

## 3. Full Capability Envelope & 10-Layer Fractal Invariants (`L0..L9`)

- **38 Policy Directive Families** (`governance/agents/policy/superset.toml`) & **44 Policy Identities** (`governance/agents/policy/mapping.toml`).
- **28 Canonical `uos-core-evo` Skills** (`.agents/skills`), **14 Superpowers** (`governance/capability-inventory/superpowers.toml`), **2 Verified Plugins** (`governance/capability-inventory/plugins.toml`).
- **104 `uos-harness` MCP Routes** (`93 tools + 11 resources`) pinned across all 16 configuration targets to capsule `/home/an/NAS-setup/uos/var/releases/ecology/20261105-1956-630752df0813ce1938ae3e821f453a138900a05013c7f220061cf8b684aa30f2` (`payload_sha256: b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6537`).
- **12 Core Mandates**: (1) DMC Two-Key Verification, (2) Zero-Muda Purity, (3) Standalone Jujutsu (`.jj/`) only, (4) `EV-93` Admitted Ceiling (`EV-94..109` `NOT_ADMITTED`), (5) `sa-plan` Exclusive Authority & Jidoka Andon, (6) `uos-harness` MCP Boundary, (7) 7-Stage POODAVR Loop, (8) `#km-triad` Brain-Memory Binding, (9) 6-Domain 18-Check Checklist & Tailscale FQDN, (10) `SC-JOURNAL-v3` 13-Section Ledger, (11) NVMe `25503L801736` Lock, (12) Immutable Old-Artifact Retention & On-Demand Recall.
