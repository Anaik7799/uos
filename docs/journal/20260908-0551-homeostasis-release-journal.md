# 20260908-0551 — Homeostasis release assurance journal

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Runbook](http://nas-1.tail55d152.ts.net:4100/docs/sop/20260908-0551-web-release-sdlc-sre-runbook.md) · [Verification receipt](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260908-0551-homeostasis-release-verification.json) · [Decision summary](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260908-0551-release-decision-and-forecast-review.md)

## 1. Scope & Trigger

The operator requested a robust, documented and tested SDLC/SRE release process, functionally equivalent native OCaml/Mojo tools, no new Bash scripts, truthful OTP/ERTS health, denotational/F Prime design, all17-aspect review, fractal RCA/Jidoka, C3I/Indrajaal source reuse and Tailscale FQDN operation including private staging. New packages must come from Determinate Nix or devenv; Python is permitted if Mojo needs it under the same provisioning rule.

This is scoped side-conversation work. No subagents, existing-agent interaction, board posting or production integration was performed. Own workspace: .uos-workspaces/codex-homeostasis-release-20260908-0551. Canonical plan: uos/homeostasis-release/20260908-0551. Worker: codex-side-homeostasis-release. PREPARE attempt2 covers the isolated candidate and staging evidence. DEPLOY remains outside completed scope.

## 2. Pre-State Assessment

### Runtime and source

Intake source a0679e3ddc6cbe22a2b38bfcabacf28378598b39 was composed with prior homeostasis UI candidate bf136217a93b887c6f8a2f5e52cc2c3e278a5cc6 in an isolated JJ workspace. Conflicting historical UI media were restored to intake bytes; no shared source or main bookmark was rewritten.

Production port4100 was an unmanaged development-launched BEAM process, PID1261131, run1261131-1788827505320531, with no declared source revision. Its endpoint reported OTP29 while its actual runtime was ERTS15.2.7.4. The OTP value came from a default/environment label. Health output elsewhere included fixed healthy model values. Source inspection also left document/file-viewer authorization and private-path containment unresolved.

No exact production rollback artifact was established. A copied moving build directory cannot prove which bytecode an already-running VM loaded. Production replacement therefore remained blocked.

### Ownership, time and tools

Own coordinator session codex-side-homeostasis-release-20260908-0551 was registered locally, with a separate staging runtime lease. This is not a discovered Herdr identity or peer acknowledgement. Existing native Sa-plan and OTP coordinator interfaces were used; the file event store was not migrated to the empty SQLite file. Final effects used PREPARE attempt2 and runtime lease epoch3.

Chrony-backed active-risk checks passed. At06:49:18UTC, absolute offset was0.000384755s with uncertainty0.0169973195s. Logical sequence numbers are not physical-clock offsets. No assertion of wall-clock/Lamport equality is made.

## 3. Execution Detail

### Design and implementation

Added a 12-stage typed release lifecycle using existing UOS FPP domain/interpreter code. Denotation covers ordered receipts, candidate/time/digest validation, no skipping/replay, fold composition, held/recovering/rolled_back and authority separation. Declarative intents have the same observations as direct typed transitions. Official FPP compilation or mathematical certification is not claimed.

Added tools/release_process.ml as the native operational core: bounded argv-only subprocesses, monotonic timeout, process-group cleanup, output limits, actual runtime checks, source-stable builds, complete package inventory, corruption rejection, stage-packet structure validation, fresh compilation/unit tests, browser tests, parity, web startup and TUI. No new Bash script was retained.

Added tools/release_process.mojo with an independent finite prefix model and an equivalent command entrypoint using existing Python stdlib os.execv to the common OCaml core. The old Process.run forwarding attempt failed in the installed environment; exact exit/stdout parity passed after replacement. No Python package was installed.

Changed runtime identity to observe erlang:system_info directly and reject incoherent OTP29/ERTS17, process/run identity or timestamp tuples. Invalid BEAM counters become unavailable. Real GUI/TUI/API/SSE continue to label unsupported physiological/health measurements UNKNOWN rather than inventing data.

Expanded native browser checks from homeostasis interactions to eight rendered routes, actual runtime identity and unavailable fixtures. Browser navigation and launcher arguments require the Tailscale FQDN; private ports resolve locally. Browser requests to outside host names are refused. The startup banner now uses the actual configured port and Tailnet FQDN.

### Packages and source review

Added ops/release/flake.nix and lock pinned to nixpkgs c25784012c9982bca5b3e0de87e90bbdac8927d3. Determinate Nix provisioned compiler/linker, curl/library/development outputs, pkg-config and zlib. An omitted libcurl output was caught before browser verification and fixed. Final native browser compilation used /nix/store/6qdx3qvjidcdwjdjyanl5fawv48j1nyr-uos-release-checker-dependencies. Existing OCaml/Mojo/BEAM/browser tools are explicit prerequisites; this profile is not a complete bare-host bootstrap.

Initial Nix dependency fetching preceded the strengthened FQDN-only direction. Subsequent provisioning was offline from pinned cached inputs. New uncached operations require a Tailnet package mirror under the current SOP. Existing Mojo execution uses Pixi --no-install --frozen; no new Pixi environment or lock mutation.

Read C3I/Indrajaal files on vm-1.tail55d152.ts.net and compared three exact hashes with local source copies. Adapted route matrices, navigation, SSE and release-testing concepts. Did not copy unvetted external code or claim upstream tests had run. Source review found weak body-exists/version-string/greeting checks and a skipped assertion branch; new checks use actual runtime and browser observations. Phoenix release/runtime configuration, explicit migrations and initial/connected UI testing informed the procedure.

### Private execution and recovery

Built five native artifact revisions without overwriting release directories. Final package c0480a3a91323e4819e0d7e5c3eb7a1249565728 contains3523 inventoried files and built in46.77354303s. Its complete manifest digest is in the machine receipt. Later changes are documentation/evidence only.

An explicitly owned backup was killed and restarted; primary run identity stayed unchanged during that bounded restart check. Private A/B/A artifact restoration observed v1, then v2, then restored v1. Stopped transient units disappeared and had to be recreated from their saved launch definitions before restoration verified.

The earlier primary later restarted because RuntimeMaxSec plus Restart=on-failure treats timeout as a restartable failure. Therefore no uninterrupted-primary claim is made across the entire staging period. Final canaries use Restart=no with RuntimeMaxSec600. The final v5 canary had runtime PID2020861, run2020861-1788850173980473, actual OTP29/ERTS17.0.6 and zero restarts.

At06:56UTC, own v5 unit was stopped after a fresh heartbeat/epoch check. It was inactive/dead with no listeners on owned ports59457/59458. Production PID/run and the separate existing mesh process were preserved.

## 4. Root Cause Analysis

| Symptom | Established cause / evidence | Repair and limit |
|---|---|---|
| OTP29 paired with ERTS15 | Version label came from configuration/default, not VM | Observe actual system_info; coherence tests; production still old |
| Green-looking unavailable physiology | Model/static values confused with measured health | Shared attributed samples and UNKNOWN; no application-health sensor invented |
| Mojo launch lost arguments | Observed Process.run dynamic forwarding failure | stdlib execv with explicit argv; parity and actual web/TUI execution |
| Nix browser link failed | curl package output set omitted required shared library | Explicit lib output and Nix rpath; final compilation/browser passed |
| Browser filter hung | Synchronous route callback awaited protocol work on its own dispatch path | Asynchronous Eio fiber; bounded final browser check passed |
| Time cap restarted canary | Restart=on-failure includes RuntimeMaxSec timeout | Restart=no on final bounded canaries |
| Restoring stopped unit failed | systemd transient-unit garbage collection | Recreate saved definition, then check restored candidate |
| Cleanup fence refused | Epoch2 lease expired | No dependent effect; acquire epoch3, refresh heartbeat and recheck |

The wider root issue is conflating declarations, component tests and live admission. The repair keeps them separate and retains unknowns. File-viewer containment, exact production rollback and distributed atomic fencing remain unresolved hypotheses/obligations, not repaired findings.

## 5. Fix Taxonomy

Corrective: actual runtime identity, invalid-counter rejection, dynamic startup navigation, Mojo argument forwarding, browser callback and Nix library linkage.

Preventive: bounded process ownership/time/output, complete artifact inventory, source stability, stage ordering, stale/foreign receipt rejection, exact source checks before/after smoke, FQDN-only operational hosts, explicit shutdown.

Detective:84 EUnit tests,113 checker tests,338 model rows,15 frontend cases,69 browser assertions,5 package checks, current clocks/lease checks and private restoration observations.

Governance/documentation: candidate SOP contract, AGENTS reference, manual acceptance card,17-aspect matrix, algebraic atlas mapping, L0–L9 RCA/Jidoka and reviewable forecasting/decision standard.

## 6. Patterns & Anti-Patterns Discovered

Useful patterns: one operational core with independently tested computational model; explicit evidence provenance; coherent runtime identity; private bounded canaries; restored artifact verification; smallest-scope Jidoka stop; deterministic inexpensive checks before broader browser work.

Avoid: trusting requested OTP; treating HTTP200 or literal atlas flags as proofs; calling simulation a live forecast; unlimited restart behavior hidden inside a timeout; assuming transient units persist; equating cooperative leases with atomic OS enforcement; counting repeated/overlapping tests as coverage growth; importing external source without provenance.

## 7. Verification Matrix

| Check | Observed result | Candidate / scope |
|---|---|---|
| Actual OTP spoof test | PASS on installed OTP27 and OTP29; label99 cannot replace real observation | Fixed FFI; final checker parity exercised |
| Scoped Gleam EUnit |84/84 PASS | Final application source; retained unit log |
| Native process/stage/packet checker |113 PASS | Final packaged OCaml and Mojo |
| Finite model agreement |338 rows equal | Gleam/OCaml/Mojo ordered-prefix domain; separate fault/intent tests |
| Frontend command parity |15/15 PASS | Final v5; exact exit/stdout for named cases |
| Package validation/corruption |5 PASS | Own copied artifact; no production mutation |
| Eight route smoke |PASS before and after browser | Same final candidate and run ID |
| Browser semantic/transport/rendered checks |69 PASS | Final v5;320/768/1280, SSE, controls, errors, freshness and real/test separation |
| Real native TUI |PASS | Final packaged Mojo, actual local counters and UNKNOWN health |
| Backup restart / artifact A/B/A |Bounded observations PASS | Earlier v1/v2 artifacts; limitations above |
| Final cleanup |PASS | Own unit inactive, no owned staging listeners |
| Independent/manual/production/full17 gates |BLOCKED or UNRUN | Never inferred from component success |

Key text receipts are retained in docs/evidence/20260908-0551-release. Temporary compiler logs and browser screenshots remain local evidence; their paths and limits are recorded. Earlier30-cycle/video receipts were not regenerated at this final candidate and are not counted as current verification. Whole-monorepo test totals, official Lean/Gospel/Quint/FPP, OTel delivery, multi-node failover, reboot/draining and human acceptance remain unrun in this slice.

## 8. Files Modified

Native tools: tools/release_process.ml, tools/release_process.mojo, tools/validation/homeostasis_browser_check.ml.

Runtime/application: apps/indrajaal_gleam_web/src/uos_web_runtime_ffi.erl; src/indrajaal/runtime_identity.gleam; src/indrajaal_gleam_web.gleam; test/runtime_identity_test.gleam. Gleam control: apps/cepaf_gleam/src/cepaf_gleam/fpp/release_lifecycle.gleam; ha/beam_metrics.gleam; ui/homeostasis_status.gleam; test/release_lifecycle_test.gleam; test/homeostasis_evidence_test.gleam.

Provisioning/policy: ops/release/flake.nix, flake.lock, AGENTS.md, contracts/rules/20260908-0551-release-assurance-sdlc-sre-sop.md.

Documents/evidence: timestamped denotational specification, SDLC/SRE runbook,17-aspect/source review, decision/forecast review, risk JSON, verification JSON, this journal and retained unit/browser/checker/package/model evidence. Earlier homeostasis UI candidate changes are preserved separately in lineage. Native build outputs stay under ignored var/releases; no executable release binaries are admitted to source.

## 9. Architectural Observations

Gleam/OTP is the typed control and UI domain; OCaml is the practical deterministic checking/operations core; Mojo shares that core and retains an independent finite model. This makes functional equivalence concrete without duplicating deployment behavior.

FPP state transitions and test receipts are observational. They do not grant a production lease or authentication authority. The same applies to existing atlas literal verification flags, Rete conclusions and model forecasts. Review found forecast demonstration labels with sample_count0; live calibration cannot be assumed.

The repository now carries the scoped standard, source code, pinned dependency definition and key evidence. A complete fresh-host toolchain bootstrap and canonical artifact publication are remaining work; hardcoded existing tool locations are recorded prerequisites, not hidden installs.

## 10. Remaining Gaps

Priority1 blockers: exact recoverable production artifact/source binding; file/document-viewer authorization and private-path confinement. Production still displays the old OTP label and remains unmanaged/unbound.

Priority2: independent review and canonical integration, target-specific runtime ownership, migration/drain/rollback rehearsal and observed cutover. Human GUI/TUI acceptance has instructions but no human receipt.

Priority3: all pages/components' semantic coverage, current long-capture suite, actual application-health sensors, live forecasting calibration, bounded Rete advisory integration, end-to-end OTel, atomic executor fencing and distributed/reboot/failover evidence.

Full17-aspect compliance is NOT_VERIFIED. No unverified obligation was removed to make a green percentage. The later OpenRouter Gemma4 request has a sanitized bounded review packet; actual dispatch awaits an existing Tailscale gateway address. The configured model is google/gemma-4-31b-it:free; live availability remains unverified and no provider request was made.

Final VCS inspection found an empty .git placeholder in the shared root (no HEAD/config). A strict absence test failed; metadata identifies JJ's internal git_target as git under its own store, and the isolated workspace has no .git. No active Git colocation was found. The placeholder was left unchanged rather than altering shared main-thread VCS state.

## 11. Metrics Summary

Final build:46.774s,3523 files. Scoped tests:84 EUnit;113 checker;338 model rows;15 frontend cases;69 browser assertions;5 package checks. These overlap; no summed total or global coverage percentage.

Final staging: one bounded canary, zero restarts, private ports cleaned. Peer/subagent/model calls:0. New Python installations:0. Existing native tool execution plus Determinate Nix dependency provisioning only. PREPARE prioritization C4×STPA4×FMEA4×dependency4×impact3=768; ordinal judgments and FMEA RPN36 do not imply measured probability or authority.

## 12. STAMP & Constitutional Alignment

Unsafe action constraints cover omitted rollback, wrong target, wrong time and excessive/insufficient duration. Jidoka halted bad prerequisites within owned scope. Sa-plan task attempt and fresh runtime epoch were checked before effects; cooperative limits remain explicit. Standalone JJ isolation preserved mainline and other agents. External VM-1 trees remained read-only. No storage/device operations or secret ingestion occurred.

SC-RELEASE-ASSURANCE-001 binds future reviewed SOP integration to native parity, pinned provisioning, FQDN hosts, truthful health, explicit stage/manual evidence,17-aspect accountability, forecast provenance and scoped closure. Its presence in this candidate does not admit itself.

## 13. Conclusion

Release preparation is built and privately exercised with retained evidence. Sa-plan PREPARE completed at07:06:49UTC (request sa-plan-1788851209967092894); own runtime lease was released at sequence580 and session retired at581. Production update is blocked, and complete-system stability is not claimed. The next work is to resolve the production recovery/security boundaries, obtain independent review and execute target-specific admission checks. The new Gemma advisory request remains pending a compliant gateway address.

Closure caught the repository-wide *.lock ignore rule: the unchanged Nix flake.lock was explicitly tracked with JJ. Its recorded hash equals the file already used by the tested package and provisioned profile. Runtime/tool bytes remain unchanged from c0480a3a91323e4819e0d7e5c3eb7a1249565728; the review commit additionally retains documentation, receipts and that lockfile. No package integrity or independent-admission claim is inferred merely from a bookmark.


<details><summary>Verification checklist — five domains, 18 checkpoints</summary>

| Domain | Checkpoints | Scope |
|---|---|---|
| Metadata and navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Timestamp, full Tailnet links, tags and evidence references |
| Purity and storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | Existing runtimes only; no drive operations |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Scoped test receipts; broader gates remain unverified |
| Runtime and observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | Distinguish actual process observations from simulations |
| Governance and JJ | CHK-17-SOV, CHK-18-JJ | Independent admission outstanding; isolated JJ work |

No row grants a passing global checklist. Consult the revision-bound verification receipt.
</details>
