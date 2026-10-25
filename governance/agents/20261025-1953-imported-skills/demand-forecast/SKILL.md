---
name: demand-forecast
description: "Build a demand forecast for \"$ARGUMENTS\":"
---

# Demand Forecast — Semiconductor demand planning and forecasting

Build a demand forecast for "$ARGUMENTS":

## 1. Forecast Methodology
| Method | Use When | Accuracy | Horizon |
|--------|---------|----------|---------|
| **Bottoms-up** (design win rollup) | Named accounts, active programs | High (near-term) | 1-4 quarters |
| **Top-down** (market x share) | New segments, territory planning | Medium | 4-12 quarters |
| **Run-rate** (trailing x growth) | Stable/mature products | Medium | 1-4 quarters |
| **Leading indicators** | Early signal detection | Variable | 2-8 quarters |
| **Consensus** (weighted average) | Final plan number | Highest | All |

## 2. Leading Indicators Dashboard
| Indicator | Signal | Current | Trend | Lead Time |
|-----------|--------|---------|-------|-----------|
| **PMI / ISM** | Manufacturing expansion/contraction | | | 3-6 months |
| **Auto production forecast** (IHS) | Vehicle build volume | | | 6-12 months |
| **Disti inventory (weeks)** | Channel health | | | 1-3 months |
| **Book-to-bill ratio** | Demand vs supply | | | 1-2 months |
| **Customer forecasts / POs** | Direct demand signal | | | 0-6 months |
| **Design win pipeline** | Future demand | | | 6-24 months |
| **Capex announcements** (hyperscalers) | Data center demand | | | 6-12 months |
| **Fab utilization** (TSMC, etc.) | Supply-side signal | | | 3-6 months |
| **Sample/EVK requests** | Early design activity | | | 12-24 months |
| **RFQ volume** | Active purchasing intent | | | 3-6 months |

## 3. Bottoms-Up Forecast (by account)
| Account | Product | FY-26 Actual | Q1 | Q2 | Q3 | Q4 | FY-27 Total | Confidence |
|---------|---------|-------------|----|----|----|----|-------------|-----------|
| | | | | | | | | H/M/L |
| **Total named** | | | | | | | | |
| **Unnamed / long tail** | | | | | | | | |
| **Grand Total** | | | | | | | | |

## 4. Top-Down Forecast (by segment)
| Segment | Market Size ($B) | Our Share % | FY-27 Revenue ($M) | Growth Driver |
|---------|-----------------|-----------|-------------------|---------------|
| | | | | |
| **Total** | | | | |

## 5. Scenario Planning
| Scenario | Probability | FY-27 Revenue | Assumptions | Trigger |
|----------|------------|-------------|-------------|---------|
| **Bull** | 20% | $___M | | |
| **Base** | 60% | $___M | | |
| **Bear** | 20% | $___M | | |
| **Probability-weighted** | | $___M | | |

## 6. Seasonality Pattern
| Quarter | Historical % of Annual | FY-27 Plan % | FY-27 Plan ($M) |
|---------|----------------------|-------------|----------------|
| Q1 | ___% | | |
| Q2 | ___% | | |
| Q3 | ___% | | |
| Q4 | ___% | | |

## 7. Backlog & Book-to-Bill
| Month | Bookings ($M) | Billings ($M) | B:B Ratio | Backlog ($M) | Backlog Coverage (months) |
|-------|-------------|-------------|-----------|-------------|--------------------------|
| | | | | | |

Target: B:B > 1.0 (growing), Backlog coverage > 3 months

## 8. Inventory & Supply Planning
| Product Family | Forecast (units) | Lead Time | Safety Stock | Build Plan | Supply Risk |
|---------------|-----------------|-----------|-------------|-----------|------------|
| | | | | | |

## 9. Forecast Accuracy Tracking
| Quarter | Forecast ($M) | Actual ($M) | Variance % | Bias (over/under) | Root Cause |
|---------|-------------|-----------|-----------|-------------------|-----------|
| Q1 FY-26 | | | | | |
| Q2 FY-26 | | | | | |
| Q3 FY-26 | | | | | |
| Q4 FY-26 | | | | | |

**MAPE** (Mean Absolute % Error): ___%
**Bias**: Systematic over-forecast or under-forecast?
**Target**: MAPE < 10%, zero systematic bias

## 10. Risk-Adjusted Forecast
```
Gross forecast:           $___M
- Slippage risk (___%)    ($___M)  [historical slip rate]
- Churn risk (___%)       ($___M)  [customer loss probability]
- Competitive risk (___%) ($___M)  [socket loss probability]
+ Upside (___%)           $___M   [unforecasted wins]
= Risk-adjusted forecast: $___M
```
