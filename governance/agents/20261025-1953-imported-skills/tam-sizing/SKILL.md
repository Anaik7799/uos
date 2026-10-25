---
name: tam-sizing
description: "Size the market for \"$ARGUMENTS\":"
---

# TAM/SAM/SOM Sizing — Market sizing with bottoms-up and top-down approaches

Size the market for "$ARGUMENTS":

## 1. Market Definition
- **Product/service scope**: What exactly are we sizing?
- **Geographic scope**: Global, regional, country-specific?
- **Customer scope**: All buyers or specific segments?
- **Time horizon**: Current year, 3-year, 5-year?
- **Currency and units**: USD, EUR? Units shipped, revenue, ASP?

## 2. Top-Down Approach (TAM)
Start from total market, narrow down:
```
Total semiconductor market ($___B, source: WSTS/SIA/Gartner)
  x Relevant segment share (___%)
  = Segment TAM: $___B

Segment TAM: $___B
  x Our addressable geography (___%)
  x Our addressable end-markets (___%)
  = SAM: $___B

SAM: $___B
  x Realistic market share (___%)
  = SOM: $___M
```

| Level | Value | Method | Source | Confidence |
|-------|-------|--------|--------|-----------|
| TAM | $___B | Industry reports | WSTS, Gartner, IDC | High |
| SAM | $___B | Segment + geo filter | Analyst + internal | Medium |
| SOM | $___M | Win rate x pipeline | Internal data | Medium-Low |

## 3. Bottoms-Up Approach (Validation)
Build from individual opportunities:
```
# of target accounts: ___
x Average annual spend per account: $___
x Our addressable share of spend: ___%
= Bottoms-up SOM: $___M

Cross-check:
# of design wins in pipeline: ___
x Average lifetime revenue per win: $___
x Win probability: ___%
= Pipeline-based SOM: $___M
```

## 4. Segment Breakdown
| Sub-segment | TAM ($M) | CAGR % | SAM ($M) | SOM ($M) | Key Drivers |
|------------|----------|--------|----------|----------|-------------|
| | | | | | |
| **Total** | | | | | |

## 5. Geographic Breakdown
| Region | TAM ($M) | % of Total | Growth % | Key Markets |
|--------|----------|-----------|----------|-------------|
| Americas | | | | USA, Mexico, Brazil |
| EMEA | | | | Germany, Nordics, UK, France |
| APAC | | | | China, Japan, Korea, India |
| **Total** | | | | |

## 6. Growth Drivers & Headwinds
| Factor | Direction | Impact | Timeframe | Confidence |
|--------|-----------|--------|-----------|-----------|
| | Tailwind | | | |
| | Headwind | | | |

## 7. Scenario Analysis
| Scenario | Probability | SOM ($M) | Assumptions |
|----------|------------|----------|-------------|
| Bull case | 20% | | Strong design wins, fast ramp, ASP holds |
| Base case | 60% | | Normal cycles, moderate growth |
| Bear case | 20% | | Inventory correction, delayed ramps, ASP erosion |
| **Probability-weighted SOM** | | | |

## 8. Data Sources
| Source | Type | Coverage | Cost | Freshness |
|--------|------|----------|------|-----------|
| WSTS | Industry stats | Global semi market | Free/paid | Quarterly |
| SIA (Semiconductor Industry Association) | Policy + data | US focus | Free | Monthly |
| Gartner | Analyst reports | Full coverage | $$$ | Quarterly |
| IDC | Analyst reports | Market share | $$$ | Quarterly |
| Omdia/Informa | Analyst reports | Components | $$ | Monthly |
| TechInsights | Teardowns | Bill of materials | $$ | Ongoing |
| Company earnings calls | Public filings | Individual companies | Free | Quarterly |
| Job postings | Hiring signals | Growth indicators | Free | Real-time |

## 9. Validation Checklist
- [ ] Top-down and bottoms-up within 2x of each other
- [ ] Growth rates consistent with industry forecasts
- [ ] Geographic split matches known market distribution
- [ ] ASP assumptions validated against current pricing
- [ ] No double-counting across segments
- [ ] Sources cited for all external data points
