# 20261027-1810 — UOS harness MCP comprehensive tool sweep

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This report](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1810-harness-tool-sweep.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Surface: `mcp__uos_harness` (Gleam/OTP `c3i-planning-mcp`). Method: every tool called once; no-arg read tools with `{}` (happy path), mutation tools with `{}` (validation/refusal guard), read tools with required args with valid minimal inputs. `verification_run` excluded (runs `gleam check`; deferred to the canary). Admiralty B2 (author-observed transport/functional check; not admission).

## Result: 53 tools — 41 functional, 4 fail-closed, 6 guard-proven, 1 schema bug, 1 deferred, 0 broken

### 1. Functional, happy path proven (41)
- **No-arg read/compute (26)**: plan_status, plan_list_pending, system_health, system_dashboard, system_immune, system_zenoh, system_verification, podman_containers, metabolic_state, ooda_phase, fractal_status, prajna_health, dark_cockpit_mode, integrity_check, evolution_metrics, mesh_topology, ooda_decide, kms_catalog, sa_plan_status, sa_plan_list, sciviz_extension_deep_dive, ggram_synthesize, mcp_capability_inventory, holon_status, swarm_status, agent_hierarchy.
- **Args happy path (15)**: plan_list, plan_get, plan_search, knowledge_search, read_file, forecast_predict, stpa_fmea_hazard, rete_rule_conflict, ruliad_branch_eval, shruti_harmonics, ast_anomaly_detect, lyapunov_trend_predict, feature_tracker_status, sa_plan_status_for, zk_transclude.

### 2. Fail-closed role guard (4) — correct, require a grant
`role_binding_missing`: harness_execution_progress, harness_system_feature_catalog, harness_system_feature_observations, harness_system_feature_intent. These are the privileged feature/execution surface; refusal is the expected no-grant behavior.

### 3. Mutation tools — validation guard proven, happy path deferred (6)
plan_add, plan_update, sa_task_claim, sa_task_complete, sa_job_enqueue, sa_workflow_start. Empty args correctly refused with `must have required property`. Happy path not exercised to avoid mutating the canonical Sa-plan / Planning.db outside a reviewed grant scope.

### 4. Schema mismatch — FLAGGED (1)
`preflight_check`: declared inputSchema is flat (`actor`,`action`,`benefit`,`cost`) but the implementation validates `params.arguments` as a nested map. Flat args → `Missing required params.arguments: …`; nested → `Validation failed`. Effectively unusable over the current MCP binding → repair needed in the Gleam tool declaration or validator.

### 5. Deferred (1)
`verification_run` — runs `gleam check`; deferred to the grant-gated canary, not run in this read-only sweep.

## Observations
- `system_zenoh`/`mesh_topology`: 1 router, connected, 12 active topics, `tcp/localhost:7447` — control/data mesh up.
- `mcp_capability_inventory`: 65 declared / 12 unavailable / 53 unprobed.
- `system_verification`/`fractal_status`: SIL-6, 266 tests (projection; not a fresh run).
- `podman_containers`: 0 podman containers while `system_dashboard` shows 16 containers → likely docker vs podman backends; noted, not a tool failure.
- Plan store visible: `uos/symbiosis-sync/20261027-1741` (7 tasks, 1 complete) and `infranodus/fractal-closure` (18 tasks).

## Residual
`preflight_check` arg-shape mismatch is the one actionable defect. The 4 role-gated tools and `verification_run` require the Pi-bound grant (proposal drafted: `var/harness/20261027-1808-pi-bound-grant-proposal.json`).

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · This report is a functional observation, not system admission.