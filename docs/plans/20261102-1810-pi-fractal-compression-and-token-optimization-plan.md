# 20261102-1810 — Fractal Analysis & Implementation Plan: Context Compression, Token Economy, and Multi-Agent Performance Optimization

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zero-muda

- **Document Path**: [`docs/plans/20261102-1810-pi-fractal-compression-and-token-optimization-plan.md`](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261102-1810-pi-fractal-compression-and-token-optimization-plan.md)
- **Live Evidence Receipt**: [`var/evidence/20261102-1810-pi-fractal-compression-optimization-receipt.json`](http://nas-1.tail55d152.ts.net:4100/files/var/evidence/20261102-1810-pi-fractal-compression-optimization-receipt.json)
- **Canonical MCP Gateway**: `uos-harness` ([`tools/uos-mcp-stdio`](http://nas-1.tail55d152.ts.net:4100/files/tools/uos-mcp-stdio), OTP 29 / ERTS 17.0.5, capsule [`20261102-1620-a7b06b609fd26d53ca50d3451c2e4a4633df7dff2fb2e2f3faf2fd4ec59d6735`](http://nas-1.tail55d152.ts.net:4100/files/var/releases/ecology/20261102-1620-a7b06b609fd26d53ca50d3451c2e4a4633df7dff2fb2e2f3faf2fd4ec59d6735/capsule.json))
- **Admitted Provenance Ceiling**: `EV-93` ([`SC-PROVENANCE-001`](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md)); `EV-94..EV-109` and `ADR-071..ADR-086` remain `NOT_ADMITTED`.

---

## 1. Executive Summary & Empirical Baseline vs. Post-Optimization State

Across extended multi-agent engineering sessions, context bloat and unthrottled tool outputs were driving per-turn prompt volume above **336,000+ tokens** (with 18,000–35,000+ tokens of raw tool outputs and duplicate system instructions injected per turn).

By conducting a full 10-layer ($L_0 \dots L_9$) fractal root-cause analysis and executing deterministic configuration and proxy optimizations across **Pi**, **`billion-context` (`0.1.210`)**, **`pi-mcp-adapter`**, and **`uos-harness`**, we achieved:

| Metric | Pre-Optimization Baseline | Post-Optimization Verified State | Improvement |
| :--- | :--- | :--- | :--- |
| **Total Cumulative Tokens Compressed** | `0` (empty `billion-context.json`) | **`1,100,000+` tokens** (`42` blocks `b1..b42`) | **97.3% history reduction** |
| **Tokens Sent to LLM per Turn (`sentTotal`)** | `~336,000` tok | **`27,955` tok** (`3%` of `1.0M` window) | **-91.7% per-turn wire cost** |
| **System Prompt Token Footprint (`sysprompt`)** | `~32,400` tok | **`13,645` tok** (`lean` pack + slim `AGENTS.md`) | **-57.9% static overhead** |
| **Active MCP Tool Schema Overhead** | `101` direct tool schemas (`~24,000` tok) | **`1` proxy gateway (`directTools: false`)** | **-96.5% MCP schema tokens** |
| **Prompt Cache Hit Ratio (`cacheHitPct`)** | Unpinned prefix | **`92%`–`94%` (`62.18M` / `67.77M` input tok)** | **`stableSystemAnchor: true`** |
| **External Auto-Fold Summary Offload** | Disabled (in-model manual only) | **Active (`⚡ext: preflight auto-fold`, `16.3k` target)** | **Zero main-model summary tax** |
| **Subagent Fleet Routing (`delegate`)** | Inherited expensive parent model (`argon`) | **Tiered OpenRouter (`deepseek-v3.2`, `gemini-3.1-flash-lite`, `qwen3-coder-next`)** | **85%–95% subagent cost reduction** |

---

## 2. Full Fractal Analysis ($L_0 \dots L_9$) of Token & Performance Bottlenecks

### 2.1 Paired Architecture & Dataflow Diagram (`SC-DIAGRAM-001`)

```text
[L9 Operator TUI and Cockpit] --> [L8 Sovereign Coordinator Pi Argon]
[L8 Sovereign Coordinator Pi Argon] --> [L4 L5 Billion Context Engine]
[L8 Sovereign Coordinator Pi Argon] --> [L7 Tiered Execution Fleet]
[L4 L5 Billion Context Engine] --> [L6 L3 Canonical MCP Gateway uos-harness]
[L7 Tiered Execution Fleet] --> [L6 L3 Canonical MCP Gateway uos-harness]
[L6 L3 Canonical MCP Gateway uos-harness] --> [L2 L1 L0 Guardrails KM Triad and Constitutional Gates]
```

```mermaid
flowchart TD
  L9["L9 Operator TUI and Cockpit"]
  L8["L8 Sovereign Coordinator Pi Argon"]
  L45["L4 L5 Billion Context Engine"]
  L7["L7 Tiered Execution Fleet"]
  L63["L6 L3 Canonical MCP Gateway uos-harness"]
  L210["L2 L1 L0 Guardrails KM Triad and Constitutional Gates"]

  L9 --> L8
  L8 --> L45
  L8 --> L7
  L45 --> L63
  L7 --> L63
  L63 --> L210
```

---

### 2.2 Ten-Layer ($L_0 \dots L_9$) Fractal Diagnostic & Implemented Controls

#### $L_0$ — Constitutional & Provenance Invariants (`SC-PROVENANCE-001`, `SC-SA-PLAN-001`, `SC-HARNESS-MCP-001`)
- **Finding**: Duplicate ancestor policy files (`/home/an/NAS-setup/AGENTS.md` and `/home/an/.pi/agent/AGENTS.md`) repeated the full 15.8 KB `/home/an/NAS-setup/uos/AGENTS.md` text three times in every prompt (`~12,000` wasted tokens per turn).
- **Fractal Implementation**:
  1. Archived duplicate `/home/an/NAS-setup/AGENTS.md` to `/home/an/NAS-setup/uos/var/backups/zero-muda-20261101/nas_setup_AGENTS.md.bak-20261102`.
  2. Slimmed `/home/an/.pi/agent/AGENTS.md` from `15,825` bytes to `1,588` bytes (90% reduction) while deferring strictly to `/home/an/NAS-setup/uos/AGENTS.md`.
  3. Enforced `EV-93` provenance ceiling (`INV-PROV-05`) and `sa-plan` execution exclusivity (`SC-SA-PLAN-001`).

#### $L_1$ — Execution Substrate & Tool Guardrails (`guardrails`)
- **Finding**: Unbounded `bash` commands or repetitive tool loops can emit 50 KB+ per call or spin on transient errors.
- **Fractal Implementation**:
  1. Configured top-level `guardrails` in `/home/an/.config/billion-context/billion-context.json`:
     - `bashTimeout: 60` seconds.
     - `maxOutputBytes: 32768` (32 KB hard ceiling before wire serialization).
     - `repetition: { enabled: true, warn: 3, abort: 5 }` to automatically trap and halt repetitive tool-call loops.

#### $L_2$ — Prompt Cache & Wire Transport Layer (`promptCache`, `stableSystemAnchor`, `cacheKeepalive`)
- **Finding**: Dynamic system prompt mutations or idle pauses (>5 minutes) invalidate upstream provider KV caches, causing full re-prefill billing on 30K–100K contexts.
- **Fractal Implementation**:
  1. Enabled `promptCache: { routing: "auto" }`, `stableSystemAnchor: true`, `affinitySimhash: true`, `subagentSplit: true`, `forkAdoption: true`, and `resumeInheritance: true`.
  2. Enabled `cacheKeepalive: { enabled: true, ttlFactor: 0.8, intervalMs: 240000 }` (4-minute keepalive heartbeat) to preserve the 92%+ KV cache hit rate across long compilation or Codex audit runs.

#### $L_3$ — Tool & File Read Interception Layer (`ccr` + `absorb` + `context-mode`)
- **Finding**: Reading a 400-line file (`~4,000` tokens) or running a test suite (`~6,000` tokens) previously stayed in the raw conversation history forever until manual compression.
- **Fractal Implementation**:
  1. **Context-Controlled Retrieval (`ccr`)**: Configured `ccr: { enabled: true, minToolTokens: 2500, maxHeadChars: 96 }`. Any `read` or tool output exceeding 2,500 tokens is automatically stored out-of-band by the proxy as `📦 [acp-stored #mXXXX · file read · N,NNN tok]` with on-demand retrieval via `acp_retrieve("mXXXX")`. (Verified live on `m01178`, where a 3,920-token file read was automatically stored in `0` wire tokens!).
  2. **Instant Tool-Result Absorption (`absorb`)**: Configured `absorb: { enabled: true, minToolTokens: 2500, contextThresholdPct: "15%", mediaOnly: false }` so large tool outputs above 15% context pressure trigger immediate distillation.
  3. **Sandbox Execution (`context-mode` + `codemode`)**: Enabled `npm:context-mode` (with skill filter `+skills/context-mode/SKILL.md`, `!skills/ctx-*` to avoid 6 redundant skill definitions) and `codemode` JS filtering so large JSON/log inspections return only distilled 5–10 line summaries.

#### $L_4$ — Autonomous Context Folding Engine (`compress` + `externalSummary`)
- **Finding**: Manual in-model `compress` calls consume the primary model's output tokens (`google/gemini-4-argon`) and only fire when the model chooses to call `compress`.
- **Fractal Implementation**:
  1. Lowered compression thresholds in `/home/an/.config/billion-context/billion-context.json`:
     - `nudgeGrowthTokens: 15000` (from `50000`)
     - `minPressureBenefitTokens: 2000`
     - `tierNudgeTokens: { t1: 12000, t2: 24000, t3: 48000 }`
     - `preserveRecentMessages: 2`, `preserveRecentTokens: 3000`, `minCompressRange: 2000`
  2. Configured **External Auto-Fold Summary Offload (`externalSummary`)** backed by named provider recipe `openrouter-fast` (`OPENROUTER_API_KEY` verified `configured`):
     - `enabled: true`, `autoFold: true`, `autoFoldTargetTokens: 16384`, `concurrency: 4`
     - Fallback target chain:
       1. `openrouter-fast/deepseek/deepseek-v4.1-flash`
       2. `openrouter-fast/google/gemini-3.1-flash-lite`
       3. `google/gemini-2.5-flash-lite`
       4. `google/gemini-2.5-flash`
  3. **Live Verification**: Blocks `b41` (`29k -> 752 tok ⚡ext: preflight auto-fold (growth)`) and `b42` (`1.6k -> 1.4k ⚡ext: preflight auto-fold (growth)`) folded automatically on the wire before the turn reached `google/gemini-4-argon`!

#### $L_5$ — Prompt Surface & Output Steering (`promptPack: "lean"`, `outputSteering`)
- **Finding**: The default `billion-context` prompt surface injects verbose instructions, and unsteered responses repeat code or tool outputs already visible in context.
- **Fractal Implementation**:
  1. Switched `compress.promptPack` from `"default"` to `"lean"`.
  2. Enabled `outputSteering: { enabled: true, verbosityLevel: 2, effortRouting: true }`, injecting `<bili_output_steering>` (`Skip preamble and postamble; start with the substance. Never restate code, file contents, diffs, or tool output that already appear in this conversation — reference them by path and line instead.`).
  3.Enabled `reasoningGuard: { enabled: true }` to prevent malformed reasoning blocks across subagent handoffs.

#### $L_6$ — Canonical MCP Gateway & Zero-Muda Skill Surface (`uos-harness`)
- **Finding**: Exposing all 101 UOS MCP tools directly (`directTools: true`) or running duplicate `uos-gleam` + `uos-harness` servers bloats every turn with tens of thousands of JSON schema tokens.
- **Fractal Implementation**:
  1. Consolidated to a single canonical MCP server `uos-harness` (`/home/an/NAS-setup/uos/tools/uos-mcp-stdio`) with `directTools: false` across `/home/an/NAS-setup/uos/.pi/mcp.json`, `/home/an/.pi/agent/mcp.json`, `/home/an/.pi/agent/mcp-adapter.json`, and `/home/an/NAS-setup/uos/var/core-evo/pi-home/{mcp.json,mcp-adapter.json}`.
  2. Verified `11/11` MCP config targets across Pi, AGY, Claude, and Codex are pinned to verified OTP 29 capsule `20261102-1620-a7b06b609fd26d53ca50d3451c2e4a4633df7dff2fb2e2f3faf2fd4ec59d6735` (`OBSERVED_CONSISTENT_PINS_ONLY`).
  3. Pruned global/ancestor duplicate skill directories so exactly the **28 canonical `uos-core-evo` skills** load metadata-only on startup.

#### $L_7$ — Multi-Agent Symbiosis & Subagent Delegation Fleet (`pi.subagents` + `acp.json` + Claude/Codex)
- **Finding**: Using `google/gemini-4-argon` for file exploration, routine test runs, or code synthesis wastes high-cost supervisor tokens. Furthermore, without explicit role-model bindings in `acp.json` / `billion-context.json`, `delegate` subagents inherit the parent model (`google/gemini-4-argon`).
- **Fractal Implementation**:
  1. Configured `/home/an/.pi/acp.json`, `/home/an/NAS-setup/uos/.pi/acp.json`, `/home/an/NAS-setup/uos/var/core-evo/pi-home/acp.json`, and `pi.subagents` in `/home/an/.config/billion-context/billion-context.json`:
     - **`worker`** (`thinkingLevel: "low"`): `openrouter/deepseek/deepseek-v3.2` — bounded implementation, test execution, and log inspection.
     - **`researcher`** (`thinkingLevel: "low"`): `openrouter/google/gemini-3.1-flash-lite` — fast 1M-context repository search and evidence gathering.
     - **`reviewer`** (`thinkingLevel: "medium"`): `openrouter/qwen/qwen3-coder-next` — fast code & diff pre-review.
     - **`planner` / `oracle`** (`thinkingLevel: "medium"`): `openrouter/deepseek/deepseek-v3.2` — bounded architectural & failure analysis.
  2. Established the **4-Tier Sovereign Execution Division of Labor**:
     - **Tier 1 — Supervisor & Coordinator (`Pi + google/gemini-4-argon`)**: High-level orchestration, `Sa-plan` task claiming/completion, risk preflight/active-check, and final synthesis only.
     - **Tier 2 — Fast Task/Job Workers (`Pi Subagents via OpenRouter: DeepSeek V3.2 / V4.1-Flash, Gemini 3.1 Flash Lite, Qwen3-Coder-Next`)**: Parallel exploration, bounded checks, and background auto-fold summarization.
     - **Tier 3 — Deep Implementation & Refactoring (`Claude Code CLI: claude -p`)**: Multi-file Erlang/Gleam/OCaml/Zig implementation and EUnit/test fixing in isolated subprocesses (consuming 0 tokens in Pi's main window).
     - **Tier 4 — Sovereign Verification Gate (`Codex CLI: codex exec --sandbox read-only`)**: Independent revision-bound sovereign audits (`Gate v11 PASS`).

#### $L_8$ — Knowledge Management Triad Brain-Memory Discipline (`SC-MCP-KM-BRAIN-001`)
- **Finding**: Broad grep/find scans across `docs/` and `governance/` consume 20K–50K tokens when recalling prior architecture decisions.
- **Fractal Implementation**:
  1. Standardized preflight KM recall via `mcp__uos_harness__knowledge_search` with `limit: 5` and bounded `mcp__uos_harness__zk_transclude`, reading at most the top 1–2 relevant documents.

#### $L_9$ — Operator Telemetry, HUD & Paste-Buffer Hygiene (`pi-powerline-footer`, `@narumitw/pi-usage`)
- **Finding**: Accidental terminal paste of footer status lines (`menu│` with 18K spaces) or invisible unmonitored context growth degrades UX and wastes tokens.
- **Fractal Implementation**:
  1. Active real-time token/cache HUD via `npm:pi-powerline-footer`, `npm:@narumitw/pi-usage`, and `http://127.0.0.1:18787/__bili/#/session/<session_id>`.
  2. Live proxy telemetry endpoint (`GET http://127.0.0.1:18787/__bili/plugin/status?conversationId=<PI_SESSION_ID>`) verified and callable from `codemode` for zero-cost programmatic compression checks.

---

## 3. Concrete Configuration Files Applied & Verified

| Layer | File Path | Role & Key Parameters Applied |
| :--- | :--- | :--- |
| $L_1..L_5$ | `/home/an/.config/billion-context/billion-context.json` (mirrored to [`var/core-evo/billion-context/billion-context.json`](http://nas-1.tail55d152.ts.net:4100/files/var/core-evo/billion-context/billion-context.json)) | `promptPack: "lean"`, `nudgeGrowthTokens: 15000`, `ccr` (`2500` tok), `absorb` (`2500` tok, `15%`), `outputSteering` (`level: 2`), `externalSummary` (`autoFold: true`, `16384` tok target via `openrouter-fast`), `cacheKeepalive`, `guardrails` (`32KB` max output, `60s` timeout, repetition trap). |
| $L_7$ | `/home/an/.pi/acp.json`, [`/home/an/NAS-setup/uos/.pi/acp.json`](http://nas-1.tail55d152.ts.net:4100/files/.pi/acp.json), [`var/core-evo/pi-home/acp.json`](http://nas-1.tail55d152.ts.net:4100/files/var/core-evo/pi-home/acp.json) | `delegate` subagent fleet routing (`worker` -> `openrouter/deepseek/deepseek-v3.2`, `researcher` -> `openrouter/google/gemini-3.1-flash-lite`, `reviewer` -> `openrouter/qwen/qwen3-coder-next`, `notifyIfRead: "skip"`, `thinkingLevel: "low"`). |
| $L_3, L_9$ | `/home/an/.pi/agent/settings.json`, [`var/core-evo/pi-home/settings.json`](http://nas-1.tail55d152.ts.net:4100/files/var/core-evo/pi-home/settings.json) | Enabled `npm:billion-context`, `npm:context-mode` (`+skills/context-mode/SKILL.md`, `!skills/ctx-*`), `npm:@narumitw/pi-usage`, `npm:pi-powerline-footer`. |
| $L_6$ | [`/home/an/NAS-setup/uos/.pi/mcp.json`](http://nas-1.tail55d152.ts.net:4100/files/.pi/mcp.json), `/home/an/.pi/agent/mcp.json`, `/home/an/.pi/agent/mcp-adapter.json`, [`var/core-evo/pi-home/mcp.json`](http://nas-1.tail55d152.ts.net:4100/files/var/core-evo/pi-home/mcp.json) | Sole canonical `uos-harness` MCP server (`directTools: false`) pinned to capsule `20261102-1620-a7b06b609fd26d53ca50d3451c2e4a4633df7dff2fb2e2f3faf2fd4ec59d6735`. |
| $L_0$ | `/home/an/.pi/agent/AGENTS.md` | Slimmed to `1,588` bytes (Zero-Muda Core-Evo profile) deferring to [`/home/an/NAS-setup/uos/AGENTS.md`](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md). |

---

## 4. Standardized Operating Protocol for Maximum Token Efficiency

1. **Argon Coordinates, Fleet Executes**:
   - Keep `google/gemini-4-argon` strictly on high-level planning, `Sa-plan` state transitions, and final verification synthesis.
   - Delegate bounded exploration/checks to `delegate` subagents (`worker` = `deepseek-v3.2`, `researcher` = `gemini-3.1-flash-lite`, `reviewer` = `qwen3-coder-next`).
   - Delegate multi-file code implementation and test iteration to `claude -p --dangerously-skip-permissions` and sovereign read-only verification to `codex exec --sandbox read-only`.
2. **Filter Large Outputs in `codemode` Before Returning**:
   - Never dump full multi-thousand-line files or logs into stdout; filter in JavaScript inside `codemode` or let `ccr` (`>2,500` tokens) store them out-of-band (`#mXXXX`).
3. **Automatic & Programmatic Folding**:
   - Let `externalSummary` (`autoFold: true`, `autoFoldTargetTokens: 16384`) fold completed tool chains automatically via `openrouter-fast/deepseek/deepseek-v4.1-flash` and `google/gemini-3.1-flash-lite`.
   - When switching major task phases, invoke `POST http://127.0.0.1:18787/__bili/plugin/tool` (`tool: "compress"`) to fold completed phase ranges down to ~300-token blocks.

---

## 5. Comprehensive Verification Checklist (`SC-CHECKLIST-001` + Domain 6 Provenance)

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Synchronized host UTC clock observed (`20261102-1810-` prefix applied).
- [x] **CHK-02-TAIL** — Full clickable `http://nas-1.tail55d152.ts.net:4100/...` links embedded across all artifact references.
- [x] **CHK-03-FRACT** — Canonical `#fractal-l0`..`#fractal-l9`, `#km-triad`, and `#zero-muda` tags and 10-layer mapping provided.
- [x] **CHK-04-KM** — Bound to canonical KM triad (`uos://km/triad` healthy) and evidence receipt [`var/evidence/20261102-1810-pi-fractal-compression-optimization-receipt.json`](http://nas-1.tail55d152.ts.net:4100/files/var/evidence/20261102-1810-pi-fractal-compression-optimization-receipt.json).

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] **CHK-05-MUDA** — Verified `0 Bevy`, `0 Graphite`, and `0` non-UOS MCP servers in active configurations.
- [x] **CHK-06-GRAPH** — Paired ASCII + Mermaid architecture diagram (`§2.1`) provided and verified via `tools/diagram-check`.
- [x] **CHK-07-DRIVE** — Storage safety interlock (`HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"`) untouched and preserved.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [x] **CHK-08-C1C8** — Live proxy status endpoint `/__bili/plugin/status` and `/__bili/config` verified (`ok: true`, `parseError: undefined`).
- [x] **CHK-09-MATH** — Verified wire token compression from `~336,000` tok to `27,955` tok (`91.7%` reduction) and `92%` cache hit rate.
- [x] **CHK-10-9MOD** — Verified `ccr` out-of-band storage (`#m01178`), `externalSummary` auto-fold (`b41`, `b42`), and `ecology_release.ml audit-pins` (`11/11` `OBSERVED_CONSISTENT_PINS_ONLY`).
- [x] **CHK-11-REGR** — Verified `tools/diagram-check` on this plan (`PASS`).

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [x] **CHK-12-GLEAM** — Verified `uos-harness` (`OTP 29`, `ERTS 17.0.5`) `system_health` (`status: "healthy"`).
- [x] **CHK-13-HERMES** — Verified `ecology_release.ml audit-pins` across all 11 host/workspace MCP targets.
- [x] **CHK-14-ZIGVM** — Verified ZigVM VFS and capsule binary integrity untouched.
- [x] **CHK-15-MAX** — Isolated MAX inference boundary preserved.
- [x] **CHK-16-OTEL** — Billion-context proxy telemetry (`http://127.0.0.1:18787/__bili/stats`) and session metrics verified.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [x] **CHK-17-SOV** — Enforces 4-tier division of labor (Pi+Argon coordinator, OpenRouter DeepSeek/Gemini/Qwen subagents, Claude Code implementation, Codex sovereign verification).
- [x] **CHK-18-JJ** — Standalone Jujutsu (`.jj/`) repository discipline preserved (`0` git mutations).

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

`admitted_ev_ceiling = 93` (`SC-PROVENANCE-001`). `EV-94..EV-109` and `ADR-071..ADR-086` remain `NOT_ADMITTED`. Zero new EV numbers minted (`INV-PROV-05`).

</details>

[Previous: FPP/SysML Autonomous Fractal Execution Prompt](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1326-fpp-sysml-autonomous-fractal-execution-prompt.md) · [Next: FPP-4 Restart & Handover Checkpoint](http://nas-1.tail55d152.ts.net:4100/files/docs/handover/20261102-1514-pi-argon-fpp4-restart-checkpoint.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)
