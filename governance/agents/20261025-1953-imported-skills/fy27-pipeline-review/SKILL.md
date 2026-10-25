---
name: fy27-pipeline-review
description: "Conduct a structured FY27 pipeline review for \"$ARGUMENTS\" (default: full pipeline):"
---

# FY27 Pipeline Review — Weekly pipeline health check with ZK recall

Conduct a structured FY27 pipeline review for "$ARGUMENTS" (default: full pipeline):

## Pre-Flight: ZK Recall
Before ANY analysis, search the FY27 Zettelkasten:
```
cd /home/an/dev/ver/c3i/sub-projects/work/gdrive/1-Work/FY27-Plan/zettelkasten
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten search "pipeline opportunity funnel"
/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten search "tracker deal"
```

## 1. Pipeline Snapshot
| Metric | Current | Target | Gap | Action |
|--------|---------|--------|-----|--------|
| Total pipeline value ($M) | | | | |
| Weighted pipeline ($M) | | | | |
| Pipeline coverage (vs quota) | | 3.5x | | |
| # Active opportunities | | | | |
| # New this week | | | | |
| # Closed-won this week | | | | |
| # Closed-lost this week | | | | |
| # Stale (>30 days no activity) | | 0 | | |

## 2. Pipeline by Stage (Design Win Funnel)
| Stage | # Deals | Value ($M) | Avg Age (days) | Conversion Rate |
|-------|---------|-----------|----------------|-----------------|
| Awareness | | | | |
| Evaluation | | | | |
| Design-In | | | | |
| Prototype | | | | |
| Qualification | | | | |
| Production | | | | |

## 3. Pipeline by OEM
| OEM | # Deals | Value ($M) | Biggest Deal | Risk Level |
|-----|---------|-----------|-------------|-----------|
| ARM | | | | |
| Nokia | | | | |
| Ericsson | | | | |
| Infinera | | | | |
| New Logos | | | | |

## 4. Stale Deal Audit
List every deal with no activity >14 days:
| Deal | OEM | Stage | Last Activity | Days Stale | Action |
|------|-----|-------|--------------|-----------|--------|
| | | | | | Advance / Kill / Park |

## 5. Top 5 Deals — MEDDPICC Quick Score
| Deal | Score /80 | Weakest Link | This Week's Action |
|------|----------|-------------|-------------------|
| 1. | | | |
| 2. | | | |
| 3. | | | |
| 4. | | | |
| 5. | | | |

## 6. Pipeline Math
```
Required pipeline = Quarterly quota x Coverage ratio (3.5x)
Current pipeline  = $___M
Gap               = $___M
To close gap:     Need ___ new opportunities at avg $___K each
```

## 7. This Week's Pipeline Actions (max 5)
| # | Action | Account | Owner | Due |
|---|--------|---------|-------|-----|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

## 8. Verification Gate
- [ ] All data sourced from ZK or CRM (no fabrication)
- [ ] Pipeline math verified (coverage ratio correct)
- [ ] Stale deals actioned (advance/kill/park decision)
- [ ] Top 5 MEDDPICC scores current
- [ ] Actions have owners and due dates
