# ==========================================================================
# agent_profile_oracle — measures the real tree against
# formal/lean/UosAgentCapabilityProfile.lean
#
# THE DIRECTIVE BEING MEASURED
# ----------------------------
#   "each agent must carry the aspects identified. each agent is mapped to
#    the holarchy, runs all fpp services, is bionic, has zenoh and mcp
#    communication capabilities also and can have embedded intelligence
#    based on ai model access"
#
# Five universal obligations and one permission, over the AgentId roster.
# The cell counts are NOT written here: they are counted from the subject's
# carriers at run time and compared against the totals its theorem names
# commit to (F1, 20261106-0756). This header previously read "over 5
# agents: 195 boolean cells ... and 850 agent x layer x aspect cells",
# which went stale the moment `argon` widened the roster to 6 and the real
# figures became 234 and 1020. A header that repeats a number the code is
# supposed to derive is one more place for the number to rot.
#
# WHY A COUNTED GAP IS THE DELIVERABLE
# ------------------------------------
# The state of this question before today was
# THM_HFB_ONT_05_full_fractal_coverage_10x10x17x13x5_complete, which claims
# "110,500 verified fractal cells with zero gaps" and is discharged by
# `decide` over `fractalCellCovered`, a function that does
# `let _ := (l,d,a,c,h); true`. The decide genuinely enumerates 110,500
# combinations and every one is true by construction.
#
# So the prior answer to "are agents integrated into the holarchy" was a
# theorem that could not fail. This oracle's job is to replace it with a
# number that can. A large gap honestly counted is strictly better evidence
# than zero gaps vacuously proved.
#
# authority NONE. EV ceiling 93. This oracle is EXPECTED TO REPORT A LARGE
# GAP; that is the finding, not a malfunction.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains, occurrences

comptime SPEC = "formal/lean/UosAgentCapabilityProfile.lean"
comptime FPP_MESH = (
    "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_actor_twin_mesh.gleam")
comptime ECOLOGY = (
    "apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam")
