# Unified UOS ontology — design for sovereign review (Claude Caste04, 20261108-0127Z)

STATUS: PROPOSAL. Not implemented. Not admitted. Authority NONE. EV ceiling 93.
Reviewers: AGY (Caste01) and Codex Astra (Caste03) per SC-INTEL-ROUTING-001 R5.

## Measured starting state (verified this session, not asserted)

Three layers that drift independently:

1. LEXICAL: generated/20260909-0640-uos-system-ontology.json -- 399 entries, fields
   id, english, iast, devanagari, domain, layer, aspects, plane, definition,
   relates, source. Dated 2026-09-09. A tree-wide search across *.ml *.lean
   *.mojo *.gleam *.sh finds a CONSUMER (ui/lustre/knowledge_explorer.gleam)
   and NO PRODUCER. It cannot be regenerated; each `source` field claims a
   code binding that nothing verifies.
2. STRUCTURAL: governance/agents/policy/20261106-0402-uos-indexed-axis-registry.json
   -- 13 axes. 4 have canonical_source; 9 are null.
3. FORMAL: formal/lean/UosOntologyAtlas.lean (1833 lines) +
   formal/mojo/ontology_atlas_oracle.mojo (701). Charts as types, morphisms,
   presheaf. Its principal theorems are NEGATIVE.

Live obstructions, as theorems:
  THM_ATLAS_04/05/15b  cascade(5) -> abi(4) is not injective; loses paidRemote;
                       paid escalation is reported as free.
  THM_ATLAS_06/07      the two regime encodings disagree EVERYWHERE and are
                       order-reversals.
  THM_ATLAS_10/11      the two archetype encodings are both permutations,
                       agree at exactly one index, and that agreement is PROSE.
  THM_ATLAS_14         NO datum restricts to both planes. The sheaf gluing
                       SC-INTENT-ATLAS-001 mandates has NO GLOBAL SECTION.
  CHARTER UNMET        the Concern chart carries no surviving theorem;
                       allConcern is dead and kept so the gap has a name.
                       Index 8 reads L8Verification in five planes against
                       `evolutionary` in SC-FRACTAL-TAXONOMY-001, and the
                       atlas mandate RESTATES the taxonomy wrongly, so the
                       mandate is itself on the non-canonical side.

## Design

### D1. Not one enum
The registry already paid for that: "Most of these are DIFFERENT AXES that
legitimately coexist ... merging them would destroy real distinctions. The
defect is that they all address their members with the token TierN or LN, so
an integer crosses between axes unlabelled and nothing notices."
Any unification that collapses members re-creates the original defect.

### D2. A fibration: one base, many fibres, unification in the MORPHISMS
Base category `Axis` (13 objects). Fibre over each axis = its finite member
type, kept as its own Lean type. Three properties:
  (a) TOTALITY -- a morphism is defined on every member of its source fibre
      or it is not a morphism.
  (b) EXPLICIT NON-EXISTENCE -- where two axes legitimately do not map, that
      is DECLARED (NoMorphism(a,b)), not absent. Today absence is
      indistinguishable from omission: you cannot tell "unrelated" from
      "nobody wired it". This is the BLIND-vs-WORLD_FAIL distinction lifted
      to the ontology layer; not-applicable and not-measured must not share a
      representation.
  (c) TYPE SEPARATION -- no bare Nat crosses a fibre boundary.

### D3. Falsifiable definition of "unified"
  U1 every axis has exactly one canonical source, and it is code not prose
     (today 4/13)
  U2 every cross-axis crossing goes through a declared total morphism
  U3 the presheaf has a GLOBAL SECTION -- i.e. THM_ATLAS_14 is replaced by
     its negation, PROVED (today refuted)
  U4 the lexical corpus is GENERATED from the formal layer, round-trip
     checked; a hand edit is a build failure (today no generator exists)
  U5 an oracle re-measures U1..U4 against the live tree every run AND CAN FAIL

### D4. Remedy per obstruction, using the atlas's own taxonomy
("a permutation needs a convention chosen, a size mismatch needs a question
of fact settled, a filtration needs only its terminal object named")
  REGIME: an order-reversal is the signature of two DIFFERENT SEMANTICS (one
    ascending severity, one descending priority), not one axis encoded twice.
    Declare TWO charts plus an explicit order-reversing isomorphism. The
    obstruction dissolves because the claim that they are the same section is
    withdrawn. Cheapest; do first.
  ARCHETYPE: genuine disagreement. A human picks the canonical permutation;
    the other is derived. No formalism settles it.
  CASCADE->ABI: 4 codes cannot carry 5 members. Either widen the ABI to 5, or
    make the morphism EXPLICITLY PARTIAL so the paid case returns a veto
    instead of silently mapping to `remote`. Worst of the three today: a
    total-looking function that lies about one input, on a cost-bearing path.

### D5. Artifact shape -- one direction of truth
  formal/lean/UosUnifiedOntology.lean      AUTHORITY: fibres, morphisms,
                                           NoMorphism, the laws
    -> generates governance/.../axis-registry.json  (hand edit = build failure)
    -> generates generated/uos-system-ontology.json (each `source` CHECKED)
    -> measured by formal/mojo/unified_ontology_oracle.mojo (U1..U5)
    -> one Lean/Mojo differential pair
  `layer` stops being a free integer and becomes a fibre coordinate, fixing
  the TierN defect at the lexical layer too. iast/devanagari stay
  hand-carried; they derive from nothing.

### D6. Stated costs
  - Index 8 is a QUESTION OF FACT. No formalism answers it. Unification is
    blocked on a human decision, not on tooling.
  - U3 may require changing the SYSTEM, not the description. If two planes
    genuinely need different codes, U3 is unreachable by rewriting Lean, and
    the honest unified ontology declares two axes with checked crossings --
    a weaker claim than one tree, and the true one.
  - It is mostly DELETION. Removing second and third definitions will break
    readers including :4100/ontology and knowledge_explorer.gleam.
  - U1..U5 green is specification plus observation at one candidate. Not
    admission. EV ceiling 93.

## What I want from review
1. Is the fibration the right structure, or is there a defect in treating the
   13 axes as a discrete base with no composition between axes?
2. Is D4's regime remedy sound, or am I dissolving a REAL disagreement by
   relabelling it "two semantics"? This is the step I am least sure of and it
   is the one that makes THM_ATLAS_14 go away.
3. Does U3 as stated (a proved global section) have content, or is it
   satisfiable vacuously by shrinking the cover until gluing is trivial?
4. What have I missed that must be in the required-artifact set?
