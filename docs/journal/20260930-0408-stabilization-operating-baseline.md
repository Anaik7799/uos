# 20260930-0408 UOS stabilization operating baseline

Observed: 2026-09-30, 03:57–04:16 UTC. Status: **LIMITED OPERATION; recovery remains HOLD**.
Tags: #fractal-l0 #fractal-l2 #zero-muda
Authority: bounded operator-approved development bootstrap, not production admission.
Sa-plan: `uos/stabilization/20260930-0311`, task `BOOTSTRAP`, worker `codex-stabilization-20260930`, attempt 1.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [This journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260930-0408-stabilization-operating-baseline.md)

## 1. Scope & Trigger

The operator requested current-state assessment and stabilization, then approved the proposed bounded local recovery bootstrap with “continue”. This pass restores useful observation and corrects false-success reporting. It does not restore coordinator authority, deploy a release, or claim full system readiness. Engine 5: the existing Gleam harness authority tests are executable evidence; no new Lean/Gospel theorem or two-key admission is claimed.

## 2. Pre-State Assessment

The cockpit and several user services were running. The exposed MCP interface contained only file reads and knowledge search, although canonical task status and capability inventory were callable in the underlying server. The status CLI printed unconditional “Active”, EV-15 admission and enforcement claims. Its entry point returned an integer instead of propagating the verdict to the process exit code.

The canonical coordinator SQLite verifier rejects stored digests at sequences 66–117 and typed replay; the legacy journal rejects event 1762 after 1761 healthy events. Existing independent lineage reconciliation remains unresolved. Engine 7: the prior was an unknown mixed operational state, not a calibrated Kalman estimate. Current observations support limited availability with authority failure; no covariance or stability estimate is invented.

## 3. Execution Detail

Toolchain preflight passed 31 checks; chrony reported normal synchronization and sub-millisecond offset. A dedicated canonical Sa-plan task was created and claimed under the approved bootstrap. Risk preflight and active checks passed their observation contracts, with no effect or admission authority inferred.

The project MCP configuration now exposes `sa_plan_status_for` and `mcp_capability_inventory` alongside the existing two read tools. Codex parsed the new configuration successfully. Initialized stdio MCP calls returned real canonical task counts and a conservative inventory. Missing plan arguments were rejected. A task mutation was refused with code -32003, “Transport-bound task authority unavailable; legacy mutation refused”. The development effect server remains disabled. A fresh MCP connection/session is required for the host application's tool list to pick up configuration changes; the running conversation's tool list is not dynamically reloaded.

The CLI status now says UNRUN/UNKNOWN, reports the EV-93 policy ceiling, and exits 1. The doctor labels existing files INVENTORY instead of VERIFIED. The CLI entry point now calls the existing bounded Erlang halt facade with the computed verdict. Runtime output was checked: status and doctor exit 1; help exits 0.

Tests used copied sources and existing cached dependencies in `/tmp/uos-stabilization-20260930`, with two BEAM schedulers. No package installation occurred. The first harness run failed five tests because the scratch fixture lacked a discoverable repository root and guardian executable. Creating a genuine standalone scratch Jujutsu repository and making the existing toolchain/guardian available corrected that fixture; the same 117 tests then passed. A separate subprocess regression reproduced the discarded exit status before the fix and passed afterward. Engine 6: fail-closed verdict propagation is exercised; no fresh Rete-UL admission is asserted.

### Known operating procedure

Use the Tailnet links above for the cockpit, planning and knowledge pages. All four observed `/health`, `/planning`, `/wiki` and `/zk` routes returned HTTP 200. These are HTTP observations, not browser interaction certification. Browser control was unavailable because the session lacked enabled CUA surfaces.

After reconnecting the project's MCP server, use `sa_plan_status_for` with the explicit plan `uos/system-mcp-features/20260919-1642` or `uos/stabilization/20260930-0311`. Use `mcp_capability_inventory` to inspect declaration/availability, not to infer working capabilities. Its 65 entries comprise 12 unavailable and 53 declared/unprobed entries. A nonexistent plan currently returns zero counts; task counts alone do not prove plan existence. Use canonical `tools/sa-plan plan show <plan-id>` when existence matters.

For an operator's local diagnosis, `bash tools/uos-cli status` intentionally returns 1 until it has actual runtime probes; `bash tools/uos-cli doctor` currently returns HOLD/1. Neither is a health certificate. Authorized development must retain Sa-plan and risk fencing. Do not enable effect tools or restart the failed release on the strength of this document.

## 4. Root Cause Analysis

ACH disconfirmation matrix:

| Hypothesis | Disconfirming observation | Finding |
| --- | --- | --- |
| H1: total toolchain/service outage caused unusability | 31 preflight checks, live HTTP responses and successful initialized MCP reads | Rejected for the observed surfaces |
| H2: missing client exposure restricted useful observation | Underlying MCP supports the two calls omitted by the enabled-tools list | Supported; configuration repaired |
| H3: CLI success reliably represented operation | Status performed no probes, and a subprocess returned 0 after a failure verdict | Rejected; entry point and claims repaired |
| H4: formatting alone explains coordinator rejection | Independent checks report both digest and typed replay failures | Unsupported as a sufficient explanation; historical cause unresolved |

