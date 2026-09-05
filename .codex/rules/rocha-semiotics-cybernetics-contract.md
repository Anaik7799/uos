# Rocha Cybernetic & Semiotic Knowledge Contract

- **Contract ID**: `SC-ROCHA-001`
- **Domain**: Knowledge Management, Semiotic Traceability, and Cybernetic Systems
- **Authority**: UOS Architecture Board & Canonical Policy (`contracts/rules/rocha-semiotics-cybernetics-contract.md`)
- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/contracts/rules/rocha-semiotics-cybernetics-contract.md](http://nas-1.tail55d152.ts.net:4100/docs/contracts/rules/rocha-semiotics-cybernetics-contract.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web`
- **Status**: ACTIVE & STRICTLY ENFORCED IN CODE

---

## 1. Systemic Grounding & Rocha Cybernetics Mandate

The Unified Operational System (UOS) integrates complex systems cybernetics and biosemiotics (after Luis M. Rocha, Gordon Pask, and W. Ross Ashby) with ZigVM's formal Zettelkasten knowledge graph.

Per operator directive:
> **"secreate strong rules and checks in code. tag every doc and html page on the webiste. use checks in code"**

This contract establishes the mandatory invariants that MUST be satisfied by every Markdown document, every HTML web page, and verified by programmatic checks in code.

---

## 2. Invariants for Every Markdown Document (`.md`)

Every canonical `.md` file in `docs/` and across UOS must satisfy:

1. **`ROCHA-01-TAILSCALE`**: A full, clickable Tailscale Web FQDN link (`http://nas-1.tail55d152.ts.net:4100/<path>`).
2. **`ROCHA-02-FRACTAL`**: Explicit fractal layer classification (`#fractal-l0` through `#fractal-l9`).
3. **`ROCHA-03-SEMIOTICS`**: Mandatory semiotic and cybernetic tags:
   - `#rocha-semiotics`: Marks biosemiotic and self-referential closure.
   - `#cybernetics`: Marks feedback loops, OODA controllers, and circuit breakers.
   - `#km-triad`: Links the Hermes Wiki, ZigVM ZK, and C3I Living Ontology triad.
   - `#zero-muda`: Affirms 0 Bevy, 0 Graphite, and pure BEAM/Hermes algorithms.
4. **`ROCHA-04-TRANSCLUSION`**: Bidirectional knowledge transclusions linking:
   - Master ZK MOC: `[[zk:20260905-1801-moc-uos-unified-master]]`
   - Master Corpus Index: `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
5. **`ROCHA-05-NAVIGATION`**: Bottom navigation block with direct Tailscale links to the ZK Master MOC, Hermes Wiki Corpus Index, and Review Tome.

---

## 3. Invariants for Every HTML Web Page

Every webpage served by the UOS web cockpit on `0.0.0.0:4100` (`http://nas-1.tail55d152.ts.net:4100`) must render:

1. **Top Status Bar**:
   - Clickable Tailscale FQDN URL link (`http://nas-1.tail55d152.ts.net:4100/...`).
   - SIL-6 Fractal Badge (`SIL-6 / L0-L9 Fractal`).
   - Rocha Semiotics Badge (`#rocha-semiotics #cybernetics`).
   - Zero-Muda Purity Badge (`Zero-Muda Pure BEAM`).
   - Storage Safety Lock Badge (`Root OS NVMe 25503L801736 Locked`).
2. **18/18 Comprehensive Verification Checklist Accordion (`SC-CHECKLIST-001`)**:
   - Present on every screen with expandable inspection across all 5 verification domains.
3. **Interactive Document Viewer**:
   - Intercepts file links and opens them within the live web viewer.
   - Converts transclusion syntax `[[wiki:...]]` and `[[zk:...]]` into styled, clickable badges.
   - Dual View Mode toggle ("👁️ View Rendered Markdown" vs "📝 View Raw Source").
   - Click-to-Copy Tailscale URL button.
4. **Persistent System Footer**:
   - Direct Tailscale mesh links to NAS-1 (`:4100`) and peer VM-1 (`:8088`).

---

## 4. In-Code Programmatic Verification

Enforcement is not manual; it is strictly encoded and verified by:

1. **`tools/uos rocha-check`**: Programmatically inspects all Markdown files and verifies presence of Tailscale links, fractal tags, and Rocha semiotics tags.
2. **`tools/uos gate G-ROCHA`**: Automated gate requiring 100% compliance across all documents.
3. **`tools/uos verify-all`**: Unified in-code test runner executing all 8 domain checks (DMC, TCM, Timestamp, KM, WebLinks, Checklist, Rocha, Zero-Muda).
4. **`tools/uos doctor`**: Verifies all 19 EV-cycles.
5. **REST API Endpoint `/api/verify/checks`**: Returns JSON telemetry of all verified in-code rules.
