---
name: zk-learn
description: After completing work, ingest all new and modified documents into BOTH Zettelkasten databases:
---

# Zettelkasten Learn — Ingest to BOTH brains

After completing work, ingest all new and modified documents into BOTH Zettelkasten databases:

## 1. C3I Zettelkasten (engineering docs, specs, rules)
```bash
sa-plan-daemon ingest-docs
```

## 2. FY27 Zettelkasten (sales docs, account plans, contacts)
```bash
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
cd /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten && $ZK import ..
```

## 3. Also re-import any new agents, rules, commands
```bash
$ZK import /home/an/dev/ver/c3i/.claude/agents/
$ZK import /home/an/dev/ver/c3i/.claude/commands/
$ZK import /home/an/dev/ver/c3i/.claude/rules/
```

## 4. Verify
Report for BOTH databases:
- Number of new holons created
- Total holons
- Key STAMP refs discovered

## 5. Stats
```bash
$ZK stats
```

This is SC-ZK-CLAUDE-002: Claude MUST ingest documents after completing work.
