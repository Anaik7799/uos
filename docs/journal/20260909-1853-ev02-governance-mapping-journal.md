# 20260909-1853 — EV-02 current directive mapping journal

## 1. Scope & Trigger

The historical EV-02 claim describes 38 directive families across client policy surfaces, but it lacked a directive-to-rule binding. AGY's corrected scoped advice (`AGY_ADVICE_EV_CWD_1833`, session `abe9bd8d`) directed a full-body normalizer with only explicit surface adaptations. This record covers that bounded repair at source candidate `031fda129c2afec809af01fa4eecfc187379c3f2`; it grants no admission.

## 2. Pre-State Assessment

The initial observer found 32 shared Markdown rule files, not 38 files, while `superset.toml` enumerates 38 directives. It held for no directive mapping and for four raw surface drifts. The original 2026-09-05 governing design and implementation-plan paths remain absent from the traced historical lineage, so the state remains `MISSING_HISTORICAL_LINEAGE`.

## 3. Execution Detail

Added a current-dated 38-row proposal mapping each directive ID to one `.claude/rules` file and an exact Markdown heading. Added an OCaml verifier that bounds reads at 1 MiB, checks cardinality, exact ID sets, duplicate IDs, file presence, heading lines, four-surface availability, and equality of complete normalized bodies. Normalization removes only the exact `trigger: always_on` frontmatter and substitutes the four known internal surface prefixes.

## 4. Root Cause Analysis

The former verification criterion confused a historic claim count with a file count and had no machine-checkable relation from every declared directive to a current rule section. Raw byte comparison also falsely treated client frontmatter and self-links as content disagreement.

## 5. Fix Taxonomy

This is a bounded evidence-verifier and current amendment proposal. It does not copy policy bytes, select a policy winner, authenticate historical external sources, modify client policy bodies, or alter the admitted EV ceiling.

## 6. Patterns & Anti-Patterns Discovered

Allowed: named surface headers and client-local link locators. Refused: dropping arbitrary lines, extracting only `MUST` statements, trimming unapproved prose, or inferring semantic equality from matching filenames. A first type-check exposed an incorrect intersection predicate in the new verifier; it was corrected before its selftest and actual observation.

## 7. Verification Matrix

`20260909-1842-ev02-governance-checks.json` binds six native OCaml/realized local gate invocations to `031fda…`: policy and mapping selftests pass; the two actual observations and `km_gate --gate` correctly exit HOLD; `km_gate --ev-selftest` passes. The mapping emits 38 per-ID rows: all anchors exist, 36 bodies normalize equal, and `DIR-AUTH-001` plus `DIR-TOOL-001` remain unequal.

The document-level 18-checkpoint structure is evidence-only here: metadata/timestamp and source binding are recorded; Zero-Muda and storage controls are unchanged; the applicable bounded tests and their negative controls are executed; runtime, deployment, UI navigation, and sovereign governance checkpoints remain `NOT_EXECUTED` or `NOT_GRANTED`. No checklist count is represented as an EV pass.

## 8. Files Modified

`governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json`, `tools/ev02_governance/directive_mapping_gate.ml`, `tools/ev02_governance/policy_surface_gate.ml`, and `tools/ev02_governance/run_checks.ml` form the source candidate. This journal, checks, raw outputs, risk assessment, and evidence binding are descendants only.

## 9. Architectural Observations

The current canonical policy surface is four adapted client views, not a byte-identical archive. A full-body allowlist normalizer is a bounded implementation relation for those views. It is weaker than authenticated source provenance and must stay report-only until independent semantic review.

## 10. Remaining Gaps

`DIR-AUTH-001` and `DIR-TOOL-001` have remaining normalized full-body differences. The 11 shared rule documents absent from the directive map require separate scope interpretation, not a fabricated directive. Historical September 5 lineage, independent semantic review, fresh runtime/formal two-key evidence, and sovereign EV admission are open. KM entropy remains below its floor without relabeling.

## 11. Metrics Summary

38/38 proposed IDs map to existing anchors; 38/38 anchors are present; 36/38 mapped bodies are equal after the narrow normalizer; 2/38 are rejected; 11 shared documents are intentionally reported as unmapped. The active observation at 18:42:15Z passed for attempt 2 while retaining `runtime_admission: NOT_GRANTED`.

## 12. STAMP & Constitutional Alignment

The unsafe control action is reporting policy closure when evidence is missing, malformed, stale, or semantically divergent. The verifier fails closed, preserves rejected observations, bounds resource use, and does not execute policy, runtime, admission, or external-source effects. The EV-93 ceiling remains unchanged.

## 13. Conclusion

The bounded mapping repair is ready for independent review as a HOLD-preserving governance evidence improvement. It does not establish the historic 38-family claim or admit EV-02.
