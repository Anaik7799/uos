# SC-ZK-COST-OPT-001 — Closed-Loop Agentic ZK Cost Optimization

**STAMP**: SC-ZK-COST-OPT-001 (new, pass-7)
**Task**: 116452500338698000
**ZK origin**: [zk-6e88c8749efc66d5] (pass-5), [zk-d3edd671b66e5e3e] (pass-4 FMEA), [zk-299d285fbb18ad13] (dispatcher)
**Layer**: L4 System · L5 Cognition · L7 Federation (SRE rollup)
**Priority**: P0

## 1. Purpose

Every agent operation on the C3I mesh MUST participate in the closed-loop OODA optimization for ZK/token/cost. This means:

1. **Observe** the live KPI view (`v_ooda_live` in smriti.db) BEFORE initiating an LLM inference or expensive job.
2. **Orient** against thresholds (embedding coverage ≥ 95 %, cache hit ≥ 90 %, cost/citation ≤ $0.05, edges ≥ 10k).
3. **Decide** via `rules/dispatcher.decision_to_action` using the RuleResult from `rules/engine.evaluate`.
4. **Act** — dispatch to Zenoh, emit OTel span, persist outcome to `session_metrics`.

## 2. Mandatory KPIs per operation

For every session, task, job, or plan the system MUST record:

| KPI | Table column | Captured by |
|---|---|---|
| `zk_recalls` | `session_metrics.zk_recalls` | Pi hook + Claude hook + cortex RAG |
| `zk_citations` | `session_metrics.zk_citations` | zk-recall counter + message scan |
| `tokens_input` | `session_metrics.tokens_input` | `after_provider_response` event |
| `tokens_output` | `session_metrics.tokens_output` | `after_provider_response` event |
| `tokens_cache_read` | `session_metrics.tokens_cache_read` | `after_provider_response` event |
| `tokens_cache_write` | `session_metrics.tokens_cache_write` | `after_provider_response` event |
| `cost_usd` | `session_metrics.cost_usd` | `after_provider_response.cost.total` |
| `cache_hit_ratio` | `session_metrics.cache_hit_ratio` | computed on shutdown |
| `tool_calls` | `session_metrics.tool_calls` | `tool_call` event |

Plus stage-level telemetry in `pipeline_stage_metrics`: `intent / recall / rag / rerank / inference / dispatch / cache_hit` etc.

## 3. Agent checklist (before any LLM call)

```bash
# 1. snapshot OODA view
./sa-zk-metrics --json

# 2. if embedding_coverage_pct < 50 → defer to embed_refresh job
# 3. if cache_hit_ratio < 0.7 → prefer recall over fresh inference
# 4. if cost_per_citation > 0.10 → do ZK recall first, inject cached context
# 5. if alarms/edges_low active → batch link extraction
```

## 4. Hooks required

| Agent | Hook | File | Status |
|---|---|---|---|
| Claude | `UserPromptSubmit` | `.claude/settings.json` | ✅ active since pass-5 |
| Claude | `SessionStart` | `.claude/settings.json` | ✅ active |
| Claude | `Stop` | `.claude/settings.json` | ✅ active |
| Pi | `before_agent_start` | `.pi/extensions/zk-recall.ts` | ✅ added pass-7 |
| Pi | `after_provider_response` | `.pi/extensions/zk-recall.ts` | ✅ added pass-7 |
| Pi | `session_shutdown` | `.pi/extensions/zk-recall.ts` | ✅ added pass-7 |
| Gemini | equivalent | `.gemini/extensions/…` | ⚠️ pass-8 |
| Cortex | RAG auto-inject | `cortex.rs:1557-1578` | ✅ already in prod |

## 5. Closed-loop rule bindings (pass-8 target)

```gleam
// Pseudocode, to land in rules/engine.gleam
fn sre_rules() -> String { "
  rule \"HighCostPerCitation\" when
    SessionMetrics.cost_per_citation > 0.05
  then decision = \"Escalate\"; reason = \"cost/citation > threshold\"
  rule \"LowCacheHit\" when
    SessionMetrics.cache_hit_ratio < 0.70
  then decision = \"PrefixRefactor\"; reason = \"cache hit below target\"
  rule \"LowEmbeddingCoverage\" when
    KmsState.embedding_coverage_pct < 50.0
  then decision = \"EmbedRefresh\"; reason = \"semantic search blind on >50% of KMS\"
  rule \"LowEdgeCoverage\" when
    KmsState.edges_total < 10000
  then decision = \"LinkExtractorBatch\"; reason = \"graph-walk substrate thin\"
"}
```

Dispatcher.Action already supports `Escalate`, `RestartContainer`, `ScaleDown`, `LogAndContinue`. New `PrefixRefactor`, `EmbedRefresh`, `LinkExtractorBatch` actions must be added.

## 6. Live endpoints

| URL | Role |
|---|---|
| `https://vm-1.tail55d152.ts.net:8443/task-id/116452500338698000/20260423-060231-…-ooda-metrics.html` | Human dashboard |
| `https://vm-1.tail55d152.ts.net:8443/task-id/116452500338698000/ooda-live.json` | Machine-readable feed (polled every 60 s) |
| Zenoh `indrajaal/l4/sre/ooda/snapshot` | Full payload |
| Zenoh `indrajaal/l4/sre/<metric>` | Per-metric topic |
| Zenoh `indrajaal/l4/sre/alarm/<rule>` | Threshold breach events |

## 7. CLI surface

```bash
./sa-zk-metrics                  # human-readable
./sa-zk-metrics --json           # agent-readable
./sa-zk-ooda-snapshot            # refresh JSON once
./sa-zk-zenoh-publisher 0        # one-shot publish
./sa-zk-zenoh-publisher 60 &     # background 60-s loop
./sa-plan zk-recall "<q>"        # recall pipeline
./sa-plan knowledge-search "<q>" # FTS5 only
./sa-plan semantic-search "<q>"  # embedding only
./sa-plan embed                  # backfill embeddings
```

## 8. Anti-patterns (BLOCKING)

1. Making an LLM call without first consulting `v_ooda_live` → BLOCK.
2. Shipping a session whose `session_metrics` row is not persisted → BLOCK.
3. New agent type without parity hooks → BLOCK.
4. Rule firing without `dispatcher.dispatch` → BLOCK (see pass-6 SC-OODA-003).
5. Metric emitted without matching OTel span on Zenoh → BLOCK.
6. Any deployment that changes cost per citation by > 50 % without an entry in `session_metrics` → BLOCK.

## 9. Cross-references

- `.agents/skills/zk-cost-optimizer/SKILL.md`
- `.gemini/rules/sc-pass5-auto-001.md` (report pipeline)
- `.claude/settings.json` (Claude hooks)
- `.pi/extensions/zk-recall.ts` (Pi hooks)
- `lib/cepaf_gleam/src/cepaf_gleam/rules/dispatcher.gleam` (decide → act)
- `lib/cepaf_gleam/src/cepaf_gleam/ha/claude_metrics.gleam` (Gleam counters)
- `sub-projects/c3i/native/planning_daemon/src/cortex.rs:1557` (auto-RAG)
- `docs/journal/20260422-recall-rag-agent-utilization-guide.md` (SC-RECALL-RAG)
- `docs/journal/20260423-060231-task-116452500338698000-zk-symbiosis-closure-ultrapass7-journal.md` (this pass)
