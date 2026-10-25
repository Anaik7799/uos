---
name: fractal-autopilot
description: Execute mandatory post-feature fractal evolution including regression, visual convergence, KPI/journal artifacts, link registry, ZK ingest, and email delivery.
version: 1
auto_trigger:
  - keywords: ["feature implemented", "post feature", "fractal autopilot", "evolution pipeline", "pi symbiosis verify"]
---

# Fractal Autopilot Skill

## Workflow
1. Ensure/obtain task-id from `sa-plan add`.
2. Generate fractal-criticality matrix (L0-L7 × components × RETE-UL/ruliology × STAMP × FMEA/FEMA) and sort actions by P0→P3.
3. Run regression: `scripts/fractal_feature_evolution_suite.sh <task-id>`.
4. Run recursive visual loop: `scripts/recursive_feature_convergence.sh <task-id> 3`.
5. Generate/update journal + analysis html + summary deck + matrix artifact.
6. Refresh links: `scripts/update_task_link_registry.sh <task-id>`.
7. Ingest docs: `sa-plan ingest-docs`.
8. Send email with artifacts and task-id URL.

## Output contract
- task-id URL at top of every generated MD/HTML artifact.
- Visual checklist JSON proving convergence.
- Fractal-criticality matrix artifact (md + json).
- Link registry JSON for dynamic artifact discovery.
