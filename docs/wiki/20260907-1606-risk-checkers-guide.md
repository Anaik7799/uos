# 20260907-1606 — Running the UOS risk checkers

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1606-risk-checker-contract.md) · [Guide](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1606-risk-checkers-guide.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1606-risk-checkers-journal.md) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

Created: 2026-09-07T16:58:06Z. This is the repository-local operational guide for
SC-RISK-CHECK-001 and SC-RISK-PRIORITY-001.

## Local setup

Use OCaml >=4.14, Dune >=3, Yojson >=2, Cryptokit >=1.18, sqlite3 >=5,
Mtime >=2, POSIX shell and GNU timeout. These are declared in
[the package manifest](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/validation/uos-risk-priority-validation.opam).
Live evidence modes also require the host's chronyc command; Sa-plan comparison uses
the existing var/sa-plan/uos.sqlite3 through READONLY queries.
There are no private skill paths, provider keys, downloaded agents or background daemons
required by this package. Use the installed approved toolchain; builds stay in temporary storage.

Run from UOS:

```sh
bash tools/risk-priority-check --all
bash tools/risk-priority-check --plan uos/risk-checkers/20260907-1631
```

--all is also the default when no arguments are supplied. It exercises 375 baseline
checks, 32,768 independently calculated three-node DAG cases and targeted adversarial
checks. The emitted JSON reports actual counts, not a production health score.

## Preparing a live packet

1. Read the complete Sa-plan plan. Copy no task state from a board ACK or stale journal.
2. Create a JSON array using the existing record schema. Keep plan/task/actor IDs and
   actual dependencies exact. Each assessment needs a distinct ID and observed UTC time.
3. Include only reviewed, sanitized, repository-relative source paths and actual
   SHA-256 digests. Every factor evidence reference must appear in snapshot.evidence;
   an optional :line suffix must point inside that file.
4. Use snapshot.kind=working_tree. A file named as a runtime receipt is still only
   file evidence here; this checker does not authenticate the asserted runtime.
5. Calculate the factors, FMEA, score and intervals; retain four UCA types,
   assumptions, counterevidence, forecasts, acceptance and rollback.
6. Run --audit before using --preflight or --active-check. Refresh evidence when code,
   dependencies, ownership or hazard context changes.

Examples below use placeholders that must be replaced with the actual packet and identity:

```sh
bash tools/risk-priority-check --audit PORTFOLIO
bash tools/risk-priority-check --preflight PORTFOLIO TASK
bash tools/risk-priority-check --active-check PORTFOLIO TASK WORKER ATTEMPT
bash tools/risk-priority-check --receipt RECEIPT
```

A completed task cannot be claimed again through --preflight. An executing task uses
--active-check with the observed attempt. No command above changes Sa-plan.

## Reading findings

| Finding | Immediate response |
|---|---|
| RP-EVIDENCE / RP-REFERENCE / RP-SNAPSHOT | Re-observe the named source and bind its digest; do not merely restamp old claims |
| RP-TIME / RP-TIME-END or clock failure | Check host synchronization and refresh affected observations |
| RP-SA-PLAN / RP-ACTIVE-OWNER | Re-read authority state; stop that stale attempt's effects |
| RP-SELECTION | Inspect unfinished dependencies and higher-class candidates |
| RP-INHERITANCE | Refresh the downstream consumer supplying urgency |
| RP-SENSITIVITY / RP-COST-TIE | Record why the ordering is provisional; run a cheap discriminating probe or use a separately reviewed selection |
| RP-INVALID / RP-UNAVAILABLE | Preserve the input/checker failure; repair the cause before retry |
| STALE_OR_CHANGED_ARTIFACTS | Keep the historical receipt and create new revision-bound verification |

Output always carries authority=NONE for strong modes. PREFLIGHT_PASS or
ACTIVE_OBSERVATION_PASS is an observation result with explicit limitations.
A checker process cannot authenticate the operator, authorize itself or make a claim/effect atomic.

## Lifecycle integration and economical intelligence

The local skill, root/per-runtime agent policies and Superpowers bindings require --all
for checker changes and appropriate evidence checks before selection/continuation.
Use deterministic checks first; they cost no additional model-provider tokens.
Escalate semantic contradictions or high-impact residual risks to a qualified reviewer.
No change to running Claude/AGY/Codex sessions, plugin reload, live hooks or global model routing
is asserted. The package neither spawns agents nor registers a shadow task queue.

Prioritize next: atomic Sa-plan claim/effect fencing; typed authenticated evidence and
cost fields; independent agent-process adoption tests. Keep those as separate authorized
work, with their own STPA/FMEA assessment and acceptance evidence.

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


**UOS footer:** repository-owned checker operation; production admission remains separate.

