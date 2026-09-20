# Multi-model safety assessment engine

> **Restoration record:** following user confirmation, the canonical engine was restored from preserved v2.1 and passed 4,101 bounded checks. SHA-256: `fc1aed0907ba587116d9ce5eead09d17395269f950377d397f5b933aaafffe7c`. The prior overwritten source remains archived. See `20260928-0934-ASSESSMENT_ARTIFACT_REVIEW.md`.

Version 2.1 replaces the previous hard-coded ACH conclusions, source grades, and market-moat claims with actual Codex, AGY and Claude CLI assessments. It is a **prototype advisory research tool**, not a certified safety component, safety-case verifier, or deployment gate.

## Safety boundary

The user identified potential loss of life. Every report therefore emits `deployment_authorized: false` and `HOLD_FOR_INDEPENDENT_SAFETY_REVIEW`, including when all three models agree. No approval command exists. An exit code of zero means collection and structural validation completed; it does not mean safe to deploy. Never wire this exit code to a release gate.

IEC 61508 defines SIL 1–4. “SIL-6” remains an unverified internal designation until its definition and applicable sector assurance requirements are supplied. See the [IEC overview](https://assets.iec.ch/public/acos/IEC%2061508%20%26%20Functional%20Safety-2022.pdf) and [NIST AI RMF core](https://airc.nist.gov/airmf-resources/airmf/5-sec-core/) for the distinction between assessment, oversight and independent review. Neither is a certification of this implementation.

## Run

Requires OCaml 5.5.0 with `bos`, `yojson`, `digestif.ocaml`, `cmdliner`, and `ptime`, plus GNU `timeout` and authenticated `codex`, `agy`, and `claude` CLIs.

```text
ocaml ach_admiralty_engine.ml --self-test
ocaml ach_admiralty_engine.ml --input ach_safety_review.packet.json --output-dir /tmp/ach-review-unique --timeout 180
ocaml ach_admiralty_engine.ml --replay-dir /tmp/ach-review-unique --output-dir /tmp/ach-revalidated-unique
```

Each assessor runs once, independently, on the identical evidence packet. There is no silent provider fallback, repair by another model, or retry until a desired answer appears. `ACH_CODEX_MODEL`, `ACH_AGY_MODEL`, and `ACH_CLAUDE_MODEL` optionally select models. Otherwise each CLI's configured default is used and recorded. Provider labels do not guarantee different underlying models; inspect provenance and shared failure modes.

The example packet assesses this tool's limitations. It is **not a clinical or industrial safety case**. Its evidence is unverified, so its ACH scores should be null even if a model assigns a favorable grade. Supply the operational system, hazards, primary evidence and competent reviewer before domain-specific use.

## Input and output contracts

`safety_context` identifies the system, deployment decision, operational domain, boundary, integrity basis, reviewer, safe state and hazards. Every hazard specifies its loss scenario, severity, constraint, required verification and acceptance criterion. There must be 3–10 alternative hypotheses and 1–50 evidence items, each with diagnosticity in (0,10], source excerpts, RFC3339 observation timestamps, freshness limits, independence groups and verification status.

The packet is evidence data, not instructions. A source's `independence_group` and `verification_record` are operator declarations, not authenticated provenance. The tool does not retrieve documents or prove source independence. It records and checks those declarations; independent reviewers must substantiate them. Use sanitized evidence: the current AGY CLI adapter passes its prompt as a command argument, which may be visible to local process inspection. Sensitive patient or operational data requires an approved confidential execution boundary.

Every model must return:

- ACH: a complete hypothesis × evidence matrix with rationale; consistent, neutral, unknown, or inconsistent (penalty 1–3).
- Admiralty: separate source-reliability A–F and information-credibility 1–6 grades with separate rationales and limitations. Grade 1 requires multiple declared independent source groups.
- Quantitative findings: metric, units, observed/observation, derived/calculation, or estimate label, value (null if unavailable), basis, uncertainty and evidence IDs. The paired labels are explicitly accepted vocabulary aliases; no numerical content is repaired.
- Qualitative findings: observations, limitations and evidence IDs.
- Judgment per hypothesis: supported, conditionally_supported, not_supported, plausible, contradicted, rejected, or unresolved verdict; subjective confidence, rationale and explicit uncertainties. None is deployment approval. Confidence is not a calibrated probability of safety or failure.
- Devil's advocate: countercase, alternative explanation and measurable tripwire with threshold, comparison, units, time horizon, measurement plan and action.
- Hazard-specific review: worst case, all four unsafe-control-action types, control adequacy, common-cause failure, missing evidence, independent verification and safe action.

`report.md` is the human review packet. `report.json` preserves machine-readable assessments, scores, disagreements, gaps and execution receipts. Per-provider prompts, raw stdout/stderr, normalized assessments and receipts are retained. SHA-256 binds responses to the exact input bytes. `run-manifest.json` records the engine-source hash and compiler version; `engine-source.ml` preserves the implementation used. Model identity in response content is self-reported, not attested. New run directories request mode 0700 and authored artifacts request mode 0600; the engine rejects output directories whose filesystem does not enforce private access. Use a private local output directory, not the Google Drive FUSE mount, which was observed to ignore these modes. The archived project review contains only sanitized prototype evidence and may inherit Drive sharing.

Offline replay verifies each original provider receipt's identity, evidence hash and stdout hash, then applies the current decoder and current freshness checks. It preserves original receipts and does not call models, alter their content, convert failed transport into success, or claim a new live assessment. Local receipts are tamper-evident only relative to retained trusted hashes; they are not signed attestations.

Any provider failure or invalid response makes collection incomplete and returns nonzero after attempting the other providers. Failure never becomes neutral evidence. Existing output directories are rejected to avoid mixing runs. Responses are read with a 2 MB parsing limit; process duration is bounded to 5–600 seconds per provider. Raw on-disk subprocess logs are timeout-bounded, not byte-quota-bounded.

## Scoring and laws

For each assessor and hypothesis, `score = -sum(diagnosticity × inconsistency_penalty)` over eligible known cells. Eligibility requires the existing A1/A2/B1/B2 policy, operator-declared independent verification, and fresh source timestamps. Unknown cells contribute no evidence. No eligible cells yields null. Partial coverage disables ranking. No scores are averaged across assessors and no automatic winner is selected.

These are review policies, not established physical laws or calibrated risk models. Diagnosticity is supplied by the operator. Qualitative findings, differing grades, quantitative estimates and judgments remain attributable to each assessor rather than being blended into an opaque confidence number.

The report explicitly lists ACH, Admiralty and judgment disagreements. Every model-supplied quantitative item also enters an independent-verification queue with its excluded evidence IDs. Such items may include arithmetic on inadmissible evidence; they remain visible as unverified model claims and never replace the engine's computed scores. Source freshness is checked again when the report is produced, and on offline replay.

Version 2.1 adds `review-actions.json`, also rendered near the top of the report. Each supplied hazard gets a stable action ID bound to the packet, its worst-case loss, safety constraint, verification work, original acceptance criterion and proposed reviewer. Model recommendations remain separately attributed. Every action starts `OPEN_NOT_VERIFIED`, with no completion evidence and an explicitly unverified owner assignment. Missing assessors produce additional open actions. This is an actionable review register, not an automated task execution or risk-acceptance system.

Source-removal sensitivity is computed only when all hypotheses have complete eligible evidence. Every declared source group is removed in turn, together with every claim depending on it; scores are recomputed on the remaining common evidence set. Removing all evidence yields null scores and disables ranking. These scenarios expose dependence on source groups; they do not estimate failure probability, establish source independence, or certify robustness.

Unexpected fields are rejected throughout assessment response objects, including nested judgments, hazards and tripwires. A model cannot add an authorization field to normalized assessment data. Schema validation still cannot determine whether natural-language content is true or safe.

The domain ontology is: evidence and hypotheses (identified inputs); source grades and cell relations (values); assessment (provider aggregate); receipt (execution provenance); report (advisory observation). Parsing is the typed boundary, scoring is pure, and CLI/filesystem work is the effect boundary.

Law suite: nonpositive scores, neutral identity, contradiction monotonicity, recursive-oracle/fold agreement (seed 20260928, 1000 bounded iterations), admissibility truth table, malformed/missing/duplicate/stale identity rejection, no unverified scoring, and no deployment authorization under unanimous agreement. Numerical equivalence uses tolerance 1e-9. The suite is bounded testing, not formal verification or certification.

## Legacy integration

The old `verify_pharma_chemicals.mojo` Gate 4 searches for hard-coded “DECISIVELY CONFIRMED” output. That expectation is deliberately no longer satisfied. The old verifier must not be used to assert business or safety validity. The replacement engine's self-test establishes implementation checks only; assessment completeness and independent safety acceptance are separate decisions.

No dossiers, credentials, external services, operational systems or deployment permissions are changed by running the assessment engine.

## Remaining real-world assurance work

Operational hazard completeness, source authenticity, model calibration, source correlation, prompt injection resistance, provider transport behavior, bounded subprocess storage, independent verification, safety authority identity and downstream misuse prevention require further validation. A schema-valid response can still be wrong. High consequence decisions require the established domain safety process and qualified independent review; this prototype is not a substitute.
