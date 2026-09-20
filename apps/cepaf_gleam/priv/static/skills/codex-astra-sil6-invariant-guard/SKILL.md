---
name: codex-astra-sil6-invariant-guard
description: Review Bountytek assessment invariants and safety hazards with Codex; the legacy skill name does not imply SIL-6 qualification, formal proof or operational authority.
---

# Codex invariant and hazard review

The historical identifier is retained for compatibility. Use the configured Codex model or ACH_CODEX_MODEL; do not infer model identity from the name. Run through the engine's ephemeral, read-only, schema-constrained adapter.

Identify loss, hazard, controller/control action, feedback, safe state and all four UCA categories: not provided, provided unsafely, wrong timing/order, and wrong duration. Give measurable verification and acceptance criteria. Treat model hazard lists as proposals requiring domain review; no claim of exhaustive coverage.

Check forged input/outputs, missing provider, stale source, lost dissent and false approval paths. Keep worst-case severity visible even if an FMEA priority score is small. Do not invent occurrence probabilities, use an RPN threshold to accept catastrophic risk, claim mathematical proofs from tests, or attach a model-generated digital safety attestation. Tests are bounded; production acceptance belongs to an independent competent authority.
 

## Shared boundary

Follow the project rule `governance/rules/bountytek-assessment.md` (C3I adapter: `.agents/rules/bountytek-assessment.md`) and the engine runbook `ACH_ASSESSMENT.md` in the Bountytek project. Retain deployment_authorized:false and HOLD_FOR_INDEPENDENT_SAFETY_REVIEW. This skill is guidance, not a certifier, installed tool or permission grant. Missing sources or unavailable providers must remain explicit. No automatic outreach, production changes or safety approval.
