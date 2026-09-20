# Assessment artifact review — 2026-09-28

This record covers Bountytek assessment governance and documentation. It is not a system-wide C3I/UOS safety certification. Deployment remains on hold.

## 1. Scope & Trigger

The user requested review and update of rules, skills, superpowers, plugins and agents after the three-provider assessment-engine change. Scope includes the Bountytek workspace, its artifact mirrors and the six C3I skills created for this workflow. Unrelated platform rules, third-party plugin code, credentials, model configuration and UOS admission policy are outside this change.

## 2. Pre-State Assessment

The handover and catalog claimed unconditional verification, named outdated models and described eleven “superpowers” as operational. Six custom skills included unsupported certification, hidden reasoning, SDK and procurement claims. Workspace skill directories were empty. The Mojo verifier looked for predetermined assessment conclusions and compared file sizes. The document renderer repeated an unsupported validation badge on all pages.

## 3. Execution Detail

Rewrote six project skills; added a shared assessment rule, an advisory reviewer role and a plugin/Superpowers integration policy. Replaced the handover, catalog, index and README. Historical Markdown receives a visible supersession notice; earlier presentations receive a fixed notice. Original changed sources are preserved under `historical/20260928-pre-governance/`.

Reworked the OCaml renderer to escape source text, reject executable URLs, produce static navigation and show a deployment hold. It writes local HTML only. Added an artifact registry, SHA-256 verifier and a preimage-checked installer with staged payloads and rollback copies. Retired the five obsolete Mojo verifier/cycle/deck-generation entry points; the historical source remains available for audit.

The initial guidance-only phase installed and byte-verified 36 C3I guidance copies: nine files in each of `.agents`, `.claude`, `.gemini` and `.codex`. The engine and live site were untouched in that phase. After the user's restoration confirmation, the full artifact set is synchronized using a new preimage-bound plan. File installation does not activate a running agent or plugin; receipts distinguish the two phases.

## 4. Root Cause Analysis

The earlier workflow tested that expected text and files existed, then presented those checks as evidence of market truth and safety. This is a circular verification error. A second failure occurred during this review: at 09:30 local time an external writer replaced the previously tested v2.1 engine in all three locations with the older hardcoded source. That source fails compilation at line 276 and again prints unconditional safety claims. Writer identity and trigger are unknown; a specific process is not blamed without evidence.

The overwritten engine digest was `6846e0cd2cf9b04cbe3ef3555319464c033a57b7988198d1773f1c4c65078687`. The reviewed v2.1 digest is `fc1aed0907ba587116d9ce5eead09d17395269f950377d397f5b933aaafffe7c`. The user selected restoration and confirmed the other-writers-stopped option. The canonical engine was restored from the preserved source; the matching hash and a fresh 4,101-check pass were observed. The conflicting source remains archived.

## 5. Fix Taxonomy

False certainty: replace unconditional ratification with explicit evidence limits. Stale guidance: establish one scoped rule and byte-identical mirrors. Reintroduced legacy tools: archive their sources and remove active entry points. Concurrent write risk: bind installation to source and destination hashes and fail on conflicts. HTML injection: escape text and reject unsafe link schemes at rendering boundaries.

## 6. Patterns & Anti-Patterns Discovered

File equality establishes synchronization, not truth. A skill name is not an installed capability. A cached plugin is not an active plugin. Model agreement is not independent corroboration. A self-test pass does not qualify a tool for life-critical use. A deployment hold must remain visible even when an assessment is structurally complete.

## 7. Verification Matrix

