# OCaml/Gleam additive test design journal

Document identity timestamp: 2026-09-05T21:42:49Z (UTC). Status: DESIGN REVIEW PENDING; NOT A MIGRATION COMPLETION RECORD.

Tags: `#fractal-l0` `#fractal-l2` `#fractal-l7` `#zk-adr` `#zero-muda`.

[UOS home](http://nas-1.tail55d152.ts.net:4100/) / [Planning](http://nas-1.tail55d152.ts.net:4100/planning) / [Design](../design/20260905-2149-ocaml-gleam-additive-test-design.md) / Journal

Contents: [Scope](#1-scope--trigger), [Baseline](#2-pre-state-assessment), [Execution](#3-execution-detail), [Verification](#7-verification-matrix), [Gaps](#10-remaining-gaps), [Conclusion](#13-conclusion).

## 1. Scope & Trigger

Verbatim current instruction:

> , make all of theocaml tests gleam tests, keep the ocaml tests as-is , do not remove them

The operator confirmed side-by-side Gleam counterparts and explicitly prohibited removing the originals. This overrides the previous assistant suggestion of retiring OCaml tests after parity. Preservation is permanent and includes fixtures, support code, and runners.

## 2. Pre-State Assessment

The UOS tree exists and contains 933 scanned OCaml implementation files. A path-name scan identifies 318 test/support candidates in 16 Hermes modules. This is not a test-case count. Existing Gleam parity modules are present, but the inspected count predicate and mock renderer do not establish complete source-suite coverage.

Stored JJ baseline: commit `22008c49704ab12e809537d0d7a7c43810158fba`, change `xxwnznxwmxkmlkwpnkzyoprxplxpxvso`. Read-only status reported a stored clean working-copy commit; this is not proof that no concurrent source writer exists. Each inventoried source has its own observed SHA-256.

## 3. Execution Detail

Read the governing policies and relevant design, journalling, timestamp, Gleam integration, JJ workspace, and verification skills. Inspected source test cases, Dune declarations, the existing OCaml bridge, and existing Gleam parity implementations. Saved a written additive design and machine-readable candidate inventory.

Created the isolated sparse JJ workspace `/home/an/NAS-setup/.uos-workspaces/ocaml-gleam-tests`. The first workspace command failed because the parent directory was absent. A subsequent command created a workspace but rejected `--ignore-working-copy` before setting its parent. Inspection established that it was an empty root-based workspace; `jj new` then set its parent explicitly to the observed UOS baseline. No source file recovery, reset, or deletion was performed.

The brainstorming workflow requires written-design review before implementation. A review request has been presented. No test package, operation adapter, or counterpart has been implemented at this stage.

## 4. Root Cause Analysis

The source suites exercise production behavior at different boundaries: pure library functions, actual Dream routing, filesystem/process effects, and bounded solver operations. A language-level rewrite therefore needs both equivalent assertions and access to the original boundary. Counting source files or exercising an independently mocked renderer cannot demonstrate that coverage.

## 5. Fix Taxonomy

Design decisions: `ADDITIVE-PRESERVATION` (retain originals), `SOURCE-BOUND-INVENTORY` (path plus digest), `CASE-LEVEL-COVERAGE` (separate files from cases), `REAL-IMPLEMENTATION-BOUNDARY` (raw native outputs, Gleam assertions), and `FAIL-CLOSED-EVIDENCE` (unavailable is not passing). These are planned implementation controls, not claims that executable gates already exist.

## 6. Patterns & Anti-Patterns Discovered

Preserve each original input domain, invalid-input case, runtime boundary, and failure condition. Preserve actual generated vectors when runtimes use different random-number generators. Keep mapping, execution, and verification counts separate. Do not equate a hard-coded `432` predicate, a mock renderer, or a wrapper running the old executable with a completed Gleam counterpart.

## 7. Verification Matrix

| Check | Observed result | Limit |
|---|---|---|
| Source path inventory | 318 unique candidates, 16 modules | Support and nonstandard-suite classification pending |
| Source digests | 318 SHA-256 values captured and rechecked; 318 unchanged, 0 changed | Per-file observation, not atomic snapshot |
| Candidate JSON validation | `jq -e` returned true | Data shape/uniqueness, not test coverage |
| Reserved target paths | 318 unique planned paths | None implemented |
| JJ diff | Exactly three new design/inventory/journal files; no edits or deletions to existing paths | Isolated workspace only |
| Document structure | Exactly 13 journal sections; 18 checklist entries in each Markdown file | Structure, not runtime verification |
| Clock | chrony Normal; system 0.000151538 seconds fast of NTP | Host offset only, not an invented agent-context delta |
| Counterpart tests | UNRUN / NOT IMPLEMENTED | No pass claim |
| Existing OCaml suites | Not executed in this design stage | Existing results not inferred |
| AGY/Claude review | Not performed | No consensus or signoff claim |

<details>
<summary>Domain 1: Metadata, timestamp, and navigation</summary>

- [x] CHK-01-TIME: Required filename prefix from observed UTC clock.
- [x] CHK-02-TAIL: Full Tailnet navigation links included; live publication unverified.
- [x] CHK-03-FRACT: Scope-appropriate fractal tags included.
- [ ] CHK-04-KM: Bidirectional Wiki/ZK publication unverified.

</details>
<details>
<summary>Domain 2: Purity and hardware safety</summary>

- [ ] CHK-05-MUDA: Global dependency/history purity not audited.
- [ ] CHK-06-GRAPH: Vector mathematics not modified or verified.
- [ ] CHK-07-DRIVE: Hardware interlock not exercised; no storage mutation performed.

</details>
<details>
<summary>Domain 3: Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8: UI gold-standard checks not executed.
- [ ] CHK-09-MATH: Mathematical quality metrics not measured.
- [ ] CHK-10-9MOD: Counterparts not implemented or run.
- [ ] CHK-11-REGR: UI regression suite not run.

</details>
<details>
<summary>Domain 4: Languages and observability</summary>

- [ ] CHK-12-GLEAM: New test execution pending.
- [ ] CHK-13-HERMES: Source inventory only; adapter execution pending.
- [ ] CHK-14-ZIGVM: Kernel not changed or verified.
- [ ] CHK-15-MAX: Inference tier not changed or verified.
- [ ] CHK-16-OTEL: Runtime receipt observability pending.

</details>
<details>
<summary>Domain 5: Review and Jujutsu</summary>

- [ ] CHK-17-SOV: Written-design and multi-agent approvals pending.
- [ ] CHK-18-JJ: Isolated JJ workspace exists; full-system admission not evaluated.

</details>

## 8. Files Modified

| New file | Purpose |
|---|---|
| [Additive design](../design/20260905-2149-ocaml-gleam-additive-test-design.md) | Preservation, interfaces, case mapping, gates, delivery order |
| [Candidate inventory](../../governance/testing/ocaml_gleam/20260905-2149-source-candidates.json) | Every candidate path and digest; explicit unimplemented status |
| This journal | Prompt, findings, observed checks, and remaining work |

No existing OCaml source, test, fixture, helper, runner, or production file was edited by this task. Existing Gleam modules and historical documentation were also left unchanged.

## 9. Architectural Observations

```text
OCaml tests (unchanged) ----------> actual OCaml library
                                             ^
Gleam counterparts (planned) --> typed adapter+
             |
             +--> independently evaluated assertions and coverage evidence
```

The existing small C3I OCaml NIF surface does not expose every Hermes production API. The design therefore permits new isolated operation adapters without claiming that native ABI coverage already exists.

## 10. Remaining Gaps

- P1: Written-design review gate precedes implementation under the brainstorming skill.
- P1: Classify source suites, support modules, nonstandard test declarations, and source-case domains.
- P1: Implement the complete parity-algebra pilot, real operation adapters, preservation checks, and failure-sensitive Gleam assertions.
- P1: Complete every remaining module; stateful and solver cases need isolated resources and cancellation tests.
- P2: Integrate revision-bound evidence and documentation navigation after implementation and verification.

## 11. Metrics Summary

318 candidate files recorded; 318 source digests; 16 modules; 0 new Gleam counterparts implemented; 0 new counterparts executed or verified; semantic coverage unknown. No source tests are removed or deprecated. Candidate count must never be reported as individual test count or verified coverage.

## 12. STAMP & Constitutional Alignment

The main hazards are silent coverage loss, tests passing without exercising the real implementation, original-suite destruction, and unsafe native/process execution. The planned controls are permanent preservation, case-level mapping, runtime-boundary checks, fail-closed decoding, bounded isolated workers, and explicit missing-evidence states. None permits mutation of live infrastructure or formal proof bypass.

## 13. Conclusion

The requested change is now specified as additive: all OCaml originals stay intact, while genuine Gleam counterparts are built alongside them. The source inventory and design are review artifacts, not completed migration evidence.

Implementation remains pending written-design approval. The first implementation slice must complete the parity-algebra source suite in full and establish failure-sensitive adapters and preservation checks before the remainder is scaled out.

Previous: [Additive design](../design/20260905-2149-ocaml-gleam-additive-test-design.md). Next: [Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning).

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) | [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) | [ZK](http://nas-1.tail55d152.ts.net:4100/zk)
