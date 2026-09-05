# C3I Gleam-First System — Gemini Guidance (v22.10.1-PI-SYMBIOSIS)

**Master Architecture Matrix**: See `docs/architecture/FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md` for comprehensive mapping of offline voice, chat components, Zenoh, observability, logging, and formal specs across all L0-L7 fractal layers.

## §1.0 System Identity & Mandate

**C3I is a Gleam-first cybernetic command-and-control cockpit for distributed mesh orchestration.**

- **Primary Language**: Gleam (type-safe, BEAM VM, hot reload)
- **UI Framework**: Lustre 5.6+ MVU (server-side rendered, no JavaScript)
- **API Framework**: Wisp 2.2.2 (HTTP/JSON)
- **Terminal UI**: ANSI renderer + Split-Screen TUI
- **Telemetry Bus**: Zenoh pub/sub mesh with OTel span publishing
- **Backend Integration**: Elixir/Phoenix (legacy, maintained for backwards compatibility)
- **Compute Bridge**: F# CEPAF (biomorphic synthesis, FMEA generation, formal verification)

The system uses a **Penta-Stack** architecture:
1. Gleam Lustre WebUI (port 4100)
2. Gleam Wisp REST API (port 4100)
3. Gleam TUI (ANSI terminal + Split-Screen dashboard)
4. Elixir Phoenix LiveView (port 4000, legacy)
5. F# Prajna CLI (fallback)

---

## §2.0 Penta-Stack Architecture

Every UI capability MUST be simultaneously available across all 3 Gleam interfaces. Types are shared from `ui/domain.gleam`; no per-interface duplication.

| Layer | Tech | Port | Purpose | Path |
|-------|------|------|---------|------|
| **Web UI** | Lustre 5.6+ MVU | 4100 | Server-rendered HTML, no client JS | `ui/lustre/*.gleam` |
| **REST API** | Wisp 2.2.2 HTTP | 4100 | Typed JSON endpoints | `ui/wisp/*.gleam` |
| **Terminal UI** | ANSI + Split-Screen | CLI | Dashboard with sparklines + test results | `ui/tui/*.gleam` |
| **Legacy Web** | Phoenix LiveView | 4000 | Backward compatibility | `lib/indrajaal_web/live/` |
| **CLI Fallback** | F# Console | CLI | Safety kernel, dark cockpit | `lib/cepaf/` |

---

## §2.5 Zenoh OTel Integration

All 15 UI pages publish OpenTelemetry spans via `ui/zenoh_otel.gleam` for every state change.
OTel spans are transported over Zenoh topics `indrajaal/otel/spans/**` for distributed tracing.

**Module**: `ui/zenoh_otel.gleam` — OTel span context propagation, span builder, Zenoh publisher
**Test Observer**: `testing/zenoh_test_observer.gleam` — Zenoh message verification during tests
**Topics**: `indrajaal/otel/spans/{page}/{operation}`, `indrajaal/test/zenoh/observe/**`

---

## §2.6 Zenoh-MCP-OTel Fractal Backplane (ZMOF) (NEW)

**Mandate**: SC-ZMOF-001 — Zenoh is the SOLE transport for internal mesh communication, observability (OTel), and AI tool calls (MCP).

**Fractal Namespace**:
- L0 Constitutional: `indrajaal/l0/const/**`
- L1 Atomic/NIF: `indrajaal/l1/atomic/**`
- L2 Health/Quorum: `indrajaal/l2/health/**`
- L4 System/Podman: `indrajaal/l4/system/**`
- L5 Cog/OODA/Rules: `indrajaal/l5/cog/**`

**Protocols**:
- **OoZ (OTel-over-Zenoh)**: Publish spans to `indrajaal/otel/span/{layer}/{entity_id}`.
- **MoZ (MCP-over-Zenoh)**: Layer JSON-RPC over Zenoh Pub/Sub for tool requests (`.../mcp/req/{tool}/{id}`) and responses (`.../mcp/res/{id}`).

---

## §3.0 Triple-Interface Mandate (SC-GLM-UI-001)

Every new page, dashboard, or interactive component MUST be implemented THREE times:

**Requirement**: A single feature = 1 Lustre page + 1 Wisp endpoint + 1 TUI view.

**Canonical Rule**: Before marking a feature "done," verify:
```
✓ Lustre page renders without client JS
✓ Wisp endpoint returns typed JSON (no string concat)
✓ TUI view displays terminal output (ANSI codes OK)
✓ All three share types from ui/domain.gleam
✓ OTel spans published via zenoh_otel (SC-GLM-ZEN-001)
✓ State changes published to fractal Zenoh namespace (SC-ZMOF-001)
✓ Feature exposed as an MoZ tool if actionable (SC-ZMOF-005)
✓ Code compiles with ZERO warnings and no dead code (SC-MUDA-001)
```

**Consequences of omission**: Feature is 67% incomplete (only 1/3 interface) and lacks ZMOF backplane integration.

---

## §3.5 Muda Waste Reduction Protocol (NEW)
**Mandate**: SC-MUDA-001 — The system MUST be maintained with zero compilation warnings and active elimination of "Muda" (waste).
See `.claude/rules/muda-waste-reduction.md` for the 7 Wastes of Software Engineering and the exact enforcement constraints.

## §3.6 Effect TypeScript + Full IIFE Collapse (Operator-Gated H-Risk)
**Mandate**: all TypeScript generated or modified by users/agents MUST use Effect (`effect`) as the functional runtime and standard library. Browser/runtime JavaScript behavior MUST be authored in Effect TypeScript and shipped via IIFE bundles.

Authoritative rules:
- `.gemini/rules/effect-ts-universal.md` — all TypeScript, all agents
- `.gemini/rules/effect-ts-only-js.md` — browser/runtime JS + IIFE collapse

Required constraints:
- SC-EFFECT-TS-001..007
- SC-EFFECT-TS-008..020
- No `fp-ts` for generated/agent-authored TypeScript; migrate touched `fp-ts` to Effect
- Internal async/IO must stay in `Effect.Effect<A, E, R>` until compatibility edges
- Full IIFE collapse for H-risk paths
- No new raw `.js` logic; legacy JS is migration-only and must trend toward Effect TS

