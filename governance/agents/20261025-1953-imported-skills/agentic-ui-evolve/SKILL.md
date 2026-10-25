---
name: agentic-ui-evolve
description: "Apply the full planning page evolution pattern to any C3I page. Implements LiveView-equivalent WebSocket reactivity, Gemma AI chat, responsive mobile-first design, fractal navigation, and 179+ Rust E2E tests."
---

# Agentic UI Evolution Skill

Apply the full planning page evolution pattern to any C3I page. Implements LiveView-equivalent WebSocket reactivity, Gemma AI chat, responsive mobile-first design, fractal navigation, and 179+ Rust E2E tests.

## Usage
`/agentic-ui-evolve <page-path>` — e.g., `/agentic-ui-evolve /dashboard`

## Ultrathink Alignment
Focus Areas: #4 (Homomorphic Tripartite UI), #6 (SLM Cognitive Kernels), #9 (OpenClaw Penta-Stack), #10 (HA Seamless Upgrades)

---

## Phase 1: Multi-View & Fractal Navigation
1. Add 4-view toggle (Grid/Kanban/Timeline/Analytics) with keyboard shortcuts 1-4
2. Add L0-L7 fractal layer filter chips with keyword classification (see rule for keyword table)
3. Add AI search bar (Ctrl+K) with 200ms debounce, grid filter + Zettelkasten knowledge lookup
4. Add click-to-detail drill-down with 5 actions: Knowledge, Related, STAMP, Sub-Tasks, AI Analysis
5. Add elegant gradient badges: P0 red glow, P1 amber, P2 green, P3 muted outline
6. Add state change event log (status_change, priority_change, new_task, task_removed, data_diff)
7. Remove dead code (SC-MUDA-001)

## Phase 2: Real-Time Dynamic Updates
1. Live header updates every 5s: weather bar (emoji + mood + score), status cards, progress ring SVGs
2. Active data refresh every 1s with row-level diff detection + highlight animation (CSS `rowPulse`)
3. Heartbeat indicator: green (live) / amber (stale >5s) / red (disconnected)
4. Card value flash teal for 1.5s when data changes

## Phase 3: Responsive Mobile-First Design
1. Base CSS targets mobile (<768px): 1-col grids, stacked layout
2. `@media (min-width:768px)`: 2-col cards/kanban, 4x1 rings (90px), tablet font scaling
3. `@media (min-width:1024px)`: auto-fill cards, 4-col kanban, 100px rings, full tables
4. `@media (min-width:1400px)`: 110px rings, 2rem gaps, 1.4rem ring values
5. `min-height:44px` on ALL interactive elements (buttons, chips, search, cards)
6. `safe-area-inset-bottom` for notched phones
7. `scroll-behavior:smooth`, `overscroll-behavior:none`
8. `-webkit-overflow-scrolling:touch` for momentum scroll on tables/timeline
9. Glassmorphism: `backdrop-filter:blur(8px-16px)` on cards, panels, headers
10. CSS variables for theming: `var(--bg)`, `var(--text)`, `var(--accent)`, `var(--border)`

## Phase 4: WebSocket (LiveView-Equivalent)
1. Add Mist WebSocket upgrade handler on `/ws/<page-name>` in `web/server.gleam`
2. WsState tracks `push_count: Int` and `last_status: String` for diff detection
3. `ws_on_init`: Send initial status snapshot on connection, return state with no timer
4. Client sends `"ping"` every 1s → server diff-checks status → responds with:
   - `"update"` (status + active + blocked JSON) when data changed
   - `"heartbeat"` (seq counter only) when data unchanged — saves bandwidth
5. Client can send search queries → server responds with NIF search results
6. Auto-reconnect: exponential backoff 1s→2s→4s→8s→...→30s max
7. Falls back to HTTP polling (5s) when WS disconnected
8. **All three transports (WS + SSE + HTTP) MUST report identical data**

## Phase 5: AI Agent Integration (Gemma 3/4)
1. Chat widget: floating panel with message history, typing indicator, model label
2. Default: Gemma 3 (port 11434, 3.3GB, ~5s response) — fast enough for interactive chat
3. Fallback: Gemma 4 (port 11435, 9.6GB) on Gemma 3 failure
4. Use `/api/chat` with message arrays (NEVER `/api/generate` — returns empty)
5. System prompt enriched with live page data: total/active/blocked/completed counts
6. 15s AbortController timeout. Graceful fallback to NIF search context
7. Add `/api/v1/ai/status` (model info + capabilities) and `/api/v1/ai/chat?q=` endpoints

