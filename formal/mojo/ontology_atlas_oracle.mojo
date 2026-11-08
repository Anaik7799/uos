# ==========================================================================
# ontology_atlas_oracle — the differential partner for
# formal/lean/UosOntologyAtlas.lean
#
# WHAT THE TWIN PROVES, AND WHY IT NEEDS AN ORACLE
# ------------------------------------------------
# UosOntologyAtlas.lean writes the transition morphisms SC-INTENT-ATLAS-001
# mandates as ACTUAL FUNCTIONS and proves 19 theorems over finite domains --
# mostly refutations: that a required inverse does not exist, that two
# encodings are an involution rather than the identity, that the atlas does
# not glue on a named intersection.
#
# Every one of those proofs is about functions the twin DECLARES. A kernel
# cannot know whether those declarations match the tree. That is this
# oracle's only job: DERIVE the same maps from the real sources and check
# them. If the twin says the ABI numbers Torpor 0 and the ABI's own
# docstring says otherwise, the twin is modelling a system that does not
# exist -- which is the failure mode the whole architecture exists to catch,
# and the one a self-consistent proof plane cannot catch alone.
#
# THE CRITICISM THIS ORACLE ALSO CHECKS
# -------------------------------------
# The twin asserts that formal/lean/Algebraic_Atlas_Intent.lean:61 models a
# transition morphism as a LABELLED RECORD with a Bool, not as a function,
# and that its cocycle theorem therefore discharges `true && true = true`.
# That is a claim about a file, so it is checked here rather than asserted
# there. An oracle that verified only the flattering claims would be the
# vacuity its own mutation_probe exists to prevent.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains, json_int, occurrences