Coordinator and cycle-ledger corruption are observations, not attributed to a writer in this pass. No digest was re-signed and no history was replaced.

## 5. Fix Taxonomy

Poka-Yoke: a subprocess test prevents loss of failure verdicts at the CLI boundary. Jidoka: unobserved runtime status returns failure and task effects remain refused. Muda reduction: use existing pinned tools and a bounded 117-test harness selection; avoid a whole-workspace reformat or repeated full suites. Corrected doctor language separates file inventory from runtime verification.

## 6. Patterns & Anti-Patterns Discovered

Returning an integer from Gleam `main` does not establish the operating-system exit code. A unit test of the internal return value missed the boundary defect; the child-process test exposed it. Runtime availability and authority integrity are separate observations.

Devil's Advocate: HTTP 200, a service PID and “healthy_count=16” can coexist with corrupt ledgers and a failed release. Those observations cannot certify supervised execution or recovery safety. Missing tool exposure is not itself justification to activate all declared capabilities. The MCP audit-only authorization log is not proof of enforcement; the explicit mutation refusal is the narrower observed behavior.

## 7. Verification Matrix

Admiralty/STANAG grading here is an author assessment: B2 for fresh directly observed local results, not independent sovereign review. Reports remain bounded to the listed sources and commands. Source digests and raw results are retained in [the evidence inventory](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260930-0408-stabilization-evidence/20260930-0412-source-hashes.txt).

| Check | Observed result | Limit |
| --- | --- | --- |
| Pinned toolchain preflight | 31 checks passed | Tool availability, not admission |
| Focused Gleam harness tests | 117 passed, 0 failed | Eight selected harness/MCP modules, isolated development |
| Status regression tests | 2 passed; subprocess failure reproduced first | Entry-point and unobserved status contracts |
| Actual CLI commands | status=1, doctor=1, help=0 | No runtime health verdict from status |
| MCP reads and negative controls | Counts/inventory returned; missing plan rejected; task mutation refused | Same generic server entry point; no successor grant |
| Live HTTP | health/planning/wiki/zk: 200 | No browser interaction test |
| Service manager | cockpit, Sa-plan HTTP, cognitive worker active; no restarts reported for these | Sa-plan HTTP cwd is external `/home/an/NAS-setup/c3i` |
| Ecology release unit | failed; three restarts recorded; PID 0; startup rejects `runtime dependency changed: max_manifest` | Not restarted or deployed; no bypass of dependency check |
| Coordinator SQLite | HOLD: 117 checked; digest and replay failure | Sequence/link/triggers alone do not establish integrity |
| Legacy coordinator | HOLD: first failure at 1762 | Original preserved |
| KM gate | HOLD: 71/550 cycle digests fail; first 333; prohibited EV-111 manifest claim | Layer entropy now 3.298 bits, not the historical 1.306 claim |
| Doctor inventory | 2 artifacts present, 91 undeclared, 18 above EV-93; total 111 | No candidate admission |
| Formatting | new regression file formatted; main already failed formatting before this task | Broad pre-existing formatting preserved |
| Risk validator `--all` | 375 baseline and 32,843 adversarial checks passed; 32,768 independent DAG scenarios | Report-only; live agent tests UNRUN |
| Journal checker | 10/10 structural checks passed; journal HTTP 200 | Mechanical structure, not validation of every prose claim |

## 8. Files Modified

- `.codex/config.toml`: expose two observed read tools; preserve disabled development server.
- `tools/uos/src/main.gleam`: truthful status, inventory terminology, exit-code propagation.
- `tools/uos/test/status_truth_test.gleam`: internal and subprocess failure regression.
- `governance/planning/20260930-0311-stabilization-risk.json`: bounded bootstrap assessment and source binding.
- `governance/planning/20260930-0408-stabilization-evidence/`: command observations, selected test logs, source hashes and exact task-owned patch.
- This timestamped journal.

The working copy had extensive unrelated changes before this task. Jujutsu was observed without replacing or resetting those changes. Starting working-copy identity was `vwzysoxv / 98ef3335`, parent `f83c326b`; dirty bytes are additionally bound by the evidence hash manifest. No release bookmark or main bookmark was created. Only this task's hunks are represented by its preimage diff. Its own accidental Erlang crash dump was moved to a restricted temporary file, outside the repository and evidence bundle.

## 9. Architectural Observations

Gleam owns CLI/control decisions; the existing Erlang halt function is a narrow runtime facade. OCaml Sa-plan remains the task store. Engine 5/sheaf-presheaf consistency: a healthy local web observation does not extend to a consistent global authority claim when the coordinator and cycle ledger disagree. No categorical proof is asserted. The development harness still binds the legacy coordinator; selecting and integrating canonical authority is separate work.

## 10. Remaining Gaps

The broad stabilization request is **not complete**. The existing plan `uos/system-mcp-features/20260919-1642` still has 17 of 21 tasks incomplete. Follow its dependencies: `t0a-reconcile` and `r02-recovery-candidate` for preserved-history authority recovery; `r03-harness-coordinator` for harness binding; `r11-release-review` for independent review; `r12-operational-acceptance` for deployed usability. These are canonical Sa-plan tasks, not new execution authority granted by this prose.

