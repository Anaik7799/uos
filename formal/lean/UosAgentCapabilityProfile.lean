/-
  UosAgentCapabilityProfile.lean — the capability specification whose gap
  `UosOntologyAtlas.lean` THM_ATLAS_27 sizes.

  CORRECTED 20261106: this opened by citing ATLAS-27 as proving the total
  assignment "does not exist". ATLAS-27's own docstring retracts exactly
  that claim as false — twice over. Reasserting a retracted claim as the
  first sentence of a companion file is a live contradiction between two
  files written hours apart, and it survived because nothing re-read the
  first file when the second was written.

  THE SPECIFICATION BEING FORMALISED
  ----------------------------------
  Operator directive, 2026-11-06:

    "each agent must carry the aspects identified. each agent is mapped to
     the holarchy, runs all fpp services, is bionic, has zenoh and mcp
     communication capabilities also and can have embedded intelligence
     based on ai model access"

  That is six obligations per agent, and five of them are universal while
  the sixth is explicitly optional ("CAN have embedded intelligence"). The
  distinction matters: a profile that made AI access mandatory would exclude
  the Tier-0 deterministic binaries that occupy a caste slot in the live
  runtime, and a profile that made it merely absent could not express that
  an agent is permitted intelligence it does not currently use.

  WHAT THIS FILE IS AND IS NOT
  ----------------------------
  It is a SPECIFICATION with its completeness conditions proved over a
  finite domain. It is NOT a claim that any agent satisfies it.

  CORRECTED 20261106 — the previous version of this paragraph was FALSE.
  It said "ZERO of the 40 FPP subsystem specs carry an agent or caste field
  (`core_fpp_actor_twin_mesh.gleam:395-420`)". A reviewer falsified that
  using the exact line range cited: `role: TaskRole` sits at :404, INSIDE
  that range, and `TaskRole` (core_evolution.gleam:136-142) is exactly the
  five caste roles. `assigned_aspects: List(Int)` is declared at :352 and
  populated for EVERY actor at :425.

  So the specs do carry role and aspect data. Asserting an absence that the
  cited evidence refutes is the worst error available here, because the
  citation made it look checked.

  THE MEASURED TRUTH, which is smaller and sharper: `aspects_for_actor_index`
  returns `[a1]` or `[a1, a2]`, so each of the 40 specs carries ONE OR TWO of
  the 17 aspects. `carriesAllAspects` therefore fails for all 40 — a
  quantified shortfall of 15 or 16 aspects per subsystem, not an absence.
  And the role is a 5-valued TaskRole, not an AgentId, so the FPP→AGENT
  morphism specifically is what is missing.

  So this file's value is that it makes the gap COUNTABLE. The prior state
  was a vacuous coverage theorem -- `fractalCellCovered` discarding all five
  arguments and returning `true` under a `decide` over 110,500 cells. A
  specification that can be unmet is strictly better than a theorem that
  cannot fail.

  No `sorry`, no `axiom`, no `IO`, no recorded observation.
  authority NONE. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV minted.
-/

namespace UOS.AgentCapabilityProfile

/-! ## 1. The carriers -/

/-- The agent roster's terminal object, matching
    `UosOntologyAtlas.lean` `AgentId`.

    STALE JUSTIFICATION, CORRECTED 20261106: this said the duplication was
    necessary because "`formal/lean` has no lakefile". A lakefile now EXISTS
    at `formal/lean/lakefile.toml`, written earlier the same day, and
    Mathlib v4.35.0 is reachable. The duplication is therefore no longer
    forced — it is merely not yet removed, and `tools/lean` (pinned 4.33.0)
    ignores the lakefile, so an import would still fail on the gate path.
    Recorded as a live inconsistency rather than defended. -/
inductive AgentId where
  | agy | pi | codex | claude | deepseek | argon
  deriving DecidableEq, Repr

def allAgentId : List AgentId := [.agy, .pi, .codex, .claude, .deepseek, .argon]

