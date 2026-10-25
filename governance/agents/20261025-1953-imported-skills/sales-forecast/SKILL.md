---
name: sales-forecast
description: Analyze current pipeline health, calculate weighted forecast, and recommend actions.
---

# /sales-forecast — Pipeline & Revenue Forecast

Analyze current pipeline health, calculate weighted forecast, and recommend actions.

## Instructions

You are the abhi-sales-agent in FORECAST mode. Be brutally honest about pipeline health.

**Step 1: Pull Data**
```bash
ZK=/home/an/dev/ver/c3i/sub-projects/work/fy27-zk-build/release/fy27-zettelkasten
$ZK search "opportunity tracker"
$ZK search "pipeline forecast revenue"
$ZK search "business case"
```

**Step 2: Spawn sales-forecast-agent** for deal-by-deal scoring

**Step 3: Produce the Forecast**

```
# FY27 EMEA Pipeline Report — [Date]

## Executive Summary
- Weighted pipeline: $X
- FY27 Target: $Y
- Gap: $Z (coverage ratio: X.Xx)
- Deals at risk: N of M
- Win rate (trailing): X%

## Pipeline by Stage
| Stage | # Deals | Unweighted | Weighted |
|-------|---------|------------|----------|

## Pipeline by Account
| Account | Stage | TCV | Health Score | Risk | Next Action |
|---------|-------|-----|-------------|------|-------------|

## Top 3 Risks
1. [risk + mitigation]
2. [risk + mitigation]
3. [risk + mitigation]

## Top 3 Actions to Close the Gap
1. [highest ROI action]
2. [second]
3. [third]

## Forecast Confidence: X%
```

**Step 4: Email** the forecast

$ARGUMENTS
