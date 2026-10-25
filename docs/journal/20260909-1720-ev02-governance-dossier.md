# EV-02 Governance verification dossier

## 1. Scope & Trigger

Verify the historical EV-02 `INV-GOV-SUPERSET-CLOSURE` statement: 38 policy families admitted from `.gemini`, `.claude`, `.agents`, and `.codex`. This is a bounded evidence slice under Sa-plan `uos/ev02-governance/20260909` task `VERIFY`; it makes no admission decision.

## 2. Pre-State Assessment

The scope inventory and AGY/Codex resolution at immutable root revision `211ba0d423123cc718519a7c95e56104a8fe8e98` label EV-02 `NOT_VERIFIED` and `AGREED_SCOPE_ONLY`. The sealed implementation base has four policy surfaces but no canonical 38-family manifest, original-source snapshot, or two-key EV-02 bundle.

## 3. Execution Detail

Created a bounded OCaml policy-surface observer, rebuilt the already-realized `tools/km_provenance/km_gate.exe`, and executed its gate and EV-law selftest. Raw outputs and argv/exit receipts are bound in `docs/reviews/20260909-1716-ev02-governance-checks.json`.

## 4. Root Cause Analysis

The historical claim provides a count and source-directory labels but no immutable enumeration or source-to-adapted-policy mapping. Therefore file presence cannot prove the claimed closure. The first observer implementation also attempted to read union members from every surface before reporting a missing member; the codex-only `README.md` reproduced that defect.

## 5. Fix Taxonomy

The observer now enumerates each surface independently, bounds names and file bytes, reports missing members before comparison, compares available member bytes, and fails closed unless exactly 38 shared policy families agree. This repairs only the verifier's missing-file handling; it does not synthesize the absent historical manifest.

## 6. Patterns & Anti-Patterns Discovered

Mirrored rule filenames are useful observed configuration, not provenance of the original external policy families. A report-only gate and an internal admission-law selftest are controls against false positive claims; neither authenticates a producer or grants authority.

## 7. Verification Matrix

`policy-surface --selftest` passed complete, missing, count, and divergence controls. Actual observation held: 33 union names, surface counts 32/32/32/33, count and missing-surface failures. `km_gate --gate` held on entropy 1.333 below 2.50 while retaining ceiling 93 and `NOT_GRANTED`; `km_gate --ev-selftest` passed 17 fail-closed law checks.

## 8. Files Modified

`tools/ev02_governance/policy_surface_gate.ml`, `tools/ev02_governance/run_checks.ml`, and `tools/ev02_governance/write_manifest.ml` are new isolated OCaml evidence tools. This journal, risk assessment, raw outputs, manifest, and checks receipt are evidence. No CLI/bootstrap source owned by EV-01 was changed.

## 9. Architectural Observations

`tools/km_provenance/km_gate.ml` lines 63-86 explicitly limits metrics to report-only document observation, and lines 544-592 refuse legacy reference recording and declare admission computation report-only. `Km_ev.admit` in `tools/km_provenance/km_ev.ml` lines 41-53 refuses one-key and legacy two-file evidence.

## 10. Remaining Gaps

EV-02 lacks the canonical 38-family manifest with family identities, immutable original-source snapshot/sanitization binding, adaptation mapping to these surfaces, fresh runtime behavior for the relevant governance enforcement, a candidate-bound formal specification, and authenticated independent Codex/AGY review. The AGENTS-referenced `2026-09-05` governance design filenames are absent at the cited paths; related later files are not substitutes.

## 11. Metrics Summary

Four direct invocations: two passing controls and two expected HOLD observations. The policy observer has four selftest predicates. Current observed policy-family union is 33, five below the historical target; no completion or admission metric is inferred.

## 12. STAMP & Constitutional Alignment

The task remains under Sa-plan and source-bound risk assessment. It preserves ceiling 93, treats EV-02 as not verified, makes no runtime side effect, and applies STPA controls against provided-unsafe closure, omitted failures, stale binding, and prolonged report-only interpretation.

## 13. Conclusion

The bounded verifier is ready for independent review, and the evidence is a concrete HOLD rather than a repaired EV-02 closure. It establishes the smallest next acceptance input: an independently reviewed, immutable 38-family source/adaptation manifest; only then can runtime and formal acceptance work be meaningfully bound.
