---
name: fy27-status
description: "Pull the complete current status for \"$ARGUMENTS\" (default: full dashboard):"
---

# FY27 Status Dashboard -- Instant status from Zettelkasten

Pull the complete current status for "$ARGUMENTS" (default: full dashboard):

## Execution

Search BOTH Zettelkasten databases for current state:

FY27-ZK (sales data):
```
cd /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
$ZK stats
$ZK search "activity log 2026"
$ZK search "meeting 2026"
$ZK search "deal opportunity pipeline"
$ZK search "decision 2026"
$ZK search "follow-up action pending"
```

C3I-ZK (engineering + planning): Use MCP knowledge_search tool.

## Dashboard Output

### 1. Pipeline Status
| Metric | Value | Trend |
|--------|-------|-------|
| Total pipeline ($M) | (from ZK) | |
| Weighted pipeline ($M) | | |
| Pipeline coverage | | |
| Active deals | | |
| Stale deals (>14 days) | | |

### 2. Account Status
| Account | Last Touch | Open Deals | Next Action | Health |
|---------|-----------|-----------|-------------|--------|
| ARM | | | | Green/Amber/Red |
| Nokia | | | | |
| Ericsson | | | | |
| Infinera | | | | |
| New Logos | | | | |

### 3. Recent Activities (last 7 days)
| Date | Category | Account | Activity | Outcome |
|------|----------|---------|----------|---------|
| (from activity logs in ZK) | | | | |

### 4. Upcoming Actions (next 7 days)
| Due | Action | Account | Owner | Priority |
|-----|--------|---------|-------|----------|
| (from follow-ups in ZK) | | | | |

### 5. Open Decisions
| Decision | Account | Due | Status |
|----------|---------|-----|--------|
| (from decision records in ZK) | | | |

### 6. Key Metrics (this week vs last week)
| Metric | This Week | Last Week | Delta |
|--------|-----------|-----------|-------|
| Meetings held | | | |
| Emails sent | | | |
| LinkedIn touches | | | |
| Proposals sent | | | |
| Deals advanced | | | |

### 7. Alerts
Flag anything requiring immediate attention:
- Overdue follow-ups (past due date)
- Stale accounts (no activity >14 days)
- At-risk deals (MEDDPICC <40)
- Missing data (accounts with no recent activity log)

### 8. Data Freshness
| Source | Last Updated | Status |
|--------|-------------|--------|
| FY27-ZK | (from stats) | Fresh/Stale |
| C3I-ZK | (from ingest) | Fresh/Stale |
| Activity logs | (latest file date) | Fresh/Stale |
| Pipeline tracker | (file date) | Fresh/Stale |

## Verification
- All data sourced from ZK (no fabrication)
- Stale data flagged explicitly
- Gaps identified (missing accounts, outdated contacts)
