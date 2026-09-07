# 20260907-1559 — Use the UOS risk prioritization process

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Source](http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20260907-1559-risk-prioritization-guide.md) · [SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1559-risk-prioritization-guide.md) · [ADR](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1559-adr-risk-prioritization.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1559-risk-prioritization-journal.md)

Created: 2026-09-07T15:58:59Z. Process guidance; no production admission claim.

The [canonical SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) defines the rubric.
Use safety constraints and dependency readiness before **criticality × STPA × FMEA × dependency × impact**.
A larger number is a work-ordering aid, not permission.

## Daily use

1. Observe the live plan, effect scope, evidence and dependencies.
2. Attach UCAs/constraints, FMEA modes, the five scores, uncertainty and acceptance tests.
3. Record through Sa-plan and claim the exact eligible task.
4. Recheck at review/release and on changed evidence.
5. Journal outcomes, residuals and reprioritization.

## Self-contained repository package

| Artifact | Role |
|---|---|
| contracts/rules/20260907-1559-risk-prioritization-sop.md | Canonical SOP and anchored rubric |
| governance/planning/20260907-1559-risk-priority-policy.json | Machine-readable profile |
| governance/planning/20260907-1559-risk-priority-record.schema.json | Record structure |
| governance/planning/20260907-1559-risk-priority-example.json | Historical policy-change example, not live clearance |
| plugins/uos-risk-prioritization/skills/uos-risk-prioritization/SKILL.md | Common local skill |
| plugins/uos-risk-prioritization/validation/ | OCaml report-only validator and tests |
| tools/risk-priority-check | Location-independent wrapper; no private home paths |
| governance/agents/policy/20260907-1559-risk-priority-bindings.toml | Agent/skill/plugin consumption map |

The repository supplies every authored policy, schema, binding, example and validator.
Prerequisites are OCaml >=4.14, Dune >=3.0 and Yojson >=2.0, declared in the
repository-owned validation/uos-risk-priority-validation.opam manifest.
Use tools on PATH or an explicitly selected UOS toolchain. No private ZigVM checkout or global
skill directory is required by the package. Compiler dependencies are ordinary toolchain dependencies,
not vendored model weights, caches or private source snapshots.

## Validation

From any directory, invoke the wrapper by its repository path:

- **bash tools/risk-priority-check --selftest** — bounded arithmetic, freshness and dependency/ranking cases.
- **bash tools/risk-priority-check --package** — local manifests, discovery bindings and required references.
- **bash tools/risk-priority-check --record governance/planning/20260907-1559-risk-priority-example.json** — structural and arithmetic check of the example; does not attest current file content or authorize work.
- **bash tools/risk-priority-check --rank PORTFOLIO.json** — advisory ordering of a JSON array of records from one plan; include all dependencies. Live digest authentication and cost tie review remain separate.

The wrapper builds in a temporary directory and removes its own build directory on exit.
Checks read the repository and print results. They never write a task, score gate, admission receipt,
board message, plugin configuration or runtime state.

The local plugin manifest is discoverable source, not proof of installation in every running agent.
Per-runtime skill aliases and AGENTS rules provide repository discovery without installing the plugin.
Existing running sessions must reload/read the updated instructions; no live adoption is claimed without observation.

## Remaining work

Native Sa-plan impact/class/freshness support, safe automatic scheduling and independent behavioral
evaluation remain separate implementation/verification work. Do not call the process-only integration
a fleet-wide mandatory runtime gate.

[[zk:20260907-1559-adr-risk-prioritization]]

## 20260907-1606 — Strong checker integration (SC-RISK-CHECK-001)

Follow the repository-owned
[checker contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1606-risk-checker-contract.md)
and [operating guide](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1606-risk-checkers-guide.md).
Run **bash tools/risk-priority-check --all** for checker/policy changes and relevant CI.
Before a claim use **--preflight PORTFOLIO TASK**; during owned work use
**--active-check PORTFOLIO TASK WORKER ATTEMPT** with current Sa-plan identity.
Both require a complete, fresh, source-bound plan assessment. Reused receipts require
**--receipt RECEIPT**. HOLD, missing tools/evidence, clock failures and provisional
ordering fail closed; investigate the reported next check before retry.
These are local preflight observations. Atomic admission, semantic review and actual
effect-time fencing remain separate requirements. No global hooks or agent reload are implied.


## Comprehensive verification checklist

This is a process/document package. The entries below do not assert production conformance.
UNRUN and NOT_ADMITTED remain nonpassing; N/A must be justified for each actual change.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host timestamp recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN references provided; live delivery unverified.
- [x] CHK-03-FRACT — L0–L9 applicability tagged.
- [x] CHK-04-KM — SOP, wiki, ADR and journal linked in this package.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Fleet dependency exclusion scan UNRUN.
- [ ] CHK-06-GRAPH — Runtime language/NIF conformance UNRUN.
- [ ] CHK-07-DRIVE — OS storage interlock execution UNRUN.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI categories UNRUN.
- [ ] CHK-09-MATH — Mathematical quality gates UNRUN.
- [ ] CHK-10-9MOD — Nine runtime test modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression monitoring UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Production supervision/fencing checks UNRUN.
- [ ] CHK-13-HERMES — Mandatory scheduler enforcement NOT_IMPLEMENTED by this package.
- [ ] CHK-14-ZIGVM — Runtime kernel checks UNRUN.
- [ ] CHK-15-MAX — Actual inference checks UNRUN.
- [ ] CHK-16-OTEL — Runtime telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review/admission NOT_ADMITTED.
- [x] CHK-18-JJ — No native Git command or integration/VCS mutation used for this package.

</details>

**UOS footer:** use repository sources when Tailnet rendering is unavailable; serving status unverified.