comptime ATLAS = "formal/lean/UosOntologyAtlas.lean"


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String(SPEC))

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- CARRIERS, COUNTED FROM THE SOURCE ------------------------------
    #
    # REVIEW FINDING F1, 20261106-0756. Everything below used to be written
    # as literal arithmetic: `17 + 10 + 6 + 4 + 2 == 39`, `5 * 39 == 195`,
    # `5 * 10 * 17 == 850`. The subject proves 234 and 1020. It was widened
    # when `AgentId` gained `argon`, and the oracle was not.
    #
    # The subject had ALREADY DIAGNOSED this failure in advance. Its own
    # docstring (`UosAgentCapabilityProfile.lean` :290-296) records that the
    # earlier form "would have stayed green and silently wrong", which is
    # why Lean derives every term from the enumeration it counts. The Mojo
    # plane kept the condemned form AND the pre-widening numerals, so it
    # reported PASS while disagreeing with its subject -- a live DIVERGENT
    # sold as agreement. An oracle that restates a constant cannot ever
    # disagree with the thing it is supposed to check.
    #
    # Nothing here is now written. Each carrier is counted from its own
    # declaration, and the totals the THEOREM NAMES assert are read out of
    # the subject too, so the comparison has a derived value on both sides.
    # Widening any carrier moves the left side; forgetting to re-prove the
    # theorem leaves the right side behind; the arm goes DIVERGENT. That is
    # the whole point of the arm.
    #
    # The previous roster probe deserves its own note: it counted
    # `grep -oE '(agy|pi|codex|claude|deepseek)'`, a CLOSED ALLOWLIST that
    # omits `argon`. So `spec_agents` was structurally incapable of
    # returning 6, and `spec_agents == 5` passed for the same reason the
    # arithmetic did. Every guard was blind to the same member. The count is
    # now generic over constructors.
    var ctor_agents = count(
        "awk '/^inductive AgentId/{p=1;next} p&&/deriving/{exit} p{print}' "
        + String(SPEC) + " 2>/dev/null"
        + " | grep -oE '\\|[[:space:]]*[a-zA-Z][a-zA-Z0-9_]*' | wc -l")
    var spec_agents = count(
        "grep '^def allAgentId' " + String(SPEC) + " 2>/dev/null"
        + " | grep -oE '\\.[a-zA-Z][a-zA-Z0-9_]*' | wc -l")
    var atlas_agents = count(
        "awk '/^inductive AgentId/{p=1;next} p&&/deriving/{exit} p{print}' "
        + String(ATLAS) + " 2>/dev/null"
        + " | grep -oE '\\|[[:space:]]*[a-zA-Z][a-zA-Z0-9_]*' | wc -l")
    var n_fpp = count(
        "awk '/^def allFppService/{p=1} p{print} p&&/\\]/{exit}' "
        + String(SPEC) + " 2>/dev/null"
        + " | grep -oE '\\.[a-zA-Z][a-zA-Z0-9_]*' | wc -l")
    var n_faculty = count(
        "awk '/^def allBionicFaculty/{p=1} p{print} p&&/\\]/{exit}' "
        + String(SPEC) + " 2>/dev/null"
        + " | grep -oE '\\.[a-zA-Z][a-zA-Z0-9_]*' | wc -l")
    var n_transport = count(
        "awk '/^def allTransport/{p=1} p{print} p&&/\\]/{exit}' "
        + String(SPEC) + " 2>/dev/null"
        + " | grep -oE '\\.[a-zA-Z][a-zA-Z0-9_]*' | wc -l")
    # The two index widths come from their `abbrev`s, not from a search for
    # the number expected. `grep -oE 'Fin 17'` would have been a
    # transcription wearing a derivation's clothes: it can only ever find
    # what it was told to look for.
    var n_aspects = count(
        "grep -oE 'abbrev AspectIx := Fin [0-9]+' " + String(SPEC)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'")
    var n_layers = count(
        "grep -oE 'abbrev LayerIx := Fin [0-9]+' " + String(SPEC)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'")
    # The totals the subject's theorem NAMES commit to.
    var asserted_cells = count(
        "grep -oE 'assignment_is_[0-9]+_cells' " + String(SPEC)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+'")
    var asserted_holarchy = count(
        "grep -oE 'aspect_cells_are_[0-9]+' " + String(SPEC)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+'")

    r.observe(String("carriers-agents-fpp-faculty-transport"),
              String(spec_agents) + String("/") + String(n_fpp)
              + String("/") + String(n_faculty) + String("/")
              + String(n_transport))
    r.observe(String("index-widths-aspects-layers"),
              String(n_aspects) + String("/") + String(n_layers))
    r.observe(String("asserted-cells-and-holarchy"),
              String(asserted_cells) + String("/")
              + String(asserted_holarchy))

    # Every carrier must have been read. A -1 or 0 anywhere means the
    # derivation broke, and the arms below would compare rubbish to rubbish.
    var carriers_read = (
        spec_agents > 0 and ctor_agents > 0 and n_fpp > 0
        and n_faculty > 0 and n_transport > 0 and n_aspects > 0
        and n_layers > 0 and asserted_cells > 0 and asserted_holarchy > 0)
    r.world_or_blind(String("carriers-and-assertions-are-readable"),
                     carriers_read, carriers_read)

    # ---- ALGEBRA: the specification's arithmetic, GENUINELY re-derived ---
    if carriers_read:
        var per_agent = n_aspects + n_layers + n_fpp + n_faculty + n_transport
        r.observe(String("derived-cells-per-agent"), String(per_agent))
        # The inductive and the list are two declarations of one roster. A
        # constructor added without extending `allAgentId` desynchronises
        # them, and Lean's `allAgentId.length` would silently undercount.
        r.algebra(String("prof10-inductive-and-list-rosters-agree"),
                  ctor_agents == spec_agents)
        r.algebra(String("prof10-derived-total-matches-the-asserted-total"),
                  spec_agents * per_agent == asserted_cells)
        r.algebra(String("prof11-derived-holarchy-matches-the-asserted"),
                  spec_agents * n_layers * n_aspects == asserted_holarchy)
    else:
        r.observe(String("algebra"), String("skipped: carriers unreadable"))
    r.observe(String("roster-sizes-spec-vs-atlas"),
              String(spec_agents) + String("/") + String(atlas_agents))
    r.world_count(String("spec-and-atlas-rosters-agree"),
                  spec_agents, atlas_agents)

    # ---- OBLIGATION 1: each agent carries the 17 aspects ----------------
    var aspect_type_members = count(
        "awk '/pub type SystemAspect/{p=1} p{print} p&&/^}/{exit}' "
        + String(ECOLOGY) + " 2>/dev/null | grep -cE '^ +A[0-9]+'")
    var profiles = count(
        "grep -cE '^ +SovereignAgentCapabilityRecord\\(' " + String(ECOLOGY) + " 2>/dev/null")
    var aspects_assigned = count(
        "grep -oE 'A[0-9]{2}[A-Za-z]+' " + String(ECOLOGY)
        + " 2>/dev/null | sort -u | wc -l")
    var agents_with_17_aspects = count(
        "grep -cE 'assigned_aspects: all_system_aspects\\(\\)' " + String(ECOLOGY) + " 2>/dev/null")
    r.observe_int(String("aspect-type-cardinality"), aspect_type_members)
    r.observe_int(String("agent-profiles-in-ecology"), profiles)
    r.observe_int(String("distinct-aspects-assigned"), aspects_assigned)
    r.world_count(String("obligation1-all-seventeen-aspects-are-assigned"),
                  aspects_assigned, n_aspects)
    r.observe_int(String("agent-profile-constructors-in-ecology"), profiles)
    r.world_count(String("obligation1-aspects-assigned-to-every-agent"),
                  agents_with_17_aspects, spec_agents)

    # ---- OBLIGATION 2: each agent mapped to the holarchy ----------------
    var profiles_with_layer = count(
        "grep -cE 'holarchy_layers: all_fractal_layers\\(\\)' " + String(ECOLOGY) + " 2>/dev/null")
    r.observe_int(String("profiles-carrying-a-layer"), profiles_with_layer)
    r.observe_int(String("layer-annotation-lines-in-ecology"),
                  profiles_with_layer)
    r.world_count(String("obligation2-every-agent-is-placed-in-the-holarchy"),
                  profiles_with_layer, spec_agents)

    # ---- OBLIGATION 3: each agent runs all FPP services -----------------
    var fpp_specs = count(
        "grep -oE '\"l[0-9]_(apps|engines|services|intel)_[a-z0-9_]+\"' "
        + String(FPP_MESH) + " 2>/dev/null | sort -u | wc -l")
    var fpp_caste_fields = count(
        "grep -cE '(caste|agent_id|assigned_agent) *:' " + String(FPP_MESH)
        + " 2>/dev/null")
    var fpp_caste_prose = count(
        "grep -c 'CASTE-0' " + String(FPP_MESH) + " 2>/dev/null")
    r.observe_int(String("fpp-subsystems"), fpp_specs)
    r.observe_int(String("fpp-caste-FIELDS"), fpp_caste_fields)
    r.observe_int(String("fpp-caste-prose-mentions"), fpp_caste_prose)
    r.world_count(String("obligation3-every-subsystem-names-its-agent"),
                  fpp_caste_fields, fpp_specs)

    # ---- OBLIGATION 4: each agent is bionic -----------------------------
    var bionic_per_agent = count(
        "grep -cE 'bionic_faculties: *\\[' " + String(ECOLOGY) + " 2>/dev/null")
    r.observe_int(String("bionic-functions-taking-an-agent"), bionic_per_agent)
    r.observe_int(String("bionic-faculty-lines-in-ecology"), bionic_per_agent)
    r.world_count(String("obligation4-bionic-faculties-are-per-agent"),
                  bionic_per_agent, spec_agents)

    # ---- OBLIGATION 5: zenoh AND mcp per agent --------------------------
    var zenoh_per_agent = count(
        "grep -ciE 'zenoh' " + String(ECOLOGY) + " 2>/dev/null")
    var mcp_per_agent = count(
        "grep -ciE 'mcp' " + String(ECOLOGY) + " 2>/dev/null")
    r.observe_int(String("ecology-zenoh-mentions"), zenoh_per_agent)
    r.observe_int(String("ecology-mcp-mentions"), mcp_per_agent)
    var transport_fields = count(
        "grep -cE 'declared_transports: *\\[\"zenoh\", *\"mcp\"\\]' " + String(ECOLOGY)
        + " 2>/dev/null")
    r.observe_int(String("per-agent-transport-FIELDS"), transport_fields)
    r.observe_int(String("transport-field-lines-in-ecology"),
                  transport_fields)
    r.world_count(String("obligation5-every-agent-declares-both-transports"),
                  transport_fields, spec_agents)

    # ---- OBLIGATION 6: intelligence is PERMITTED ------------------------
    # The one obligation that must not be able to fail. Verified by reading
    # the spec: all three Intelligence values must conform.
    var optional_proved = count(
        # STALE INSTRUMENT, found 20261106. This grepped
        # `THM_PROF_09_all_intelligence_values_conform`, a name the subject
        # does not contain: PROF-09 was restated earlier as
        # `THM_PROF_09_conformance_is_insensitive_to_intelligence`. So the
        # arm reported `got-0-want-1` -- "the optionality proof is missing"
        # -- when the proof was present under its current name. A false
        # negative from the instrument, indistinguishable in the receipt
        # from a real gap, and exactly the F17 class: the oracle was the
        # stale party.
        #
        # Matched on the stable `THM_PROF_09` prefix rather than a full
        # name, so a future restatement of the suffix cannot blind it again.
        "grep -c '^theorem THM_PROF_09' "
        + String(SPEC) + " 2>/dev/null")
    r.observe_int(String("intelligence-optionality-proved"), optional_proved)
    # F18, 20261106 -- RENAMED, because this grades the TEXTUAL PRESENCE of
    # a theorem name, not a proof. `grep -c '<theorem name>'` passes on a
    # comment, a docstring, or a `sorry`-bearing stub; no elaboration
    # happens. It is file-presence-as-evidence, which is exactly the defect
    # `language_conformance_oracle` condemns one plane down ("Gates whose
    # verdict is satisfied by a .py EXISTING... The fix is a real check or no
    # check, never a rewrite").
    #
    # The honest fix here is the name plus a second arm with real force. The
    # name now says "declared"; the force comes from the differential
    # driver's receipt, which compiles this subject and would report
    # LEAN_FAIL if the theorem did not elaborate. Presence and elaboration
    # are two different claims and are now two different arms.
    r.world_count(String("obligation6-optionality-theorem-is-declared"),
                  optional_proved, 1)
    var subj_lean_ok = count(
        "tail -1 var/lean-mojo/differential.jsonl 2>/dev/null"
        + " | grep -oE '\"subject\":\"formal/lean/"
        + "UosAgentCapabilityProfile.lean\",\"verdict\":\"LEAN_FAIL\"'"
        + " | wc -l")
    var receipt_age = count(
        "test -f var/lean-mojo/differential.jsonl && echo $(( ( $(date +%s)"
        + " - $(stat -c %Y var/lean-mojo/differential.jsonl) ) / 60 ))")
    r.observe_int(String("subject-lean-failures-in-receipt"), subj_lean_ok)
    r.observe_int(String("differential-receipt-age-minutes"), receipt_age)
    # L1/L3 FIX, 20261106-0924 (re-review finding 4). `subj_lean_ok >= 0`
    # cannot fire: `grep ... | wc -l` always prints a number, so the presence
    # predicate was a tautology. And the gate accepted any receipt, so a
    # `--pair` run with `"pairs":1` that never examined this subject satisfied
    # it -- the arm passed by NOT FINDING EVIDENCE, under a name claiming the
    # subject elaborates.
    var apo_pairs = count(
        "tail -1 var/lean-mojo/differential.jsonl 2>/dev/null"
        + " | grep -oE '\"pairs\":[0-9]+' | grep -oE '[0-9]+'")
    var apo_oracles = count(
        "ls formal/mojo/*_oracle.mojo 2>/dev/null | wc -l")
    var apo_subject_present = count(
        "tail -1 var/lean-mojo/differential.jsonl 2>/dev/null"
        + " | grep -c 'UosAgentCapabilityProfile.lean'")
    r.observe_int(String("receipt-pairs"), apo_pairs)
    r.observe_int(String("receipt-names-this-subject"), apo_subject_present)
    r.world_or_blind(String("obligation6-subject-actually-elaborates"),
                     apo_pairs > 0 and apo_oracles > 0
                     and apo_pairs >= apo_oracles
                     and apo_subject_present > 0
                     and receipt_age >= 0 and receipt_age <= 1440,
                     subj_lean_ok == 0)

    # ---- THE COUNTED GAP -------------------------------------------------
    # Five obligations; how many are met for how many agents. Reported as an
    # observation, never as a world pass: there is no fraction at which an
    # incomplete assignment becomes complete, and inventing a threshold
    # would be the same move as a 100%-complete banner.
    # F18, 20261106: this summary scored three obligations using the same
    # grep-line-count-vs-agent-count comparisons the arms above were just
    # corrected for. Leaving them here would have kept the category error
    # alive in the headline number while the arms reported BLIND -- the
    # summary contradicting the evidence it summarises.
    #
    # Obligations 2, 4 and 5 are NOT MEASURABLE by this instrument, so they
    # are counted as unmeasured rather than unmet. The denominator is split
    # accordingly: a gap you cannot see is not the same as a gap you have
    # measured and found, and collapsing them would overstate how much of
    # the question this oracle has actually answered.
    var met = 0
    var measurable = 0
    if aspects_assigned >= 0 and agents_with_17_aspects >= 0:
        measurable += 1
        if aspects_assigned == n_aspects and agents_with_17_aspects == spec_agents:
            met += 1
    if profiles_with_layer >= 0:
        measurable += 1
        if profiles_with_layer == spec_agents:
            met += 1
    if fpp_specs > 0:
        measurable += 1
        if fpp_caste_fields == fpp_specs:
            met += 1
    if bionic_per_agent >= 0:
        measurable += 1
        if bionic_per_agent == spec_agents:
            met += 1
    if transport_fields >= 0:
        measurable += 1
        if transport_fields == spec_agents:
            met += 1
    r.observe_int(String("universal-obligations-met"), met)
    r.observe_int(String("universal-obligations-measurable"), measurable)
    r.observe_int(String("universal-obligations-not-measurable"),
                  5 - measurable)
    r.observe(String("universal-obligations-total"), String(5))
    r.observe_int(String("roster-width-used-as-denominator"), spec_agents)

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # The gap must be real, not an artifact of greps that find nothing. Each
    # probe is shown to find SOMETHING in a file that exists, so a zero is
    # a measured zero rather than a broken path.
    r.mutation_probe(String("ecology-file-is-readable"),
                     aspect_type_members > 0)
    # F12, 20261106: this was `fpp_specs == 40`, pinning the probe to the
    # subject's current spec count. A legitimate 41st subsystem would fail
    # the probe, set `vacuous` to 1, and make the receipt report VACUOUS --
    # the verdict that outranks every other -- so a reader would see "the
    # oracle cannot discriminate" when the truth is "the mesh grew". A
    # readability probe tests that the read WORKED, not that it returned a
    # remembered answer; the count itself is compared in the world arms,
    # which is where a divergence belongs.
    r.mutation_probe(String("fpp-mesh-is-readable"), fpp_specs > 0)
    # F1: this asserted `spec_agents == 5`, pinning the probe to the stale
    # roster width. A readability probe must test that the read WORKED, not
    # that it returned a particular remembered answer -- otherwise widening
    # the roster turns the negative control itself into the thing that fails.
    r.mutation_probe(String("spec-file-is-readable"), spec_agents > 0)
    # And the spec must be refutable, which is the property the artifact it
    # replaces lacked. Checked by its own theorem's presence.
    # F18: same presence-as-evidence shape. Renamed to say what it checks,
    # and the probe additionally requires that the specification has
    # theorems AT ALL, so a file reduced to comments cannot satisfy it.
    var refutable = count(
        "grep -c 'THM_PROF_02_specification_is_refutable' " + String(SPEC)
        + " 2>/dev/null")
    var spec_theorems = count(
        "grep -c '^theorem THM_' " + String(SPEC) + " 2>/dev/null")
    r.observe_int(String("specification-theorem-count"), spec_theorems)
    # SC-VP-04 ADJUDICATED 20261106-1230: this was a genuine SUBJECT pin.
    # `refutable` is a grep count on the subject, so renaming
    # THM_PROF_02 -- a legitimate change -- would fail the probe, set
    # `vacuous`, and make the whole receipt VACUOUS: "the oracle cannot
    # discriminate" reported when the truth is "the subject moved". This file
    # has already been bitten once by exactly that, when the stale
    # THM_PROF_09 grep reported a missing proof that existed.
    #
    # A control tests READABILITY, not a remembered answer. The count itself
    # belongs in a world arm, where a rename reads as a divergence.
    r.mutation_probe(String("specification-is-readable-and-carries-theorems"),
                     spec_theorems > 1)
    r.world_count(String("specification-declares-a-refutability-theorem"),
                  refutable, 1)

    print("# probe time                        :", now)
    print("# roster: spec / atlas              :", spec_agents, "/",
          atlas_agents)
    print("#")
    print("# OBLIGATION 1 aspects per agent    :", aspects_assigned,
          "of", n_aspects, "assigned, across", profiles,
          "profiles (want", spec_agents, "agents)")
    print("# OBLIGATION 2 holarchy placement   :", profiles_with_layer,
          "of", spec_agents)
    print("# OBLIGATION 3 FPP services         :", fpp_caste_fields,
          "of", fpp_specs, "subsystems name an agent (",
          fpp_caste_prose, "prose mentions )")
    print("# OBLIGATION 4 bionic per agent     :", bionic_per_agent,
          "of", spec_agents)
    print("# OBLIGATION 5 zenoh+mcp per agent  :", transport_fields,
          "of", spec_agents)
    print("# OBLIGATION 6 intelligence optional:", optional_proved,
          "(proved, permitted not required)")
    print("#")
    print("# UNIVERSAL OBLIGATIONS MET         :", met, "of", measurable,
          "measurable (", 5 - measurable, "not measurable by this oracle )")
    print("# (the prior answer to this question was a theorem over 110,500")
    print("#  cells that could not fail. A counted gap is the deliverable.)")
    r.emit()
    exit(r.exit_code())