## Phase 6: Testing (Mandatory)
### Gleam Tests (106+ per page)
- C1 Page Structure: init() defaults, empty state
- C2 Status Badges: cockpit mode colors at boundaries (0.3, 0.5, 0.7, 0.9)
- C3 Data Grids: all filter variants, task counts
- C4 Timeline: OODA cycle ordering, timestamps
- C5 Interactive: ALL Msg variants through update()
- C6 Media/Rich: health_score computation, progress ring values
- C7 AI Advisory: AG-UI lifecycle, tool calls, reasoning events
- C8 Action Buttons: HITL approval flow, cockpit escalation
- Prime Paths: chained multi-step update() sequences
- TUI Render: non-empty ANSI output verification

### Rust E2E Tests (179+ per page, pure Rust, zero Python)
| Section | Tests | Coverage |
|---------|-------|----------|
| A. Server Health | 2 | HTTPS 200 |
| B. API Endpoints | 10 | All routes |
| C. Live Data | 3 | Status counts |
| D. DOM Elements | 21 | All IDs present |
| E. Responsive CSS | 7 | Breakpoints + touch |
| F. Page Content | 7 | Sections + cards + SVGs |
| G. JS Features | 26 | All functions present |
| H. SSE Stream | 4 | Event types + retry |
| I. WebSocket | 5 | Upgrade + ping + search |
| J. Gemma AI | 1 | Responds with context |
| K. AI Status | 2 | Model + capabilities |
| L. Search | 2 | Returns results |

### DAG Scenarios (6 per page, 27+ stages)
| DAG | Stages | Path |
|-----|--------|------|
| M: Triage Journey | 5 | page→status→blocked→search→WS verify |
| N: Real-Time Monitor | 6 | WS→status→HTTP compare→3 pings monotonic |
| O: AI Analysis | 5 | AI status→tasks→Gemma→search keyword→chat |
| P: View Consistency | 7 | all tasks→count→match active/blocked/completed→search subset |
| Q: Transport Consistency | 4 | SSE→WS→compare→match HTTP |
| R: Page↔API Integrity | 3 | HTML contains count→JS ref'd→JS >50KB |

### Responsive Tests (60 per page)
| Section | Viewport | Tests |
|---------|----------|-------|
| S. Mobile Triage | <768px | 12 (1-col, touch, safe-area, scroll, wrap) |
| T. Tablet Review | 768-1024px | 8 (2-col, rings, fonts, labels) |
| U. Desktop Canvas | 1024px+ | 8 (auto-fill, 4-col, auto-fit, 100px) |
| V. Wide Desktop | 1400px+ | 4 (110px, 2rem, 1.4rem) |
| W. Cross-Viewport | All | 12 (DOM, blur, transitions, fluid, vars, colors) |
| X. Mobile Journey | <768px | 7 (weather→status→blocked→search→chat) |
| Y. Desktop Journey | 1024px+ | 8 (views→fractal→tables→export→WS) |

## Phase 7: Documentation & Notification
1. 15-section specification: architecture, features, state machines, API, visual design, user journeys, testing, ruliology, performance
2. 13-section journal entry (SC-SYNC-DOC-002)
3. Email via SMTP: `sa-plan-daemon send-email --to Abhijit.Naik@bountytek.com --subject "..." --body "..." --attach <spec.md>`
4. NEVER use Gmail MCP — ALWAYS SMTP via sa-plan-daemon

## Verification Criteria (ALL must pass)
- [ ] Gleam build: 0 errors
- [ ] Gleam tests: 0 failures (3,941+ total)
- [ ] Rust E2E: 179+ tests, 0 failures
- [ ] 21+ DOM elements dynamically updated
- [ ] 10+ API endpoints HTTP 200
- [ ] WebSocket upgrade HTTP 101
- [ ] WS ping→heartbeat verified
- [ ] WS search→results verified
- [ ] Gemma AI responds with task context
- [ ] 4 responsive breakpoints verified
- [ ] 44px touch targets verified
- [ ] SSE + WS + HTTP all report identical data
- [ ] 6 DAG scenarios pass
- [ ] Mobile + Desktop user journeys pass

## Phase 8: Multidimensional Optimization
1. Score each component across 5 dimensions: FMEA Risk (0.30), Criticality (0.25), Utility (0.20), Performance (0.15), Accessibility (0.10)
2. Build FMEA table: Component × Failure Mode × Severity × Occurrence × Detection → RPN
3. RPN ≥ 200 → immediate remediation. Priority = (1 - CompositeScore) × FractalLayerWeight
4. Enforce latency SLAs: WS round-trip <50ms, card update <100ms, Gemma <5s, search <200ms, page load <2s
5. Bandwidth budget: WS heartbeat <100 bytes/frame, WS update <50KB/frame

## Phase 9: Ruliology Integration
1. Connect to Rust rule engine (`rule_engine.rs`, 52 GRL rules) via NIF for UI behavior decisions
2. Implement UI-specific GRL rules: UIRefreshRate, UICockpitEscalate, UIKanbanAlert, UITimelineStale, UISearchBoost, UIGemmaEscalate, UIWsReconnect, UIFractalFocus
3. Rule evaluation flow: JS event → `/api/v1/rules/evaluate?context=<json>` → NIF → action → JS applies
4. Wolfram cellular automata: Rule 30 (chaos detection), Rule 110 (complexity emergence), Rule 184 (traffic flow)