/-- The 17 systems-engineering aspects, by index. The axis registry records
    FOUR incompatible member lists for this axis across the tree, agreeing
    on aspect 03 and little else, so naming the members here would pick a
    winner this file has no standing to pick. Indices are what every plane
    does agree on. -/
abbrev AspectIx := Fin 17

/-- The 10 fractal concern layers, `SC-FRACTAL-TAXONOMY-001` §2. -/
abbrev LayerIx := Fin 10

/-- The FPP service classes an agent must run. Taken from the mesh's own
    `SubsystemFppActorSpec` shape rather than invented. -/
inductive FppService where
  | supervision | typedPort | companionMachine | mcpTool
  | taskRole | intelligenceFocus
  deriving DecidableEq, Repr

def allFppService : List FppService :=
  [.supervision, .typedPort, .companionMachine, .mcpTool,
   .taskRole, .intelligenceFocus]

/-- The bionic faculties, one per bionic object the tree enumerates. -/
inductive BionicFaculty where
  | metabolicRegime      -- 4 regimes
  | immuneBreaker        -- 6 antigens, 3 breaker states
  | shannonArchetype     -- 8 fastpath archetypes
  | lyapunovContraction  -- strict energy descent
  deriving DecidableEq, Repr

def allBionicFaculty : List BionicFaculty :=
  [.metabolicRegime, .immuneBreaker, .shannonArchetype, .lyapunovContraction]

/-- The two mandated transports. Zenoh is the admitted mesh ingress and MCP
    the harness boundary (`SC-HARNESS-MCP-001`); an agent carrying only one
    is reachable by half the system. -/
inductive Transport where
  | zenoh | mcp
  deriving DecidableEq, Repr

def allTransport : List Transport := [.zenoh, .mcp]

/-- Embedded intelligence is OPTIONAL by the directive's own wording.
    `none` is a complete and valid answer -- it is how the Tier-0
    deterministic binaries are expressible at all. -/
inductive Intelligence where
  | none
  | localModel  (modelId : String)
  | remoteModel (modelId : String)
  deriving DecidableEq, Repr

/-! ## 2. The profile -/

structure AgentProfile where
  agent       : AgentId
  /-- Which of the 17 aspects this agent carries. -/
  aspects     : AspectIx → Bool
  /-- Which of the 10 layers this agent is placed at. An agent may span
      layers; the directive says "is mapped to the holarchy", not "to one
      layer". -/
  layers      : LayerIx → Bool
  /-- Which FPP services it runs. -/
  services    : FppService → Bool
  /-- Which bionic faculties it implements. -/
  bionic      : BionicFaculty → Bool
  /-- Which transports it speaks. -/
  transports  : Transport → Bool
  /-- Optional embedded intelligence. -/
  intelligence : Intelligence

/-! ## 3. Conformance, as five total predicates plus one permission

Each is stated so it can FAIL. That is the whole point: the artifact this
replaces could not. -/

def carriesAllAspects (p : AgentProfile) : Bool :=
  (List.finRange 17).all (fun i => p.aspects i)

def mappedToHolarchy (p : AgentProfile) : Bool :=
  (List.finRange 10).any (fun i => p.layers i)

def runsAllFppServices (p : AgentProfile) : Bool :=
  allFppService.all (fun s => p.services s)

def isBionic (p : AgentProfile) : Bool :=
  allBionicFaculty.all (fun f => p.bionic f)

def hasBothTransports (p : AgentProfile) : Bool :=
  allTransport.all (fun t => p.transports t)

/-- REMOVED 20261106. This was
      `def intelligenceIsPermitted (_p : AgentProfile) : Bool := true`
    and it was referenced by NOTHING — one grep hit, its own definition.

    That is, verbatim, the vacuity this file's header condemns in
    `fractalCellCovered`: an argument-discarding constant-true predicate. I
    reintroduced the exact pattern I was replacing, and defended it in the
    docstring as making optionality "a stated part of the contract". A
    definition nothing consults is not part of a contract.

    Optionality is now expressed where it has content: `conformant` does not
    read `intelligence`, and THM_PROF_09 states that insensitivity as the
    property it actually is. -/

