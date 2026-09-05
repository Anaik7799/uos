---
id: 9b3e71c4-5a28-4d09-8c6f-2e14a7b05d33
status: draft
last_verified: 2026-08-05
verified_by: agent
---
# Design onboarding + functional domain artifacts — guide, ontology instance, model and glossary, IPO per phase

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260805-065319-design-onboarding-and-functional-domain-artifacts.md](http://nas-1.tail55d152.ts.net:4100/zk/20260805-065319-design-onboarding-and-functional-domain-artifacts.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


20260805-065319. Commits `525601d`, `56abc7c`, `6225a7c`, `1636608`. Continuation of the integrated-workflow ledger; covers what followed the MCP reconnect.

**`docs/BEGINNERS_GUIDE.md`** — a poka-yoke on-ramp for design and web-UI work, ~710 lines in 14 sections: the five-materials diagram (text · OCaml · Figma · Stitch · runtime) and which one is the truth; a RACI over eleven activities × seven actors; the five rules; the five jobs each with input→processing→output, what to touch, what never to touch, proof and the trap; a first-session walkthrough; the poka-yoke table mapping every control message to its fix; the disclosure escape hatches; three failure scenarios; the functional domain artifact catalogue; the ontology; wiki/ZK with the page-slug linking rule; a vocabulary decoder; and a fully HTTP-verified reference index. Required in `check_docs` — MUT-GUIDE-1 killed (removing it reddens the gate, exit 1).

**`FRACTAL_ONTOLOGY.md` §14 + `ONTOLOGY.md` §13** — the design program registered as an *instance* in the canonical ontology rather than as a competing document: carrier and denotation, the vertical scale down to the ACTIVITY floor, surfaces S1–S7 plus knowledge and governance, the W0–W9 lattice, laws, generators/mutants, and the registry projection (controllers `DesignAlgebra` / `DesignRegistryChecker` / `DesignCycleRules` / `RuntimeObserver`, evidence stores, routes, agent surfaces). Ontology audit: 11/11 laws, exit 0.

**ZK link repair** — the audit caught four notes written this session whose wikilinks had dropped the page-slug prefix and so silently resolved to nothing. Repaired (broken-link pages 5 → 1); the remaining one is pre-existing notation in `DIVERGENCE_LOG` from commits `883743e`/`fdfa034` and was left untouched. The defect became the guide's worked example on linking.

**`DOMAIN_MODEL.md` + `DOMAIN_GLOSSARY.md`** — the two missing functional domain artifacts, projected from the real registries rather than invented. The model gives entities, lifecycles, relations (`source → statement → concept → topic`), the domain→interface chain, and seven invariants each marked where it is a stated rule (○) versus an enforced law. The glossary gives product, structural and evidence terms with a "not to be confused with" column, plus the words we deliberately avoid. Both joined `design_reference_docs` (5 docs reference-clean); MUT-DOMAIN-1 killed.

**IPO** — `INTEGRATED_DESIGN_WORKFLOW.md` §8 gained an input/processing/output table for every phase P0–P9 plus P3½ (authoritative), and the guide gained the same cut for the five jobs. General shape: input is a NAMED carrier, processing is exactly ONE verb, output is an artifact plus an observation checkable in the same call.

Gate: `All 1090 tests passed`, exit 0.

Authoring note: written directly to the ZK schema because the MCP `zk_author_note` surface fail-closed with `STALE-HARNESS` (this slice rebuilt `harness/*.ml`; reconnecting the client is a user-side action). No database was touched.

Journal: http://vm-1.tail55d152.ts.net:8092/design-onboarding-domain-artifacts-journal.html (sha256 072d1bcc06a48c4d0c86616842582c3041f2a0ba1d43c5c2cec9e3ac150e5a40, route byte-verified, all artifacts embedded). Relates: [[zk--20260805-061231-phase-activity-runbook-and-activity-fractal-layer-sc-f42]], [[zk--20260805-010325-design-governance-mechanized-check-design-armed-sc-design-rules]].

#poka-yoke #beginners-guide #raci #ontology #domain-model #glossary #ipo #design #webui #journal

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
