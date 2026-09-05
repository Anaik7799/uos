---
name: zk-recall
description: Before starting work on \"$ARGUMENTS\", search BOTH Zettelkasten databases:
---

# Zettelkasten Recall — Search BOTH brains before acting

Before starting work on "$ARGUMENTS", search BOTH Zettelkasten databases:

## 1. C3I Zettelkasten (engineering, architecture, code patterns)
```bash
sa-plan-daemon knowledge-search "$ARGUMENTS"
sa-plan-daemon knowledge-search "$ARGUMENTS anti-pattern"
sa-plan-daemon knowledge-search "$ARGUMENTS journal RCA"
```

## 2. FY27 Zettelkasten (sales, accounts, contacts, competitive intel)
```bash
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
$ZK search "$ARGUMENTS"
$ZK contacts "$ARGUMENTS"
```

## 3. Synthesize
- Summarize what BOTH Zettelkasten know about this topic
- List any anti-patterns to avoid
- Identify which prior decisions are still relevant
- For sales/account queries: activate abhi-sales-agent mode
- For engineering queries: use Gleam NIF compute
- Apply SC-AVP verification to any analysis output
- Only then proceed with the task

This is SC-ZK-CLAUDE-001: Claude MUST search Zettelkasten BEFORE starting ANY task.

$ARGUMENTS
