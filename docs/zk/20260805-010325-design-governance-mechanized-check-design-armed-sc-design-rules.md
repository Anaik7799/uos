---
id: 7f2a4c18-6b03-4d51-9e27-5c1d80a3f664
status: draft
last_verified: 2026-08-05
verified_by: agent
---
# Design governance MECHANIZED — check_design gate + armed SC-DESIGN Rete rules (DIVERGENCE 755)

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260805-010325-design-governance-mechanized-check-design-armed-sc-design-rules.md](http://nas-1.tail55d152.ts.net:4100/zk/20260805-010325-design-governance-mechanized-check-design-armed-sc-design-rules.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


20260805-010325, commit `6b9a1b4`. The design program's SC-F constraints stopped being protocol-only. Three arms are now mechanical.

**check_design** (`harness/zigvm_harness.ml`): new `--check-design` mode ALSO called from `check_docs`, so it runs inside the canonical gate. Decides SC-F registry TOTALITY (defined indices contiguous 1..max) and REFERENCE-CLEANLINESS (every SC-F cited by `FIGMA_WORKFLOW.md` / `INTEGRATED_DESIGN_WORKFLOW.md` / `FIGMA_FRACTAL_PHASES.md` resolves in the envelope). Live: `design check: ok (SC-F registry total 1..41; 3 doc(s) reference-clean)`.

**SC-DESIGN-1 / SC-DESIGN-2** (`Rete_rules.design_rules`, added to `all_rules`, hence armed in the Zero-Trust `verify_cycle` path shared by MCP `record_cycle` and CLI `--verify-cycle`): reject a cycle whose commit changed a generated design artifact (`tokens.json`/`.css`) without `harness/figma_design.ml` or a visible `regen:` acknowledgement (SC-F4, H-D2 silent drift); reject a cycle whose commit changed a published journal HTML without a real 64-hex sha256 or an explicit `publication:unverified` disclosure (SC-F18/F19, H-D3 dishonest evidence). Both consume facts `verify_cycle` ALREADY projects (`RecordCycle` notes + `GitDiffFile` paths) — no new evidence path, no new writer. The escape hatches are DISCLOSURES, never silence — the Tier-1 `PROOF-PENDING` shape.

Evidence: 13 `design-rete laws`; `rete_coverage_laws` now 18 (the new family proven a live discriminator and routed through `all_rules`); 3 mutants KILLED (MUT-DESIGN-1 drop the generator disjunct; MUT-DESIGN-2 accept a note merely saying "sha256"; MUT-DESIGN-3 data mutant planting a dangling constraint index). Exit codes measured without a pipe per CAST-12. Canonical gate: `All 1090 tests passed`, exit 0.

Notable: the law's first catch was its own author — the envelope §25 draft wrote a dangling constraint index as a literal token inside the registry file while describing MUT-DESIGN-3; `check_design` reddened on a 42..98 gap. The prose was fixed, not the law.

New constraint SC-F41 governance-sync (envelope §26); CTRL-FIGMA-DESIGN safety-packet addendum; W9 governance stage in the workflow lattice. Propagated to CLAUDE/CODEX/GEMINI, the four supervisor profiles, `docs/rules/full-symbiosis.md` (Design-Governance Law), `CLAUDE_HARNESS_SOP` §5d, and the `infranodus-design-superset` skill.

HONEST BOUNDARY: SC-F1–F40 remain protocol-enforced except the arms named in envelope §25.

Authoring note: written directly to the ZK schema because the MCP `zk_author_note` surface fail-closed with `STALE-HARNESS` (this slice rebuilt `harness/*.ml`; reconnecting the MCP client is a user-side action). No database was touched — this is a plain file in the same schema as its siblings.

Journal: http://vm-1.tail55d152.ts.net:8092/integrated-workflow-journal.html (sha256 b8cc2f79ea53e3c79a0ced241397189c7d2c8656beabd3b56c3b60c7205ef663, route byte-verified). Relates: [[zk--20260804-222210-integrated-w0-w8-design-workflow-lattice-p0-p9-walk-sc-f40-wiki-projection-advisory]], [[zk--20260804-215818-s7-stitch-generation-operator-unavailable-observed-ach-verdict-sc-f38-39]].

#design-governance #rete #check-design #sc-design #divergence-755 #stpa #mechanization #journal

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
