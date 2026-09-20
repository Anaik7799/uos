---
name: claude-extended-reasoning-audit
description: Use Claude as one structured Bountytek assessor for quantitative, qualitative, judgment and adversarial analysis; preserve access failures and avoid claims about hidden reasoning or model identity.
---

# Claude assessment adapter

Invoke through the engine, with optional ACH_CLAUDE_MODEL set to a supported configured model. Do not claim a latest model, fixed hidden-thinking budget, access to chain of thought, or tool availability from this skill. Ask for concise rationale, evidence citations, assumptions, uncertainties and falsifiers.

The adapter disables tools and sessions and uses strict structured output; review actual receipt and error status. As of the recorded 2026-09-28 trial, organizational subscription access was disabled and Claude produced no assessment. A human administrator or an authorized credential setup must resolve that; do not bypass policy or insert a synthetic response. After access is resolved, run a new three-provider trial and retain the earlier failure.
 

## Shared boundary

Follow the project rule `governance/rules/bountytek-assessment.md` (C3I adapter: `.agents/rules/bountytek-assessment.md`) and the engine runbook `ACH_ASSESSMENT.md` in the Bountytek project. Retain deployment_authorized:false and HOLD_FOR_INDEPENDENT_SAFETY_REVIEW. This skill is guidance, not a certifier, installed tool or permission grant. Missing sources or unavailable providers must remain explicit. No automatic outreach, production changes or safety approval.
