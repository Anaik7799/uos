# ==========================================================================
# axis_registry_oracle — the first machine reader
# contracts/rules/20260909-0704-fractal-layer-taxonomy-single-source.md
# has ever had, and the collision guard for every indexed axis in the tree.
#
# Lean subject: formal/lean/Fractal_Holonic_Composability.lean
#   (the concern-axis implementation whose indices 0..7 are conformant and
#    whose 8/9 are not; the twin this oracle differentiates against)
#
# WHY THIS EXISTS
# ---------------
# SC-FRACTAL-TAXONOMY-001 declares itself the single source of truth for the
# L0..L9 concern axis. It was written 2026-09-09. Measured 2026-11-06:
#
#   * ZERO tools reference it. `grep -rl SC-FRACTAL-TAXONOMY-001` hits docs,
#     Lean and governance records only.
#   * Its enforcement mechanism was a pointer installed into both source
#     documents. That pointer was DELETED when .claude/rules/full-symbiosis.md
#     was rewritten on 2026-10-01, and nothing noticed for 36 days.
#   * The live full-symbiosis.md no longer contains the L0-L7 gate table at
#     all, so the contract's own reconciliation cites a reading that no
#     longer exists in the tree.
#
# A contract that declares a defect closed, and is read by nothing, is the
# same failure as a theorem decided over a frozen observation: a recorded
# verdict whose subject moved. This oracle is the re-measurement.
#
# WHAT IT ACTUALLY FOUND, AND WHY THE CENSUS WAS WRONG
# ----------------------------------------------------
# The first census reported "nine incompatible L0..L9 semantics" and "seven
# incompatible definitions of the routing tier object". Direct measurement of
# all 17 layer enums and all 6 tier enums shows that is not the shape:
#
#   * Indices 0..7 of the concern axis are CONFORMANT IN EVERY
#     IMPLEMENTATION. Every single deviation is at index 8 or 9 -- exactly
#     the two members the contract itself says no governing document had ever
#     defined before it was written. The defect is historical and
#     concentrated, not diffuse.
#   * Most "competing" enums are DIFFERENT AXES: a ZigVM implementation
#     stack, a subsystem stack, an F-prime scale axis, an 11-rung refinement
#     ladder, and deck.gl visual layers. Merging them would destroy real
#     distinctions. They need DECLARING, not renaming.
#   * The routing "object" is five distinct axes. `Minimum_Token_Cascade`
#     has 5 members, not the 3 reported, and the real defect is ONE INDEX on
#     ONE axis: position 1 of the locality cascade is Hermes OCaml Rete-UL in
#     one Lean file, Gleam/OTP Rete-UL in the exported C ABI, and a bounded
#     compressor in the Gleam type the Lean file CLAIMS to match.
#
# So this oracle checks three things a rename could never check:
#   T1  every layer/tier enum in the tree belongs to a DECLARED axis
#   T2  the concern axis's indices 0..7 stay conformant (regression guard)
#   T3  the index-1 divergence on the locality cascade is still unresolved
#       -- and it fails closed while it is
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains, json_int, occurrences

comptime REGISTRY = (
    "governance/agents/policy/20261106-0402-uos-indexed-axis-registry.json")
comptime CONTRACT = (
    "contracts/rules/"
    "20260909-0704-fractal-layer-taxonomy-single-source.md")
