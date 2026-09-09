# 20260909-0248 — Codex hook compatibility and activation

#fractal-l0 #fractal-l4 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Source](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0248-codex-hooks-journal.md)

Host observation: **2026-09-09T02:00:48Z**. Chrony: stratum 3, system time 0.000012921 seconds fast, leap status Normal. Prefix uses UTC hour and seconds. Sa-plan: `uos/ecology-hooks/20260909-0146`, task `HOOKS`, worker `codex-ecology-hooks`, attempt **1**; parent `uos/ecology/20260909-0146`. No EV number was minted.

## 1. Scope & Trigger

The operator requested “fix hooks” and authorized delegated ecology implementation. This bounded cycle repairs the UOS Codex policy reminder and activates only its reviewed handler. [Machine receipt](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0248-codex-hooks-receipt.json) and [risk assessment](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0248-codex-hooks-risk.json) record its evidence.

## 2. Pre-State Assessment

Installed `codex-cli 0.153.4` rejected `.codex/hooks.json`: `unknown field uos_control_loop, expected description or hooks`. The project handler was absent from `hooks/list`. Its intended message also claimed Zero-Muda and OTP rules were enforced after only testing for `.jj`. [Original bytes](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0248-codex-hooks-before.json) are preserved with SHA-256 `c101fbad0b4eb14ffef7c5ee7b7000509174fea0abeab2754abecdafc10643ae`.

## 3. Execution Detail

The installed CLI generated its own experimental app-server JSON schemas. A bounded, zero-inference `initialize` / `hooks/list` exchange reproduced the rejection. The candidate replaced the invented wrapper/event with `hooks.SessionStart[].hooks[]`, retained a five-second command timeout and the standalone-workspace presence guard, and emitted valid `hookSpecificOutput.additionalContext` with explicit advisory wording.

The original configuration failed the focused OCaml check; the candidate command returned valid context and exit 0. After approved installation in the protected `.codex` directory, the canonical handler loaded without warnings/errors but initially reported `untrusted`. The root then authorized the necessary single-hook trust registration. Codex's supported `config/value/write` API used `expectedVersion` to preserve concurrent settings; readback reported `enabled=true`, `trustStatus=trusted`. Removing that one new state entry from the returned user configuration restored exact semantic equality with the entire prior user configuration.

## 4. Root Cause Analysis

The hook schema and event had not been checked against the installed loader. The directory-presence guard was also mistaken for runtime policy verification, producing an unsupported enforcement assertion. A trusted project and a trusted hook command are separate Codex states: repairing the schema alone did not establish the latter.

## 5. Fix Taxonomy

Applied schema compatibility repair, truthful advisory context, bounded command validation, and exact-hash trust registration through a version-fenced product API. No policy gate, scheduler, inference service or admission mechanism was added.

## 6. Patterns & Anti-Patterns Discovered

Use the installed runtime's schema and discovery API to verify integration points. Keep the file SHA-256 distinct from Codex's handler `currentHash`; they identify different subjects. Compare all unrelated global settings after a narrow trust write.

The first verifier draft had a Bos result-type compile error, corrected before the successful red/green runs. The temporary candidate directory was omitted by `hooks/list`, so canonical-path discovery was decisive. An initial config-comparison tool expression used unavailable `structuredClone`; JSON cloning corrected the observation without another mutation. Sandbox failure to initialize Codex's local SQLite state was resolved with approved bounded app-server escalation. No failure was counted as a pass.

The closure assessment initially returned HOLD because its confidence field used prose rather than a schema enum. The field was repaired to `analyst_estimate`; the [failed observation](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0248-codex-hooks-risk-hold.json) preserves the rejected value and assessment hash.

## 7. Verification Matrix

| Check | Observed result |
|---|---|
| Installed loader, original file | Expected rejection; project handler absent |
| Focused OCaml verifier, original file | Exit 1, unsupported top-level field |
| Focused OCaml verifier, candidate bytes | Exit 0, valid SessionStart advisory context |
| Candidate-to-installed bytes | Identical SHA-256 `4854b8b2e35ba9b136f294a4a9ac46575e3e0564c6fb869bd804ae284f846ca7` |
| Installed loader, canonical repair | Project handler present; no warnings/errors; timeout 5 seconds |
| Supported trust API and readback | Exact reviewed hash trusted; enabled true; unrelated settings preserved |
| Risk preflight / active checks | PASS with observed chrony clock and exact task attempt; [final active receipt](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0248-codex-hooks-active-check.json) |
| `bash tools/risk-priority-check --all` | PASS: 375 baseline, 32,843 adversarial checks, 32,768 independent DAG scenarios; 39 local package paths |
| Automatic SessionStart event / already-open client reload | UNRUN; loader discovery and direct command execution were observed separately |
| Full-system verification / sovereign admission | NOT_ADMITTED by this cycle |

The canonical seventeen aspects remain scoped explicitly:

