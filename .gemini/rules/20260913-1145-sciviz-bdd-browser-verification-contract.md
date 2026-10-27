# SciViz & 167 Extensions BDD Browser Verification Contract

- **Contract ID**: `SC-SCIVIZ-BDD-001`
- **Domain**: UI Browser Testing, Scientific Visualization & Multi-Aspect BDD Verification
- **Authority**: Operator Directive / UOS Canonical Policy (`contracts/rules/20260913-1145-sciviz-bdd-browser-verification-contract.md`)
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/contracts/rules/20260913-1145-sciviz-bdd-browser-verification-contract.md](http://nas-1.tail55d152.ts.net:4100/docs/contracts/rules/20260913-1145-sciviz-bdd-browser-verification-contract.md)
- **Status**: ACTIVE & ENFORCED ACROSS SDLC, SRE, FORMAL PROOFS & AGENTS

#fractal-l2 #fractal-l3 #fractal-l4 #zero-muda #km-triad #stamp-stpa #bdd-sciviz

---

## 1. Operator Mandate

Per operator directive:
> **"increase gherkin+browser+ui+sciviz elements based test to 500 tests for sciviz and 167 extensions, clearly show which sciviz or extension fetaures are being tetsted, how much of full feature coverage and 5is being done, review each BDD, create comprehensive scripts that cover all aspects that the system supports"**
> **"update all system artifacts and wiring for this new feature and capability - sdlc, sre, formal verifications and evidence, agentic floswa nd aspects opf tehs sytem"**

---

## 2. Invariants & Rules

1. **500+ BDD Scenario Minimum (`INV-SCIVIZ-01`)**:
   The BDD browser test suite must maintain $\ge 500$ executable scenarios (measured: 542 scenarios) covering all 167 registered SciViz and analytical extensions without mock stubs.

2. **5 Orthogonal Verification Domains (`INV-SCIVIZ-02`)**:
   Every feature and extension batch must verify the 5 canonical domains:
   - **Domain 1**: Functional UI & Interactive State Transitions.
   - **Domain 2**: Mathematical Precision & Coordinate Geometry Projection.
   - **Domain 3**: WCAG 2.1 AA Accessibility & Keyboard Navigation.
   - **Domain 4**: Zero-Muda Purity (0 Bevy, 0 Graphite, 0 client JS).
   - **Domain 5**: OTel Telemetry & Sub-50ms Paint Performance.

3. **Zero-Muda Browser Test Runner (`INV-SCIVIZ-03`)**:
   BDD browser testing is executed natively via Hermes OCaml WebSocket CDP (`tools/webui_bdd_runner.exe`). External Node.js, Playwright, or Selenium dependencies are strictly barred from the runtime test harness.

4. **SDLC Gate Binding (`INV-SCIVIZ-04`)**:
   `tools/uos-cli gate G-SCIVIZ-BDD` and `tools/uos-cli gate G-SCIVIZ-5DOMAINS` are integrated into `uos-cli verify-all` and must pass 100% green before any release candidate admission.

5. **SRE Telemetry & Receipt (`INV-SCIVIZ-05`)**:
   Test execution must emit a durable SRE receipt to `var/sciviz_bdd/latest.json` containing timestamp, total scenarios, passed/failed counts, duration, and per-domain breakdown. Cockpit UI dashboards must display live status badges derived from this receipt.

6. **Formal Lean 4 & Gospel Soundness (`INV-SCIVIZ-06`)**:
   Test harness invariants must be formally proven in Lean 4 (`formal/lean/SciViz_Browser_Verification_Invariants.lean` Theorems 12–15) and specified with Gospel contracts in Hermes OCaml (`engines/hermes/modules/gospel_poodavr/sciviz_bdd_contract.ml{,i}`).

7. **Autonomous Agent Discovery (`INV-SCIVIZ-07`)**:
   The `sciviz_bdd_verify` tool must be registered in Cortex agent tool registry (`apps/cepaf_gleam/src/cepaf_gleam/agents/cortex.gleam`) and emit AG-UI reasoning lifecycle events during execution.

---

## 3. Enforcement & Verification

- **SDLC**: `tools/uos-cli gate G-SCIVIZ-BDD`
- **5-Domain Gate**: `tools/uos-cli gate G-SCIVIZ-5DOMAINS`
- **SRE Receipt**: `cat var/sciviz_bdd/latest.json`
- **Formal Gate**: `lean formal/lean/SciViz_Browser_Verification_Invariants.lean`
- **Gospel Contract**: `cd engines/hermes && dune build`
- **Agent Dispatch**: `cortex.gleam: sciviz_bdd_verify`
