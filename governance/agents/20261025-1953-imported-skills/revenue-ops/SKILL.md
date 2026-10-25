---
name: revenue-ops
description: "Analyze and optimize revenue operations for \"$ARGUMENTS\":"
---

# Revenue Operations — Optimize the revenue engine

Analyze and optimize revenue operations for "$ARGUMENTS":

## 1. Revenue Architecture
```
Marketing → MQL → SQL → SAL → Opportunity → Design Win → Revenue
         (Lead Gen) (Qualify) (Accept) (Pipeline) (Commit) (Ship)
```

### Funnel Metrics
| Stage | Volume | Conversion % | Velocity (days) | Value ($) |
|-------|--------|-------------|-----------------|-----------|
| Leads / MQLs | | | | |
| SQLs (qualified) | | | | |
| SALs (accepted by sales) | | | | |
| Opportunities created | | | | |
| Design wins / commits | | | | |
| Revenue (shipped) | | | | |

## 2. Pipeline Analytics
| Metric | Current | Target | Gap | Action |
|--------|---------|--------|-----|--------|
| Pipeline coverage (x quota) | | 3-4x | | |
| Weighted pipeline | | | | |
| Pipeline created / month | | | | |
| Pipeline velocity ($M/day) | | | | |
| Win rate (overall) | | | | |
| Win rate (by segment) | | | | |
| Average deal size | | | | |
| Sales cycle (days) | | | | |

## 3. Forecasting Model
| Category | Definition | Revenue ($M) | Confidence |
|----------|-----------|-------------|-----------|
| **Closed** | Booked, shipping | | 100% |
| **Commit** | Verbal PO, high certainty | | 90%+ |
| **Best case** | Strong pipeline, likely this Q | | 60-80% |
| **Upside** | Possible, needs acceleration | | 30-50% |
| **Pipeline** | Early stage, future quarters | | 10-25% |

Forecast = Closed + (Commit x 0.9) + (Best case x 0.7) + (Upside x 0.4)

## 4. Territory & Quota Design
| Territory | Rep | Quota ($M) | Pipeline ($M) | Coverage | Attainment YTD |
|-----------|-----|-----------|--------------|----------|---------------|
| | | | | | |

**Quota-setting methodology**: Top-down (from plan) + bottoms-up (from accounts) = balanced quota
**Capacity model**: # reps x avg quota = achievable revenue. Current capacity vs plan gap.

## 5. Lead Scoring Model
| Signal | Weight | Source | Decay |
|--------|--------|--------|-------|
| Datasheet download | +10 | Website | 30 days |
| Sample request | +25 | Website/Disti | 60 days |
| EVK purchase | +30 | E-commerce | 90 days |
| Webinar attended | +15 | Marketing | 30 days |
| Trade show scan | +10 | Events | 14 days |
| Content engagement (3+ assets) | +20 | Marketing | 30 days |
| Job title match (engineer) | +15 | Enrichment | Static |
| Company size match | +10 | Enrichment | Static |
| Active RFQ | +40 | Sales | 14 days |
| **MQL threshold** | **70+** | | |

## 6. Sales Process & Methodology
| Stage | Exit Criteria | Required Evidence | Tools |
|-------|-------------|-------------------|-------|
| Prospect | Confirmed ICP fit | Contact + company verified | LinkedIn, ZoomInfo |
| Discover | Pain identified + quantified | Discovery notes, MEDDPICC started | CRM, call recording |
| Evaluate | Technical validation done | Sample/EVK shipped, FAE engaged | Lab, design tools |
| Propose | Solution mapped to needs | Proposal sent, pricing agreed | CPQ, proposal tool |
| Negotiate | Terms agreed | Legal/procurement engaged | Contract management |
| Commit | Design win confirmed | PO received or verbal commit | CRM, ERP |
| Ramp | Production shipping | Revenue recognized | ERP, logistics |

## 7. Tech Stack Assessment
| Function | Current Tool | Gaps | Recommended | Priority |
|----------|-------------|------|-------------|----------|
| CRM | | | Salesforce / HubSpot | |
| Marketing automation | | | HubSpot / Marketo | |
| Sales engagement | | | Outreach / Salesloft | |
| Conversation intel | | | Gong / Chorus | |
| CPQ | | | Salesforce CPQ | |
| BI / Analytics | | | Tableau / PowerBI | |
| Data enrichment | | | ZoomInfo / Apollo | |
| Design registration | | | Custom / Disti portal | |

## 8. RevOps Rhythm
| Cadence | Attendees | Focus | Output |
|---------|-----------|-------|--------|
| Daily standup | SDR/AE team | Activities, blockers | Actions |
| Weekly pipeline | AE + Manager | Deal progression | Forecast update |
| Monthly business | Sales + Marketing + RevOps | Pipeline health, metrics | Course corrections |
| QBR | Leadership + cross-functional | Strategy, forecast, plan | Quarterly plan update |
| Annual planning | All GTM | FY plan, quota, territory | Annual operating plan |

## 9. KPI Dashboard
| KPI | Formula | Frequency | Owner |
|-----|---------|-----------|-------|
| Pipeline velocity | (# opps x win rate x avg deal) / cycle days | Weekly | RevOps |
| Marketing ROI | Pipeline generated / marketing spend | Monthly | Marketing |
| Sales productivity | Revenue / headcount | Monthly | Sales ops |
| Quota attainment | Bookings / quota | Monthly | Finance |
| Forecast accuracy | |Forecast - Actual| / Actual | Quarterly | RevOps |
| CAC | Total S&M cost / new customers | Quarterly | Finance |
| NRR | (Start + expansion - churn) / start | Quarterly | CS |
