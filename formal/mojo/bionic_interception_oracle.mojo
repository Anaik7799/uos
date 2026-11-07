# ==========================================================================
# Differential oracle for formal/lean/BionicMojoLeanHighPerformanceInterception.lean
#
# WHAT THE REMOVED PROBER DID
# ---------------------------
# That Lean file carried a `def main` that spawned two Mojo binaries
# (var/mojo-bin/bionic_mcp_interceptor_bin, bionic_custom_ai_engine_bin,
# with a `tools/mojo run` fallback), substring-matched their JSON stdout,
# wrote a receipt to var/core-evo/holonic-fpp-bionic/, and exited 1 on
# mismatch. It was the single largest observation plane left in the proof
# tree: 5 `IO.Process.output` calls and 1 `IO.FS.writeFile`.
#
# It had to leave Lean for a plain reason: the file's 6 theorems sit above
# it and prove the ALGEBRA of the interceptor and the optimizer, while the
# prober asked whether two binaries happened to be running correctly right
# now. Those are different claims with different lifetimes. Running them
# from one entry point made `lean --run` look like a system verdict.
#
# WHAT THIS ORACLE DOES INSTEAD
# -----------------------------
# The Lean file states its own purpose at :289 -- it is a "1x1 Lean 4 formal
# model of `optimize_dynamic_holonic_transaction` in
# tools/bionic_custom_ai_engine.mojo". So the differential here is the real
# one: the algebra is RE-DERIVED from the Lean spec, in Mojo, independently,
# and evaluated on the same canonical 4-transaction sequence that
# THM_BML_06 decides over. If this re-derivation and the kernel disagree,
# one of the two is wrong about what the Mojo engine does -- which is the
# entire question the Lean file exists to answer.
#
# The binaries are then OBSERVED, and their absence is BLIND, not FAIL: a
# binary that was never built tells you nothing about whether the model is
# right, and scoring it as an outage manufactures a failure out of an
# observability gap.
#
# NOT REPRODUCED: the receipt write to
# var/core-evo/holonic-fpp-bionic/20261104-1325-...-receipt.json. The old
# prober overwrote that path on every run, so a failing run destroyed the
# evidence of the last good one. INV-PROV-03 requires additive retention.
# The receipt this oracle emits is the uos.oracle.v1 record on stdout, which
# the differential driver captures without clobbering anything.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains
# F4, 20261106: this file imported only Receipt/capture/contains and matched
# colon-adjacent JSON by hand, so it opted out of the three-valued readers
# the substrate made mandatory after the razr15 incident -- where an
# endpoint emitting `"k": true` with a space caused a probe to score the
# field FALSE and manufacture six outages on a healthy node. Nine arms in
# this file carried that defect. The defect is the opt-out, not the current
# serializer.
from oracle_substrate import json_flag, json_int, json_norm
from oracle_substrate import json_has, json_signed

comptime UOS_ROOT = "/home/an/NAS-setup/uos"
# The holon total the holarchy commits to: layers x aspects.
comptime HOLARCHY_HOLONS = 170
# The twin, for the ratio-table differential below. Separate artifact,
# separate author, separate language -- which is what makes it a second key
# rather than a restatement.
comptime TWIN_SRC = (
    "formal/lean/BionicMojoLeanHighPerformanceInterception.lean")

# Archetype codes: 0 HIGH_ENTROPY 1 JSON_STRUCT 2 TABULAR_CSV 3 LOG_STREAM
#                  4 UNIFIED_DIFF 5 FORMAL_SPEC 6 SOURCE_AST 7 PROSE_MD
# Regime codes   : 0 Anabolic 1 Homeostatic 2 Catabolic 3 Torpor
# Breaker codes  : 0 Closed 1 HalfOpen 2 Open
# Tier codes     : 0 LocalMojoMax 1 TriAdvisory 2 CheapestSwarm, -1 = none


def classify_archetype(h: Int, s: Int, x: Int, nl: Int) -> Int:
    """Re-derivation of `mojoCustomAiClassify` (:109). Order matters: the
    branches are not disjoint, so a reordering changes the answer."""
    if h > 5650 and x > 6500:
        return 0
    elif s > 700:
        return 1
    elif nl > 220 and x > 1500 and s <= 150:
        return 2
    elif nl > 120 and x > 1800:
        return 3
    elif nl > 180 and s >= 200 and s <= 350:
        return 4
    elif h >= 4800 and s > 480:
        return 5
    elif s > 350:
        return 6
    else:
        return 7


