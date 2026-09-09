# Comprehensive harness evolution decision review

Review status: REQUESTED, not acknowledged or approved.  
Canonical scope: /home/an/NAS-setup/uos; Sa-plan root work uos/ecology/20260909-0146 / HARNESSBOOT, worker codex-01a083d2-harness, attempt 1.  
Observed discovery: 2026-09-09T05:25:27Z through the Gleam MCP harness.  
Operator instruction: “review all harness evolution decisions with claude fable an agy comprehensively. must check”.  
Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

The review MUST be independent and cover every decision below. Confirm your real session ID, runtime/model identity (including whether the Claude session is the requested Fable), current source identity and Sa-plan review claim. Do not impersonate another reviewer, infer an ACK from successful prompt delivery, or admit a system merely from this review.

The operator approved a one-time development bootstrap to save the specification and repair/add the mandatory MCP Gleam harness services. Implementation is ongoing; read-only review may use the available harness or record the exact bootstrap service gap. Do not mutate another worker's source, production runtime, credential, live coordinator data or external VM-1 trees. No new EV numbers; ceiling 93 and EV-94..109 NOT_ADMITTED remain in force.

## Decision census

| ID | Decision and scope | Evidence and mandatory challenge |
|---|---|---|
| D01 | Canonical UOS reuses C3I/Indrajaal concepts and VM-1 as read-only evidence | Check source provenance, no unvetted import, and that UCon integration is not invented. |
| D02 | Agentic holons discover the full capability set and activate authorized subsets | Distinguish 26 local participant models from actual external system bindings. |
| D03 | Gleam/OTP owns all agents, orchestration, policies, clock/check verdicts and backend choice | Check actual direct-tool exceptions and client enforcement; documentation is not enforcement. |
| D04 | MCP and admitted Zenoh share typed intents and receipts | Existing Zenoh prefixes/correlation/targeting differ; no live equivalence claim. |
| D05 | All newly authored control implementation is Gleam | Existing bounded native adapters are internal services; stock Gleam targets Erlang/JS only. |
| D06 | Native generation is proposed via a constrained typed kernel IR | General Gleam-to-OCaml/Mojo/NIF translation is not implemented; reject unsupported constructs. |
| D07 | Native ABI/runtime ownership gates preserve semantics | Check OCaml runtime/GC roots, Mojo runtime lifecycle, short NIF scheduling and daemon defaults. |
| D08 | Sa-plan is sole task/job/workflow authority | Check actual claim/attempt/expiry/dependencies, full-plan risk and effect-time fences. |
| D09 | Fractal TPS/Jidoka limits scope and stops uncertain effects | Validate all four STPA UCA classes, raw FMEA, dependency priority and bounded recovery. |
| D10 | Coordinator leases are cooperative; task/runtime/integration ownership differ | No lease or ACK grants deployment/system admission; inspect stale-check timing. |
| D11 | Stable logical effect identity survives retries and task attempts | Failed/corrupt/lost-result replay must not become success or dispatch twice. |
| D12 | Development edits use bounded files and cooperative compare/replace | Inspect path aliases, inode checks, byte bounds, exclusive create, fsync and parent-rename limitations. |
| D13 | Existing legacy MCP UTF-8 reader and Sa-plan adapter are repaired | Identity-as-Result crashed; shell-joined argv hid exit failures; attempt was absent. Verify regressions and remaining legacy gaps. |
| D14 | New finite stdio MCP development interface | Check initialization, notification behavior, finite schema, roles, loaded code identity, deadlines and terminal reconciliation. |
| D15 | Clock policy separates UTC, signed monotonic duration, boot coordinates, reference age and delivery age | Inspect real chrony adapter and continuity; clocks from different hosts/boots cannot be subtracted. |
| D16 | Development, production primary and production standby are distinct roles | Two hosts can run three isolated nodes; a dev candidate must not silently become a prod standby. |
| D17 | Complete declared state requires explicit durability/replication | OTP supervision alone does not replicate state or solve split-brain. Check leases, queues, liabilities, models and knowledge state. |
| D18 | Hot loading is conditional on candidate-bound migration/recovery | No general “Gleam/OTP implies safe live upgrade” claim. Check appup/relup/sys semantics and native resource limits. |
| D19 | OpenRouter coding profiles use paid GLM/Kimi/DeepSeek, decisions prefer Gemma 4 | Price/capability eligibility and local task quality must drive routing; model names do not establish best quality. |
| D20 | OpenRouter aggregate budget is USD 10 per UTC day | Durable reservations, USD0.25 bounded call liability, unknown spend retained, no automatic retries/refunds. No paid call has been made in this session. |
| D21 | Adaptive routing optimizes for agent need and measured evidence | Pure Gleam engine and budget adapters exist; actual production binding/calibration is not yet verified. |
| D22 | Environment-specific evaluation includes Gleam, OCaml, Mojo, Lean, Quint, STM, Bayesian, Rete, STPA/FMEA | Separate synthetic semantic cases, actual native executions and algorithms not verified (notably Rete-UL). |
| D23 | Formal authority is invocation/candidate-specific | No sorry/Admitted/unknown tool outcome counts as proof; declared Lean axioms remain explicit. |
| D24 | Existing ecology baseline remains separate from new harness admission | Last earlier observation: real local MAX and free OpenRouter request; local loop does not prove the entire ecology/UCon has external bindings. |
| D25 | Hooks are advisory until independently observed as enforcing | Installed Codex hook check passed earlier; this is not universal client bypass prevention. |
| D26 | Journal/wiki/ZK/KM and algebraic atlas preserve claims and uncertainty | Check exact 13 journal sections, timestamps, L0–L9, all 17 aspects, matching ASCII/Mermaid and real links. |
| D27 | Primary/backup SRE requires independent observations and tested recovery | Source tests and component counts cannot substitute for actual production/standby runtime behavior. |
| D28 | Bootstrap completion requires observed finite service acceptance and peer reconciliation | Verify recoverable completion, current source-bound build/test receipts, explicit residual gaps and no claimed whole-system admission. |

