---
name: crm-hygiene
description: "Audit CRM/pipeline health for \"$ARGUMENTS\":"
---

# CRM Hygiene — Audit and clean pipeline data

Audit CRM/pipeline health for "$ARGUMENTS":

## 1. Pipeline Snapshot
- Total pipeline value and deal count
- Pipeline by stage (funnel shape analysis)
- Pipeline coverage ratio (pipeline / quota target)
- Weighted pipeline (stage probability x amount)

## 2. Data Quality Audit
Check for these common CRM hygiene issues:

| Issue | Check | Action |
|-------|-------|--------|
| **Stale deals** | No activity > 30 days | Move to nurture or close-lost |
| **Missing close dates** | Close date blank or in the past | Update or push to realistic date |
| **Stuck in stage** | Same stage > 2x average cycle | Investigate blocker or downgrade |
| **Missing contacts** | No decision-maker mapped | Research and add contacts |
| **No next step** | Next step field empty | Define concrete next action |
| **Zombie pipeline** | Close date pushed > 3 times | Qualify out or reset |
| **Missing MEDDPICC** | Key fields incomplete | Schedule discovery or review |
| **Overdue tasks** | Tasks past due date | Complete, reschedule, or cancel |

## 3. Pipeline Health Metrics
| Metric | Current | Benchmark | Status |
|--------|---------|-----------|--------|
| Pipeline coverage | | 3-4x quota | |
| Win rate | | Industry avg | |
| Average deal size | | | |
| Sales cycle length | | | |
| Stage conversion rates | | | |
| Pipeline created this month | | | |
| Deals pushed (this quarter) | | | |

## 4. Forecast Accuracy
- Compare last quarter's forecast vs actual
- Identify systematic bias (over-optimistic stages, sandbagging)
- Recommend forecast methodology adjustments

## 5. Prioritization Matrix
Rank deals by: (Deal size x Win probability x Urgency) / Effort required
- Top 5 deals to focus on this week
- Deals to nurture (long-term, low effort)
- Deals to qualify out (save time)

## 6. Action Items
Generate a prioritized list of CRM cleanup tasks, sorted by impact.
