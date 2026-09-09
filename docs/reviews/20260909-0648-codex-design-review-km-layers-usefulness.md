**Build a claim-to-witness auditor. P1 is the right direction; P2 overstates what lexical analysis can establish.**

First, the figures mix populations. Your 80-document statistics reproduce for **ADR-017–096**, excluding the sixteen files with six-digit time prefixes. The full 96-document snapshot has 47 all-ten records, 22 two-tag records, mean cardinality 6.51, and 17 dead vocabulary terms. The gate PASS, entropy 3.308558, and reported medians reproduce. ADR-002 scores L5 at 0.453632, ranking 13th by confidence.

An independent OCaml calculation agreed across 960 document/layer comparisons within \(1.12×10^{-16}\). All six ADR-002 `wiki` hits are outside its substantive body. Removing metadata/navigation alone changes its winner to L1. **Weak coverage and boilerplate interact; “coverage, not boilerplate” is too exclusive.** The exact 56/79 count and synthetic scores need their stripping rule and fixture to be reproducible.

ADR-097 appeared during review; the original 96 documents remained byte-identical.

**Q1. P1 needs a preceding semantic contract.** Define what claiming a layer means: *addresses*, *affects*, *constrains*, or *implements*. These require different evidence. There is already a taxonomy collision: [ADR-010](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-155000-adr-010-seven-level-fractal-granularity-taxonomy-and-100-functional-mapping-kpis.md) calls L1 mesh topology; this module calls it atomic. Its L5 seed also confuses an ADR’s role as a knowledge artifact with its subject.

Then define:

- **Evidenced:** a substantive passage satisfies a named criterion for that relation.
- **Unsupported:** an explicit documentation obligation is unmet, or a reviewer has established absence under the agreed scope.
- **Abstain:** the analyzer cannot decide.

**No lexical match must ordinarily mean abstain.** Otherwise P1 repackages vocabulary blindness as a negative judgment. P2 should promise *reviewable candidates for unjustified tagging*. Neither high cardinality nor missing keywords establishes ritual tagging.

**Q2. My assessment of (a)–(i):**

| Addition | Judgment |
|---|---|
| **a — Tokenization/folding** | Boundary-aware matching is necessary for lexical retrieval; general morphological folding is optional. `NUL` versus `null` needs domain concepts, not blind stemming. Preserve identifiers such as `memchr`. |
| **b — Independent support** | Necessary. Separate thresholds on the existing cosine are insufficient: adding unrelated L4 terms reduced an unchanged L1 fixture’s score from 1.0 to 0.7071 through the shared document norm. |
| **c — Boilerplate excision** | Necessary structural separation, before estimating frequencies. Preserve substantive citations and their locations. Templates vary; this is not literally a constant offset. |
| **d — IDF/90% floor** | Optional. Frequency measures discrimination, not evidential value. A ubiquitous term can still participate in a decisive contextual rule. |
| **e — Abstention** | Necessary, but dead-term counts cannot determine eligibility. Assess demonstrated performance per layer and recognizability of the particular document. |
| **f — Vocabulary repair** | Necessary if lexical retrieval remains. Mine expressions from the corpus; obtain meanings and positive/negative examples from reviewed criteria. Existing tags are not training truth. |
| **g — Calibration** | Drop “confidence” immediately. Probability calibration is optional; measured error at the chosen operating point is necessary. |
| **h — Laws/oracle** | Behavioral laws are necessary. Mojo differential testing is conditional on retaining cosine. Agreement establishes arithmetic, not relevance or support. |
| **i — CLI correction** | Necessary, including downstream consumers. Replace the obsolete proposal schema and entropy comparison with claim/support/abstention counts and explicit denominators. |

Missing prerequisites are **claim extraction, witness provenance, and independently adjudicated examples**. The current [claim scanner](/home/an/NAS-setup/uos/tools/km_provenance/km_corpus.ml:100) searches everywhere and even interprets `#fractal-l10` as L1. A quoted tag or checklist example must not become an author’s claim.

**Q3. Minimum useful version:** a bounded OCaml `--audit-layers` command that produces one row per declared claim:

`layer · relation · verdict · criterion · source passage · reason · content/rubric digest`

It should locate substantive witnesses, explain missing obligations, and invalidate assessments when their evidence changes. Keyword counts can help locate passages; they cannot independently establish an unsupported verdict.

For [ADR-002](/home/an/NAS-setup/uos/docs/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md:18), the review should expose:

- **L1:** documented support—binary truncation, `memchr`, and the explicit `-2` rejection behavior.
- **L6:** abstain pending a defensible ecosystem relationship.
- **L5:** no assessment; it was not claimed.

That gives the reviewer an actionable evidence trail. A ten-score dashboard does not.

**Q4. The failure I most fear is “evidenced” becoming admission evidence.** A document can describe a layer fluently while its implementation claims are false or quarantined. Keyword stuffing could then turn unsupported assertions into apparently verified facts.

Consumers must preserve the distinction between **documented relevance** and **verified behavior**. Also test omitted warnings, false support, stale assessments, and premature withdrawal of valid support. For false admission, FMEA severity is 5 under the repository rubric; occurrence and detection remain unmeasured.

**Q5. Yes: explicit claims with reviewed witnesses are a stronger starting point.** Use a versioned annotation table binding each layer relationship to a rationale, passage, and reviewer decision. Pure OCaml checks references, hashes, completeness, and invalidation. Lexical retrieval remains an optional annotation aid.

This is attractive for roughly a hundred ADRs because semantic decisions become inspectable and reusable. **An existing anchor proves only that text exists**; the relationship still needs a reviewed rule or human judgment. I would test this approach against improved lexical retrieval before assuming its annotation cost pays off. Embeddings alone would not solve the distinction between mentioning something and supporting it.

**Q6. Admission should require both semantic usefulness and implementation evidence:**

- **Reference judgments:** two independent reviewers, evidence spans, recorded disagreements, and an adjudicated rubric. Separate related ADR/template families before tuning vocabulary or thresholds.
- **Behavioral tests:** ADR-002; legitimate support for all ten layers; boilerplate-only documents; keyword stuffing; unseen terminology; quoted tags; missing references; contextual negation. Boilerplate duplication and unrelated layer content must not erase established support. This follows the [behavioral-testing approach](https://aclanthology.org/2020.acl-main.442/), with domain-specific cases.
- **Proposed usefulness bar:** at least 95% observed precision for each automatic verdict, at least 30% non-abstention, and 20% less time in a paired reviewer exercise. Publish per-layer counts and uncertainty; sparsely validated layers remain abstaining.
- **Candidate-bound assurance:** machine-checkable contracts and executed tests for bounded resources, complete claim accounting, deterministic results, read-only behavior, and stale-witness invalidation. Run applicable repository gates and sovereign review. Numerical parity is additional evidence only where that numerical path exists.

I made no filesystem changes and ran no VCS mutations.