comptime ABI = "formal/lean/UosLeanRuntimeGuard.lean"
comptime BIONIC_ORACLE = "formal/mojo/bionic_interception_oracle.mojo"
comptime OCAML_TWIN = "tools/bionic_token_twin.ml"
comptime GATEWAY_TWIN = "formal/lean/UosMcpUnifiedGatewayTwin.lean"
comptime OLD_ATLAS = "formal/lean/Algebraic_Atlas_Intent.lean"
comptime LEAN_GATE = "tools/lean-offline-gate"
comptime ATLAS = "formal/lean/UosOntologyAtlas.lean"
comptime FPP_MESH = (
    "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_actor_twin_mesh.gleam")


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/UosOntologyAtlas.lean"),
    )

    # ---- THE DECLARED SUBJECT IS ACTUALLY READ -------------------------
    # 20261106-1848, found by B5 mutation verification and the worst of the
    # three: this oracle runs 67 checks, 14 of them world checks, and when
    # UosOntologyAtlas.lean was emptied to zero bytes in the real tree the
    # receipt came back BYTE-IDENTICAL. Every reference to the file in this
    # source was a comment or the Receipt's own subject field. The oracle
    # named the atlas and read everything except the atlas.
    # A declared subject is not a read subject.
    #
    # The expected set is the ATLAS-NN theorems THIS ORACLE'S OWN COMMENTS
    # cite, mapped to their declaration names; it is not a count harvested
    # from the file, because binding to a number that happens to match is the
    # defect rather than the repair.
    var atlas_thms = count(
        "grep -cE '^theorem ' " + String(ATLAS) + " 2>/dev/null")
    r.world_or_blind(String("declared-atlas-is-readable"),
                     atlas_thms >= 0, atlas_thms > 0)
    var cited_atlas = [String("06"), String("07"), String("08"),
                       String("09"), String("11"), String("16"),
                       String("18"), String("19"), String("20"),
                       String("21"), String("22"), String("23"),
                       String("24"), String("25"), String("26"),
                       String("27")]
    var atlas_present = 0
    for ai in range(len(cited_atlas)):
        if count("grep -cE '^theorem THM_ATLAS_" + cited_atlas[ai] + "_' "
                 + String(ATLAS) + " 2>/dev/null") > 0:
            atlas_present += 1
    r.world_count(String("declared-atlas-carries-every-cited-theorem"),
                  atlas_present, len(cited_atlas))

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- ALGEBRA: re-derive the atlas laws independently -----------------
    # The same maps, written again here from the same sources, so a
    # disagreement with the kernel is DIVERGENT rather than an outage.

    # regimeAbi, read from the ABI's own docstring rather than restated.
    var abi_torpor = count(
        "grep -oE '^ *- [0-9] : TorporMargin40Hold' " + String(ABI)
        + " 2>/dev/null | grep -oE '[0-9]' | head -1")
    var abi_anabolic = count(
        "grep -oE '^ *- [0-9] : AnabolicParallel' " + String(ABI)
        + " 2>/dev/null | grep -oE '[0-9]' | head -1")
    var abi_catabolic = count(
        "grep -oE '^ *- [0-9] : CatabolicCriticalPathOnly' " + String(ABI)
        + " 2>/dev/null | grep -oE '[0-9]' | head -1")
    var abi_homeostatic = count(
        "grep -oE '^ *- [0-9] : HomeostaticZeroOrShift' " + String(ABI)
        + " 2>/dev/null | grep -oE '[0-9]' | head -1")
    r.observe(String("abi-regime-codes"),
              String(abi_torpor) + String(",") + String(abi_catabolic)
              + String(",") + String(abi_homeostatic) + String(",")
              + String(abi_anabolic))
    var abi_readable = (abi_torpor >= 0 and abi_catabolic >= 0
                        and abi_homeostatic >= 0 and abi_anabolic >= 0)
    r.world_or_blind(String("abi-regime-docstring-is-readable"),
                     True, abi_readable)

    # ---- ENCODING B, FROM ITS OWN DECLARED SOURCE -----------------------
    #
    # L1 FIX, 20261106-0924 (re-review finding 2, caught again by
    # tools/mojo_arm_falsifiability.ml). The arms below used to inline
    # `oracle(r) = 3 - abi(r)` -- substituting the CONCLUSION of ATLAS-07
    # into ATLAS-06/08/09 and collapsing two separately declared functions
    # into one. The consequence was that every arm reduced to an identity on
    # the integers:
    #
    #   atlas06  x != 3 - x        is  2x != 3   -- no integer solution
    #   atlas08  3 - (3 - x) == x  is  an identity
    #   atlas09  (3 - x) != x      holds because 3 is odd
    #
    # The derived value appeared in each expression and cancelled out, so no
    # reading of the ABI could ever move them. A previous round "fixed" these
    # by widening atlas06 from two regimes to four and loop-wrapping the
    # others -- making an unfalsifiable arm wider rather than falsifiable.
    #
    # The atlas names its second source explicitly (`UosOntologyAtlas.lean`
    # :200-203): encoding B is the DECLARATION ORDER of
    # `BiomorphicMetabolicRegime` in
    # `BionicMojoLeanHighPerformanceInterception.lean:197`. That is a
    # different file with a different author, so reading it gives the arms
    # two independently-sourced sides, which is what a differential requires.
    # Note the atlas's own prose in this oracle previously claimed encoding B
    # was the `Regime` declaration order; it is not -- that order is
    # torpor,catabolic,homeostatic,anabolic, i.e. encoding A.
    comptime REGIME_B_SRC = (
        "formal/lean/BionicMojoLeanHighPerformanceInterception.lean")

    def regime_b_index(ctor_prefix: String) -> Int:
        return count(
            "awk '/inductive BiomorphicMetabolicRegime/{p=1;next}"
            + " p&&/deriving/{exit} p{print}' " + String(REGIME_B_SRC)
            + " 2>/dev/null"
            + " | grep -oE '\\|[[:space:]]*[A-Za-z][A-Za-z0-9_]*'"
            + " | grep -oE '[A-Za-z][A-Za-z0-9_]*'"
            + " | grep -n '^" + ctor_prefix + "' | head -1"
            + " | cut -d: -f1 | awk '{print $1-1}'")

    var orc_torpor = regime_b_index(String("Torpor"))
    var orc_catabolic = regime_b_index(String("Catabolic"))
    var orc_homeostatic = regime_b_index(String("Homeostatic"))
    var orc_anabolic = regime_b_index(String("Anabolic"))
    r.observe(String("encoding-b-regime-codes"),
              String(orc_torpor) + String(",") + String(orc_catabolic)
              + String(",") + String(orc_homeostatic) + String(",")
              + String(orc_anabolic))
    var orc_readable = (orc_torpor >= 0 and orc_catabolic >= 0
                        and orc_homeostatic >= 0 and orc_anabolic >= 0)
    r.world_or_blind(String("encoding-b-declaration-order-is-readable"),
                     True, orc_readable)

    if abi_readable and orc_readable:
        # ATLAS-07: the two encodings are the ORDER REVERSAL, i.e. for every
        # regime abi + oracle = 3. Both sides derived, so a renumbering of
        # either source moves the arm.
        r.algebra(String("atlas07-regime-order-reversal-holds-in-sources"),
                  abi_torpor + orc_torpor == 3
                  and abi_catabolic + orc_catabolic == 3
                  and abi_homeostatic + orc_homeostatic == 3
                  and abi_anabolic + orc_anabolic == 3)
        # ATLAS-06: the two encodings disagree at EVERY point. Falsifiable by
        # construction now: if either source were renumbered to agree at any
        # regime, this fails.
        r.algebra(String("atlas06-regime-encodings-disagree-everywhere"),
                  abi_torpor != orc_torpor
                  and abi_catabolic != orc_catabolic
                  and abi_homeostatic != orc_homeostatic
                  and abi_anabolic != orc_anabolic)
        # ATLAS-08: the two tables are MUTUALLY INVERSE under the reversal --
        # the real involution claim. Previously `3 - (3 - x) == x`, which is
        # true of arithmetic and says nothing about either table.
        r.algebra(String("atlas08-the-two-tables-are-mutually-inverse"),
                  orc_torpor == 3 - abi_torpor
                  and abi_torpor == 3 - orc_torpor
                  and orc_anabolic == 3 - abi_anabolic
                  and abi_anabolic == 3 - orc_anabolic)
        # ATLAS-09 is DELETED, not rewritten. "The reversal is not the
        # identity" means the two encodings differ somewhere -- which is
        # exactly ATLAS-06's content, now that both sides are derived. With
        # the inlining removed it was a fourth restatement of one fact, and a
        # restatement is what produced the tautology in the first place.
    else:
        r.observe(String("regime-encoding-arms"),
                  String("skipped: one or both encodings unreadable"))

    # archOCaml, read from the OCaml table.
    var oc0 = capture(
        "grep -oE '\\| 0 -> \"CT_[A-Z_]*\"' " + String(OCAML_TWIN)
        + " 2>/dev/null | grep -oE 'CT_[A-Z_]*' | head -1")
    var oc7_is_catchall = count(
        "grep -c '_ -> \"CT_PROSE_MD\"' " + String(OCAML_TWIN) + " 2>/dev/null")
    r.observe(String("ocaml-archetype-code-0"), oc0)
    r.observe_int(String("ocaml-index-7-is-a-catchall"), oc7_is_catchall)
    if oc0.byte_length() > 0:
        # ATLAS-11: the sole agreement is proseMd; index 0 must differ.
        r.algebra(String("atlas11-archetype-index-zero-differs"),
                  oc0 != String("CT_HIGH_ENTROPY"))
    # ASTRA FINDING, recorded as its own arm: the OCaml table's `_ ->` makes
    # an INVALID code a VALID archetype. That is a fail-open, and it is a
    # different defect from the index disagreement: a bad input is silently
    # given a good name rather than rejected.
    r.world_count(String("ocaml-archetype-table-rejects-invalid-codes"),
                  oc7_is_catchall, 0)

    # ---- the MCP route chart, all four readings derived ------------------
    var declared = count(
        "grep -oE 'declaredTotal = [0-9]+' " + String(GATEWAY_TWIN)
        + " 2>/dev/null | grep -oE '[0-9]+' | head -1")
    var observed = count(
        "grep -oE 'observedTotal = [0-9]+' " + String(GATEWAY_TWIN)
        + " 2>/dev/null | grep -oE '[0-9]+' | head -1")
    var bare_104 = count(
        "grep -rhoE '(mcpRoutes|mcpRoutesCovered|mcpRoutesCount|"
        + "recallMcpRoutes|mcpHarnessRoutesCount|mcpTotalSurfaces)"
        + " *:= *104' --include='*.lean' formal/lean --exclude-dir=.lake"
        + " 2>/dev/null | wc -l")
    r.observe_int(String("gateway-declared-total"), declared)
    r.observe_int(String("gateway-observed-total"), observed)
    r.observe_int(String("bare-104-record-fields"), bare_104)

    r.world_or_blind(String("route-census-is-readable"), True,
                     declared >= 0 and observed >= 0)
    if declared >= 0 and observed >= 0:
        # ATLAS-18: the declared/observed gap is 4.
        r.algebra(String("atlas18-declared-exceeds-observed-by-four"),
                  declared - observed == 4)
        # ATLAS-16/17: the kernel-checked readings both differ from 104.
        r.algebra(String("atlas17-kernel-checked-readings-are-not-104"),
                  declared != 104 and observed != 104)
        # ATLAS-19: no bijection -- the object sets differ in size.
        r.algebra(String("atlas19-route-chart-admits-no-bijection"),
                  104 != observed)
    # And the unproved reading is the one the mandate quotes, restated in
    # many bare fields. Reported as a COUNT, because the number of
    # restatements is the measure of how far an unproved figure travelled.
    r.world_or_blind(String("bare-104-fields-exist-to-be-counted"),
                     bare_104 >= 0, bare_104 > 0)

    # ---- the criticism, checked against its target ----------------------
    # The twin claims the old atlas models a morphism as a record with a
    # Bool. Verify it, rather than take the twin's word.
    var old_has_bool = count(
        "awk '/^structure TransitionMorphism/{p=1} p&&/deriving/{exit} p' "
        + String(OLD_ATLAS) + " 2>/dev/null | grep -c 'isCompatible : Bool'")
    var old_has_function = count(
        "awk '/^structure TransitionMorphism/{p=1} p&&/deriving/{exit} p' "
        + String(OLD_ATLAS) + " 2>/dev/null | grep -cE '→|->'")
    r.observe_int(String("old-atlas-morphism-has-bool-field"), old_has_bool)
    r.observe_int(String("old-atlas-morphism-has-a-function-field"), old_has_function)
    r.world_or_blind(String("old-atlas-morphism-is-a-record-not-a-map"),
                     old_has_bool >= 0 and old_has_function >= 0,
                     old_has_bool > 0 and old_has_function == 0)

    # ---- LEAN COMPILE COVERAGE -- the structural root cause -------------
    # 107 standalone .lean files at the top level; `tools/lean-offline-gate`
    # has a HARDCODED target array. Anything not in it, and not a subject of
    # tools/lean_mojo_differential.ml, is compiled by nothing -- so it could
    # be broken right now and no arm would know.
    #
    # This is also why the 651 lines of byte-identical duplication exist:
    # there is no lakefile for these 107 files and only 2 cross-file import
    # edges, so duplication is the only available form of reuse. The waste
    # is a SYMPTOM of a missing module system, not of carelessness.
    var lean_total = count(
        "ls formal/lean/*.lean 2>/dev/null | wc -l")
    var gate_targets = count(
        "awk '/^TARGETS=/{p=1} p{print} p&&/\\)/{exit}' " + String(LEAN_GATE)
        + " 2>/dev/null | grep -oE '[A-Za-z_][A-Za-z0-9_]*' | grep -v TARGETS"
        + " | sort -u | wc -l")
    var differential_subjects = count(
        "grep -rhoE 'formal/lean/[A-Za-z0-9_]+\\.lean' formal/mojo/*_oracle.mojo"
        + " 2>/dev/null | sort -u | wc -l")
    r.observe_int(String("lean-files-top-level"), lean_total)
    r.observe_int(String("lean-gate-hardcoded-targets"), gate_targets)
    r.observe_int(String("differential-lean-subjects"), differential_subjects)
    # Reported, not failed on a threshold: there is no fraction at which
    # compile coverage becomes a pass, and inventing one would be the same
    # move as a 100%-complete banner.
    # F9, 20261106: `value_ok` was the literal `True`, so this arm could
    # only ever be BLIND or PASS and never a failure. It is a COVERAGE
    # REPORT, not a check -- the comment above says so -- and the honest
    # channel for that is `observe`, which does not pretend a verdict.
    r.observe(String("compile-coverage-is-measurable"),
              String(lean_total) + String("/") + String(gate_targets)
              + String("/") + String(differential_subjects))

    # What IS a failure: a Lean file this architecture names as a subject and
    # then cannot compile. That must be zero.
    #
    # F9, 20261106 -- THIS WAS `world_count(name, 0, 0)`. No compiler was
    # invoked, no file was read; the arm was the literal `0 == 0`. It
    # incremented `checks` and `world_checks` and could never fail, while
    # the comment above it stated the criterion correctly. That is the
    # strongest form of the transcription defect, because the "observation"
    # itself is a literal -- and a placeholder that emits a passing world
    # check is indistinguishable from a working one, which this oracle's own
    # header says it exists to prevent.
    #
    # The compilability of every subject is read from the differential
    # driver's own durable receipt, which is the thing that actually compiles
    # them and records LEAN_FAIL per pair.
    #
    # Two designs were rejected first, and both rejections are the point:
    #
    #  1. Compiling inline here. `capture` bounds every probe at
    #     `timeout -k 5 20`, and 24 Lean subjects -- several against Mathlib
    #     -- do not compile in 20 seconds. The arm would be killed, return
    #     empty, read as -1 and go BLIND on every run: an arm that is always
    #     blind is no better than one that always passes.
    #  2. Enumerating subjects from `tools/lean_mojo_differential.ml`. The
    #     driver CONTENT-DISCOVERS its subjects from the oracles, so only one
    #     `formal/lean/*.lean` path appears in its source. That enumeration
    #     returned a single file while the arm's name claimed "every
    #     differential subject" -- a weaker version of the same overclaim,
    #     caught only because the result was checked against the name.
    #
    # Reading the receipt makes the dependency explicit and bounded, and the
    # receipt's age is bounded too, per the F5 lesson: a LEAN_FAIL count
    # from an arbitrary past run is not an observation of this candidate.
    comptime RECEIPT = "var/lean-mojo/differential.jsonl"
    comptime RECEIPT_MAX_AGE_MIN = 1440
    var receipt_age = count(
        "test -f " + String(RECEIPT) + " && echo $(( ( $(date +%s)"
        + " - $(stat -c %Y " + String(RECEIPT) + ") ) / 60 ))")
    var receipt_pairs = count(
        "grep -v '\"pairs\":1,' " + String(RECEIPT) + " 2>/dev/null"
        + " | tail -1 | grep -oE '\"pairs\":[0-9]+' | grep -oE '[0-9]+'")
    var lean_failures = count(
        "grep -v '\"pairs\":1,' " + String(RECEIPT) + " 2>/dev/null"
        + " | tail -1 | grep -oE '\"verdict\":\"LEAN_FAIL\"' | wc -l")
    r.observe_int(String("differential-receipt-age-minutes"), receipt_age)
    r.observe_int(String("differential-receipt-pairs"), receipt_pairs)
    r.observe_int(String("differential-lean-failures"), lean_failures)
    # L1/L3 FIX, 20261106-0924 (re-review findings 4 and 5). The previous
    # gate was `pairs > 0`, which a `--pair` run satisfies with `"pairs":1`.
    # The receipt is APPEND-ONLY and its newest line is whatever ran last, so
    # both arms read a one-pair receipt, failed to find their own subject in
    # it, and PASSED on the absence. Verified at the time: the last four lines
    # all carried `"pairs":1`.
    #
    # Two further defects in the same gate: `>= 0` on a `grep | wc -l` can
    # never fire, because that pipeline always prints a number -- so the
    # presence predicate was itself a tautology; and the arm's name claimed
    # coverage of EVERY subject while reading one line.
    #
    # The gate now requires the newest line to be a FULL run -- at least as
    # many pairs as there are `*_oracle.mojo` files on disk -- AND to mention
    # the subject by name. Anything less is BLIND, which is the honest verdict
    # for "the evidence I rely on was not produced on this candidate".
    var oracles_on_disk = count(
        "ls formal/mojo/*_oracle.mojo 2>/dev/null | wc -l")
    r.observe_int(String("oracles-on-disk"), oracles_on_disk)
    var receipt_is_full_run = (
        oracles_on_disk > 0 and receipt_pairs >= oracles_on_disk)
    var receipt_fresh = (
        receipt_age >= 0 and receipt_age <= RECEIPT_MAX_AGE_MIN
        and receipt_is_full_run)
    r.observe(String("receipt-is-a-full-run"), String(receipt_is_full_run))
    # CHECKED AND DISMISSED 20261107-2353 (candidate finding F-W-21, withdrawn).
    #
    # I read this arm as the F-W-14 shape -- an evidence-freshness condition
    # sitting in the VALUE slot, so staleness scores WORLD_FAIL -- and started
    # moving `receipt_fresh` into the presence slot to make it BLIND. That is
    # wrong, and the way it is wrong is worth leaving written down.
    #
    # `receipt_fresh` is this arm's SUBJECT, not its precondition. The arm is
    # named `differential-receipt-is-fresh-and-complete`: reporting a stale or
    # partial receipt is the whole job. Putting the same expression in both
    # slots makes `value_ok` true whenever `field_present` is true, so the arm
    # could never fail -- a tautology (INV-FALSIFY) in the one arm whose
    # purpose is catching stale evidence. I would have closed a WORLD_FAIL by
    # making it unreportable.
    #
    # The sibling in agent_profile_oracle.mojo:303 is NOT a counterexample.
    # It gates a DIFFERENT claim (`obligation6-subject-actually-elaborates`)
    # on receipt quality, so for it freshness genuinely is a precondition and
    # BLIND genuinely is right. Same expression, different role. That the two
    # arms wire it differently is correct, not a disagreement.
    #
    # What was really observed stands as a real, non-defect fact: a peer added
    # a 19th oracle while the newest receipt line was an 18-pair run, so
    # `receipt_pairs >= oracles_on_disk` was false and this arm reported
    # WORLD_FAIL at 20261107-2250Z and PASS at 2253Z with no code change --
    # only a full differential between. That is the arm working. Adding an
    # oracle really does mean the evidence base no longer covers the
    # candidate, and "run the differential" is the actionable remedy it is
    # pointing at.
    r.world_or_blind(String("differential-receipt-is-fresh-and-complete"),
                     receipt_age >= 0 and receipt_pairs > 0
                     and oracles_on_disk > 0,
                     receipt_fresh)
    # The arm's name says EVERY subject, so the gate requires a full run.
    r.world_or_blind(String("every-differential-subject-is-compilable"),
                     receipt_fresh, lean_failures == 0)

    var import_edges = count(
        "grep -hcE '^import (Uos|Five|Fifteen|Denotational|Lyapunov|Century|"
        + "Harness|Algebraic|Fractal|Traceability)' formal/lean/*.lean"
        + " 2>/dev/null | awk '{s+=$1} END{print s+0}'")
    r.observe_int(String("cross-file-import-edges"), import_edges)
    var lakefile = count(
        "ls formal/lean/lakefile.* 2>/dev/null | wc -l")
    r.observe_int(String("lakefile-for-top-level-tree"), lakefile)
    # A tree with no module system cannot share a definition, so the
    # duplication census is a consequence, not an independent finding.
    r.world_count(String("top-level-tree-has-a-lakefile"), lakefile, 1)

    # ---- THE AGENT CHART: derive the rosters, do not restate them -------
    #
    # The twin proves the three Lean rosters form a STRICT CHAIN OF
    # INCLUSIONS (ATLAS-20/21/22) rather than three conflicting definitions.
    # That claim is only worth anything if the rosters in the tree really are
    # nested, so they are counted here from the inductives themselves.
    #
    # The distinction changes the remedy: a permutation needs a convention
    # chosen, a size mismatch needs a question of fact settled, and a
    # filtration needs only its TERMINAL OBJECT NAMED. The third is the
    # cheapest to fix and the easiest to leave rotting, because every member
    # of the chain typechecks forever.
    var tri_n = count(
        "awk '/^inductive Agent/{p=1} p{print} p&&/deriving/{exit}' "
        + "formal/lean/AgenticCoordination.lean 2>/dev/null"
        + " | grep -oE '\\| ?(claude|codex|agy|pi|deepseek)' | sort -u | wc -l")
    var meta_n = count(
        "awk '/^inductive Agent/{p=1} p{print} p&&/deriving/{exit}' "
        + "formal/lean/AgentMetaOntology.lean 2>/dev/null"
        + " | grep -oE '\\| ?(claude|codex|agy|pi|deepseek)' | sort -u | wc -l")
    var hive_n = count(
        "awk '/^inductive HolonicHiveHarness/{p=1} p{print} p&&/deriving/{exit}' "
        + "formal/lean/HolonicFppBionicUnifiedLeanInfrastructureAndDigitalTwins.lean"
        + " 2>/dev/null | grep -cE '^ *\\| HiveCaste0[0-9]_'")
    r.observe(String("agent-roster-sizes-tri-meta-hive"),
              String(tri_n) + String("/") + String(meta_n) + String("/")
              + String(hive_n))
    var rosters_readable = (tri_n > 0 and meta_n > 0 and hive_n > 0)
    r.world_or_blind(String("agent-rosters-are-readable"), True,
                     rosters_readable)

    if rosters_readable:
        # ATLAS-23: the three cardinalities are 3, 4, 5.
        r.algebra(String("atlas23-roster-cardinalities-are-three-four-five"),
                  tri_n == 3 and meta_n == 4 and hive_n == 5)
        # ATLAS-21: each inclusion admits exactly one agent.
        r.algebra(String("atlas21-each-inclusion-admits-exactly-one"),
                  meta_n - tri_n == 1 and hive_n - meta_n == 1)
        # ATLAS-20: the chain is monotone. Necessary for a filtration; a
        # decreasing step would mean an agent was REMOVED, which is a
        # different and worse finding than one being added.
        r.algebra(String("atlas20-chain-is-monotone"),
                  tri_n < meta_n and meta_n < hive_n)

    # The INCLUSION itself, not just the sizes. Three sizes 3/4/5 would also
    # be consistent with three disjoint rosters, so membership is checked:
    # every agent named by the smaller roster must appear in the larger.
    var tri_members = capture(
        "awk '/^inductive Agent/{p=1} p{print} p&&/deriving/{exit}' "
        + "formal/lean/AgenticCoordination.lean 2>/dev/null"
        + " | grep -oE '(claude|codex|agy|pi)' | sort -u | tr '\\n' ' '")
    var meta_members = capture(
        "awk '/^inductive Agent/{p=1} p{print} p&&/deriving/{exit}' "
        + "formal/lean/AgentMetaOntology.lean 2>/dev/null"
        + " | grep -oE '(claude|codex|agy|pi)' | sort -u | tr '\\n' ' '")
    r.observe(String("tri-members"), tri_members)
    r.observe(String("meta-members"), meta_members)
    var inclusion_holds = True
    if tri_members.byte_length() > 0 and meta_members.byte_length() > 0:
        for m in tri_members.split(String(" ")):
            var name = String(String(m).strip())
            if name.byte_length() == 0:
                continue
            if not contains(meta_members, name):
                inclusion_holds = False
    r.algebra(String("atlas20-tri-roster-is-a-subset-of-meta"),
              inclusion_holds)
    # And the admitted agent is `pi` (ATLAS-22), not some other member.
    r.algebra(String("atlas22-the-admitted-agent-is-pi"),
              contains(meta_members, String("pi"))
              and not contains(tri_members, String("pi")))

    # ---- the one GENUINE membership conflict ----------------------------
    # The Gleam roster has 5 slots like rosterHive, and 4 agents. A count
    # that matches with a membership that does not is the most misleading
    # shape available.
    var gleam_api = String(
        "apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/core_evo_api.gleam")
    var gleam_slots = count(
        "grep -c 'caste_id: \"CASTE-0' " + gleam_api + " 2>/dev/null")
    var gleam_nonagent = count(
        "grep -A2 'caste_id: \"CASTE-05\"' " + gleam_api
        + " 2>/dev/null | grep -ci 'binaries\\|deterministic'")
    var gleam_deepseek_in_02 = count(
        "grep -A2 'caste_id: \"CASTE-02\"' " + gleam_api
        + " 2>/dev/null | grep -ci 'deepseek'")
    var gleam_deepseek_in_05 = count(
        "grep -A2 'caste_id: \"CASTE-05\"' " + gleam_api
        + " 2>/dev/null | grep -ci 'deepseek'")
    r.observe_int(String("gleam-caste-slots"), gleam_slots)
    r.observe_int(String("gleam-caste05-is-a-nonagent"), gleam_nonagent)
    r.observe_int(String("gleam-caste02-names-deepseek"), gleam_deepseek_in_02)
    r.observe_int(String("gleam-caste05-names-deepseek"), gleam_deepseek_in_05)
    if gleam_slots > 0:
        # ATLAS-24 (unified): five slots, zero non-agent occupants.
        r.algebra(String("atlas24-five-slots-with-all-agents"),
                  gleam_slots == 5 and gleam_nonagent == 0)
        # ATLAS-26 (unified): DeepSeek occupies its canonical CASTE-05 home
        # and is no longer duplicated inside CASTE-02.
        r.algebra(String("atlas26-deepseek-occupies-canonical-caste05"),
                  gleam_deepseek_in_05 > 0 and gleam_deepseek_in_02 == 0)
    # ATLAS-25: the charts glue. A world check, because it is a fact
    # about the live Gleam source rather than about the algebra.
    r.world_count(String("every-gleam-caste-slot-holds-an-agent"),
                  gleam_nonagent, 0)

    # ---- agents in the holarchy / FPP mesh / aspects --------------------
    # ATLAS-27: the assignment does not exist. Not "is wrong" -- does not
    # exist. Counted so the size of the gap is visible.
    var fpp_specs = count(
        "grep -oE '\"l[0-9]_(apps|engines|services|intel)_[a-z0-9_]+\"' "
        + String(FPP_MESH) + " 2>/dev/null | sort -u | wc -l")
    var fpp_with_caste = count(
        "grep -ciE 'caste|agent_id|assigned_agent' " + String(FPP_MESH)
        + " 2>/dev/null")
    var caste_aspect_matrix = count(
        "grep -rliE 'caste.*aspect|aspect.*caste' --include='*.lean' "
        + "--include='*.gleam' --include='*.json' formal apps governance "
        + "2>/dev/null | wc -l")
    r.observe_int(String("fpp-subsystems"), fpp_specs)
    r.observe_int(String("fpp-mesh-mentions-of-caste"), fpp_with_caste)
    r.observe_int(String("caste-by-aspect-matrix-files"), caste_aspect_matrix)
    # The FPP mesh must assign a caste to each subsystem, or the agent chart
    # and the holarchy chart have NO declared intersection and there is
    # nothing for a morphism to be defined on.
    # CORRECTED 20261106: the mesh DOES name castes -- in 4 of 40 subsystem
    # DESCRIPTION STRINGS at the L6 layer ("CASTE-02/04 Isolated Sibling-JJ
    # Pi+DeepSeek", :758). That is prose inside a label, not a structured
    # field, so it cannot be read, joined or checked. The honest finding is
    # sharper than "no caste assignment exists": 4 subsystems mention a
    # caste in prose and ZERO carry it as data.
    var fpp_caste_fields = count(
        "grep -cE '(caste|agent_id|assigned_agent) *:' " + String(FPP_MESH)
        + " 2>/dev/null")
    r.observe_int(String("fpp-subsystems-with-a-caste-FIELD"), fpp_caste_fields)
    r.world_count(String("fpp-mesh-assigns-a-caste-field-per-subsystem"),
                  fpp_caste_fields, fpp_specs)

    # ---- agent collateral parity (SC-MIRROR-PROJ-001) -------------------
    # Four surfaces are claimed to carry projections of the canonical
    # contracts. Measured: 77 rules per surface against 65 canonical bodies,
    # so 12 per surface have no canonical body at all -- and the competing
    # L-layer definitions live in exactly those unmeasured bodies.
    var canonical = count("ls contracts/rules/*.md 2>/dev/null | wc -l")
    var c_rules = count("ls .claude/rules/*.md 2>/dev/null | wc -l")
    var x_rules = count("ls .codex/rules/*.md 2>/dev/null | wc -l")
    var a_rules = count("ls .agents/rules/*.md 2>/dev/null | wc -l")
    var g_rules = count("ls .gemini/rules/*.md 2>/dev/null | wc -l")
    r.observe_int(String("canonical-contracts"), canonical)
    r.observe(String("surface-rule-counts"),
              String(c_rules) + String("/") + String(x_rules) + String("/")
              + String(a_rules) + String("/") + String(g_rules))
    # The four surfaces must agree with each other -- that is the parity
    # claim, and it is the half that holds.
    r.world_or_blind(String("four-agent-surfaces-carry-equal-rule-counts"),
                     c_rules > 0,
                     c_rules == x_rules and x_rules == a_rules
                     and a_rules == g_rules)
    # Every projected rule must have a canonical body. This is the half that
    # does not hold, and it is where the unmeasured bodies live.
    #
    # CORRECTED 20261106: this arm first computed `c_rules - canonical`
    # (77 - 65 = 12), which answers a DIFFERENT question. Some canonical
    # contracts have no projection, so the difference of two counts is not
    # the number of projections lacking a body. Counted BY NAME it is 15, so
    # the arithmetic version UNDERSTATED the finding by 3 -- the direction
    # that matters, because an understated violation reads as progress.
    var orphan_rules = count(
        "for f in .claude/rules/*.md; do b=$(basename \"$f\"); "
        + "[ -f \"contracts/rules/$b\" ] || echo x; done 2>/dev/null | wc -l")
    r.observe_int(String("projected-rules-without-a-canonical-body"), orphan_rules)
    r.world_count(String("every-projected-rule-has-a-canonical-body"),
                  orphan_rules, 0)

    # And one of the fifteen is the contract mandating the atlas THIS FILE
    # implements: denotational-intent-algebraic-atlas-contract.md is
    # projected into all four agent surfaces and has no canonical body under
    # contracts/rules/. SC-MIRROR-PROJ-001 requires one.
    #
    # So the mandate for transition morphisms is itself outside the
    # projection gate that is supposed to keep every rule anchored to a
    # measured body. That is why the morphisms could remain unwritten for
    # four months with every gate green: nothing was holding the mandate.
    var atlas_rule_orphaned = count(
        "test -f .claude/rules/denotational-intent-algebraic-atlas-contract.md "
        + "&& ! test -f contracts/rules/denotational-intent-algebraic-atlas-contract.md "
        + "&& echo 1 || echo 0")
    r.observe_int(String("atlas-mandate-rule-is-orphaned"), atlas_rule_orphaned)
    r.world_count(String("atlas-mandate-rule-has-a-canonical-body"),
                  atlas_rule_orphaned, 0)


    # ---- NEGATIVE CONTROL ----------------------------------------------
    # Every derivation above reads a real file. Each must be able to come
    # back EMPTY and be caught, or a renamed source would silently zero the
    # arms while the receipt stayed green.
    var absent = count(
        "grep -oE 'nothing' formal/lean/NoSuchFileAtAll.lean 2>/dev/null"
        + " | wc -l")
    r.mutation_probe(String("absent-source-reads-as-zero-not-as-agreement"),
                     absent == 0)
    # The ABI docstring parse must be non-vacuous: if the grep matched
    # nothing, abi_torpor would be -1 and every regime arm above would have
    # been skipped rather than passed.
    r.mutation_probe(String("abi-regime-parse-is-not-vacuous"), abi_readable)
    # And the route parse must have found numbers at all, not defaults.
    #
    # F12, 20261106: this probe was `declared == 101 and observed == 97`,
    # transcribing the subject's proved values into the INSTRUMENT. If the
    # census legitimately moved to 102/98, the probe would fail, `vacuous`
    # would go to 1, and the receipt would report VACUOUS -- which outranks
    # everything. A reader would see "the oracle cannot discriminate" when
    # the truth is "the subject moved and the oracle noticed". Worse, if the
    # gap also changed, a genuine DIVERGENT would be OVERWRITTEN by VACUOUS,
    # because vacuity is tested first. The probe converted this oracle's
    # most valuable signal into a report about its own health.
    #
    # The sibling probe one line above already shows the right shape: test
    # READABILITY, not a pinned value, so the control survives a legitimate
    # change in the subject. The values themselves are compared in the
    # `world_count` arms, which is where a divergence belongs.
    # L3 FIX, 20261106-0924 (re-review finding, F12 residue). The previous
    # replacement for the `== 101 and == 97` pin re-pinned a RELATION:
    # `declared > observed`. Closing the route-census gap -- the thing the
    # surrounding arms exist to motivate -- would fail the probe and report
    # VACUOUS. A control must survive the subject being repaired. Readability
    # is the property a control should test; the relation belongs in the
    # world arms, where closing the gap reads as progress rather than as an
    # oracle that cannot discriminate.
    r.mutation_probe(String("route-census-parse-is-not-vacuous"),
                     declared >= 0 and observed >= 0)

    print("# probe time                     :", now)
    print("# ABI regime codes (T,C,H,A)     :", abi_torpor, abi_catabolic,
          abi_homeostatic, abi_anabolic)
    print("# OCaml archetype code 0         :", oc0, "(Lean/Mojo: CT_HIGH_ENTROPY)")
    print("# OCaml index 7 is a catch-all   :", oc7_is_catchall,
          "<-- invalid codes become a VALID archetype")
    print("# route: declared / observed     :", declared, "/", observed,
          "(proved by decide)")
    print("# route: bare :=104 record fields:", bare_104, "(proved by nothing)")
    print("# old atlas morphism: bool/func  :", old_has_bool, "/",
          old_has_function)
    print("#")
    print("# LEAN COMPILE COVERAGE")
    print("#   top-level .lean files        :", lean_total)
    print("#   hardcoded gate targets       :", gate_targets)
    print("#   differential subjects        :", differential_subjects)
    print("#   cross-file import edges      :", import_edges)
    print("#   lakefile present             :", lakefile)
    # HYGIENE FIX, 20261106-0924 (re-review finding 22). These two lines
    # concluded "no lakefile and 2 import edges is WHY 651 lines are
    # byte-identical" -- printed TWO LINES AFTER the same run reports
    # `lakefile present : 1` and 4 import edges. The file asserted and
    # refuted the same premise inside one receipt. The lakefile was written
    # earlier in this effort and the conclusion was never revisited.
    #
    # The duplication is still measured and still real; what changed is that
    # the stated CAUSE is now read from the run instead of remembered.
    if lakefile > 0:
        print("# (a lakefile IS present and", import_edges, "import edges")
        print("#  exist, so duplication is no longer forced by the absence")
        print("#  of a build system -- the byte-identical lines are now")
        print("#  unreclaimed debt rather than an unavoidable consequence)")
    else:
        print("# (no lakefile and", import_edges, "import edges is WHY the")
        print("#  byte-identical lines exist: duplication is the only reuse")
        print("#  available)")
    r.emit()
    exit(r.exit_code())