## §3.7 fp-core Rust Functional Mandate (Operator-Gated H-Risk)
**Mandate**: all Rust generated or modified by users/agents MUST use `fp-core` functional abstractions where applicable and target >=95% functional style in touched Rust logic.

Authoritative rule: `.gemini/rules/fp-core-rust-universal.md`.

Required constraints:
- SC-FP-RUST-001..020
- Add `fp-core = "0.1.9"` to touched Rust crates when functional Rust logic is modified and dependency addition is allowed
- Use pure functions, iterator combinators, folds, `Option`/`Result`, `fp_core` traits/modules, and isolated IO/FFI boundaries
- No new `unwrap`, `expect`, or `panic!` paths in generated runtime Rust

## §3.7.1 Safe Rust X-Safety Mandate (Operator-Gated H-Risk)
**Mandate**: all Rust generated or modified by users/agents MUST be safe-by-construction. Encode domain, protocol, concurrency, serialization, authorization, parsing, and resource-state invariants so invalid programs fail to compile wherever practical.

Authoritative rule: `.gemini/rules/safe-rust-x-safety.md`.

Required constraints:
- SRXS-001..012
- Define invariants on types, traits, lifetimes, const generics, capability tokens, typestates, or sealed module boundaries
- Enforce invariants at construction and mutation boundaries with private fields, smart constructors, checked conversions, RAII guards, exhaustive enums, and local unsafe wrappers
- Consume invariants only through APIs whose signatures prove preconditions are satisfied
- Treat new `unsafe` as a proof boundary requiring `SAFETY:` docs, safe wrappers, and focused tests or verification

## §3.8 Functional Runtime Supervisor (Operator-Gated H-Risk)
**Mandate**: mixed TypeScript/Rust/runtime-governance work MUST use the multilayer supervisor state to keep Claude, Gemini, Pi-mono, Codex/GPT, rules, skills, agents, and hooks synchronized.

Authoritative supervisor: `.gemini/agents/functional-runtime-supervisor.md`.

Required constraints:
- Use `.gemini/skills/effect-ts-architect/SKILL.md` for Effect TypeScript design
- Use `.gemini/skills/fp-core-rust-architect/SKILL.md` for fp-core Rust design
- Use `.agents/skills/functional-runtime-supervisor/SKILL.md` for OpenCode/Codex-compatible routing
- Keep `.gemini`, `.claude`, `.agents`, `/home/an/.codex`, and `sub-projects/pi-mono` mirrors in parity

---

## §4.0 Build & Test Commands

### Canonical Compile (SC-ENV-COMPILE)
```bash
NO_TIMEOUT=true \
PATIENT_MODE=enabled \
SKIP_ZENOH_NIF=0 \
WALLABY_ENABLED=true \
ELIXIR_ERL_OPTIONS="+fnu +S 16:16 +SDio 16" \
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 \
mix compile --jobs 16
```

### Gleam Build
```bash
cd lib/cepaf_gleam
gleam build
```

### Gleam Test
```bash
cd lib/cepaf_gleam
gleam test
```

### Split-Screen Test Cycle (NEW)
```bash
./scripts/run-split-screen-tests.sh
```
Runs 10-minute test cycle with split-screen TUI: dashboard + test results simultaneously.
15 tabs × 8 fractal layers × 381 comprehensive regression tests.

### Wallaby E2E (Gleam UI coverage)
```bash
WALLABY_ENABLED=true \
SKIP_ZENOH_NIF=0 \
NO_TIMEOUT=true \
PATIENT_MODE=enabled \
ELIXIR_ERL_OPTIONS="+fnu +S 16:16 +SDio 16" \
HEALTH_PORT=4051 \
MIX_ENV=test mix test --only wallaby
```

---

## §5.0 AG-UI 32-Event Protocol (SC-AGUI)

**AG-UI** is the event bus connecting agents (Gemini, Gemini, external) to the Gleam UI.

All events defined in `agui/events.gleam` (5 modules, 1,224 lines):

| Category | Count | Events |
|----------|-------|--------|
| Lifecycle | 5 | RunStarted, RunFinished, RunError, StepStarted, StepFinished |
| Text | 4 | TextMessageStart, TextMessageContent, TextMessageEnd, TextMessageChunk |
| Tool | 5 | ToolCallStart, ToolCallArgs, ToolCallEnd, ToolCallResult, ToolCallChunk |
| State | 3 | StateSnapshot, StateDelta (RFC 6902), MessagesSnapshot |
| Activity | 2 | ActivitySnapshot, ActivityDelta |
| Reasoning | 7 | ReasoningStart, ReasoningMessageStart/Content/End/Chunk, ReasoningEnd, ReasoningEncryptedValue |
| Special | 4 | Raw, Custom, MetaEvent, Heartbeat |
| **TOTAL** | **32** | — |

**Modules**: `events.gleam` (582 lines), `state.gleam` (268), `tools.gleam` (231), `sse.gleam` (84), `zenoh_bus.gleam` (59), `event_stream_widget.gleam` (isomorphic HTML+ANSI event log)

**Transport**: Lustre server components (WebSocket) + Wisp REST (JSON) + Zenoh PubSub (telemetry) + OTel spans (zenoh_otel).

**MCP Tools** (26 total, all NIF-backed via `c3i_nif`):
- Planning (7): plan_status, plan_list_pending, plan_list, plan_get, plan_add, plan_update, plan_search
- System (5): system_health, system_dashboard, system_immune, system_zenoh, system_verification
- Knowledge (2): knowledge_search, verification_run
- Domain (11): podman_containers, metabolic_state, ooda_phase, ooda_decide, fractal_status, prajna_health, dark_cockpit_mode, integrity_check, evolution_metrics, mesh_topology, kms_catalog
- Utility (1): read_file

---

## §6.0 A2UI Declarative Catalog (SC-A2UI)

**A2UI** is the component schema system for agents. No executable code, JSON-only.

