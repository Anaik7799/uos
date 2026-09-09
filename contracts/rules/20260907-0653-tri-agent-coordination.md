# 20260907-0653 — Shared agent coordination contract

#fractal-l0 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web

**UOS / Coordination / Contract** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)  
**Live document:** [http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-0653-tri-agent-coordination.md](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-0653-tri-agent-coordination.md) · [Source](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-0653-tri-agent-coordination.md)

Created: 2026-09-07T06:38:53Z. Operator authority: parallel Claude, Codex, AGY and OpenRouter agent swarms for UOS SDLC and SRE. This contract adds a coordination protocol; it does not grant system admission or credentials. Canonical repository: `/home/an/NAS-setup/uos`.

## Coordination rules

1. **SYNC-01 Observe before work.** Discover the real Herdr pane/session identity and inspect the UOS coordination status, inbox, working change, main bookmark and task state. A running process, successful prompt delivery or synthetic probe is not a peer acknowledgement.
2. **SYNC-02 Preserve work.** All VCS writes use standalone JJ. Record an immutable candidate commit and stable change ID. Preserve all pre-existing edits. Parallel workers own disjoint paths or separate JJ workspaces; they must not format, regenerate, rebase or overwrite another worker's files.
3. **SYNC-03 One integration writer.** Claim `integration/main` in the durable local coordinator and announce it on the signed board. Other sessions acknowledge the ownership and hold VCS mutations. Recheck the current epoch immediately before each integration step. A lease is a cooperative coordination guard; the standalone JJ binary does not independently enforce it.
4. **SYNC-04 Runtime ownership is separate.** Claim `runtime:<service>` independently of source ownership. An incident report, ACK, test success or model response grants no deploy/restart/delete permission. Runtime changes require a typed, revision-bound authorized action with a concrete target, rollback and post-change check.
5. **SYNC-05 Durable events.** Never truncate or regenerate the live coordination journal. Never delete a shared Zenoh key namespace to refresh a dashboard. Projections are rebuildable and must preserve foreign senders; board transport delivery and peer ACK are different facts.
6. **SYNC-06 Fencing and replay.** Claims have monotone epochs, bounded TTL and explicit holder. Renew/release/check require the live epoch and correct holder. Replayed operation IDs with identical commands return the same result; conflicting command reuse fails. Expired or replaced sessions cannot reuse old ownership. Local filesystem access is the current trust boundary, not cryptographic workload IAM.
7. **SYNC-07 Bounded Herdr adapter.** Use only discovered pane IDs with expected live session IDs. Deny blocked/unknown targets, automatic approval answers, shell injection, automatic restart and ambiguous prompt retries. Check both project and foreground directory provenance. The explicit AGY exception covers its known ZigVM harness installation while its project remains UOS. A Herdr pre/post identity check has a documented race; it is not an atomic session fence.
8. **SYNC-08 Small work packets.** Send task ID, owner, scoped paths, base/candidate revisions, acceptance criteria, budget and evidence references. Do not resend full histories or private reasoning. Request concise actionable findings, not parallel duplication of the same analysis.
9. **SYNC-09 OpenRouter economy.** Deterministic checks run locally. Remote models produce bounded advisory results only. Use a current allowlist and price receipt, free-first routing, explicit paid opt-in, a maximum 512 completion tokens and USD 0.02 request ceiling. Unknown/unbounded price, missing credential, exhausted budget or provider ambiguity fails closed. Record actual model/provider/usage and cost uncertainty. Do not infer fleet-wide spend limits from a per-request bound.
10. **SYNC-10 Evidence before closure.** Candidate hashes, tool versions, invocation, exit status, test/model bounds and limitations accompany results. Seventeen aspect rows remain explicit; no constant-true matrix, file presence or model opinion is runtime proof. `UNKNOWN`, `UNRUN`, `STALE` and `NOT_ADMITTED` remain nonpassing.
11. **SYNC-11 SDLC and SRE lifecycle.** Plan/claim/design/build/test/review/integrate/release/observe/incident/rollback/postmortem are distinct steps. Per `SC-JIDOKA-001` and `SC-SA-PLAN-001`, `sa-plan` (`tools/sa-plan`, `var/sa-plan/uos.sqlite3`) is the sole, exclusive task, Oban job, and Temporal workflow authority across all autonomous agents (AGY, Claude, Codex, swarms). All task claiming must hold monotonic leases (`claim WORKER PLAN LEASE_NS TASK_ID`). Any attempt to manipulate, bypass, or execute tasks outside `sa-plan` triggers an immediate fail-closed Andon stop line (error `-32002`), halting execution immediately. Session coordination owns local work/resource reservations; the signed board carries exchange and evidence references. Neither a board message nor a model output completes a Sa-plan task automatically.
12. **SYNC-12 Recovery.** On a dead session, inspect outstanding effect outcomes before reclaiming work. Verify dead lock ownership before removing a lock; unknown or live owners fail closed. Reconcile mainline and inbox before resuming. Backups include the private coordination directory, with no live state admitted to source history.
13. **SYNC-13 Toolchain preflight before work.** Before claiming a task or producing evidence, every agent runs `bash tools/preflight` (or accepts a fresh receipt via `--max-age`). Its six arms cover resolver, useability (all entrypoints EXECUTED, not stat'ed), wrappers, VCS tracking, table parity and — under `--full` — derivation identity. A receipt is honoured only while the checker that wrote it is unchanged. Results are advisory evidence about the toolchain: a PASS neither completes a Sa-plan task nor grants deploy or admission authority, and a FAIL is a stop line for evidence production because artefacts built on an unverified toolchain are mislabelled, per `SC-NIX-DEVENV-001`.

## Enforcement boundary

The new CLI checks durable local coordination commands. Existing CLI tools and runtime APIs are not made mandatory consumers merely by adding this contract. Cross-user IAM, mandatory kernel-level fences, authenticated remote task acceptance, continuous daemon supervision and production release adapters require their own two-key evidence. This boundary is recorded so cooperative operation is not mistaken for security isolation.

See [system specification](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0653-uos-tri-agent-sdlc-sre-herdr-spec.md) and [operator runbook](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-0653-uos-tri-agent-swarm-operations.md)


## Comprehensive verification checklist

Document checks and production gates have different evidence scopes. Checked
items below refer only to this document package. All infrastructure runtime,
formal-proof and sovereign-admission obligations remain **UNRUN**.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Host-clock timestamp prefix and chrony receipt recorded.
- [x] **CHK-02-TAIL** — Full clickable Tailscale FQDN references provided; serving status is reported in the journal.
- [x] **CHK-03-FRACT** — Canonical L0–L9 fractal tags assigned.
- [x] **CHK-04-KM** — Specification, wiki, ADR, source review and journal cross-linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Production dependency/exclusion scan required.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary must pass runtime checks.
- [ ] **CHK-07-DRIVE** — Denied OS serial `25503L801736` must pass real interlock tests.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Structure, health badges, data grids, timeline, interactions, dark cockpit, advisory and action interlock.
- [ ] **CHK-09-MATH** — H ≥ 2.50 bits, CCM ≥ 90.0%, D_EA ≤ 10.0%, ITQS ≥ 0.85 require declared metrics and fresh measurements.
- [ ] **CHK-10-9MOD** — Unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos.
- [ ] **CHK-11-REGR** — Relevant UI regression suite and 30-second monitoring require execution.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Real OTP domain/actor supervision and restart evidence.
- [ ] **CHK-13-HERMES** — Authoritative WAL, bounded formal checks and evidence receipts.
- [ ] **CHK-14-ZIGVM** — Deterministic execution and descriptor-relative VFS evidence.
- [ ] **CHK-15-MAX** — Real inference through the isolated MAX boundary.
- [ ] **CHK-16-OTEL** — UTC microsecond timestamps and nonzero W3C trace/span IDs.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Tri-sovereign candidate review and authorized admission are outstanding.
- [x] **CHK-18-JJ** — Documentation authored in UOS using its standalone JJ discipline; no native Git mutations in UOS.

</details>


**Previous:** [Infrastructure specification](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md) · **Next:** [Swarm operations](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-0653-uos-tri-agent-swarm-operations.md)  
**UOS footer:** Local coordination contract; production admission remains evidence-bound.
