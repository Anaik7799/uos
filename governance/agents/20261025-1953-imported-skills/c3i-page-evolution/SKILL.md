---
name: c3i-page-evolution
description: Comprehensive prompt that covers ALL items from the planning page evolution session. Use this to evolve ANY C3I page to full agentic UI standard.
---

# C3I Page Evolution — Master Prompt

Comprehensive prompt that covers ALL items from the planning page evolution session. Use this to evolve ANY C3I page to full agentic UI standard.

## Usage
`/c3i-page-evolution <page-path>` — e.g., `/c3i-page-evolution /dashboard`

---

## THE MASTER PROMPT

```
Target: https://<host>:4100/<page-path>

═══ PHASE 1: MULTI-VIEW AGENTIC NAVIGATION ═══
Add 4-view toggle (Grid/Kanban/Timeline/Analytics) with keyboard shortcuts 1-4.
Add L0-L7 fractal layer filter chips with keyword classification:
  L0 Constitutional (guardian,safety,emergency,sil4,psi,prime)
  L1 Atomic/Debug (nif,debug,trace,telemetry,otel,ffi)
  L2 Component (parser,component,form,badge,catalog,a2ui)
  L3 Transaction (planning,task,state,db,sqlite,smriti)
  L4 System (podman,container,system,boot,build,docker)
  L5 Cognitive (ooda,cortex,mcp,agent,llm,inference)
  L6 Ecosystem (zenoh,mesh,topology,quorum,cluster)
  L7 Federation (federation,gateway,version,consensus)
Add AI search bar (Ctrl+K) with 200ms debounce + Zettelkasten knowledge lookup.
Add click-to-detail drill-down with 5 actions:
  Knowledge Lookup, Related Items, STAMP Refs, Sub-Items, AI Analysis.
Add elegant gradient badges: P0 red glow, P1 amber, P2 green, P3 muted.
Add state change event log (status_change, priority_change, new, removed, data_diff).
Remove dead code per SC-MUDA-001.

═══ PHASE 2: REAL-TIME LIVEVIEW-EQUIVALENT UPDATES ═══
WebSocket on /ws/<page-name> via Mist 6.0 — bidirectional, client-driven 1s ping.
Server diff-detects: status != last_status → full update, else heartbeat (<100 bytes).
Bidirectional: same WS carries push updates AND search queries.
Auto-reconnect: exponential backoff 1s→2s→4s→...→30s max.
SSE fallback on /api/v1/<page>/stream — unidirectional event stream.
HTTP polling fallback (5s) when both WS and SSE fail.
Triple transport (WS + SSE + HTTP) MUST report identical data.
Live header updates: weather bar + status cards + progress rings every 5s via WS.
Row-level diff: snapshotData() → findChangedIds() → highlightChangedRows() (1.8s CSS animation).
Heartbeat indicator: green (<3s), amber (3-10s), red (>10s → trigger reconnect).
Latency SLAs: WS round-trip <50ms, card update <100ms, row highlight <16ms, page load <2s.
Bandwidth: heartbeat <100 bytes, update <50KB, search <100KB per frame.

═══ PHASE 3: FULLY RESPONSIVE MOBILE-FIRST DESIGN ═══
Base CSS = mobile (<768px): 1-col grids, stacked, 44px touch, safe-area-inset.
@media (min-width:768px) = tablet: 2-col cards/kanban, 4x1 rings (90px), 0.85rem tables.
@media (min-width:1024px) = desktop: auto-fill cards, 4-col kanban, 100px rings, 0.88rem.
@media (min-width:1400px) = wide: 110px rings, 2rem gaps, 1.4rem ring values.
6 device profiles: iPhone SE (375px), iPhone 15 Pro (393px), iPad Mini (768px),
  iPad Pro (1024px), MacBook (1440px), 4K Monitor (3840px).
Orientation: @media (orientation:portrait) → stack; landscape → side-by-side.
DPR-aware: stroke-width 4px (1x), 3px (2x), 2px (3x) for optical consistency.
System preferences: prefers-color-scheme, prefers-reduced-motion, prefers-contrast.
Performance budget: Mobile first paint <1.5s, Desktop <1s, JS bundle <100KB.
Glassmorphism: backdrop-filter:blur(8-16px), gradient badges, pulse animations.
CSS variables: var(--bg), var(--text), var(--accent), var(--border), var(--card-bg).
Dark theme default (#0a0e17), semantic colors (teal/green/amber/red).
Monospace for IDs/code (JetBrains Mono), system-ui for text.

═══ PHASE 4: GEMMA AI AGENT INTEGRATION ═══
Gemma 3 (port 11434, 3.3GB, ~5s) = default fast chat.
Gemma 4 (port 11435, 9.6GB) = deep analysis fallback.
ALWAYS /api/chat with message arrays (NEVER /api/generate — returns empty).
System prompt enriched with live page data: total, active, blocked, completed counts.
15s AbortController timeout. Graceful fallback to NIF search context.
Chat widget: floating panel, message history, typing indicator with shimmer.
Model label shows which Gemma responded.
Add /api/v1/ai/status (model + capabilities) and /api/v1/ai/chat?q= endpoints.

═══ PHASE 5: MULTIDIMENSIONAL OPTIMIZATION ═══
Score each component across 5 dimensions:
  FMEA Risk (0.30): RPN = Severity × Occurrence × Detection. RPN ≥ 200 → immediate fix.
  Criticality (0.25): Fractal layer weight (L0=10, L5=8, L6=9, L3=5).
  Utility (0.20): User interaction frequency × task completion impact (0-10).
  Performance (0.15): Render <100ms, data freshness <2s, bandwidth <50KB/frame.
  Accessibility (0.10): WCAG 2.1 AA (contrast ratio, touch size, keyboard nav).
Composite = Σ(weight × normalized_score). Priority = (1 - Composite) × LayerWeight.
Build FMEA table per component: Failure Mode × Severity × Occurrence × Detection → RPN.

═══ PHASE 6: RULIOLOGY — BEHAVIORAL RULES ENGINE ═══
Connect to Rust rule engine (rule_engine.rs, 52 GRL rules, 13 domains) via NIF.
UI-specific GRL rules:
  UIRefreshRate (salience 80): active_tasks > 20 → 500ms refresh.
  UIRefreshSlow (70): active_tasks == 0 → 5s refresh (power save).
  UICockpitEscalate (90): blocked > 10 OR health < 0.5 → Bright/Emergency mode.
  UICockpitDark (60): blocked == 0 AND health > 0.9 → Dark cockpit.
  UIKanbanAlert (75): P0_pending > 0 → flash P0 column red.
  UITimelineStale (70): oldest_active > 30d → highlight amber.
  UISearchBoost (65): query matches SC-* → prioritize STAMP results.
  UIGemmaEscalate (85): query contains "emergency" → route to Gemma 4.
  UIWsReconnect (95): ws_disconnected > 10s → force reconnect + alert.
  UIFractalFocus (60): recent_failures in L0/L4 → auto-select filter.
Wolfram cellular automata: Rule 30 (chaos), Rule 110 (complexity), Rule 184 (traffic).
Flow: JS event → /api/v1/rules/evaluate?context=<json> → NIF → action → JS applies.

═══ PHASE 7: COMPREHENSIVE TESTING (Rust only, zero Python) ═══
Gleam tests (106+ per page): C1-C8 gold standard + prime paths + TUI render.
Rust E2E binary (179+ tests across 25 sections A-Y):
  A-L: Server health (2), APIs (10), data (3), DOM (21), CSS (7), content (7),
       JS features (26), SSE (4), WebSocket (5), Gemma (1), AI status (2), search (2).
  M-R: 6 DAG cross-component scenarios (27 stages):
    M: Triage (page→status→blocked→search→WS)
    N: Monitoring (WS→status→HTTP compare→3 pings monotonic)
    O: AI Analysis (AI status→tasks→Gemma→keyword→chat)
    P: View Consistency (all tasks→count→match API×3→search subset)
    Q: Transport Consistency (SSE→WS→compare→HTTP all agree)
    R: Page↔API (HTML contains count→JS ref'd→JS >50KB)
  S-Y: 7 responsive sections (60 tests):
    S: Mobile triage (12), T: Tablet review (8), U: Desktop canvas (8),
    V: Wide desktop (4), W: Cross-viewport (12),
    X: Mobile journey (7), Y: Desktop journey (8).

═══ PHASE 8: DOCUMENTATION & NOTIFICATION ═══
15-section specification: architecture, features, state machines, API spec,
  visual design, keyboard shortcuts, user journeys (5), testing, STAMP compliance,
  data flow diagram, ruliology (20 rules), performance, dependencies, gaps.
13-section journal: scope, pre-state, execution, RCA, fix taxonomy, patterns,
  verification matrix, files, architecture, gaps, metrics, STAMP, conclusion.
Email via SMTP: sa-plan-daemon send-email (NEVER Gmail MCP).
Update .claude/rules, .claude/agents, .claude/commands with cross-links.

═══ VERIFICATION CRITERIA (ALL must pass) ═══
[ ] Gleam build: 0 errors, 0 warnings in modified files
[ ] Gleam tests: 0 failures (3,941+ total)
[ ] Rust E2E: 179+ tests, 0 failures
[ ] DOM elements: 21+ dynamically updated
[ ] API endpoints: 10+ HTTP 200
[ ] WebSocket: HTTP 101 upgrade + ping→heartbeat + search→results
[ ] SSE stream: status + active + blocked events
[ ] Gemma AI: responds with page-specific context
[ ] Responsive: 4 breakpoints verified in Rust tests
[ ] Touch: 44px min-height verified
[ ] Transport: SSE + WS + HTTP all agree (DAG Q)
[ ] DAG: 6 scenarios pass (M-R)
[ ] Responsive: 60 viewport tests pass (S-Y)
[ ] FMEA: component table with RPN scores
[ ] Ruliology: UI rules connected via NIF
```

