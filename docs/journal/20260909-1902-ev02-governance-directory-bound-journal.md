# 20260909-1902 — EV-02 directory-bound evidence follow-up

## 1. Scope & Trigger

This follow-up adds the final directory-entry bound requested in review to source `e843465721bce2a1a6b6258c8fff58bc26865abe`.

## 2. Pre-State Assessment

The prior source bounded accepted Markdown rule names but could iterate unlimited ignored directory entries.

## 3. Execution Detail

The verifier now refuses a policy-surface directory after 256 total non-dot entries, in addition to its 64 Markdown-rule limit.

## 4. Root Cause Analysis

Bounding only selected entries left a resource path through arbitrary non-rule names.

## 5. Fix Taxonomy

This is a deterministic OCaml input-resource limit; no policy source, runtime, or admission state changed.

## 6. Patterns & Anti-Patterns Discovered

Bound every iterator, including discarded input, before classifying its values.

## 7. Verification Matrix

The candidate-bound runner records the policy selftest, mapping unit selftest, private valid/duplicate/unknown/traversal/symlink/missing/budget fixtures, expected actual mapping HOLD, KM gate HOLD, and KM EV selftest. Active risk passed at 19:02:10Z under attempt 2.

Evidence-only checklist caveat: metadata, bounded reads, and negative controls are observed; deployment, UI, historical-source authentication, full formal proof, and sovereign admission remain `NOT_EXECUTED` or `NOT_GRANTED`.

## 8. Files Modified

`directive_mapping_gate.ml` contains the new limit; `run_checks.ml` retains its fixture invocation. This journal and receipts are evidence descendants.

## 9. Architectural Observations

The actual canonical `.claude` risk SOP remains a symlink and is correctly held without following it. All 38 directive rows retain explicit semantic-coverage limits.

## 10. Remaining Gaps

Policy symlink ownership, two normalized body differences, absent historical lineage, unsupported directive semantics, KM entropy, independent review, and EV admission remain open.

## 11. Metrics Summary

Limits are 64 rule rows, 256 directory entries, 1 MiB per regular file, and 16 MiB aggregate. No admitted capability count changed.

## 12. STAMP & Constitutional Alignment

The gate fails closed for malformed, excessive, symlinked, or unbound data and retains `NOT_GRANTED` authority.

## 13. Conclusion

The final bounded source is ready for independent review; VERIFY remains executing and EV-02 is not admitted.
