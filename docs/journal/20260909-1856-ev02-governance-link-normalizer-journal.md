# 20260909-1856 — EV-02 link-locator normalizer follow-up

## 1. Scope & Trigger

Review of the first mapping candidate found that its normalizer replaced any client-surface prefix. The scoped correction narrows it to eight known Tailscale policy-link locator prefixes.

## 2. Pre-State Assessment

`031fda…` preserved two material body HOLDs, but its broad substitution could normalize ordinary prose containing `.agents/rules/`.

## 3. Execution Detail

Candidate `4e3dc68a884d55ce5e73c9cd4be73f4414aeac5a` replaces only `http://nas-1.tail55d152.ts.net:4100/{docs,files}/.<surface>/rules/` locators and retains all other text. Both OCaml verifier selftests include a normative-prose retention control.

## 4. Root Cause Analysis

Surface name replacement was broader than AGY's approved transformation allowlist of client metadata and internal-link locators.

## 5. Fix Taxonomy

This is an allowlist reduction in report-only comparison logic; it does not change policy source bodies.

## 6. Patterns & Anti-Patterns Discovered

Normalize explicit locator syntax, not lexical fragments that could appear in a requirement. Do not add a denial list for arbitrary prose.

## 7. Verification Matrix

The candidate-bound runner records both selftests as pass and actual policy/mapping observations as expected HOLD. All 38 anchors remain present; 36/38 mapped bodies are equal under the narrower normalizer; AUTH and TOOL remain rejected. The sandbox-clock HOLD is preserved at `/tmp/ev02-governance-active-link-normalizer-attempt2-20260909-1855.json`; host-clock active PASS is `/tmp/ev02-governance-active-link-normalizer-escalated-attempt2-20260909-1855.json`.

Evidence-only checklist caveat: timestamp, source binding, bounded validation, and governance limits are recorded. Deployment, UI, runtime implementation, formal two-key closure, and admission checkpoints are `NOT_EXECUTED` or `NOT_GRANTED`; no count is a pass claim.

## 8. Files Modified

Only `policy_surface_gate.ml` and `directive_mapping_gate.ml` changed from the earlier source candidate. This journal and receipts are evidence descendants.

## 9. Architectural Observations

The normalizer now states the permitted relation directly in code. It remains a bounded implementation check rather than authenticated historical provenance.

## 10. Remaining Gaps

The two body differences, missing historical lineage, unmapped shared documents, KM entropy HOLD, independent semantic review, and sovereign admission remain open.

## 11. Metrics Summary

Eight locator prefixes are allowed; all other surface strings are retained. 38 mapping rows and four surfaces are evaluated within 1 MiB per file.

## 12. STAMP & Constitutional Alignment

The revised control fails closed when non-allowlisted material differs and cannot issue admission. EV-93 remains the ceiling.

## 13. Conclusion

This follow-up is ready for independent review with the original evidence preserved. EV-02 remains HOLD and NOT_ADMITTED.
