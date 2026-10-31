# UOS agent symbiosis operations

Observed: 2026-10-01T11:17:29Z. Status: development guidance; runtime admission is capability-specific. Plan: `uos/telegram-admission/20261001-1015`, task SYMBIOSIS_FIX.

Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Canonical policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) · [Harness contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) · [Formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Recovery dashboard](http://nas-1.tail55d152.ts.net:4100/static/20260930-0633-restoration-dashboard.html)

## Authority and operating procedure

UOS at /home/an/NAS-setup/uos is canonical. Read root AGENTS.md and applicable contracts before operating. External C3I, ZigVM, Harness, global skills and plugin caches are read-only evidence. Do not propagate changes into them. Preserve their original bytes and provenance; adapt required behavior in UOS-owned files.

1. Discover actual agent sessions and available Gleam MCP operations. A declared tool, installed plugin, advisory hook, model identity or board ACK grants no execution authority.
2. Record work in canonical Sa-plan. Resolve dependencies and current risk evidence, run risk preflight, claim the task, then active-check the actual worker and attempt. Use the current coordinator resource epoch and expiry at the effect boundary. A heartbeat does not renew a lease.
3. Submit operational intents through Gleam/OTP via MCP or admitted Zenoh. Gleam owns supervision, scheduling, policy, time and check verdicts. Bounded native compilers, browser controllers and IO adapters execute behind this boundary. Missing callable mutations are a capability gap, never permission to invent a tool or bypass the harness. The finite development bootstrap in the harness contract confers no production authority.
4. Reproduce failures in development. Inspect the actual revision and disconfirm competing causes from atomic L1 state through L3 transactions, L4 service interactions, L0 authority and L9 federation. Distinguish a faulty implementation from a false-positive check. Preserve failing receipts before repairing code or its acceptance test.
5. Bind source hashes, toolchain, actual test invocation and outcomes. Use independent review by a peer who did not implement the candidate. Tests, board acknowledgements and documentation cannot promote global admission.
6. Prepare an immutable candidate and a finite reviewed release grant; recheck source, task, runtime and clock fences before effect. Observe actual OTP/ERTS identity, startup, bounded requests and recovery. Merge applicable reviewed JJ changes after stabilization; classify obsolete or quarantined heads without importing unsafe history. Never use native Git mutation.
7. Publish a timestamped 13-section SC-JOURNAL-v3 completion ledger, honest dashboard and residual risks. Complete tasks only for the work actually performed; a completed review can return HOLD. Release leases and retire finished sessions.

## Agent, skill, Superpowers, plugin and MCP rules

The four local agent surfaces share this procedure. Their hooks remain advisory until bypass behavior and client activation are observed. A settings file does not demonstrate that a client loaded it. Never broadly replace settings or expose credentials during inventory.

Local full-symbiosis, gemini-symbiosis, production-readiness and ocaml-playwright-control adapters supersede conflicting imported workflow guidance within UOS. Superpowers lifecycle methods (systematic debugging, planning, implementation, independent review, verification and branch finishing) are applied within Sa-plan and the Gleam boundary. Their optional global installation, approval prompts, Git commands, automatic delegation and external-tree propagation do not override the user's authorization, root policy or active session restrictions. No blanket plugin update, package download or external cache mutation is authorized by inventory work.

Maintain separate states for declaration, loadability, transport observation, effect authorization, verification and admission. The observed MCP inventory contains 65 declarations: 12 unavailable and 53 unprobed, all with unknown admission. It must be refreshed before relying on it. Actual read-only MCP calls are distinct from this broader catalog. Preserve unavailable capabilities as pending work.

## Telegram and browser operation

Telegram identity must be an exact configured numeric bot/chat/user tuple; text and usernames are not authority. Remote requests need canonical per-request tasks, fresh fences and an independently reviewed finite tool allowlist. Persist ingress and the committed batch prefix before advancing polling. A response is delivered only after verified Telegram success for the matching chat and a positive message ID. A crash during sending is UNCERTAIN and must not blindly retry. Never log tokens or private message bodies. Existing legacy polling and shared-bus execution must be quiesced under reviewed cutover before a new service starts.

Direct reads currently cover query_doctor and query_saplan locally; remote Telegram acceptance remains pending. Unsupported mutations must return a truthful refusal. No new outbound test message is sent without an authorized recipient and message scope.

Browser acceptance must use the actual candidate, HTTP status, final route, page-specific identity and the actual visible verification component. Any details element is insufficient. Restrict probe traffic to authorized read paths; block mutations and socket traffic. Keep private fixture evidence separate from production behavior. Capture desktop/mobile screenshots and inspect them; DOM counts alone missed the terminal checklist defect. Independent browser review on 2026-10-01 returned HOLD on those checks; the original PASS receipts are preserved and superseded for acceptance.

## Seventeen-aspect evidence map

These are obligations, not a passing score. Each needs candidate-bound evidence and a reviewer disposition.

| Aspect | Current scope / required evidence | Status |
|---|---|---|
| 1 Architecture | Gleam authority and native boundaries in canonical contract | Specified; runtime scope-specific |
| 2 Functional behavior | Local two-tool reads observed; Telegram end-to-end pending | Partial |
| 3 Trust and safety | Numeric ingress, task/lease fences, refusal tests | Development / pending |
| 4 Reliability | Durable inbox/outbox, crash uncertainty and recovery tests | Pending |
| 5 Performance | Bounded response and browser deadlines; service load measurements | Pending |
| 6 Scalability | Queue/payload bounds and saturation refusal | Pending |
| 7 Data integrity | Coordinator append-only and cycle integrity; candidate recheck | Previously observed; refresh required |
| 8 Concurrency | Single poller, worker/epoch fence, no HTTP inside SQLite transaction | Specified; pending |
| 9 Observability | Actual identities, clock, trace/span and sanitized receipts | Partial |
| 10 Deployment | Immutable artifact, finite release grant and observed startup | Existing baseline; new candidate pending |
| 11 Recovery | Tested rollback/stop-preserve and uncertain delivery reconciliation | Pending |
| 12 Compatibility | Existing provider wire values, tools and clients remain compatible | Pending |
| 13 UI/accessibility | Real browser routes, keyboard checklist, desktop/mobile | HOLD; fixes in development |
| 14 Formal evidence | Invocation-specific proofs, satisfiable controls, no unsupported axioms | Global validation pending |
| 15 Governance | Sa-plan, independent review, JJ and provenance ceiling | Required throughout |
| 16 Supply chain | Pinned already-realized toolchain, no external ingestion or secrets | Scoped checks only |
| 17 Documentation/operations | Mirrors, manuals, hooks, skills, plugins and MCP evidence | Correction in progress |

## Known pending work and boundaries

Global admission remains HOLD. Presence-only CLI checks and hardcoded ratification claims require correction and real obligation verification. EV-93 is the admitted ceiling; EV-94..109 remain NOT_ADMITTED and new EV identifiers remain barred. Historical policy snapshots are inert under [preserved source history](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20261001-1118-symbiosis-history/GEMINI.md). The existing main bookmark is an observed repository state, not proof of new system admission. This manual does not rewrite historical EV claims or admit imported artifacts.

## Core development learnings

Apply [the core development learnings](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261027-0836-core-development-learnings.md) (`SC-LEARN-001`) and their [lifecycle bindings](http://nas-1.tail55d152.ts.net:4100/files/governance/agents/20261027-0836-learning-bindings.md), which extend the existing [Superpowers bindings](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md). They are normative guidance motivated by refusals and receipts observed on 2026-10-27, recorded in the [receipt-core](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-receipt-core-journal.md) and [mcp-core](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-mcp-core-journal.md) journals. They install nothing and enforce nothing; client adoption is UNRUN.

Keep specification, model proof, runtime observation and admission as four separate claims. When the graph a model was built over changes, recheck that model's closure and minimality claims rather than treating its theorems as false: the 13-node closure was frozen on a 27-task graph and predates both the 28th audit-repair task and this grant's mandatory review authority, so it is not a statement of current functionality or optimality and its closure recheck is outstanding.

Verify the control surface before using it for ordinary work, with an isolated recovery path. Keep evidence JSON compact and within the 262144-byte read cap, and use each field's actual type: a grant's `expires_utc_us` is a decimal string of integral microseconds, risk `ready_since` and `observed_at` are whole-second canonical UTC, and a clock observation may validly carry fractional seconds, which must not be stripped. Publish retained bytes with a digest of those retained bytes, counts on both sides of the bound and an explicit truncation statement.

Heartbeat immediately before each effect phase, and keep the three renewal scopes distinct: a native coordinator heartbeat renews the coordinator session only; `harness_heartbeat` with a task attached renews the session and the active coordinator task-lease, and its receipt carries `coordinator_renewal`; the Sa-plan task lease is renewed by neither, and the same receipt reports `sa_plan_renewal` as `NOT_IMPLEMENTED_RELEASE_AND_RECLAIM_BEFORE_EXPIRY`. Release and reclaim before Sa-plan expiry.

Reconcile an unknown outcome before any fresh intent or grant, using an oracle specific to the operation attempted: an unchanged source map suffices only when the whole effect was a source-tree write, and never establishes the absence of a network, service or other physical effect. Do not automatically retry the same unresolved effect; preserve all required negative cases, isolate effectful fault cases with a planned recovery path, and prefer read-class or claim-class refusals where they test the same guard.

Build the completion packet from flat top-level fields and run the journal and diagram linters before finish. Treat soft cost or size targets as targets, not gates; reuse existing tasks and evidence; claim no global cost or reliability optimum. Report provider identity and quota truthfully, and never assert an unobserved client success.


- **2026-10-29 Fast-OODA & Critical Code Resilience Update (`SC-AGENTIC-RESILIENCE-001`)**: Three-scope lease renewal (`sa_plan_bridge.renew_task` / `--task-renew`) is active; the successor development harness exposes **15 scoped tools** (`ops.names`, including `harness_client_mcp_config` and `harness_plan_intent`), pins **28 BEAM control modules** + `tools/ecology_process.ml` across **44 source files**, supports `host_immutable_nix` (`/nix/store/mmycwn1v7bvpjgl0hxvbazxrqwjwn335-uos-sa-plan-main-cfe06ec3`), and enforces 184/184 EUnit tests across 12 MCP + harness test modules under `gemini-4-argon` supervision with `codex` (`gpt-6-luna`) and `claude` (`claude-opus-5`) agent lanes.

## 2026-10-30 Addendum — AK-47 Multi-Agent Supervisor & Unified 101-Route MCP Architecture (SC-AK47-SYMBIOSIS-001)

Observed: 2026-10-30T10:58:00Z. Status: canonical reference addendum; `REPORT_ONLY` with respect to runtime admission. Grants no effect authority and no admission. Client adoption is **UNRUN**. The canonical operating SOP is [20261030-1058-uos-fractal-comprehensive-system-prompt.md](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261030-1058-uos-fractal-comprehensive-system-prompt.md).

Authority: [AK-47 multi-agent MCP symbiosis rule](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261030-1058-ak47-multi-agent-mcp-symbiosis-rule.md) (`SC-AK47-SYMBIOSIS-001`). Companion surfaces: [client guide](http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20261030-1058-unified-101-route-mcp-client-guide.md) · [ZK ADR](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20261030-1058-adr-ak47-multi-agent-101-route-mcp-architecture.md) · [local skill](http://nas-1.tail55d152.ts.net:4100/files/governance/agents/20261001-1118-skills/ak47-multi-agent-mcp-symbiosis/SKILL.md). This addendum is a projection wrapper: it states no new runtime property and mints no EV.

### AK-47 design principle, extended to agentic delivery

The system is built the way the rifle is: a small number of **unbreakable steel-receiver invariants** carry everything that matters, while the remaining parts run with **loose bolt clearance** so ordinary tolerances never stop the mechanism. Steel = authority, safety, admission, provenance, secret hygiene, effect fencing, and the 28-module critical control path (hash-gated, CAS-written, independently verified; a critical file changes only under its own authorized control epoch with its own recovery path). Clearance = parallel disjoint-file workers, each owning one bounded new-file set, never a shared dispatcher, never a sibling's file. **Zero Muda** = pull only dependency-ready slices, merge verified work, then stop; do not build inventory for its own sake, recompute a landed candidate, or hold a ready record while its real blocker is an operator input.

### 4-agent symbiosis

| Agent | Role & boundary | Invocation discipline |
|---|---|---|
| **AGY Argon** | Strict Supervisor, integrator and verifier. **Never authors application code.** Holds the Sa-Plan claim/completion ledger and the `integration/main` epoch fence; runs the SHA-256 and EUnit gates; performs final merges. | One writer, one fence, one merge gate; no self-review conflict. |
| **Pi + DeepSeek-v4.1-Flash** | Fast disjoint slices: adapters, transports, facilities, doc/mirror sweeps, unit-test authoring. | `--thinking low` + the 8-flag Zero-Muda isolation bundle (`--no-session --no-extensions --no-mcp --no-skills --no-prompt-templates --no-context-files --no-themes`), measured at a **-99.2%** prompt-token overhead. Supervisor post-run `sha256sum` re-checks every touched file. |
| **Codex** | Complex multi-file integration and security-sensitive slices where the receiver steel must be understood as a whole (shared dispatcher wiring, HTTP/Zenoh auth, full-suite independent EUnit audit). | `-s workspace-write` is mandatory: `-s read-only` mounts `/tmp` read-only (`{error, erofs}`) and fails temp-dir fixture tests. |
| **Claude** | Independent **cross-family Popperian falsification**, read-only. Proves falsification; does not author; may return `HOLD`. | `claude -p --allowedTools "Read"`. Its ACK is never admission. |

The separation is a **STAMP control**: the executing agent never reviewed its own work, the reviewer never authored, and the supervisor never wrote application code.

### Unified 101-route Gleam/OTP MCP server

One server exposes **101 routes**: **65 public routes across 9 domain adapters** + **21 development routes** + **15 successor routes**. Reachable over three fenced transports: **stdio**, **Zenoh with an HMAC fence**, and **Streamable HTTP with Bearer / Origin / `Mcp-Session-Id` fences**. Accepted MCP protocol versions are **`2024-11-05`** (`Legacy20241105`) and **`2026-07-28`** (`Modern20260728`), matching `mcp/version.gleam` and `transports/http.gleam`; an unlisted version is refused rather than silently downgraded. The Streamable-HTTP `Origin` fence is HTTPS-only and Tailscale-FQDN-shaped: the `http_auth.gleam` allowlist accepts `https://nas-1.tail55d152.ts.net:4100` and refuses `http://` or raw IP literals. Zenoh topics carry an HMAC fence; the HTTP and Zenoh fences are steel and refuse before dispatch. **Five client profiles** (`agy`, `gemini`, `codex`, `claude`, `pi`) point at the one server. A declared route is not a connected route; verify the live `describeNamespace`/heartbeat list before relying on any route. Exact commands are in [the canonical SOP](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261030-1058-uos-fractal-comprehensive-system-prompt.md).

**Catalog reconciliation note (`tools.gleam`).** The public catalog declares **65** public tools: **53** are listed directly in the default legacy unauthenticated `tools/list` (`tools.operational_tool_definitions()` = 65 declared minus 12 unavailable), and **12** gated domain tools (`control_loop`, `safety_status`, `run_selfcheck`, `registry_status`, `run_gate`, `zk_search`, `sa_bridge_submit`, `vault_status`, `vault_list_secrets`, `vault_policy_get`, `vault_audit_tail`, `vault_health`) fail closed with `UNAVAILABLE` on unauthenticated/unconfigured legacy calls and execute only through authenticated typed adapters in `server.execute_route_authenticated`. `65 declared − 12 unavailable = 53 advertised`, matching the T19 receipt's `tools_listed_count: 53`; `tools/list` and `tools/call` must tell the same story.

### Truthful epistemic projection

`Refused` is not `Operational`. Completed tasks alone are not green readiness. Raw review cannot be overridden. `DEV_READY` is not `SYSTEM_ADMITTED`. A live cutover requires separate **T24 operator release authority**. `UNRUN`, `UNKNOWN`, `STALE` and `NOT_ADMITTED` remain nonpassing. The `EV-93` ceiling, the `EV-94`..`EV-109` `NOT_ADMITTED` range and the held `SourceFX` plan are unchanged by this addendum.

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


## 20261031-1807 — All-agent heartbeat, preflight and evolution binding

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zk-adr #zero-muda

Use the [canonical monitoring SOP](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261031-1807-all-agent-symbiosis-preflight-tps-and-evolution-sop.md) and [SC-SYMBIOSIS-PREFLIGHT-001](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261031-1807-all-agent-symbiosis-monitoring-contract.md) for Claude, Pi, AGY and Codex. Follow heartbeat/deep cadence, exact per-agent service coverage, source/clock freshness, verified recovery, scoped TPS/RCA, private cost reconciliation and current Sa-plan authority. Typed Rete outputs and Stan posteriors remain advisory; STANAG source admissibility is separate. Production owner/collector/catalog/effect gates are not established by this guidance. Preserve imported/historical originals and global files.

<details><summary>Domain 6 — Provenance extension for this addendum</summary>

EV93 ceiling; EV94..109 / ADR071..086 NOT_ADMITTED. Existing18 core-check obligations remain in force; no blanket pass or new EV identifier.

</details>