## Phase 10: Device-Specific Responsive Patterns
1. Support 6+ device profiles: iPhone SE (375px), iPhone 15 Pro (393px), iPad Mini (768px), iPad Pro (1024px), MacBook (1440px), 4K Monitor (3840px)
2. Orientation rules: `@media (orientation: portrait)` → stack, hide timeline; `@media (orientation: landscape)` → side-by-side
3. DPR-aware: `@media (-webkit-min-device-pixel-ratio: 2/3)` → adjust stroke-width for optical consistency
4. System preferences: `prefers-color-scheme`, `prefers-reduced-motion`, `prefers-contrast`
5. Performance budget: Mobile first paint <1.5s, Desktop <1s, JS bundle <100KB

## Ultrathink Traceability (per page)
Every evolved page MUST map to ≥3 of the 10 Ultrathink focus areas:
- #4 Homomorphic Tripartite UI (4 views + responsive + triple transport)
- #6 Embedded SLM Cognitive Kernels (Gemma chat + AI analysis)
- #9 OpenClaw Ecosystem (5 drill-down actions, A2UI 233 components)
- #10 HA Seamless Upgrades (WS reconnect, polling fallback)

## System Integration Checklist
- [ ] AG-UI 32-event protocol handlers in Lustre Msg
- [ ] A2UI 233 component types available via JSON proposals
- [ ] Zenoh OTel spans published for all state changes (SC-GLM-ZEN-001)
- [ ] NIF bridge calls for page-specific data
- [ ] MoZ (MCP-over-Zenoh) tools exposed if actionable
- [ ] Zettelkasten FTS5 search integrated in AI search + drill-down
- [ ] Allium behavioral spec written for page state machine
- [ ] OODA loop: Observe(WS)→Orient(diff)→Decide(rules)→Act(update)
- [ ] TPS/Jidoka: stop on defect (red heartbeat), andon (weather bar)
- [ ] Psi invariants displayed or verified (Psi-0..5, Omega-0)
- [ ] Shannon entropy H ≥ 2.5 bits across C1-C8 test categories
- [ ] PageRank priority guides test execution order
- [ ] Dark cockpit: healthy=hidden, critical=emergency mode

## SIL-6 Compliance (per page)
- [ ] Fail-safe degradation: WS→SSE→polling→static
- [ ] Dying gasp: WS disconnect captures last state to change log
- [ ] Heartbeat: 1s ping, 3s stale, 10s dead thresholds
- [ ] Audit trail: every state change logged with timestamp + seq
- [ ] State recovery: page reconstructs from NIF on reload (no client state)
- [ ] Rollback: Esc closes, back button works, all view changes reversible

## VSM Mapping (per page)
- [ ] S1 Operations: data grids, task cards (1s refresh)
- [ ] S2 Coordination: view toggle, fractal filter, search
- [ ] S3 Control: status cards, progress rings, analytics
- [ ] S3* Audit: state change log, STAMP refs
- [ ] S4 Intelligence: Gemma chat, AI analysis, knowledge lookup
- [ ] S5 Policy: weather bar, cockpit mode, Psi invariants

## Post-Evolution SOP
1. Write spec → `docs/architecture/<page>-specification.md`
2. Write journal → `docs/journal/YYYYMMDD-<page>-evolution.md`
3. Write Allium → `specs/allium/<page>.allium`
4. Commit ICP v2.0 format
5. Ingest to Zettelkasten: `sa-plan-daemon zettel ingest --file <spec> --level molecular`
6. Email via SMTP: `sa-plan-daemon send-email`
7. Run 24 compliance checks from master prompt
8. Update `sa-plan update <id> completed`

## Evolution Order (by PageRank)
1. `/planning` — DONE
2. `/dashboard` — NEXT
3. `/cockpit` → `/verification` → `/immune` → `/agents` → `/zenoh` → `/knowledge`
4. Remaining 23 pages by PageRank tier

## Reference
- Rule: `.claude/rules/agentic-ui-responsive-design.md` (29 sections, SC-AGUI-UI-001..015)
- Master prompt: `.claude/commands/c3i-page-evolution.md` (8 phases, 24 checks)
- Agent: `.claude/agents/agentic-ui-designer.md`
- Spec: `docs/architecture/planning-page-specification.md`
- Journal: `docs/journal/20260411-planning-page-evolution.md`
- Allium: `specs/allium/ignition.allium` (add ui.allium per page)
- Ruliology: `native/planning_daemon/src/ruliology.rs` (929 lines)
- Rule engine: `native/planning_daemon/src/rule_engine.rs` (961 lines, 52 GRL)
- Zettelkasten: `zettelkasten/*.gleam` (9 modules, 2,060+ holons)
