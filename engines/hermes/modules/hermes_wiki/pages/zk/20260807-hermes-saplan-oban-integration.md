---
migrated_from: docs/zk/20260807-hermes-saplan-oban-integration.md (zigvm-era tree, authored for Hermes)
---
# Architectural Decision: SA-Plan and Oban for Task Management

**Date:** August 7, 2026
**Topic:** Hermes OCaml Job Scheduling & Orchestration

## Decision
1. **Task Management & Scheduling:** We will completely discard ad-hoc threading or Python-style async task queues (e.g., Celery) for the Hermes OCaml port. Instead, we will natively integrate the `zigvm_harness`'s existing `sa_plan` infrastructure.
2. **Oban Equivalent:** All long-running tool executions, background tasks, and sub-agent orchestrations will be scheduled as persistent jobs using the `sa_plan_oban.ml` and `sa_plan_store.ml` modules provided by the harness.

## Rationale
- **Resilience and Durability:** `sa_plan` provides database-backed, transactional job execution equivalent to Elixir's Oban. This ensures that long-running agent tasks (like web scraping, model fine-tuning, or complex tool execution) survive system restarts or crashes.
- **Harness Integration:** Utilizing the existing `sa_plan` aligns the Hermes agent directly with the underlying harness's Autonomous Execution Engine (AEE). It ensures that the SDLC and SRE specifications defined in the harness natively monitor and manage the agent's workload.
- **Fractal Scaling:** Because `sa_plan` supports multi-agent and distributed task coordination, delegating tasks to sub-agents (a core Hermes feature) becomes a natural extension of pushing an Oban job onto the persistent queue, maintaining strict algebraic boundaries.