def conformant (p : AgentProfile) : Bool :=
  carriesAllAspects p && mappedToHolarchy p && runsAllFppServices p &&
  isBionic p && hasBothTransports p

/-! ## 4. The specification's own properties

These are the theorems a specification owes: that it is satisfiable, that
it is REFUTABLE, and that each conjunct is load-bearing. -/

/-- A fully conformant profile, as the satisfiability witness. -/
def fullProfile (a : AgentId) : AgentProfile :=
  { agent := a
  , aspects := fun _ => true
  , layers := fun _ => true
  , services := fun _ => true
  , bionic := fun _ => true
  , transports := fun _ => true
  , intelligence := Intelligence.none }

/-- **PROF-01 — WEAKENED CLAIM, 20261106.** This enumerates all five agents.
    A reviewer noted `conformant` never reads `p.agent`, so the enumeration
    is ATLAS-01's pattern: a tautology spread over a list. The satisfiability
    content needs only ONE witness, and the 5-way sweep adds nothing.

    Kept in the one-witness form, with the insensitivity stated separately so
    the vacuity is visible rather than hidden in a list. -/
theorem THM_PROF_01_specification_is_satisfiable :
    conformant (fullProfile AgentId.claude) = true := by decide

/-- **PROF-01b.** And conformance is insensitive to which agent it is about,
    which is why PROF-01's old 5-way enumeration carried no information. -/
theorem THM_PROF_01b_conformance_is_insensitive_to_the_agent (a b : AgentId) :
    conformant (fullProfile a) = conformant (fullProfile b) := rfl

/-- **PROF-02 (refutable).** The specification can FAIL. The artifact this
    replaces, `fractalCellCovered`, discarded all five of its arguments and
    returned `true`, so no input could refute it. Exhibiting a
    counterexample is what distinguishes a specification from a banner. -/
theorem THM_PROF_02_specification_is_refutable :
    conformant { fullProfile AgentId.claude with
                 aspects := fun i => i.val != 4 } = false := by decide

/-! ### Each conjunct is independently load-bearing

Five theorems, one per obligation. Without these the conjunction could be
carried by a single clause while the others were decoration — which is
exactly how a 110,500-cell enumeration came to prove nothing. -/

theorem THM_PROF_03_aspects_conjunct_is_load_bearing :
    conformant { fullProfile AgentId.agy with aspects := fun _ => false } = false := by
  decide

theorem THM_PROF_04_holarchy_conjunct_is_load_bearing :
    conformant { fullProfile AgentId.agy with layers := fun _ => false } = false := by
  decide

theorem THM_PROF_05_fpp_conjunct_is_load_bearing :
    conformant { fullProfile AgentId.agy with services := fun _ => false } = false := by
  decide

theorem THM_PROF_06_bionic_conjunct_is_load_bearing :
    conformant { fullProfile AgentId.agy with bionic := fun _ => false } = false := by
  decide

theorem THM_PROF_07_transport_conjunct_is_load_bearing :
    conformant { fullProfile AgentId.agy with transports := fun _ => false } = false := by
  decide

/-- **PROF-08.** A SINGLE missing transport refutes conformance. An agent
    speaking MCP but not Zenoh is reachable through the harness boundary and
    invisible to the mesh; the directive names both, so half is not
    partial credit. -/
theorem THM_PROF_08_one_missing_transport_refutes :
    conformant { fullProfile AgentId.pi with
                 transports := fun t => t == Transport.mcp } = false ∧
    conformant { fullProfile AgentId.pi with
                 transports := fun t => t == Transport.zenoh } = false := by
  constructor <;> decide

