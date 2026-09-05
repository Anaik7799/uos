---
name: zk-cost
description: name: zk-cost
---

---
name: zk-cost
description: Show live ZK/token/cost KPIs from smriti.db. Run before expensive LLM operations.
---

# /zk-cost — Live OODA KPIs

Runs `./sa-zk-metrics --ooda` and shows the current thresholds & alarms.

```bash
./sa-zk-metrics --ooda
./sa-zk-metrics --json    # for scripted consumption
curl -sk https://vm-1.tail55d152.ts.net:8443/task-id/116452500338698000/ooda-live.json
```

Targets: embedding_coverage_pct ≥ 95% · cache_hit_ratio ≥ 90% · cost_per_citation ≤ $0.05 · edges_total ≥ 10,000.

See `.gemini/rules/sc-zk-cost-optim-001.md` for the full rule and SC-ZK-COST-OPT-001 compliance.