**233 Component Types** across 5 modules (1,800+ lines):
- `schema.gleam` (118 lines) — ComponentSpec, PropSpec, BindingSpec, FractalLayer types
- `catalog.gleam` (500+ lines) — Trusted registry: 233 components across 22 domains (15 core + 100 wave1 + 118 wave2)
- `renderer.gleam` (300+ lines) — Isomorphic A2UI → HTML + JSON + ANSI rendering (render_tripartite)
- `bindings.gleam` (88 lines) — Data binding (state path → component prop)
- `validator.gleam` (119 lines) — Security validation (allowlist enforcement)

**Pattern**: Agent → (A2UI JSON spec) → Validator → Renderer → {Lustre HTML, Wisp JSON, TUI ANSI}.

---

## §7.0 Fractal Widget Architecture (L0-L7)

Each fractal layer has a dedicated widget module in `fractal/`:

| Layer | Module | Lines | Purpose | HITL |
|-------|--------|-------|---------|------|
| L0 | `l0_constitutional.gleam` | 176 | Guardian approval, emergency stop, Psi invariants (Psi-0..5, Omega-0) | Mandatory |
| L1 | `l1_atomic_debug.gleam` | 118 | Debug trace viewer, event monitor, state inspections | Optional |
| L2 | `l2_component.gleam` | 112 | Reusable forms, data grids, badges, buttons, inputs | No |
| L3 | `l3_transaction.gleam` | 144 | State diff viewer, tool invocation panel, command history | Optional |
| L4 | `l4_system.gleam` | 202 | Agent run monitor, step tracker, execution timeline | Optional |
| L5 | `l5_cognitive.gleam` | 149 | Reasoning display, OODA ring, AI copilot panel | Optional |
| L6 | `l6_ecosystem.gleam` | 105 | Agent mesh topology, A2A messaging, collaboration | Optional |
| L7 | `l7_federation.gleam` | 101 | Gateway, version vectors, federated reconciliation, SIL-6 sync | Optional |

**Total**: 8 modules, 1,107 lines.

---

## §8.0 Testing Gold Standard (C1-C8)

All Gleam UI code MUST achieve **8-category gold standard coverage**:

| Category | Weight | Gate | Check |
|----------|--------|------|-------|
| C1 Page Structure | 1.0 | Renders without error | Lustre element count ≥ 5 |
| C2 Status Badges | 1.5 | All states visible | Healthy/Degraded/Critical all shown |
| C3 Data Grids | 1.0 | Rows render | ≥ 3 rows × ≥ 3 columns |
| C4 Timeline | 0.8 | Events in order | Timestamp validation |
| C5 Interactive | 1.2 | Buttons work | Click → state change |
| C6 Media/Rich | 0.8 | Assets load | SVG/PNG verified |
| C7 AI Advisory | 1.5 | AG-UI events flow | E2E Zenoh publish verified |
| C8 Action Button | 3.0 | Safety gates pass | Guardian approval + 2oo3 consensus |

**Math Gates** (ALL must pass):
- Shannon Entropy H ≥ 2.5 bits
- Cyclomatic Complexity CCM ≥ 90%
- Expected vs Actual Divergence D_EA ≤ 10%
- Integrated Test Quality Score ITQS ≥ 0.85

### §8.1 Comprehensive Regression Suite (NEW)

**Test file**: `test/comprehensive_ui_regression_test.gleam`
- **381 tests** covering all 15 tabs × 8 fractal layers
- **100% tab coverage** — every tab verified
- **Zenoh message verification** via `testing/zenoh_test_observer.gleam`
- **OTel span validation** via `ui/zenoh_otel.gleam`
- **30+ second monitoring** per tab during verification (SC-GLM-TST-002)

### §8.2 Test Metrics (Current)

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Total Tests | 9,055 passed, 1 pre-existing | — | PASS |
| Shannon Entropy H | 2.67 bits (weighted mean) | ≥ 2.5 bits | PASS |
| CCM | 0.770 | ≥ 0.90 | IMPROVING |
| ITQS | 0.736 | ≥ 0.85 | IMPROVING |
| D_EA | — | ≤ 10% | — |
| Tab Coverage | 100% (31/31) | 100% | PASS |
| Nav Graph Pages | 31 (SCC=1, edges=930) | 31 | PASS |
| A2UI Components | 233 | — | PASS |
| MCP Tools | 93 federated (6 Gemini + 14 Pi + 73 C3I) | — | PASS |
| Pi Bridge Modules | 6 (agent/zenoh/tools/session/provider/claude_code) | 6 | PASS |
| Source Warnings | 0 (132 in test files only) | 0 src | PASS |
| Videos/Screenshots | 5 videos + 6 screenshots | — | PASS |
| Zenoh Observer | 31 pages | 31 | PASS |
| Zenoh Verification | Active | — | PASS |

---

## §9.0 Key File Locations

