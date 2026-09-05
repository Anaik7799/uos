# Zettelkasten + Gleam Agent Integration for Claude (SC-ZK-GEMINI)
# HIGHEST PRIORITY REQUIREMENT
# CROSS-REF: `.claude/rules/zk-imperative-recall.md` (SC-ZK-IMP — mandatory citation protocol)

## SUPREME MANDATE
**Gemini MUST use the Zettelkasten for memory and Gleam NIF functions for computation. Every session. No exceptions.**
**Gemini MUST CITE holon IDs from ZK recall in every response. See SC-ZK-IMP-001..006.**

## STAMP Constraints
| ID | Constraint | Severity |
|----|------------|----------|
| SC-ZK-GEMINI-001 | Gemini MUST search Zettelkasten BEFORE starting any task | CRITICAL |
| SC-ZK-GEMINI-002 | Gemini MUST ingest documents to Zettelkasten AFTER completing work | CRITICAL |
| SC-ZK-GEMINI-003 | Gemini MUST use Graphene NIF for graph analysis instead of manual reasoning | HIGH |
| SC-ZK-GEMINI-004 | Gemini MUST use sa-plan-daemon for all task management | CRITICAL |
| SC-ZK-GEMINI-005 | Gemini MUST check prior patterns in Zettelkasten before proposing solutions | HIGH |
| SC-ZK-GEMINI-006 | Gemini MUST use coverage_math for test quality assessment | HIGH |

## Dual Zettelkasten Architecture
The system operates TWO Zettelkasten databases in parallel:

| ZK | Database | Binary | Content | Holons |
|----|----------|--------|---------|--------|
| **C3I-ZK** | `data/kms/smriti.db` | `sa-plan-daemon knowledge-search` | Engineering: code patterns, architecture, journals, constraints | 2,600+ |
| **FY27-ZK** | `sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten/fy27-plan.db` | `sub-projects/work/fy27-zk-build/release/fy27-zettelkasten search` | Sales: accounts, contacts, rate cards, proposals, competitive intel | 475+ |

Both are searched on every `UserPromptSubmit` hook. Both are ingested on every `Stop` hook.

For sales/account/ARM/Nokia/pipeline queries → FY27-ZK has the data.
For engineering/Gleam/Rust/architecture queries → C3I-ZK has the data.

## Session Start Protocol
```bash
# 1. Search BOTH Zettelkasten for context on current task
sa-plan-daemon knowledge-search "<task keywords>"
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
$ZK search "<task keywords>"

# 2. Check system health
sa-plan-daemon status

# 3. Check gleam builds
cd lib/cepaf_gleam && gleam build

# 4. Check FY27 ZK health
$ZK stats
```

## During Work Protocol
```bash
# For graph questions: Use NIF, don't reason manually
# WRONG: "The navigation graph has 31 pages, they form a complete graph..."
# RIGHT: Run graphene_scc via gleam test to verify

# For math: Use NIF functions
# WRONG: Manually compute PageRank
# RIGHT: graphene_pagerank_typed(pages, edges, 0.85, 30)

# For diagrams: Use NIF rendering
# WRONG: ASCII art state machine
# RIGHT: skia_render_machine() or mermaid_render_machine()

# For color checks: Use NIF
# WRONG: "This hex color should work for dark mode"
# RIGHT: bevy_color_srgba_to_oklch() to verify perceptual uniformity
```

## Session End Protocol
```bash
# 1. Ingest all new documents to BOTH Zettelkasten
sa-plan-daemon ingest-docs
cd sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten && $ZK import ..

# 2. Email summary
sa-plan-daemon send-email --to Abhijit.Naik@bountytek.com --subject "Session Summary" --body "..."

# 3. Update memory
# Write to .claude/projects/*/memory/ with session learnings
```

## Available Zettelkasten Commands
| Command | Use When |
|---------|----------|
| `sa-plan-daemon knowledge-search "query"` | Before starting ANY task |
| `sa-plan-daemon ingest-docs` | After creating/modifying docs |
| `sa-plan-daemon status` | Check task state |
| `sa-plan-daemon list pending` | Find work to do |

## Available Gleam NIF Compute (125 functions)
| Package | Functions | Use Instead Of |
|---------|-----------|---------------|
| `graphene_*` | 15 | Manual graph reasoning |
| `petgraph_*` | 13 | Manual shortest path / cycle detection |
| `kurbo_*` | 42 | Manual SVG / geometry calculations |
| `skia_*` | 5 | External diagram tools |
| `mermaid_*` | 7 | Mermaid CLI / browser rendering |
| `vega_lite_*` | 16 | Manual chart JSON construction |
| `bevy_color_*` | 6 | Manual color math |
| `bevy_math_*` | 6 | Manual 3D math |
| `bevy_ecs_*` | 3 | Manual entity tracking |
| `grafana_*` | 9 | Manual dashboard JSON |

## How to Call NIF Functions from Claude
```bash
# Option 1: Via gleam test (create a test that calls the function)
cd lib/cepaf_gleam && gleam test -- --module graphene_render_test

# Option 2: Via erl eval (within OTP context)
cd lib/cepaf_gleam && gleam run -m graphene_quick_check

# Option 3: Via the running server's API
curl -s https://localhost:4100/api/v1/graph/analyze
```
