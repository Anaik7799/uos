# Source register and research trail

Observed review date: 2026-09-06 UTC. Prefix `20260906-0631-` uses the host's mandated hour/second convention. Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #km-triad #checklist-nav #tailscale-web.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Review](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0631-web-knowledge-verification-review.md) · [Test catalogue](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0631-cross-project-test-catalogue.md) · [Sources](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0631-sources-and-research.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0631-web-knowledge-verification-journal.md).


Local code and documents are tracked by filesystem locator and digest. External private source locators are read-only workspace evidence, not published UOS routes. Primary web references were reviewed on 2026-09-06. A moving branch/page is not a pin. No external source code or test-fixture bytes were imported. The complete machine register is `20260906-0631-source-register.json`.

## Primary web references

| Primary source | Version and scope | Proposed use |
| --- | --- | --- |
| W01 — [Gleeunit API](https://hexdocs.pm/gleeunit/gleeunit.html) | Local 1.9; web API 1.10 observed | Run assertions against actual UOS values and collect named failures. |
| W02 — [Lustre element API](https://lustre.hexdocs.pm/lustre/element.html) | Local 5.6.0; web 5.7.1 observed | Serialize/query real Element values; do not confuse VDOM checks with browser layout. |
| W03 — [Lustre development queries](https://hexdocs.pm/lustre/lustre/dev/query.html) | 5.6 documentation reviewed | Component-role/content/state tests before browser integration. |
| W04 — [Phoenix LiveViewTest](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveViewTest.html) | 1.2.11 web documentation | Server-simulated LiveView event and render tests; browser layer remains separate. |
| W05 — [StreamData](https://stream-data.hexdocs.pm/StreamData.html) | 1.4 web documentation | Generated inputs, shrinking and reproducible property failures; port semantics to Gleam. |
| W06 — [Playwright visual comparisons](https://playwright.dev/docs/test-snapshots) | Rolling docs; pin runtime before adoption | Reviewed baseline, stable OS/fonts/browser, explicit pixel differences; screenshots alone are not quality. |
| W07 — [Playwright Trace Viewer](https://playwright.dev/docs/trace-viewer) | Rolling docs | Action/DOM/network/error timelines for causal debugging; traces proposed, current audit saved DOM/video. |
| W08 — [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | 12 December 2024 publication observed | Keyboard, focus, reflow, contrast, consistent navigation; manual criteria remain. |
| W09 — [ARIA-AT](https://github.com/w3c-cg/aria-at) | Moving repository, no import pin | Assistive-technology interoperability scenarios beyond accessibility-tree presence. |
| W10 — [axe-core](https://github.com/dequelabs/axe-core) | License must be checked per pinned package before ingestion | Automated accessibility rules as one modality; no full compliance claim. |
| W11 — [Web Platform Tests authoring](https://web-platform-tests.org/writing-tests/) | Rolling docs | Use testharness, reftest and webdriver test patterns for browser semantics. |
| W12 — [Core Web Vitals](https://web.dev/articles/vitals) | Page updated 2024-10-31 observed | Field p75 LCP &lt;=2.5s, INP &lt;=200ms, CLS &lt;=0.1; separate mobile/desktop and lab from field. |
| W13 — [Lighthouse](https://github.com/GoogleChrome/lighthouse) | Moving repository; not installed/run for this audit | Repeatable lab performance/accessibility diagnostics, never a proxy for actual field INP. |
| W14 — [HEART: measuring user experience](https://research.google/pubs/measuring-the-user-experience-on-a-large-scale-user-centered-metrics-for-web-applications/) | Rodden, Hutchinson and Fu; CHI 2010 | Define goals, signals and metrics for happiness, engagement, adoption, retention and task success. |
| W15 — [HaTS: happiness tracking surveys](https://research.google/pubs/hats-large-scale-in-product-measurement-of-user-attitudes-experiences-with-happiness-tracking-surveys/) | Research publication metadata reviewed | Pair behavior/latency data with task-specific user feedback; no surveys sent. |
| W16 — [Parsoid round-trip testing](https://www.mediawiki.org/wiki/Parsoid/Round-trip_testing) | Rolling wiki page | Test wikitext/HTML round trips using declared semantic equivalence and documented acceptable changes. |
| W17 — [CommonMark specification](https://spec.commonmark.org/0.31.2/) | 0.31.2 | Adopt only examples in UOS's declared Markdown dialect; classify intentional divergences. |
| W18 — [TiddlyWiki test directory](https://github.com/TiddlyWiki/TiddlyWiki5/tree/master/editions/test/tiddlers/tests) | Moving master; BSD-3-Clause license text separately read | Candidate backlink, backtransclusion, filter, parser, serialization and widget tests; fake DOM is not browser. |
| W19 — [TiddlyWiki backlink tests](https://github.com/TiddlyWiki/TiddlyWiki5/blob/master/editions/test/tiddlers/tests/test-backlinks.js) | File reviewed through web; no bytes imported | Candidate update/delete/rename and inverse-link semantic cases. |
| W20 — [TiddlyWiki license](https://github.com/TiddlyWiki/TiddlyWiki5/blob/master/license) | BSD-3-Clause text observed | Track attribution/notice obligations before any source or fixture admission. |
| W21 — [Logseq tests](https://github.com/logseq/logseq/tree/master/src/test) | Directory reviewed, not every test body | Candidate outliner/block identity, parser and query scenarios; further file-level review required. |
| W22 — [Logseq license](https://github.com/logseq/logseq/blob/master/LICENSE.md) | AGPL text and additional permissions observed | Per-file and version-specific review required before copying code. |
| W23 — [Joplin development guide](https://joplinapp.org/help/dev/) | Rolling docs; exact suite files not deeply inspected | Candidate sync, note identity, attachment and export workflows. |
| W24 — [Joplin license](https://github.com/laurent22/joplin/blob/dev/LICENSE) | AGPL-3.0-or-later default; subdirectories may override | Do not assume repository-wide uniform licensing or reuse logos. |
| W25 — [Docusaurus configuration](https://docusaurus.io/docs/api/docusaurus-config) | 3.10.2 docs observed | Build-time broken-link/anchor/duplicate-route gates complement runtime navigation. |
| W26 — [Sphinx builders](https://www.sphinx-doc.org/en/master/usage/builders/index.html) | Rolling docs | Linkcheck architecture; retain redirects, timeouts and exclusions as distinct statuses. |
| W27 — [Google OSS-Fuzz project guide](https://google.github.io/oss-fuzz/getting-started/new-project-guide/) | Rolling docs | Coverage-guided parser fuzzing in isolated harnesses; deterministic seeds here are a different modality. |
| W28 — [NIST automated combinatorial testing](https://csrc.nist.gov/projects/automated-combinatorial-testing-for-software) | Project documentation reviewed | Covering arrays over browser, viewport, theme, role, locale and network states with constraints. |
| W29 — [SHACL](https://www.w3.org/TR/shacl/) | 2017 Recommendation; do not conflate newer 1.2 drafts | Graph cardinality, class, path and closed-shape contracts for the knowledge graph. |
| W30 — [SHACL test suite](https://w3c.github.io/data-shapes/data-shapes-test-suite/) | Manifest format reviewed | Machine-readable expected conform/nonconform results; pin exact test manifests before use. |
| W31 — [PROV-DM](https://www.w3.org/TR/prov-dm/) | 30 April 2013 | Represent code/docs as entities, runs as activities and responsible agents; retain derivation chains. |
| W32 — [Seven Sketches in Compositionality](https://arxiv.org/abs/1803.05316v3) | Fong and Spivak; v3, 12 October 2018; abstract/metadata and local concepts reviewed | Ground carriers, operations, functors and compositional diagrams; no claim to have proved the full book. |
| W33 — [A faster algorithm for betweenness centrality](https://www.uni-konstanz.de/algo/publications/b-fabc-01.pdf) | Ulrik Brandes, 2001; PDF read | Prioritize navigation bottlenecks; derive product-specific budgets, not universal 0.35 thresholds. |
| W34 — [Stanford PageRank resources](https://web.stanford.edu/class/cs106m/meetings/03-pagerank/) | Updated 2025-10-03 | Links original Google/PageRank papers; use ranking for crawl priority, not proof of usability. |


TiddlyWiki's three-clause BSD text was read. Logseq's AGPL text and additional permissions were read. Joplin declares AGPL-3.0-or-later by default and allows directory-specific license overrides. Before any copying, pin the exact revision, inspect applicable per-file terms/notices and retain attribution. Neither a repository name nor its top-level license establishes the status of every file. This audit records reference use, not admission of those implementations.

## Detailed local source review

| ID | Filesystem locator | Review depth | Finding |
| --- | --- | --- | --- |
| Z01 | /home/an/dev/ver/zigvm/docs/design/HTML_ALGEBRA.md | Detailed source review | Token span/context/stack laws; tokenizer scope; historical counts not rerun. |
| Z02 | /home/an/dev/ver/zigvm/docs/design/TABLE_ALGEBRA.md | Full document read | Typed row/delimiter/arity model, independent oracle, exhaustive/mutation claims and fence preconditions. |
| Z03 | /home/an/dev/ver/zigvm/docs/formal/knowledge-systems-algebra.md | Detailed source review | Typed knowledge graphs, inverse links and embeddings versus isomorphisms. |
| Z04 | /home/an/dev/ver/zigvm/docs/TESTING_DISCIPLINES.md | Detailed source review | Law-first development, mutant controls, nonvacuous generators and paired visibility tests. |
| Z05 | /home/an/dev/ver/zigvm/docs/WIKI_RENDER_FEATURE_PROGRAMME.md | Detailed source review | Closed Markdown dialect, AST folds/zippers, transclusion and projection programme; distinguish plans from executions. |
| Z06 | /home/an/dev/ver/zigvm/docs/PLAYWRIGHT_OCAML_ONTOLOGY.md | Opening 160 lines and relevant authority descriptions read | Typed protocol versus external runtime and knowledge-only test corpus. |
| Z07 | /home/an/dev/ver/zigvm/docs/FRACTAL_FP_ATLAS.md | Opening 150 lines and registry scope read | Generated status/evidence distinctions, including unavailable observations. |
| C01 | /home/an/dev/ver/c3i/docs/journal/20260523-c3i-ui-current-100-target-review.md | Opening 170 lines and relevant findings read | Historical scoped UI closure, unavailable endpoints and shared projections. |
| C02 | /home/an/dev/ver/c3i/docs/architecture/indrajaal-ui-evaluation-framework.md | Opening 145 lines and framework dimensions read | Cognitive/temporal/situation/experience dimensions; proposed budgets are not measurements. |
| C03 | /home/an/dev/ver/c3i/docs/journal/20260410-1030-ui-evaluation-framework-review.md | Full document read | Conceptual scoring versus missing instrumentation. |
| C04 | /home/an/dev/ver/c3i/docs/journal/20260403-1700-gleam-testing-framework-graph-coverage-hitl.md | Opening 130 lines and mapping read | LiveView-to-Lustre mappings; scope/taxonomy and graph proposals. |
| C05 | /home/an/dev/ver/c3i/docs/journal/20260407-1200-fractal-bdd-31x7-verification-suite.md | Opening 130 lines read against test source | 222 functions do not imply delivered mesh messages or browser execution. |
| C06 | /home/an/dev/ver/c3i/docs/journal/20260406-2353-ui-playwright-e2e-allium-specifications.md | Full document read; referenced E2E path followed | A written specification is not itself TLA checker invocation or semantic immutability. |
| C07 | /home/an/dev/ver/c3i/docs/journal/20260511-planning-grid-agentic-ui-full-coverage-journal.md | Opening 145 lines and historical result tables read | Five-browser historical matrix and remaining race/restart/negative-schema programme. |
| I01 | /home/an/dev/ver/c3i/sub-projects/c3i/docs/formal_specs/cockpit_navigation_graph.md | Opening 150 lines and graph model read | Partial navigation graph versus actual route reachability. |
| I02 | /home/an/dev/ver/c3i/sub-projects/c3i/docs/architecture/ZUIP_V3_TESTING_ROBUSTNESS_PLAN.md | Opening 150 lines and robustness plan read | Planned schema/concurrency/dual-write/fault scenarios, not fresh runtime evidence. |
| U01 | /home/an/NAS-setup/uos/contracts/rules/dmc-tcm-mandate.md | Rule read | Terminology mismatch: Type Class Morphisms versus Traceability Coordinate Matrix. |
| U02 | /home/an/NAS-setup/uos/contracts/rules/diagram-ascii-mermaid-mandate.md | Rule read | Both editable sources; screenshots/video are provenance-bound evidence. |
| U03 | /home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/verification/dmc_tcm_algebraic_atlas.gleam | Core implementation read | Four of thirteen fields checked; Boolean morphism/sheaf flags; L0-L7 table. |
| U04 | /home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/verification/browser_emulation_bridge.gleam | Full implementation read | Copies declared test count into pass count without invoking a browser. |
| U05 | /home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_differential_oracle.gleam | Full implementation read | Digest equality/Boolean callbacks/file-count comparison; no native oracle invocation. |
| U06 | /home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/verification/algebraic_sheaf_harmonizer.gleam | Full implementation read | Whole-state digest agreement is narrower than actual restriction/gluing. |
| U07 | /home/an/NAS-setup/uos/governance/prompts/20260906-0742-codex-navigational-verification-master-prompt.md | Opening 160 lines reviewed as source evidence | Concurrent prompt contains aspirational counts and arbitrary centrality thresholds; not execution authority or a pass receipt. |


The separate bounded corpus index contains 8,047 records. Full-text indexing and extracted headings do not mean every line was manually analyzed or executed. Publication-time hashes identify current bytes; a moving source must be reviewed again before admission. Historical GREEN/count claims retain their historical scope.

## Skills and industry practices

| Skill | Source | Role | Adaptation |
| --- | --- | --- | --- |
| ocaml-scripting | /home/an/NAS-setup/uos/.codex/skills/ocaml-scripting/SKILL.md | Used | New read-only inventory, verification and evidence helpers; original OCaml preserved. |
| formal-technique-selection | /home/an/NAS-setup/uos/.codex/skills/formal-technique-selection/SKILL.md | Used | Choose bounded finite models and independent oracles; formal scope explicit. |
| gleam-expert | /home/an/NAS-setup/uos/.codex/skills/gleam-expert/SKILL.md | Used | Typed contracts, compiler checks and Gleeunit. |
| algebraic-fractal-structures | /home/an/NAS-setup/uos/.codex/skills/algebraic-fractal-structures/SKILL.md | Used as design guidance | Carrier/operation/denotation/law/oracle/generator/evidence packet. |
| wiki-design | /home/an/NAS-setup/uos/.codex/skills/wiki-design/SKILL.md | Reviewed design reference | Knowledge navigation, links and source semantics. |
| docs-design | /home/an/NAS-setup/uos/.codex/skills/docs-design/SKILL.md | Used for document renderer and navigation review | Two-way reading/navigation, escaping and source view; remote parser/sanitization gaps remain. |
| lustre-gleam-ui-expert | /home/an/NAS-setup/uos/.codex/skills/lustre-gleam-ui-expert/SKILL.md | Reviewed API/design reference | MVU/component tests; installed and online versions distinguished. |
| mobile-first-adaptive-ui | /home/an/NAS-setup/uos/.codex/skills/mobile-first-adaptive-ui/SKILL.md | Reviewed design reference | Responsive behavior and browser geometry, not a score. |
| ocaml-playwright-control | /home/an/NAS-setup/uos/.codex/skills/ocaml-playwright-control/SKILL.md | Used with UOS path adaptation | Typed OCaml lifecycle/control over installed external Playwright runtime; no original harness changes. |
| agentic-ui-evolve | /home/an/NAS-setup/uos/.codex/skills/agentic-ui-evolve/SKILL.md | Reviewed workflow reference | Observe/compare/correct/retest; historical email/Rust instructions do not override UOS. |
| ui-report-quality | /home/an/NAS-setup/uos/.codex/skills/ui-report-quality/SKILL.md | Reviewed and critically assessed | Artifact metadata/byte thresholds do not prove meaning/readability; no external closure bundle/email sent. |
| test-driven-development | /home/an/NAS-setup/uos/.codex/skills/test-driven-development/SKILL.md | Used where RED receipts exist | Do not retroactively claim TDD for every new test. |
| skill-repair | /home/an/NAS-setup/uos/.codex/skills/skill-repair/SKILL.md | Used in earlier skill repair work | Installed skill parse repairs and explicit manifest/evidence recording. |
| systematic-debugging | /home/an/NAS-setup/uos/.codex/skills/systematic-debugging/SKILL.md | Used | Agent health and observed browser regression diagnosis. |


Skill syntax/loader health and semantic quality are separate. Historical path/language/email rules do not override canonical UOS authority. The report critically examines quality metrics rather than treating artifact size, presence or supplied Boolean fields as proof. No messages were sent to other people.

## Failed or incomplete retrievals

| Attempted source | Result |
| --- | --- |
| https://www.cse.chalmers.se/~rjmh/QuickCheck/manual.html | Fetch failed; original QuickCheck paper/manual not reviewed in full |
| https://dl.acm.org/doi/10.1145/351240.351266 | Publisher fetch failed; bibliographic trail only |
| https://dl.acm.org/doi/10.1145/360825.360855 | Aho-Corasick publisher fetch failed; use local source laws as reviewed evidence |
| https://www.cs.cmu.edu/~cdm/resources/Tarjan1972-sccs.pdf | PDF fetch failed; no full-paper reading claim |
| https://ilpubs.stanford.edu:8090/422/ | Original PageRank endpoint inaccessible through browsing tool |
| https://www.cse.chalmers.se/~jomoa/papers/VPT21QuickSpec.pdf | 403; no full-paper reading claim |
| https://tiddlywiki.com/dev/#Testing | Fetch failed; used official repository test directory instead |


These failures are retained rather than replaced with a claim that the original paper was read. Stanford's institutional PageRank resource page supplies the original bibliography. The reviewed local code and independent finite oracles establish the inspected implementation evidence. Further corpus acquisition requires version, license, source-admission and execution receipts.


<details>
<summary>Verification checklist: 5 domains, 18 checkpoints — explicit evidence states</summary>

| Domain | Checkpoint | State and evidence boundary |
|---|---|---|
| Metadata, time and navigation | 1. Timestamp prefix | Present; synchronized host receipt recorded in review |
| Metadata, time and navigation | 2. Source provenance | File locators/digests and primary web references recorded |
| Metadata, time and navigation | 3. Tailnet navigation | Full FQDN links provided; site-wide correctness remains FAIL/UNRUN |
| Metadata, time and navigation | 4. Uniform document controls | Eight web unit tests pass; isolated browser checks separate from live deployment |
| Purity and storage safety | 5. Language boundary | New production checks Gleam; bounded verification/controller OCaml |
| Purity and storage safety | 6. Excluded runtimes | No prohibited runtime or dependency introduced by this work |
| Purity and storage safety | 7. Storage interlock | No storage administration performed; hardware interlock not reverified |
| Testing and mathematics | 8. Unit and regression | New scoped tests executed; legacy suites UNRUN |
| Testing and mathematics | 9. BDD and system | Typed sequence examples executed; complete user journeys remain incomplete |
| Testing and mathematics | 10. Property and fuzz | Finite graph census and deterministic route generation executed; coverage-guided fuzz UNRUN |
| Testing and mathematics | 11. Browser/navigation | Four baseline passes per 46 discovered pages; failures and skipped effects retained |
| Testing and mathematics | 12. Compiler and four math gates | Real compiler negatives and bounded SMT run; DMC/TCM/sheaf/full-site proofs incomplete |
| Control and observability | 13. Cross-language parity | Port mappings documented; no claim of executing original OCaml oracle |
| Control and observability | 14. Trace conservation | All 13 transport fields mutation-tested in new scoped module |
| Control and observability | 15. Runtime evidence | DOM, accessibility snapshots, images, videos and explicit failure ledger retained |
| Governance and VCS | 16. Jujutsu-only mutation | No native Git mutation; concurrent workspace advancement recorded |
| Governance and VCS | 17. Two-key admission | No external source-code admission; final site admission withheld |
| Governance and VCS | 18. Journal and diagrams | 13-section completion journal; new explanatory diagram has ASCII and Mermaid |

</details>

[Previous: review](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0631-web-knowledge-verification-review.md) · [Next: sources](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0631-sources-and-research.md) · [Return to wiki](http://nas-1.tail55d152.ts.net:4100/wiki).

