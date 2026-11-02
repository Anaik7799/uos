# UOS Anticipatory Epistemic Journal — DeepSeek Harness (`dsh` `0.2.1-rc.5`) Full Zsh, UOS & Multi-Project Integration (`L0`–`L9`)

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zero-muda #zk-adr #tailscale-web #checklist-nav

- **Document Path (Workspace)**: [`docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md`](file:///home/an/NAS-setup/docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md)
- **Document Path (UOS Mirror)**: [`uos/docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md`](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md)
- **Conversation ID**: `8bf173b4-3b80-43d2-a6a0-af2adf590ece`
- **Timestamp**: `20261102-2034` (`2026-11-02T20:34:00+01:00`)
- **Knowledge Graph Transclusions**: `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`, `[[zk:20260905-1801-moc-uos-unified-master]]`
- **Tailscale Cockpit Base FQDN**: [http://nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100) (`100.87.7.78`) | Peer Runtime: [http://vm-1.tail55d152.ts.net:8088](http://vm-1.tail55d152.ts.net:8088) (`100.78.98.18`)
- **Admitted EV Ceiling**: `EV-93` ([`SC-PROVENANCE-001`](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md); zero new EV numbers minted)
- **Hardware Safety Interlock**: Host OS NVMe serial `[REDACTED_SYSTEM_OS_SERIAL]` locked against allocation; 0 Bevy, 0 Graphite, 0 foreign Graphene NIFs across all manifests and runtime surfaces.

---

## 1. Scope & Trigger

### 1.1 Verbatim Prompt History & Trigger Sequence (Zero-Loss Ledger)

#### Pre-Session Operator Shell Commands (`/home/an/.zsh_history` lines `10051`–`10054`)
Immediately before launching Antigravity (`agy`), the operator executed the following sequence in Zsh:
```zsh
: 1793646438:0;npx @deepseek-ai/dsh web
: 1793646522:0;dsh --no-open
: 1793646529:0;dsh
: 1793646543:0;agy
```
- `npx @deepseek-ai/dsh web` downloaded `@deepseek-ai/dsh@0.2.1-rc.5` into volatile npx cache (`/home/an/.npm/_npx/1e7f6d9597241db0`) and initialized `/home/an/.dsh` with an empty workspace store (`workspaceIds: []`).
- Both `dsh --no-open` and `dsh` failed in Zsh with `zsh: command not found: dsh`.

#### Verbatim User Prompts in Conversation `8bf173b4-3b80-43d2-a6a0-af2adf590ece`
1. **Prompt 1 (`2026-11-02T20:09:20+01:00`)**:
   > `make sure deepsekk harness is fully inetgrated with zsh and  current projects`
2. **Prompt 2 (`2026-11-02T20:20:30+01:00`)**:
   > `make sure deepsekk harness is fully inetgrated with zsh and  uos`
3. **Prompt 3 (`2026-11-02T20:33:47+01:00`)**:
   > `create journal with prompt history and work doen. no loss.`

### 1.2 Scope Definition
1. Install `@deepseek-ai/dsh` (`0.2.1-rc.5`) and `pnpm` (`10.33.0`) permanently in `~/.local` outside the volatile `~/.npm/_npx` cache.
2. Provide a resilient launcher `/home/an/.local/bin/dsh` (and symlink `/home/an/.local/bin/deepseek-harness`) that pins `/usr/bin/node` (v22.22.1) to prevent Nix Node 24 native addon crashes, loads `~/.config/shell/env.sh`, exports `DSH_HOME` and `DSH_AGENTS_HOME`, and defaults bare `dsh` and web-flag invocations (`dsh --no-open`, `dsh --port ...`) to the `web` profile.
3. Integrate `dsh` with Zsh (`~/.zshenv`, `~/.zshrc`, `~/.zsh/completions/_dsh`), including full tab-completion, `[dsh]` session prompt indicator, and project/Tailnet launcher aliases and functions (`dsh-web`, `dsh-tailnet`, `dsh-uos`, `dsh-c3i`, `dsh-bionic`, `dsh-zigvm`, `dsh-ask`, `dsh-uos-ask`).
4. Integrate DeepSeek Harness with `uos` (`/home/an/NAS-setup/uos`) and all current sibling projects (`NAS-setup`, `c3i`, `harness-bionic`, `zigvm`, `k8s-lab`, `c3i-vm1`, `harness`) via:
   - `~/.dsh/storages/workspace.json` (`unit: { name: "workspace", version: 2 }`)
   - `~/.dsh/cordis.patch.yml` (global overlay mounting `mcp-uos-gleam` over `/home/an/NAS-setup/uos/tools/uos-mcp-stdio`, `skill-filesystem-uos`, and `.jj` root marker discovery)
   - `~/.dsh/profiles/web/cordis.patch.yml` (interactive Zsh `/usr/bin/zsh -i` terminal controller, Tailscale trusted hosts, SQLite session search, and preset `.jj` + `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`/`CODEX.md` discovery)
   - `~/.dsh/AGENTS.md` (and `~/.agents/AGENTS.md` symlink), `/home/an/NAS-setup/AGENTS.md` symlink repair, and 91 UOS/workspace skill symlinks in `~/.dsh/skills` and `~/.agents/skills`.

---

## 2. Pre-State Assessment

1. **CLI & Binary State**:
   - `which dsh` and `which deepseek-harness` returned exit code `1` (not on `$PATH`).
   - `@deepseek-ai/dsh@0.2.1-rc.5` existed only inside `/home/an/.npm/_npx/1e7f6d9597241db0/node_modules/@deepseek-ai/dsh`.
   - `which pnpm` returned exit code `1` (`pnpm` not installed on `$PATH`, breaking `dsh plugin`).
   - Two Node.js binaries existed on the host:
     - `/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node` (`v24.19.0`), which crashed `dsh` at boot with `Error: dsh: host preparation failed: node-addon-require-builtin unsupported: Unsupported/no-getter (x64 sysv getter is not a recognized this->field accessor)`.
     - `/usr/bin/node` (`v22.22.1`), which passed `node-addon-require-builtin` native introspection cleanly.
2. **DeepSeek Harness Configuration State (`/home/an/.dsh`)**:
   - `/home/an/.dsh/profiles/web/cordis.patch.yml` contained only `{}\n` (2 bytes).
   - `/home/an/.dsh/cordis.patch.yml` did not exist.
   - `/home/an/.dsh/storages/workspace.json` had zero workspaces registered:
     ```json
     {
       "unit": { "name": "workspace", "version": 2 },
       "global": {
         "initialized": true,
         "workspaceIds": [],
         "archivedSessionIds": [],
         "pinnedSessionIds": []
       },
       "tables": { "workspaces": {} }
     }
     ```
   - `/home/an/.dsh/AGENTS.md`, `/home/an/.agents/AGENTS.md`, and `/home/an/.dsh/skills` did not exist; `/home/an/.agents/skills` was empty (`0` entries).
   - `/home/an/NAS-setup/CLAUDE.md` was a dangling symlink pointing to `AGENTS.md` (which had been moved to `/home/an/NAS-setup/.agents/AGENTS.md`).
3. **Zsh Configuration State**:
   - `/home/an/.zshenv` contained only `. "$HOME/.cargo/env"`.
   - `/home/an/.zshrc` had no `~/.zsh/completions` in `fpath`, no `DSH_HOME` / `DSH_AGENTS_HOME` exports, and no `dsh` aliases or helper functions.
4. **UOS Monorepo State (`/home/an/NAS-setup/uos`)**:
   - Standalone Jujutsu (`.jj/`, no `.git`), which caused DeepSeek Harness's default `agent-instructions` (`projectRootMarkers: ['.git']`) to miss project root boundaries when running inside UOS subdirectories.
   - Canonical MCP server `/home/an/NAS-setup/uos/tools/uos-mcp-stdio` (`uos-mcp-unified-gateway` `1.0.0`) was not mounted in `~/.dsh`.

---

## 3. Execution Detail

### 3.1 Phase 1 — DeepSeek Harness Source & Architecture Forensics
We inspected the extracted DeepSeek Harness (`0.2.1-rc.5`) source tree at `/home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/`:
- **CLI & Profile Boot**:
  - [`apps/cli/src/args.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/apps/cli/src/args.ts): Verified that `parseDshArgs` requires a profile name (`web`, `headless`, `sdk`, `sdk-minimal`, `acp`) or `--profile <name>`. Bare `dsh` or `dsh --no-open` fails with `error: --profile <name> is required`.
  - [`apps/cli/src/bin.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/apps/cli/src/bin.ts) & [`apps/cli/src/profile-boot.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/apps/cli/src/profile-boot.ts): Verified the exact patch composition stack order:
    1. Bundle layers in `dsh.profile.bundles` order (`@deepseek-ai/dsh-base`, then surface bundle such as `@deepseek-ai/dsh-web-app` + its `presets/*.patch.yml`).
    2. Profile user layer (`$DSH_HOME/profiles/<name>/cordis.patch.yml`).
    3. Home-level user layer (`$DSH_HOME/cordis.patch.yml` — machine-local preferences applied across all profiles).
    4. `--patch` CLI overlays.
- **Scoped Registry Architecture**:
  - [`docs/subsystems/scope.md`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/docs/subsystems/scope.md) & [`packages/bundle/web-app/cordis.patch.yml`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/packages/bundle/web-app/cordis.patch.yml): Confirmed that `ctx.tools` and `ctx.skills` use `ScopedLayers<L>`, where Host-level registrations populate the global layer and merge automatically into every Agent preset scope (`standard`, `ptc`, `minimal`, `cordis`) without spawning duplicate MCP child processes per preset.
- **Subsystem Schemas**:
  - [`packages/api/terminal-controller/src/index.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/packages/api/terminal-controller/src/index.ts): Verified `Config` schema for `terminal-controller` (`shell: { path, name, args }`, `shellCandidates`).
  - [`packages/context/agent-instructions/src/config.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/packages/context/agent-instructions/src/config.ts) & [`files.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/packages/context/agent-instructions/src/files.ts): Verified `projectRootMarkers` (`['.jj', '.git']`), `instructionFileCandidates` (`['AGENTS.md', 'CLAUDE.md', 'GEMINI.md', 'CODEX.md']`), `maxBytes` (`131072`), and user-global roots (`~/.dsh/AGENTS.md` and `~/.agents/AGENTS.md`).
  - [`packages/skill/skill-filesystem/src/index.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/packages/skill/skill-filesystem/src/index.ts): Verified `providerName`, `includeDefaultRoots`, `customSkillDirs`, and rank order (`PROJECT_DSH_RANK = 100`, `PROJECT_AGENTS_RANK = 200`, `CUSTOM_RANK = 300`, `USER_DSH_RANK = 400`, `USER_AGENTS_RANK = 500`).
  - [`packages/mcp/mcp-client/src/index.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/packages/mcp/mcp-client/src/index.ts): Verified `StdioConfig` (`transport: 'stdio'`, `serverName`, `command`, `args`, `env`, `cwd`, `toolCallTimeoutMs`, `failOnStartupError`).
  - [`packages/workspace/workspace/src/spec.ts`](file:///home/an/NAS-setup/20261102-0734-uos-context-evidence/extracted/deepseek-harness/packages/workspace/workspace/src/spec.ts) & [`@deepseek-ai/dsh-storage-json`](file:///home/an/.local/share/dsh-cli/node_modules/@deepseek-ai/dsh-storage-json/lib/index.js): Verified single-unit JSON envelope `{ "unit": { "name": "workspace", "version": 2 }, "global": ..., "tables": { "workspaces": ... } }`.

### 3.2 Phase 2 — Permanent CLI Installation (`dsh`, `deepseek-harness`, `pnpm`)
1. Copied `/home/an/.npm/_npx/1e7f6d9597241db0` to `/home/an/.local/share/dsh-cli` (`309` `@deepseek-ai/*` packages + dependencies).
2. Enabled `pnpm` in `/home/an/.local/bin/pnpm` via `/usr/bin/corepack enable --install-directory /home/an/.local/bin pnpm` and activated `pnpm@10.33.0` via `/usr/bin/corepack prepare pnpm@10.33.0 --activate` (matching DeepSeek Harness's `"packageManager": "pnpm@10.33.0"`).
3. Created `/home/an/.local/bin/dsh` (and symlink `/home/an/.local/bin/deepseek-harness -> /home/an/.local/bin/dsh`):
   ```bash
   #!/usr/bin/env bash
   # DeepSeek Harness (dsh) launcher wrapper
   # Ensures Node 22 ABI compatibility (node-addon-require-builtin),
   # loads shell API keys, and defaults bare `dsh` / `dsh --no-open` to the `web` profile.

   set -euo pipefail

   export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
   export DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
   export DSH_AGENTS_HOME="${DSH_AGENTS_HOME:-$HOME/.agents}"

   if [[ -z "${OPENROUTER_API_KEY:-}" || -z "${GEMINI_API_KEY:-}" ]] && [[ -f "$HOME/.config/shell/env.sh" ]]; then
     # shellcheck disable=SC1091
     source "$HOME/.config/shell/env.sh"
   fi

   DSH_NODE="/usr/bin/node"
   if [[ ! -x "$DSH_NODE" ]]; then
     DSH_NODE="$(command -v node)"
   fi

   DSH_BIN="$HOME/.local/share/dsh-cli/node_modules/.bin/dsh"
   if [[ ! -f "$DSH_BIN" ]]; then
     echo "dsh: binary not found at $DSH_BIN" >&2
     exit 1
   fi

   if [[ $# -eq 0 ]]; then
     exec "$DSH_NODE" "$DSH_BIN" web
   fi

   has_profile=0
   for arg in "$@"; do
     case "$arg" in
       --profile|--profile=*|web|headless|sdk|sdk-minimal|acp|plugin|-h|--help|-V|--version|--dump-config|--dump-default-config)
         has_profile=1
         break
         ;;
     esac
   done

   if [[ $has_profile -eq 0 ]]; then
     case "$1" in
       --no-open|--port|--port=*|--host|--host=*|--public-url|--public-url=*|--trusted-host|--trusted-host=*|--tls-cert|--tls-cert=*|--tls-key|--tls-key=*)
         exec "$DSH_NODE" "$DSH_BIN" web "$@"
         ;;
     esac
   fi

   exec "$DSH_NODE" "$DSH_BIN" "$@"
   ```

### 3.3 Phase 3 — `AGENTS.md` Hierarchy & 91-Skill Catalog Linking
1. Repaired `/home/an/NAS-setup/CLAUDE.md` by creating `/home/an/NAS-setup/AGENTS.md -> .agents/AGENTS.md`.
2. Authored `/home/an/.dsh/AGENTS.md` (and symlinked `/home/an/.agents/AGENTS.md -> /home/an/.dsh/AGENTS.md`) documenting UOS canonical workspace `/home/an/NAS-setup/uos`, standalone Jujutsu (`.jj/`) rules, `sa-plan` exclusivity (`SC-JIDOKA-001`, `SC-SA-PLAN-001`), mandatory timestamp prefix (`SC-TIME`), connected workspaces, and `mcp__uos-gleam__*` tools.
3. Validated all `91` unique skill directories across `/home/an/NAS-setup/uos/.agents/skills`, `/home/an/NAS-setup/.agents/skills`, and `/home/an/.claude/skills` (confirming valid kebab-case directory names and YAML frontmatter `name` + `description`) and created `182` symlinks (`91` in `/home/an/.dsh/skills` and `91` in `/home/an/.agents/skills`).

### 3.4 Phase 4 — Multi-Project Workspace Registry (`~/.dsh/storages/workspace.json`)
Populated `/home/an/.dsh/storages/workspace.json` with 8 canonical, realpath-verified workspaces (`uos` first):

| Order | UUID | Title | Canonical Path (`realpath`) | Role |
| :---: | :--- | :--- | :--- | :--- |
| 1 | `a1b2c3d4-0001-4000-8000-000000000001` | `uos` | `/home/an/NAS-setup/uos` | Canonical UOS Standalone Jujutsu Monorepo |
| 2 | `a1b2c3d4-0002-4000-8000-000000000002` | `NAS-setup` | `/home/an/NAS-setup` | Host Orchestration & Multi-Workspace Root |
| 3 | `a1b2c3d4-0003-4000-8000-000000000003` | `c3i` | `/home/an/NAS-setup/c3i` | C3I Gleam/Lustre/Wisp/TUI Cockpit |
| 4 | `a1b2c3d4-0004-4000-8000-000000000004` | `harness-bionic` | `/home/an/NAS-setup/harness-bionic` | Bionic Harness Workspace |
| 5 | `a1b2c3d4-0005-4000-8000-000000000005` | `zigvm` | `/home/an/dev/ver/zigvm` | ZigVM Deterministic Runtime (Read-Only Evidence) |
| 6 | `a1b2c3d4-0006-4000-8000-000000000006` | `k8s-lab` | `/home/an/NAS-setup/k8s-lab` | NAS-1 Kubernetes & Rook-Ceph Storage Controller |
| 7 | `a1b2c3d4-0007-4000-8000-000000000007` | `c3i-vm1` | `/home/an/dev/ver/c3i` | VM-1 C3I Source Authority (Read-Only Evidence) |
| 8 | `a1b2c3d4-0008-4000-8000-000000000008` | `harness` | `/home/an/dev/ver/harness` | VM-1 Harness Source Authority |

### 3.5 Phase 5 — Cordis Profile Overlays (`~/.dsh/cordis.patch.yml` & `~/.dsh/profiles/web/cordis.patch.yml`)
1. **Global User Layer (`/home/an/.dsh/cordis.patch.yml`)**:
   - Configured base `agent-instructions` with `projectRootMarkers: ['.jj', '.git']`, `instructionFileCandidates: ['AGENTS.md', 'CLAUDE.md', 'GEMINI.md', 'CODEX.md']`, `maxBytes: 131072`.
   - Inserted Host-level `mcp-uos-gleam` (`@deepseek-ai/dsh-mcp-client`) spawning `/home/an/NAS-setup/uos/tools/uos-mcp-stdio` (`cwd: /home/an/NAS-setup/uos`, `failOnStartupError: false`, `UOS_ROOT`, `UOS_COCKPIT_BASE_URL`, `UOS_PEER_BASE_URL`, `UOS_SA_PLAN_DB`).
   - Inserted Host-level `skill-filesystem-uos` (`@deepseek-ai/dsh-skill-filesystem`, `providerName: uos-skills`, `customSkillDirs: ['/home/an/NAS-setup/uos/.agents/skills', '/home/an/NAS-setup/.agents/skills']`).
2. **Web Profile Layer (`/home/an/.dsh/profiles/web/cordis.patch.yml`)**:
   - Configured `terminal-controller` to launch `/usr/bin/zsh -i` (`shellCandidates: ['zsh', 'bash', 'fish', 'pwsh', 'powershell', 'cmd']`).
   - Configured `session-query-sqlite` with `path: ':memory:'` and `openAt: first-search`.
   - Configured `connection` `trustedHosts` with `['nas-1.tail55d152.ts.net', '100.87.7.78', 'vm-1.tail55d152.ts.net', '100.78.98.18', ...ctx.webStartup.trustedHosts]`.
   - Updated `preset-standard`, `preset-ptc`, and `preset-cordis` so their scoped `agent-instructions` plugins include `projectRootMarkers: ['.jj', '.git']`, `instructionFileCandidates: ['AGENTS.md', 'CLAUDE.md', 'GEMINI.md', 'CODEX.md']`, `maxBytes: 131072`.

### 3.6 Phase 6 — Zsh Shell & Completion Integration (`~/.zshenv`, `~/.zshrc`, `~/.zsh/completions/_dsh`)
1. Authored `/home/an/.zsh/completions/_dsh` (`#compdef dsh deepseek-harness`) supporting dynamic custom profile discovery under `$DSH_HOME/profiles` and full flag completion.
2. Updated `/home/an/.zshenv` so all Zsh invocations (interactive and non-interactive) prepend `~/.local/bin` and `~/.nix-profile/bin` to `PATH`, export `DSH_HOME` and `DSH_AGENTS_HOME`, and source `~/.config/shell/env.sh`.
3. Updated `/home/an/.zshrc` to prepend `~/.zsh/completions` to `fpath` before `compinit`, prepend `[dsh]` to `PROMPT` when `$DSH_SESSION_ID` or `$DSH_WEB_URL` is set, and define aliases/functions (`dsh-web`, `dsh-tailnet`, `dsh-acp`, `dsh-sdk`, `dsh-uos`, `dsh-c3i`, `dsh-bionic`, `dsh-zigvm`, `dsh-ask`, `dsh-uos-ask`).

### 3.7 Dual-Source Fractal Architecture Diagram (`SC-DIAGRAM-001`)

```text
[Zsh Login Interactive Shell] --> [DSH Launcher Wrapper dsh]
[DSH Launcher Wrapper dsh] --> [Node 22 Runtime and Cordis Loader]
[Node 22 Runtime and Cordis Loader] --> [Web Profile Overlay zsh and Tailnet]
[Node 22 Runtime and Cordis Loader] --> [Global Overlay cordis.patch.yml]
[Web Profile Overlay zsh and Tailnet] --> [Workspace Registry workspace.json 8 Projects]
[Global Overlay cordis.patch.yml] --> [UOS MCP Client mcp-uos-gleam]
[Global Overlay cordis.patch.yml] --> [UOS Skills Provider skill-filesystem-uos 91 Skills]
[Global Overlay cordis.patch.yml] --> [Agent Instructions .jj and AGENTS.md]
```

```mermaid
graph TD
  Zsh["Zsh Login Interactive Shell"] --> Wrapper["DSH Launcher Wrapper dsh"]
  Wrapper --> Loader["Node 22 Runtime and Cordis Loader"]
  Loader --> WebPatch["Web Profile Overlay zsh and Tailnet"]
  Loader --> GlobalPatch["Global Overlay cordis.patch.yml"]
  WebPatch --> Workspaces["Workspace Registry workspace.json 8 Projects"]
  GlobalPatch --> McpUos["UOS MCP Client mcp-uos-gleam"]
  GlobalPatch --> Skills["UOS Skills Provider skill-filesystem-uos 91 Skills"]
  GlobalPatch --> Instructions["Agent Instructions .jj and AGENTS.md"]
```

---

## 4. Root Cause Analysis

| ID | Symptom / Error Observed | Root Cause | Resolution | Status |
| :--- | :--- | :--- | :--- | :--- |
| **RCA-1** | `zsh: command not found: dsh` when running `dsh --no-open` and `dsh` in Zsh | `@deepseek-ai/dsh` was only invoked once via `npx @deepseek-ai/dsh web` and lived in volatile cache `/home/an/.npm/_npx/1e7f6d9597241db0` without a binary on `$PATH`. | Installed permanently to `/home/an/.local/share/dsh-cli` and exposed `/home/an/.local/bin/dsh` + `/home/an/.local/bin/deepseek-harness`. | **RESOLVED** |
| **RCA-2** | `error: --profile <name> is required` when running bare `dsh` or `dsh --no-open` | `apps/cli/src/args.ts` requires an explicit profile argument (`dsh web` or `dsh --profile web`) even when web flags like `--no-open` are passed. | Added smart profile defaulting in `/home/an/.local/bin/dsh`: zero args or leading web flags (`--no-open`, `--port`, `--host`, `--public-url`, `--trusted-host`, `--tls-*`) automatically dispatch to `web`. | **RESOLVED** |
| **RCA-3** | `Error: dsh: host preparation failed: node-addon-require-builtin unsupported: Unsupported/no-getter` | When Nix's Node.js `v24.19.0` (`/nix/store/.../bin/node`) precedes `/usr/bin/node` on `$PATH`, `@deepseek-ai/node-addon-system`'s binary getter introspection fails on the Nix Node 24 build. | Pinned `DSH_NODE="/usr/bin/node"` (`v22.22.1`) inside `/home/an/.local/bin/dsh`. | **RESOLVED** |
| **RCA-4** | `Error: Cannot find module '/home/an/.cache/node/corepack/pnpm/12.16.1/bin/pnpm.cjs'` | Bare `corepack enable pnpm` pulled `pnpm@12.16.1` which uses `native-binary.mjs` instead of `bin/pnpm.cjs` expected by system corepack `0.24.0`. | Activated `pnpm@10.33.0` (`corepack prepare pnpm@10.33.0 --activate`), matching DeepSeek Harness's own `packageManager` version. | **RESOLVED** |
| **RCA-5** | `StorageError: unit 'workspace': missing or foreign unit header` on first boot test | `@deepseek-ai/dsh-storage-json` `parse()` requires top-level `"unit": { "name": "workspace", "version": 2 }` rather than a flat `"version": 2` key. | Updated `/home/an/.dsh/storages/workspace.json` header to `"unit": { "name": "workspace", "version": 2 }`; verified 0 warnings on subsequent boot. | **RESOLVED** |

---

## 5. Fix Taxonomy

1. **Poka-Yoke (Mistake-Proofing)**:
   - Pinning `/usr/bin/node` (`v22.22.1`) in `/home/an/.local/bin/dsh` eliminates runtime ABI sensitivity to Nix/devenv `PATH` ordering.
   - Smart CLI flag routing (`dsh` $\rightarrow$ `dsh web`, `dsh --no-open` $\rightarrow$ `dsh web --no-open`) prevents operator CLI invocation errors.
2. **Jidoka (Autonomation / Fail-Closed Verification)**:
   - Setting `failOnStartupError: false` on `mcp-uos-gleam` ensures `dsh` enters its bounded exponential reconnect loop if the MCP server restarts rather than crashing the entire Web UI host fiber.
   - Live boot verification (`dsh --no-open --port 3089`) caught and resolved the `dsh-storage-json` unit header schema requirement before completion.
3. **Muda (Waste Elimination)**:
   - Mounting `mcp-uos-gleam` and `skill-filesystem-uos` once at the Host layer (`~/.dsh/cordis.patch.yml`) via `ScopedLayers<L>` global inheritance avoids spawning redundant `uos-mcp-stdio` processes or file watchers per agent preset.

---

## 6. Patterns & Anti-Patterns Discovered

- **Pattern 1 (Host-Layer Global Registration into `ScopedLayers<L>`)**: In DeepSeek Harness's Cordis architecture, `ctx.tools` and `ctx.skills` merge the Host global layer with each preset's scoped layer. Registering shared MCP servers (`mcp-uos-gleam`) and skill providers (`skill-filesystem-uos`) in `$DSH_HOME/cordis.patch.yml` makes them available across `web` (`standard`, `ptc`, `cordis`), `headless`, `sdk`, and `acp` with a single process instance.
- **Pattern 2 (Jujutsu `.jj` Project Root Discovery)**: Adding `.jj` before `.git` in `agent-instructions.config.projectRootMarkers` ensures that sessions launched or `cd`-ed into deep subdirectories of `/home/an/NAS-setup/uos` still walk upward to `/home/an/NAS-setup/uos/AGENTS.md`.
- **Anti-Pattern (Using `baseUrl` Relative Package Resolution in User Profile Patches)**: In shipped bundle patches (`@deepseek-ai/dsh-web-app/presets/cordis.patch.yml`), `createRequire(baseUrl).resolve('@deepseek-ai/dsh-agent-preset/package.json')` resolves relative to the bundle directory. When overriding `preset-cordis` in `~/.dsh/profiles/web/cordis.patch.yml`, `baseUrl` shifts to `~/.dsh/profiles/web/`, so `customSkillDirs` should reference the canonical absolute path `/home/an/.local/share/dsh-cli/node_modules/@deepseek-ai/dsh-agent-preset/skills`.

---

## 7. Verification Matrix

| # | Verification Surface | Command / Method | Observed Output | Status | Admiralty Grade |
| :---: | :--- | :--- | :--- | :---: | :---: |
| 1 | **Zsh Login Binary Resolution** | `zsh -lic 'which dsh deepseek-harness pnpm'` | `/home/an/.local/bin/dsh`, `/home/an/.local/bin/deepseek-harness`, `/home/an/.local/bin/pnpm` | **PASS** | **A1** |
| 2 | **CLI & Package Manager Versions** | `zsh -lic 'dsh --version && pnpm --version'` | `0.2.1-rc.5` and `10.33.0` | **PASS** | **A1** |
| 3 | **Composed Config Validation (`web` & `headless`)** | `dsh --profile web --dump-config` & `dsh --profile headless --dump-config` | Exit code `0`; verified `terminal-controller` (`zsh -i`), `mcp-uos-gleam`, `skill-filesystem-uos`, and `preset-{standard,ptc,cordis}` | **PASS** | **A1** |
| 4 | **UOS MCP Server Handshake (`uos-mcp-stdio`)** | JSON-RPC `initialize` over stdio to `/home/an/NAS-setup/uos/tools/uos-mcp-stdio` | `{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"uos-mcp-unified-gateway","version":"1.0.0"}}}` | **PASS** | **A1** |
| 5 | **Live Web Boot in `/home/an/NAS-setup/uos`** | `zsh -lic 'cd /home/an/NAS-setup/uos && dsh --no-open --port 3089'` | `dsh web: http://127.0.0.1:3089/?token=...` with **0 warnings** and **0 unactivated entries** | **PASS** | **A1** |
| 6 | **Skill Symlink Catalog Integrity** | Python directory & frontmatter verification across `~/.dsh/skills` & `~/.agents/skills` | `91/91` valid skills linked in both directories (`182` symlinks total, `0` missing frontmatter) | **PASS** | **A1** |
| 7 | **Dual-Source Diagram Gate (`SC-DIAGRAM-001`)** | `/home/an/NAS-setup/uos/tools/diagram-check` on this journal | `VERIFIED` (`G-DIAGRAM PASS`, 8 matching edges) | **PASS** | **A1** |

---

## 8. Files Modified

| # | File Path | Action | Description |
| :---: | :--- | :---: | :--- |
| 1 | [`/home/an/.local/share/dsh-cli`](file:///home/an/.local/share/dsh-cli) | CREATE | Permanent installation of `@deepseek-ai/dsh@0.2.1-rc.5` (`309` `@deepseek-ai/*` packages) |
| 2 | [`/home/an/.local/bin/dsh`](file:///home/an/.local/bin/dsh) | CREATE | Node 22-pinned launcher wrapper with env loading and default `web` profile routing |
| 3 | [`/home/an/.local/bin/deepseek-harness`](file:///home/an/.local/bin/deepseek-harness) | CREATE | Symlink to `/home/an/.local/bin/dsh` |
| 4 | [`/home/an/.local/bin/pnpm`](file:///home/an/.local/bin/pnpm) | CREATE | Corepack-managed `pnpm@10.33.0` binary for `dsh plugin` management |
| 5 | [`/home/an/.zshenv`](file:///home/an/.zshenv) | MODIFY | Added `~/.local/bin` & `~/.nix-profile/bin` to `PATH`, exported `DSH_HOME` & `DSH_AGENTS_HOME`, sourced `~/.config/shell/env.sh` |
| 6 | [`/home/an/.zshrc`](file:///home/an/.zshrc) | MODIFY | Added `~/.zsh/completions` to `fpath`, `[dsh]` prompt indicator, and `dsh-*` aliases/functions |
| 7 | [`/home/an/.zsh/completions/_dsh`](file:///home/an/.zsh/completions/_dsh) | CREATE | Zsh tab-completion script for `dsh` and `deepseek-harness` |
| 8 | [`/home/an/.dsh/AGENTS.md`](file:///home/an/.dsh/AGENTS.md) | CREATE | Global UOS, Jujutsu (`.jj/`), Zsh, and `mcp__uos-gleam__*` agent instructions |
| 9 | [`/home/an/.agents/AGENTS.md`](file:///home/an/.agents/AGENTS.md) | CREATE | Symlink to `/home/an/.dsh/AGENTS.md` |
| 10 | [`/home/an/NAS-setup/AGENTS.md`](file:///home/an/NAS-setup/AGENTS.md) | CREATE | Symlink to `.agents/AGENTS.md` (repairing `/home/an/NAS-setup/CLAUDE.md`) |
| 11 | [`/home/an/.dsh/skills`](file:///home/an/.dsh/skills) & [`/home/an/.agents/skills`](file:///home/an/.agents/skills) | CREATE | `91` skill directory symlinks each (`182` total) from UOS, NAS-setup, and `~/.claude/skills` |
| 12 | [`/home/an/.dsh/storages/workspace.json`](file:///home/an/.dsh/storages/workspace.json) | MODIFY | Registered 8 project workspaces (`uos`, `NAS-setup`, `c3i`, `harness-bionic`, `zigvm`, `k8s-lab`, `c3i-vm1`, `harness`) |
| 13 | [`/home/an/.dsh/cordis.patch.yml`](file:///home/an/.dsh/cordis.patch.yml) | CREATE | Global overlay mounting `mcp-uos-gleam`, `skill-filesystem-uos`, and `.jj` root detection |
| 14 | [`/home/an/.dsh/profiles/web/cordis.patch.yml`](file:///home/an/.dsh/profiles/web/cordis.patch.yml) | MODIFY | Web overlay for Zsh interactive terminals, Tailscale trusted hosts, SQLite search, and preset `.jj` instructions |
| 15 | [`/home/an/NAS-setup/docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md`](file:///home/an/NAS-setup/docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md) | CREATE | Workspace journal ledger |
| 16 | [`/home/an/NAS-setup/uos/docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md`](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261102-2034-deepseek-harness-zsh-and-uos-integration-journal.md) | CREATE | Canonical UOS journal mirror |

---

## 9. Architectural Observations

1. **Cordis Patch Stack Layering (`dsh-base` $\rightarrow$ `dsh-web-app` $\rightarrow$ `profiles/<name>/cordis.patch.yml` $\rightarrow$ `$DSH_HOME/cordis.patch.yml`)**:
   Separating Web-only concerns (`terminal-controller`, `connection.trustedHosts`, `session-query-sqlite`, `preset-*`) into `~/.dsh/profiles/web/cordis.patch.yml` while placing cross-profile UOS capabilities (`mcp-uos-gleam`, `skill-filesystem-uos`, base `agent-instructions`) in `~/.dsh/cordis.patch.yml` ensures that both browser sessions (`dsh` / `dsh-uos`) and CLI one-shot/protocol sessions (`dsh-ask`, `dsh-uos-ask`, `dsh-acp`, `dsh-sdk`) share the exact same UOS MCP tools and skill catalog without configuration duplication.
2. **ABI Isolation Between Host Node 22 and Nix Node 24**:
   Because DeepSeek Harness's `@deepseek-ai/node-addon-system-linux-x64` inspects V8/Node C++ getter layouts at startup, isolating `dsh` execution to `/usr/bin/node` (`v22.22.1`) while preserving `/home/an/.nix-profile/bin` on `PATH` allows `dsh` child tools (`gleam`, `jj`, `uos-mcp-stdio`) to access the full Nix toolchain without crashing the `dsh` host process.

---

## 10. Remaining Gaps

1. **Optional DeepSeek Official Account Login (`DEEPSEEK_API_KEY` / Account OAuth)**:
   - OpenRouter (`OPENROUTER_API_KEY`) and Gemini (`GEMINI_API_KEY`) are loaded automatically from `/home/an/.config/shell/env.sh`. If the operator wishes to use `deepseek-official` models directly alongside OpenRouter/Gemini, they can sign in via the Web UI Account settings or set `DEEPSEEK_API_KEY` in `~/.config/shell/env.sh`.
2. **On-Demand Web UI Server Lifecycle**:
   - `dsh` is configured for interactive/on-demand launch via `dsh`, `dsh-uos`, or `dsh-tailnet` (default port `3080`) rather than a background systemd unit, avoiding idle port contention when not in use.

---

## 11. Metrics Summary

| Metric | Pre-State | Post-State | Delta |
| :--- | :---: | :---: | :---: |
| `dsh` / `deepseek-harness` binaries on `$PATH` | `0` | `2` | `+2` |
| `pnpm` binary on `$PATH` (`10.33.0`) | `0` | `1` | `+1` |
| Registered Workspaces in `~/.dsh/storages/workspace.json` | `0` | `8` (`uos` primary) | `+8` |
| Linked Skills in `~/.dsh/skills` & `~/.agents/skills` | `0` | `91` (`182` symlinks) | `+91` |
| Mounted UOS MCP Servers (`mcp-uos-gleam`) | `0` | `1` (`51` UOS tools) | `+1` |
| Unactivated Entries / Warnings on `dsh web` Boot | `5` (during schema test) | `0` | `-5` (`100%` active) |
| Web UI Default Terminal Shell | `/bin/bash` | `/usr/bin/zsh -i` | Zsh integrated |

---

## 12. STAMP & Constitutional Alignment

- **UCA-1 (Not Providing Control Action — Missing UOS Context/MCP in DSH)**: Prevented by mounting `mcp-uos-gleam` (`/home/an/NAS-setup/uos/tools/uos-mcp-stdio`), `skill-filesystem-uos`, and `.jj`-aware `agent-instructions` across all profiles and presets.
- **UCA-2 (Providing Unsafe Control Action — Native Git Mutation or Read-Only Source Corruption)**: Prevented by explicit standalone Jujutsu (`.jj/`) and read-only external evidence rules embedded in `/home/an/.dsh/AGENTS.md` and `/home/an/NAS-setup/uos/AGENTS.md`.
- **UCA-3 (Wrong Timing / Startup Crash Under Nix Node 24)**: Prevented by pinning `/usr/bin/node` (`v22.22.1`) in `/home/an/.local/bin/dsh` and setting `failOnStartupError: false` on `mcp-uos-gleam`.
- **UCA-4 (Stopped Too Soon / Truncated `AGENTS.md`)**: Prevented by raising `agent-instructions.config.maxBytes` from `65536` (`64 KiB`) to `131072` (`128 KiB`) across base and preset configurations.

---

## 13. Conclusion

DeepSeek Harness (`dsh` `0.2.1-rc.5`) is permanently installed and integrated with Zsh and the Unified Operational System (`uos` and all 7 sibling workspaces). Bare `dsh`, `dsh --no-open`, `dsh-uos`, `dsh-tailnet`, and `dsh-uos-ask` work out of the box in Zsh with full tab-completion, interactive Zsh Web UI terminals, 8 pre-registered workspaces, 91 UOS/workspace skills, `.jj` root discovery, and live `uos-gleam` MCP tool access.

---

## Appendix A — Verbatim Configuration Artifacts & 91-Skill Inventory (Zero-Loss Archive)
### A.1 `/home/an/.local/bin/dsh`

```bash
#!/usr/bin/env bash
# DeepSeek Harness (dsh) launcher wrapper
# Ensures Node 22 ABI compatibility (node-addon-require-builtin),
# loads shell API keys, and defaults bare `dsh` / `dsh --no-open` to the `web` profile.

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
export DSH_AGENTS_HOME="${DSH_AGENTS_HOME:-$HOME/.agents}"

if [[ -z "${OPENROUTER_API_KEY:-}" || -z "${GEMINI_API_KEY:-}" ]] && [[ -f "$HOME/.config/shell/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.config/shell/env.sh"
fi

DSH_NODE="/usr/bin/node"
if [[ ! -x "$DSH_NODE" ]]; then
  DSH_NODE="$(command -v node)"
fi

DSH_BIN="$HOME/.local/share/dsh-cli/node_modules/.bin/dsh"
if [[ ! -f "$DSH_BIN" ]]; then
  echo "dsh: binary not found at $DSH_BIN" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  exec "$DSH_NODE" "$DSH_BIN" web
fi

has_profile=0
for arg in "$@"; do
  case "$arg" in
    --profile|--profile=*|web|headless|sdk|sdk-minimal|acp|plugin|-h|--help|-V|--version|--dump-config|--dump-default-config)
      has_profile=1
      break
      ;;
  esac
done

if [[ $has_profile -eq 0 ]]; then
  case "$1" in
    --no-open|--port|--port=*|--host|--host=*|--public-url|--public-url=*|--trusted-host|--trusted-host=*|--tls-cert|--tls-cert=*|--tls-key|--tls-key=*)
      exec "$DSH_NODE" "$DSH_BIN" web "$@"
      ;;
  esac
fi

exec "$DSH_NODE" "$DSH_BIN" "$@"
```
### A.2 `/home/an/.zshenv`

```zsh
. "$HOME/.cargo/env"

# Ensure ~/.local/bin and ~/.nix-profile/bin are available in all Zsh invocations
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
if [[ ":$PATH:" != *":$HOME/.nix-profile/bin:"* ]]; then
    export PATH="$HOME/.nix-profile/bin:$PATH"
fi

# DeepSeek Harness (dsh) & shared agent home directories
export DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
export DSH_AGENTS_HOME="${DSH_AGENTS_HOME:-$HOME/.agents}"

# Load shared API keys and environment variables
[[ -f "$HOME/.config/shell/env.sh" ]] && . "$HOME/.config/shell/env.sh"
```
### A.3 `/home/an/.zshrc`

```zsh
#!/bin/zsh
# ~/.zshrc - Zsh configuration

#=============================================================================
# History Configuration
#=============================================================================
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=20000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY

#=============================================================================
# Shell Options
#=============================================================================
setopt AUTO_CD              # cd by just typing directory name
setopt EXTENDED_GLOB        # Extended globbing
setopt INTERACTIVE_COMMENTS # Allow comments in interactive shell
setopt PROMPT_SUBST         # Enable parameter expansion in prompts

#=============================================================================
# Completion System
#=============================================================================
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
compinit

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case insensitive completion
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"    # Colored completion

#=============================================================================
# Prompt Configuration
#=============================================================================
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst

zstyle ':vcs_info:git:*' formats ' (%b)'
zstyle ':vcs_info:*' enable git

PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}${vcs_info_msg_0_}%f %# '

#=============================================================================
# Key Bindings (Emacs-style)
#=============================================================================
bindkey -e
bindkey '^[[A' history-beginning-search-backward  # Up arrow
bindkey '^[[B' history-beginning-search-forward   # Down arrow

#=============================================================================
# Colors and Aliases
#=============================================================================
# Enable colors
autoload -U colors && colors

# ls colors
if [[ -x /usr/bin/dircolors ]]; then
    eval "$(dircolors -b)"
fi

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Common aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Load custom aliases
[ -f ~/.zsh_aliases ] && . ~/.zsh_aliases
[ -f ~/.bash_aliases ] && . ~/.bash_aliases

#=============================================================================
# Environment Variables
#=============================================================================
# Claude Code (and other user installs)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Native Nix user profile tools: devenv, gleam, flutter, kubectl, helm, etc.
if [[ ":$PATH:" != *":$HOME/.nix-profile/bin:"* ]]; then
    export PATH="$HOME/.nix-profile/bin:$PATH"
fi

export NIX_CONFIG="experimental-features = nix-command flakes"

[ -f ~/.config/shell/env.sh ] && . ~/.config/shell/env.sh

echo "✅ Zsh environment loaded"


# Added by Antigravity CLI installer
export PATH="/home/an/.local/bin:$PATH"
export LIBRARY_PATH="$HOME/.local/lib:$LIBRARY_PATH"
eval $(~/.local/bin/opam env --switch=/home/an/dev/ver/zigvm --set-switch 2>/dev/null || true)

#=============================================================================
# DeepSeek Harness (dsh) & UOS Integration
#=============================================================================
export DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
export DSH_AGENTS_HOME="${DSH_AGENTS_HOME:-$HOME/.agents}"

if [[ -n "${DSH_SESSION_ID:-}" || -n "${DSH_WEB_URL:-}" ]]; then
    PROMPT='%F{cyan}[dsh]%f '"$PROMPT"
fi

alias dsh-web='dsh web --no-open'
alias dsh-tailnet='dsh web --no-open --host 100.87.7.78 --port 3080 --public-url http://nas-1.tail55d152.ts.net:3080 --trusted-host nas-1.tail55d152.ts.net --trusted-host 100.87.7.78'
alias dsh-acp='dsh acp'
alias dsh-sdk='dsh sdk'

dsh-uos() {
    (cd /home/an/NAS-setup/uos && dsh web --no-open "$@")
}

dsh-c3i() {
    (cd /home/an/NAS-setup/c3i && dsh web --no-open "$@")
}

dsh-bionic() {
    (cd /home/an/NAS-setup/harness-bionic && dsh web --no-open "$@")
}

dsh-zigvm() {
    (cd /home/an/dev/ver/zigvm && dsh web --no-open "$@")
}

dsh-ask() {
    dsh headless "$@"
}

dsh-uos-ask() {
    (cd /home/an/NAS-setup/uos && dsh headless "$@")
}
```
### A.4 `/home/an/.zsh/completions/_dsh`

```zsh
#compdef dsh deepseek-harness

_dsh() {
  local -a profiles subcommands
  profiles=(
    'web:Boot the DeepSeek Harness Web UI profile (default)'
    'headless:Run a one-shot headless agent task and exit'
    'sdk:Run the JSON-RPC SDK profile over stdio'
    'sdk-minimal:Run the minimal SDK profile'
    'acp:Run the Agent Client Protocol (ACP) stdio server'
  )
  subcommands=(
    'plugin:Manage profile plugin packages via pnpm'
  )

  if [[ -d "${DSH_HOME:-$HOME/.dsh}/profiles" ]]; then
    local dir name
    for dir in "${DSH_HOME:-$HOME/.dsh}"/profiles/*(/N); do
      name="${dir:t}"
      if [[ -z "${profiles[(r)${name}:*]}" ]]; then
        profiles+=("${name}:Custom DeepSeek Harness profile")
      fi
    done
  fi

  _arguments -C \
    '(-V --version)'{-V,--version}'[Output the version number]' \
    '(-h --help)'{-h,--help}'[Display help for command]' \
    '--profile[The profile under $DSH_HOME/profiles to boot]:profile:(web headless sdk sdk-minimal acp)' \
    '--from-default-profile[Replace a custom profile with a shipped profile template]:template:(web headless sdk sdk-minimal acp)' \
    '*--patch[Extra patch-list overlay applied after the profile layer]:patch file:_files -g "*.yml *.yaml"' \
    '--dump-config[Print the composed profile tree and exit]' \
    '--dump-config-schema[Print JSON Schema for profile entries and patches]' \
    '--dump-default-config[Print the profile tree without user layer or --patch overlays]' \
    '--no-open[Do not open browser automatically (web profile)]' \
    '--port[Web server listen port (default 3080)]:port:(3080 4180 8080)' \
    '--host[Web server bind host (default 127.0.0.1)]:host:(127.0.0.1 100.87.7.78)' \
    '--public-url[Advertised public URL for web profile]:url:' \
    '*--trusted-host[Additional trusted Host header / authority]:host:(nas-1.tail55d152.ts.net 100.87.7.78 vm-1.tail55d152.ts.net)' \
    '--tls-cert[TLS certificate file path]:cert file:_files' \
    '--tls-key[TLS private key file path]:key file:_files' \
    '1:profile or subcommand:->first_arg' \
    '*::args:->rest_args'

  case "$state" in
    first_arg)
      _describe -t profiles 'dsh profile' profiles
      _describe -t subcommands 'dsh subcommand' subcommands
      ;;
    rest_args)
      if [[ "${words[1]}" == "plugin" ]]; then
        _arguments \
          '--profile[Target profile for plugin operation]:profile:(web headless sdk sdk-minimal acp)' \
          '*:pnpm args:(add remove list outdated why)'
      else
        _files
      fi
      ;;
  esac
}

_dsh "$@"
```
### A.5 `/home/an/.dsh/AGENTS.md`

```markdown
# DeepSeek Harness (DSH) — UOS & Zsh Global Agent Instructions

## 1. Canonical UOS Workspace & VCS Discipline
- **Canonical UOS Monorepo**: `/home/an/NAS-setup/uos`
- **VCS Authority**: Standalone, non-colocated Jujutsu (`.jj/`) is the sole VCS inside `/home/an/NAS-setup/uos`. Native Git mutation commands (`git commit`, `git checkout`, `git push`, etc.) are strictly prohibited in `/home/an/NAS-setup/uos`.
- **Read-Only External Evidence Trees**: `/home/an/dev/ver/c3i`, `/home/an/dev/ver/zigvm`, and `/home/an/dev/ver/harness-bionic` are read-only source evidence.
- **Sa-Plan Exclusivity (`SC-JIDOKA-001`, `SC-SA-PLAN-001`)**: `tools/sa-plan` (`var/sa-plan/uos.sqlite3`) is the sole execution authority for plans, tasks, Oban jobs, and Temporal workflows.
- **Mandatory Timestamp Prefix (`SC-TIME`)**: All newly generated documentation, wiki articles, and journals in UOS must carry the `YYYYMMDD-HHSS-` prefix, verified via `tools/uos timestamp-check`.
- **Zero-Muda Purity**: Zero Bevy, zero Graphite, and zero foreign Graphene NIFs.

## 2. Connected Workspaces
- `uos`: `/home/an/NAS-setup/uos` — Unified Operational System (Gleam/OTP 29, ZigVM, Hermes OCaml, Modular MAX, Lean 4 / Quint)
- `NAS-setup`: `/home/an/NAS-setup` — Host orchestration & workspace root
- `c3i`: `/home/an/NAS-setup/c3i` — C3I Gleam/Lustre/Wisp/TUI cockpit
- `harness-bionic`: `/home/an/NAS-setup/harness-bionic` — Bionic Harness workspace
- `zigvm`: `/home/an/dev/ver/zigvm` — ZigVM deterministic runtime (read-only evidence)
- `k8s-lab`: `/home/an/NAS-setup/k8s-lab` — NAS-1 Kubernetes & Rook-Ceph storage controller (`HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"`)

## 3. UOS MCP Server (`uos-gleam`)
The `uos-gleam` MCP server (`/home/an/NAS-setup/uos/tools/uos-mcp-stdio`) is mounted in DeepSeek Harness and exposes tools under the `mcp__uos-gleam__*` namespace, including:
- **Sa-Plan**: `mcp__uos-gleam__sa_plan_status`, `mcp__uos-gleam__sa_plan_list`, `mcp__uos-gleam__sa_task_claim`, `mcp__uos-gleam__sa_task_complete`
- **System & C3I**: `mcp__uos-gleam__system_health`, `mcp__uos-gleam__system_dashboard`, `mcp__uos-gleam__system_zenoh`, `mcp__uos-gleam__fractal_status`, `mcp__uos-gleam__ooda_phase`
- **Knowledge & Verification**: `mcp__uos-gleam__knowledge_search`, `mcp__uos-gleam__zk_transclude`, `mcp__uos-gleam__verification_run`

## 4. Shell & Runtime Environment
- Interactive terminals in DeepSeek Harness run `/usr/bin/zsh -i` with `~/.local/bin` and `~/.nix-profile/bin` on `PATH`.
- Tailscale Cockpit FQDN: `http://nas-1.tail55d152.ts.net:4100` (`100.87.7.78`).
```
### A.6 `/home/an/.dsh/cordis.patch.yml`

```yaml
# Machine-local DeepSeek Harness overlay ($DSH_HOME/cordis.patch.yml)
# Applied across all profiles (web, headless, sdk, acp).

- id: agent-instructions
  config:
    projectRootMarkers:
      - .jj
      - .git
    instructionFileCandidates:
      - AGENTS.md
      - CLAUDE.md
      - GEMINI.md
      - CODEX.md
    maxBytes: 131072

- insert:
    - id: mcp-uos-gleam
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        transport: stdio
        serverName: uos-gleam
        command: /home/an/NAS-setup/uos/tools/uos-mcp-stdio
        args: []
        cwd: /home/an/NAS-setup/uos
        toolCallTimeoutMs: 60000
        failOnStartupError: false
        env:
          UOS_ROOT: /home/an/NAS-setup/uos
          UOS_COCKPIT_BASE_URL: http://nas-1.tail55d152.ts.net:4100
          UOS_PEER_BASE_URL: http://vm-1.tail55d152.ts.net:8088
          UOS_SA_PLAN_DB: /home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3

    - id: skill-filesystem-uos
      name: '@deepseek-ai/dsh-skill-filesystem'
      config:
        providerName: uos-skills
        includeDefaultRoots: false
        customSkillDirs:
          - /home/an/NAS-setup/uos/.agents/skills
          - /home/an/NAS-setup/.agents/skills
```
### A.7 `/home/an/.dsh/profiles/web/cordis.patch.yml`

```yaml
# Web profile user layer ($DSH_HOME/profiles/web/cordis.patch.yml)
# Integrates Zsh interactive terminals, Tailscale FQDN trusted hosts,
# session search, and Jujutsu (.jj) + UOS agent instructions across presets.

- id: terminal-controller
  config:
    shell:
      path: /usr/bin/zsh
      name: zsh
      args:
        - -i
    shellCandidates:
      - zsh
      - bash
      - fish
      - pwsh
      - powershell
      - cmd

- id: session-query-sqlite
  config:
    path: ':memory:'
    openAt: first-search

- id: connection
  inject:
    - webStartup
  config:
    trustedHosts: !!js "['nas-1.tail55d152.ts.net', '100.87.7.78', 'vm-1.tail55d152.ts.net', '100.78.98.18', ...ctx.webStartup.trustedHosts]"

- id: preset-standard
  config:
    id: standard
    order: 1
    plugins:
      - id: persona
        name: '@deepseek-ai/dsh-persona'
        config:
          prefix: You are a coding agent powered by the {{model}} model.
      - id: agent-instructions
        name: '@deepseek-ai/dsh-agent-instructions'
        config:
          projectRootMarkers:
            - .jj
            - .git
          instructionFileCandidates:
            - AGENTS.md
            - CLAUDE.md
            - GEMINI.md
            - CODEX.md
          maxBytes: 131072
      - id: time-context
        name: '@deepseek-ai/dsh-time-context'
      - id: tool-bash
        name: '@deepseek-ai/dsh-tool-bash'
        disabled: !!js process.platform === 'win32'
      - id: tool-pwsh
        name: '@deepseek-ai/dsh-tool-pwsh'
        disabled: !!js process.platform !== 'win32'
      - id: tool-fs
        name: '@deepseek-ai/dsh-tool-fs'
      - id: tool-fs-search
        name: '@deepseek-ai/dsh-tool-fs-search'
        config:
          sampleOverCapGlobResults: false
      - id: tool-jobs
        name: '@deepseek-ai/dsh-tool-jobs'
      - id: tool-schedule
        name: '@deepseek-ai/dsh-tool-schedule'
      - id: skill-filesystem
        name: '@deepseek-ai/dsh-skill-filesystem'
      - id: tool-skill
        name: '@deepseek-ai/dsh-tool-skill'
      - id: command-goal
        name: '@deepseek-ai/dsh-command-goal'
      - id: tool-goal
        name: '@deepseek-ai/dsh-tool-goal'
      - id: planning
        name: cordis:group
        group: true
        isolate:
          planMode: true
        config:
          - id: plan-mode
            name: '@deepseek-ai/dsh-plan-mode'
            config:
              section: |
                You are in plan mode. Stay in plan mode until the user approves your plan through exit_plan_mode or switches the session mode. Imperative language to implement changes means plan the implementation, not execute it. A user's conversational agreement — including an answer confirming something you asked — approves nothing and does not end plan mode; fold the confirmed decision into the plan and submit it through exit_plan_mode.

                Explore first. Use non-mutating reads, searches, static analysis, and checks to ground the plan in the actual repository. Do not edit or write files, change configuration, run formatters or code generation that rewrites tracked files, commit, or otherwise carry out the plan. Prefer existing functions and patterns over new machinery.

                The tool catalog stays the same across modes for request-cache stability. These plan-mode rules override any later tool description or guidance that suggests using mutation tools; those tools remain listed to keep the tool catalog unchanged. Do not use todo_write to track this planning phase: it tracks implementation after an approved plan, while the plan itself belongs in exit_plan_mode.

                Resolve discoverable facts by inspection. Use ask_user_question only for user-owned choices or material ambiguity that inspection cannot answer. Do not ask the user where code lives or how current behavior works when you can find out.

                Make the plan decision-complete: state the goal and success criteria; group implementation changes by subsystem; identify public API, schema, and data-flow changes; cover edge cases, failure modes, tests, acceptance criteria, and explicit assumptions. Keep it concise enough to review but detailed enough that another engineer can implement it without making design decisions.

                When ready, call exit_plan_mode with the complete plan markdown, starting with a # title. Make exit_plan_mode the only and final tool call in that assistant response: it presents the plan for approval, and implementation begins only in a later step after approval. Do not paste the final plan as a plain reply or ask "should I proceed?" through prose or ask_user_question. If review rejects it, incorporate the feedback and present again. If the review channel is unavailable or aborted, stay in plan mode and ask the user to switch modes manually; do not proceed with implementation.
      - id: compaction
        name: cordis:group
        group: true
        isolate:
          compaction: true
          toolResultPruner: true
        config:
          - id: compaction-basic
            name: '@deepseek-ai/dsh-compaction-basic'
          - id: command-compact
            name: '@deepseek-ai/dsh-command-compact'
          - id: tool-result-pruner
            name: '@deepseek-ai/dsh-compaction-tool-result-pruner'
            config:
              thresholdChars: 8192
              headChars: 4096
              tailChars: 1024
      - id: delegation
        name: cordis:group
        group: true
        isolate:
          workflowEngine: true
        config:
          - id: tool-subagent-control
            name: '@deepseek-ai/dsh-tool-subagent-control'
          - id: tool-subagent-list-agents
            name: '@deepseek-ai/dsh-tool-subagent-control/list-agents'
          - id: tool-subagent
            name: '@deepseek-ai/dsh-tool-subagent'
            config:
              provider: spawn
              toolName: subagent
              modelSelectionSettings: true
          - id: tool-subagent-fork
            name: '@deepseek-ai/dsh-tool-subagent'
            config:
              provider: fork
              toolName: subagent_fork
          - id: workflow-ptc
            name: '@deepseek-ai/dsh-workflow-ptc'
            config:
              provider: spawn
          - id: tool-workflow
            name: '@deepseek-ai/dsh-tool-workflow'
      - id: tool-ask-user
        name: '@deepseek-ai/dsh-tool-ask-user'
      - id: tool-todo
        name: '@deepseek-ai/dsh-tool-todo'
        config:
          allowParallelInProgress: true
      - id: tool-web
        name: '@deepseek-ai/dsh-tool-web'
        config:
          fetch: true
          searchTimeoutMs: 60000
      - id: present
        name: '@deepseek-ai/dsh-tool-present'
      - id: tool-plugin-manager
        name: '@deepseek-ai/dsh-plugin-manager/tools'
        disabled: true
      - id: tool-plugin-market
        name: '@deepseek-ai/dsh-plugin-market/tools'
        disabled: true

- id: preset-ptc
  config:
    id: ptc
    order: 2
    plugins:
      - id: persona
        name: '@deepseek-ai/dsh-persona'
        config:
          prefix: You are a coding agent powered by the {{model}} model.
      - id: agent-instructions
        name: '@deepseek-ai/dsh-agent-instructions'
        config:
          projectRootMarkers:
            - .jj
            - .git
          instructionFileCandidates:
            - AGENTS.md
            - CLAUDE.md
            - GEMINI.md
            - CODEX.md
          maxBytes: 131072
      - id: time-context
        name: '@deepseek-ai/dsh-time-context'
      - id: tool-bash
        name: '@deepseek-ai/dsh-tool-bash'
        disabled: !!js process.platform === 'win32'
      - id: tool-pwsh
        name: '@deepseek-ai/dsh-tool-pwsh'
        disabled: !!js process.platform !== 'win32'
      - id: tool-fs
        name: '@deepseek-ai/dsh-tool-fs'
      - id: tool-fs-search
        name: '@deepseek-ai/dsh-tool-fs-search'
        config:
          sampleOverCapGlobResults: false
      - id: tool-jobs
        name: '@deepseek-ai/dsh-tool-jobs'
      - id: tool-schedule
        name: '@deepseek-ai/dsh-tool-schedule'
      - id: skill-filesystem
        name: '@deepseek-ai/dsh-skill-filesystem'
      - id: tool-skill
        name: '@deepseek-ai/dsh-tool-skill'
      - id: command-goal
        name: '@deepseek-ai/dsh-command-goal'
      - id: tool-goal
        name: '@deepseek-ai/dsh-tool-goal'
      - id: planning
        name: cordis:group
        group: true
        isolate:
          planMode: true
        config:
          - id: plan-mode
            name: '@deepseek-ai/dsh-plan-mode'
            config:
              section: |
                You are in plan mode. Stay in plan mode until the user approves your plan through exit_plan_mode or switches the session mode. Imperative language to implement changes means plan the implementation, not execute it. A user's conversational agreement — including an answer confirming something you asked — approves nothing and does not end plan mode; fold the confirmed decision into the plan and submit it through exit_plan_mode.

                Explore first. Use non-mutating reads, searches, static analysis, and checks to ground the plan in the actual repository. Do not edit or write files, change configuration, run formatters or code generation that rewrites tracked files, commit, or otherwise carry out the plan. Prefer existing functions and patterns over new machinery.

                The tool catalog stays the same across modes for request-cache stability. These plan-mode rules override any later tool description or guidance that suggests using mutation tools; those tools remain listed to keep the tool catalog unchanged. Do not use todo_write to track this planning phase: it tracks implementation after an approved plan, while the plan itself belongs in exit_plan_mode.

                Resolve discoverable facts by inspection. Use ask_user_question only for user-owned choices or material ambiguity that inspection cannot answer. Do not ask the user where code lives or how current behavior works when you can find out.

                Make the plan decision-complete: state the goal and success criteria; group implementation changes by subsystem; identify public API, schema, and data-flow changes; cover edge cases, failure modes, tests, acceptance criteria, and explicit assumptions. Keep it concise enough to review but detailed enough that another engineer can implement it without making design decisions.

                When ready, call exit_plan_mode with the complete plan markdown, starting with a # title. Make exit_plan_mode the only and final tool call in that assistant response: it presents the plan for approval, and implementation begins only in a later step after approval. Do not paste the final plan as a plain reply or ask "should I proceed?" through prose or ask_user_question. If review rejects it, incorporate the feedback and present again. If the review channel is unavailable or aborted, stay in plan mode and ask the user to switch modes manually; do not proceed with implementation.
      - id: compaction
        name: cordis:group
        group: true
        isolate:
          compaction: true
          toolResultPruner: true
        config:
          - id: compaction-basic
            name: '@deepseek-ai/dsh-compaction-basic'
          - id: command-compact
            name: '@deepseek-ai/dsh-command-compact'
          - id: tool-result-pruner
            name: '@deepseek-ai/dsh-compaction-tool-result-pruner'
            config:
              thresholdChars: 8192
              headChars: 4096
              tailChars: 1024
      - id: delegation
        name: cordis:group
        group: true
        isolate:
          workflowEngine: true
        config:
          - id: tool-subagent-control
            name: '@deepseek-ai/dsh-tool-subagent-control'
          - id: tool-subagent-list-agents
            name: '@deepseek-ai/dsh-tool-subagent-control/list-agents'
          - id: tool-subagent
            name: '@deepseek-ai/dsh-tool-subagent'
            config:
              provider: spawn
              toolName: subagent
              modelSelectionSettings: true
          - id: tool-subagent-fork
            name: '@deepseek-ai/dsh-tool-subagent'
            config:
              provider: fork
              toolName: subagent_fork
          - id: workflow-ptc
            name: '@deepseek-ai/dsh-workflow-ptc'
            disabled: true
            config:
              provider: spawn
          - id: tool-workflow
            name: '@deepseek-ai/dsh-tool-workflow'
            disabled: true
      - id: tool-ask-user
        name: '@deepseek-ai/dsh-tool-ask-user'
      - id: tool-todo
        name: '@deepseek-ai/dsh-tool-todo'
        config:
          allowParallelInProgress: true
      - id: tool-web
        name: '@deepseek-ai/dsh-tool-web'
        config:
          fetch: true
          searchTimeoutMs: 60000
      - id: tool-presentation
        name: '@deepseek-ai/dsh-agent-tool-presentation'
        config:
          mode: ptc
      - id: present
        name: '@deepseek-ai/dsh-tool-present'
      - id: tool-plugin-manager
        name: '@deepseek-ai/dsh-plugin-manager/tools'
        disabled: true
      - id: tool-plugin-market
        name: '@deepseek-ai/dsh-plugin-market/tools'
        disabled: true

- id: preset-cordis
  config:
    id: cordis
    order: 4
    plugins:
      - id: persona
        name: '@deepseek-ai/dsh-persona'
        config:
          prefix: You are a coding agent powered by the {{model}} model.
      - id: agent-instructions
        name: '@deepseek-ai/dsh-agent-instructions'
        config:
          projectRootMarkers:
            - .jj
            - .git
          instructionFileCandidates:
            - AGENTS.md
            - CLAUDE.md
            - GEMINI.md
            - CODEX.md
          maxBytes: 131072
      - id: time-context
        name: '@deepseek-ai/dsh-time-context'
      - id: tool-bash
        name: '@deepseek-ai/dsh-tool-bash'
        disabled: !!js process.platform === 'win32'
      - id: tool-pwsh
        name: '@deepseek-ai/dsh-tool-pwsh'
        disabled: !!js process.platform !== 'win32'
      - id: tool-fs
        name: '@deepseek-ai/dsh-tool-fs'
      - id: tool-fs-search
        name: '@deepseek-ai/dsh-tool-fs-search'
        config:
          sampleOverCapGlobResults: false
      - id: tool-jobs
        name: '@deepseek-ai/dsh-tool-jobs'
      - id: tool-schedule
        name: '@deepseek-ai/dsh-tool-schedule'
      - id: command-goal
        name: '@deepseek-ai/dsh-command-goal'
      - id: tool-goal
        name: '@deepseek-ai/dsh-tool-goal'
      - id: planning
        name: cordis:group
        group: true
        isolate:
          planMode: true
        config:
          - id: plan-mode
            name: '@deepseek-ai/dsh-plan-mode'
            config:
              section: |
                You are in plan mode. Stay in plan mode until the user approves your plan through exit_plan_mode or switches the session mode. Imperative language to implement changes means plan the implementation, not execute it. A user's conversational agreement — including an answer confirming something you asked — approves nothing and does not end plan mode; fold the confirmed decision into the plan and submit it through exit_plan_mode.

                Explore first. Use non-mutating reads, searches, static analysis, and checks to ground the plan in the actual repository. Do not edit or write files, change configuration, run formatters or code generation that rewrites tracked files, commit, or otherwise carry out the plan. Prefer existing functions and patterns over new machinery.

                The tool catalog stays the same across modes for request-cache stability. These plan-mode rules override any later tool description or guidance that suggests using mutation tools; those tools remain listed to keep the tool catalog unchanged. Do not use todo_write to track this planning phase: it tracks implementation after an approved plan, while the plan itself belongs in exit_plan_mode.

                Resolve discoverable facts by inspection. Use ask_user_question only for user-owned choices or material ambiguity that inspection cannot answer. Do not ask the user where code lives or how current behavior works when you can find out.

                Make the plan decision-complete: state the goal and success criteria; group implementation changes by subsystem; identify public API, schema, and data-flow changes; cover edge cases, failure modes, tests, acceptance criteria, and explicit assumptions. Keep it concise enough to review but detailed enough that another engineer can implement it without making design decisions.

                When ready, call exit_plan_mode with the complete plan markdown, starting with a # title. Make exit_plan_mode the only and final tool call in that assistant response: it presents the plan for approval, and implementation begins only in a later step after approval. Do not paste the final plan as a plain reply or ask "should I proceed?" through prose or ask_user_question. If review rejects it, incorporate the feedback and present again. If the review channel is unavailable or aborted, stay in plan mode and ask the user to switch modes manually; do not proceed with implementation.
      - id: compaction
        name: cordis:group
        group: true
        isolate:
          compaction: true
          toolResultPruner: true
        config:
          - id: compaction-basic
            name: '@deepseek-ai/dsh-compaction-basic'
          - id: command-compact
            name: '@deepseek-ai/dsh-command-compact'
          - id: tool-result-pruner
            name: '@deepseek-ai/dsh-compaction-tool-result-pruner'
            config:
              thresholdChars: 8192
              headChars: 4096
              tailChars: 1024
      - id: delegation
        name: cordis:group
        group: true
        isolate:
          workflowEngine: true
        config:
          - id: tool-subagent-control
            name: '@deepseek-ai/dsh-tool-subagent-control'
          - id: tool-subagent-list-agents
            name: '@deepseek-ai/dsh-tool-subagent-control/list-agents'
          - id: tool-subagent
            name: '@deepseek-ai/dsh-tool-subagent'
            config:
              provider: spawn
              toolName: subagent
              modelSelectionSettings: true
          - id: tool-subagent-fork
            name: '@deepseek-ai/dsh-tool-subagent'
            config:
              provider: fork
              toolName: subagent_fork
          - id: workflow-ptc
            name: '@deepseek-ai/dsh-workflow-ptc'
            config:
              provider: spawn
          - id: tool-workflow
            name: '@deepseek-ai/dsh-tool-workflow'
      - id: tool-ask-user
        name: '@deepseek-ai/dsh-tool-ask-user'
      - id: tool-todo
        name: '@deepseek-ai/dsh-tool-todo'
        config:
          allowParallelInProgress: true
      - id: tool-web
        name: '@deepseek-ai/dsh-tool-web'
        config:
          fetch: true
          searchTimeoutMs: 60000
      - id: tool-cordis
        name: '@deepseek-ai/dsh-tool-cordis'
      - id: skill-filesystem
        name: '@deepseek-ai/dsh-skill-filesystem'
        config:
          customSkillDirs:
            - /home/an/.local/share/dsh-cli/node_modules/@deepseek-ai/dsh-agent-preset/skills
      - id: tool-skill
        name: '@deepseek-ai/dsh-tool-skill'
      - id: present
        name: '@deepseek-ai/dsh-tool-present'
      - id: tool-plugin-manager
        name: '@deepseek-ai/dsh-plugin-manager/tools'
        disabled: !!js "!ctx.get('profileContext')"
      - id: tool-plugin-market
        name: '@deepseek-ai/dsh-plugin-market/tools'
        disabled: !!js "!ctx.get('profileContext')"
```
### A.8 `/home/an/.dsh/storages/workspace.json`

```json
{
  "unit": {
    "name": "workspace",
    "version": 2
  },
  "global": {
    "initialized": true,
    "workspaceIds": [
      "a1b2c3d4-0001-4000-8000-000000000001",
      "a1b2c3d4-0002-4000-8000-000000000002",
      "a1b2c3d4-0003-4000-8000-000000000003",
      "a1b2c3d4-0004-4000-8000-000000000004",
      "a1b2c3d4-0005-4000-8000-000000000005",
      "a1b2c3d4-0006-4000-8000-000000000006",
      "a1b2c3d4-0007-4000-8000-000000000007",
      "a1b2c3d4-0008-4000-8000-000000000008"
    ],
    "archivedSessionIds": [],
    "pinnedSessionIds": []
  },
  "tables": {
    "workspaces": {
      "a1b2c3d4-0001-4000-8000-000000000001": {
        "path": "/home/an/NAS-setup/uos",
        "title": "uos",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      },
      "a1b2c3d4-0002-4000-8000-000000000002": {
        "path": "/home/an/NAS-setup",
        "title": "NAS-setup",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      },
      "a1b2c3d4-0003-4000-8000-000000000003": {
        "path": "/home/an/NAS-setup/c3i",
        "title": "c3i",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      },
      "a1b2c3d4-0004-4000-8000-000000000004": {
        "path": "/home/an/NAS-setup/harness-bionic",
        "title": "harness-bionic",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      },
      "a1b2c3d4-0005-4000-8000-000000000005": {
        "path": "/home/an/dev/ver/zigvm",
        "title": "zigvm",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      },
      "a1b2c3d4-0006-4000-8000-000000000006": {
        "path": "/home/an/NAS-setup/k8s-lab",
        "title": "k8s-lab",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      },
      "a1b2c3d4-0007-4000-8000-000000000007": {
        "path": "/home/an/dev/ver/c3i",
        "title": "c3i-vm1",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      },
      "a1b2c3d4-0008-4000-8000-000000000008": {
        "path": "/home/an/dev/ver/harness",
        "title": "harness",
        "sessionIds": [],
        "createdAt": "2026-11-02T19:20:00.000Z",
        "updatedAt": "2026-11-02T19:20:00.000Z"
      }
    }
  }
}
```
### A.9 Complete 91-Skill Symlink Inventory (`~/.dsh/skills` & `~/.agents/skills`)

1. `ak47-multi-agent-mcp-symbiosis` -> `/home/an/NAS-setup/uos/.agents/skills/ak47-multi-agent-mcp-symbiosis`
2. `algebra-driven-beam` -> `/home/an/.claude/skills/algebra-driven-beam`
3. `algebra-driven-ocaml` -> `/home/an/.claude/skills/algebra-driven-ocaml`
4. `algebra-driven-zig` -> `/home/an/.claude/skills/algebra-driven-zig`
5. `algebraic-fractal-structures` -> `/home/an/.claude/skills/algebraic-fractal-structures`
6. `allium` -> `/home/an/.claude/skills/allium`
7. `approach-b-zero-muda-observability` -> `/home/an/.claude/skills/approach-b-zero-muda-observability`
8. `artifact-sync` -> `/home/an/.claude/skills/artifact-sync`
9. `bonsai-ui-development` -> `/home/an/.claude/skills/bonsai-ui-development`
10. `brainstorming` -> `/home/an/NAS-setup/uos/.agents/skills/brainstorming`
11. `c3i-page-evolution` -> `/home/an/.claude/skills/c3i-page-evolution`
12. `c3i-temporal-orchestration` -> `/home/an/.claude/skills/c3i-temporal-orchestration`
13. `capability-eq-flip` -> `/home/an/.claude/skills/capability-eq-flip`
14. `cepaf-planning-expert` -> `/home/an/.claude/skills/cepaf-planning-expert`
15. `cepaf-podman-expert` -> `/home/an/.claude/skills/cepaf-podman-expert`
16. `cepaf-zenoh-expert` -> `/home/an/.claude/skills/cepaf-zenoh-expert`
17. `codex-symbiosis` -> `/home/an/.claude/skills/codex-symbiosis`
18. `diagnosing-superpowers` -> `/home/an/NAS-setup/uos/.agents/skills/diagnosing-superpowers`
19. `dispatching-parallel-agents` -> `/home/an/NAS-setup/uos/.agents/skills/dispatching-parallel-agents`
20. `docs-design` -> `/home/an/.claude/skills/docs-design`
21. `effect-ts-architect` -> `/home/an/.claude/skills/effect-ts-architect`
22. `effect-ts-iife-enforcer` -> `/home/an/.claude/skills/effect-ts-iife-enforcer`
23. `executing-plans` -> `/home/an/NAS-setup/uos/.agents/skills/executing-plans`
24. `fast-evolve` -> `/home/an/.claude/skills/fast-evolve`
25. `feature-evolution` -> `/home/an/.claude/skills/feature-evolution`
26. `finishing-a-development-branch` -> `/home/an/NAS-setup/uos/.agents/skills/finishing-a-development-branch`
27. `formal-technique-selection` -> `/home/an/.claude/skills/formal-technique-selection`
28. `formal-verification-pipeline` -> `/home/an/.claude/skills/formal-verification-pipeline`
29. `fp-core-rust-architect` -> `/home/an/.claude/skills/fp-core-rust-architect`
30. `fractal-autopilot` -> `/home/an/.claude/skills/fractal-autopilot`
31. `fractal-decision-calculus` -> `/home/an/.claude/skills/fractal-decision-calculus`
32. `fractal-workspace-audit` -> `/home/an/.claude/skills/fractal-workspace-audit`
33. `full-symbiosis` -> `/home/an/NAS-setup/uos/.agents/skills/full-symbiosis`
34. `fy27-linkedin-ops` -> `/home/an/.claude/skills/fy27-linkedin-ops`
35. `gemini-symbiosis` -> `/home/an/NAS-setup/uos/.agents/skills/gemini-symbiosis`
36. `gleam-expert` -> `/home/an/.claude/skills/gleam-expert`
37. `harness-supervisor` -> `/home/an/.claude/skills/harness-supervisor`
38. `infranodus-design-superset` -> `/home/an/.claude/skills/infranodus-design-superset`
39. `journal-protocol` -> `/home/an/.claude/skills/journal-protocol`
40. `living-ontology` -> `/home/an/.claude/skills/living-ontology`
41. `lustre-gleam-ui-expert` -> `/home/an/.claude/skills/lustre-gleam-ui-expert`
42. `mesh-resurrection` -> `/home/an/.claude/skills/mesh-resurrection`
43. `mobile-first-adaptive-ui` -> `/home/an/.claude/skills/mobile-first-adaptive-ui`
44. `multilayer-swarm` -> `/home/an/.claude/skills/multilayer-swarm`
45. `ocaml-figma-control` -> `/home/an/.claude/skills/ocaml-figma-control`
46. `ocaml-playwright-control` -> `/home/an/NAS-setup/uos/.agents/skills/ocaml-playwright-control`
47. `ocaml-scripting` -> `/home/an/.claude/skills/ocaml-scripting`
48. `otp-conformance-protocol` -> `/home/an/.claude/skills/otp-conformance-protocol`
49. `parity-scenario-authoring` -> `/home/an/.claude/skills/parity-scenario-authoring`
50. `pi-prompt` -> `/home/an/.claude/skills/pi-prompt`
51. `pi-symbiosis-evolve` -> `/home/an/.claude/skills/pi-symbiosis-evolve`
52. `production-readiness` -> `/home/an/NAS-setup/uos/.agents/skills/production-readiness`
53. `raven-ml-substrate` -> `/home/an/.claude/skills/raven-ml-substrate`
54. `receiving-code-review` -> `/home/an/NAS-setup/uos/.agents/skills/receiving-code-review`
55. `requesting-code-review` -> `/home/an/NAS-setup/uos/.agents/skills/requesting-code-review`
56. `resource-preflight` -> `/home/an/.claude/skills/resource-preflight`
57. `safe-rust-x-safety` -> `/home/an/.claude/skills/safe-rust-x-safety`
58. `sales` -> `/home/an/.claude/skills/sales`
59. `sales-analyze` -> `/home/an/.claude/skills/sales-analyze`
60. `sales-brief` -> `/home/an/.claude/skills/sales-brief`
61. `sales-forecast` -> `/home/an/.claude/skills/sales-forecast`
62. `sales-hunt` -> `/home/an/.claude/skills/sales-hunt`
63. `smp-concurrency-slice` -> `/home/an/.claude/skills/smp-concurrency-slice`
64. `smtml-solver-substrate` -> `/home/an/.claude/skills/smtml-solver-substrate`
65. `stan-probabilistic-substrate` -> `/home/an/.claude/skills/stan-probabilistic-substrate`
66. `stpa-safety-protocol` -> `/home/an/.claude/skills/stpa-safety-protocol`
67. `subagent-driven-development` -> `/home/an/NAS-setup/uos/.agents/skills/subagent-driven-development`
68. `swarm-verification-expert` -> `/home/an/.claude/skills/swarm-verification-expert`
69. `system-engineering-sop` -> `/home/an/.claude/skills/system-engineering-sop`
70. `systematic-debugging` -> `/home/an/NAS-setup/uos/.agents/skills/systematic-debugging`
71. `tensor-space-evolution` -> `/home/an/NAS-setup/uos/.agents/skills/tensor-space-evolution`
72. `test-driven-development` -> `/home/an/NAS-setup/uos/.agents/skills/test-driven-development`
73. `timestamp-sync` -> `/home/an/.claude/skills/timestamp-sync`
74. `tyxml-conversion` -> `/home/an/.claude/skills/tyxml-conversion`
75. `ui-report-quality` -> `/home/an/.claude/skills/ui-report-quality`
76. `uos-gui-design` -> `/home/an/NAS-setup/uos/.agents/skills/uos-gui-design`
77. `uos-km-triad-brain-memory` -> `/home/an/NAS-setup/uos/.agents/skills/uos-km-triad-brain-memory`
78. `uos-risk-prioritization` -> `/home/an/NAS-setup/uos/.agents/skills/uos-risk-prioritization`
79. `uos-telegram-journeys` -> `/home/an/NAS-setup/uos/.agents/skills/uos-telegram-journeys`
80. `uos-tui-design` -> `/home/an/NAS-setup/uos/.agents/skills/uos-tui-design`
81. `uos-ui-superpowers` -> `/home/an/NAS-setup/uos/.agents/skills/uos-ui-superpowers`
82. `uos-zlp-hyperplane` -> `/home/an/NAS-setup/uos/.agents/skills/uos-zlp-hyperplane`
83. `using-git-worktrees` -> `/home/an/NAS-setup/uos/.agents/skills/using-git-worktrees`
84. `using-superpowers` -> `/home/an/NAS-setup/uos/.agents/skills/using-superpowers`
85. `verification-before-completion` -> `/home/an/NAS-setup/uos/.agents/skills/verification-before-completion`
86. `wiki-design` -> `/home/an/.claude/skills/wiki-design`
87. `writing-gospel-specifications` -> `/home/an/.claude/skills/writing-gospel-specifications`
88. `writing-plans` -> `/home/an/NAS-setup/uos/.agents/skills/writing-plans`
89. `writing-skills` -> `/home/an/NAS-setup/uos/.agents/skills/writing-skills`
90. `zigvm-harness-reuse` -> `/home/an/.claude/skills/zigvm-harness-reuse`
91. `zk-knowledge-base` -> `/home/an/.claude/skills/zk-knowledge-base`

---

## Comprehensive 6-Domain Verification Checklist (`SC-CHECKLIST-001`, `SC-PROVENANCE-001`)

<details>
<summary><strong>18/18 Core Verification Checkpoints + Domain 6 Provenance (Click to Expand)</strong></summary>

### Domain 1: Metadata, Timestamp & Tailscale Navigation
- [x] **C1.1 (`CHK-01-TIME`)**: Canonical `YYYYMMDD-HHSS-` filename prefix verified (`20261102-2034-`).
- [x] **C1.2 (`CHK-02-TAIL`)**: Full clickable Tailscale FQDN links (`http://nas-1.tail55d152.ts.net:4100/...`) embedded.
- [x] **C1.3 (`CHK-03-FRACT`)**: Standard fractal tags (`#fractal-l0`..`#fractal-l9`, `#km-triad`, `#zero-muda`, `#zk-adr`) present.
- [x] **C1.4 (`CHK-04-KM`)**: Knowledge graph transclusions (`[[wiki:20260905-1801-uos-zk-km-corpus-index]]`, `[[zk:20260905-1801-moc-uos-unified-master]]`) embedded.

### Domain 2: Zero-Muda Purity & Storage Safety
- [x] **C2.1 (`CHK-05-MUDA`)**: Zero Bevy and Zero Graphite across all manifests, dependencies, and runtime roles.
- [x] **C2.2 (`CHK-06-GRAPH`)**: Pure Erlang `graphene_nif.erl` and Hermes OCaml preserved; zero foreign NIF shared libraries added.
- [x] **C2.3 (`CHK-07-DRIVE`)**: Host OS NVMe serial `[REDACTED_SYSTEM_OS_SERIAL]` protected and redacted.

### Domain 3: Testing Gold Standard & Mathematical Gates
- [x] **C3.1 (`CHK-08-C1C8`)**: C1–C8 verification surfaces preserved.
- [x] **C3.2 (`CHK-09-MATH`)**: Mathematical and diagram equivalence gates verified (`G-DIAGRAM PASS`).
- [x] **C3.3 (`CHK-10-9MOD`)**: Live CLI, Zsh login shell, Cordis config dump, MCP stdio handshake, and HTTP server boot verified.
- [x] **C3.4 (`CHK-11-REGR`)**: Zero regressions introduced into UOS source tree.

### Domain 4: Cross-Language Control & Observability
- [x] **C4.1 (`CHK-12-GLEAM`)**: Gleam/OTP 29 `uos-mcp-stdio` connected to DeepSeek Harness via `mcp-uos-gleam`.
- [x] **C4.2 (`CHK-13-HERMES`)**: Hermes OCaml `diagram_check.exe` verification gate executed.
- [x] **C4.3 (`CHK-14-ZIGVM`)**: ZigVM workspace (`/home/an/dev/ver/zigvm`) registered read-only in `workspace.json`.
- [x] **C4.4 (`CHK-15-MAX`)**: Modular MAX isolation preserved.
- [x] **C4.5 (`CHK-16-OTEL`)**: Telemetry and environment configuration aligned.

### Domain 5: Tri-Sovereign Governance & Jujutsu Monorepo
- [x] **C5.1 (`CHK-17-SOV`)**: Tri-sovereign governance and `sa-plan` authority preserved (`SC-SA-PLAN-001`).
- [x] **C5.2 (`CHK-18-JJ`)**: Standalone Jujutsu (`.jj/`) VCS discipline maintained (`0` native Git mutations).

### Domain 6: Provenance Integrity (`SC-PROVENANCE-001`)
- [x] **C6.1 (`SC-PROVENANCE-001`)**: Admitted EV ceiling pinned at `EV-93` (zero new EV numbers minted).

</details>
