# Sa-plan help incident containment and generator preservation

Observed: 2026-09-09T06:11:56Z. Source candidate: `32d2770110cd78e50429d8214377c4c02e4cde14`.

#fractal-l0 #fractal-l2 #fractal-l3 #zk-adr #zero-muda #checklist-nav

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki)

## 1. Scope & Trigger

Contain an actual accidental task claim discovered during the EV programme and repair the native CLI. Also repair the independently reproduced generator symlink overwrite. All new implementation and test orchestration use OCaml; generated application code remains Gleam.

## 2. Pre-State Assessment

A delegate invoked `sa-plan task claim --help` expecting usage. The live CLI normalized it to `--claim`, accepted `--help` as a worker identity and claimed the historical default plan's task0. Independently, generator replacement followed a symlink whose target carried the generator marker. No formal or EV admission followed from either operation.

## 3. Execution Detail

The affected stream paused. Root observed the exact historical plan/task, worker`--help`, attempt2, then released that exact unexpired claim through Sa-plan. Fresh readback showed available state, no worker and attempt2 preserved. Root informed the other actual Codex session on coordinator event1279 and resumed the correctly claimed FORMAL task after containment.

The CLI now recognizes exact help controls before format decoding, validates claim worker identity, and handles help/version before resolving or creating the database path. The EV adapter additionally refuses option-style help before starting the unchanged live binary. Generator replacement checks regular-file and inode identity, formats a private temporary file, and publishes with rename for replacement or a non-overwriting hard-link operation for new output.

## 4. Root Cause Analysis

The CLI treated every post-verb token as positional data, including reserved help controls, and optional claim arguments selected a historical default plan. Its main function opened a database even for informational requests, while database path initialization created parents at module startup. Generator replacement opened its target with truncation before formatting and followed symbolic links. A marker identifies format intent but does not prove path ownership.

## 5. Fix Taxonomy

The fixes separate informational control parsing from task effects, defer database initialization, reject malformed claim identity, block the unsafe live invocation shape in the native adapter, and publish formatted generator output without truncating a followed target. No journal or task attempt was rewritten.

## 6. Patterns & Anti-Patterns Discovered

Help is a process behavior that needs a no-side-effect test, not merely a string-normalization example. Invalid format arguments must not consume a help token and expose the underlying effect. A repair requires actual fenced recovery of an accidental claim. Generated-file markers do not make symlink writes safe. Temporary formatting preserves the prior file if formatting fails.

## 7. Verification Matrix

| Observation | Result | Scope |
|---|---|---|
| Actual task recovery |Exact attempt2 released; state available|Canonical Sa-plan, original attempt retained|
| Argument checks |48 assertions passed|Includes six help and six invalid-worker cases|
| Native private CLI |27 checks passed|11 informational shapes against absent/existing stores; claim/release controls|
| Native adapter |7 checks passed|Help refusal before child and prior process/receipt regressions|
| Generator controls |6 passed|New/existing/regular/symlink/directory/unmarked paths|
| Independent final review |Pending|No approval inferred from author results|

The original regression test failed at the help effect-normalization law before the repair. Two private build attempts failed due to the test PATH construction and Core integer-only equality syntax; both were corrected before the successful native execution. Two initial generator test attempts included the previous review's existing runner fixture and correctly hit an occupied-path refusal; the corrected fixture starts without that runner. These private failed artifacts remain preserved.

## 8. Files Modified

Three Sa-plan CLI/test files change help parsing and storage initialization. `tools/test_sa_plan_help.ml` stages and builds the actual CLI with private databases. `tools/ev_native.ml` and its regression file add immediate help refusal. `tools/generate_ev_recovery_runner.ml` changes publication. Timestamped observations preserve task recovery, source binding, actual process receipts and the original generator review.

## 9. Architectural Observations

The canonical live CLI binary remains unchanged; its integration belongs to the current integration owner and needs reviewed source. The isolated native adapter already contains the hazardous help shape for this programme. Informational commands need no database authority. Current generator path checks assume a cooperative checkout and do not establish descriptor-relative safety against a hostile concurrent parent-directory replacement.

## 10. Remaining Gaps

Independent review and integration of the CLI repair remain open. The full claim grammar still supports historical default-plan compatibility; ordinary programme commands therefore use explicit plan/task/worker/lease arguments. The EV98 campaign producer is under review and its formal slice is repairing missing actual implementation relation and solver-witness checks. Full EV runtime and sovereign admission remain open.

## 11. Metrics Summary

One unintended task claim was contained, with its attempt history retained. No historical task was executed or completed. The policy ceiling remainsEV93. PROGRAM, PRODUCER and FORMAL continue under separate authority.

## 12. STAMP & Constitutional Alignment

The unsafe control action was providing a task claim in response to an informational request. Missing help interception, incorrect parsing order, stale/default target selection and an unexpected hour-long lease cover all four UCA classes. Root active risk passed at06:09:08Z for52 source files, assessmentc5f57163. Native process checks use private databases; no direct SQLite edits or live binary replacement occurred. Seventeen assurance aspects are distinguished in the prior combined journal; this incident adds source, authority, storage, recovery and independent-review evidence without promoting unrelated aspects.

## 13. Conclusion

The accidental claim is contained. The private CLI and generator repair candidates pass focused author checks and await independent review. The wider EV programme remains executing.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- [x] CHK-01-TIME — Host-derived timestamp and synchronized active observation recorded.
- [x] CHK-02-TAIL — Full Tailscale links supplied; private evidence publication remains unverified.
- [x] CHK-03-FRACT — Fractal tags supplied.
- [x] CHK-04-KM — Source, evidence and historical scope references supplied.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [ ] CHK-05-MUDA — Full production dependency scan remains required.
- [ ] CHK-06-GRAPH — Real graph execution acceptance remains required.
- [ ] CHK-07-DRIVE — Live storage interlock acceptance remains required.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI acceptance remains required.
- [ ] CHK-09-MATH — Four system mathematical gates remain required.
- [ ] CHK-10-9MOD — Focused suites do not cover every modality.
- [ ] CHK-11-REGR — Full system regression and monitoring remain required.

</details>
<details><summary>Domain 4 — Runtime and observability</summary>

- [ ] CHK-12-GLEAM — Operational supervision and recovery still need evidence.
- [ ] CHK-13-HERMES — Full formal authority and live coordinator cutover remain open.
- [ ] CHK-14-ZIGVM — Current deterministic runtime/VFS acceptance remains required.
- [ ] CHK-15-MAX — Actual supervised inference remains required.
- [ ] CHK-16-OTEL — End-to-end operational traces remain required.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Full sovereign admission has not been granted.
- [x] CHK-18-JJ — Isolated JJ candidates preserved; no native Git mutation.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV94–109 remain NOT_ADMITTED. The scope decision forEV86 follows the primary Raga Durga/22-Shruti/Web Audio journal and AGY's withdrawal of the Acoustic Sheaf addition. Historical claims remain preserved. No board ACK or component count grants admission.

</details>

**Previous:** [SQLite andEV98 stage](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0512-sqlite-verification-and-ev98-repair-journal.md) · **Next:** [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

**UOS footer:** Isolated development evidence; live publication and EV admission not granted.
