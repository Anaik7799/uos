---
name: fy27-obsidian-sync
description: "Run Obsidian sync for \"$ARGUMENTS\" (default: full sync):"
---

# FY27 Obsidian Sync -- Sync Obsidian vault with both Zettelkasten databases

Run Obsidian sync for "$ARGUMENTS" (default: full sync):

## Sync Operations

### 1. full (default)
Import all FY27-Plan markdown files to both ZKs:
1. Run FY27-ZK import: cd zettelkasten && $ZK import ..
2. Run C3I-ZK ingest: MCP knowledge_ingest
3. Report: files imported, holons count, contacts count

### 2. status
Check sync status:
1. Count .md files in FY27-Plan/
2. Run $ZK stats for FY27-ZK holon count
3. Compare timestamps (newest file vs last import)
4. Report freshness

### 3. home
Update HOME.md (Map of Content) with current state:
1. Scan activities/ for recent logs
2. Scan activities/meetings/ for recent meetings
3. Scan activities/decisions/ for recent decisions
4. Update Quick Links and Research sections
5. Add any new account plans

### 4. graph
Generate a text representation of the Obsidian graph:
1. Scan all .md files for [[wikilinks]]
2. Build adjacency list
3. Report: nodes (files), edges (links), orphans (unlinked files)
4. Suggest links for orphan files

### 5. templates
Verify all templates exist and are current:
1. Check templates/daily-activity-log.md
2. Check templates/meeting-note.md
3. Check templates/decision-record.md
4. Check templates/account-plan.md
5. Report any missing templates

## Post-Sync
1. Report sync results
2. Log to activity file: /fy27-log task "Obsidian sync: N files, N holons"
