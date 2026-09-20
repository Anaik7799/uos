# Bountytek assessment governance — 2026-09-28

Scope: Bountytek's `ach_admiralty_engine.ml` and its research, report, skill, plugin and agent consumers. This is written operating guidance; runtime enforcement exists only where verified in the engine. It does not change unrelated C3I/UOS policy or grant tool permissions.

## Evidence and assessment rules

1. Require a specific system boundary, decision, losses, hazards, safe state, evidence, acceptance criteria and accountable independent reviewer. Missing operational context prevents operational use. The supplied packet is a prototype review, not a deployment case.
2. Use Codex, AGY and Claude through the engine's CLI adapters. Every provider must address quantitative findings, qualitative findings, judgments, ACH, separate source reliability and information credibility, devil's advocate countercases, and all four STPA unsafe-control-action categories per hazard. Three model names do not establish independent evidence or independent safety assurance.
3. Preserve original packet, prompt, schema, engine hash, raw output, errors, receipts and report. Do not replace unavailable providers with fabricated outputs or convert failed transport into success. Replay is revalidation of old responses, not a new live trial.
4. Separate measurements, calculations, estimates and unknowns. Quantitative findings need units, basis and uncertainty; independently recalculate model numbers. Never turn missing evidence into zero risk, guessed probability or a precise confidence claim. ACH penalties rank disconfirmation only; they are not accident probabilities.
5. Treat A–F reliability and 1–6 credibility as separate dimensions. Do not award a grade from a source's prestigious name alone. Eligible engine scoring requires A1/A2/B1/B2, declared verification with a record, known fresh timestamps and complete eligible matrix coverage. Declarations are not authenticated. Shared source groups are correlated; model agreement is not corroboration. Keep rejected evidence visible with reasons.
6. Retain disagreements, adverse evidence, alternative explanations, falsifiers and measurable tripwires. Source-removal sensitivity is available only for complete eligible coverage. It does not establish robustness against all plausible scenarios.
7. Preserve `deployment_authorized:false` and `HOLD_FOR_INDEPENDENT_SAFETY_REVIEW`. `assessment_complete` and exit 0 mean collection/structural validation only. No skill, plugin, agent, HTML badge or downstream workflow may translate them into operational approval. A named, competent human safety authority must independently accept residual risk under the applicable lifecycle; the engine cannot do so.
8. Review actions remain open until an authorized reviewer checks evidence against the original hazard-specific acceptance criterion. Suggested owners are unverified. Model proposals are not completion evidence. Do not edit an archived assessment to close tasks; record separately with provenance and review identity.
9. Execute on a private local filesystem. Do not put confidential packets/logs in Drive mirrors or served static assets. Review provider data terms, access and isolation for the intended data before use; AGY currently places prompts in process arguments. No automatic outreach, external writes or deployment is authorized by assessment completion.
10. Test negative paths, missing providers, injection, stale/unknown evidence, correlated sources, changed hashes, disagreements and downstream hold enforcement. Record bounded tests separately from live integration, formal proof, clinical validation and certification.

## Current observation and interpretation

Integrity incident resolved: after user confirmation, canonical v2.1 was restored and its 4,101 bounded checks passed. The overwritten source is archived. Verify engine SHA-256 `fc1aed0907ba587116d9ce5eead09d17395269f950377d397f5b933aaafffe7c` before relying on implementation claims. The handover and artifact review preserve the incident history.

Engine v2.1.0; recorded trial has two usable responses of three. Claude was blocked by organization access policy. The changed AGY flag combination has not had a new live trial. All supplied evidence is unverified, so engine hypothesis scores are null. The retained report is `assessment_incomplete`; operational use is on hold. Read ACH_ASSESSMENT_VALIDATION.md for exact test scope and limitations.

“SIL-6” remains an undefined internal requirement here. IEC 61508 describes SIL 1–4; do not invent SIL-6 certification. Governing domain standard, actual deployment, safety authority, evidence authentication, calibration, human factors, provider containment and downstream enforcement remain unresolved.

## Source precedence and maintenance

Use actual engine behavior and candidate-bound verification records for implementation claims; use independently validated primary evidence for domain facts. This rule supersedes conflicting Bountytek historical catalog/certificate assertions. User instructions and applicable parent governance retain precedence. Preserve source originals in the historical archive. Update guidance, schema-facing examples, tests, registry and served documents together. Compare bytes or SHA-256, not lengths. Mirror equality proves equality only.

References: ACH_ASSESSMENT.md; ACH_SAFETY_ANALYSIS.md; ACH_ASSESSMENT_VALIDATION.md; CODEX_HANDOVER.md. Standards basis: https://assets.iec.ch/public/acos/IEC%2061508%20%26%20Functional%20Safety-2022.pdf . Human oversight framework: https://airc.nist.gov/airmf-resources/airmf/5-sec-core/ .