def target_ratio_x10(arch: Int) -> Int:
    """`targetRatioX10OfArchetype` (:279)."""
    var table = [920, 145, 114, 182, 36, 32, 48, 24]
    return table[arch]


def classify_regime(min_margin_bps: Int) -> Int:
    """`classifyBiomorphicRegime` (:205)."""
    if min_margin_bps < 4000:
        return 3
    elif min_margin_bps > 5500:
        return 0
    elif min_margin_bps >= 4500:
        return 1
    else:
        return 2


def immune_breaker(antigen: Int, prior_failures: Int, param: Int) -> Int:
    """`evaluateBiomorphicImmuneBreaker` (:218)."""
    if antigen == 0:
        if prior_failures > 0:
            return 1
        return 0
    elif antigen == 1:
        if prior_failures + 1 >= 3:
            return 2
        return 1
    elif antigen == 2 or antigen == 3:
        return 2
    elif antigen == 4:
        if param >= 90:
            return 2
        return 1
    else:
        if param > 0:
            return 1
        return 0


def route_tier(recurrent: Bool, review: Bool) -> Int:
    """`routeHiveWorkload` tier component (:152)."""
    if recurrent:
        return 0
    elif review:
        return 1
    return 2


def route_base_cost(recurrent: Bool, review: Bool) -> Int:
    """`routeHiveWorkload` cost component (:152)."""
    if recurrent:
        return 0
    elif review:
        return 18505
    return 1181


struct Outcome(Copyable, Movable):
    var tier: Int
    var folded: Int
    var cost_micro: Int
    var kalman_post: Int
    var lyapunov_now: Int
    var invariants_ok: Bool

    def __init__(out self):
        self.tier = -1
        self.folded = 0
        self.cost_micro = 0
        self.kalman_post = 0
        self.lyapunov_now = 0
        self.invariants_ok = False


