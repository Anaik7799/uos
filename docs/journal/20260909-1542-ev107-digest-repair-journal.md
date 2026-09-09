# 20260909-1542 EV107 expected-digest component repair

Observed 2026-09-09T15:55:42Z. #fractal-l0 #fractal-l3 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Source](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/system_engg/gospel_dispatch_contracts.ml)

## 1. Scope & Trigger

Parent PROGRAM delegated only the EV107 ignored expected-digest defect. Separate canonical plan `uos/ev107-digest/20260909`, task `DIGEST`, worker `codex-ev107-digest`. EV107 remains NOT_ADMITTED. No Rete or admission implementation.

## 2. Pre-State Assessment

Base `52e013cfe8c32d6c8d4353c27cfdf0a23f225124`; owned root-held codec workspace epoch2. Only two direct-test callers existed, both passing empty expected strings. Implementation ignored `_expected_digest` and passing reference digest; only primary digest length was checked. Initial inherited risk product mismatch caused HOLD; exact raw S4/O3/Det3, RPN36/F4 and product576 were corrected before PREFLIGHT_PASS15:46:30Z. Superseded manifests and failed receipt are retained, not passing evidence.

## 3. Execution Detail

Canonical claim attempt1 succeeded15:46:50Z; lease until16:46:50Z. ACTIVE_PASS15:47:00Z preceded source implementation. Test-first18-case suite built successfully and produced11 actual expected-refusal failures. Interface semantics were written before implementation. Canonical digest format, exact payload binding and both passing result digests are now checked. Fresh source-bound activePASS15:53:05Z checked6files before final campaign.

## 4. Root Cause Analysis

The expected value was an unused parameter; an output shape check substituted for content equality. The tests passed empty expectations and therefore could not falsify wrong-payload evidence. Unconditional passing-result length also masked reference digest disagreement.

## 5. Fix Taxonomy

Input contract and comparison correctness repair. Public signature unchanged. Empty, uppercase, nonhex and noncanonical digest spellings are refused rather than normalized. Both rejected filters may still agree, but the expected digest must bind their input. Diagnostic time and prose differences remain intentionally irrelevant.

## 6. Patterns & Anti-Patterns Discovered

Exact equality must accompany shape validation. A negative test must observe the designated semantic failure after successful compilation. The first native campaign correctly exposed baseline primary digest acceptance but its harness initially expected exit1 for an uncaught OCaml Failure; observed exit2 was preserved and the expectation corrected. No compilation error was credited as a semantic falsifier.

## 7. Verification Matrix

| Check | Actual observation |
|---|---|
| Immutable candidate direct suite |18 cases PASS|
| Same18 acceptance cases against immutable base |11 designated failures,7 passing cases|
| Primary digest disagreement |Compiled base accepts (designated Failure/exit2); candidate refuses|
| Reference digest disagreement |Compiled base accepts (designated Failure/exit2); candidate refuses|
| Rejection-code disagreement |Base and candidate both refuse|
| Passing/rejected verdict disagreement |Base and candidate both refuse|
| Native staged campaign |10 compiled variants,10 normal runtime outcomes matched exactly|
| Source/tool/recipe/executable/receipt bindings |Rehashed after campaign; exact staged source and generated probe bytes retained|
| Formal/runtime/admission |No solver, live dispatch, runtime admission or sovereign approval performed|

## 8. Files Modified

`engines/hermes/modules/system_engg/gospel_dispatch_contracts.ml`, `.mli`, `test_gospel_dispatch_contracts.ml`; native helper `tools/test_ev107_digest.ml`. Timestamped risk, receipt and journal evidence accompany these4codefiles. No Dune production stanza change or new dependency.

## 9. Architectural Observations

The native helper stages exact full `commit_id` bytes using pinned JJ, compiles a private three-file Dune executable and generates fixed disagreement probes. Production still calls its two original local filters. Their SQL detector and SHA implementation are shared, so parity is neither independently authenticated evidence nor proof of those helpers. Existing module-guide global ops verification/mutation commands were not invoked: parent expressly scoped this repair to isolated native Dune and designated compiled mutation controls. This bounded substitution grants no broader module verification.

## 10. Remaining Gaps

No Z3/Gospel invocation, no Rete chaining repair, no authenticated oracle producer, no deployment or EV107 admission. Broad payload-size/time bounds of the existing public filter are outside this comparison repair. Dune and native child invocation are bounded by the observed adapter; local filesystem responsiveness is assumed. The eight dependency hashes are post-execution observations, not before/after immutability proof or full native linker closure. Independent component review is pending. Parent controls completion and integration.

## 11. Metrics Summary

Source candidate `11eeca9df5c14961ed4b4b8fc990752ad7bccd46`.18 positive cases;11 baseline refusal failures;4 disagreement pairs;10 fresh native compilations and executions in final campaign. Original4test entrypoints retained, with valid expected hashes supplied. Exact count denotes test cases, not independent formal properties. Shared parent source and previous completed recipe evidence were not rewritten.

## 12. STAMP & Constitutional Alignment

Not-provided: require missing digest checks. Unsafe-provided: refuse wrong expected/result digests. Wrong-timing: bind immutable candidate and current task attempt. Excess duration: bounded native children and capture. P1, C4×T4×F4×Dep3×I3=576; analyst judgment, not system admission. Canonical Sa-plan remains sole task authority; report-only parity never grants effects. EV94–109 remain NOT_ADMITTED.

## 13. Conclusion

Bounded implementation and native component controls are green at the named source candidate. DIGEST remains executing for independent review; no final task completion or sovereign admission is asserted.

<details><summary>18-checkpoint verification boundary</summary>

| Domain | Checkpoints | Scope status |
|---|---|---|
| Metadata/navigation |CHK01 time,02 FQDN,03 fractal,04 KM|Timestamp and references recorded; live delivery unverified|
| Purity/storage |CHK05 exclusion,06 language,07 drive|OCaml-only scoped change; no storage effect; fleet audit unrun|
| Testing/math |CHK08 C1–C8,09 math,10 modalities,11 regression|Named native controls only; full matrix unrun|
| Cross-language/observability |CHK12 Gleam,13 Hermes,14 ZigVM,15 MAX,16 OTel|Hermes component executed; other domains not claimed|
| Governance/JJ |CHK17 sovereign,18 JJ|Review pending; standalone JJ source pinned|

</details>

UOS footer: component evidence only; admitted ceiling remains EV93.