| Aspect | This cycle's evidence or limit |
|---|---|
| A01 — Substrate & Hardware Storage Interlock | No disk allocation/wipe operation; hardware interlock execution UNRUN |
| A02 — Standalone Jujutsu Monorepo Discipline | No VCS mutation; exact scoped source hashes bound; immutable JJ candidate not captured |
| A03 — Zero-Muda Purity & Waste Elimination | No package installation or dependency changes; one OCaml verifier and a bounded existing command |
| A04 — Gleam/OTP 29 4-Domain Root Supervisor | No supervisor changes; fleet supervision UNRUN |
| A05 — ZigVM Deterministic Engine & 8 VFS Laws | No engine changes; VFS verification UNRUN |
| A06 — Hermes Formal Evidence, Gospel & Z3 | OCaml command verifier executed; no Gospel/Z3 proof claim |
| A07 — Mathematical Authority & Conservation | Installed schema and behavioral observations; formal proof UNRUN |
| A08 — Biosemiotic Cybernetics & Rocha Cut | Reminder explicitly grants no enforcement or admission; exact trust registration remains a separate authorized operation |
| A09 — Quarantined Modular MAX/Mojo Inference | Zero inference turns and no Python/MAX dispatch in the hook or verifier |
| A10 — Zenoh OoZ & MoZ Mesh Telemetry Backplane | No external peer message or mesh mutation; telemetry tests UNRUN |
| A11 — AG-UI 32-Event SSE Stream Protocol | No AG-UI change; stream verification UNRUN |
| A12 — A2UI 233-Component Declarative Catalog | No UI component change; catalog verification UNRUN |
| A13 — Penta-Stack Multi-Interface Accessibility | Installed CLI app-server loader observed; cross-surface UI conformance UNRUN |
| A14 — Universal Tailscale FQDN Web Navigation | Full FQDN artifact links provided; live delivery UNRUN |
| A15 — Comprehensive Verification Checklist | Eighteen scoped checkpoints below; no fleet conformance claim |
| A16 — Knowledge Management Triad | Receipt, before-state, assessment and journal linked; root ecology wiki/ZK/KM grouping owns cross-corpus publication |
| A17 — Sa-Plan & Bionic Durable Workflows | Exact delegated task and attempt; preflight and active observations; no competing task store |

## 8. Files Modified

| Path | Change |
|---|---|
| `.codex/hooks.json` | Supported SessionStart schema and advisory JSON context |
| `tools/verify_codex_hooks.ml` | Focused bounded configuration/command verifier |
| `docs/journal/20260909-0248-codex-hooks-{journal.md,receipt.json,before.json,risk.json,risk-hold.json,active-check.json}` | Scoped journal, observed receipt, preserved original bytes, source-bound assessment, failed observation and final active check |
| `/home/an/.codex/config.toml` | Only the exact UOS handler's `trusted_hash` added through the Codex config API; unrelated settings semantically preserved |

## 9. Architectural Observations

Hook discovery, command output, trust state, event execution and runtime enforcement are distinct observations. The repair establishes the first three; it must not be cited as policy enforcement, automatic event-execution evidence or proof of autonomous ecology behavior.

## 10. Remaining Gaps

Automatic SessionStart event execution and reload of an already-open client remain UNRUN. The hook is ready for discovery by fresh Codex sessions, as observed through the installed loader. Full system formal evidence, supervisor activation and broader hook/plugin health belong to their separately owned tasks. Root ecology knowledge projections will group this cycle.

## 11. Metrics Summary

One previously rejected project handler is now recognized, enabled and trusted. Its timeout remains five seconds; the direct test adds a one-second kill grace. App-server sessions were bounded to 45 seconds and stopped after use. Zero inference turns, package installs, VCS mutations or unrelated trust changes occurred.

## 12. STAMP & Constitutional Alignment

The final hook-specific assessment records C3 × T4 × F4 × Dep3 × I2 = **288**, class P2 after the bounded repair observations. Original-failure FMEA is S4/O5/Det2, RPN40, F4; these are ordinal assessments, not measured probabilities. All four UCAs are explicit: missing reminder, unsafe/false enforcement context, stale hash/config timing, and overlong startup execution. Controls are installed-loader evidence, advisory wording, a version-fenced trust mutation, settings preservation and time bounds.

Sa-plan remains execution authority. EV admission ceiling remains EV-93; no new EV identifier or whole-system admission claim was made. The original hook bytes are preserved for rollback. Revoke only the newly added trust entry through a fresh version-fenced config operation if rollback is required, preserving concurrent settings.

## 13. Conclusion

The canonical UOS Codex hook now uses a supported SessionStart schema, emits a bounded policy reminder, and is reported enabled/trusted by the installed loader. The original rejection and all verification limits remain recorded. Completion of this bounded repair supplies evidence to the parent ecology task; it does not complete that broader task.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host UTC and chrony observation recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN links provided; live serving UNRUN.
- [x] CHK-03-FRACT — L0/L4 applicability and canonical tags provided.
- [ ] CHK-04-KM — Local evidence linked; parent wiki/ZK/KM grouping pending.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — No packages, barred dependencies or foreign scripting files added by this repair.
- [ ] CHK-06-GRAPH — Runtime graph/NIF verification UNRUN; no graph changes.
- [ ] CHK-07-DRIVE — Hardware interlock tests UNRUN; no storage allocation/wipe operation.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI categories UNRUN; no UI component change.
- [ ] CHK-09-MATH — Four mathematical quality gates UNRUN.
- [ ] CHK-10-9MOD — Focused loader/command checks observed; full nine modalities UNRUN.
- [ ] CHK-11-REGR — Continuous UI regression UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — OTP supervision verification UNRUN.
- [x] CHK-13-HERMES — OCaml verifier executed; no formal or scheduler-enforcement claim.
- [ ] CHK-14-ZIGVM — Engine/VFS verification UNRUN.
- [ ] CHK-15-MAX — Inference verification UNRUN; no inference invoked.
- [ ] CHK-16-OTEL — Runtime telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Independent whole-system admission NOT_ADMITTED.
- [x] CHK-18-JJ — No native Git or other VCS mutation.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV-94..EV-109 remain NOT_ADMITTED. This cycle is identified solely by its Sa-plan task. Full-file SHA-256, installed-binary SHA-256 and Codex handler hash identify their separate evidence subjects; no historical green count substitutes for these observations.

</details>

**Previous:** [Risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · **Next:** [Hook receipt](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0248-codex-hooks-receipt.json)

**UOS footer:** Bounded hook repair; advisory context grants no runtime enforcement or admission.