---

## Cross-Reference Map

| Artifact | Path | Sections | STAMP |
|----------|------|----------|-------|
| **This prompt** | `.claude/commands/c3i-page-evolution.md` | 8 phases + verification | All SC-AGUI-UI-* |
| **Rule** | `.claude/rules/agentic-ui-responsive-design.md` | 14 sections | SC-AGUI-UI-001..015 |
| **Skill** | `.claude/commands/agentic-ui-evolve.md` | 10 phases + criteria | SC-AGUI-UI-001..015 |
| **Agent** | `.claude/agents/agentic-ui-designer.md` | 5-step workflow | SC-AGUI-UI-001..015 |
| **Spec** | `docs/architecture/planning-page-specification.md` | 15 sections | SC-GLM-UI-001 |
| **Journal** | `docs/journal/20260411-planning-page-evolution.md` | 13 sections | SC-SYNC-DOC-002 |
| **Gleam UI rule** | `.claude/rules/gleam-web-ui-development.md` | 16 sections | SC-GLM-UI-001..010 |
| **UI graph testing** | `.claude/rules/ui-graph-testing.md` | DAG + LTS + prime paths | SC-UIGT-001..015 |
| **Wiring guard** | `.claude/rules/wiring-guard.md` | Model constructor safety | SC-WIRE-001..007 |
| **Muda waste** | `.claude/rules/muda-waste-reduction.md` | 7 wastes, zero warnings | SC-MUDA-001 |
| **Ultrathink** | `.claude/rules/ultrathink-mandate.md` | 10 focus areas | SC-ULTRA-001 |
| **Core protocols** | `.claude/rules/core-protocols.md` | Functional invariant | SC-FUNC-001 |
| **Rust-Gleam split** | `.claude/rules/rust-gleam-split.md` | Architecture boundary | SC-ARCH-SPLIT-001..004 |
| **Build & test** | `.claude/rules/build-and-test.md` | Compile env + CPU gov | SC-ENV-COMPILE |
| **Zenoh telemetry** | `.claude/rules/zenoh-telemetry-mandatory.md` | OTel spans | SC-GLM-ZEN-001..003 |

