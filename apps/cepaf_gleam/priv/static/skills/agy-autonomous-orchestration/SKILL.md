---
name: agy-autonomous-orchestration
description: Use AGY as a bounded Bountytek assessment CLI provider; verify actual plan-mode behavior and preserve provenance without claiming autonomous SDK or MCP capabilities.
---

# AGY assessment adapter

Use the engine's AGY CLI adapter with optional ACH_AGY_MODEL. It invokes plan mode, sandbox and structured JSON output. Plan-mode enforcement with the final flag combination is not live-validated yet. Inspect stderr and actual CLI behavior before using it with sensitive or operational material.

Prompts currently appear in AGY process arguments: restrict local visibility and use sanitized review packets. This skill does not provide an SDK, start_subagent, MCP federation, registry ingestion, telemetry or CRM access. Do not infer delegation authority from the skill name. Require all assessment dimensions and preserve every disagreement with other providers.
 

## Shared boundary

Follow the project rule `governance/rules/bountytek-assessment.md` (C3I adapter: `.agents/rules/bountytek-assessment.md`) and the engine runbook `ACH_ASSESSMENT.md` in the Bountytek project. Retain deployment_authorized:false and HOLD_FOR_INDEPENDENT_SAFETY_REVIEW. This skill is guidance, not a certifier, installed tool or permission grant. Missing sources or unavailable providers must remain explicit. No automatic outreach, production changes or safety approval.