## Review method and required response

For each D01–D28 return ACCEPT_WITHIN_SCOPE, REVISE, REJECT or UNKNOWN with source/candidate references, actual observations, assumptions, falsifier, proposed repair and residual risk. Review all 17 system aspects from §7 of the formal specification and every lifecycle stage in §20/§21. Prioritize safety/authority/dependencies before criticality × STPA × FMEA × dependency × impact.

Request own disjoint Sa-plan task/worker and record exact peer ACK. Source-only review must say so. Any observed runtime test must identify invocation, revision, toolchain, exit status and limits; do not rerun broad suites or touch production merely to create a green count. No sensitive data belongs in prompts or receipts.

Publish one timestamped review Markdown and JSON receipt under docs/journal, with a 28-row decision matrix and 17-aspect coverage. Send the path/digest and compact findings to root session 01a083d2-baa3-7783-8e45-5357cc9e96d8 on the coordinator board if available, and respond visibly in your Herdr session. No review result alone grants effect authority or admission.

## Evidence locations

- [Formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) and [atlas](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-algebraic-atlas.json).
- New source: apps/cepaf_gleam/src/cepaf_gleam/harness/{development,files,clock,value,mcp,peers}.gleam and tests harness_development_test, harness_authority_test (in progress), harness_sa_plan_boundary_test, harness_verification.
- MCP boundary source: apps/cepaf_gleam/src/cepaf_gleam/mcp/{server,tools,authz}.gleam; planning/sa_plan_bridge.gleam; existing ecology_capability_ffi.erl and tools/ecology_process.ml.
- Canonical contract: contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md; AGENTS.md §5.7; repository .codex/.claude/.gemini/.agents rule mirrors.
- Actual development MCP evidence: var/harness/20260909-0412-bootstrap-risk.json and var/harness/effects/. The first observed MCP test receipt contains 28 passing checks but predates later review repairs; inspect newer receipts rather than assuming it is final.
- Prior routing analysis: docs/design/20260909-0314-openrouter-engine-review-and-recommendation.md; Gleam ecology/openrouter_engine.gleam, ecology/daily_budget.gleam, uos_swarm/openrouter_worker.gleam; tools/ecology_budget.ml and tools/ecology_openrouter.ml. The latter prototype's old task attempt is stale and must not be used.
- Prior evaluation: tools/validation/openrouter_eval*.ml; docs/journal/20260909-0331-ecology-evaluation-independent-review.{md,json}.
- Prior budget: docs/journal/20260909-0356-ecology-daily-budget-completion.{md,json}.
- Prior hooks/browser: docs/journal/20260909-0248-codex-hooks-journal.md; docs/journal/20260909-0328-ecology-browser-journal.md.
- Independent Codex source review: docs/journal/20260909-0510-gleam-harness-bootstrap-independent-review.{md,json}; clock review docs/journal/20260909-0539-ecology-clock-reuse-review.{md,json}. These do not substitute for requested Claude/Fable and AGY reviews.
- VM-1 comparison receipt: governance/sources/20260909-0241-ecology-vm1-comparison-receipt.json. External trees are read-only; no published current VM-1 harness endpoint was verified.
- Existing running baseline was staged separately under var/releases/ecology/. No production restart/deployment has occurred during this bootstrap.

All Tailnet links are intended locators. Local readback is evidence of local content, not proof of live web publication.

<details>
<summary>Verification checklist — 18 checkpoints and provenance</summary>

| Domain | Checkpoints | State |
|---|---|---|
| Metadata and navigation | 01 timestamp prefix; 02 full Tailnet links; 03 navigation and document identity | Declared; live serving requires separate observation |
| Purity and storage | 04 excluded dependencies; 05 protected storage; 06 sanitized provenance | No new dependencies or storage operations in this document |
| Testing and mathematics | 07 C1–C2; 08 C3–C4; 09 C5–C6; 10 C7–C8; 11 four mathematical gates | Capability-specific evidence required; no blanket pass |
| Control and observability | 12 Gleam/native boundary; 13 trace and clock; 14 supervision/resources; 15 recovery | Requirements stated; runtime admission not granted |
| Governance and repository | 16 Sa-plan/coordination; 17 standalone JJ; 18 independent admission | Scoped task authority only; no system admission |
| Provenance extension | EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV number | Preserved |
</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)