| Subsystem | Files | Lines | Path |
|-----------|-------|-------|------|
| Domain types | 1 | 166 | `lib/cepaf_gleam/src/cepaf_gleam/ui/domain.gleam` |
| Lustre Web UI | 24 | 3,415 | `lib/cepaf_gleam/src/cepaf_gleam/ui/lustre/*.gleam` |
| Wisp REST API | 15 | 2,278+ | `lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/*.gleam` |
| TUI Terminal | 23 | 1,730+ | `lib/cepaf_gleam/src/cepaf_gleam/ui/tui/*.gleam` |
| Zenoh OTel | 1 | — | `lib/cepaf_gleam/src/cepaf_gleam/ui/zenoh_otel.gleam` |
| AG-UI Events | 6 | 1,400+ | `lib/cepaf_gleam/src/cepaf_gleam/agui/*.gleam` |
| A2UI Catalog | 5 | 1,800+ | `lib/cepaf_gleam/src/cepaf_gleam/a2ui/*.gleam` (233 components) |
| Fractal L0-L7 | 8 | 1,107 | `lib/cepaf_gleam/src/cepaf_gleam/fractal/*.gleam` |
| Unified NIF | 7 | 725 | `lib/cepaf_gleam/native/c3i_nif/src/*.rs` (14 NIFs) |
| NIF Bridge | 2 | 120 | `lib/cepaf_gleam/src/{c3i_nif.erl,cepaf_gleam/c3i/nif.gleam}` |
| MoZ Transport | 3 | 280+ | `lib/cepaf_gleam/src/cepaf_gleam/moz/*.gleam` |
| Testing | 4 | 602+ | `lib/cepaf_gleam/src/cepaf_gleam/testing/*.gleam` |
| Zenoh Test Observer | 1 | — | `lib/cepaf_gleam/src/cepaf_gleam/testing/zenoh_test_observer.gleam` (30 pages) |
| Test Dashboard | 1 | — | `lib/cepaf_gleam/src/cepaf_gleam/testing/test_dashboard.gleam` |
| Verification | 4 | 383 | `lib/cepaf_gleam/src/cepaf_gleam/verification/*.gleam` |
| **Test suite** | **70** | **18,000+** | `lib/cepaf_gleam/test/*_test.gleam` |
| Rust Cortex Daemon | 31 | 9,104 | `sub-projects/c3i/native/planning_daemon/src/*.rs` |
| Gleam Cortex | 1 | ~300 | `lib/cepaf_gleam/src/cepaf_gleam/agents/cortex.gleam` |
| Gleam Gateway | 3 | 183 | `lib/cepaf_gleam/src/cepaf_gleam/gateway/*.gleam` |
| Planning modules | 16 | 5,483 | `lib/cepaf_gleam/src/cepaf_gleam/planning/*.gleam` |
| Podman modules | 7 | 1,304 | `lib/cepaf_gleam/src/cepaf_gleam/podman/*.gleam` |
| Pi-mono bridge | 6 | 1,500+ | `lib/cepaf_gleam/src/cepaf_gleam/bridge/pi_*.gleam` |
| Pi-mono (TypeScript) | 7 pkg | 106,577 | `sub-projects/pi-mono/packages/` |
| Pi runtime bridge | 2 | 700+ | `lib/cepaf_gleam/src/cepaf_gleam/bridge/pi_runtime.gleam`, `pi_rpc.gleam` |
| Pi runtime tests | 1 | 350+ | `lib/cepaf_gleam/test/pi_runtime_test.gleam` |
| Video recording | 1 | 200+ | `scripts/xvfb-record.sh` |
| **TOTAL** | **293+** | **~43,000+ Gleam + 106K TS** | — |

---

## §10.0 Active Constraints Cross-Reference

Full constraint registry (2,257 SC-* / 480 AOR-* at parity): `.claude/rules/constraint-registry.md`

Key Gleam UI families: SC-GLM-UI(10) SC-AGUI(10) SC-A2UI(8) SC-UIGT(10) SC-HINT(8) SC-MATH-COV(6) SC-HMI(80) SC-VER(79) SC-FRACTAL(8) SC-PROM(7) SC-GLM-ZEN(3) SC-GLM-TST(2) SC-PI-AUTO(8) SC-VERIFY-VISUAL(6) **SC-VAULT(25)** **SC-VAULT-CRYPTO(1)** **AOR-VAULT(15)**

### Secrets Vault (SC-VAULT family — task `urn:c3i:task:misc:116494073339521648`)

RustyVault NIF inside `lib/cepaf_gleam/native/rusty_vault_nif/` providing local-first sealed K/V vault with western crypto only (no Tongsuo SM2/SM3/SM4), variable per-secret TTL via `secret_policy` table in Smriti.db, GCP Secret Manager + Cloud KMS as cloud DR root, 1-week internet-outage tolerance.

| Constraint | Severity | Purpose |
|---|---|---|
| SC-VAULT-001 | INFINITE | Vault sealed at process start |
| SC-VAULT-002 | INFINITE | KEK never plaintext on disk |
| SC-VAULT-003 | INFINITE | Reads via vault.gleam typed wrapper only |
| SC-VAULT-004 | INFINITE | No plaintext API-key shapes in committed files (pre-commit hook ARMED) |
| SC-VAULT-005 | INFINITE | Hot path no network calls |
| SC-VAULT-006 | INFINITE | Hard-stale (age >= max_ttl) MUST fail-closed |
| SC-VAULT-CRYPTO-001 | INFINITE | No Tongsuo / SM2/SM3/SM4 in dependency tree (`cargo tree | grep -i tongsuo` empty) |
| SC-VAULT-007..025 | CRITICAL/HIGH | KEK chain, audit, sync, region, IAM, rotation policy |

**RETE-UL rules**: 12 across 2 domains (`secret_freshness` 7, `vault_integrity` 5) in `lib/cepaf_gleam/src/cepaf_gleam/rules/engine.gleam`.

**Formal specs**:
- `specs/tla/RustyVaultIntegration.tla` (170 LOC) — 7 invariants + 2 liveness
- `specs/agda/VaultStateMachine.agda` (140 LOC) — type-level proof: Sealed → ¬PlaintextAccessible
- `specs/allium/secrets_vault.allium` (270 LOC) — 8 entities + 12 rules + 5 contracts + 7 invariants

**Oban schedules** (4): `vault_sync` (5min), `vault_audit_reconcile` (daily 02:00), `vault_kek_rotation_check` (weekly Sun 03:00), `vault_policy_audit` (daily 04:00).

**Triple-interface** (per SC-GLM-UI-001):
- Lustre: `ui/lustre/secrets_vault.gleam` (Andon dashboard tile, 30s refresh)
- Wisp REST: `ui/wisp/secret_api.gleam` + `/api/v1/secret-status` route
- TUI: `ui/tui/secrets_vault_view.gleam` (ANSI box-drawn)

**Pre-commit hook** (Jidoka): `.claude/scripts/vault-precommit-secret-scan.sh` chained into `.git/hooks/pre-commit`. 7 API-key shape regexes; placeholder skip works.

**Doc pack**: `docs/journal/task-116494073339521648/` (12 PNG diagrams + journal + 5-level RCA + TPS countermeasures + fractal criticality matrix + 7-phase test plan + 5 slice continuation plans + analysis HTML + slide deck + links manifest).

