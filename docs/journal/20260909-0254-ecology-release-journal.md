# 20260909-0254 — Immutable ecology release packaging

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l7 #fractal-l8 #zk-adr #zero-muda #tailscale-web

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0254-ecology-release-receipt.json) · [Risk](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0254-ecology-release-risk.json) · [Manifest](http://nas-1.tail55d152.ts.net:4100/files/var/releases/ecology/20260909-0256-3eca9188251a0975349de9c9da456dcb408e62242e86d99f75c8bbb1300652fc/release-manifest.json)

Generated from host observations at 2026-09-09T02:38:11Z. Clock: chrony stratum3, normal leap status; system offset 0.000248185 seconds fast at 02:33:54Z. Task uos/ecology-release/20260909-0243 / PACKAGE, worker codex-ecology-release, attempt1. This is package evidence; application_admitted=false.

## 1. Scope & Trigger

The parent delegated reproducible staging of the ecology runtime while it completed capability and service implementation. This worker owns the OCaml package helper, equivalent native Mojo command, their checks, and this receipt. Runtime selection, service startup, systemd, VCS integration and admission belong to separate root-owned gates.

## 2. Pre-State Assessment

The existing release helper was read-only reference: its external OCaml path and unavailable hardcoded OTP location could not identify the current repository toolchains. Core and web development builds also carried independently compiled duplicate modules; even matching package versions can differ in source-path metadata. The final package therefore uses the entire final web build closure, including that build's Cepaf dependency.

## 3. Execution Detail

The helper captures source and test inputs, copies only BEAM/application artifacts, explicitly listed public static assets, the process guardian and MAX worker, then rechecks source hashes. It records explicit realized OCaml, Pixi, OTP, MAX metadata and Python locators; no environment tree or model weights are copied. It probes actual OTP/ERTS, checks application dependencies and listed modules, writes sorted SHA256 inventories, freezes files/directories to read-only permissions and renames the private stage without overwriting releases.

The Mojo facade uses native execl with bounded argv and shares all validation/effects with OCaml. It imports no Python and creates no shell command. Its C-string API was checked against [Modular's official FFI documentation](https://mojolang.static.modular.com/docs/manual/c-ffi/) and the actual installed Mojo1.0.0 compiler. Successful commands preserve the OCaml output and exit code.

## 4. Root Cause Analysis

L4 packaging needed a fixed artifact boundary before autonomous runtime startup. L5 verification previously lacked ecology-specific inventory and realized dependency evidence. L7 merging independently built trees would have produced an untested mixture. Containment is one web closure plus exact source/artifact hashes; changed, missing, extra or unsupported entries abort verification before any runtime probe. L8 risk refresh initially supplied the invalid state string in_progress; HOLD/RP-INVALID was retained, the actual Sa-plan executing state was observed, and a fresh active check passed before staging.

## 5. Fix Taxonomy

New bounded packaging and verification commands; no mutation of the prior release helper, application source, toolchain installation or service configuration. Candidate identity is a canonical manifest hash, while the receipt also binds the exact serialized manifest bytes. Permission freezing and later verification detect ordinary drift; they are not signed provenance or hostile-host confinement.

## 6. Patterns & Anti-Patterns Discovered

Preserve coherent build closures and original .app descriptors, including the tests present in a dev build. Derive runtime identity from the real VM rather than version labels. Verify manifest identity, exact files and dependency hashes before executing a probe. Avoid importing entire priv, .pixi, cache, database or journal trees. The dedicated ecology listener is the intended entrypoint; the general repository-file viewer is outside this release's exposure scope.

## 7. Verification Matrix

| Observation | Result | Boundary |
|---|---|---|
| OCaml selftest | PASS17 | Traversal, absolute/newline paths, stable JSON/inventory, missing/extra/changed files, symlinks, missing/changed dependencies, direct verifier faults, unexpected empty directory, manifest byte tampering and admission refusal |
| Native Mojo selftest | PASS17 | Same shared operational core; no external subprocesses in test fixtures |
| Empty environment plus PATH/LANG | PASS | OCaml selftest, real stage and published verification without HOME/OPAM environment |
| Published OCaml/Mojo verify | PASS; JSON equal | Exact files/permissions, dependency hashes, actual OTP/ERTS and packaged .app/module closure |
| Actual VM | OTP29 / ERTS17.0.5 | Realized repository Nix OTP29.0.5 locator |
| Risk lifecycle | Preflight PASS; final active PASS | Current PACKAGE attempt1; assessment grants no effect authority |
| Supervision build/test observations | Parent team reports core66 and web5 tests PASS | Exact logs listed in receipt; additional source-to-build validation owned by root |
| Runtime service, recovery, browser, formal proof, human acceptance | Separate gates | No pass or admission inferred from package success |

Mojo reported Crashpad socket initialization unavailable inside the sandbox; compilation and command execution nevertheless exited0. No retry or installation was needed.

## 8. Files Modified

Added tools/ecology_release.ml (SHA256 fd6a9f5463db99c0aa6292903bed979830a90aab243f44f2f4132e1dfa3bffd3) and tools/ecology_release.mojo (SHA256 063d03d32b7d833dd5b19471f211518a98ffb36b8469cc029433bf2afbc01231), plus this timestamped journal, risk inputs, checks and receipt. Created var/releases/ecology/20260909-0256-3eca9188251a0975349de9c9da456dcb408e62242e86d99f75c8bbb1300652fc with1116 inventory entries. The guardian and MAX worker are immutable package copies of root-owned source; their source files were not edited here.

## 9. Architectural Observations

Package denotes SourceSnapshot × RealizedDependencies → Result(CandidateDirectory). Identical canonical inputs produce identical candidate hashes; a changed input must change the candidate or stop the operation. Verify denotes CandidateDirectory → Result(Identity), with no deployment authority. The source manifest includes tests without exporting their source. Source-to-build correspondence remains a separate build receipt, and the existing MAX library environment remains an explicit external dependency.

## 10. Remaining Gaps

The release is a dev artifact. Owner-writable permissions can be restored by that owner; hostile same-UID races and signed provenance are not solved. The external MAX environment's complete library closure is not hashed here. Operational resource-envelope owner injection is unavailable, so the local df budget check does not claim harness enforcement. Parent-owned runtime, recovery, formal, UI and independent admission evidence remains necessary. Grouped wiki/ZK/KM indexing is owned by root; workspace links do not establish live publication.

## 11. Metrics Summary

1116 manifest entries;27,091,636 copied payload bytes; source manifest includes 2477 inputs. Per-operation120seconds, subprocess20seconds/1MiB, two BEAM schedulers, file128MiB, aggregate512MiB and20,000-file limits. Disk check requires20percent additional room and512MiB remaining. Risk is ordinal P1/768 with C4×T4×F4×Dep4×I3 and raw FMEA S4/O3/Det3/RPN36; no measured probability is asserted.

## 12. STAMP & Constitutional Alignment

All four UCA types are recorded in the risk artifact: omitted validation, unsafe artifact acceptance, stale timing, and excessive duration. Sa-plan remains the execution authority. No EV number, external plugin admission, VCS mutation, production replacement or global conformance claim was issued.

| Aspect | Scoped status / remaining obligation |
|---|---|
| A01 Storage | Private release directory only; no device operations |
| A02 Jujutsu | No VCS mutation by this worker; root integration separate |
| A03 Zero-Muda | Allowlisted runtime files, no installation; global audit unrun |
| A04 OTP supervision | Actual OTP/ERTS observed; live supervision evidence separate |
| A05 ZigVM/VFS | Symlink refusal tested; descriptor-relative/hostile-race proof unrun |
| A06 Hermes/formal evidence | Native OCaml/Cryptokit checks; Gospel/Z3 proof unrun |
| A07 Mathematical authority | Canonicalization/identity laws checked; proof unrun |
| A08 Cybernetic authority | Package and model outputs grant no effect authority |
| A09 MAX/Mojo | Native facade executed; existing inference environment referenced |
| A10 Zenoh | No mesh changes or new delivery claim |
| A11 AG-UI SSE | Runtime transport verification separate |
| A12 A2UI | No component changes by this worker |
| A13 Accessibility | Browser and accessibility acceptance separate |
| A14 Tailscale | Canonical links provided; listener operation owned by root |
| A15 Checklist |18checkpoint structure below; no global passing claim |
| A16 KM triad | Journal/receipt delivered for root grouping and indexing |
| A17 Sa-plan | PACKAGE attempt1 and fresh observations; workflow recovery separate |

## 13. Conclusion

The immutable ecology package is staged and verified through both native command surfaces. Its exact candidate, source and runtime dependency identities are available for root-owned startup and recovery checks. Application admission remains false.

<details><summary>Verification checklist — five domains,18 checkpoints</summary>

| Domain | Checkpoints | Scope |
|---|---|---|
| Metadata/navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Host time, links, tags and root grouping references |
| Purity/storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | No prohibited dependency added or device operation; global checks unrun |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Bounded negative tests and real package verification; formal/global gates unrun |
| Runtime/observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | Actual OTP identity; other runtime evidence separately owned |
| Governance/JJ | CHK-17-SOV, CHK-18-JJ | No admission or VCS mutation by this worker |

</details>
