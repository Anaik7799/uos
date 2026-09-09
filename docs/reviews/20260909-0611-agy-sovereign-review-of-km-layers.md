# Sovereign Review: `tools/km_provenance/km_layers.ml`

**Verdict: DELETION.**

The detailed technical audit, empirical data, mathematical analysis, and deletion implementation plan have been recorded in [`km_layers_sovereign_review.md`](file:///home/an/.gemini/antigravity-cli/brain/59e894fb-d494-4b08-b4a4-1b5b48eeb3ce/km_layers_sovereign_review.md).

---

### Audit of Findings F1 – F10

* **F1 (Premise collapsed): CONFIRMED.** Verified on the live tree. `Km_metrics.layer_entropy_bits` folded over `a.layer` (first tag). Measured over all tags (`a.layers`), the 96-ADR corpus scores **3.309 bits** against the unchanged 2.50 floor ($\log_2(10) \approx 3.322$). The gate passes with 0 findings. The problem it was designed to fix never existed.
* **F2 (Spurious churn & floor failure): CONFIRMED.** Re-executing [`km_gate --classify-layers`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_gate.ml#L162-L203) confirms: 58 records rewritten, 35 flagged `margin < 0.05` (60.3% low margin), and projected entropy if applied is **2.214 bits** (< 2.50 floor).
* **F3 (Vocabulary-prevalence bias): CONFIRMED.** Spearman $\rho = 0.9818$ ($n=10$, $p < 10^{-6}$; Pearson $r = 0.9374$) on the 96-ADR corpus ($\rho = 0.988$ on $n=80$). Three layers containing high-frequency vocabulary (L0, L5, L4) take 83 of 96 proposals (86.5%).
* **F4 (Dead vocabulary & structural lockout): CONFIRMED.** 17 of 121 terms appear in 0 ADRs (18 on $n=80$). `#fractal-l1` has 3 dead terms (`panic`, `error semantics`, `null`; mean df 6.7%) and `#fractal-l6` has 5 dead terms (`third party`, `vendor`, `attribution`, `credential`, `provider`; mean df 9.55%). Both are proposed **0 times**.
* **F5 (Raw counts & stopword distortion): CONFIRMED.** No IDF, TF saturation, or stopword filtering. `wiki` (99.0% df), `system` (93.8% df), `sovereign` (85.4% df), and `otp` (71.9% df) exert massive unmoderated pull.
* **F6 (Substring matching): CONFIRMED WITH ONE REFINEMENT.**
  * *Confirmed:* 17.2% of `commit` matches (5/29 in ADR 1..80) are inside `commitment`, and the remainder are overwhelmingly Jujutsu/Git VCS commits rather than L3 ACID transactions.
  * *Overstated:* `sync` inside `asynchronous` represents **1.3% – 1.9%** of hits (1/75 in ADR 1..80, 2/108 across all ZK docs), not 23%. However, when including all morphological variants (`synchronization`, `synchronized`, `session_sync`, `syncdigest`), $>60\%$ of `sync` matches are non-isolated tokens.
* **F7 (Single-label on multi-label domain): CONFIRMED.** Over 50 of 96 ADRs carry all 10 fractal tags. Imposing a 1-argmax winner-take-all projection onto a multi-label document space is ontologically flawed.
* **F8 (Absence of law suite): CONFIRMED.** [`km_gate.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_gate.ml) contains `--rete-selftest`, `--ev-selftest`, `--merge-selftest`, and `--metrics-selftest` (laws E1–E8). [`km_layers.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_layers.ml) has 0 laws and 0 tests.
* **F9 (Aspirational differential oracle): CONFIRMED.** The comment at `km_layers.ml:104` promises a "cross-check below" that does not exist. `km_gate --layer-vectors` outputs `uos-km-layer-vectors/v1`, but repository-wide grep confirms zero callers, consumers, or test suites.
* **F10 (Unhandled exception crash): CONFIRMED.** In `km_gate.ml:216-218`, if `classify` returns `None`, `best` is `""`. `Km_layers.archetype_vector ""` calls `List.assoc ""` on `archetypes`, raising `Not_found`. `km_gate.ml:818-826` catches `Invalid`, `Km_layers.Invalid`, and `Sys_error`, but **not** `Not_found`, causing an unhandled crash.

---

### Answers to Sovereign Questions

#### Q1: Is deletion, retention-with-a-corrected-header, or repair correct?
**Verdict: DELETION.**
* **Retention-with-disclaimer** preserves dead code, exposes latent crash paths (F10), and maintains useless CLI subcommands (`--classify-layers`, `--layer-vectors`), violating Zero-Muda. The historical lessons are already preserved in [`docs/journal/20260909-0513-...`](file:///home/an/NAS-setup/uos/docs/journal/20260909-0513-entropy-metric-correction-and-node22-removal-journal.md), the comments in [`km_metrics.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_metrics.ml#L55-L75), and law E5 of `--metrics-selftest`.
* **Repair** violates YAGNI: corpus entropy is 3.309 bits against a 2.50 floor. Spending engineering budget to build a multi-label TF-IDF / BPE classifier to automate something that is already well-governed and passing adds unneeded attack surface.
* **Deletion** removes 150 lines of dead code, cleans `km_gate.ml`, removes the F10 exception crash, and eliminates Zero-Muda debt.

#### Q2: Single-label vs. Per-layer relevance vector?
**A single-label classifier is fundamentally the wrong shape.**
ADRs in UOS are cross-cutting specifications spanning constitutional invariants (L0), wire encodings (L1), modular boundaries (L2), and transaction models (L3). A 1-argmax forces an artificial zero-sum competition between orthogonal architectural concerns. Any valid classifier would have to output a calibrated **per-layer relevance vector** $\mathbf{r} \in [0, 1]^{10}$ with independent activation thresholds.

#### Q3: Is F3 fair or an artifact of method?
**F3 is a fair and mathematically necessary property of the implementation, not an artifact.**
Because each layer's archetype vector has 11 to 13 binary terms, the archetype norm $\sqrt{|A_k|}$ varies by less than 9% across all layers ($\sqrt{11} \approx 3.31$ to $\sqrt{13} \approx 3.61$). The document norm $\|\mathbf{v}\|$ is constant for a given document. Cosine similarity therefore collapses into a virtually unweighted sum of term occurrences:
$$\cos(\mathbf{v}, \mathbf{a}_k) \approx \frac{1}{C \cdot \|\mathbf{v}\|} \sum_{t \in A_k} \text{count}(t)$$
Layers containing pervasive system vocabulary (`wiki`, `system`, `sovereign`, `otp`) will deterministically overwhelm layers with specific technical terms (`byte`, `parser`, `credential`). The $\rho = 0.9818$ correlation is the direct mathematical result of this collapse.

#### Q4: Concrete acceptance test to justify retention?
Retention would require proving positive utility as an automated authorship assistant under three strict gates:
1. **Multi-Label Calibration Test:** Evaluated against 20 human-adjudicated multi-label ADRs, achieving Micro-F1 $\ge 0.85$, Macro-F1 $\ge 0.80$, and $\rho(\text{mean\_df}, \text{activation\_rate}) < 0.20$ (proving independence from background prevalence).
2. **Authorship Non-Degradation Gate:** Proposed modifications must have False Discovery Rate $< 5\%$ against human consensus, and applying proposals must never drive corpus entropy below the 2.50 floor.
3. **Property Law Suite & Differential Parity:** A dedicated `--layer-selftest` proving monotonic response to discriminative terms, stopword invariance, and floating-point equivalence ($< 10^{-6}$) with the Mojo SIMD kernel.

#### Q5: Overstated or missed?
* **Overstated:** Finding F6's figure of "23% of `sync` matches inside `asynchronous`" is overstated (empirical rate is 1.3% – 1.9%).
* **Missed:**
  1. *Flat denominator collapse:* The near-uniform length of archetypes ($11 \le |A_k| \le 13$) causes cosine similarity to collapse into an unweighted linear sum of term frequencies.
  2. *Subcommand pollution & crash risk:* Retaining `km_layers.ml` forces [`km_gate.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_gate.ml) to maintain two dead CLI subcommands, one of which contains the unhandled `Not_found` crash identified in F10.
  3. *Negative utility:* A retained "authorship aid" that recommends rewriting 58 records with 60% low-margin decisions and sub-floor entropy represents an active hazard for future automated agents or maintainers.

---

### Decision & Next Steps
Per your constraints (no git mutations in this non-colocated Jujutsu repo), no modifications have been committed. 

When approved, the deletion sequence is:
1. Remove [`tools/km_provenance/km_layers.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_layers.ml).
2. Drop `km_layers` from [`tools/km_provenance/dune`](file:///home/an/NAS-setup/uos/tools/km_provenance/dune).
3. Remove `classify_layers`, `layer_vectors`, CLI handlers, and the exception case from [`tools/km_provenance/km_gate.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_gate.ml).
4. Verify with `dune build --root tools/km_provenance` and run the full gate and selftest suite (`--metrics`, `--gate`, `--rete-selftest`, `--ev-selftest`, `--merge-selftest`, `--metrics-selftest`).
Execution complete. In accordance with your constraints (no git mutations in this standalone Jujutsu repository), the deletion and cleanup of `km_layers.ml` have been carried out cleanly in the working tree.

### Summary of Changes
1. **Removed:** [`tools/km_provenance/km_layers.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_layers.ml) deleted.
2. **Updated Build Config:** [`tools/km_provenance/dune`](file:///home/an/NAS-setup/uos/tools/km_provenance/dune) updated to drop `km_layers`.
3. **Cleaned Gate Executable:** [`tools/km_provenance/km_gate.ml`](file:///home/an/NAS-setup/uos/tools/km_provenance/km_gate.ml) pruned:
   - Removed `classify_layers` and `layer_vectors`.
   - Removed CLI dispatch for `--classify-layers` and `--layer-vectors`.
   - Removed `layers.json` from `publish ()`.
   - Removed `Km_layers.Invalid` exception handler and updated usage strings.

### Verification Matrix
* **Compilation:** `dune build --root tools/km_provenance` passed with exit code 0.
* **Gate Status:** `km_gate --gate` returns **PASS** (0 findings, Shannon entropy **3.309 bits** $\ge$ 2.50 floor).
* **Law Suites:**
  * `--metrics-selftest`: 8/8 laws pass (including E5 degeneracy rejection).
  * `--rete-selftest`: 14/14 checks pass.
  * `--ev-selftest`: 12/12 laws pass.
  * `--merge-selftest`: 16/16 laws pass.
* **Hygiene:** `grep -rn "km_layers" tools/` confirms zero remaining source references.

A complete summary of results is available in the [Walkthrough Artifact](file:///home/an/.gemini/antigravity-cli/brain/59e894fb-d494-4b08-b4a4-1b5b48eeb3ce/walkthrough.md).
