# 20261027-0836 — Learning bindings for Superpowers, plugins and agent roles

- **Document ID**: `GOV-LEARN-BIND-001`
- **Binds**: [`SC-LEARN-001`](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261027-0836-core-development-learnings.md) into the lifecycle points UOS already owns
- **Authority**: operator directive 2026-10-27; Sa-plan `uos/hive-development/20261027-0532` task `AGENT_PARITY`
- **Status**: reference mapping only. No installation, no hook registration, no plugin mutation. **Adoption by any client is UNRUN.**

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #km-triad #tailscale-web

Transclusions: `[[zk:20260905-1801-moc-uos-unified-master]]` · `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

**Navigation:** [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist) · [Learnings](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261027-0836-core-development-learnings.md) · [Operations manual](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261001-1117-uos-agent-symbiosis-operations.md) · [Existing Superpowers bindings](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md)

**Public evidence baseline:** [receipt-core journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-receipt-core-journal.md) · [mcp-core journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-mcp-core-journal.md) · [mcp-core peer review](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-0745-mcp-core-peer-review.json).

## 1. What this document is, and is not

It states where each learning applies in the lifecycle UOS already runs. It is a **normative mapping motivated by observations**, not a factual report, and it creates no skill, framework, hook or plugin. It does not show that any client loaded anything: a settings file is not evidence of activation, nor is a listed plugin or a declared tool. This mapping extends the existing [Superpowers bindings](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md) rather than replacing them.

The four local rule and profile mirrors already read the shared operations manual, and the eight skill aliases across `.claude`, `.gemini`, `.agents` and `.codex` already resolve to the two owned SKILL files. Nothing hidden, client-side, plugin-cached or configuration-level is edited here, so no duplicate mirror edits were needed.

## 2. Superpowers lifecycle bindings

| Lifecycle method | Learnings | Obligation at that point |
|---|---|---|
| systematic-debugging | `L-01`, `L-04`, `L-05`, `L-08` | Disconfirm competing causes against source and receipts; a typed decode or size refusal is a deterministic cause, not an unknown. Preserve the failing receipt first, and choose a reconciliation oracle that covers the actual effect class. |
| writing-plans | `L-02`, `L-11` | Reuse existing tasks and evidence; name the graph a plan's closure assumes, and recheck closure and minimality when that graph changes. |
| executing-plans | `L-03`, `L-07`, `L-09` | Canary the control surface first with an isolated recovery path; heartbeat immediately before each effect phase; keep required negative cases but never auto-retry the same unresolved effect. |
| requesting-code-review, receiving-code-review | `L-01`, `L-12` | The reviewer must not be the implementer; report provider identity and quota truthfully; a review may return HOLD. |
| verification-before-completion | `L-10` | Run `tools/journal-check` and `tools/diagram-check` before `finish`; build the completion packet from flat top-level fields. |
| finishing-a-development-branch | `L-01`, `L-08` | Complete only the work actually performed; reconcile any unknown outcome with an operation-specific oracle before closing; release leases. |

These methods remain subordinate to Sa-plan authority, the Gleam boundary and the user's existing authorization. Optional global installation, approval prompts, Git commands and automatic delegation do not override root policy or active session restrictions.

## 3. Plugin and MCP surface

No plugin is installed, updated or cached by this work. Two surfaces exist and neither is a coverage percentage: the natively connected surface exposes **4 read-only operations**, and the private reviewed harness **advertises 13 scoped tools**, of which the core workflow is exercised but **not all 13 are fully verified** — exposure is not verification. The 4-tool read surface **can read** this public guidance, which establishes readability only; active client adoption remains unverified. The broader inventory holds 65 declarations, 53 unprobed and 12 unavailable with admission unknown, and must be refreshed before reliance (`L-12`). Hidden paths, client caches and configuration remain **unread and unedited**; those gaps stay explicit rather than closed by assertion.

**Unprobed scope gap for `PLANNING_MCP`.** `harness_assess` validates every assessment record path against the grant (`assessment_paths_allowed`, `operations.gleam:627`, called at `:678`). A full-portfolio assessment references `governance/planning/20261027-0634-hive-development-readiness-plan.json`, which exists at 71312 bytes but is **absent from this grant's read paths**, so such a call would be rejected. No `harness_assess` run was attempted: this is inferred from source, **not an observed failed run**, and is not to be bypassed. Where a normal assessment mutation is impossible within an approved scope, report the gap for root rather than forcing the API.

## 4. Agent role bindings

| Role | Binding |
|---|---|
| Implementer | Owns `L-03`–`L-10` in execution. Reproduces a defect before repairing it, keeps RED and GREEN distinct, stays inside the reviewed write scope. |
| Independent reviewer | Owns `L-01`, `L-02`, `L-12`. Recomputes digests rather than trusting them, checks that a frozen model is labelled frozen with its closure claim rechecked, and may return HOLD. |
| Coordinator | Owns `L-07`, `L-08`, `L-11`. Holds grant and lease metadata, dispatches reconciliation before a fresh intent or grant, and sets soft targets as targets. |
| Any agent | Never impersonates another agent or provider; records a quota block as a block (`L-12`). |

## 5. Measured scaling headroom, for PLANNING_MCP

A measured constraint, recorded here and in the journal's remaining gaps. No new task or framework is created for it now.

| Quantity | Value |
|---|---|
| Complete 28-task compact risk portfolio | 245379 bytes |
| `files.max_bytes` read cap | 262144 bytes |
| Occupancy | ~94% |
| Headroom | 16765 bytes |

The earlier compaction fixed a **pretty-format incident**; it does not bound future growth. The currently accepted 28-task scope fits. Before any large task expansion, a bounded plan and assessment representation must be **designed with coverage tests**, under its own reviewed task. Do not simply raise the cap, do not relax limits generally, and do not declare the design scalable on the strength of today's fit.

## 6. Open gaps, recorded not closed

1. Client adoption of this mapping is **UNRUN** for every surface; readability by the 4-tool surface is not adoption.
2. Google and client activation for broad agent parity remain **HOLD**; `AGENT_PARITY` cannot finish while they do.
3. Hidden and plugin-cache paths are out of scope and unobserved.
4. The frozen 13-node closure predates the 28th task and this grant's review authority; its closure and minimality claims need rechecking through a real planning API, not hand-edited dependencies and not a claimed new theorem run.
5. Risk-portfolio headroom is ~6% (§5); bounded representation design is prerequisite to large task expansion.
6. `harness_assess` full-portfolio scope gap (§3) is unprobed and unresolved; it needs a grant whose read paths include the readiness plan, decided by root.
7. Of the 13 advertised harness tools, only the core workflow is exercised; full per-tool verification is outstanding.
8. State after a partial release is an explicitly **partial** state, not a new normal readiness baseline.

Sa-plan is the sole execution authority. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV number minted.

## Comprehensive verification checklist

Obligations for governed work, not passing claims for this document. Runtime items are **unchecked**: this document executes nothing.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — `YYYYMMDD-HHSS-` prefix present; host clock observed 2026-10-27.
- [x] **CHK-02-TAIL** — Full Tailnet links provided; live serving status not asserted.
- [x] **CHK-03-FRACT** — L0, L3, L4, L9 tags assigned.
- [x] **CHK-04-KM** — Transclusions, manual, learnings, journal and review links resolve to existing artifacts.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Dependency exclusion scan UNRUN; no dependency introduced.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary UNRUN here.
- [ ] **CHK-07-DRIVE** — Storage interlock execution UNRUN; no host serial appears here.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Not applicable to this package; UNRUN.
- [ ] **CHK-09-MATH** — Four mathematical gates UNRUN here.
- [ ] **CHK-10-9MOD** — Nine test modalities UNRUN here.
- [ ] **CHK-11-REGR** — UI regression monitoring UNRUN here.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Supervision behaviour not observed by this package.
- [ ] **CHK-13-HERMES** — Bounded analysis and evidence ledger UNRUN here.
- [ ] **CHK-14-ZIGVM** — Deterministic kernel and VFS UNRUN here.
- [ ] **CHK-15-MAX** — Isolated inference UNRUN here.
- [ ] **CHK-16-OTEL** — Runtime telemetry correlation UNRUN here.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent review of this document is OUTSTANDING; NOT_ADMITTED.
- [x] **CHK-18-JJ** — Authored under standalone JJ discipline; no native Git mutation used.

</details>

<details>
<summary>Domain 6 — Provenance and admission integrity</summary>

- [x] **CHK-19-CEIL** — EV ceiling 93 stated; EV-94..109 NOT_ADMITTED; no EV claim made.
- [ ] **CHK-20-INDEX** — KM index enumeration of this new record UNRUN.
- [x] **CHK-21-PRESERVE** — Additive only; no historical artifact rewritten.
- [ ] **CHK-22-CHAIN** — Cycle-chain verification UNRUN by this package.
- [x] **CHK-23-NOMINT** — No new EV number minted.
- [ ] **CHK-24-FAILCLOSED** — Metric-path fail-closed runtime behavior UNRUN in this documentation scope; no passing claim.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this document grants no admission.
