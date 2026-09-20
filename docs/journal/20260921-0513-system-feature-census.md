# 20260921-0513 — Compiled census and lossless bounded transport

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

**UOS / Journal / Feature inventory** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Created: 2026-09-21T06:18:24Z; prefix preserves workflow origin at 2026-09-21T05:33:13Z. **DEVELOPMENT CHECKPOINT; t1 INCOMPLETE; NOT_ADMITTED.**
[Census](http://nas-1.tail55d152.ts.net:4100/files/governance/capability-inventory/20260921-0513-system-feature-census.json) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260921-0513-system-feature-census-evidence.json) · [Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20260920-1438-hive-swarm-mcp-recovery-plan.md) · [Risk](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260921-0338-execution-optimization-risk.json)

## 1. Scope & Trigger

Continue universal MCP and DB coverage through Sa-plan t1-tracker, attempt1, worker codex-01a0ba74-feature-tracker. Workflow uos/system-mcp-features/20260919-1642/t1-census/20260921-0513 records scoped development evidence. Pure Gleam extraction covers seven existing compiled declaration sources without probing or starting services. Private persistence exposed Unicode corruption; regression investigation exposed two native lifecycle defects. No production import, deployment, identity enrollment, coordinator repair, package installation or VCS mutation.

## 2. Pre-State Assessment

Prior ingestion conserved98 records from two raw JSON arrays. Larger compiled catalogs remained unprocessed; the catalog limit128 could not represent239 A2UI records in one shard. Runtime availability, authenticated source/build identity and global completeness remained unknown. Canonical dashboard had2/20completed,1executing,17blocked. Kalman state prior is qualitative uncertainty, not a fitted forecast model.

## 3. Execution Detail

Pinned exact source bodies, app dependency lockfile and independently observed raw ID-set fingerprints. Compiled adapters yield55MCP tool definitions,26supervision declarations,11ecology capability declarations,75autonomous claims,167visualization metadata entries,145knowledge claims and239A2UI tuples. Deterministic128-record shards preserve every selected identity. Together with98raw records, this is816declarations across9source sets and12catalog shards—not816distinct working capabilities.

MCP input schemas are actually declared and hashed; output/refusal schemas and effects remain unknown. Empty mappings are unmapped, not absent. Raw maturity labels remain Declaration values; authors are not inferred as owners. Normalized endpoint compatibility is checked globally across shards. A source/path/hash match cannot authenticate the loaded compiler output.

An actual55-record private Sa-plan roundtrip initially failed because Erlang binary_to_list caused UTF8 bytes to be encoded again at the OS argv boundary. Strict Unicode decoding now preserves exact characters and rejects malformed/incomplete input before spawning. The private corrupted fixture remains evidence, not silently repaired.

After a full-suite guardian125 failure, a child that closes output then sleeps50ms and exits7 reproduced premature SIGKILL. Linux-only bounded procfs inspection now waits for the owned unreaped child to become a zombie while the original timer remains armed, then cleans its process group before reaping. A reviewer found the later exception-after-reap window; monotonic group-cleaned state now forbids further numeric-PID kills before either waitpid path. Cleanup masks handled signals and retains idempotent reaping. Repeated descriptor close ignores only EBADF; fault tests require an injection-reached marker and prove no subsequent kill attempt.

## 4. Root Cause Analysis

| ACH hypothesis | Diagnostic evidence | Disconfirmation |
|---|---|---|
| H1: Per-shard validation proves global compatibility | Conflicting endpoint declarations in shards1and2 passed before the new guard | Disconfirmed; targeted RED then GREEN |
| H2: Sa-plan storage changes Unicode | Minimal pinned printf reproduced mojibake before any DB call | Disconfirmed; argv facade was responsible |
| H3: EOF proves process termination | Closed-output exit7 failed125 while open-output exit7 passed | Disconfirmed; EOF is a pipe condition |
| H4: Kill-before-wait alone prevents all reuse races | Private after-reap exception injection recorded another kill attempt | Disconfirmed; monotonic cleanup state required |
| H5: The named full-suite failure is conclusively traced to early EOF | No syscall trace of that exact invocation exists | Unresolved attribution; reproduced defect is real but inference is qualified |

The two older unidentified full-suite failures remain unexplained. Later green results do not erase them or prove these repairs caused them.

## 5. Fix Taxonomy

Poka-Yoke: exact raw identities, source bounds, normalized global endpoint consistency, explicit unknown metadata and strict UTF8. Jidoka: missing process-state evidence refuses; authority fences still prevent canonical import and deployment. Muda reduction: reuse pure registries, existing bounded process guardian and Sa-plan storage instead of another scheduler, database or unbounded scanner.

## 6. Patterns & Anti-Patterns Discovered

Conservation of source records is not semantic deduplication. A declaration count is not service startup evidence: the root spec declares26children while inspected startup wires only5. App manifest.toml files are dependency lockfiles, not runtime inventories. Visualization catalogs are metadata, not167renderers; knowledge claims are not145admissions.

Devil's Advocate and Popperian falsification cover missing/changed/duplicate source bytes, wrong ID counts/fingerprints, collisions, cross-shard schema/effect conflicts, known edges crossing unsupported shard boundaries, malformed UTF8, shell-text literals, early EOF, deadlines, signals, overflow and surviving descendants. Private fault injection intercepts post-reap kills into a marker rather than risking a reused PID.

## 7. Verification Matrix

Admiralty B2 denotes local development observations corroborated by separate source review, not sovereign operational certification.

| Check | Observed result | Boundary |
|---|---|---|
| Census initial RED |6failed/2passed|Before extraction implementation|
| Cross-shard conflict RED |1failed/8passed|Before global endpoint guard|
| Census plus core |29/0|Pure development|
| Actual55MCP persistence |Initial readback conflict; after UTF8 repair PASS31.259s|Private DB only|
| UTF8 boundary RED |3failed/1passed|Malformed input and byte preservation|
| Initial full regression |11955passed/1failed, guardian125|Failure log retained|
| Early-EOF controls RED |2failed/1passed|Exit7 and timeout distinguished from EOF|
| Intermediate full regression |11964/0|EOF-only candidate, before final cleanup changes|
| Intermediate state-split full regression |11965/0|Before final descriptor cleanup correction|
| Post-reap fault RED |Unsafe-kill marker observed|Private instrumented copy, no unsafe kill performed|
| Final focused lifecycle/UTF8 |23/0:10lifecycle,4UTF8,9census|Development, not cgroup/PID-reuse stress|
| Final full regression |11966/0, exit0;240second bound|Candidate-bound local execution|
| Connected MCP census read |PASS223835bytes; exact candidate confirmed|Artifact read only, not tracker endpoint or import|
| Release / actual peer workflow / canonical import |NOT_PERFORMED|No admission|

Independent read-only reviewer observations are advisory and are not Claude/AGY sovereign ACKs. No runtime reloading occurred. A dashboard observation command initially failed from shell quoting in Erlang eval; corrected quoting plus pipefail produced the fresh observation. That tooling error is not a system-health result. Initial journal lint missed the explicit falsification vocabulary; the section label is corrected without changing test evidence. Mechanical lint does not execute the seven verification engines.

## 8. Files Modified

New system_feature_census.gleam and census tests bind seven compiled sources and shard them completely. system_features.gleam adds global endpoint compatibility over opaque catalogs. Store tests add actual55MCP persistence. ecology_capability_ffi.erl repairs strict UTF8 argv conversion. ecology_process.ml, its existing fixture and new bounded_process_lifecycle_test.gleam cover EOF, cleanup state and negative controls; bounded_process_utf8_test.gleam covers literal bytes and refusal boundaries.

The census carries exact33source/test/catalog bindings and candidate preimage d913c4475ffe56661fe4b1c9456ca5477d60281da0b203464344a8f69f1ad6c7. Risk, census, evidence, this journal and the human plan are current projections; historical evidence remains preserved. The candidate is a limited working-tree source set, not a JJ commit or whole-repository admission.

## 9. Architectural Observations

Pure Gleam owns catalog semantics; bounded native interpretation remains behind the existing interface. A monotonic cleanup phase is required because an exception can occur after waitpid reaps but before the next assignment. Cleanup ECHILD means no child remains to reap, never successful application exit. Linux zombie state is observational evidence only; unavailable procfs fails closed. See [Linux procfs documentation](https://docs.kernel.org/filesystems/proc.html) and the [OCaml Unix interface](https://ocaml.org/manual/5.5/api/Unix.html); local pinned Unix.mli confirms only WNOHANG/WUNTRACED are exposed.

Category/sheaf consistency and invocation-specific formal proof remain unestablished. No Lean, Gospel or Z3 invocation is claimed for this slice. Seventeen aspect/law identifiers remain obligations rather than verified results.

## 10. Remaining Gaps

Read-only follow-up identifies19finite development-harness and13successor tool declarations with8overlapping names; schemas and server identities must stay distinct. Two legacy dispatch aliases and five vault declarations without direct dispatch branches need reconciliation. Resource/prompt absence is established only within three inspected dispatches, not globally. Finite harness MCP/resource/prompt catalogs, actual dispatch bindings,13MAX wire methods, real app entrypoints/supervision graphs, native ABI, engines, operations and formal/tool surfaces remain a source frontier. Other product arrays and reference-only Hermes catalogs are not silently admitted. Global inventory completeness, trusted build/source provenance, canonical task-scoped import, real MCP discovery/probes and all17aspect evidence remain open.

Guardian scope is Linux procfs and same-session process groups; deliberate new-session escapes require service cgroups. SIGKILL plus blocking reap does not guarantee a hard cleanup bound for uninterruptible kernel tasks. Unrelated legacy Unicode-path conversions remain outside this fix. Sa-plan workflow history is not SQL-level append-only/authenticated; hashes/readback do not manufacture authority.

## 11. Metrics Summary

Nine source sets;816declarations;12complete shards; zero omitted selected IDs;55known input schemas, zero known output/refusal schemas. No semantic feature count or runtime-usable count is inferred. One writer and one read-only reviewer used pinned Gleam1.16.0/OTP29; no paid inference or package provisioning.

Bayesian Beta-Binomial updates over correlated test cases would invent independent field trials. Calibrated posterior, evidence half-life and Lyapunov dV/dt < 0 remain NOT_ESTABLISHED; passing counts are not production stability evidence. Seven journal-engine obligations are documented, not claimed fully executed by mechanical lint.

## 12. STAMP & Constitutional Alignment

UCAs: missing declarations hide gaps; fabricated readiness or wrong-process kills create unsafe effects; stale candidate/lease data misleads timing; unbounded parsing or cleanup outlives authority. Explicit unknowns, exact pins,128-record/4096-total bounds, monotonic process cleanup and effect-time fences address these at their stated scope.

Authority and dependency eligibility precede C×T×F×Dep×I. t1 remains P1,3125; false-coverage FMEA S5/O3/Det4,RPN60 is an analyst estimate, not empirical occurrence. Sa-plan retains all execution authority. EV ceiling93 and EV94..109 NOT_ADMITTED remain unchanged; no new EV. No protected storage action occurred.

## 13. Conclusion

This checkpoint broadens truthful discovery and fixes observed transport defects; it does not complete t1 or the overall goal. At 2026-09-21T06:18:24Z, canonical progress remains **2/20completed,1executing,17blocked,0unknown**. Continue the remaining source frontier and independently authorized import/probes, not unsafe deployment.

Forecast: conditional on unchanged candidate and pinned toolchain, p=0.95 that the first rerun of the final pure census plus bounded lifecycle/UTF8 checks before2026-09-22T06:30:00Z passes. Missing/failed tests falsify it. Outcome and Brier score (p-outcome)^2 remain PENDING; this is an uncalibrated development precommitment.

### Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Observed host/chrony time and workflow-origin prefix.
- [x] CHK-02-TAIL — Full Tailnet references; live webpage serving not inferred from MCP.
- [x] CHK-03-FRACT — L0–L9 applicability retained.
- [x] CHK-04-KM — Plan, census, evidence and journal linked; corpus-wide sync pending.

</details>
<details><summary>Domain 2 — Purity and storage safety</summary>

- [x] CHK-05-MUDA — No package or runtime addition; fleet exclusion audit not rerun.
- [x] CHK-06-GRAPH — Gleam semantics and existing bounded native boundary retained.
- [x] CHK-07-DRIVE — Private fixture effects only; protected storage untouched.

</details>
<details><summary>Domain 3 — Tests and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full-system surface acceptance UNRUN.
- [ ] CHK-09-MATH — Four mathematical gates UNRUN for this candidate.
- [x] CHK-10-9MOD — Scoped unit, negative, property, persistence and fault tests observed.
- [x] CHK-11-REGR — Final result and retained failures in verification matrix.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [ ] CHK-12-GLEAM — Actual production supervision/authority unverified.
- [ ] CHK-13-HERMES — Invocation-specific formal admission pending.
- [ ] CHK-14-ZIGVM — Kernel/VFS acceptance outside this slice.
- [ ] CHK-15-MAX — Inference activation/probes not performed.
- [ ] CHK-16-OTEL — End-to-end data/control trace correlation pending.

</details>
<details><summary>Domain 5 — Governance</summary>

- [ ] CHK-17-SOV — Independent release review/admission pending.
- [x] CHK-18-JJ — Standalone JJ preserved; no VCS mutation.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV ceiling93; EV94..109 NOT_ADMITTED. Source records, test receipts, peer advice and effect authority are distinct.

</details>

[Previous: raw source ingestion](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260921-0540-system-feature-source-ingestion.md) · [Next: canonical plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20260920-1438-hive-swarm-mcp-recovery-plan.md)

UOS footer: development evidence never grants runtime or system admission.
