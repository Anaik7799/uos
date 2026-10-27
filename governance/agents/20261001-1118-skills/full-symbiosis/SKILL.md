---
name: full-symbiosis
description: UOS-local full-symbiosis workflow through canonical Gleam and Sa-plan authority.
---

# 20261001-1117 UOS full-symbiosis

Locally authored adaptation, observed 2026-10-01T11:17:29Z; external originals remain read-only. Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

Synchronize UOS-owned agent rules, skills, role adapters, advisory hooks, capability inventories and evidence. Read the manual, inventory all active mirrors, preserve old evidence, adapt locally, validate exact parity and links, then independent review. Never write through external skill symlinks. Track unprobed and unavailable capabilities without declaring them active.

Follow [root policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md), [operations manual](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261001-1117-uos-agent-symbiosis-operations.md) and [harness contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md). The user’s existing scope/authorization and higher-priority instructions govern. This skill grants no effect authority or runtime admission. Use standalone JJ, exact Sa-plan tasks and independent candidate verification. No new EV identifier.

## Observed API and reference clarifications

Factual API reference drawn from refusals and receipts observed on 2026-10-27, per [`SC-LEARN-001`](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261027-0836-core-development-learnings.md) and its [bindings](http://nas-1.tail55d152.ts.net:4100/files/governance/agents/20261027-0836-learning-bindings.md); evidence in the [receipt-core](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-receipt-core-journal.md) and [mcp-core](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-mcp-core-journal.md) journals. No workflow behaviour is changed and no new discipline is claimed: nothing here was behaviour-pressure-tested against a client, and client adoption is UNRUN.

- A reviewed grant's `expires_utc_us` is a **decimal string of integral microseconds**; the same value as a JSON number refuses at startup with `grant_decode` (`admission.gleam:200`). Risk `ready_since` and `observed_at` are whole-second canonical UTC. A clock observation may validly carry fractional seconds and must not be stripped. A decoder preflight on the final artifact is therefore needed in its own right; review validation does not cover it.
- Evidence inputs read through the harness must be compact JSON within 262144 bytes (`files.max_bytes`); an oversize portfolio refuses `attach` before any effect.
- `operations.finish` validates a **flat top-level** binding set and rejects nested equivalents as absent. The full set is `schema` exactly `uos.harness-task-verification.v1`, `plan`, `task`, `attempt`, `candidate_sha256`, `build_receipt_sha256`, `test_receipt_sha256`, `verdict` exactly `VERIFIED`, and `peer_review_path`/`peer_review_sha256` plus `formal_evidence_path`/`formal_evidence_sha256`, each review file re-verified against its digest. Run `tools/journal-check` and `tools/diagram-check` before `finish`. Qualifier fields never justify asserting `VERIFIED` while required scope is unfinished: that case takes an honest partial artifact with a non-`VERIFIED` verdict plus a release.
- Three renewal scopes are distinct. A native coordinator heartbeat renews the coordinator **session**. `harness_heartbeat` with a task attached renews the session **and** the active coordinator **task-lease**, and its receipt carries `coordinator_renewal`. The **Sa-plan task lease is renewed by neither**: the same receipt reports `sa_plan_renewal` as `NOT_IMPLEMENTED_RELEASE_AND_RECLAIM_BEFORE_EXPIRY` and exposes `sa_plan_lease_until_ns`. With no task attached the call returns the bare session heartbeat without that wrapper.
- Keep the stable logical effect identity for status lookup and reconciliation; while an outcome is unresolved, do **not** redispatch it or mint a new intent or grant to evade the stop line. Reconcile with an oracle **specific to the operation attempted**. An unchanged source map is **not** sufficient evidence of no effect for any operation: a byte-identical rewrite can still carry side effects, and it says nothing about network, service or other physical effects. The known-no-effect verdict for the refused source write rested on the refusal occurring **pre-dispatch, before the file primitive**, plus a terminal receipt naming `write_scope_refused`.

- A **quarantined unknown is not retryable**: reconcile it to a known outcome first. Once the outcome is known, retry is governed by the actual policy and budget controls that apply, not by any fixed count. Required negative cases are still expected; a refused out-of-scope write still records an unverified effect and trips the stop line, so prefer read-class or claim-class refusals where they test the same guard.
- A bounded diagnostic publishes retained bytes, a digest of those retained bytes, counts on both sides of the bound and an explicit truncation statement; a full-output digest alone verifies nothing present on a truncated record.
- Capability counts carry their states: 65 declared, 53 unprobed, 12 unavailable, admission unknown. The natively connected MCP surface exposes 4 read-only operations and can read public guidance; the private reviewed harness **advertises 13 scoped tools**, of which the core workflow is exercised but **not all 13 are fully verified**. Neither surface is a coverage percentage; exposure is not verification and readability is not adoption.

- `harness_assess` validates every assessment record path against the grant (`assessment_paths_allowed`, `operations.gleam:627`, called at `:678`). A full-portfolio assessment references `governance/planning/20261027-0634-hive-development-readiness-plan.json`, which exists but is absent from this grant's read paths, so such a call would be rejected. This is an **unprobed scope and configuration gap** inferred from source for `PLANNING_MCP`, not an observed failed run; do not bypass it. Where a normal assessment mutation is impossible within an approved scope, report the gap.

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

## Empirical learnings (2026-10-27 sync, per SC-MIRROR-PROJ-001)

1. **Rule mirrors are curated projections of `contracts/rules/`**, not forks. Project every canonical contract into all four vendor `rules/` surfaces as byte-identical copies. Vendor-local adapters may differ only by vendor-path FQDN links and vendor frontmatter (`trigger: always_on`); substance must stay identical.
2. **Short-name shadows** of later timestamped canonical contracts (e.g. `swarm-monitoring-protocol.md` vs `20260908-0935-…`) are preserved, never deleted; the timestamped name is canonical. Record the mapping before any symlink preserve pass.
3. **Sa-plan dependency graph**: filesystem/documentation tasks must not depend on grant/runtime tasks or they become unclaimable. Never force-complete a blocking task or mutate the Sa-plan store out of band (SC-JIDOKA-001).
4. **Harness MCP truth**: a declared MCP server is not a connected, admitted surface. Verify the live tool list (describeNamespace/heartbeat) before relying on it; unconnected servers are `Unavailable_observed`.
5. **Skills mirror via symlink** (`imported-skills`, `20261001-1118-skills`, `plugins/*/skills`); edit the canonical body, never write through the symlink. After any mirror edit re-run the validation gate: 4-mirror isomorphism, JSON parse, skill frontmatter, broken-symlink = 0.
