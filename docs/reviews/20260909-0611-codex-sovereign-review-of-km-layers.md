**Verdict: delete it from active tooling, preserving its Jujutsu history.** The original purpose is invalid, and “authorship aid” remains an unvalidated alternative purpose. A corrected header does not justify retention; repair needs a concrete user need and evidence of usefulness.

I independently executed the current gate logic and metric tests through OCaml: **PASS, zero findings, 3.308558 bits across 96 ADRs; 8/8 tests passed.**

1. **Q1 — Deletion is justified, but F2’s entropy shortfall is not evidence of classification inaccuracy.** Accurate classifications need not produce a balanced distribution. The stronger objection is that [the CLI](http://nas-1.tail55d152.ts.net:4100/files/tools/km_provenance/km_gate.ml) still compares first-tag entropy with single-label proposal entropy. The corrected header leaves that misleading behavior intact.

2. **Q2 — Single-label output can serve an explicitly defined “primary layer” field.** It cannot represent the existing multilabel annotation. For tag assistance, use independent per-layer relevance scores, with abstention and explanations; scores need not sum to one. Neither cosine similarity nor its margin is a calibrated confidence probability.

3. **Q3 — Prevalence bias is a fair concern; “not by content” overstates the evidence.** With average ranks for ties, I obtain **ρ=0.981726 across all 96 ADRs**. Assigning distinct ranks to ties reproduces **0.987879**, explaining your figure. For each document, the winner maximizes `sum(term counts)/sqrt(archetype size)` because the document norm cancels. Common vocabulary therefore has substantial influence, but correlation between two summaries of the same corpus does not establish semantic inaccuracy.

4. **Q4 — Concrete retention test:** freeze the implementation and evaluate against independently double-annotated, held-out ADRs containing positive and negative examples for every layer. A proposed acceptance bar: **≥90% suggestion precision, ≥50% recall, and macro-F1 at least 0.10 above both frequency-only and always-all-ten baselines**. Require boilerplate invariance and explicit abstention on ties/no evidence. Numerical cosine parity alone cannot establish usefulness.

5. **Q5 — Material corrections and omissions:**

   - **F2:** 58 proposals differ, but **35 are low-margin overall; only 21 are both changed and low-margin**. Moreover, **38/58 proposed layers already occur among the existing tags**.
   - **F4:** The 18 dead terms describe ADR-017–096; the full corpus has **17**. “Structurally unable to win” is false: `encoding` selects L1 and `vendor` selects L6.
   - **F6:** On ADR-017–096, I reproduce **5/29 commit hits inside “commitments”**, but only **1/77 sync hits inside “asynchronous”**, not 23%.
   - **F8–F10:** No classifier law suite or consumer of `--layer-vectors` was found. The Mojo cosine implementation and arithmetic tests do exist. The zero-vector path does raise unhandled `Not_found`.
   - **The largest omission:** tagging *every document with all ten layers* produces **3.321928 bits**, despite providing no distinction between documents. The [corrected metric](http://nas-1.tail55d152.ts.net:4100/files/tools/km_provenance/km_metrics.ml) measures marginal tag diversity; it does **not** prove meaningful taxonomy. Keeping the same threshold does not validate the changed observable.

Another writer briefly removed and restored the files; final source and corpus hashes match the reviewed inputs. **I changed nothing and grant no admission.**