**Rule**: `.claude/rules/secrets-vault.md` + `.gemini/rules/secrets-vault.md` parity.



### Wiring Guard Protocol (SC-WIRE — MANDATORY)

**ALL Model type changes MUST update `testing/wiring_guard.gleam` FIRST.**

| ID | Constraint | Severity |
|----|-----------|----------|
| SC-WIRE-001 | wiring_guard.gleam MUST compile before any test | CRITICAL |
| SC-WIRE-002 | Adding a Model field MUST update wiring_guard.gleam in SAME commit | CRITICAL |
| SC-WIRE-003 | Adding a Msg variant MUST update update() in SAME commit | CRITICAL |
| SC-WIRE-007 | Tests MUST use init() constructors, NOT direct Model() constructors | HIGH |

**Verified connections**: 95 (33 page inits + 32 events + 6 models + 21 roundtrips + 3 strict invariants)
**File**: `testing/wiring_guard.gleam` | **Tests**: `test/wiring_guard_test.gleam` (13 tests)
**Rule**: `.claude/rules/wiring-guard.md`

### New STAMP Constraints (v22.5.0-CORTEX)

| ID | Constraint | Severity |
|----|------------|----------|
| SC-GLM-ZEN-001 | All UI state changes MUST publish OTel spans via zenoh_otel | CRITICAL |
| SC-GLM-ZEN-002 | Test runner MUST observe Zenoh messages for verification | CRITICAL |
| SC-GLM-ZEN-003 | Split-screen TUI MUST display dashboard + test results simultaneously | HIGH |
| SC-GLM-TST-001 | 100+ regression tests required per release | CRITICAL |
| SC-GLM-TST-002 | Each tab monitored for 30+ seconds during verification | HIGH |

### New STAMP Constraints (v22.10.1-PI-SYMBIOSIS)

| ID | Constraint | Severity |
|----|------------|----------|
| SC-PI-AUTO-001 | Every new Gleam module MUST check Pi bridge compatibility | HIGH |
| SC-PI-AUTO-002 | Every feature MUST update pi_claude_code.gleam if adding tools/events | CRITICAL |
| SC-PI-AUTO-003 | Tool federation count (93) MUST be verified after every feature | HIGH |
| SC-PI-AUTO-004 | Event bridge mapping MUST be verified after AG-UI changes | HIGH |
| SC-VERIFY-VISUAL-001 | Screenshots MUST be captured for every HTML dashboard page | HIGH |
| SC-VERIFY-VISUAL-002 | Screenshots MUST be verified against spec | HIGH |
| SC-VERIFY-VISUAL-003 | Video user journeys MUST demonstrate key workflows | MEDIUM |
| SC-VERIFY-VISUAL-006 | Failed visual verification triggers recursive fix loop | HIGH |

### Pi-Mono Symbiosis (v22.10.1)

**Bridge**: `lib/cepaf_gleam/src/cepaf_gleam/bridge/pi_claude_code.gleam` (300+ lines)
**Test**: `lib/cepaf_gleam/test/pi_claude_code_test.gleam` (30 tests)
**Dashboard**: `https://vm-1.tail55d152.ts.net:4200/pi-symbiosis`
**Tool Federation**: 93 total = 6 Claude (Read/Write/Edit/Bash/Grep/Glob) + 14 Pi + 73 C3I MCP
**Event Bridge**: 29 Pi events ↔ 32 AG-UI events (bidirectional)
**Video Recording**: `scripts/xvfb-record.sh` (Xvfb + ffmpeg + xdotool)
**Rule**: `.claude/rules/pi-symbiosis-automation.md` (SC-PI-AUTO-001..008)
**Rule**: `.claude/rules/pi-runtime-activation.md` (SC-PI-RUNTIME-001..008)
**Rule**: `.claude/rules/video-screenshot-verification.md` (SC-VERIFY-VISUAL-001..006)
**Skill**: `.claude/commands/pi-symbiosis-evolve.md`
**User Guide**: `docs/PI_RUNTIME_USER_GUIDE.md`

### Pi Runtime Activation (v22.10.2-PI-RUNTIME)

Pi-mono Node.js runtime is activatable from the BEAM mesh:
- **Runtime Manager**: `bridge/pi_runtime.gleam` — process lifecycle, circuit breaker (3 fail → 60s), auto-restart (max 5x)
- **RPC Client**: `bridge/pi_rpc.gleam` — JSONL protocol, 15 command types, 15 providers
- **Subscriber Actor**: `actors/pi_subscriber.gleam` — OTP actor, event processing, health probes
- **Tests**: `test/pi_runtime_test.gleam` — 42 tests (lifecycle, circuit breaker, RPC serialization)
- **Wiring Guard**: 111 verified connections (was 107, +4 Pi runtime)
- **Providers**: 15 (google, anthropic, openai, ollama, bedrock, mistralai, openrouter, groq, deepseek, xai, cerebras, qwen, sambanova, fireworks, together)

**Quick Start**:
```bash
# One-shot (fastest)
source sub-projects/pi-mono/load-env.sh
node sub-projects/pi-mono/packages/coding-agent/dist/cli.js \
  --provider google --model gemini-2.5-flash --print "Your prompt"

# RPC daemon (persistent, for C3I integration)
node sub-projects/pi-mono/packages/coding-agent/dist/cli.js \
  --provider google --model gemini-2.5-flash --mode rpc
```

**See** `docs/PI_RUNTIME_USER_GUIDE.md` for comprehensive documentation.
**See** `docs/GLEAM_UI_DEVELOPMENT_PROMPT.md` for development session prompt.

---

## §11.0 Allium Behavioral Specification

**Allium v3** captures system behavioral intent formally. Spec and code divergence = information.

- **Spec**: `specs/allium/ignition.allium` (1,923 lines, 26 sections)
- **Template**: `specs/allium/TEMPLATE.allium` (26-section standard)
- **Checklist**: `specs/allium/CHECKLIST.md`
- **Skill**: `.claude/commands/allium.md` + `.agents/skills/allium/` (official JUXT)
- **Rule**: `.claude/rules/allium-behavioral-specs.md` (SC-ALLIUM-001..008)
- **Guide**: `docs/allium-user-guide.md`