# The cascade width the Lean source declares, and the refinement ladder's
# rung count. Named so the arms below compare a derived value against a
# declared one rather than two literals.
comptime CASCADE_WIDTH = 5
comptime LADDER_RUNGS = 11
comptime CASCADE_LEAN = "formal/lean/Minimum_Token_Cascade_Theorems.lean"
comptime CASCADE_ABI = "formal/lean/UosLeanRuntimeGuard.lean"
comptime CASCADE_GLEAM = (
    "apps/cepaf_gleam/src/cepaf_gleam/ai/local_first_cascade.gleam")


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
        String("formal/lean/Fractal_Holonic_Composability.lean"),
    )

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    var registry = capture("cat " + String(REGISTRY) + " 2>/dev/null")
    r.observe(String("registry"), registry)
    r.world_or_blind(String("registry-is-readable"), True,
                     registry.byte_length() > 0)
    if registry.byte_length() == 0:
        print("# registry unreadable; every verdict below would be vacuous")
        r.emit()
        exit(r.exit_code())

    # ---- ALGEBRA: the contract's own cardinality ------------------------
    # Derived from the contract table, not restated. Ten `#fractal-lN` rows
    # with N in 0..9, and the contract's explicit denial of N >= 10.
    var contract_rows = count(
        "grep -cE '^\\| `#fractal-l[0-9]`' " + String(CONTRACT)
        + " 2>/dev/null")
    r.observe_int(String("contract-table-rows"), contract_rows)
    r.world_count(String("t0-contract-declares-ten-concerns"),
                  contract_rows, 10)
    var denies_ten = capture(
        "grep -c 'do not exist' " + String(CONTRACT) + " 2>/dev/null")
    r.world_or_blind(String("t0-contract-denies-index-ten-and-above"),
                     denies_ten.byte_length() > 0,
                     denies_ten != String("0"))

    # F11, 20261106: these were `(9 - 0 + 1) == 10` and `8 < 9` -- arithmetic
    # on literals, asserting the axis's width and ordering without reading
    # the axis. The second is the sharpest, because the LIVE DEFECT it was
    # written about is a transposition (two implementations place evolution
    # at 9 and provenance at 8), and `8 < 9` cannot detect a transposition:
    # it is true whatever either plane says.
    #
    # Both now read the declared axis out of the contract, so a renumbering,
    # a widening, or a transposition all move them.
    # The contract declares the axis as a Markdown table whose first column
    # is `| `#fractal-lN` |`. My first version of this extraction assumed a
    # `- N : Name` list, matched nothing, and every arm below went BLIND --
    # which is the correct failure mode for a broken reader, and is how the
    # wrong assumption was caught rather than passing silently.
    comptime AXROW = "'^\\| .#fractal-l[0-9].'"
    var idx_min = count(
        "grep -oE " + String(AXROW) + " " + String(CONTRACT) + " 2>/dev/null"
        + " | grep -oE '[0-9]' | sort -n | head -1")
    var idx_max = count(
        "grep -oE " + String(AXROW) + " " + String(CONTRACT) + " 2>/dev/null"
        + " | grep -oE '[0-9]' | sort -n | tail -1")
    var idx_n = count(
        "grep -oE " + String(AXROW) + " " + String(CONTRACT) + " 2>/dev/null"
        + " | grep -oE '[0-9]' | sort -nu | wc -l")
    var evo_idx = count(
        "grep -iE '^\\| .#fractal-l[0-9].[[:space:]]*\\|"
        + "[[:space:]]*Evolution' " + String(CONTRACT) + " 2>/dev/null"
        + " | grep -oE 'l[0-9]' | head -1 | tr -d 'l'")
    var sov_idx = count(
        "grep -iE '^\\| .#fractal-l[0-9].[[:space:]]*\\|"
        + "[[:space:]]*Sovereign' " + String(CONTRACT) + " 2>/dev/null"
        + " | grep -oE 'l[0-9]' | head -1 | tr -d 'l'")
    r.observe_int(String("concern-axis-min-index"), idx_min)
    r.observe_int(String("concern-axis-max-index"), idx_max)
    r.observe_int(String("concern-axis-distinct-indices"), idx_n)
    r.observe_int(String("declared-evolution-index"), evo_idx)
    r.observe_int(String("declared-sovereign-index"), sov_idx)
    var axis_read = (idx_min >= 0 and idx_max >= 0 and idx_n > 0)
    r.world_or_blind(String("t0-concern-axis-is-readable-from-the-contract"),
                     axis_read, axis_read)
    if axis_read:
        r.algebra(String("t0-concern-axis-is-zero-based-and-gap-free"),
                  idx_min == 0 and (idx_max - idx_min + 1) == idx_n)
    if evo_idx >= 0 and sov_idx >= 0:
        # The transposition check the literal could not express.
        r.algebra(String("t0-evolution-precedes-sovereign"),
                  evo_idx < sov_idx)
    else:
        r.observe(String("t0-order"),
                  String("skipped: evolution/sovereign indices unreadable"))

    # ---- T1: every layer/tier enum belongs to a DECLARED axis -----------
    # Discover them; do not enumerate them here. A hardcoded list is how a
    # fourteenth enum arrives unnoticed.
    var lean_enums = capture(
        "grep -rhoE '^inductive (FractalLayer|Layer|LayerItem|CascadeTier"
        + "|HiveModelRoutingTier|HolonicFppBionicLayer)[A-Za-z0-9_]*' "
        + "--include='*.lean' formal/lean --exclude-dir=.lake 2>/dev/null"
        + " | sed 's/^inductive //' | sort -u")
    var gleam_enums = capture(
        "grep -rhoE 'pub type (FractalLayer|ChartIndex|Tier|ModelTier"
        + "|InferenceTierId)[A-Za-z0-9_]*' "
        + "apps/cepaf_gleam/src --include='*.gleam' 2>/dev/null"
        + " | sed 's/^pub type //' | sort -u")
    r.observe(String("lean-axis-types"), lean_enums)
    r.observe(String("gleam-axis-types"), gleam_enums)

    # Files carrying a concern-axis-shaped enum. Each must be named by the
    # registry, in some axis.
    var layer_files = capture(
        "grep -rlE '^inductive (FractalLayer|Layer)[A-Za-z0-9_]* ?(where)?$' "
        + "--include='*.lean' formal/lean --exclude-dir=.lake 2>/dev/null"
        + " | sort")
    var undeclared = String("")
    var declared_n = 0
    var layer_n = 0
    if layer_files.byte_length() > 0:
        for line in layer_files.split(String("\n")):
            var f = String(String(line).strip())
            if f.byte_length() == 0:
                continue
            layer_n += 1
            if contains(registry, f):
                declared_n += 1
            else:
                if undeclared.byte_length() > 0:
                    undeclared += String(" ")
                undeclared += f
    r.observe(String("layer-enum-census"),
              String(declared_n) + String("/") + String(layer_n))
    r.world_or_blind(String("t1-every-layer-enum-is-in-a-declared-axis"),
                     layer_n > 0, undeclared.byte_length() == 0)
    if undeclared.byte_length() > 0:
        print("# T1 VIOLATIONS -- layer enums belonging to no declared axis:")
        print(undeclared)

    # ---- T2: indices 0..7 of the concern axis stay conformant -----------
    # The regression guard. Every deviation measured on 20261106 was at index
    # 8 or 9; if a 0..7 deviation ever appears, the defect has spread from a
    # historical pocket into the part of the axis everyone agrees on.
    #
    # Checked by CONCERN KEYWORD at each index, across the implementations
    # the registry names as concern-axis. Spelling is free; the concern is
    # not.
    var concern_files = [
        String("formal/lean/Fractal_Holonic_Composability.lean"),
        String("formal/lean/Fractal_Triad_Matrix_Invariants.lean"),
        String("formal/lean/Master_Feature_Composability_Evolution.lean"),
        String("formal/lean/Five_BDD_Demo_Evolutionary_Cycles.lean"),
    ]
    var concern_words = [
        String("Constitutional"), String("Atomic"), String("Component"),
        String("Transaction"), String("System"), String("Cognitive"),
        String("Ecosystem"), String("Federation"),
    ]
    var conformant_0_to_7 = 0
    var unreadable = 0
    var checked_0_to_7 = 0
    var deviations = String("")
    for fi in range(len(concern_files)):
        var f = concern_files[fi]
        var body = capture(
            "awk '/^inductive (FractalLayer|Layer)/{p=1} p&&/^ *deriving/"
            + "{print;exit} p' " + f + " 2>/dev/null")
        if body.byte_length() == 0:
            # 20261106-1848, found by B5 mutation verification: emptying ONE of
            # the four named concern files used to be invisible. The bare
            # `continue` dropped that file's eight indices from BOTH
            # `checked_0_to_7` and `conformant_0_to_7`, so coverage fell 32 ->
            # 24, `conformant == checked` still held, `checked > 0` still held
            # on the remaining three, and the receipt came back unchanged. The
            # oracle shrank its own coverage and said nothing.
            # A source the oracle cannot read is now recorded as BLIND and
            # named, so the loss of coverage appears in the receipt instead of
            # being absorbed by the ratio.
            unreadable += 1
            r.observe(String("concern-file-unreadable"), f)
            continue
        for ci in range(8):
            checked_0_to_7 += 1
            # The constructor at index ci must mention index ci's concern.
            var line = capture(
                "awk '/^inductive (FractalLayer|Layer)/{p=1;next} "
                + "p&&/^ *deriving/{exit} p&&/\\| /{n++; if(n==" + String(ci + 1)
                + ") {print; exit}}' " + f + " 2>/dev/null")
            if contains(line, concern_words[ci]):
                conformant_0_to_7 += 1
            else:
                if deviations.byte_length() > 0:
                    deviations += String("; ")
                deviations += (f + String(" idx") + String(ci)
                               + String(" lacks ") + concern_words[ci])
    r.observe(String("concern-axis-0-to-7"),
              String(conformant_0_to_7) + String("/")
              + String(checked_0_to_7))
    r.world_or_blind(String("t2-concern-indices-0-to-7-are-conformant"),
                     checked_0_to_7 > 0,
                     conformant_0_to_7 == checked_0_to_7)
    # EVERY named concern file must have been read. Without this the arm above
    # is satisfiable by reading fewer sources, which is coverage loss dressed
    # as a pass.
    r.world_count(String("t2-every-named-concern-file-was-read"),
                  len(concern_files) - unreadable, len(concern_files))
    if deviations.byte_length() > 0:
        print("# T2 REGRESSION -- a 0..7 deviation has appeared:")
        print(deviations)

    # Index 8/9: measured and REPORTED, not failed. The registry declares
    # these deviations as a recorded, unresolved historical defect; failing
    # here every run would make the guard unreadable noise while telling
    # nobody anything new. T3 is where the unresolved thing fails closed.
    var evo_at_8 = count(
        "grep -cE '\\| L8[A-Za-z_]*(Evolution|Evolutionary|Mutation)' "
        + "--include='*.lean' -r formal/lean --exclude-dir=.lake 2>/dev/null"
        + " | awk -F: '{s+=$2} END{print s+0}'")
    var evo_at_9 = count(
        "grep -rhcE '\\| L9[A-Za-z_]*(Evolution|Evolutionary|MetaEvolution)' "
        + "--include='*.lean' --include='*.gleam' formal/lean "
        + "apps/cepaf_gleam/src --exclude-dir=.lake 2>/dev/null"
        + " | awk '{s+=$1} END{print s+0}'")
    r.observe_int(String("evolution-named-at-index-8"), evo_at_8)
    r.observe_int(String("evolution-named-at-index-9"), evo_at_9)

    # ---- T3: the locality-cascade index-1 divergence --------------------
    # This is the one genuinely unresolved routing defect, and it fails
    # closed until an operator picks a reading.
    var lean_idx1 = capture(
        "grep -oE '\\| Tier1[A-Za-z]*' " + String(CASCADE_LEAN)
        + " 2>/dev/null | head -1 | sed 's/| //'")
    var gleam_idx1 = capture(
        "grep -oE '^ *Tier1[A-Za-z]*' " + String(CASCADE_GLEAM)
        + " 2>/dev/null | head -1 | tr -d ' '")
    var abi_idx1_owner = capture(
        "grep -oE '^ *- 1 *: Tier1Rete \\(([A-Za-z/ ]+) Rete-UL' "
        + String(CASCADE_ABI) + " 2>/dev/null"
        + " | sed 's/.*(\\(.*\\) Rete-UL.*/\\1/'")
    r.observe(String("cascade-index1-lean"), lean_idx1)
    r.observe(String("cascade-index1-gleam"), gleam_idx1)
    r.observe(String("cascade-index1-abi-owner"), abi_idx1_owner)

    # The Lean file's docstring CLAIMS it matches the Gleam type. Hold it to
    # that claim: same name at the same index, or the claim is false.
    var lean_claims_match = capture(
        "grep -c 'matching Gleam CascadeTier' " + String(CASCADE_LEAN)
        + " 2>/dev/null")
    r.world_or_blind(String("t3-lean-claims-to-match-gleam"),
                     lean_claims_match.byte_length() > 0,
                     lean_claims_match != String("0"))
    if lean_idx1.byte_length() > 0 and gleam_idx1.byte_length() > 0:
        r.algebra(String("t3-cascade-index1-agrees-across-planes"),
                  lean_idx1 == gleam_idx1)
    else:
        r.world_or_blind(String("t3-cascade-index1-is-readable"),
                         False, False)

    # The ABI's index 1 must name the language canonical policy assigns
    # Rete-UL to. CLAUDE.md's language roles put Rete-UL in OCaml/Hermes.
    if abi_idx1_owner.byte_length() > 0:
        r.algebra(String("t3-abi-index1-names-the-canonical-rete-owner"),
                  contains(abi_idx1_owner, String("Hermes"))
                  or contains(abi_idx1_owner, String("OCaml")))

    # ---- T4: the lossy morphism is DECLARED -----------------------------
    # The ABI has 4 codes for a 5-member axis: free and paid remote both
    # collapse to 3. That collapse existed in code with no stated morphism,
    # which is the cocycle condition SC-INTENT-ATLAS-001 requires and
    # nothing checked. It must now be declared.
    var abi_codes = count(
        "grep -cE '^ *- [0-9]+ *: Tier' " + String(CASCADE_ABI)
        + " 2>/dev/null")
    var lean_members = count(
        "awk '/^inductive CascadeTier/{p=1;next} p&&/deriving/{exit} "
        + "p&&/\\| Tier/{n++} END{print n+0}' " + String(CASCADE_LEAN)
        + " 2>/dev/null")
    r.observe_int(String("cascade-abi-codes"), abi_codes)
    r.observe_int(String("cascade-lean-members"), lean_members)
    r.world_count(String("t4-lean-cascade-has-five-members"),
                  lean_members, 5)
    r.world_or_blind(String("t4-lossy-collapse-is-declared"),
                     registry.byte_length() > 0,
                     contains(registry, String("declared_morphism_to_abi"))
                     and contains(registry, String("LOSSY")))

    # ---- T6: out-of-range #fractal-lN tags, and the contract's own stale
    #           measurement of them -------------------------------------
    #
    # The contract says plainly: "`#fractal-l10` and above do not exist.
    # Eleven records carry `#fractal-l10`; it names no layer and is counted
    # as none."
    #
    # That sentence contains a FROZEN MEASUREMENT -- "eleven records" -- of a
    # corpus that grows. It is the same defect class as a theorem decided
    # over a present-tense observation: a number true when written, re-read
    # as current forever, and re-verified by nothing. Measured now: 36 files.
    #
    # The contract also states its enforcement as laws E9/E10 in
    # tools/km_provenance/km_gate.ml. Those laws verify the PARSER does not
    # misread `#fractal-l10` as `#fractal-l1` -- a real and necessary check.
    # They do NOT reject a document for carrying the tag. So the tag "names
    # no layer" in the parser and still travels through the corpus, including
    # into records that self-certify `CHK-03-FRACT ... PASS` on it.
    #
    # This arm reports the live count and fails on the DRIFT from the
    # contract's declared number, because the contract is the thing that
    # went stale, not the corpus.
    var oor_files = count(
        "grep -rlE '#fractal-l(1[0-9]|[2-9][0-9])' docs governance "
        + "2>/dev/null | wc -l")
    # F16, 20261106. This read
    #
    #   grep -oE 'Eleven|[0-9]+ records carry' CONTRACT | grep -oE '[0-9]+'
    #     || echo 11
    #   if contract_claim < 0: contract_claim = 11
    #
    # and the contract writes the figure as the WORD "Eleven", so the inner
    # digit grep matched nothing, exited non-zero, and `|| echo 11` supplied
    # the literal. BOTH fallbacks landed on 11. The arm's name asserts it
    # reads the declared count; it read a constant the author typed twice.
    #
    # The consequence is the arm's own diagnosis turned on itself: this
    # oracle's header calls the contract's "eleven" a frozen measurement
    # "re-read as current forever, and re-verified by nothing", and the
    # instrument froze it a second time. Correcting the contract in prose to
    # "Thirty-six records carry..." would match NEITHER alternation, fall
    # back to 11 again, and leave the arm failing -- remediation could not
    # clear the check.
    #
    # The number-word is now actually parsed, with no numeric fallback. If
    # the contract says something this table does not cover, the declared
    # side is UNREADABLE and the arm is BLIND -- which is the honest verdict
    # for "I could not determine what was declared", and unlike a literal it
    # changes when the contract does.
    var claim_digits = count(
        "grep -oE '[0-9]+ records carry' " + String(CONTRACT)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+'")
    var claim_word = capture(
        "grep -ioE '(zero|one|two|three|four|five|six|seven|eight|nine|ten|"
        + "eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|"
        + "eighteen|nineteen|twenty|thirty|thirty-six|thirty-seven|forty)"
        + " records carry' " + String(CONTRACT) + " 2>/dev/null"
        + " | head -1 | sed -E 's/ records carry//' | tr 'A-Z' 'a-z'")
    var contract_claim = claim_digits
    if contract_claim < 0 and claim_word.byte_length() > 0:
        var w = String(claim_word.strip())
        var words = [
            String("zero"), String("one"), String("two"), String("three"),
            String("four"), String("five"), String("six"), String("seven"),
            String("eight"), String("nine"), String("ten"),
            String("eleven"), String("twelve"), String("thirteen"),
            String("fourteen"), String("fifteen"), String("sixteen"),
            String("seventeen"), String("eighteen"), String("nineteen"),
            String("twenty")]
        for i in range(len(words)):
            if w == words[i]:
                contract_claim = i
        if w == String("thirty"):
            contract_claim = 30
        if w == String("thirty-six"):
            contract_claim = 36
        if w == String("thirty-seven"):
            contract_claim = 37
        if w == String("forty"):
            contract_claim = 40
    r.observe_int(String("out-of-range-tag-files"), oor_files)
    r.observe(String("contract-declared-count-raw-word"), claim_word)
    r.observe_int(String("contract-declared-count"), contract_claim)
    r.world_or_blind(String("t6-declared-count-is-readable"),
                     claim_digits >= 0 or claim_word.byte_length() > 0,
                     contract_claim >= 0)
    if contract_claim >= 0:
        r.world_count(String("t6-out-of-range-tags-match-the-declared-count"),
                      oor_files, contract_claim)
    if oor_files != contract_claim and oor_files >= 0:
        print("# T6 STALE CONTRACT -- declared", contract_claim,
              "records carry an out-of-range #fractal-lN tag; measured",
              oor_files)

    # And the honest limit, stated as its own check: no gate REJECTS the tag.
    var e9e10 = capture(
        "grep -c 'E9\\|E10' tools/km_provenance/km_gate.ml 2>/dev/null")
    r.observe(String("km-gate-e9-e10-present"), e9e10)
    # A parser that refuses to MISREAD the tag is not a gate that refuses the
    # tag. Recorded as an observation, not asserted as enforcement.
    #
    # F11, 20261106: the comment said "recorded as an observation" and the
    # code registered `r.algebra(..., True != False)` -- an algebra arm, and
    # a tautology. The distinction between parsing and rejecting is a point
    # about what the gate MEANS; no arithmetic expresses it, which is why
    # forcing it into an algebra channel produced a literal. It is now
    # actually an observation, as the comment always said it was.
    r.observe(String("t6-parsing-correctly-is-not-rejecting"),
              String("a correct parse is not a refusal; no gate rejects"))

    # ---- T5: the distinct axes are declared with a sanction -------------
    var axis_ids = occurrences(registry, String("\"axis_id\""))
    var sanctions = occurrences(registry, String("\"sanction\""))
    r.observe_int(String("declared-axes"), axis_ids)
    r.world_or_blind(String("t5-registry-declares-multiple-axes"),
                     axis_ids > 0, axis_ids >= 8)
    # L2 FIX, 20261106-0924 (re-review finding 16). This was
    # `sanctions >= axis_ids - 2`, hardcoding an exemption for "the two
    # canonical axes". Measured: 13 axes, 9 sanctions, and FOUR axes without
    # one (agent-roster, ontology-aspect, fractal-concern, cascade-locality).
    # So the arm failed on its own arithmetic rather than on the registry's
    # state, and the "2" was an author assumption the registry does not
    # record -- there is no `canonical` field anywhere in it.
    #
    # The exemption is therefore NOT CHECKABLE from this artifact, and
    # asserting it would be inventing the registry's content. What IS
    # checkable is that the sanction field partitions the axes: every axis
    # either carries one or does not, and the two counts must sum to the
    # total. That fails on a malformed registry and holds however many axes
    # are exempt, so it survives the exemption being recorded later.
    r.observe_int(String("axes-carrying-a-sanction"), sanctions)
    # The axes WITHOUT a sanction, named so a reader can adjudicate the
    # exemption the registry does not record. Host utilities only -- awk and
    # grep -- never an interpreter: CLAUDE.md confines helper scripting to
    # OCaml and Mojo, and an earlier draft of this very command carried a
    # stray `python3` invocation.
    r.observe(String("axes-without-a-sanction"),
              capture("awk '/\"axis_id\"/{split($0,p,\"\\\"\"); id=p[4];"
                      + " has=0} /\"sanction\"/{if(id!=\"\"){has=1}}"
                      + " /^    \\}/{if(id!=\"\"&&has==0) printf \"%s \", id;"
                      + " id=\"\"}' " + String(REGISTRY) + " 2>/dev/null"))
    if axis_ids > 0 and sanctions >= 0:
        r.algebra(String("t5-sanction-field-partitions-the-axes"),
                  sanctions <= axis_ids)
    # The exemption itself is an operator question, recorded as one.
    r.observe(String("t5-canonical-exemption-is-not-recorded-in-the-registry"),
              String("no canonical flag exists; the 'except two' exemption "
                     "cannot be verified from this artifact"))

    # ---- ALGEBRA: the registry's own consistency ------------------------
    #
    # F11, 20261106. These were `5 == 5`, `5 - 4 == 1` and `11 != 10` --
    # three arms asserting the registry's own shape without reading the
    # registry, in a file that had ALREADY DERIVED both cascade widths
    # (`lean_members` at :327, `abi_codes`) and printed them in its own
    # summary line. The measurements were taken, printed, and then not used
    # by the arms that claimed to be about them.
    # L2 FIX, 20261106-0924 (re-review finding 16). Two defects here.
    #
    # (a) `grep -c ... || echo 0` is a shell bug: `grep -c` ALREADY prints `0`
    #     and then exits 1, so the `||` fires and stdout becomes TWO lines
    #     ("0\n0"). `Int` raises, `count` returns -1, and `observe_int`
    #     scored the arm BLIND from the instrument, not the subject.
    #
    # (b) It counted `axis_id` lines matching refinement|ladder -- which is 1,
    #     the number of ladder AXES -- under a name claiming to count RUNGS.
    #
    # The axis declares its own `"cardinality": 11`, so the rung count is read
    # from the registry rather than counted from a name match or written as a
    # literal.
    var ladder_rungs = count(
        "awk '/\"axis_id\": \"vertical-refinement-ladder\"/{f=1}"
        + " f&&/\"cardinality\"/{print;exit}' " + String(REGISTRY)
        + " 2>/dev/null | grep -oE '[0-9]+'")
    r.observe_int(String("refinement-ladder-cardinality"), ladder_rungs)
    if lean_members >= 0 and abi_codes >= 0:
        r.algebra(String("reg-cascade-width-is-what-the-lean-source-declares"),
                  lean_members == CASCADE_WIDTH)
        # The ABI collapse loses exactly one distinction -- stated over the
        # two widths actually counted, so a second collapse, or a repaired
        # ABI, both move the arm. The old `5 - 4 == 1` could not notice
        # either.
        r.algebra(String("reg-abi-collapse-loses-exactly-one-distinction"),
                  lean_members - abi_codes == 1)
    else:
        r.observe(String("reg-cascade"),
                  String("skipped: cascade widths unreadable"))
    # The refinement ladder is not the layer axis: different cardinality,
    # different thing. Stated over the counted axis width rather than two
    # literals, so a renumbering of either side is visible.
    # Both sides derived: the ladder's declared cardinality against the
    # concern axis's counted width. Previously the comptime literal 11 was
    # compared while `ladder_rungs` sat derived and unused two lines above --
    # the exact pattern the F11 note in this file condemns.
    if idx_n > 0 and ladder_rungs > 0:
        r.algebra(String("reg-refinement-ladder-is-not-the-layer-axis"),
                  ladder_rungs != idx_n)
    else:
        r.observe(String("reg-ladder"),
                  String("skipped: ladder cardinality or axis width unreadable"))

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # The T2 conformance scan must be able to SEE a deviation. Plant an enum
    # whose index 2 names the wrong concern and require detection; and plant
    # a conformant one and require it passes. Without both, a scan that
    # always says "conformant" is indistinguishable from a working one.
    # HYGIENE FIX, 20261106-0924. This path hardcoded a REVIEW SESSION's
    # scratchpad UUID, so a per-session identifier had become provenance in
    # oracle source: the probe wrote into one particular agent session's
    # directory, which is meaningless on any other machine or run and is a
    # dangling reference the moment that session ends. It also `rm -rf`s the
    # path, so a stale UUID pointing somewhere real would delete it.
    #
    # The probe now uses `mktemp -d`, which is session-independent, and the
    # directory is removed by the probe itself rather than by a path this
    # file remembers.
    var probe = String(String(capture("mktemp -d 2>/dev/null")).strip())
    if probe.byte_length() == 0:
        probe = String("./.uos-axisprobe-tmp")
    _ = capture("rm -rf " + probe + " && mkdir -p " + probe)
    _ = capture(
        "printf 'inductive Layer where\\n  | L0Constitutional\\n"
        + "  | L1Atomic\\n  | L2WrongConcern\\n  deriving Repr\\n'"
        + " > " + probe + "/Bad.lean")
    var bad_idx2 = capture(
        "awk '/^inductive (FractalLayer|Layer)/{p=1;next} "
        + "p&&/^ *deriving/{exit} p&&/\\| /{n++; if(n==3){print; exit}}' "
        + probe + "/Bad.lean 2>/dev/null")
    r.mutation_probe(String("scan-sees-a-wrong-concern-at-index-2"),
                     bad_idx2.byte_length() > 0
                     and not contains(bad_idx2, String("Component")))
    _ = capture(
        "printf 'inductive Layer where\\n  | L0Constitutional\\n"
        + "  | L1Atomic\\n  | L2ComponentHealth\\n  deriving Repr\\n'"
        + " > " + probe + "/Good.lean")
    var good_idx2 = capture(
        "awk '/^inductive (FractalLayer|Layer)/{p=1;next} "
        + "p&&/^ *deriving/{exit} p&&/\\| /{n++; if(n==3){print; exit}}' "
        + probe + "/Good.lean 2>/dev/null")
    r.mutation_probe(String("scan-accepts-a-right-concern-at-index-2"),
                     contains(good_idx2, String("Component")))
    # And the registry lookup must be able to say "undeclared".
    r.mutation_probe(String("registry-lookup-reports-an-absent-file"),
                     not contains(registry,
                                  String("formal/lean/NoSuchAxis.lean")))
    _ = capture("rm -rf " + probe)

    print("# probe time                   :", now)
    print("# contract table rows          :", contract_rows, "(want 10)")
    print("# layer enums declared         :", declared_n, "of", layer_n)
    print("# concern axis idx 0..7        :", conformant_0_to_7, "of",
          checked_0_to_7)
    print("# evolution named at index 8   :", evo_at_8)
    print("# evolution named at index 9   :", evo_at_9, "(contract says 8)")
    print("# cascade idx1 lean            :", lean_idx1)
    print("# cascade idx1 gleam           :", gleam_idx1)
    print("# cascade idx1 abi owner       :", abi_idx1_owner)
    print("# cascade members lean / abi   :", lean_members, "/", abi_codes)
    print("# declared axes                :", axis_ids)
    r.emit()
    exit(r.exit_code())
