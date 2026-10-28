# 20261028-0853 - Controller and worker isolation amendment

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Prior plan](http://nas-1.tail55d152.ts.net:4100/docs/journal/20261028-0815-controller-assessment-bootstrap-plan.md) | [Full plan](http://nas-1.tail55d152.ts.net:4100/docs/journal/20261028-0118-uos-full-fractal-four-client-mcp-plan.md) | [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

## 1. Scope & Trigger
This proposed amendment replaces only the launcher/isolation condition for the initial-assessment editor. The0815plan SHA e1dd917f42829e7ed0ff0014c2b9645fe34dbd749560ab766bf368013aa38eaa and completed0806review are preserved. No source code was changed under the blocked activation.

## 2. Pre-State Assessment
The reviewed whole-controller network namespace failed before MCP initialization. The minimal writable JJ working-copy state mount resolved its read-only lock failure; the next gate refused bounded_clock_sampler_failed. The actual user cannot reach the host chrony socket in0700 _chrony-owned /run/chrony. Removing host networking also removes the sampler's host-loopback path. No injected clock or unisolated build/test fallback was used.

## 3. Execution Detail
As-is: a clean editor sibling and frozen serving controller are verified, but the old handler does not itself isolate build/test networking.

To-be: real control/time policy stays in the trusted frozen controller; development build/test execution is isolated separately.

Approach:
1. Issue a new independently reviewed SOURCE-ONLY grant. Preserve the old grant and failed launcher observations.
2. Run the frozen817e8 controller with the required real host time/control access in a filesystem sandbox: serving source/build read-only; only registered editor, canonical var metadata, named evidence directories and minimum JJ working-copy lock/state writable. Clear inherited provider credentials. No chrony permission changes or synthetic samples.
3. Permit only named source/evidence read/write, assessment, claim/attach/release and observation operations in this source-only phase. The operator and trusted executor MUST NOT invoke the old harness_build or harness_test under this launcher.
4. Compile/test only through separately authorized, fixed-argument native Gleam bounded bootstrap workers using bwrap --unshare-net. Bind/copy only already-realized source-identical pinned toolchains/dependencies/cache. Missing inputs are UNRUN/failed, not silently fetched; no host-network test fallback.
5. Record actual launcher init, real clock, task and source-root fences before source writes. Record actual network-isolated worker command, inputs, exit, output and readback before any test claim.
6. Review the implementation and actual new control identities separately before any new serving-code activation.

The old handler lacks an enforced per-tool/network allowlist for this distinction. This source-only phase relies on the reviewed trusted-executor restriction; it is not a hostile-worker isolation or production-admission claim. Child isolation and the new initial-assessment helper remain unverified until executed.

The selected canonical task is now available COMMAND_ACCEPT attempt4: it was released at08:48:58 after a passing active check, before its08:50:42 lease expiry. New work must genuinely claim a new attempt through admitted control after fresh risk checks; it must not reuse the released attempt.

## 4. Root Cause Analysis
ACH disconfirmation matrix:

| Hypothesis | Disconfirmation | Assessment |
|---|---|---|
| H1: editor source already broke the controller | No source writes occurred; failure preceded initialization | Refuted |
| H2: complete controller network removal conflicts with its real time dependency | JJ fix reached clock refusal; socket access and loopback observations explain it | Supported |
| H3: test-network isolation requires disabling trusted control time | A separated control/worker design can retain real clock and isolate only execution | Proposed, not yet tested |

Raw FMEA: S5, O3, Det1, RPN15 severity floor5, ordinal judgments. Primary failure mode: an isolation exception becomes unrestricted worker network access or fake time authority. Controls: explicit source-only restriction, fixed bounded isolated workers, real clock checks, independent review and retained negative evidence.

## 5. Fix Taxonomy
Poka-Yoke separates controller and worker requirements. Jidoka retains fail-closed initialization and unknown-effect handling. Muda removes repeated impossible launcher attempts without claiming readiness.

## 6. Patterns & Anti-Patterns Discovered
Popperian Falsification: any source change before approved activation, fake clock receipt, chrony permission broadening, old unisolated build/test call, hidden dependency fetch, canonical-source write or unreviewed serving reload falsifies this amendment's conditions.

## 7. Verification Matrix
Admiralty B2 applies only to observed clean source, root-routing checks and the actual failed activation reports. New source-only launcher, isolated build/test workers and initial-assessment implementation remain UNRUN. The amended policy is not runtime evidence.

## 8. Files Modified
Only this new plan amendment is created. Prior0815plan and0806review remain byte-preserved. No product source or canonical main was changed.

## 9. Architectural Observations
Gleam/OTP retains check/time/backend policy. Native execution stays bounded and isolated. Metadata-only initial assessment still must not construct fake Execution values or claim/renew tasks. Canonical risk-evidence bytes and editor candidate bytes are distinct roots; the mixed-root negative test remains required.

## 10. Remaining Gaps
Initial-assessment implementation, enforced worker-network policy, deterministic CAS barrier, proactive renewal, durable unknown recovery, full26-control integration, four native-client tool turns and the public/private MCP union remain open. The earlier CAS case is owner-only generation2, not a successful simultaneous race.

## 11. Metrics Summary
No new test passed during blocked activation. Bayesian Beta-Binomial calibration, half-life decay and Lyapunov dV/dt remain UNRUN. Earlier125/133/104 suites overlap and must not be summed. Provider/model calls are not authorized by this amendment.

## 12. STAMP & Constitutional Alignment
Allfour UCA types apply: omitted time access, unsafe worker network access, stale checks and excessive grant/lease duration. Real task/grant/epoch/source fences remain mandatory. No authority arises from a review alone. Standalone JJ, external-source read-only discipline, storage interlock, Zero-Muda and EV93 ceiling remain unchanged.

## 13. Conclusion
Forecast: subjective uncalibrated probability0.7 that a source-only launcher and initial-assessment implementation result will be reviewable by2026-10-28T09:30:00Z. Horizon and Brier resolution PENDING; this concerns a development result, not capability admission or full goal completion.

## Comprehensive verification checklist
<details><summary>Domain1 - Metadata</summary>
- [x] CHK01 timestamp prefix.
- [x] CHK02 full Tailnet links; serving-byte verification pending.
- [x] CHK03 fractal tags.
- [ ] CHK04 knowledge synchronization pending.
</details>
<details><summary>Domain2 - Purity and storage</summary>
- [ ] CHK05 dependency audit pending.
- [ ] CHK06 runtime graph pending.
- [ ] CHK07 interlock not exercised.
</details>
<details><summary>Domain3 - Tests and math</summary>
- [ ] CHK08 C1-C8 pending.
- [ ] CHK09 mathematical gates pending.
- [ ] CHK10 modalities pending.
- [ ] CHK11 new regression evidence pending.
</details>
<details><summary>Domain4 - Control</summary>
- [x] CHK12 Gleam policy owner.
- [ ] CHK13 Hermes correspondence pending.
- [ ] CHK14 ZigVM integration pending.
- [ ] CHK15 inference unexercised.
- [ ] CHK16 new traces pending.
</details>
<details><summary>Domain5 - Governance</summary>
- [ ] CHK17 new independent scope/runtime approvals pending.
- [x] CHK18 standalone JJ.
</details>
<details><summary>Domain6 - Provenance</summary>EV94-109 remain NOT_ADMITTED; no new EV number.</details>

[Raw](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261028-0853-controller-editor-isolation-amendment.md) | [Previous](http://nas-1.tail55d152.ts.net:4100/docs/journal/20261028-0815-controller-assessment-bootstrap-plan.md) | [Next tracker](http://nas-1.tail55d152.ts.net:4100/docs/journal/20261028-0303-development-harness-live-tracker.md) | [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: proposed development amendment, not admission.
