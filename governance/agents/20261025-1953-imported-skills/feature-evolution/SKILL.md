---
name: feature-evolution
description: Run the full fractal feature evolution pipeline after implementing a new feature.
---

# /feature-evolution — Complete Feature Evolution Pipeline

Run the full fractal feature evolution pipeline after implementing a new feature.

## Steps
1. Identify what changed (git diff, new files)
2. Run full regression: `gleam test` + `dart test` + `element_x_test`
3. Update KPI dashboard HTML with current metrics
4. Create 13-section journal entry in docs/journal/
5. Email journal + Tailscale link to Abhijit.Naik@bountytek.com
6. Generate fractal-criticality matrix (L0-L7 × components × RETE-UL/ruliology × STAMP × FMEA/FEMA) and execute remaining work in P0→P3 order
7. Ingest journal + matrix to Zettelkasten
8. Update MEMORY.md with session findings
9. Confirm dashboard accessible at https://vm-1.tail55d152.ts.net:4200/kpi

## Verification
- All test suites green
- Dashboard loads in browser
- Email received with attachment
- ZK search finds the new feature

## STAMP
SC-FEAT-EVO-001..008