/-- **PROF-09 — RESTATED 20261106 after review.** The previous version
    checked three specific `Intelligence` values against one specific agent
    and concluded "intelligence is genuinely optional". A reviewer showed the
    mechanism is simpler and the theorem weaker than its name: `conformant`
    never reads `p.intelligence` at all, so all three conjuncts were the
    SAME Boolean computation — PROF-01 at `codex`, three times.

    The honest statement is FIELD INSENSITIVITY, and it is stronger: for
    EVERY profile and EVERY pair of values, conformance is unchanged. Proved
    by `rfl`, universally quantified, no enumeration. Optionality follows
    from non-consultation, and saying so is what makes a later "tightening"
    visibly a change of contract rather than a clarification. -/
theorem THM_PROF_09_conformance_is_insensitive_to_intelligence
    (p : AgentProfile) (i j : Intelligence) :
    conformant { p with intelligence := i }
      = conformant { p with intelligence := j } := rfl

/-! ## 5. The size of the obligation, counted

The directive is a total assignment over a product of finite sets. Counting
the cells is what turns "agents are not integrated" into a number, and a
number is what can be burned down. -/

/-- **PROF-10.** The full assignment is 6 agents × (17 aspects + 10 layers +
    6 services + 4 faculties + 2 transports) = 6 × 39 = 234 booleans, plus
    6 intelligence values. Stated as arithmetic so the target is explicit.

    PROSE CORRECTED 20261106-0756. This sentence still said "5 agents …
    = 5 × 39 = 195 … plus 5 intelligence values" directly above a theorem
    named `..._is_234_cells`, whose own comment explains the widening. The
    numerals in the STATEMENT were derived and therefore moved; the numerals
    in this PROSE were written and therefore did not. A reader taking the
    docstring at its word would have read 195 off a file that proves 234.
    That is the identical defect the companion Mojo oracle was just repaired
    for, in the same file that diagnosed it — found only because the oracle
    review forced both sides to be read together. -/
theorem THM_PROF_10_assignment_is_234_cells :
    -- RECOUNTED 20261106: 5 agents became 6 when `AgentId` was widened to
    -- admit `argon`, so 195 became 234 and 850 became 1020. BOTH THEOREMS
    -- BROKE when the type changed, which is exactly why the numerals were
    -- made derived rather than written — the earlier version
    -- (`17 + 10 + 6 + 4 + 2 = 39`, `5 * 10 * 17 = 850`) would have stayed
    -- green and silently wrong.
    --
    -- CORRECTED EARLIER: the previous version was `17 + 10 + 6 + 4 + 2 = 39`, which
    -- mentions no carrier and would survive unchanged if `FppService` gained
    -- a constructor. Every term is now derived from the enumeration it
    -- counts, so adding a service BREAKS this theorem, which is the point.
    (List.finRange 17).length + (List.finRange 10).length
      + allFppService.length + allBionicFaculty.length
      + allTransport.length = 39 ∧
    allAgentId.length * 39 = 234 := by
  refine ⟨by decide, by decide⟩

/-- **PROF-11.** And the holarchy cross-product the directive implies —
    every agent at every layer carrying every aspect — is 5 × 10 × 17 = 850
    cells. This is the number `THM_HFB_ONT_05` gestured at with
    10×10×17×13×5 = 110,500 while proving nothing; 850 is the part that
    concerns agents.

    CORRECTED 20261106 — this said "currently unpopulated", which this very
    file retracts in its own header and which the companion atlas now states
    the opposite of. Aspects ARE populated, one or two per subsystem. The
    honest figure is the SHORTFALL, not an absence. Leaving the retracted
    claim alive in a second docstring is the same drift the files are
    written to detect, so it is named rather than quietly edited. -/
theorem THM_PROF_11_agent_layer_aspect_cells_are_1020 :
    -- Likewise derived rather than written: `5 * 10 * 17 = 850` mentioned no
    -- carrier either.
    allAgentId.length * (List.finRange 10).length * (List.finRange 17).length
      = 1020 := by decide