## Compliance Checks (automated)

Run this after every page evolution to verify compliance:

```bash
# 1. Build check (SC-FUNC-001)
cd lib/cepaf_gleam && gleam build 2>&1 | grep -c "error" | grep "^0$"

# 2. Test check (SC-UIGT-004)
gleam test 2>&1 | grep "passed" | grep "0 failures"

# 3. Rust E2E check (SC-AGUI-UI-010)
cd /tmp/ws-test && nix-shell -p openssl.dev pkg-config --run "./target/release/c3i-planning-e2e"

# 4. DOM elements check (SC-AGUI-UI-001..007)
curl -sk https://localhost:4100/<page> | grep -oP 'id="[^"]*"' | sort -u | wc -l

# 5. API check (SC-GLM-UI-003)
for ep in health "api/v1/plan/status" "api/v1/ai/status"; do
  curl -sk -o /dev/null -w "%{http_code} $ep\n" "https://localhost:4100/$ep"
done

# 6. WebSocket check (SC-AGUI-UI-006)
curl -sk -i -H "Upgrade: websocket" -H "Connection: Upgrade" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGVzdA==" \
  https://localhost:4100/ws/<page> 2>&1 | grep "101"

# 7. Responsive check (SC-AGUI-UI-008)
curl -sk https://localhost:4100/<page> | python3 -c "
import sys,html; c=html.unescape(sys.stdin.read())
assert 'min-width:768px' in c, 'Missing tablet breakpoint'
assert 'min-width:1024px' in c, 'Missing desktop breakpoint'
assert 'min-height:44px' in c, 'Missing touch targets'
print('Responsive: PASS')
"

# 8. Wiring guard check (SC-WIRE-001)
grep "init()" lib/cepaf_gleam/src/cepaf_gleam/testing/wiring_guard.gleam | wc -l

# 9. Zero warnings check (SC-MUDA-001)
gleam build 2>&1 | grep "warning" | grep -v "test/" | wc -l | grep "^0$"

# 10. STAMP reference check
grep -c "SC-AGUI-UI" .claude/rules/agentic-ui-responsive-design.md

# 11. Ultrathink alignment (SC-ULTRA-001)
grep -c "Ultrathink\|Focus Area" .claude/rules/agentic-ui-responsive-design.md

# 12. AG-UI 32-event check
grep -c "AG-UI\|AGUI" .claude/rules/agentic-ui-responsive-design.md

# 13. Zettelkasten integration check
grep -c "Zettelkasten\|FTS5\|holon" .claude/rules/agentic-ui-responsive-design.md

# 14. Psi invariant check
grep -c "Psi-\|Omega-0" .claude/rules/agentic-ui-responsive-design.md

# 15. Allium spec check
grep -c "Allium\|allium" .claude/rules/agentic-ui-responsive-design.md

# 16. OODA + TPS/Jidoka check
grep -c "OODA\|Jidoka\|Toyota" .claude/rules/agentic-ui-responsive-design.md

# 17. Mathematical foundations check
grep -c "Shannon\|PageRank\|Chinese Postman\|FMEA" .claude/rules/agentic-ui-responsive-design.md

# 18. Zenoh + NIF + MoZ check
grep -c "Zenoh\|NIF\|MoZ" .claude/rules/agentic-ui-responsive-design.md

# 19. VSM layer mapping check
grep -c "S1\|S2\|S3\|S4\|S5" .claude/rules/agentic-ui-responsive-design.md

# 20. Inter-page DAG check
grep -c "PageRank\|G_nav\|SCC=1" .claude/rules/agentic-ui-responsive-design.md

# 21. SIL-6 checklist check
grep -c "SIL-6\|SC-SIL4\|fail-safe\|2oo3\|dying gasp" .claude/rules/agentic-ui-responsive-design.md

# 22. SOP check
grep -c "Pre-Flight\|Post-Flight\|Failure Recovery" .claude/rules/agentic-ui-responsive-design.md

# 23. Zettelkasten ingestion check
grep -c "zettel ingest\|holon\|Zettelkasten" .claude/rules/agentic-ui-responsive-design.md

# 24. Section count (must be >= 29)
grep -c "^## " .claude/rules/agentic-ui-responsive-design.md
```
