# SC-SCIVIZ-167-001: SciViz 167 Extensions Deep-Dive & Browser Media Verification Mandate

- **Rule Identifier**: `SC-SCIVIZ-167-001`
- **Sub-Rules**: `SC-SCIVIZ-167-ASPECTS` (Deep-Dive Aspect Engine), `SC-SCIVIZ-167-SVGS` (16 Bespoke Category Geometric Generators), `SC-SCIVIZ-167-FLAGSHIPS` (33 Flagship Extension Profiles), `SC-SCIVIZ-167-DATASETS` (High-Cardinality Scientific Datasets), `SC-SCIVIZ-167-MEDIA` (Headless Browser Video & High-Res Screenshots), `SC-SCIVIZ-167-5DOMAINS` (5-Domain 18/18 Checklist Verification)
- **Specification**: `apps/cepaf_gleam/src/cepaf_gleam/sciviz/extension_deep_dive.gleam`
- **Decision Record**: `docs/zk/20260916-2100-adr-135-sciviz-167-extensions-complete-deep-dive-implementation.md` (`ADR-135`)
- **Tailscale Link**: [http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260916-2100-sciviz-167-comprehensive-mandate.md](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260916-2100-sciviz-167-comprehensive-mandate.md)
- **Web UI Endpoint**: [http://nas-1.tail55d152.ts.net:4100/sciviz/comprehensive](http://nas-1.tail55d152.ts.net:4100/sciviz/comprehensive)
- **Lean 4 Proofs**: [`formal/lean/SciViz_167_Comprehensive.lean`](file:///home/an/NAS-setup/uos/formal/lean/SciViz_167_Comprehensive.lean)
- **Authority**: Codex Astra (`codex-astra`), Claude Fable (`L0-fable`), and Antigravity (`antigravity`) Tri-Sovereign Consensus

#fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #zero-muda #sciviz #svg #playwright #chrome #video #tailscale-web

---

## 1. Principle & Scope

Per operator directive ("check all branches for sciviz 167 extension. they have not been implemented completely. nas-1.tail55d152.ts.net:4100/sciviz/comprehensive. use claude to test with browser with images and video"), the system MUST ensure complete, verified, end-to-end implementation and visual presentation of all 167 ggplot2 extensions in the Unified Operational System (UOS):

1. **Aspect Engine Completeness (`SC-SCIVIZ-167-ASPECTS`)**:
   - `apps/cepaf_gleam/src/cepaf_gleam/sciviz/extension_deep_dive.gleam` MUST implement bespoke deep-dive aspects for all 167 extensions without falling back to inert 4-circle dummy geometry or generic unmapped telemetry.
2. **16 Category Geometric SVG Generators (`SC-SCIVIZ-167-SVGS`)**:
   - All 16 taxonomic categories (Quality Control & SPC, Complex Intersections, Text & Label Geodesics, Multi-Scale & Break Scales, 3D & Isometric, Diagnostic & ROC, Visual Effects & Shaders, Dimension Reduction, Layout & Spatial, Marginal & Distributions, Theming & Composition, Correlation & Networks, Temporal & Flow, AST & Dynamic Grammars, Genomics & Phylogenetics, Survival & Biostatistics) MUST possess dedicated, mathematically distinct SVG generators producing realistic domain data visualizations.
3. **33 Bespoke Flagship Extension Profiles (`SC-SCIVIZ-167-FLAGSHIPS`)**:
   - Flagship extensions across all domains (`ggram`, `ggupset`, `ggrepel`, `ggdist`, `xmrr`, `gg3D`, `ggbreak`, `ggalluvial`, `ggtree`, `geomtextpath`, `plotROC`, `ggfx`, `ggpca`, `ggforce`, `patchwork`, `survminer`, `ggcorrplot`, `gghighlight`, `ggspatial`, `ggtern`, `ggbeeswarm`, `ggstream`, `gghoriplot`, `ggQC`, `cowplot`, `ggmosaic`, `ggradar`, `ggbump`, `treemapify`, `ggstatsplot`, etc.) MUST define individualized parameter schemas, sample code, and specialized visual properties.
4. **Authentic High-Cardinality Empirical Datasets (`SC-SCIVIZ-167-DATASETS`)**:
   - Visualizations MUST bind to authentic scientific, biomedical, Kaggle, and operational corpora totaling over 18,000,000 empirical observations (TCGA Genomic RNA-Seq, MCMC Posterior Traces, UOS Swarm Mesh, MIMIC-III ICU Biostatistics, NOAA Climatology, SEMI Fab SPC, Kaggle Genomic Intersections, PubMed Knowledge Graph, Kepler/TESS Exoplanet Lightcurves, PDB 3D Macromolecular Coordinates, Credit Risk ROC Ensembles, and Financial High-Frequency Tick L2).
5. **Headless Browser Media Verification (`SC-SCIVIZ-167-MEDIA`)**:
   - Visual rendering and interactivity MUST be verified via headless Google Chrome using Playwright, capturing full-page and section screenshots (`var/sciviz_media/images/` and `docs/reports/sciviz_media/images/`) and generating a 1080p progressive HD walkthrough video (`docs/reports/sciviz_media/videos/sciviz_comprehensive_walkthrough.mp4`).
6. **5-Domain Comprehensive Verification Checklist (`SC-SCIVIZ-167-5DOMAINS`)**:
   - The UI endpoint `/sciviz/comprehensive` MUST strictly render and pass the 5-domain 18/18 verification checklist (`SC-CHECKLIST-001`), including zero-muda purity (0 Bevy, 0 Graphite, 0 foreign NIFs), root OS NVMe hardware interlock, and microsecond UTC ISO 8601 timestamps.

---

## 2. Invariant Rules

### Invariant 1: Catalog Cardinality Invariant (`INV-SCIVIZ-01`)
$$|\mathcal{C}_{\text{catalog}}| = 167$$
The catalog cardinality must equal exactly 167 extensions. Machine-checked by Lean 4 theorem `sciviz_catalog_cardinality_eq_167`.

### Invariant 2: Category Partition Coverage (`INV-SCIVIZ-02`)
$$|\mathcal{K}_{\text{categories}}| = 16 \quad \land \quad \bigcup_{k \in \mathcal{K}} \text{Ext}(k) = \mathcal{C}$$
The taxonomic categories must cover all 16 domains. Machine-checked by Lean 4 theorem `sciviz_category_count_eq_16`.

### Invariant 3: High-Cardinality Dataset Lower Bound (`INV-SCIVIZ-03`)
$$\sum_{d \in \mathcal{D}} \text{Records}(d) > 18{,}000{,}000$$
The cumulative empirical datasets bound to the visualizers must exceed 18,000,000 records. Machine-checked by Lean 4 theorem `sciviz_dataset_volume_gt_18m`.

### Invariant 4: Pure Functional SVG Determinism (`INV-SCIVIZ-04`)
$$\forall c \in \mathcal{C}, \quad \text{render\_svg}(c) \neq \emptyset \quad \land \quad \text{deterministic}(\text{render\_svg}(c))$$
Every extension yields a non-empty, pure functional SVG rendering without runtime side-effects. Machine-checked by Lean 4 theorem `sciviz_svg_rendering_deterministic`.

### Invariant 5: Storage Hardware OS NVMe Lockout (`INV-SCIVIZ-05`)
The root OS drive serial `HARD_DENIED_SYSTEM_OS_SERIAL` (`[REDACTED_SYSTEM_OS_SERIAL]`) is strictly locked fail-closed across all data ingestion and storage operations. Machine-checked by Lean 4 theorem `sciviz_storage_nvme_hard_denied`.

### Invariant 6: Zero-Muda Architecture Purity (`INV-SCIVIZ-06`)
$$\text{Count}(\text{Bevy}) = 0 \quad \land \quad \text{Count}(\text{Graphite}) = 0 \quad \land \quad \text{Count}(\text{ForeignNIF}) = 0$$
Machine-checked by Lean 4 theorem `sciviz_zero_muda_purity`.