| Check | Observed result | Limit |
|---|---|---|
| Preserved v2.1 engine self-test | 4,101 checks passed in a fresh run | Bounded synthetic checks; not operational validation |
| Restored canonical v2.1 engine | SHA-256 matches preserved reviewed source; 4,101 checks passed | Previous overwritten source failed compilation and remains archived; no new live-provider trial |
| Renderer boundaries | 14 checks; run `render_docs_wiki.ml --self-test` | Covers escaping, link schemes, malformed tables, duplicate anchors, navigation, unclosed fences and parenthesized PDF filenames |
| Artifact verifier boundaries | 7 checks passed | Hash oracle, missing files, relative-path checks and typed incomplete state |
| Artifact/mirror integration | Run `verify_assessment_system.ml`; install receipt records actual outcome | No pass claim without fresh output and matching hashes |
| Generic C3I UI report quality gate | Failed | Expects a six-diagram UI closure bundle, index/analysis/deck/journal/email pack and platform-specific evidence absent here; no generic closure certification claimed |
| Three-provider live trial | Incomplete, two usable responses | Claude access blocked; final AGY flags not live-retested |

The installation preflight correctly rejected a source changed after staging. The full installer correctly refused the conflicting engine. A local consistency pass also caught a truncated HTML read/copy (79,192 bytes versus 79,374 bytes). The sync now requires two identical source reads matching stable file size/mtime and verifies writes; the verifier fails on short reads. This is a bounded filesystem check, not a guarantee that another writer cannot alter a file later.

The generic gate was executed using the existing compiled Gleam module through Erlang. Its raw failure report is `diagram-quality-report.md`; this is a genuine failed gate, not a skipped or passed check. The assessment-specific verifier is a separate contract, not a waiver of that failure.

## 8. Files Modified

See `ASSESSMENT_SYSTEM_REGISTRY.json` for exact artifact paths, roles and SHA-256 digests. `maintain_assessment_artifacts.ml --prepare` synchronizes the local project mirror and builds `/tmp/bountytek-governance-install-20260928/plan.json`. The plan lists exact external destinations, old/new hashes and rollback copies. `--install` requires the reviewed engine hash and unchanged preimages. A successful file receipt does not activate plugins, agents or UOS policy.

## 9. Architectural Observations

The assessment engine is a standalone OCaml advisory tool. The commercial library is served as static documentation. Codex, AGY and Claude are CLI adapters. Superpowers 6.4.2 is observed in the Codex plugin cache with empty hooks; activation is not attested. Scoped C3I mirrors are documentation adapters. UOS global policy and user-local plugin packages remain unchanged.

## 10. Remaining Gaps

The concurrent overwrite has been reconciled by user-authorized restoration. Remaining assurance work: resolve authorized Claude access and test final adapter flags; specify the real deployment, domain standard, SIL-6 definition and accountable risk authority; authenticate source evidence; validate calibration/performance, provider containment, human factors and downstream hold enforcement. Raw financial data and commercial/regulatory claims have not been independently revalidated. Generic UI closure requirements remain unsatisfied.

## 11. Metrics Summary

Six skills rewritten; one shared rule; one reviewer role; one plugin integration policy; five obsolete automation entry points retired. Automated tests are counted by their actual bounded checks, not by asserted epistemic quality. No coverage entropy, independence probability, risk reduction percentage, Bayesian reliability or formal proof is invented from these counts.

## 12. STAMP & Constitutional Alignment

Primary loss: harmful reliance on unsupported assessment judgments. Hazard: false approval or apparent certainty reaches an operational decision-maker. Controls: explicit hold, original provenance, disagreement retention, source qualification, independent numerical review, open acceptance actions, and failure on hash conflicts. Unsafe timing includes stale assessments and concurrent overwrites. Written policy supplements runtime behavior; it is not evidence that every downstream controller enforces the hold.

## 13. Conclusion

The revised artifact set makes evidence limits and operational obligations explicit. The canonical engine has been restored with user authorization and passed the recorded bounded checks. Exact source/project/served/C3I synchronization is verified separately by `verify_assessment_system.ml --all-mirrors` and the installation receipt. These checks cannot establish loss-of-life deployment readiness. The independent safety-review hold remains mandatory.