| Allium Construct | Count | Coverage |
|-----------------|-------|---------|
| Entities | 14 | Container, Genome, BootSequence, OodaCycle, Observation, Orientation, etc. |
| Rules | 16 | Boot (4), OODA (5), GRL (7), health (2), build (1), apoptosis (2), RCA (1) |
| Contracts | 5 | PodmanOps, HealthOrchestra, RuleEngine, LLMAdvisor, GuardianGate |
| Invariants | 5 | Quorum, OODA SLA, CPU limit, dying gasp, EMA |
| Surfaces | 3 | OperatorDashboard, AiAdvisor, ZenohMeshBus |
| Math structures | 33 | Shannon H, CCM, ITQS, PageRank, Kahn's, CPM, EMA, RETE-UL, etc. |
| **GRL rule domains** | **13 implemented** | 52 rules across ALL domains — see rule engine table below |

Commands: `/allium`, `/allium:tend`, `/allium:weed`, `/allium:distill`, `/allium:propagate`, `/allium:elicit`

### RETE-UL Rule Engine (rust-rule-engine v1.20.1)

**52 GRL rules** across **13 domains** in `rule_engine.rs` (961 lines). 41 unit tests. Generic `run_domain()` + 13 `OnceLock` caches.

| API | Domain | Rules | Use |
|-----|--------|-------|-----|
| `evaluate_decision()` | OODA Decide | 7 | Emergency/Boot/Restart/Health/LLM/NoAction |
| `evaluate_preflight()` | Preflight Gate | 4 | Block/Warn/Pass graduated checks |
| `evaluate_recovery()` | Recovery Selection | 6 | RPN-prioritized playbook (NIF/Cascade/Glibc/Memory/Timeout) |
| `evaluate_health_consensus()` | Health Consensus | 4 | Per-criticality 2/3/4 of 5 threshold |
| `evaluate_cascade()` | Cascade Containment | 3 | Apoptosis/Isolate/Monitor by depth |
| `evaluate_partition()` | Partition Fencing | 3 | FenceMinority/PreserveData/NoAction |
| `evaluate_launch_tier()` | Launch Tier Gate | 3 | Halt/Continue/Proceed per criticality |
| `evaluate_governor()` | CPU Governor | 3 | FullSpeed/HeavyThrottle/Wait |
| `evaluate_verify()` | Verify Compliance | 3 | Compliant/Degraded/NonCompliant |
| `evaluate_build()` | Build Staleness | 3 | Rebuild P0@72h / Standard@168h / Skip |
| `evaluate_apoptosis()` | Apoptosis Grace | 4 | Immediate/Fast2s/Graceful10s/Default5s |
| `evaluate_rca()` | RCA Escalation | 4 | L1 NIF/L4 Container/L6 Quorum/L7 LLM |
| `evaluate_hysteresis()` | Hysteresis Config | 3 | Aggressive/Conservative/Default |

Rust tests: **307 passed** (41 rule engine tests). Gleam tests: **3,354 passed**.

---

## §12.0 Task Management Authority (SC-TODO-001)

**Status**: CRITICAL | **Tool**: `sa-plan-daemon` (Rust Unified Task Management)

All updates to `PROJECT_TODOLIST.md`, task status transitions (Pending -> Active -> Completed), and priority changes MUST be performed exclusively via the `sa-plan-daemon` Rust binary. This binary replaces the legacy F# `Cepaf.Planning.CLI`.

**Binary path**: `./sub-projects/c3i/target/release/sa-plan-daemon`

**Prohibitions**:
- Direct manual edits to `PROJECT_TODOLIST.md` are STRICTLY FORBIDDEN.
- Use of legacy Elixir `mix todo` or shell scripts is DEPRECATED and FORBIDDEN.
- Use of the legacy F# `Cepaf.Planning.CLI` is DEPRECATED and FORBIDDEN.

**Data Integrity**:
`PROJECT_TODOLIST.md` is a derived, read-only artifact. The authoritative state resides in the `Planning.db` SQLite/DuckDB store. Manual changes will be overwritten and lost upon next `sa-plan-daemon` sync.

**MCP+Zenoh Integration**: `sa-plan-daemon` operations are also available as MCP tools via the Zenoh backplane (SC-ZMOF-001). Task mutations publish OTel spans to `indrajaal/plan/spans/**` for distributed audit.

**Usage**:
- List: `sa-plan-daemon status`
- Add: `sa-plan-daemon add "Description" P1`
- Update: `sa-plan-daemon update <ID> <status>`

---

## §13.0 High Availability & Zero-Downtime Evolution (HA-SEAMLESS)

**Mandate**: SC-HA-001 — The system MUST support continuous evolution (compilation/restarting) without dropping intents or corrupting state.
- **Leader Election**: Rust `sa-plan-daemon` uses Zenoh lease `indrajaal/l4/system/leader_lease` to establish mutual exclusion over `Smriti.db` writes.
- **Graceful Drain**: Gleam `cortex-mesh` employs a `LeadershipMonitor` actor. Upon receiving `SIGTERM`, it enters `Draining` state, completes active OODA loops, and yields the lease to the `Backup` node.
- **Formal Verification**: The transition logic is proven free of Split-Brain and Deadlock scenarios via TLA+ (`specs/tla/LeaderElection.tla`). E2E chaos tests enforce 0 dropped intents during binary swaps.

---

## §14.0 OpenClaw Sensor-Motor Capabilities & CLI

**Mandate**: SC-OPENCLAW-001..004 — The system integrates the OpenClaw architecture mapped to the SIL-6 Fractal Brain-Stem.