/-! ## 6. What this file does not establish

It does not claim any agent conforms. It does not claim the 17 aspects are
agreed across planes — the axis registry records four incompatible member
lists, which is why aspects are indexed here rather than named. It does not
claim the 5-agent roster is current, only that it is the filtration's
terminal object (`UosOntologyAtlas.lean` ATLAS-20..23).

`formal/mojo/agent_profile_oracle.mojo` measures the real tree against this
specification. The expected result is a large, countable gap, and that is
the deliverable: the previous state of this question was a theorem that
could not fail. -/

/-! ## 7. Enumeration completeness — the guard this file did not have

Every quantified theorem above ranges over a HAND-WRITTEN list, never over
the type: `carriesAllAspects` over `List.finRange 17`, `runsAllFppServices`
over `allFppService`, `isBionic` over `allBionicFaculty`, `hasBothTransports`
over `allTransport`, and PROF-01/PROF-10 over `allAgentId`. Not one of those
lists was proved exhaustive.

That is not hypothetical here. `AgentId` was widened from five constructors
to six on 2026-11-06 to admit `argon`. If `allAgentId` had not been widened
in the same edit, PROF-01 would still have proved "every agent conforms"
while silently quantifying over five of six agents, and nothing would have
failed. The lemmas below make that failure mode a compile error instead.

They are the same obligation `UosOntologyAtlas.lean` ATLAS-28..32, 36 and 37
discharge for its own charts. Plain `decide` does NOT suffice: without
Mathlib there is no `Fintype`/`DecidableForall` instance on these
inductives, so `by decide` alone fails with "Expected type must not contain
free variables". `cases x <;> decide` is the working form.

authority NONE. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV minted. -/

/-- **PROF-12.** `allAgentId` is exhaustive of `AgentId`. This is the one
    that would have caught the `argon` widening: it fails to compile if a
    constructor is added to the type and not to the list. -/
theorem THM_PROF_12_allAgentId_is_exhaustive (a : AgentId) :
    allAgentId.contains a = true := by cases a <;> decide

/-- **PROF-13.** `allFppService` is exhaustive of `FppService`, so
    `runsAllFppServices` quantifies over every service class rather than
    over the six that happen to be listed. -/
theorem THM_PROF_13_allFppService_is_exhaustive (f : FppService) :
    allFppService.contains f = true := by cases f <;> decide

/-- **PROF-14.** `allBionicFaculty` is exhaustive of `BionicFaculty`. -/
theorem THM_PROF_14_allBionicFaculty_is_exhaustive (b : BionicFaculty) :
    allBionicFaculty.contains b = true := by cases b <;> decide

/-- **PROF-15.** `allTransport` is exhaustive of `Transport`. Without this,
    PROF-08's "a single missing transport refutes conformance" would be a
    claim about two listed transports, not about the transport type — and a
    third transport added to the type would be unguarded by `conformant`
    while PROF-08 continued to pass. -/
theorem THM_PROF_15_allTransport_is_exhaustive (t : Transport) :
    allTransport.contains t = true := by cases t <;> decide

/-- **PROF-16 (the lists have the lengths the counting theorems assume).**
    PROF-10 asserts `17 + 10 + 6 + 4 + 2 = 39`. Three of those five numerals
    are list lengths, and with PROF-12..15 they are now tied to their types
    rather than asserted alongside them. Stated together so a widened type
    breaks the arithmetic instead of silently invalidating it. -/
theorem THM_PROF_16_enumeration_lengths_match_the_counting_theorems :
    allAgentId.length = 6 ∧
    allFppService.length = 6 ∧
    allBionicFaculty.length = 4 ∧
    allTransport.length = 2 := by
  refine ⟨by decide, by decide, by decide, by decide⟩

end UOS.AgentCapabilityProfile
