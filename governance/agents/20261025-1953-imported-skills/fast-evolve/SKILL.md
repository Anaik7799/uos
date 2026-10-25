---
name: fast-evolve
description: Unlike `/evolve-sil6` (full formal verification), this command optimizes for SPEED
---

# Command: /fast-evolve
# त्वरित-विकास — Rapid Evolution via Gita Protocol

**Description**: Maximum-velocity page/feature evolution using parallel agent swarm.
Unlike `/evolve-sil6` (full formal verification), this command optimizes for SPEED
while maintaining build+test quality gates.

**Usage**: `/fast-evolve <target>` — e.g., `/fast-evolve dashboard`, `/fast-evolve cockpit`

**Agent Instructions**:

When invoked, execute this protocol WITHOUT human interaction until completion:

## Phase 1: Observe (अवलोकन) — 10s budget
1. Read the target page's current state (Lustre, Wisp, TUI)
2. Check Zettelkasten for prior patterns: `sa-plan-daemon zettel search --tags "<target>"`
3. Check memory for anti-patterns

## Phase 2: Orient (अभिविन्यास) — 5s budget
4. Identify what needs evolution (reference: planning page spec)
5. Map to SC-ULTRA-001 focus areas
6. Check file sizes — if > 1000 lines, split FIRST (SC-FILESIZE-001)

## Phase 3: Decide (निर्णय) — 5s budget
7. Plan the parallel agent dispatch:
   - Agent A: JS interactivity (priv/static/<page>-grid.js)
   - Agent B: SSR HTML (page_views or split module)
   - Agent C: WebSocket handler (server.gleam /ws/<page>)
   - Agent D: API endpoints (router.gleam)
   - Agent E: TUI view (tui/<page>_view.gleam)
   - Agent F: Tests (test/<page>_comprehensive_test.gleam)

## Phase 4: Act (कर्म) — max parallel
8. Launch Agents A-F simultaneously using `run_in_background: true`
9. While agents run, verify build incrementally
10. Fix any compilation errors immediately

## Phase 5: Verify (सत्यापन) — fail-fast
11. `gleam build` — 0 errors
12. `gleam test` — 0 failures
13. Check file sizes — all modified files < 1000 lines

## Quality Gates (गुणवत्ता द्वार)
- Zero compilation errors (SC-FUNC-001)
- Zero new warnings (SC-MUDA-001)
- All existing tests pass
- New tests: 100+ per evolved page
- Triple-interface: Lustre + Wisp + TUI (SC-GLM-UI-001)
- WebSocket real-time push (SC-AGUI-UI-006)
- L0-L7 fractal layers addressed (SC-FRACTAL-001)

## Gita Protocol Activation (गीता प्रोतोकॉल)
- NO human approval needed for file writes
- NO human approval needed for builds/tests
- NO human approval needed for new file creation
- INFORM human only at completion with summary
- ESCALATE only for L0 Constitutional safety changes

## Mathematical Optimization
```
Target: V_ooda >= 3x baseline
Method: 6 parallel agents × incremental verify × zero wait
Budget: Complete evolution in < 15 minutes wall clock
```

## Sanskrit Wisdom
> योगस्थः कुरु कर्माणि सङ्गं त्यक्त्वा धनञ्जय
> Established in yoga, perform action, abandoning attachment, O Dhananjaya
> — Bhagavad Gita 2.48