Residuals: failed ecology release, corrupt coordinator and cycle ledgers, unreviewed successor activation, stale/static health assertions, unknown adapter behavior, broad test coverage unrun, and external Sa-plan HTTP runtime lineage. Release logs identify the immediate startup blocker as `runtime dependency changed: max_manifest`; reconcile the intended inference manifest with a reviewed release rather than bypassing its guard or discarding other work. The pre-existing recovery candidate diverges from canonical history at its first sequence and is not promoted. An independent review and valid candidate-bound grant are still prerequisites for restoring effectful automation. The current operator authorization permits development bootstrap, not silent historical replacement or production admission.

## 11. Metrics Summary

Fresh bounded results: 117/117 harness tests and 2/2 status tests; four HTTP routes observed; three active user services and one failed release service inspected. The first isolated harness run had 112 passes and five fixture failures; those results are retained rather than erased. The failing subprocess control was 0 where 1 was required.

Engine 3: a Bayesian Beta-Binomial operational reliability estimate is not reported because these selected tests are correlated and are not repeated production trials. There is insufficient time-series evidence for a Lyapunov derivative or long-term stability claim. Evidence should be refreshed after any source/configuration/runtime change and before an effect; this snapshot is not a standing lease.

## 12. STAMP & Constitutional Alignment

Unsafe-control-action coverage: (1) withholding useful observation was reduced by enabling two verified reads; (2) providing unauthorized task effects remains blocked; (3) acting with stale identity/authority remains a HOLD; (4) continuing beyond the bounded bootstrap is prevented by retaining separate recovery/release tasks and refusing blanket completion. Raw FMEA, evidence age and acceptance conditions are in the risk assessment. No storage operation, external source mutation, production restart, new dependency or EV-number creation occurred. Zero-Muda requires 0 Bevy and 0 Graphite; no such dependency was introduced.

<details>
<summary>Comprehensive verification checklist — scoped evidence, not blanket green</summary>

Domain 1 — metadata/navigation:

- [x] CHK-01-TIME: timestamped journal; synchronized host clock observed.
- [x] CHK-02-TAIL: full Tailnet navigation links provided.
- [x] CHK-03-FRACT: relevant layer tags present.
- [ ] CHK-04-KM: bidirectional transclusion not exercised.

Domain 2 — purity/storage:

- [x] CHK-05-MUDA: no new prohibited source or dependency in this change; historical purity not re-certified.
- [x] CHK-06-GRAPH: no new foreign NIF or vector dependency.
- [ ] CHK-07-DRIVE: storage interlock not exercised; storage untouched.

Domain 3 — testing:

- [ ] CHK-08-C1C8: full eight-category UI assessment unrun.
- [ ] CHK-09-MATH: full four-metric suite unrun.
- [ ] CHK-10-9MOD: full nine-modality suite unrun.
- [ ] CHK-11-REGR: full UI regression/monitoring unrun.

Domain 4 — language/observability:

- [x] CHK-12-GLEAM: focused Gleam harness/CLI behavior observed; whole supervisor conformance unproven.
- [x] CHK-13-HERMES: canonical Sa-plan and bounded OCaml checker used; full formal engine unrun.
- [ ] CHK-14-ZIGVM: deterministic kernel behavior not exercised here.
- [ ] CHK-15-MAX: inference daemon behavior not exercised here.
- [ ] CHK-16-OTEL: complete trace propagation not verified.

Domain 5 — governance/VCS:

- [ ] CHK-17-SOV: independent multi-sovereign review pending.
- [x] CHK-18-JJ: standalone JJ preserved; no native Git mutation; doctor HOLD recorded.

Domain 6 — provenance:

- [x] CHK-19-CEIL: EV-93 retained as policy ceiling; higher claims not admitted.
- [x] CHK-20-INDEX: observed KM index ratios 1.0; correctness beyond presence not inferred.
- [x] CHK-21-PRESERVE: historical/quarantine records untouched by this pass.
- [ ] CHK-22-CHAIN: coordinator and cycle digest integrity fail.
- [ ] CHK-23-NOMINT: this pass minted none; existing manifest violates the bar.
- [ ] CHK-24-FAILCLOSED: repaired CLI and tested refusal observed; all metric paths not verified.

</details>

## 13. Conclusion

The bounded bootstrap establishes a reproducible observation baseline and removes two false-success mechanisms. Full usable automation remains HOLD; no production or EV admission is claimed. Engine 7 precommitted Forecast: with unchanged files, within 24 hours of 2026-09-30T04:12Z, a fresh CLI status invocation will report UNRUN and exit 1, p = 0.99. Score using Brier `(p - outcome)^2` after the next observation; outcome is currently unscored. This forecast concerns the CLI contract, not service uptime.

[Previous: policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) · [Next: canonical recovery planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260930-0408-stabilization-evidence/20260930-0412-source-hashes.txt)

UOS · nas-1.tail55d152.ts.net:4100 · LIMITED OPERATION / RECOVERY HOLD
