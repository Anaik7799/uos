# 20260909-1859 — EV-02 mapping boundary follow-up

## 1. Scope & Trigger

Root review of `4e3dc68…` found unsafe mapping input and insufficient semantic evidence. This follow-up hardens the bounded OCaml verifier at `51617780380ecadf8535538a074a564d72258b0c`.

## 2. Pre-State Assessment

The earlier verifier parsed an unbounded mapping, traversed from `rule.file`, used unbounded directory listing, followed a canonical policy symlink, and treated anchor presence too strongly.

## 3. Execution Detail

Added closed-schema parsing, duplicate and unknown-key refusal, bounded regular descriptor reads, aggregate accounting, bounded directory enumeration, shared-inventory filename checks, and real private filesystem fixtures.

## 4. Root Cause Analysis

The first verifier was an evidence prototype, not a safe boundary for untrusted mapping input or a proof of directive meaning.

## 5. Fix Taxonomy

The change is fail-closed input validation plus evidence classification. It does not rewrite policy bodies or grant admission.

## 6. Patterns & Anti-Patterns Discovered

Never compose a policy path from a mapping value until it is a known shared basename. Do not use an anchor as a semantic-equivalence proxy.

## 7. Verification Matrix

`mapping_fixture_selftest` executes valid, duplicate-key, unknown-key, traversal, symlink, missing-surface, and aggregate-budget controls in private temporary roots. The actual observer now emits all 38 rows but holds `DIR-GATE-001` because its canonical rule is a symlink. The active observation at 18:59:23Z passed for attempt 2 while retaining `NOT_GRANTED`.

The journal is evidence-only: source integrity and bounded tests are observed; runtime implementation, external provenance, full formal proof, deployment, interactive checklist behavior, and sovereign admission remain unexecuted or not granted.

## 8. Files Modified

`tools/ev02_governance/directive_mapping_gate.ml` and `tools/ev02_governance/run_checks.ml`; this journal, the refreshed risk file, and raw runner outputs are descendants.

## 9. Architectural Observations

`superset.toml` provides uniform classification fields for 37 directives and directive-specific timestamp text only for `DIR-TIME-001`. The output therefore labels 37 rows `UNSUPPORTED_HOLD` and TIME `PARTIAL_HOLD`.

## 10. Remaining Gaps

The policy symlink requires a separately approved canonical regular-file relation. AUTH has an extra Canonical-copy line; TOOL differs only by terminal newline; both remain HOLD under the approved normalization allowlist. Missing historical lineage, KM entropy, independent review, and admission remain open.

## 11. Metrics Summary

Bounds: 64 rules, 1 MiB per regular file, 16 MiB aggregate. Controls: one valid plus six adverse private fixtures. Actual rows: 38, all non-admitting.

## 12. STAMP & Constitutional Alignment

The control rejects unsafe paths and resource exhaustion before data reads, preserves observations, and prevents false governance closure. EV-93 remains the admission ceiling.

## 13. Conclusion

The hardened verifier is ready for independent review. EV-02 remains `HOLD` and `NOT_ADMITTED`.
