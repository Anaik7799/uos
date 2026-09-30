# 20260909-0320 — EV105, EV106 and EV109 control-boundary repair

#fractal-l0 #fractal-l2 #fractal-l5 #fractal-l7 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0320-ev-homeostasis-repair-journal.md)

Created from observed host time 2026-09-09T03:24:20Z. Prefix encodes UTC hour and seconds. Scope is an implementation handoff, **NOT_ADMITTED**. Canonical Sa-plan `uos/ev-homeostasis-repair/20260909`, task `REPAIR`, worker `codex-ev-homeostasis`, attempt 1; parent `uos/ev-admission/20260909-0210`, task `PROGRAM`. No new EV identifier was minted.

## 1. Scope & Trigger

Repair the parent-observed EV105 ballot roster/fault overwrite, EV106 negative token consumption, and EV109 supplied-proposal application defects. Base is immutable Jujutsu commit `337f99137673d7866b958a38bd490fb876b2880f`; isolated workspace is `.uos-workspaces/ev-homeostasis-repair-20260909`. The parent authentic session reserved that workspace at coordinator epoch 1; this worker never registered a synthetic Herdr identity or acted as a sovereign reviewer.

## 2. Pre-State Assessment

`cast_ballot_vote` accepted arbitrary `PeerSovereign` names and could overwrite `VerdictByzantineFault` with later votes. `consume_tokens(-1)` increased available tokens and decreased consumed tokens. `apply_ratified_evolution` trusted a supplied verdict and generation without current health, physiology, owned proposal membership, or replay validation. The OTP actor stored neither proposal submission nor voting progress.

The P1 assessment retained S5/O3/Det4, RPN60, severity-floor F5 and C4/T5/Dep5/I5, score2500. Occurrence is a source-supported analyst assessment, not measured fleet frequency. Eleven independently specified boundary tests failed on the base implementation; the red log records every test name and failure.

## 3. Execution Detail

Sa-plan preflight passed at03:12:01Z; exact REPAIR claim returned attempt1; active observation passed at03:12:16Z. Tests were written and executed before production repairs. The first fresh dependency build could not load cached rebar `pc` and attempted an unavailable Hex update. No download succeeded. The parent authorized copying already-realized root dependency artifacts, excluding the local `cepaf_gleam`, `uos_swarm` and `uos_tui` application outputs. Local source applications were compiled in this workspace. Reused dependencies are compiler inputs, not newly verified dependency builds.

EV105 adds typed eligible sovereign rosters and terminal Byzantine faults; display-name aliases cannot impersonate roster members. BFT configurations beyond the available fixed roster fail closed. EV106 adds typed `InvalidTokenAmount` and `TokenBudgetExhausted` errors. EV109 adds registered submit/vote transitions, exact current proposal comparison, typed rejection results, current equilibrium checks, monotonic generation, replay prevention and actor-owned pending state. Pure proposal/vote previews remain available but carry no application authority. Simulation and test callers use registered transitions.

The first green run passed55 tests. Additional actual actor state-preservation, recovery, stale-generation and token-conservation checks increased the final run to61 tests. A test-only helper initially lacked a Gleam type annotation; its compiler failure is preserved and the helper was corrected before the passing run.

## 4. Root Cause Analysis

The code conflated supplied intent with owned authority. Ballot eligibility was represented only as a count; mutable verdict records were treated as sufficient evidence; and actor message handling replied without recording the submission/vote transition. The debit operation also lacked its domain guard. The repair moves validation to the state transition that can change generation or debit the budget.

Process incident: an active risk check returned HOLD because `chronyc` could not access the daemon. A non-short-circuit tool batch nevertheless applied the first two source patches. This did not satisfy the effect-boundary rule. The worker immediately notified the parent, stopped further effects, preserved the HOLD and edits, observed normal clock state, refreshed patched-source hashes, and obtained ACTIVE_OBSERVATION_PASS at03:16:29Z. Later clock access failures were held and repaired via scoped escalation. A pre-check assessment contained an incorrectly anticipated03:20 timestamp; it was preserved and superseded using the actual03:19:40 host observation before any test execution. Checks and dependent effects were then separated.

## 5. Fix Taxonomy

Input-domain validation: negative debits and unrostered identities. State-machine validation: terminal faults, exact registered proposals, current equilibrium and monotonic generation. Ownership correction: actor stores submission and vote progress. Replay prevention: previously applied IDs and obsolete generations are rejected; successful application invalidates pending proposals for that generation. Process correction: inspect each risk-check exit before dependent effects and bind refreshed source bytes.

## 6. Patterns & Anti-Patterns Discovered