| Capability | Fractal Layer | Implementation | Constraint |
|:---|:---|:---|:---|
| **Tools (Motor)** | L4 (Rust) | `mcp_sys`, `mcp_file`, `mcp_web` in `sa-plan` | Sandboxing for `exec`, chroot jailing for FS. |
| **Skills (Cognitive)**| L5 (Gleam)| `SkillLoader` reads `.agents/skills/**/SKILL.md` | Prompt injection protection `[SYSTEM SKILL DIRECTIVE]`. |
| **Context & Sessions**| L5 (Gleam)| Isolated child actors | Strict context boundary isolation. |
| **CLI: Secrets** | L3/L4 | `sa-plan secrets` | Symmetrically encrypted in `Smriti.db` CRDT backplane. |
| **CLI: Approvals** | L5/L7 | `sa-plan approvals` (HITL) | Destructive intents halt OODA loop pending cryptographically signed human approval. |
| **CLI: Nodes/Pair** | L6/L7 | `sa-plan pair` | Zero-IP Identity. Devices join mesh via ECDSA-signed Zenoh tokens. |
| **Continuous Voice** | L1/L0 | `intelitor-perception` | Sub-20ms latency streaming via WebRTC/Zenoh. |
| **Canvas Hologram** | L6 | A2UI CRDT State | Shared spatial state converging deterministically across all UI clients. |

---

## §15.0 Chat Processing Pipeline (SC-COG-001)

**Mandate**: SC-COG-001 — The Rust `sa-plan-daemon` cortex processes all chat intents via a 6-tier hedged inference cascade with full transaction tracing.

**Source**: `sub-projects/c3i/native/planning_daemon/src/` (31 files, 9,104 LOC)

### Pipeline Architecture

```
Telegram/GChat → long-poll → Zenoh intent → CLASSIFY
  │ simple? → direct DB reply (<1ms)
  │ complex? → ack("⏳") → HEDGE(Gemini Direct || OpenRouter)
  │   → fallback: Ollama gemma4 → gemma3 → RETE-UL rules
  └→ GATEWAY broadcast → Telegram + GChat (retry x1)
```

### 7-Tier Inference Cascade

| Tier | Model | Latency | Cost | Transport |
|------|-------|---------|------|-----------|
| 1 | Gemini Direct (gemini-3.1-flash-lite-preview) | ~900ms | Free | HTTPS |
| 2 | OpenRouter (gemini-3-flash-preview) | ~1.1s | $0.000009 | HTTPS |
| 3 | **mistral.rs gemma4 (in-process)** | **~500ms** | **Free** | **In-process (zero HTTP)** |
| 4 | Ollama gemma4 (port 11435, fallback) | ~4s | Free | HTTP |
| 5 | Ollama gemma3 (port 11434, last resort) | ~10s | Free | HTTP |
| 6 | RETE-UL rule engine | <1ms | Free | In-process |
| 7 | Static ack | <1ms | Free | In-process |

**Hedged Parallel**: Tiers 1+2 fire simultaneously via `tokio::join!`. First success wins.
**mistral.rs Primary Local**: Tier 3 uses `TextModelBuilder` with `google/gemma-4-4b-it` — zero HTTP overhead, ~10x faster than Ollama.
**Circuit Breakers**: 5 independent `CircuitBreaker` instances (3 failures → 60s cooldown).
**Persistent HTTP**: `OnceLock<reqwest::Client>` with 30s keepalive pinger eliminates TLS cold-start.
**No-Blackhole Guarantee**: 7 mechanisms ensure every message gets a response.

### Key Modules

| Module | Lines | Purpose |
|--------|-------|---------|
| `cortex.rs` | 1,567 | Intent processing, classify, ack, RAG, dispatch |
| `db.rs` | 1,000 | SQLite backend, task CRUD, trace schema, cache |
| `ruliology.rs` | 929 | Wolfram-style computational rule analysis |
| `types.rs` | 850 | Domain types (genome, tiers, health, FSM) |
| `mcp_inference.rs` | 663 | Hedged inference, circuit breakers, HTTP client |
| `mcp_gworkspace.rs` | 380 | Gmail OAuth2 send, Workspace MCP tool |
| `simulator.rs` | 349 | 400 test scenarios (20 categories × 10 × 2 channels) |
| `ingress_polling.rs` | 331 | Dark Cockpit secure outbound polling |
| `gemini_live.rs` | 307 | WebSocket voice (Gemini Live 3.1 Flash) |
| `cli.rs` | 261 | CLI status/add/update commands |
| `trace.rs` | 242 | PipelineTracer: zero-write hot path, batch finish |
| `main.rs` | 237 | Entry point, Zenoh session, tokio runtime |
| `errors.rs` | 226 | SIL-4 fail-safe error types |
| `gateway.rs` | 198 | Parallel broadcast to Telegram/GChat with retry |
| `smoke_test.rs` | 171 | Wave 3 smoke test publisher |
| `tui.rs` | 148 | Ratatui terminal dashboard |
| `markdown.rs` | 124 | PROJECT_TODOLIST.md generator |
| `supervisor.rs` | 111 | Agent supervision tree (L4-System) |
| `audit_log.rs` | 100 | Immutable audit trail |
| `zenoh_telemetry.rs` | 91 | Boot state vector, checkpoints |
| `pii.rs` | 91 | PII scrubber (email, phone, CC, SSN, IP) |
| `rag.rs` | 87 | RAG context from Smriti FTS5 |
| `ha_election.rs` | 81 | Leader election (Primary/Backup/Standby) |
| `fmea.rs` | 79 | Automated FMEA from trace data |
| `command_verifier.rs` | 61 | Command execution verification |
| `mcp_file.rs` | 59 | OpenClaw File IO (workspace-constrained) |
| `math_monitor.rs` | 57 | 17 mathematical disciplines health |
| `mcp_sys.rs` | 49 | OpenClaw sandboxed exec |
| `mcp_web.rs` | 45 | OpenClaw web fetch + semantic extraction |
| `heartbeat.rs` | 30 | 10-minute cron for proactive OODA |
| `mcp_browser.rs` | 28 | Playwright/CDP browser tool |
| **TOTAL** | **9,104** | **31 modules** |

### PipelineTracer (SC-COG-001, SC-XHOLON-001)

