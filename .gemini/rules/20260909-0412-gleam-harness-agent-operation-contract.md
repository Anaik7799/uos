# Mandatory Gleam harness agent operations

Contract: SC-HARNESS-MCP-001  
Status: operator-mandated architecture; implementation and runtime enforcement remain capability-specific.  
Timestamp: 2026-09-09T05:19:29Z, observed through Gleam MCP heartbeat; batch prefix preserves the originating specification.  
Scope: Claude, Codex, AGY/Gemini, internal agents, swarms, hooks, tools and agentic holons across L0–L9.  
Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

1. Agents MUST submit operational intents through MCP or admitted Zenoh ingress to the Gleam/OTP harness. Direct shell, filesystem, time, network, model, build, task and release operations are not an alternate agent execution path.
2. Gleam MUST own agents, supervision, authority, policy, scheduling, model routing, time validation, check verdicts and side-effect admission. The harness selects the appropriate backend.
3. Existing bounded native adapters and pinned compilers/provers/OS observations remain internal services. New agent/control implementation MUST be authored in Gleam. General automatic Gleam-to-OCaml/Mojo compilation is a required future compiler capability, not an existing stock Gleam feature.
4. All planning/task/job/workflow mutations MUST retain canonical Sa-plan authority. Caller payload identities, model suggestions, coordinator ACKs and heuristic scores cannot create authority. Fractal TPS/Jidoka stops affected work when required evidence or fences fail.
5. Edits, builds, tests and failure injection MUST remain in development. Production and its standby run admitted production artifacts with independent state and authority. OTP supervision does not by itself establish replication, consensus or a safe hot upgrade.
6. OpenRouter MUST use the explicit aggregate USD 10 per UTC day budget, durable reservations, truthful costs and the requested coding/decision profiles subject to measured eligibility. An uncertain charge remains a liability. This policy does not claim that paid routing has been activated.
7. A capability catalog is not runtime evidence. Each operation requires its declared bounds, source/revision identity, current task/lease/epoch, clock evidence and typed receipt. Unknown outcomes MUST be reconciled before retries. Stable logical effect IDs survive task-attempt changes.
8. Clients, rules, skills, hooks, journals, wiki, ZK and KM MUST map to this same operational boundary. A reminder hook is advisory unless bypass enforcement has been observed. External VM-1 source trees remain read-only.
9. The operator explicitly authorized a one-time development bootstrap in this conversation (“yes”, then “yes. do what ever is required”). It covers saving the formal specification and repairing/testing the harness interface. It grants no production admission. BootstrapReady is a finite declared gate; successful MCP read/write/build/test/clock, authority/refusal, replay and bounded-transport evidence closes direct development-tool use. Subsequent task completion and evidence publication must use the harness.
10. Native kernels are activated only behind verified ABI, ownership, lifetime and scheduler contracts. Unbounded solvers or blocking inference cannot be NIFs. MAX/Mojo remains a supervised inference service by default; generated kernels require independent semantic and resource checks.

Full requirements, denotations, scenarios, algebra, state inventory, diagrams, SDLC and SRE are in the [formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) and [atlas](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-algebraic-atlas.json). These are intended Tailnet locators; local file presence does not prove publication.

## Comprehensive verification checklist

Checks below are obligations, not blanket passing claims.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — Observe synchronized clock evidence and document prefix.
- [ ] **CHK-02-TAIL** — Verify full Tailnet links and actual serving status.
- [ ] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping.
- [ ] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Verify exclusions against the candidate dependencies.
- [ ] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes graph boundary.
- [ ] **CHK-07-DRIVE** — Preserve the denied OS serial and test real interlocks only in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Verify all applicable C1–C8 surfaces.
- [ ] **CHK-09-MATH** — Measure the four declared mathematical gates.
- [ ] **CHK-10-9MOD** — Apply relevant unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos checks.
- [ ] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Observe actual OTP control/supervision behavior.
- [ ] **CHK-13-HERMES** — Observe bounded analysis and authoritative evidence.
- [ ] **CHK-14-ZIGVM** — Verify deterministic execution and descriptor-relative VFS.
- [ ] **CHK-15-MAX** — Observe actual isolated inference when applicable.
- [ ] **CHK-16-OTEL** — Verify clock and nonzero trace/span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Obtain candidate-bound independent review and authorized admission.
- [ ] **CHK-18-JJ** — Preserve standalone JJ, source ownership and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.
