# ==========================================================================
# twin_coverage_oracle — measures what fraction of the system has a VERIFIED
# digital twin, and makes every coverage claim falsifiable.
#
# Lean subject: formal/lean/HolonicFppBionicUnifiedLeanInfrastructureAndDigitalTwins.lean
#   (the twin that asserts fppActors := 40 in six places with no enumeration
#    behind any of them; this oracle supplies the enumeration)
#
# THE OBJECTIVE THIS ANSWERS
# --------------------------
# "all functionality must have ontology, must have digital twin that has all
# functionality verified, covers all system aspects with comprehensive
# checks."
#
# That objective cannot be satisfied by assertion, and every previous attempt
# in this tree asserted it: nine documents claim a completion or 100% status
# that nothing re-measures, led by "100% KPI mapping across all 184 system
# facets". So this oracle does the only honest thing available -- it MEASURES
# the gap and names it.
#
# FOUR COVERAGE STATES, AND WHY BLIND IS NOT COVERAGE
# ---------------------------------------------------
#   VERIFIED    a Mojo oracle OBSERVES the live subsystem and a Lean twin
#               proves the algebra. Two-key.
#   BLIND       an observer started and the subsystem does not expose the
#               evidence. NOT coverage. Counting it as coverage is precisely
#               the defect this architecture exists to prevent.
#   MODELLED    a Lean twin exists and nothing observes the subsystem. The
#               model can go stale with nothing noticing -- the
#               `observationNow` defect at subsystem scale.
#   UNMODELLED  neither. Stated, not omitted.
#
# WHY THE FIRST MEASUREMENT WAS THROWN AWAY
# -----------------------------------------
# A keyword probe matched each subsystem id against formal/lean and
# formal/mojo and reported 21 VERIFIED of 40. That is not trustworthy: a
# keyword in an oracle's COMMENT counts as coverage under it, and three
# separate false positives earlier in this work came from exactly that class
# of loose matching. The ledger's numbers are lower and true.
#
# WHAT MAKES THE LEDGER FALSIFIABLE
# ---------------------------------
# Every VERIFIED entry names specific check names in a specific oracle. This
# oracle greps the named oracle for each named check and FAILS if it is
# absent. A coverage claim therefore cannot be inflated by naming a check
# nobody wrote, and cannot quietly survive a rename or a deletion. That is
# the difference between a coverage report and a coverage claim.
#
# authority NONE. EV ceiling 93. A measured 27.5% is not an admission of
# anything; it is the size of the gap.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains, json_int, occurrences

