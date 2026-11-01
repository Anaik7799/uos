# 20261101-2334 — Pi/Argon and Codex FPP/SysML handover

**Created:** 2026-11-01T23:35:34Z.  
**Status:** IN PROGRESS / DEVELOPMENT HANDOVER; no task completion, live cutover or system admission is asserted.  
**Operator instruction:** Finish the remaining FPP/SysML, Gleam, Lean, MCP, Zenoh, messaging and persistence work with Pi using Argon and/or Codex. Minimize AGY token use. The operator has already authorized the full task-scoped development work package.

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zk-adr #zero-muda #tailscale-web

[Execution prompt](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1326-fpp-sysml-autonomous-fractal-execution-prompt.md) · [Dependency preflight SOP](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261101-1344-fpp-sysml-dependency-preflight-sop.md) · [RCA and implementation handoff](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1224-fpp-sysml-fractal-rca-tps-implementation-handoff.md) · [Wave 4 dossier](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261101-1925-wave4-protected28-harness-successor-and-fppsysml-dossier-journal.md) · [Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning) · [This handover](http://nas-1.tail55d152.ts.net:4100/files/docs/handover/20261101-2334-pi-argon-codex-fpp-sysml-handover.md)

These are intended Tailnet locators; live publication and reciprocal KM registration of this handover have not been verified. Knowledge references: [[wiki:20260905-1801-uos-zk-km-corpus-index]] and [[zk:20260905-1801-moc-uos-unified-master]].

## Current ownership and source

- Codex is coordinating and reviewing the original FPP persistence path and the independent mesh-gate findings. A real Pi session using `google/gemini-4-argon` completed a read-only SysML/reference-tool review; it did not obtain an active development grant or implement the slice. Pi explicitly acknowledged this handover in read-only standby, observed at `2026-11-01T23:42:33Z`.
- AGY was asked to hand over its existing Codex-gate result and stop further work on this package. It produced a [handover receipt](http://nas-1.tail55d152.ts.net:4100/files/var/evidence/20261101-2338-agy-fpp4-handover-to-pi-argon-and-codex.json) at `2026-11-01T23:39:15Z`, then released its fpp4 attempt with a [release receipt](http://nas-1.tail55d152.ts.net:4100/files/var/evidence/20261101-2340-fpp4-sa-plan-release-receipt.json). A subsequent Sa-plan observation showed the task `available` and the AGY session `done`. Do not launch duplicate AGY work.
- At the last observation the default Jujutsu parent was `76027c4c12fb55240f0acf1934ae6111405fb678`, with working change `1f0d1539a4262927f5092861a4d0920d98ccc4aa`. The `.codex`, `.gemini`, `.mcp`, `.pi`, FPP/SysML draft documents, grant review and master risk portfolio were already modified or added. Preserve them; re-observe ownership and exact candidate before any effect. The original FPP workspace retains two modified regression files based on `bc09f5d5`; do not overwrite or rebase it blindly.
- The master Sa-plan summary reports 7/7 tasks completed, while its Wave 4 dossier explicitly leaves the FPP/SysML package blocked. After AGY released fpp4, the separate universal FPP actor-mesh plan reports 3/5 completed, one dependency-ready and none executing. However, its risk preflight at `2026-11-01T23:40:40Z` returned `HOLD`: the portfolio still declares fpp4 `executing`, and the requested task was not the first eligible candidate. Refresh the complete source-bound assessment and ordering before a claim. The earlier open-items plan reports 16 tasks: 5 completed, 3 executing, 8 available and 0 dependency-ready. These are point-in-time task states, not proof of current leases or of completed translation, persistence, formal proofs or release.

## Pi/Argon and AGY handover findings

- Pi identified a disjoint two-file SysML slice: `apps/cepaf_gleam/src/cepaf_gleam/fpp/sysml_validator.gleam` and `apps/cepaf_gleam/test/sysml_validator_test.gleam`. Its proposed acceptance covers duplicate IDs/ports, dangling subparts and requirement links, unresolved satisfaction references, port direction and honest verification labels. Nine proposed regressions are present in the original FPP sibling workspace; they are not yet candidate-bound passing tests. The built-in package references `part-zigvm-vfs`, so reference-closure repair must account for that existing model input.
- Pi independently observed its `uos-harness-dev` server disabled, no active Pi task grant, the expired original attempt, the unresolved failed build and absent `cc` profile. Its source and risk analysis is advisory; a label or resolvable ID is not evidence that a requirement was actually verified. After its handover acknowledgement, its displayed session cost was approximately USD 1.50; actual provider billing and accounting scope were not reconciled.
- AGY's handover reports two uncommitted candidate edits in `.uos-workspaces/agy-zlp-v3-20261101` for the Gate v10 source-binding and failed-Zenoh-PUT findings. Preserve them as unverified peer work; do not treat them as landed or tested. The third KM-gate evidence finding remains to be resolved. Re-observe the current fpp4 owner and effect state before a legitimate transfer.
- Codex source-only review of that uncommitted candidate found that `is_canonical_capsule_location` compares the sibling-workspace prefix match with `{0, 40}`, although the literal prefix has 39 bytes; the sibling-root alternative therefore cannot match as written. Add a valid sibling-capsule regression and repair after task ownership transfers. The candidate also accepts a missing `UOS_MCP_EXPECTED_PAYLOAD_SHA256`; a self-consistent manifest alone cannot establish a trusted external identity. Assess the trust boundary and test missing/mismatched anchors explicitly. The symlink checks occur after file reads, so race resistance likewise remains unproven. These are source-review findings, not executed exploits or a final candidate verdict.

## Fresh observations and prioritized blockers

1. **L0/L1 — Fresh authority and unknown effect.** At `2026-11-01T23:34:37Z`, `risk-priority-check --active-check` for original FPP task `IMPLEMENT`, worker `codex-fpp-sysml-20261101`, attempt `1`, returned `HOLD`: expired lease and stale assessment. The private Codex development MCP remains disabled in the observed configuration. The old build result remains `FAILED_OR_UNVERIFIED`, with no verified complete post-effect manifest; do not retry or relabel it without operation-specific reconciliation. The completed one-time bootstrap does not authorize direct development-tool fallback.
2. **L1/L6 — Mesh gate HOLD.** The independent Codex Gate v10 receipt [`var/evidence/20261101-fpp4-codex-sovereign-audit.json`](http://nas-1.tail55d152.ts.net:4100/files/var/evidence/20261101-fpp4-codex-sovereign-audit.json) reports `HOLD` for `76027c4c`: the candidate/source manifest binding accepts substituted identities, `tools/uos-core-evo` can succeed when Zenoh PUT fails, and the host receipt lacks a captured KM gate result/exit. It reports 30 EUnit passes and actor-recovery observations within that review scope; those do not clear the blockers. Preserve the receipt and keep the candidate off live cutover.
3. **L2 — Toolchain.** A standard, non-`--full` preflight at `2026-11-01T23:37:55Z`, run with `TMPDIR=/home/an/NAS-setup/uos/var/harness`, returned 31/31 PASS, including erlc artifact, escript and Z3 `sat`; its [structured observation](http://nas-1.tail55d152.ts.net:4100/files/var/harness/20261101-2347-fpp-sysml-preflight-observation.json) binds the checker, resolver and observed working revision `3017e8659a9e89f623e01ab189bc787b02f938f8`. This is a new observation in a different scratch environment and does not explain the older failures conclusively. It does not test or provision `toolchains/nix-profile/bin/cc`, which remained absent. A GCC wrapper exists in the Nix store; qualify and expose the actual pinned closure in an authorized task. FPP and SysML reference executables were not found on the observed PATH; select real upstream tool interfaces and pin their transitive dependencies.
4. **L3/L4 — FPP and SysML semantics.** Current `apps/cepaf_gleam/src/cepaf_gleam/fpp/prm_db.gleam:73` sends `Ok(count)` from in-memory state without an observed durable commit. Current FPP actor initialization can discard an initialization error, and the SysML validator lacks some duplicate, dangling-reference and direction checks. Regression files in the original FPP sibling workspace exist but have not been observed running against the current candidate. A 40-actor FPP mesh is a related source contribution, not evidence of general FPP/SysML translation or parameter durability.
5. **L5/L7 — Messaging and agent endpoints.** The current public `system_zenoh` probe reports reachable REST/TCP endpoints but a stopped subscriber and degraded status. Identify actual owner, authentication and adapters; demonstrate addressed delivery, negative authorization, acknowledgements, idempotency and restart/replay. A public MCP connection or live port alone does not establish a private development grant or working agent control.
6. **L6/L9 — Formal and integration evidence.** Specify supported FPP/SysML dialects and model-to-Gleam-to-Lean mappings, use qualified reference fixtures, pin theorem statements and complete imports, reject untrusted axioms/`sorry`, and replay the Lean kernel. Bind independent review and runtime/formal receipts to the same candidate. Keep all missing or stale evidence nonpassing.

## Next work in dependency order

1. Use the actual Gleam harness and Sa-plan to establish an eligible, independently reviewed, per-worker development route and task grant for Pi and/or Codex. Refresh the complete risk portfolio, reclaim or establish a separately scoped non-replay task, and verify identity, attempt, lease, workspace, source revision and effect-time fence. Existing user authorization is already recorded; do not ask the user to grant it again.
2. In a disjoint, authorized candidate, fix the Gate v10 blockers. Recompute the candidate using the same canonical release-manifest serialization as `tools/ecology_release.ml`, and bind it to an independently trusted expected candidate; a self-consistent attacker-controlled manifest is not a trust anchor. Add tamper tests for substituted candidate/source hashes. Make the required Zenoh PUT part of the CLI success condition and add a failed-PUT test. Capture full KM gate exit status, output and candidate binding rather than a tail alone.
3. Qualify the pinned compiler and official FPP/SysML reference toolchains, their versions, source provenance, licenses and complete dependencies. Observe a real C/esqlite cold build in a bounded authorized workspace.
4. Preserve the existing negative regressions. First make unsupported parameter persistence fail closed; then implement a supervised durable owner with commit-before-ack, idempotency, readback, restart and crash-before/after-commit tests. In parallel only when disjoint and authorized, implement SysML model validation and supported translation fixtures.
5. Connect supported model semantics to Gleam and Lean, then to the actual MCP/Zenoh and persistence boundaries. Test valid/invalid and unsupported models, per-agent request/result/cancel behavior, authenticated delivery and recovery. Record unsupported constructs explicitly.
6. Serialize Jujutsu integration, run candidate-bound tests and kernel replay, obtain independent Pi/Codex review as applicable, update Sa-plan, journal and KM references, and perform release/cutover only when its separately required authority, state and recovery gates pass. Do not claim completion from the master task count or this handover.

## Fractal FMEA and criticality paths

These are provisional **analyst judgments**, not measured failure probabilities, a refreshed Sa-plan assessment or permission to claim. Occurrence is unknown and represented as the full local 1–5 range; detection values are assumptions to challenge against actual controls. `RPN = S × O × Det`; `F` uses the local severity floor. `C/T/F/Dep/I` are the repository's criticality, STPA exposure, FMEA, dependency and impact factors. Re-score against current evidence before execution.

| Failure mode / relevant layer | S / O / Det | RPN; F | Provisional C/T/F/Dep/I score | Discriminating acceptance |
|---|---|---|---|---|
| Unreconciled effect or stale authority, L0–L1 | 5 / unknown / 4 | 20–100; 5 | 4×4×5×5×4 = 1600 | Original operation-specific outcome or an independently authorized non-replay task; fresh identity and fence. |
| Manifest/candidate false binding, L1/L6/L9 | 5 / unknown / 4 | 20–100; 5 | 4×4×5×4×4 = 1280 | Trusted expected identity plus candidate/source tamper negatives on the selected capsule. |
| Unsupported proof or model semantics, L4/L6/L9 | 5 / unknown / 4 | 20–100; 5 | 4×4×5×4×4 = 1280 | Qualified reference fixtures, exact statements/imports, axiom refusal and kernel replay. |
| Save acknowledged without commit, L3/L4 | 4 / unknown / 4 | 16–80; 4–5 | 4×4×(4–5)×4×4 = 1024–1280 | Commit-before-ack with restart, duplicate and ambiguous-outcome tests. |
| Missing compiler or failed cold build, L2 | 4 / unknown / 2 | 8–40; 4 | 4×3×4×5×4 = 960 | Pinned `cc` and transitive closure pass a real cold build in the target environment. |
| Failed or lost Zenoh delivery reported successful, L5/L7 | 4 / unknown / 4 | 16–80; 4–5 | 3×4×(4–5)×4×4 = 768–960 | Failed-PUT exit, authenticated correlated delivery, disconnect/replay and commit tests. |

The four STPA control-action cases are: omit a required authority or persistence refusal; provide unauthorized action or false success; accept a stale lease or acknowledge before commit; and let an agent/effect continue past its lease or stop before reconciliation. Each implementing task must attach its specific controller, feedback, constraint and negative test.

Authority and safety precede these scores. The first dependency path is fresh risk and a reviewed task grant, followed by separately authorized source/test work; the old failed effect remains held unless independently reconciled. The toolchain/reference path precedes affected cold builds and semantic comparisons. The model, persistence, Lean and messaging branches converge at candidate-bound integration and independent review. Actual durations are unknown, so this is a dependency-critical sequence, not a measured longest-duration schedule. The complete 19-dependency register is in the preflight SOP.

## Comprehensive verification checklist

These checkboxes concern this handover draft and do not assert software completion.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Creation time and prior synchronized-clock observation recorded.
- [ ] CHK-02-TAIL — Verify live publication and byte identity after authorized cutover.
- [x] CHK-03-FRACT — Ten fractal layers tagged and mapped to blockers.
- [ ] CHK-04-KM — Register reciprocal wiki, ZK, inventory and journal references.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Verify candidate dependency exclusions.
- [ ] CHK-06-GRAPH — Verify applicable language and native-kernel boundaries.
- [ ] CHK-07-DRIVE — Verify applicable storage interlocks without affecting protected devices.

</details>
<details><summary>Domain 3 — Tests and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Run applicable C1–C8 checks.
- [ ] CHK-09-MATH — Evaluate applicable mathematical gates.
- [ ] CHK-10-9MOD — Run applicable test modalities.
- [ ] CHK-11-REGR — Bind final regressions to the implementation candidate.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Verify supervision and fencing at the target boundary.
- [ ] CHK-13-HERMES — Verify bounded evidence and analysis.
- [ ] CHK-14-ZIGVM — Verify the deterministic kernel where affected.
- [ ] CHK-15-MAX — Verify inference isolation where affected.
- [ ] CHK-16-OTEL — Bind actual clock and trace evidence.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Complete independent review and any applicable release authority.
- [ ] CHK-18-JJ — Reconcile the final candidate and Sa-plan receipts.

</details>
<details><summary>Domain 6 — Provenance extension</summary>

- [x] Preserve the EV-93 ceiling; EV-94–109 and ADR-071–086 are not admission evidence.
- [ ] Verify final provenance and publication before claiming completion.

</details>

[Previous: dependency preflight SOP](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261101-1344-fpp-sysml-dependency-preflight-sop.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Next: execution prompt](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1326-fpp-sysml-autonomous-fractal-execution-prompt.md).

UOS footer: this handover does not itself grant execution, deployment or system admission.
