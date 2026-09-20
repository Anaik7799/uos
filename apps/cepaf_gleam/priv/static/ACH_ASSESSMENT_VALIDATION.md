# Validation record — 2026-09-28

> **Current-file validation:** following user confirmation, reviewed v2.1 was restored to the canonical path and its 4,101 bounded checks passed again. SHA-256: `fc1aed0907ba587116d9ce5eead09d17395269f950377d397f5b933aaafffe7c`. The concurrent overwrite and recovery are recorded in `20260928-0934-ASSESSMENT_ARTIFACT_REVIEW.md`; no new live provider trial or operational validation is implied.

Scope: assessment-engine implementation and limited live integration trial. **No certification, SIL determination, operational safety validation or deployment approval was performed.**

## Toolchain and tests

Observed local dependencies: OCaml 5.5.0, Bos 0.3.0, Yojson 3.0.0, Digestif 1.3.1, Cmdliner 2.1.1, Ptime 1.2.0.

`ocaml -w +8 -warn-error +8 ach_admiralty_engine.ml --self-test` passes 4,101 checks: 4,000 seeded arithmetic property checks and 101 boundary, scoring, reporting, replay and fault-path checks. Seed 20260928; 1,000 iterations with lists shorter than 50 terms; oracle/fold tolerance 1e-9. The recursive reference and fold interpretation agree over this bounded domain. Sign-inversion and admit-everything mutants are distinguished. This is bounded testing, not proof or certification.

Negative paths include absent safety context, missing assessment dimensions/hazards, duplicate matrix cells/grades, unknown evidence IDs, invalid grades, nonfinite confidence, future/expired evidence, purported verification without a record, wrong packet/provider identity, modified stdout, and failed transport paired with valid JSON. Unanimous model outputs still produce a deployment hold. Existing output directories and invalid timeouts are rejected. No tests invoke models or use operational equipment.

Filesystem integration tests exercise all three provider envelope shapes using clearly marked synthetic responses, successful collection with deployment hold, and a failed-provider case that writes an incomplete report and returns an error. Temporary synthetic artifacts are removed by Bos at process exit.

Version 2.1 adds twelve checks for top-level/nested authorization-field injection, open hazard/provider action creation, absent completion evidence, preserved acceptance criteria, unverified owner assignments, unverified-evidence sensitivity suppression, null scores after removing all evidence, grouped removal of correlated claims and separate scenarios for distinct source groups. A local record-update syntax error during implementation was corrected before the passing run. The preserved real responses are revalidated with the stricter decoder; this does not constitute another live provider trial.

## Live trial and cause notes

1. Initial sandbox attempt: Codex and AGY failed to initialize because local runtime writes and sockets were blocked; Claude timed out. Outputs remained incomplete. No synthetic assessor responses were substituted.
2. User-approved external-sandbox trial: actual Codex and AGY CLI responses were captured with packet and stdout hashes. Codex's runtime header identified gpt-6-astra; its answer conservatively reported its model as unknown. AGY's answer self-reported Gemini 3.8 Flash, which is not independently attested here.
3. Initial parser rejected the real responses' `observation`/`calculation` terminology and AGY's `rejected` judgment. Cause: the generated schema initially specified strings without the decoder's vocabulary, and the prompt's wording differed. Correction: publish explicit enums and accept documented, semantically appropriate vocabulary variants. No numerical values, findings or conclusions were altered. Offline revalidation checks original receipt and stdout hashes and preserves original errors in provenance.
4. AGY warned that `--mode plan` was ineffective alongside `--disable-slash-commands`. The latter flag was removed from the final adapter. That revised flag combination has not received another live assessment trial; its live enforcement remains an integration-validation gap.
5. Claude returned a nonzero exit and an explicit organizational restriction: Claude subscription access for Claude Code is disabled; an Anthropic API key or administrator enablement is required. No credential changes were attempted. Its response is not an assessment.
6. The Drive FUSE mount ignored requested private POSIX modes while archiving sanitized prototype review data. The final engine now checks directory permissions before writing any packet and requires a private local filesystem for execution. The project archive contains sanitized diagnostic evidence only; it is not a confidential evidence store.

The recorded review has **two usable assessments out of three** and remains `assessment_incomplete`, with a nonzero completion status. A complete three-provider live run remains unverified until Claude access is enabled. The final adapter's stricter schema was verified locally and by revalidating preserved responses; it was not represented as a new live run.

## Findings from the real responses

- Neither response establishes readiness for a loss-of-life deployment decision. Both identify missing operational context, independent evidence and assigned safety authority.
- Both prefer supervised research over operational reliance, but that is a model judgment, not accepted residual risk.
- The supplied evidence is unverified. The engine therefore emits null scores and disables quantitative ranking for every hypothesis.
- AGY nevertheless supplied its own numerical ACH penalties. Those remain explicitly unverified model claims in the quantitative review queue, separate from engine scores. Codex and AGY disagree on some relations, grades and confidence judgments; the report exposes those differences.
- Proposed verification includes forged-provenance injection, correlated-source tests, lost-dissent tests, timeout/partial-output tests, downstream hold enforcement, independent review and human automation-bias evaluation. These proposed activities are not claimed completed by the prototype's unit checks.

## Open assurance obligations

The actual system/deployment, operational domain, complete hazard inventory, governing definition of SIL-6 and accountable risk-acceptance authority are still required. Evidence authentication, semantic source independence, domain-specific performance, calibration, provider isolation, raw-log resource quotas, downstream consumer enforcement, human factors and independent tool validation remain open. The engine deliberately has no path to authorize deployment.

The original Mojo verifier's expectation of prewritten “DECISIVELY CONFIRMED” claims is obsolete and will not pass against this engine. Do not reinterpret passing implementation tests as an Admiralty or safety certification.
