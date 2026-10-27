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
