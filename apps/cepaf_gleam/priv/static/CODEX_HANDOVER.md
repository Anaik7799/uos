# Bountytek project handover

> **Integrity incident resolved:** the user authorized restoration of reviewed v2.1 after a concurrent overwrite. The canonical engine was restored from `ach_admiralty_engine.v2.1.recovery.ml`, matched its reviewed SHA-256 and passed 4,101 bounded checks. The overwritten source remains archived. See the [artifact review](20260928-0934-ASSESSMENT_ARTIFACT_REVIEW.html) for provenance and the remaining safety hold.

Updated 2026-09-28. Engine v2.1.0. **Advisory prototype; HOLD_FOR_INDEPENDENT_SAFETY_REVIEW. No deployment authorization.**

## Project and authority

This workspace contains Bountytek's commercial research for proposed Nordic representation of 2S Consulting and Numantra: MedTech/SaMD and pharma/biotech/chemicals tracks, account dossiers, outreach drafts, offers, financial source material and presentations. Representation rights, commercial performance and regulatory claims must be checked against primary evidence. The library is not a validated operational safety case.

The OCaml engine now requests real Codex, AGY and Claude assessments. Each must cover quantitative findings, qualitative findings, judgments, ACH, Admiralty grading and devil's advocate analysis. Earlier deterministic text claiming a confirmed winner is retired. No score is a probability of safety and no model vote authorizes deployment.

## Start here

- [Assessment runbook](ACH_ASSESSMENT.html): packet and CLI contract, outputs and limitations.
- [Safety analysis](ACH_SAFETY_ANALYSIS.html): hazards and constraints.
- [Validation record](ACH_ASSESSMENT_VALIDATION.html): exact tests and actual live results.
- [Governance rule](20260928-0934-ASSESSMENT_SYSTEM_GOVERNANCE.html): guidance for rules, skills, agents and consumers.
- [Skills, capabilities and plugins](SKILLS_AND_SUPERPOWERS_CATALOG.html).
- [Artifact index](PROJECTS_INDEX.html).

## Observed assessment state

The preserved trial contains two usable assessments of three. Codex and AGY returned substantive responses; Claude was blocked by organization access policy. Schema/decoder fixes were checked by replay of preserved responses. The final AGY flag combination has not had a further live trial. No three-provider integration pass is claimed.

All packet evidence is unverified: engine hypothesis scores are null and ranking/sensitivity is unavailable. Model-generated numbers remain in the independent recalculation queue. The report exposes two ACH disagreements, three grade disagreements and three judgment disagreements. Three open review actions cover the two supplied hazards and missing Claude assessment. These are limited prototype observations, not a complete operational hazard analysis.

Sanitized local record: `ach_assessments/20260928-v21-review/`. Confidential assessment inputs must never be mirrored to the served static directory or Drive. The actual deployment, governing definition of “SIL-6”, domain standard and accountable safety authority remain unspecified. IEC 61508 uses SIL 1–4; this project has no SIL certification.

## Reproduce and review

```text
ocaml -w +8 -warn-error +8 ach_admiralty_engine.ml --self-test
ocaml ach_admiralty_engine.ml --input ach_safety_review.packet.json --output-dir /tmp/NEW-PRIVATE-RUN --timeout 180
ocaml ach_admiralty_engine.ml --replay-dir /tmp/EXISTING-RUN --output-dir /tmp/NEW-PRIVATE-REPLAY
ocaml render_docs_wiki.ml
ocaml verify_assessment_system.ml
```

Use a new private local output directory for each run; the engine refuses nonprivate directories. Model overrides: ACH_CODEX_MODEL, ACH_AGY_MODEL, ACH_CLAUDE_MODEL. Retain raw output and transport failures. Review report.md, report.json and review-actions.json together with receipts. Exit zero means successful structural collection only. No approval path exists.

The implementation self-test has 4,101 bounded checks, including 4,000 seeded arithmetic checks. It is not 4,101 independent safety cases or a formal proof. The artifact verifier checks hashes, guidance consistency and rendering; it does not verify commercial truth or deployment safety.

## Maintenance and mirrors

Authoritative project files live in this workspace. `projects/` and the UOS served static directory are artifact mirrors. Governance source files live in `governance/` and `skills/`; C3I `.agents`, `.claude`, `.gemini` and `.codex` receive scoped adapter copies. Workspace `.agents` and `.codex` are read-only mounts. UOS global policy, user credentials and vendor plugin caches are outside this installation. Mirrored reference files do not activate agents/plugins or satisfy UOS admission.

Use `ASSESSMENT_SYSTEM_REGISTRY.json` for file roles, hashes and retired paths. The local installer prepares an explicit preimage-bound plan before any external write. Verify exact mirror hashes after installation; equal sizes are insufficient. The renderer only writes local HTML and has no deployment side effects. Preserve previous material under `historical/20260928-pre-governance/`; archive files are not current instructions.

Old Mojo verifier and cycle scripts are retired because they test names, file lengths or prewritten conclusions rather than evidence. Historical presentations and certificates carry a visible supersession notice. Raw PDF, spreadsheets and financial JSON are source material whose accuracy is not certified by this update.

## Next operational requirements

Resolve authorized Claude access, test the final adapter flags live, provide the actual system/hazard packet and competent independent safety authority, authenticate evidence, validate domain performance/calibration and human factors, and verify downstream hold enforcement. No amount of mirrored documentation or model agreement closes these obligations.
