# 20260906-0300 Installed Skills Repair Journal

Observed host time: 2026-09-06T03:57:00.810Z. State: **VERIFIED for installed skill discovery and metadata**.
Tags: #fractal-l0 #fractal-l2 #fractal-l5 #zk-adr #zero-muda #tailscale-web #checklist-nav

Navigation: Command & Control — [Cockpit](http://nas-1.tail55d152.ts.net:4100/), [Planning](http://nas-1.tail55d152.ts.net:4100/planning), [AG-UI](http://nas-1.tail55d152.ts.net:4100/ag-ui/events); Knowledge Base — [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki), [ZK](http://nas-1.tail55d152.ts.net:4100/zk); Repository & Governance — [Files](http://nas-1.tail55d152.ts.net:4100/files), [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist).

Breadcrumb: [UOS](http://nas-1.tail55d152.ts.net:4100/) / [Repository](http://nas-1.tail55d152.ts.net:4100/files) / docs / journal / installed skills repair.
Document: [Full Tailscale URL](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0300-installed-skills-repair-journal.md). Evidence: [Machine-readable receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0300-installed-skills-repair-evidence.json). Use the document viewer's Rendered/Raw control to inspect either representation.

## 1. Scope & Trigger

The operator requested “fix all skills.” The repair covered discoverable workspace skills, personal Codex/Claude/Agents/Gemini installations, and installed plugin-cache skills. It corrected demonstrated loading, metadata, reference-link, and directory-traversal defects. It did not execute the workflows described by the skills.

The skill-repair and skill-creator guidance governed package inspection and validation. Installed home directories required filesystem escalation; the operator approved the prepared repair. External C3I and ZigVM source trees remained read-only evidence.

## 2. Pre-State Assessment

The initial workspace was clean at Jujutsu change xxwnznxw, commit 22008c49, parent 9c2451f6. Workspace agent roots link into the shared Gemini installation, while several personal roots independently link to the same external C3I skills.

Two YAML parsers identified 45 invalid descriptions. Five of those files contained duplicate frontmatter wrappers. Two additional descriptions were truncated. Nine Firecrawl links referred to missing local targets, and six installed directories contained self-referential symlinks. The native loader rejected 34 distinct source files; repeated aliases multiplied its error entries.

## 3. Execution Detail

### Candidate preparation

All files in each affected package were enumerated and inspected together. The 47 external-source packages contained 56 Markdown files, including nine supporting references. Credential-shaped content and binary bytes were excluded before any candidate digest or copy. Source digests were checked during staging, immediately before installation, and after verification.

Descriptions were quoted safely, five wrappers were merged while preserving the invocation hint, and three visibly truncated descriptions were completed or replaced with a concise capability description. Nine Firecrawl links now point to installed sibling skills. Existing workflow bodies were retained apart from those reference links and redundant metadata headers.

### Installation and recovery

Forty-seven repaired packages were installed as independent directories under ~/.gemini/config/skills. One hundred forty personal aliases now resolve to these installed copies. Nine Firecrawl entrypoints were edited at their installed paths. Six recursive links were moved into backup storage. Every replaced file or link was retained under the repair directory before replacement, with guarded rollback available during installation.

~~~mermaid
flowchart LR
  S[Read-only source skills] --> P[Staged repair and static validation]
  P --> I[Installed shared copies]
  I --> A[Workspace and personal aliases]
  A --> V[Native loader and complete directory scan]
  I --> B[Original files and links retained in backup]
~~~

## 4. Root Cause Analysis

The malformed descriptions show a consistent conversion defect: prose containing colons was inserted into YAML without quoting. Some wrappers copied a metadata line such as “description:” or “name:” into the new description. Other conversions cut descriptions at approximately 200 characters. Multiple symlinks exposed the same bad metadata through several discovery roots.

The recursive links are consistent with an installation command targeting an existing directory instead of replacing the intended link; the original command was not observed. Firecrawl references pointed to a router absent from this installation or to the literal relative path firecrawl-cli.

## 5. Fix Taxonomy

| Defect | Repair | Affected count |
|---|---|---:|
| Invalid YAML descriptions | Safe quoting and metadata normalization | 45 |
| Duplicate metadata wrappers | Merge original fields into one header | 5, included above |
| Additional truncated descriptions | Complete the discovery description | 2 |
| Broken local references | Route to installed sibling skills | 9 |
| Recursive directory links | Archive the self-link | 6 |
| Independent aliases to broken external files | Point to repaired installed copies | 140 links |

There were 62 affected skills: 56 changed entrypoints and six directory-link repairs. Supporting files were preserved. The plugin-owned mixed-case names accepted by the native loader were retained.

## 6. Patterns & Anti-Patterns Discovered

Inspect resolved paths before editing symlinked installations: editing an apparent workspace skill can mutate an external source tree. Validate both package syntax and actual loader behavior. Deduplicate diagnostics by resolved file to distinguish broken skills from repeated aliases. Retain source locators and backup links when replacing shared installations.

Literal output-link examples should be classified separately from shipped resources. Four such examples in vendor skills were inspected and excluded from the missing-file count. No workflow execution was needed to test metadata repair.

## 7. Verification Matrix

| Verification | Before | After / evidence |
|---|---:|---|
| Native Codex loader, UOS | 173 skills; 170 errors | 207 skills; **0 errors** |
| Native Codex loader, home | 144 skills; 68 errors | 178 skills; **0 errors** |
| Two YAML parsers | 45 invalid files | **349 unique skills pass** |
| UI metadata / packaged icons | Inspected during final scan | **125 UI files pass** |
| Local Markdown resource links | 9 broken links | **571 checked; 0 missing** |
| Recursive symlinks | 6 | **0** |
| External source preservation | 56 source files bound | **56 unchanged** |
| Installed bytes versus candidates | 65 candidate files | **65 match** |
| UOS timestamp-check | Fresh invocation | **Exit 0** |
| UOS checklist | Fresh invocation | **18/18; exit 0** |
| Repair manifest | Prepared / awaiting verification | **62 installed entries; errors cleared** |

The UOS commands were invoked through their existing compiled Erlang modules. Their checklist predicates check local contract/file presence and selected content. Their PASS output is not evidence of a fresh full-system test run. This task's runtime evidence is the native skills/list response; its static evidence consists of parser, resource, snapshot, and alias assertions.

<details>
<summary>Comprehensive verification checklist — 5 domains, 18 checkpoints</summary>

Checked entries below record the fresh repository checklist result and its limited contract-presence scope.

### Domain 1: Metadata, Timestamp & Tailscale Navigation

- [x] **CHK-01-TIME**: Timestamp contract present; this journal and evidence use synchronized host YYYYMMDD-HHSS prefixes.
- [x] **CHK-02-TAIL**: Tailscale navigation contract present; full clickable FQDN links included.
- [x] **CHK-03-FRACT**: Fractal metadata specification present; applicable layer tags included.
- [x] **CHK-04-KM**: KM contract present; [canonical knowledge-graph article](http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20260905-1721-uos-master-knowledge-graph-and-living-ontology.md), [[wiki:20260905-1721-uos-master-knowledge-graph-and-living-ontology]], and [[zk:ADR-001]] provide knowledge lineage. Transclusion rendering was not separately tested.

### Domain 2: Zero-Muda Purity & Storage Safety

- [x] **CHK-05-MUDA**: Exclusion contract present; no product source, dependencies, or imported history changed.
- [x] **CHK-06-GRAPH**: Pure Erlang facade present; no foreign NIF introduced.
- [x] **CHK-07-DRIVE**: Storage interlock specification present; no storage allocation or wiping performed.

### Domain 3: Testing Gold Standard & Mathematical Gates

- [x] **CHK-08-C1C8**: Gold-standard contract checked; UI behavior was outside this repair.
- [x] **CHK-09-MATH**: Math-gate specification checked; no new solver or proof invocation claimed.
- [x] **CHK-10-9MOD**: Test-suite presence checked; nine modalities were not rerun.
- [x] **CHK-11-REGR**: UI regression-test presence checked; the regression suite was not rerun.

### Domain 4: Cross-Language Control & Observability

- [x] **CHK-12-GLEAM**: OTP supervisor source present; no supervision change.
- [x] **CHK-13-HERMES**: Hermes interceptor source present; no evidence-engine change.
- [x] **CHK-14-ZIGVM**: Deterministic engine source present; no kernel change.
- [x] **CHK-15-MAX**: Inference-worker source present; no inference service change.
- [x] **CHK-16-OTEL**: Telemetry contract present; no new product telemetry emitted.

### Domain 5: Tri-Sovereign Governance & Jujutsu Monorepo

- [x] **CHK-17-SOV**: Governance superset present; no new multi-agent ratification claimed.
- [x] **CHK-18-JJ**: Standalone .jj repository present; no native Git mutations.

</details>

## 8. Files Modified

Forty-seven installed package entrypoints under ~/.gemini/config/skills: abm-campaign, business-analysis, channel-strategy, competitive-intel, crm-hygiene, deal-review, demand-forecast, design-win-tracker, fy-annual-plan, fy27-account-sprint, fy27-competitive-war-room, fy27-csv-export, fy27-deal-accelerator, fy27-log, fy27-obsidian-sync, fy27-pipeline-review, fy27-salesnav-ops, fy27-status, fy27-weekly-rhythm, fy27-zk-brief, gtm-strategy, journal-artifact-publisher, learn-rule, linkedin-outreach, marionette-explore, observe, pass5-auto, patrol-marionette-test, pi-verify, predict, pricing-strategy, proposal-builder, qbr-template, revenue-ops, sales-call-prep, sales-email, sales-prospecting, semi-market-intel, strategic-account-plan, tam-sizing, territory-plan, win-loss-analysis, zk-cost, zk-learn, zk-recall, agentic-ui-evolve, evolve.

Nine Firecrawl entrypoints under ~/.agents/skills: firecrawl-build-interact, firecrawl-build-onboarding, firecrawl-build-scrape, firecrawl-build-search, firecrawl-crawl, firecrawl-interact, firecrawl-map, firecrawl-scrape, firecrawl-search. Six archived self-links under ~/.claude/skills: algebra-driven-beam, algebra-driven-zig, parity-scenario-authoring, resource-preflight, writing-gospel-specifications, zigvm-harness-reuse. The evidence JSON records all 202 installation operations, exact paths, backup locations, and preserved source digests.

Repository additions: this journal and [20260906-0300-installed-skills-repair-evidence.json](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0300-installed-skills-repair-evidence.json). Repair state: /home/an/.local/state/skill-repairs/20260906-0031/20260906-0031-repair-manifest.json. Original links and replaced files are retained beside that manifest under originals/.

## 9. Architectural Observations

Skill loading is a separate assurance boundary from the workflows a skill describes. Correct metadata can restore discoverability while the underlying workflow still needs task-specific authorization, tools, and runtime validation. Shared installation copies provide a repair boundary without mutating read-only source authorities or rewriting unrelated working trees.

## 10. Remaining Gaps

No detected installation or discovery defects remain in the scanned roots. Existing sessions can retain cached metadata until reload. Vendor updates or future synchronization may replace local repairs. External source versions intentionally retain their original bytes, so reinstating their old links would reintroduce the observed defects.

No skill workflows, bundled executable behavior, external URL availability, or full-system admission was certified by this metadata repair. These remain subject to the usual task-specific evidence requirements.

## 11. Metrics Summary

Sixty-two skills repaired; 56 entrypoints changed; nine support files preserved; 140 aliases updated; six recursive links archived. The final inventory covers 349 unique skills across ten roots, 125 UI metadata files, and 571 local resource links. Both native loader scopes gained 34 accepted skills and report zero errors.

The fresh Chrony receipt reports normal leap status and system time 0.000135697 seconds slow of NTP time. That is an observed host-to-NTP offset; no system-to-model or agent-context delta is inferred. Source preservation covers 56 files, and installed candidate equality covers 65 files.

## 12. STAMP & Constitutional Alignment

The controlled action was installed skill replacement under explicit operator authorization. Before writing, the installer rejected unexpected paths, modified candidates, changed links, source drift, and writes resolving into external source trees. Originals were backed up before every replacement. Loader and static verification had to pass before the repair manifest advanced to installed with cleared errors.

No external source capability was imported into canonical UOS source, and no capability inventory state was promoted to admitted. No messages were sent, no storage devices were touched, and no Git mutation or forbidden runtime dependency was introduced.

## 13. Conclusion

The demonstrated skill installation defects are repaired and verified against the installed bytes. Codex discovery returns zero errors for UOS and home. The manifest, before/after loader receipts, source-preservation evidence, and backups make the result reviewable and reversible. Reload existing sessions to refresh cached skill metadata.

Previous: [Prior UOS journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/2026-09-05-uos-consolidation-context-journal.md). Next: [Repair evidence](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0300-installed-skills-repair-evidence.json).

System footer: [nas-1 Tailnet cockpit](http://nas-1.tail55d152.ts.net:4100/) · [vm-1 peer runtime](http://vm-1.tail55d152.ts.net:8088) · OTP 29 is the repository target; service health was not changed by this repair.