# The declared subsystem count, compared against the counted mesh in a
# world arm rather than pinned inside a control.
comptime MESH_SUBSYSTEMS = 40
comptime HOLONIC_TWIN = "formal/lean/HolonicFppBionicUnifiedLeanInfrastructureAndDigitalTwins.lean"
comptime LEDGER = (
    "governance/agents/policy/"
    "20261106-0428-uos-subsystem-twin-coverage-ledger.json")
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
        String("formal/lean/"
               + "HolonicFppBionicUnifiedLeanInfrastructureAndDigitalTwins.lean"),
    )

    # ---- THE DECLARED SUBJECT IS ACTUALLY READ -------------------------
    # 20261106-1848, found by B5 mutation verification -- and the fourth
    # instance of the same defect, hidden longest because the instrument's own
    # force-include condition required the declared path to appear as a WHOLE
    # string literal, which this one never does: it is concatenated across two
    # source lines. Emptying it to zero bytes left the receipt unchanged.
    # Every reference to it in this source was a comment or the Receipt's
    # subject field. A declared subject is not a read subject.
    #
    # The expected set is the ontology theorem names the twin declares and
    # this oracle's coverage claims rest on, asserted by NAME rather than by a
    # count harvested from the file.
    var holonic_thms = count(
        "grep -cE '^theorem ' " + String(HOLONIC_TWIN) + " 2>/dev/null")
    r.world_or_blind(String("declared-holonic-twin-is-readable"),
                     holonic_thms >= 0, holonic_thms > 0)
    var holonic_cited = [String("THM_HFB_ONT_01"), String("THM_HFB_ONT_02"),
                         String("THM_HFB_ONT_03"), String("THM_HFB_ONT_04"),
                         String("THM_HFB_ONT_05")]
    var holonic_present = 0
    for hi in range(len(holonic_cited)):
        if count("grep -cE '^theorem " + holonic_cited[hi] + "' "
                 + String(HOLONIC_TWIN) + " 2>/dev/null") > 0:
            holonic_present += 1
    r.world_count(String("declared-holonic-twin-carries-every-cited-theorem"),
                  holonic_present, len(holonic_cited))

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    var ledger = capture("cat " + String(LEDGER) + " 2>/dev/null")
    r.observe(String("ledger"), ledger)
    r.world_or_blind(String("ledger-is-readable"), True,
                     ledger.byte_length() > 0)
    if ledger.byte_length() == 0:
        print("# ledger unreadable; every number below would be invented")
        r.emit()
        exit(r.exit_code())

    # ---- the subsystem inventory, DERIVED not restated -------------------
    # The Lean twin asserts `fppActors := 40` in six differently-named fields
    # and derives it nowhere. The enumeration lives in Gleam. Read it.
    var ids = capture(
        "grep -oE '\"l[0-9]_(apps|engines|services|intel)_[a-z0-9_]+\"' "
        + String(FPP_MESH) + " 2>/dev/null | tr -d '\"' | sort -u")
    # F13, 20261106: this line was `_ = occurrences(ids, String("l"))` --
    # a value computed and explicitly discarded, in the very file whose
    # sibling guard (`proof_plane_guard_oracle`, arm G6) exists to flag that
    # idiom in Lean. Removed rather than wired to anything, because nothing
    # downstream needed it: counting the letter "l" in a newline-joined id
    # list measures nothing, and inventing a use for it would be worse than
    # deleting it.
    var id_lines = count(
        "grep -oE '\"l[0-9]_(apps|engines|services|intel)_[a-z0-9_]+\"' "
        + String(FPP_MESH) + " 2>/dev/null | tr -d '\"' | sort -u | wc -l")
    r.observe_int(String("subsystem-enumeration"), id_lines)
    r.world_count(String("inventory-enumerates-forty-subsystems"),
                  id_lines, 40)

    # Four domains x ten layers. Checked, because 40 could also be 8x5 or
    # 20x2 and the twin's "4 domains x L0..L9" claim would then be false.
    var per_layer_ok = 0
    for L in range(10):
        var n = count(
            "grep -oE '\"l" + String(L)
            + "_(apps|engines|services|intel)_[a-z0-9_]+\"' "
            + String(FPP_MESH) + " 2>/dev/null | sort -u | wc -l")
        if n == 4:
            per_layer_ok += 1
    r.observe(String("layers-with-exactly-four"), String(per_layer_ok))
    r.world_count(String("every-layer-carries-exactly-four-subsystems"),
                  per_layer_ok, 10)

    # ---- ALGEBRA: the shape of the inventory ----------------------------
    #
    # F11, 20261106: this was `4 * 10 == 40`, arithmetic on three literals.
    # It asserted the inventory's SHAPE without consulting the inventory.
    # The claim with content is that the enumeration actually found a
    # domains-by-layers grid, so both factors and the product are now
    # derived from what was counted.
    var domains_n = count(
        "grep -oE '\"l[0-9]_(apps|engines|services|intel)_[a-z0-9_]+\"' "
        + String(FPP_MESH) + " 2>/dev/null | tr -d '\"'"
        + " | sed -E 's/^l[0-9]_([a-z]+)_.*/\\1/' | sort -u | wc -l")
    var layers_n = count(
        "grep -oE '\"l[0-9]_(apps|engines|services|intel)_[a-z0-9_]+\"' "
        + String(FPP_MESH) + " 2>/dev/null | tr -d '\"'"
        + " | sed -E 's/^l([0-9])_.*/\\1/' | sort -u | wc -l")
    r.observe_int(String("domains-counted"), domains_n)
    r.observe_int(String("layers-counted"), layers_n)
    if domains_n > 0 and layers_n > 0 and id_lines > 0:
        r.algebra(String("cover-domains-times-layers-is-the-inventory"),
                  domains_n * layers_n == id_lines)
    else:
        r.observe(String("inventory-shape"),
                  String("skipped: enumeration unreadable"))
    # Coverage states partition the inventory: they must sum to the total and
    # must not overlap. A ledger whose states did not partition would be
    # reporting a fraction of something other than the system.
    var v = json_int(ledger, String("verified_count"))
    var b = json_int(ledger, String("blind_count"))
    var m = json_int(ledger, String("modelled_count"))
    var u = json_int(ledger, String("unmodelled_count"))
    r.observe(String("declared-states"),
              String(v) + String("/") + String(b) + String("/")
              + String(m) + String("/") + String(u))
    var states_readable = (v >= 0 and b >= 0 and m >= 0 and u >= 0)
    r.world_or_blind(String("coverage-states-are-readable"), True,
                     states_readable)
    if states_readable:
        # F10, 20261106: compared against the literal 40 while `id_lines`
        # was derived 20 lines above and never used. The partition must sum
        # to the INVENTORY, not to a remembered number.
        if id_lines > 0:
            r.algebra(String("cover-states-partition-the-inventory"),
                      v + b + m + u == id_lines)
        else:
            r.observe(String("partition"),
                      String("skipped: inventory unreadable"))
        # ---- THE PARTITION, DERIVED FROM THE ENTRIES ------------------
        #
        # L1/L2 FIX, 20261106-0924 (re-review finding 8). The previous arm
        # was `cover-verified-and-blind-are-disjoint` evaluating
        # `v + b <= id_lines if id_lines > 0 else v + b >= 0`. Neither branch
        # carried information: the first is strictly implied by the partition
        # arm above (`v+b+m+u == id_lines` with m,u >= 0), so it cannot fail
        # independently, and the `else` branch `v + b >= 0` is a tautology
        # under the enclosing `states_readable` guard -- which meant an
        # UNREADABLE inventory produced a PASSING algebra arm, keeping the
        # receipt out of VACUOUS. A variable `both` was computed for the
        # name-intersection the comment promised and then only observed.
        #
        # The declared `measured_coverage` summary and the per-entry `state`
        # fields are two independent recordings of one partition, so the
        # honest arm compares them. It immediately finds a real drift: the
        # entries say VERIFIED 12 / MODELLED 17, the summary says 11 / 18 --
        # one subsystem was promoted and the summary was never updated. The
        # old arm could not have seen that, because it only ever compared the
        # summary against itself.
        #
        # The ledger carries one SENTINEL entry (`__fpp_mesh_itself__`, the
        # mesh file rather than a subsystem) whose state is subtracted, or
        # the BLIND comparison would be off by one.
        var sentinel_state = capture(
            "awk '/\"id\": \"__/{f=1} f&&/\"state\"/{print;exit}' "
            + String(LEDGER) + " 2>/dev/null"
            + " | grep -oE '\"[A-Z_]+\"' | tr -d '\"'")

        def state_count(st: String, sentinel: String) -> Int:
            var total = count("grep -c '\"state\": \"" + st + "\"' "
                              + String(LEDGER) + " 2>/dev/null")
            if total < 0:
                return -1
            var adj = 0
            if sentinel == st:
                adj = 1
            return total - adj

        var e_ver = state_count(String("VERIFIED"), sentinel_state)
        var e_bli = state_count(String("BLIND"), sentinel_state)
        var e_mod = state_count(String("MODELLED"), sentinel_state)
        var e_unm = state_count(String("UNMODELLED"), sentinel_state)
        r.observe(String("entry-states-ver-bli-mod-unm"),
                  String(e_ver) + String("/") + String(e_bli) + String("/")
                  + String(e_mod) + String("/") + String(e_unm))
        r.observe(String("ledger-sentinel-state"), sentinel_state)
        var entries_read = (e_ver >= 0 and e_bli >= 0 and e_mod >= 0
                            and e_unm >= 0)
        r.world_or_blind(String("entry-states-are-readable"),
                         entries_read, entries_read)
        if entries_read:
            # The two recordings must agree, state by state.
            r.world_count(String("declared-verified-matches-the-entries"),
                          e_ver, v)
            r.world_count(String("declared-blind-matches-the-entries"),
                          e_bli, b)
            r.world_count(String("declared-modelled-matches-the-entries"),
                          e_mod, m)
            r.world_count(String("declared-unmodelled-matches-the-entries"),
                          e_unm, u)
            # And the entries themselves must partition the inventory.
            if id_lines > 0:
                r.algebra(String("entry-states-partition-the-inventory"),
                          e_ver + e_bli + e_mod + e_unm == id_lines)
            # Disjointness, actually tested: no subsystem may carry two
            # states, so the per-state counts must sum to the entry count
            # rather than exceed it.
            var entry_total = count(
                "grep -c '\"state\": \"' " + String(LEDGER)
                + " 2>/dev/null")
            var sentinels = count(
                "grep -c '\"id\": \"__' " + String(LEDGER) + " 2>/dev/null")
            r.observe_int(String("ledger-entry-total"), entry_total)
            r.observe_int(String("ledger-sentinel-entries"), sentinels)
            if entry_total >= 0 and sentinels >= 0:
                r.algebra(String("cover-states-are-mutually-disjoint"),
                          e_ver + e_bli + e_mod + e_unm
                          == entry_total - sentinels)
        # And the blind count is REPORTED, never required to be nonzero.
        r.observe_int(String("blind-subsystems-remaining"), b)

    # ---- THE FALSIFIABILITY ARM -----------------------------------------
    # Every check name a VERIFIED entry claims must EXIST in the oracle it
    # names. Without this the ledger is a wish list: a claim naming a check
    # nobody wrote would read as coverage forever.
    var claimed = capture(
        "tr -d '\\n' < " + String(LEDGER) + " 2>/dev/null"
        + " | grep -oE '\"oracle\"[[:space:]]*:[[:space:]]*"
        + "\"[a-z0-9_]+\\.mojo\"'"
        + " | grep -oE '[a-z0-9_]+\\.mojo' | sort -u")
    r.observe(String("oracles-named-by-ledger"), claimed)

    var missing_oracles = String("")
    var oracle_n = 0
    if claimed.byte_length() > 0:
        for line in claimed.split(String("\n")):
            var o = String(String(line).strip())
            if o.byte_length() == 0:
                continue
            oracle_n += 1
            var present = capture(
                "test -f formal/mojo/" + o + " && echo yes")
            if present != String("yes"):
                if missing_oracles.byte_length() > 0:
                    missing_oracles += String(" ")
                missing_oracles += o
    r.observe(String("named-oracle-count"), String(oracle_n))
    r.world_or_blind(String("every-named-oracle-exists"),
                     oracle_n > 0, missing_oracles.byte_length() == 0)
    if missing_oracles.byte_length() > 0:
        print("# COVERAGE CLAIMS NAMING AN ABSENT ORACLE:")
        print(missing_oracles)

    # ---- ATTRIBUTION, NOT MERELY EXISTENCE ------------------------------
    #
    # F10-adjacent, found 20261106 while fixing this file. The union arm
    # below verifies a claimed check exists in SOME oracle, and its comment
    # defends that choice: "a check legitimately moves between oracles; what
    # must never happen is a claimed check existing nowhere." That reasoning
    # is sound for EXISTENCE and it is kept.
    #
    # But a ledger entry does not merely claim a check exists. It claims
    # `"verified_by": {"oracle": X, "checks": [C]}` -- that oracle X verifies
    # this subsystem BY C. If C lives in oracle Y, that claim is false even
    # though C exists, and the union arm cannot see it. Tightening the test
    # to per-oracle found 11 of 48 attributions crediting an oracle that
    # does not contain the named check: port arms credited to core_evo that
    # live in monitoring_governance, writer-allowlist arms credited to
    # mcp_name_ownership that live in mcp_gateway, and an analytics arm
    # credited to monitoring_governance that lives in context_path_kpi.
    #
    # The consequence is not cosmetic. Nobody ever confirmed the credited
    # oracle covers that subsystem, so the coverage number counted evidence
    # that was never produced where the ledger says it was.
    # The extraction NORMALISES whitespace first. This is the F4 lesson
    # applied to a local artifact rather than an HTTP body: the first version
    # of this arm matched `"oracle": "X", "checks": [...]` on a single line,
    # and the moment the ledger was re-serialised with indentation the
    # pattern matched NOTHING -- so the pipeline emitted no "bad" lines,
    # `wc -l` returned 0, and the arm PASSED by seeing nothing at all. It
    # reported clean on the very run that broke it. Both arms below are now
    # gated on having extracted a non-zero number of attributions, so an
    # extraction failure is BLIND and never a pass.
    var attributions = count(
        "tr -d '\\n' < " + String(LEDGER) + " 2>/dev/null"
        + " | grep -oE '\"oracle\"[[:space:]]*:[[:space:]]*"
        + "\"[a-z0-9_]+\\.mojo\"' | wc -l")
    r.observe_int(String("ledger-attribution-blocks"), attributions)
    var misattributed = count(
        "tr -d '\\n' < " + String(LEDGER) + " 2>/dev/null"
        + " | sed -E 's/[[:space:]]+/ /g'"
        + " | grep -oE '\"oracle\" ?: ?\"[a-z0-9_]+\\.mojo\", "
        + "?\"checks\" ?: ?\\[[^]]*\\]'"
        + " | sed -E 's/\"oracle\" ?: ?\"//; "
        + "s/\", ?\"checks\" ?: ?\\[/|/; s/\\]$//'"
        + " | while IFS='|' read -r orc rest; do"
        + " for c in $(printf '%s' \"$rest\" | tr ',' '\\n'"
        + " | tr -d ' \"'); do"
        + " test -n \"$c\" || continue;"
        + " grep -q -- \"$c\" \"formal/mojo/$orc\" 2>/dev/null"
        + " || echo bad; done; done | wc -l")
    r.observe_int(String("misattributed-ledger-checks"), misattributed)
    r.world_or_blind(String("every-claimed-check-is-in-the-oracle-credited"),
                     attributions > 0 and misattributed >= 0,
                     misattributed == 0)

    # Now the check names themselves. Each must appear as a check in SOME
    # oracle. Checked against the union rather than per-oracle, because a
    # check legitimately moves between oracles; what must never happen is a
    # claimed check existing nowhere.
    # `r\.world[a-z_]*\(` replaces the hand-maintained alternation
    # `(world|world_or_blind|world_json|world_count|world_count_fresh)` on
    # 20261107-2353. The list had to be edited every time a world helper was
    # added to oracle_substrate.mojo, and it DRIFTED TWICE IN ONE DAY: once
    # when `world_count_fresh` landed (F-W-14) and again when `world_status`
    # landed (F-W-23). Both times the symptom was this arm reporting
    # `world:no-coverage-claim-names-a-phantom-check` -- an accusation that
    # the ledger claims a check nobody implements -- when in truth the check
    # existed and the census could not see it. A phantom-check alarm that
    # fires on the CENSUS being out of date, rather than on the ledger being
    # wrong, points the reader at the wrong file.
    #
    # The prefix form cannot drift, because every world arm in the substrate
    # is by construction named `world...`. The remaining coupling is the one
    # that should exist: an arm that is not a `r.world*` call is not a world
    # check, and should not be counted as one.
    var all_checks = capture(
        "grep -hoE 'r\\.world[a-z_]*"
        + "\\(String\\(\"[a-z0-9:-]+' formal/mojo/*_oracle.mojo 2>/dev/null"
        + " | sed 's/.*String(\"//' | sort -u")
    # Whitespace-normalised, same reason as the attribution arm above.
    var claimed_checks = capture(
        "tr -d '\\n' < " + String(LEDGER) + " 2>/dev/null"
        + " | sed -E 's/[[:space:]]+/ /g'"
        + " | grep -oE '\"checks\" ?: ?\\[[^]]*\\]'"
        + " | grep -oE '\"[a-z0-9:-]+\"' | tr -d '\"' | sort -u")
    r.observe(String("checks-claimed-by-ledger"),
              String(occurrences(claimed_checks, String("\n")) + 1))

    var phantom = String("")
    var checked_n = 0
    if claimed_checks.byte_length() > 0 and all_checks.byte_length() > 0:
        for line in claimed_checks.split(String("\n")):
            var c = String(String(line).strip())
            if c.byte_length() == 0 or c == String("checks"):
                continue
            checked_n += 1
            if not contains(all_checks, c):
                if phantom.byte_length() > 0:
                    phantom += String(" ")
                phantom += c
    r.observe(String("checks-verified-to-exist"), String(checked_n))
    r.world_or_blind(String("no-coverage-claim-names-a-phantom-check"),
                     checked_n > 0, phantom.byte_length() == 0)
    if phantom.byte_length() > 0:
        print("# PHANTOM CHECKS -- claimed as coverage, exist nowhere:")
        print(phantom)

    # ---- the honest headline --------------------------------------------
    # Reported as an OBSERVATION, never as a world PASS. There is no
    # threshold at which a coverage fraction becomes a pass, and inventing
    # one would be the same move as a 100%-complete banner.
    if states_readable:
        # F18, 20261106: named "...-percent" while computing per-mille
        # (`(v * 1000) // 40` gives 275 for v=11, which reads as 275%). The
        # denominator was also the literal 40 rather than the derived
        # inventory. Both fixed; the unit is now in the name.
        if id_lines > 0:
            r.observe_int(String("verified-fraction-per-mille"),
                          (v * 1000) // id_lines)

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # The falsifiability arm must be able to SEE a phantom. Plant a claim for
    # a check that cannot exist and require detection. If this passes while
    # the arm above reports clean, the arm works; if it fails, every coverage
    # number here is a wish.
    var fake = String("this-check-was-never-written-anywhere-at-all")
    r.mutation_probe(String("phantom-detector-sees-an-invented-check"),
                     not contains(all_checks, fake))
    # And it must ACCEPT a check that does exist, or it would reject
    # everything and look rigorous while measuring nothing.
    r.mutation_probe(String("phantom-detector-accepts-a-real-check"),
                     contains(all_checks, String("gateway-handshake")))
    # The inventory must be derived, not defaulted: an empty grep must not
    # silently read as forty.
    # SC-VP-04 ADJUDICATED 20261106-1230: a genuine SUBJECT pin. `id_lines`
    # is counted from the FPP mesh, so the mesh legitimately reaching 41
    # subsystems would fail the probe and report VACUOUS -- growth of the
    # system read as an oracle that cannot discriminate. The count belongs in
    # a world arm; the probe tests that the derivation RAN.
    r.mutation_probe(String("inventory-is-derived-not-defaulted"),
                     id_lines > 0 and ids.byte_length() > 0)
    r.world_or_blind(String("inventory-matches-the-declared-mesh-size"),
                     id_lines >= 0, id_lines == MESH_SUBSYSTEMS)

    print("# probe time                   :", now)
    print("# subsystems enumerated        :", id_lines, "(want 40)")
    print("# layers with exactly four     :", per_layer_ok, "of 10")
    print("# VERIFIED / BLIND             :", v, "/", b)
    print("# MODELLED / UNMODELLED        :", m, "/", u)
    print("# oracles named by ledger      :", oracle_n)
    print("# coverage claims checked      :", checked_n)
    print("# phantom claims               :",
          0 if phantom.byte_length() == 0 else 1)
    print("#")
    print("# VERIFIED FRACTION            :", v, "of 40")
    print("# (BLIND is not coverage. MODELLED means a Lean twin asserts")
    print("#  something about the subsystem that nothing re-measures.)")
    r.emit()
    exit(r.exit_code())
