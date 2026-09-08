# Manual UI testing instance and user guide journal

Generated: 2026-09-08 12:08:34 UTC. Tags: #fractal-l0 #fractal-l2 #fractal-l5 #fractal-l8 #zero-muda #tailscale-web #checklist-nav

[User guide](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-manual-ui-20260908-1150/docs/guides/20260908-1234-manual-gui-tui-testing.md) · [Testing GUI](http://nas-1.tail55d152.ts.net:59463/homeostasis/evolution) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-manual-ui-20260908-1150/tests/evidence/20260908-1234-manual-ui-testing/receipt.json)

## 1. Scope & Trigger

The operator requested a manual GUI/TUI guide and an updated system for testing latest code. Scope is an isolated, bounded homeostasis test instance and repository-local instructions. It does not include main movement or production cutover.

## 2. Pre-State Assessment

Main observed at `231ba3dbf23080d90020a06ce4ce331824e9dac1`; reviewed UI source at `6d15a6d32f798116634a8eb8760e775eb409133c`. An isolated JJ merge preserved both without conflict. Production4100 remained PID1261131/run1261131-1788827505320531, with readiness503 and OTP29/ERTS15.2.7.4. Port59463 and its test unit were unused.

## 3. Execution Detail

Registered Sa-plan `uos/manual-ui/20260908-1150`, task `PREPARE`, worker `codex-manual-ui`, attempt 1. Registered session `codex-manual-ui-20260908-1150` and acquired workspace and `runtime:uos-manual-ui-59463` leases. Used fresh risk and fence checks.

Added a restricted Gleam GET listener, navigation on the test origin and native OCaml manual-web/smoke-manual/browser-manual commands. Built 3535 inventoried files at candidate `517252df824c487ee80e61dfb4dec0fc139ec086`. Started systemd user unit `uos-manual-ui-59463.service`, InvocationID `ba557de3ef1e44e6a272142baea0056a`, PID 2599189, at 12:03:12 UTC. Limits are 4 hours, 1 GiB, 2 CPU equivalents, 128 tasks, no restart, no new privileges and read-only filesystem protection.

Tested direct Tailnet DNS locally and from VM-1, all four terminal modes, and the browser. No production restart, package installation, native Git, Bash script or subagent was used.

## 4. Root Cause Analysis

The previous GUI hardcoded4100 navigation, so a tester on an isolated port could leave the candidate instance. The full application router also exposed unrelated file/operational surfaces unsuitable for a bounded remote test. Prior private staging required host-side resolver overrides and was not a direct remote manual-testing endpoint. A displayed OTP release alone did not establish an internally coherent VM identity.

## 5. Fix Taxonomy

Routing: listener-owned port propagates to all GUI anchor origins. Containment: explicit homeostasis/identity GET allowlist,404 for unrelated paths and405 for writes. Runtime: exact Tailnet interface resolved from canonical FQDN, high-port requirement and coherent observed identity. Process: immutable package, leased single test unit, bounded lifetime and resource limits. Documentation: copy-paste terminal commands and explicit expected/negative states.

## 6. Patterns & Anti-Patterns Discovered

Reuse the same typed evidence projection across GUI, terminal and API. Compare exact deterministic fixtures, but compare provenance and freshness for independent live samples. Keep unknown telemetry unknown. Resolve staging through real Tailnet DNS and verify from a second host. Avoid hardcoded production navigation, treatingHTTP200 as correctness, mixing model time with UTC, and claiming exhaustive testing from a scoped pass.

## 7. Verification Matrix

| Check | Actual outcome | Limit |
|---|---|---|
| Scoped Gleam suite |127pass|Homeostasis/runtime/listener/release scope|
| Transition parity |338cases agree|Finite prefix model, not universal proof|
| Package |3535files inventoried and verified|Candidate-bound package; not admission|
| Manual HTTP smoke |16checks pass; repeated around browser with same runID|Restricted surface|
| Browser |62checks pass;320/768/1280 widths|Four routes, not every UOS page|
| Live stream |At least30seconds of increasing source time and at least10frames|Local VM counters, not physical health|
| Network |VM-1 fetched identical candidate/runID via Tailnet FQDN|One remote peer observed|
| Native TUI |real,disturbance,recovery,unavailable passed|Real native view samples its own VM|
| Mojo/OCaml |Disturbance fixture matches byte-for-byte|Mojo forwards to OCaml operational core|
| Production guard |Same old production PID/runID before and after|Production remains degraded; no cutover|

The 1280px screenshot was visually inspected. PNGs are retained as observed artifacts; no new video recording or human acceptance is claimed. Fault-injection browser checks reject malformed, partial, oversized, reordered and authority-bearing frames, and invalidate stale/disconnected values.

## 8. Files Modified

Application: homeostasis_evolution_hud.gleam; indrajaal/homeostasis_http.gleam; newindrajaal/manual_test.gleam andmanual_test_test.gleam. Native tooling: tools/release_process.ml; tools/validation/homeostasis_browser_check.ml. Records: task riskJSON, this journal, manual guide and scoped evidence. All source/doc changes are in the owned sibling workspace. Runtime package and action/evidence controls are under canonicalvar/releases, outside tracked source.

## 9. Architectural Observations

Gleam owns the read-only listener and typed view. Existing OCaml owns package validation, bounded subprocesses and browser verification. Mojo retains functional command parity through the same operational core. No UI response grants control authority. Observed counters, simulated physiology, transport connectivity and application admission remain separate states.

## 10. Remaining Gaps

Independent integration admission and the known broader NIF ABI failures remain open. Production runtime identity remains incoherent. No complete whole-monorepo/full17 proof, all-page regression or human acceptance is claimed. Native TUI is a one-shot view; its plain-text footer still references4100, and its real counters describe its own short-lived VM. The four-hour test unit is a bounded operator handoff, not a permanent supervised production service. Full restart/failover and long-haul SSE endurance are outside this check.

## 11. Metrics Summary

127 scoped tests, 338 parity cases, 62 browser checks, 16 HTTP checks, 4 native TUI modes and 1 Mojo fixture comparison. Build time: 47.31 seconds. Direct second-host access observed. No paid model call, package download or unbounded autonomous loop. Fresh evidence is bound to candidate/run ID and is not represented as 30 or 50 new evolutionary cycles.

## 12. STAMP & Constitutional Alignment

RiskP2 score432=C4×T3×F4×dependency3×impact3. STPA loss: a tester accidentally operates production or accepts stale/simulated health. Constraints: isolated source/port, no effect routes, source-aware displays, immutable release verification and leased ownership. Jidoka holds production admission at its known failures. The guide supplies the5-domain18-checkpoint evidence structure; unrelated checks remainUNRUN. NativeJJ only; no shared source or VCS main mutation.

## 13. Conclusion

A homeostasis GUI and terminal testing surface bound to the candidate is available directly on port 59463, with documented manual acceptance steps. It is left running for operator use until approximately 16:03:12 UTC under its bounded unit lifetime. Candidate execution and scoped checks passed; production and full-system admission remain separate.

<details>
<summary>Verification checklist: 5 domains / 18 obligations</summary>

Metadata:01UTC/prefix,02Tailnet,03tags,04links recorded.
Purity/storage:05no new barred dependency,06existing language boundaries,07no storage effects.
Tests/math:08scoped tests,09finite parity,10browser+human pending,11scoped regression.
Control/observability:12OTP/ERTS observed,13native OCaml checks,14ZigVM UNRUN,15inference UNRUN,16candidate/run provenance.
Governance:17own task/lease/report with peer admissionUNRUN,18standaloneJJ candidate with main unchanged.
No blanket18/18 admission is asserted.

</details>
