# Skills, assessment capabilities and plugin registry

Updated 2026-09-28. This catalog describes Bountytek assessment workflow v2.1.0. Written guidance is not installed functionality or safety certification. Earlier “22 active skills / 11 sovereign superpowers / 100% parity” claims are withdrawn.

## Project skills

| Skill | Purpose |
|---|---|
| ach-admiralty-audit | Complete three-provider structured assessment and disagreement review |
| claude-extended-reasoning-audit | Claude adapter, concise evidence rationale and explicit access failure |
| agy-autonomous-orchestration | Bounded AGY adapter; no assumed autonomous SDK or delegation |
| codex-astra-sil6-invariant-guard | Codex hazard/invariant review; legacy name, no SIL certification |
| nordic-medtech-go-to-market | Source-backed commercial research and qualified assumptions |
| nordic-procurement-tender-intel | Notice-specific tender analysis and current primary-source checks |

Canonical project definitions are `skills/<name>/SKILL.md`. C3I adapter copies use the same content. Install manifests and the artifact verifier establish file parity; discovery/activation in a new agent session is separate.

## Observable capabilities (formerly called superpowers)

| Capability | Implementation and limitation |
|---|---|
| ACH | Deterministic weighted disconfirmation for eligible, complete evidence; no probability of truth |
| Admiralty dimensions | Reliability and credibility recorded separately; declarations are not authenticated |
| Quantitative review | Basis, unit and uncertainty fields; all model numbers need independent recalculation |
| Qualitative review | Findings, limitations, adverse evidence and missing information |
| Judgment | Rationale, uncertainty, alternative and confidence; confidence is not calibration |
| Devil's advocate | Countercase, alternative, tripwire; model challenge is not independent safety assurance |
| Hazard review | Four STPA UCA categories per supplied hazard; completeness of hazard inventory unproven |
| Source-group sensitivity | Group removal only for full eligible coverage; unavailable in current real record |
| Audit/replay | Packet/output hashes and original receipts; not source authenticity |
| Review actions | Open hazard/provider actions; unverified owner suggestions and no closure evidence |
| Deployment hold | Engine never authorizes deployment; downstream enforcement still requires validation |

## Agents, rules, plugins and Superpowers

`governance/rules/bountytek-assessment.md` states the shared contract. `governance/agents/bountytek-assessment-reviewer.md` specifies an advisory review role. It is not a running agent or an independent human safety authority.

| Integration | Observed state |
|---|---|
| Codex CLI | Real response retained; configured model identity must come from runtime evidence |
| AGY CLI | Real response retained; final plan-mode flags still need a live trial |
| Claude CLI | Organization access blocked; no assessment obtained |
| Superpowers | Manifest cached at version 6.4.2; no assessment-specific hooks declared; activation not attested |
| Project plugin / MCP server | None required or supplied by this engine |
| Vendor plugins | Managed externally; no package upgrades, credential copies or global activation changes |

Follow `governance/plugins/bountytek-assessment-integrations.md` for permission, provenance and upgrade boundaries. Generic development skills can structure implementation work but cannot certify source evidence or accept operational risk.

## Current verification boundary

The retained run is assessment_incomplete (two of three). deployment_authorized:false and HOLD_FOR_INDEPENDENT_SAFETY_REVIEW remain mandatory. [Validation record](ACH_ASSESSMENT_VALIDATION.html) separates bounded tests, replay and live trials. [Handover](CODEX_HANDOVER.html) explains commands and remaining requirements. [Governance](20260928-0934-ASSESSMENT_SYSTEM_GOVERNANCE.html) governs report use.