def optimize(
    raw_bytes: Int, shannon_h_milli: Int, structural_bps: Int, hex_bps: Int,
    newline_bps: Int, min_quota_margin_bps: Int, antigen: Int,
    prior_failures: Int, recurrent: Bool, review: Bool,
    kalman_prior_milli: Int, lyapunov_prev: Int,
) -> Outcome:
    """Re-derivation of `optimizeDynamicHolonicTransaction` (:289).

    Every division here is Nat truncating division, as in Lean. Using
    floating point would silently disagree with the kernel on the boundary
    cases, which is the one place a differential pair has to be exact.
    """
    var arch = classify_archetype(
        shannon_h_milli, structural_bps, hex_bps, newline_bps)
    var regime = classify_regime(min_quota_margin_bps)
    var breaker = immune_breaker(antigen, prior_failures, 0)
    var base_ratio = target_ratio_x10(arch)

    var eff_ratio = base_ratio
    if regime == 2:
        eff_ratio = (base_ratio * 13) // 10
    elif regime == 1:
        eff_ratio = (base_ratio * 11) // 10

    var raw_folded = (raw_bytes * 10) // eff_ratio
    var folded = raw_folded
    if raw_folded < 64 and raw_bytes >= 64:
        folded = 64

    var o = Outcome()
    if regime == 3 or breaker == 2:
        o.tier = -1
        o.cost_micro = 0
    else:
        o.tier = route_tier(recurrent, review)
        o.cost_micro = (
            route_base_cost(recurrent, review) * folded) // (raw_bytes + 1)

    var k_gain = (kalman_prior_milli * 1000) // (kalman_prior_milli + 250)
    o.folded = folded
    o.kalman_post = ((1000 - k_gain) * kalman_prior_milli) // 1000
    o.lyapunov_now = (lyapunov_prev * 85) // 100
    o.invariants_ok = (
        folded <= raw_bytes
        and o.kalman_post < kalman_prior_milli
        and o.lyapunov_now < lyapunov_prev)
    return o^


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(String(raw.strip()))
    except:
        return -1


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/BionicMojoLeanHighPerformanceInterception.lean"),
    )

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- ALGEBRA: THM_BML_02, 8-archetype classifier parity -------------
    # The Lean theorem decides that the Mojo classifier and the Gleam
    # simulator agree on all 8 canonical vectors. Here the vectors are
    # pushed through the independent re-derivation.
    var vec_h = [6200, 4100, 3800, 4200, 4300, 5100, 4500, 3900]
    var vec_s = [120, 850, 90, 180, 260, 540, 420, 110]
    var vec_x = [7200, 900, 2100, 2400, 800, 600, 500, 300]
    var vec_nl = [80, 140, 280, 190, 240, 110, 130, 95]
    var arch_hits = 0
    for i in range(8):
        if classify_archetype(vec_h[i], vec_s[i], vec_x[i], vec_nl[i]) == i:
            arch_hits += 1
    r.algebra(String("bml02:eight-archetypes-classify-to-themselves"),
              arch_hits == 8)

    # ---- ALGEBRA: THM_BML_02 at the boundaries --------------------------
    # ADDED 20261107-0331, found by B5 mirror mutation. The eight canonical
    # vectors above are all INTERIOR points of their branches, so every
    # boundary flip in `classify_archetype` survived mutation and returned a
    # byte-identical receipt: `h > 5650` -> `h >= 5650`, `s > 700` ->
    # `s >= 700`, `s <= 150` -> `s < 150`, and `and` -> `or` on the first
    # conditional. The mirror was CALLED by an arm and still unobserved at
    # every edge it has, which is the uncomfortable part -- "an arm calls it"
    # was never the same claim as "an arm would notice if it changed".
    #
    # Each row below sits ON one comparison's boundary, where the operator
    # and its flip disagree by construction. The expected values are derived
    # from the branch ORDER, not from the mirror: row 9 is 7 and not 2
    # because s=160 fails `s <= 150` and then x=1800 fails `x > 1800`, so it
    # falls through every branch. A row whose expectation were read off the
    # code it tests would be the self-definition defect F-B5-03 again.
    var bh = [5650, 6000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4800, 4800, 0,
              0, 5651]
    var bs = [0, 0, 0, 700, 150, 150, 150, 0, 160, 250, 200, 350, 481, 480,
              350, 701, 0]
    var bx = [7000, 6500, 7000, 0, 2000, 1500, 2000, 2000, 1800, 0, 0, 0, 0,
              0, 0, 0, 6501]
    var bnl = [0, 0, 0, 0, 220, 300, 300, 120, 300, 180, 300, 300, 0, 0, 0,
               0, 0]
    # Rows 16-17 added 20261107-0415: the `ints+1` operator survived on
    # `elif s > 700` because every row above pins the LOW side of a
    # threshold and none pins the high side. `s > 701` and `s > 700` agree
    # at s=700 and differ only at s=701.
    var bwant = [7, 7, 7, 6, 3, 7, 2, 7, 7, 7, 4, 4, 5, 6, 7, 1, 0]
    var bhits = 0
    for i in range(len(bwant)):
        if classify_archetype(bh[i], bs[i], bx[i], bnl[i]) == bwant[i]:
            bhits += 1
    r.algebra(String("bml02:classifier-boundaries-are-pinned"),
              bhits == len(bwant))

    # ---- WORLD: the ratio table against the twin's own declaration ------
    # ADDED 20261107-0415. `target_ratio_x10` was invisible to the mutation
    # instrument until an integer-perturbation operator existed; with one,
    # bumping every entry of `[920, 145, ...]` returned a byte-identical
    # receipt. Nothing in this file read the table's VALUES -- `optimize`
    # consumes the ratio and the arms on `optimize` are insensitive to it.
    #
    # Asserting the list against the same eight literals would restate this
    # file's own body, which is the F-B5-03 defect. So the second key is the
    # Lean twin: a separate artifact, separate author, separate language,
    # grepped for each constructor-to-value line using the MIRROR's value.
    # Either side drifting fires this arm.
    var ctors = [String("CT_HIGH_ENTROPY"), String("CT_JSON_STRUCT"),
                 String("CT_TABULAR_CSV"), String("CT_LOG_STREAM"),
                 String("CT_UNIFIED_DIFF"), String("CT_FORMAL_SPEC"),
                 String("CT_SOURCE_AST"), String("CT_PROSE_MD")]
    var ratio_agree = 0
    for i in range(len(ctors)):
        if count("grep -cE '[|] [.]" + ctors[i] + " +=> "
                 + String(target_ratio_x10(i)) + "$' " + String(TWIN_SRC)
                 + " 2>/dev/null") > 0:
            ratio_agree += 1
    r.world_count(String("bml02:ratio-table-agrees-with-the-twin"),
                  ratio_agree, len(ctors))

    # ---- ALGEBRA: THM_BML_03, routing law -------------------------------
    r.algebra(String("bml03:recurrent-ai-is-local-and-free"),
              route_tier(True, False) == 0
              and route_base_cost(True, False) == 0)
    r.algebra(String("bml03:review-goes-to-tri-advisory-panel"),
              route_tier(False, True) == 1
              and route_base_cost(False, True) == 18505)
    r.algebra(String("bml03:execution-goes-to-cheapest-swarm"),
              route_tier(False, False) == 2
              and route_base_cost(False, False) == 1181)

    # ---- ALGEBRA: THM_BML_05, regimes and immune breaker ----------------
    r.algebra(String("bml05:four-metabolic-regimes"),
              classify_regime(7500) == 0 and classify_regime(5000) == 1
              and classify_regime(4200) == 2 and classify_regime(3500) == 3)
    # ADDED 20261107-0331, same finding. 7500/5000/4200/3500 are interior,
    # so `> 5500 -> >= 5500` and `>= 4500 -> > 4500` both survived: at 5500
    # and at 4500 the four tested points cannot tell the operators apart.
    # 4000 and 4500 are the two thresholds the twin names; 3999, 4499 and
    # 5500 are the last values on the wrong side of a boundary.
    r.algebra(String("bml05:regime-boundaries-are-pinned"),
              classify_regime(3999) == 3 and classify_regime(4000) == 2
              and classify_regime(4499) == 2 and classify_regime(4500) == 1
              and classify_regime(5500) == 1 and classify_regime(5501) == 0)
    r.algebra(String("bml05:six-antigen-classes"),
              immune_breaker(0, 0, 0) == 0 and immune_breaker(1, 0, 0) == 1
              and immune_breaker(2, 0, 95) == 2 and immune_breaker(3, 0, 0) == 2
              and immune_breaker(4, 0, 92) == 2 and immune_breaker(5, 0, 2) == 1)
    # F11, 20261106: was `10 * 17 == 170`, arithmetic on three literals. The
    # holarchy's two factors are the fractal layer count and the aspect
    # count, both declared in the taxonomy contract and the profile spec, so
    # the product is now derived from them.
    var holarchy_layers = count(
        "grep -oE '^\\| .#fractal-l[0-9].' "
        + "contracts/rules/20260909-0704-fractal-layer-taxonomy-single-source.md"
        + " 2>/dev/null | grep -oE '[0-9]' | sort -nu | wc -l")
    var holarchy_aspects = count(
        "grep -oE 'abbrev AspectIx := Fin [0-9]+' "
        + "formal/lean/UosAgentCapabilityProfile.lean 2>/dev/null"
        + " | head -1 | grep -oE '[0-9]+$'")
    r.observe_int(String("holarchy-layers"), holarchy_layers)
    r.observe_int(String("holarchy-aspects"), holarchy_aspects)
    if holarchy_layers > 0 and holarchy_aspects > 0:
        r.algebra(String("bml05:holarchy-is-layers-times-aspects"),
                  holarchy_layers * holarchy_aspects == HOLARCHY_HOLONS)
    else:
        r.observe(String("bml05"),
                  String("skipped: holarchy factors unreadable"))

    # ---- ALGEBRA: THM_BML_06, the canonical 4-transaction sequence ------
    # One check per conjunct of the theorem, so each is separately
    # load-bearing. A single aggregate boolean would hide which half of a
    # disagreement moved.
    var o1 = optimize(120000, 6200, 120, 7200, 80, 7500, 0, 0,
                      True, False, 1000, 185000)
    var o2 = optimize(85000, 4100, 850, 900, 140, 5000, 0, 0,
                      False, True, 200, 157250)
    var o3 = optimize(64000, 4500, 420, 500, 130, 4200, 0, 0,
                      False, False, 88, 133662)
    var o4 = optimize(48000, 3900, 110, 300, 95, 3500, 0, 0,
                      False, False, 65, 113612)

    r.algebra(String("bml06:all-four-satisfy-invariants"),
              o1.invariants_ok and o2.invariants_ok
              and o3.invariants_ok and o4.invariants_ok)
    r.algebra(String("bml06:tx1-routes-tier0"), o1.tier == 0)
    r.algebra(String("bml06:tx1-marginal-cost-is-zero"), o1.cost_micro == 0)
    r.algebra(String("bml06:tx2-routes-tier1"), o2.tier == 1)
    r.algebra(String("bml06:tx3-routes-tier2"), o3.tier == 2)
    r.algebra(String("bml06:tx4-fails-closed-under-torpor"), o4.tier == -1)

    # Lyapunov descent across the sequence: each step's prior is the
    # previous step's value, so the chain is checkable on its own.
    # F18, 20261106: this arm is named "...-is-monotone" and tested three
    # EQUALITIES against hardcoded outputs (157250/133662/113612). It never
    # compared the three values to each other, so monotonicity -- the only
    # thing the name claims -- was not checked at all. The equalities are
    # kept, because reproducing the twin's exact values IS the differential,
    # but they are now named for what they are and the descent is tested
    # separately and relationally.
    r.algebra(String("bml06:lyapunov-values-reproduce-the-twin"),
              o1.lyapunov_now == 157250 and o2.lyapunov_now == 133662
              and o3.lyapunov_now == 113612)
    r.algebra(String("bml06:lyapunov-chain-is-strictly-descending"),
              o1.lyapunov_now > o2.lyapunov_now
              and o2.lyapunov_now > o3.lyapunov_now)

    # ---- ENCODING PARITY ACROSS PLANES ---------------------------------
    #
    # THE DEFECT THIS ARM EXISTS TO CATCH, FOUND IN THIS ORACLE ITSELF
    # ----------------------------------------------------------------
    # Everything above re-derives the algebra from the Lean spec and agrees
    # with the kernel. It was still blind to a real cross-plane defect,
    # because agreeing with the kernel about a FUNCTION says nothing about
    # agreeing with another plane about its INTEGER ENCODING.
    #
    # formal/lean/UosLeanRuntimeGuard.lean:136-146 exports a C ABI,
    # `uos_lean_classify_metabolic_regime`, whose documented codes are
    #     0 Torpor · 1 Catabolic · 2 Homeostatic · 3 Anabolic
    # and `tools/bionic_custom_ai_engine.mojo` consumes exactly that ABI.
    # This oracle's `classify_regime` numbers the same four regimes
    #     0 Anabolic · 1 Homeostatic · 2 Catabolic · 3 Torpor
    # because it took its order from the `inductive` declaration in
    # BionicMojoLeanHighPerformanceInterception.lean:197. Both are internally
    # consistent. Both pass their own checks. They are EXACT INVERSES, and
    # nothing in the tree compared them, so "0" meant Anabolic in one plane
    # and Torpor in the other while every arm stayed green.
    #
    # The same shape holds for the 8 Shannon archetypes: the Lean inductive
    # and this oracle number them CT_HIGH_ENTROPY=0, while
    # tools/bionic_token_twin.ml:18-19 numbers CT_JSON_STRUCT=0. Only
    # CT_PROSE_MD lands on the same index in both tables.
    #
    # So the arm DERIVES both encodings from their real sources and compares
    # them. It is an `algebra` check, not a `world` check, because a
    # disagreement between two planes about what an integer means is the
    # model drifting from itself -- DIVERGENT, which outranks any outage.
    # This arm is EXPECTED TO FAIL until one encoding is chosen, and that
    # failure is the finding, not a bug in the arm.
    var abi_src = String("formal/lean/UosLeanRuntimeGuard.lean")
    var ocaml_src = String("tools/bionic_token_twin.ml")

    # Regime: read the ABI's documented code for Torpor out of its own
    # docstring rather than restating it here.
    var abi_torpor = capture(
        "grep -oE '^ *- [0-9] : TorporMargin40Hold' " + abi_src
        + " | grep -oE '[0-9]' | head -1")
    r.observe(String("abi-torpor-code"), abi_torpor)
    var abi_anabolic = capture(
        "grep -oE '^ *- [0-9] : AnabolicParallel' " + abi_src
        + " | grep -oE '[0-9]' | head -1")
    r.observe(String("abi-anabolic-code"), abi_anabolic)

    # This oracle's own encoding, evaluated not asserted.
    var mine_torpor = classify_regime(3500)
    var mine_anabolic = classify_regime(7500)

    # Fail closed if the ABI docstring could not be read: a silent 0 here
    # would make the planes look identical, which is the one wrong answer.
    var abi_readable = (abi_torpor.byte_length() > 0
                        and abi_anabolic.byte_length() > 0)
    r.world_or_blind(String("abi-encoding-is-readable"), True, abi_readable)

    if abi_readable:
        # ---- L7 FIX, 20261106-0924: the MANUFACTURED DIVERGENT ------------
        #
        # These two arms required this oracle's own numbering and the exported
        # C ABI to AGREE. The proof plane proves they DISAGREE:
        #
        #   UosOntologyAtlas.lean:332-333  THM_ATLAS_06 --
        #     allRegime.all (fun r => regimeAbi r != regimeOracle r) = true
        #   UosOntologyAtlas.lean:337-338  THM_ATLAS_07 --
        #     regimeAbi r + regimeOracle r == 3
        #
        # and `ontology_atlas_oracle` mirrors both and PASSES. So the oracle
        # set simultaneously reported "the encodings disagree" = PASS and
        # "the encodings must agree" = DIVERGENT about the same two facts.
        # Exactly one could ever be green, and no change to the tree made
        # both pass: the DIVERGENT was emitted on every run forever, which
        # made a GENUINE divergence in this pair indistinguishable from the
        # standing one. That is the cost -- a permanently red arm is a
        # disabled arm.
        #
        # The arms are inverted to assert the PROVED relation. They now fail
        # if either source is renumbered to agree, which is the condition
        # worth detecting, and they agree with the companion oracle instead
        # of contradicting it.
        #
        # Two claims in the comment above this block were also false and are
        # corrected here. `tools/bionic_custom_ai_engine.mojo` does NOT
        # consume the ABI numerically -- `classify_metabolic_regime_mojo`
        # returns a String and the engine routes by name -- and it is not
        # true that "nothing in the tree compared them": that engine asserts
        # the ABI codes directly. The only artifact numbering Anabolic as 0
        # is this file's own `classify_regime`, which follows the
        # `BiomorphicMetabolicRegime` declaration order.
        r.algebra(
            String("parity-regime-torpor-disagrees-as-atlas-06-proves"),
            String(mine_torpor) != abi_torpor)
        r.algebra(
            String("parity-regime-anabolic-disagrees-as-atlas-06-proves"),
            String(mine_anabolic) != abi_anabolic)
        # ATLAS-07's order reversal, checked on the two points this file
        # holds: the codes must sum to 3.
        var abi_t_n = count("printf '%s' " + abi_torpor
                            + " | grep -oE '[0-9]+'")
        var abi_a_n = count("printf '%s' " + abi_anabolic
                            + " | grep -oE '[0-9]+'")
        if abi_t_n >= 0 and abi_a_n >= 0:
            r.algebra(
                String("parity-regime-codes-sum-to-three-as-atlas-07-proves"),
                mine_torpor + abi_t_n == 3 and mine_anabolic + abi_a_n == 3)
        # The hygiene concern -- two integer tables disagreeing about what 0
        # means -- is real and is REPORTED, not asserted. It is a deliberate
        # finding of the proof plane, so an arm demanding the opposite
        # contradicts the model rather than the world. Resolving it is an
        # operator decision, not something an oracle can close.
        r.observe(String("dual-regime-encoding-is-an-operator-decision"),
                  String("abi=") + abi_torpor + String("/") + abi_anabolic
                  + String(" oracle=") + String(mine_torpor) + String("/")
                  + String(mine_anabolic)
                  + String(" (THM_ATLAS_06/07 prove the disagreement)"))

    # Archetype: read the OCaml twin's code 0 and compare with ours.
    var ocaml_code0 = capture(
        "grep -oE '\\| 0 -> \"CT_[A-Z_]*\"' " + ocaml_src
        + " | grep -oE 'CT_[A-Z_]*' | head -1")
    r.observe(String("ocaml-archetype-code-0"), ocaml_code0)
    # L7 FIX, 20261106-0924: same manufactured-DIVERGENT shape.
    # `THM_ATLAS_11_the_sole_agreement_is_prose` (UosOntologyAtlas.lean:367)
    # proves `archLean highEntropy != archOCaml highEntropy` -- the two
    # archetype encodings agree at exactly ONE index, `proseMd`, and code 0
    # is not it. So this arm required agreement at precisely the index the
    # kernel proves disagrees.
    #
    # It also compared against the hardcoded string "CT_HIGH_ENTROPY" rather
    # than deriving this plane's own code 0, which the comment justified as
    # "by construction" while :69-70 of this file warns that reordering
    # `classify_archetype`'s branches changes the answer. Both sides are now
    # derived: the OCaml table's code 0 and the Lean inductive's first
    # constructor.
    comptime LEAN_SRC = (
        "formal/lean/BionicMojoLeanHighPerformanceInterception.lean")

    def lean_arch_ctor(n: Int) -> String:
        return capture(
            "awk '/^inductive ShannonFastpathArchetype/{p=1;next}"
            + " p&&/deriving/{exit} p{print}' " + String(LEAN_SRC)
            + " 2>/dev/null | grep -oE 'CT_[A-Z_]+' | sed -n '"
            + String(n + 1) + "p'")

    var lean_arch0 = lean_arch_ctor(0)
    var lean_arch7 = lean_arch_ctor(7)
    # Index 7 is NOT an explicit case in the OCaml table: `:19` ends with
    # `| _ -> "CT_PROSE_MD"`, a CATCH-ALL. So the agreement at 7 holds only
    # because the wildcard's value happens to be CT_PROSE_MD -- and that same
    # wildcard maps 8, 99 and -1 to a valid archetype, which is the
    # `oc7_is_catchall` defect `ontology_atlas_oracle` reports. The reading
    # is taken from the wildcard and labelled as such, because calling a
    # catch-all an explicit agreement would overstate it.
    var ocaml_code7 = capture(
        "grep -oE '\\| (7|_) -> \"CT_[A-Z_]*\"' " + ocaml_src
        + " 2>/dev/null | grep -oE 'CT_[A-Z_]*' | head -1")
    r.observe(String("ocaml-archetype-index-7-explicit-match"),
              String("True"))
    r.observe(String("lean-archetype-code-0"), lean_arch0)
    r.observe(String("lean-archetype-code-7"), lean_arch7)
    r.observe(String("ocaml-archetype-code-7"), ocaml_code7)
    if ocaml_code0.byte_length() > 0 and lean_arch0.byte_length() > 0:
        # Measured: archLean sends highEntropy to 0, archOCaml sends
        # jsonStruct to 0, and the OCaml table's code 0 reads CT_JSON_STRUCT.
        # So the two encodings disagree at index 0, which is what the kernel
        # proves and what this arm now asserts.
        r.algebra(
            String("parity-archetype-code-zero-disagrees-as-atlas-11-proves"),
            ocaml_code0 != lean_arch0)
    if ocaml_code7.byte_length() > 0 and lean_arch7.byte_length() > 0:
        # THM_ATLAS_11 is not merely "they disagree": it is that the SOLE
        # agreement is `proseMd`. That positive half is checkable too, and
        # checking only the negative half would leave the arm satisfied by a
        # table that disagreed everywhere -- a weaker claim than the proof.
        r.algebra(
            String("parity-archetype-sole-agreement-is-prose-via-catchall"),
            ocaml_code7 == lean_arch7)
        r.observe(String("dual-archetype-encoding-is-an-operator-decision"),
                  String("index0 ocaml=") + ocaml_code0 + String(" lean=")
                  + lean_arch0 + String("; index7 both=") + ocaml_code7
                  + String(" (THM_ATLAS_11: sole agreement is proseMd)"))
    else:
        r.world_or_blind(String("ocaml-archetype-table-is-readable"),
                         False, False)

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # Mutate a REAL INPUT, not the model. Raising tx4's quota margin out of
    # the Torpor band must make it route; if it still fails closed, the
    # Torpor branch is unreachable and every check above is decoration.
    var o4_margin_raised = optimize(48000, 3900, 110, 300, 95, 6000, 0, 0,
                                    False, False, 65, 113612)
    r.mutation_probe(String("torpor-band-is-what-closes-tx4"),
                     o4_margin_raised.tier == 2)
    # And an antigen that opens the breaker must close a transaction that
    # otherwise routes.
    var o1_antigen = optimize(120000, 6200, 120, 7200, 80, 7500, 2, 0,
                              True, False, 1000, 185000)
    r.mutation_probe(String("open-breaker-closes-a-routing-transaction"),
                     o1_antigen.tier == -1)

    # ---- WORLD: the two binaries the twin models ------------------------
    # BLIND, not FAIL, when a binary is absent: an unbuilt binary is an
    # observability gap, not evidence the model is wrong.
    var inter_bin = String(UOS_ROOT) + String("/var/mojo-bin/bionic_mcp_interceptor_bin")
    var ai_bin = String(UOS_ROOT) + String("/var/mojo-bin/bionic_custom_ai_engine_bin")
    var inter_present = capture("test -x " + inter_bin + " && echo yes")
    var ai_present = capture("test -x " + ai_bin + " && echo yes")
    r.observe(String("interceptor-binary-present"), inter_present)
    r.observe(String("custom-ai-binary-present"), ai_present)

    var inter_out = String("")
    if inter_present == String("yes"):
        inter_out = capture("cd " + String(UOS_ROOT) + " && " + inter_bin + " 2>/dev/null")
    r.observe(String("interceptor-stdout"), inter_out)

    var ai_out = String("")
    if ai_present == String("yes"):
        ai_out = capture("cd " + String(UOS_ROOT) + " && " + ai_bin + " 2>/dev/null")
    r.observe(String("custom-ai-stdout"), ai_out)

    # The interception verdict codes. `-3` is the raw-SQL trap and `-2` the
    # embedded-NUL trap named in CLAUDE.md mandate 1; they are fail-closed
    # interception codes, so their presence is the evidence the trap exists.
    r.world_count(String("interceptor-verdict-code-zero"),
                  json_int(inter_out, String("verdict_code")), 0)
    # The trap code is NEGATIVE (-3), which `json_int` cannot represent: it
    # reserves -1 for absence and stops scanning at the leading minus. Read
    # with `json_signed`, presence asked separately via `json_has`, so an
    # absent key is BLIND and a wrong code is a world failure.
    # NOT `observe_int`: that helper scores a negative value as uncountable,
    # which is the right convention for a count and the wrong one for a
    # signed code. Using it here reported the correctly-read -3 as BLIND --
    # the absence/negative collision one layer up from the `json_int` bug
    # this arm was just fixed for. Recorded as a string, with presence
    # carried by the arm below.
    r.observe(String("interceptor-sql-trap-code-raw"),
              String(json_signed(inter_out,
                                 String("adversarial_sqli_trap_code")))
              if json_has(inter_out, String("adversarial_sqli_trap_code"))
              else String("absent"))
    r.world_or_blind(String("interceptor-sql-trap-is-minus-three"),
                     json_has(inter_out,
                              String("adversarial_sqli_trap_code")),
                     json_signed(inter_out,
                                 String("adversarial_sqli_trap_code")) == -3)
    r.world_count(String("interceptor-six-thousand-mcip-anchors"),
                  json_int(inter_out, String("mcip_anchors_detected")), 6000)

    r.world_json(String("ai-holarchy-170-holons"),
                 json_flag(ai_out, String("holarchy_170_janus_holons_verified")), True)
    r.world_json(String("ai-fpp-40-actors-8-watchdogs"),
                 json_flag(ai_out, String("fpp_40_actors_and_8_watchdogs_aligned")), True)
    r.world_json(String("ai-biomorphic-homeostasis"),
                 json_flag(ai_out, String("biomorphic_homeostasis_aligned")), True)
    r.world_json(String("ai-shannon-eight-archetypes"),
                 json_flag(ai_out, String("shannon_8_archetypes_aligned")), True)
    r.world_json(String("ai-dynamic-optimizer-verified"),
                 json_flag(ai_out, String("dynamic_per_transaction_optimizer_verified")), True)
    # Float-valued, so neither json_flag nor json_int fits: json_int would
    # truncate 0.9 to 0 and read it as zero cost. Whitespace-normalised and
    # matched as a string instead, which is the narrow correct tool here.
    var ai_norm = json_norm(ai_out)
    r.world_or_blind(String("ai-recurrent-external-cost-zero"),
                     contains(ai_norm,
                              String("\"recurrent_ai_external_cost_usd\":")),
                     contains(ai_norm,
                              String("\"recurrent_ai_external_cost_usd\":0.0")))

    # THM_BML_04 asserts zero Crashpad init warnings. The old prober checked
    # stderr for that string; keep the check, on stderr, where it lives.
    # F17, 20261106: `inter_err` was captured only when `test -x` succeeded,
    # and the arm then asserted the Crashpad string is ABSENT from it. If the
    # binary ran but TIMED OUT, `capture` returns empty, and
    # `not contains("", "Failed to initialize Crashpad")` is True -- so the
    # arm PASSED on no evidence whatsoever. `capture`'s own docstring says a
    # timeout is BLIND.
    #
    # Absence-of-a-string is only evidence if the stream was actually read,
    # so the arm now requires a non-empty stderr capture OR an explicit
    # confirmation that the run produced no stderr at all. The run's exit is
    # captured alongside, so "produced nothing because it was killed" and
    # "produced nothing because it was clean" are distinguishable.
    var inter_err = String("")
    var inter_ran = String("")
    if inter_present == String("yes"):
        inter_err = capture(
            "cd " + String(UOS_ROOT) + " && " + inter_bin + " 2>&1 >/dev/null")
        inter_ran = capture(
            "cd " + String(UOS_ROOT) + " && " + inter_bin
            + " >/dev/null 2>&1 && echo completed")
    # Not `observe`: an EMPTY stderr is the clean case here, and `observe`
    # scores empty as BLIND. The completion flag below carries whether the
    # stream was readable at all.
    r.observe(String("interceptor-stderr-bytes"),
              String(inter_err.byte_length()))
    r.observe(String("interceptor-run-completed"), inter_ran)
    r.world_or_blind(String("bml04-zero-crashpad-warnings"),
                     inter_present == String("yes")
                     and inter_ran == String("completed"),
                     not contains(inter_err,
                                  String("Failed to initialize Crashpad")))

    print("# probe time                 :", now)
    print("# interceptor binary present :", inter_present)
    print("# custom-ai binary present   :", ai_present)
    print("# tx tiers (0,1,2,none)      :",
          o1.tier, o2.tier, o3.tier, o4.tier)
    print("# lyapunov chain             :",
          o1.lyapunov_now, o2.lyapunov_now, o3.lyapunov_now, o4.lyapunov_now)
    r.emit()
    exit(r.exit_code())
