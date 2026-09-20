---
name: ach-admiralty-audit
description: Assess competing hypotheses, source reliability, credibility and adversarial countercases using Bountytek's three-provider OCaml engine; use for evidence-backed decision support, never certification.
---

# ACH, Admiralty and adversarial assessment

Read the packet schema and engine runbook before preparing input. Define at least three plausible competing hypotheses from the actual decision, including adverse or no-action cases where relevant; never reuse predetermined winners. Record source excerpts, origin, verification record, observation/expiry dates and independence groups. Verify sources outside the models.

Run `ocaml ach_admiralty_engine.ml --input packet.json --output-dir /tmp/NEW-PRIVATE-RUN --timeout 180`. Use an unused output directory. Each of Codex, AGY and Claude must provide every required dimension; never allocate one provider only to quantitative work and another only to judgment.

Review report.md, report.json, review-actions.json and original receipts. Quantitative findings require units, basis, uncertainty and independent recalculation. Compare qualitative limitations and judgment rationale, all matrix/grade disagreements, alternative hypotheses and falsifying observations. Lower nonnegative engine disconfirmation penalty means less refuted, not more probable. Inadmissible/unknown or incomplete evidence disables ranking. Do not describe the policy's A1/A2/B1/B2 set as a NATO certification.

Replay only with `--replay-dir OLD-RUN --output-dir NEW-RUN`; label it replay. Return incomplete when any provider is missing. Turn the open actions into a review agenda with competent accountable owners and acceptance evidence, not an automated release decision.
 

## Shared boundary

Follow the project rule `governance/rules/bountytek-assessment.md` (C3I adapter: `.agents/rules/bountytek-assessment.md`) and the engine runbook `ACH_ASSESSMENT.md` in the Bountytek project. Retain deployment_authorized:false and HOLD_FOR_INDEPENDENT_SAFETY_REVIEW. This skill is guidance, not a certifier, installed tool or permission grant. Missing sources or unavailable providers must remain explicit. No automatic outreach, production changes or safety approval.