A roster is typed identity data, not a voter count or a display label. Pure preview functions must not grant effect authority. Assertions check real actor replies and subsequent owned state, not only helper outputs. Reusing compiler dependencies is distinct from reusing local application output. The initial dependency-hash list included only32 `.app` files because ripgrep honored ignore rules; the explicitly superseding `--no-ignore` v2 manifest covers277 runtime `.beam`/`.app` files.

## 7. Verification Matrix

| Observation | Result | Scope / receipt |
|---|---|---|
| TDD base failures |11 failed,0 passed; exit1 |`docs/reviews/20260909-0320-homeostasis-red-tests.log` |
| Base local compilation |exit0 after realized dependency reuse |`20260909-0320-homeostasis-red-build.log` |
| Final local compilation |exit0; existing unrelated warnings retained |`20260909-0320-homeostasis-final-build.log` |
| Final bounded EUnit |61 passed,0 failed; exit0 |`20260909-0320-homeostasis-final-tests.log` |
| Runtime identity |OTP29 / ERTS17.0.5 |Actual `erlang:system_info` in test receipt; binary from realized OTP29.0.5 store path |
| Core source-bound task observation |ACTIVE_OBSERVATION_PASS03:23:43Z |`20260909-0315-homeostasis-risk-candidate.json`; current task attempt1 |
| Candidate source manifest |8 source/test files |`20260909-0320-homeostasis-candidate-source-sha256.txt` |
| Dependency identities |Lock hashes and277 runtime artifact hashes |`20260909-0315-homeostasis-dependency-lock-sha256.txt`, `20260909-0320-homeostasis-reused-dependency-sha256-v2.txt` |
| Formal refinement |UNRUN / NOT_IMPLEMENTED |Existing `formal/lean/Homeostasis_Evolution.lean` explicitly disclaims runtime refinement and consensus |
| Independent review / integration / release |Pending / UNRUN / UNRUN |Parent must independently review immutable candidate; no sovereign admission asserted |

The61 tests cover seven modules: `ev_control_boundary_test`, `multi_agent_quorum_test`, `predictive_autoscaler_test`, `homeostasis_evolution_engine_test`, `tui_15_evolutionary_cycles_test`, `homeostasis_evolution_hud_test`, `multi_agent_quorum_hud_test`. New boundary module has17 tests, including real isolated OTP actors.

Reproduction from `apps/cepaf_gleam`, after restoring the recorded realized dependencies:

```text
PATH=/home/an/NAS-setup/uos/toolchains/gleam-1.16.0/bin:/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin:/home/an/.nix-profile/bin:/usr/bin:/bin ERL_FLAGS='+S 2:2' timeout 180 gleam build
ERL_FLAGS='+S 2:2' timeout 60 /nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl -noshell -pa build/dev/erlang/*/ebin -eval 'io:format("OTP=~p ERTS=~p~n", [erlang:system_info(otp_release), erlang:system_info(version)]), case eunit:test([ev_control_boundary_test, multi_agent_quorum_test, predictive_autoscaler_test, homeostasis_evolution_engine_test, tui_15_evolutionary_cycles_test, homeostasis_evolution_hud_test, multi_agent_quorum_hud_test], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
```

Seventeen-aspect release coverage remains explicit; these are scoped observations, not a release certificate:

| Aspect | Status |
|---|---|
|1. Source/candidate identity |PASS: immutable base and current source hashes |
|2. Canonical task / claim |PASS: REPAIR attempt1, pending parent completion |
|3. Coordinator workspace |Parent authentic epoch1 reservation; no runtime lease |
|4. Actual OTP runtime |PASS: isolated actor executions on OTP29/ERTS17.0.5 |
|5. State-machine rejection |PASS: scoped tests |
|6. Replay / generation |PASS: scoped pure and actor tests |
|7. Ballot roster / terminal fault |PASS: fixed roster model tests |
|8. Authentication / IAM |UNRUN: typed identities are not authenticated remote workloads |
|9. Budget arithmetic |PASS: bounded token-debit cases |
|10. Formal refinement |NOT_IMPLEMENTED by this patch |
|11. Four-domain supervision |UNRUN: isolated actor only |
|12. Observability correlation |UNRUN: no live OTel trace evidence |
|13. UI model compatibility |PASS: scoped TUI/HUD tests; browser interactions UNRUN |
|14. Dependency/toolchain |Realized inputs reused; dependency-source rebuild blocked and preserved |
|15. Deployment / recovery |Deployment UNRUN; model intervention/recovery PASS |
|16. Independent sovereign review |Pending; no AGY or Codex admission signature fabricated |
|17. Storage / historical provenance |No storage or historical-ledger mutation; global storage gates UNRUN |