Every intent is traced end-to-end via `PipelineTracer`:
- Zero DB writes during processing (in-memory `Vec<TraceStage>`)
- Single batch write on `finish_with_zenoh()` to SQLite + Zenoh
- Compact footer: `Pipeline: recv(0ms) > class(1ms) > ack(2ms) > infer(1200ms) > delivered(1400ms)`
- Dual output: `TransactionTrace` + `TransactionSummary` tables + `indrajaal/l5/cog/trace/{id}`

### Additional Capabilities

- **Semantic Cache**: 24h TTL, SQLite-backed, skips inference on cache hit
- **Conversation History**: 50-message sliding window per chat
- **Rate Limiting**: 20 messages/minute per user
- **RAG Pipeline**: Smriti FTS5 context injection (~4ms)
- **PII Scrubber**: Regex-based redaction (SC-SEC-003, SC-LOG-003)
- **SMTP Email**: lettre crate, attachments, app password in Smriti
- **Multilingual Detection**: Auto-detect input language
- **Conversation Summarization**: Periodic context compression

---

## §16.0 Voice Processing Pipeline (SC-OPENCLAW-001)

**Mandate**: SC-OPENCLAW-001 — 5-tier voice cascade from real-time WebSocket to offline transcription.

### 5-Tier Voice Cascade

| Tier | Model | Latency | Method |
|------|-------|---------|--------|
| 1 | Gemini Live 3.1 Flash | ~250ms | WebSocket (real-time) |
| 2 | Gemini REST 2.5 | ~900ms | Multimodal audio REST |
| 3 | Gemini REST 3.1 | ~1.1s | Multimodal audio REST |
| 4 | Whisper.cpp (ggml-tiny) | ~2s | Local offline (75MB model) |
| 5 | Rule-based ack | <1ms | Static response |

**2-Stage Voice**: Transcribe → text pipeline with full SYSTEM_PROMPT context.
**Module**: `gemini_live.rs` (307 lines) — WebSocket client, OGG→PCM via ffmpeg, 3-tier fallback.

---

## §17.0 Gleam Cortex & Gateway (SC-COG-001, SC-ZMOF-001)

### Cortex ReAct Loop (`agents/cortex.gleam`)
- **Layer**: L5_COGNITIVE
- **Types**: `CortexState` (OODA cycle, MoZ client, active intent, memory, span context)
- **Messages**: ProcessIntent, ObserveToolResult, OodaTick
- **Functions**: start/1, handle_message/2, decide_next_action/2, fetch_context/1

### MoZ Protocol (`moz/client.gleam`, `moz/planning.gleam`, `moz/system.gleam`)
- 497 lines implementing MCP-over-Zenoh
- Tool request/response via Zenoh Pub/Sub
- Used by cortex.gleam for MCP tool invocation

### Gateway Bridges (`gateway/telegram.gleam`, `gateway/gchat.gleam`, `gateway/whatsapp.gleam`)
- **Layer**: L7_FEDERATION
- Actor-based Zenoh subscribers on `indrajaal/otel/span/critical`
- Route critical OTel spans to chat platforms

---

**Version**: 22.10.1-PI-SYMBIOSIS
**Last Updated**: 2026-04-20
**Status**: Gleam-first platform operational — unified c3i_nif (14 NIFs), 93 federated tools (6 Claude + 14 Pi + 73 C3I), 233 A2UI components, 31-module Rust cortex (9,104 LOC), 6-tier hedged inference, 5-tier voice cascade, PipelineTracer, RAG, semantic cache, ZMOF active, Muda source-clean (0 src warnings), sa-plan-daemon authoritative, OpenClaw & HA integrated, Pi-mono symbiosis (106K LOC, 29↔32 event bridge), Xvfb video recording

## §18.0 Gemini CLI Symbiosis & Cybernetic Architect

The Gemini CLI operates as the **Cybernetic Architect**, a formal system role defined by deep integration with the fractal mesh.

### §18.1 Persistence & Memory (`save_memory`)
- Gemini autonomously records architectural decisions, ASSP lock states, and session context via the `save_memory` tool.
- This ensures continuity across multi-agent handovers and workspace transitions.

### §18.2 specialized Knowledge (`activate_skill`)
- Skills in `.gemini/skills/` (e.g., `multilayer-swarm`, `system-engineering-sop`) are activated on-demand.
- Plans generated by the system MUST include explicit `activate_skill` directives to ensure the agent is operating at maximum cognitive saturation.

### §18.3 Architectural Mapping (`codebase_investigator`)
- The `codebase_investigator` subagent is the primary tool for the **Orient** phase of the OODA loop.
- It is invoked to map system-wide dependencies before executing multi-file surgical edits.

### §18.4 Web Intelligence (`firecrawl`)
- Redundant custom browser MCPs are superseded by Gemini's built-in Firecrawl tools for high-fidelity web fetching and semantic extraction.

---

## §19.0 Gemini CLI Symbiosis Recommendations

To maximize the unique capabilities of the Gemini CLI, the following architectural patterns are recommended:

### §19.1 Active Skill Tagging (@skill)
- **Pattern**: Tasks in `PROJECT_TODOLIST.md` should be tagged with `@skill {name}`.
- **Workflow**: Upon starting a task, Gemini MUST check for these tags and run `activate_skill {name}` immediately to ensure cognitive alignment with domain-specific SOPs.

### §19.2 Automated Architectural Factoids
- **Pattern**: Significant architectural findings during OODA loops should be persisted using `save_memory(scope: "project", fact: "...")`.
- **Value**: This bypasses session context limits and provides a persistent, shared "subconscious" for all agent instances working on the C3I mesh.

### §19.3 Jidoka-Triggered Mapping
- **Pattern**: If the system triggers a **Jidoka Halt** (due to invariant violation), the first action of the Orient phase MUST be `codebase_investigator(objective: "Map the failure cascade for {invariant_id}")`.
- **Value**: Leverages specialized subagents to prevent shallow fixes that could cause side-effect cascades.

### §19.4 Dynamic Documentation Fetching
- **Pattern**: When working with fast-evolving Gleam libraries (Lustre/Wisp), Gemini should use `firecrawl-scrape` on official documentation URLs to ensure API accuracy.

---