## 8. Files Modified

Eight source/test files under `apps/cepaf_gleam`: three HA modules, `ui/homeostasis_data.gleam`, new `test/ev_control_boundary_test.gleam`, and existing homeostasis, autoscaler and fifteen-cycle tests. Timestamped risk assessments, source/dependency manifests and build/test/error receipts are under `docs/reviews`; this journal is under `docs/journal`. No runtime, dependency manifest, historical ledger, admission ceiling or EV record was edited.

## 9. Architectural Observations

The owned actor state is the boundary that prevents caller-supplied proposal/vote history from becoming authority. Pure state records remain constructible by trusted in-process Gleam code; this patch does not introduce cryptographic or kernel isolation. Public voter enums identify the intended sovereign but do not authenticate who sent the message. Domain errors are typed at application and token-debit boundaries; UI simulation deliberately converts them to display strings.

## 10. Remaining Gaps

Required before admission: independent candidate review; machine-checked refinement of roster uniqueness, terminal-fault preservation, registered transition membership, generation monotonicity, and effect-time equilibrium; binding to actual authenticated sovereign sessions/evidence; live root-supervisor integration, fault/restart and persisted-state recovery evidence; source-bound deployment/recovery and relevant fleet checks. The existing Lean arithmetic facts cannot discharge these obligations. BFT rosters larger than four are deliberately unsupported. No system-wide test coverage percentage, C1–C8 completion, mathematical-quality score or admission state is inferred from61 scoped passes.

## 11. Metrics Summary

Eleven red regressions; seventeen final boundary tests; sixty-one final scoped tests; final build2.14s; bounded EUnit process approximately0.29s wall time; two BEAM schedulers; no new packages, paid inference, shared runtime changes or new EV IDs.277 reused runtime dependency artifacts are hashed. Source changes occupy eight files; evidence files are separate. All durations refer to the observed local invocations, not service performance.

## 12. STAMP & Constitutional Alignment

Not-provided UCA: omitted current-state validation is addressed at apply. Unsafe-provided UCA: unrostered voters, negative debits and substituted proposals are rejected. Wrong-timing UCA: stale generation/vote snapshots and replay cannot update owned state. Duration UCA: terminal faults persist; bounded test processes and task leases limit worker lifetime. Authentication, distributed consensus, formal refinement and runtime fencing remain unresolved P1 release constraints. Existing EV claims remain NOT_ADMITTED; the worker is an implementer, not an independent sovereign.

## 13. Conclusion

The candidate implements the bounded defects and passes the recorded61-test suite. Sa-plan completion, independent review, integration and admission remain with the parent’s authorized process. This journal preserves the clock-check incident and failed compiler/build observations; it does not convert them into passing history.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Observed host time and chronological corrections recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN navigation included; live serving UNRUN.
- [x] CHK-03-FRACT — Scoped fractal tags provided.
- [x] CHK-04-KM — Journal and evidence locators linked to canonical planning context.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — No dependencies introduced; global exclusion scan UNRUN.
- [x] CHK-06-GRAPH — Pure Gleam changes; no new NIF or foreign runtime.
- [ ] CHK-07-DRIVE — Storage interlocks UNRUN; no storage mutation in scope.

</details>
<details><summary>Domain 3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8 — Full browser categories UNRUN.
- [ ] CHK-09-MATH — Formal refinement and four mathematical gates UNRUN.
- [x] CHK-10-9MOD — Scoped TDD/unit/actor sequences observed; remaining modalities UNRUN.
- [ ] CHK-11-REGR — Live UI monitoring UNRUN; TUI/HUD model checks passed.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [x] CHK-12-GLEAM — Isolated OTP actor transitions observed; full supervision UNRUN.
- [ ] CHK-13-HERMES — Formal/runtime integration UNRUN.
- [ ] CHK-14-ZIGVM — Runtime kernel unchanged; execution UNRUN.
- [ ] CHK-15-MAX — Inference unchanged; execution UNRUN.
- [ ] CHK-16-OTEL — Live trace correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review and admission pending.
- [x] CHK-18-JJ — Standalone Jujutsu isolated workspace; no native Git mutations.

</details>
<details><summary>Domain 6 — Provenance</summary>

Historical ledgers and quarantined EV claims are preserved. Red evidence, process incident and failed builds remain explicit. No new EV ID or admission claim is generated.

</details>

**UOS footer:** Bounded implementation handoff; NOT_ADMITTED. [Previous: risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Next: planning](http://nas-1.tail55d152.ts.net:4100/planning)
