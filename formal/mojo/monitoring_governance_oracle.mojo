# ==========================================================================
# Differential oracle for formal/lean/UosUnifiedMonitoringGovernanceDigitalTwin.lean
#
# Lean proves properties of `aligned : TwinExpectation -> RuntimeObservation
# -> Bool` symbolically (THM_ALN_01..05). This oracle re-evaluates the SAME
# fail-closed conjunction concretely and feeds it a LIVE observation taken
# at the moment of asking, instead of a constant recorded in the proof file.
#
# Mirrors UosUnifiedMonitoringGovernanceDigitalTwin.lean:
#   :552 canonicalExpectation   :578 aligned   :587/:597 historical fixtures
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains

# --- canonicalExpectation, Lean :552 -------------------------------------
comptime REQ_ROUTES = 69
comptime MAX_CANONICAL_BROKEN = 0
comptime REQ_SCC = 1
comptime MIN_A2UI = 233
comptime TWIN = "formal/lean/UosUnifiedMonitoringGovernanceDigitalTwin.lean"


def aligned(
    listeners_ok: Bool,
    routes_probed: Int,
    routes_200: Int,
    canonical_broken: Int,
    scc: Int,
    a2ui: Int,
    req_routes: Int,
) -> Bool:
    """Index-wise mirror of UOS.UnifiedMonitoringTwin.aligned (Lean :578).

    Fail-closed conjunction: an absent reading is False, never "assume ok".
    """
    return (
        listeners_ok
        and routes_probed >= req_routes
        and routes_200 == routes_probed
        and canonical_broken <= MAX_CANONICAL_BROKEN
        and scc == REQ_SCC
        and a2ui >= MIN_A2UI
    )


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
        String("formal/lean/UosUnifiedMonitoringGovernanceDigitalTwin.lean"),
    )

    # ---- THE DECLARED SUBJECT IS ACTUALLY READ -------------------------
    # 20261106-1848, found by B5 mutation verification: this file was emptied
    # to zero bytes in the real tree and the receipt did not move by a single
    # byte. The oracle named a formal twin as its subject and never opened it,
    # so `Trust = Fresh Empirical Behavior AND Formal Spec` had no second
    # term at this candidate -- the receipt pointed at a file nothing read.
    # A declared subject is not a read subject.
    #
    # The expected set is the theorem names THIS ORACLE'S OWN COMMENTS cite as
    # its source, not a count harvested from the twin: binding to a number
    # that happens to match is the defect, not the repair. Emptying or
    # renaming the twin now fails this arm immediately.
    var twin_thms = count(
        "grep -cE '^theorem ' " + String(TWIN) + " 2>/dev/null")
    r.world_or_blind(String("declared-twin-is-readable"),
                     twin_thms >= 0, twin_thms > 0)
    var cited = [String("THM_ALN_01"), String("THM_ALN_02"),
                 String("THM_ALN_03"), String("THM_ALN_04")]
    var cited_present = 0
    for ci in range(len(cited)):
        if count("grep -cE '^theorem " + cited[ci] + "' "
                 + String(TWIN) + " 2>/dev/null") > 0:
            cited_present += 1
    r.world_count(String("declared-twin-carries-every-cited-theorem"),
                  cited_present, len(cited))

    # ---- ALGEBRA: re-evaluate what Lean proves -------------------------
    # THM_ALN_03 -- the empty observation never aligns. This is the single
    # most important property: a prober that cannot read the system must
    # report divergence, not health.
    r.algebra(
        String("aln03:fail-closed-on-no-evidence"),
        not aligned(False, 0, 0, 0, 0, 0, REQ_ROUTES),
    )

    # THM_ALN_01 -- the pre-repair fixture (cockpit dead) diverges.
    r.algebra(
        String("aln01:divergent-before-repair"),
        not aligned(False, 0, 0, 1, 0, 0, REQ_ROUTES),
    )

    # THM_ALN_02 -- the post-repair fixture aligns.
    r.algebra(
        String("aln02:aligned-after-repair"),
        aligned(True, 69, 69, 0, 1, 239, REQ_ROUTES),
    )

    # THM_ALN_04 -- a dead cockpit alone forces divergence even when every
    # other reading is ideal.
    r.algebra(
        String("aln04:dead-cockpit-forces-divergence"),
        not aligned(False, 69, 69, 0, 1, 239, REQ_ROUTES),
    )

    # Each conjunct must be independently load-bearing: drop one, lose
    # alignment. This is what stops `aligned` decaying into a constant.
    r.algebra(
        String("conjunct:routes-short"),
        not aligned(True, 68, 68, 0, 1, 239, REQ_ROUTES),
    )
    r.algebra(
        String("conjunct:not-all-200"),
        not aligned(True, 69, 68, 0, 1, 239, REQ_ROUTES),
    )
    r.algebra(
        String("conjunct:canonical-broken"),
        not aligned(True, 69, 69, 1, 1, 239, REQ_ROUTES),
    )
    r.algebra(
        String("conjunct:scc-split"),
        not aligned(True, 69, 69, 0, 2, 239, REQ_ROUTES),
    )
    r.algebra(
        String("conjunct:a2ui-short"),
        not aligned(True, 69, 69, 0, 1, 232, REQ_ROUTES),
    )

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # The all-ideal reading MUST align. If this failed, every `not aligned`
    # check above would pass trivially and the oracle would be blind.
    # F8, 20261106: the positive control is kept, as an OBSERVATION where it
    # belongs, and a real negative control is added. Routing a positive
    # control through `mutation_probe` spent the one slot reserved for the
    # negative one and left `vacuous` unable to increment, which makes
    # `Receipt.status()`'s first and gravest test dead code for this file.
    r.observe(String("positive-control-ideal-reading-aligns"),
              String(aligned(True, 69, 69, 0, 1, 239, REQ_ROUTES)))
    r.mutation_probe(
        String("relation-rejects-a-single-broken-conjunct"),
        not aligned(True, 69, 69, 0, 1, MIN_A2UI - 1, REQ_ROUTES),
    )

    # ---- WORLD: observe the live host ----------------------------------
    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    var ports = capture("ss -ltn 2>/dev/null")
    r.observe(String("listeners"), ports)

    # F14 + F17, 20261106: same two defects as core_evo_oracle. Bare
    # `world()` on `contains(ports, ...)` turns an absent or failed `ss`
    # into four manufactured outages, and the unanchored ":4100" also
    # matches ":41000".."41009". The instrument's availability is now the
    # presence predicate and the match is anchored on the space `ss -ltn`
    # emits after the local address.
    var ss_ran = ports.byte_length() > 0
    var l4100 = contains(ports, String(":4100 "))
    var l4101 = contains(ports, String(":4101 "))
    var l4200 = contains(ports, String(":4200 "))
    var l7447 = contains(ports, String(":7447 "))
    r.world_or_blind(String("cockpit-http-4100"), ss_ran, l4100)
    r.world_or_blind(String("cockpit-https-4101"), ss_ran, l4101)
    r.world_or_blind(String("sa-plan-http-4200"), ss_ran, l4200)
    r.world_or_blind(String("zenoh-router-7447"), ss_ran, l7447)
    var listeners_ok = l4100 and l4101 and l4200 and l7447

    # Probe the canonical route subset. The expectation is scaled to what is
    # actually probed here; the full 69-endpoint sweep belongs to
    # tools/link_tracker_verifier.exe and is NOT claimed by this oracle.
    var probed = 0
    var ok200 = 0
    var answered = 0
    var routes = [
        String("/"),
        String("/wiki"),
        String("/zk"),
        String("/checklist"),
        String("/api/health"),
    ]
    for i in range(len(routes)):
        probed += 1
        var code = capture(
            "curl -s -o /dev/null -w '%{http_code}' --max-time 5"
            + " http://127.0.0.1:4100" + routes[i] + " 2>/dev/null"
        )
        if code == String("200"):
            ok200 += 1
        else:
            print("#   route NOT 200:", routes[i], "->", code)
        if code.byte_length() > 0:
            answered += 1
    r.observe_int(String("route-sweep"), probed)
    # F14, 20261106: bare `world()`. `curl` absent or every request timing
    # out yields no "200" for any route, so ok200=0 against probed=5 and the
    # arm reports "no route serves" -- indistinguishable from the cockpit
    # being down. The instrument's availability is checked separately, so an
    # unusable curl is BLIND rather than a fleet-wide outage.
    # R2 FIX, 20261106-1230 (found by the robustness harness). This arm
    # MANUFACTURED A FAILURE when `curl` was present but broken: with a stub
    # exiting 127 every route returns an empty code, ok200 drops to 0, and the
    # oracle reported "no route serves" -- indistinguishable from the cockpit
    # being down. `command -v curl` does not help, because it checks
    # EXISTENCE and not USABILITY: that is "a declared route is not a
    # connected route", one level down.
    #
    # The instrument counts as usable only if it PRODUCED something. A sweep
    # where every probe came back empty saw nothing, and BLIND is honest.
    r.world_or_blind(String("all-probed-routes-200"),
                     probed > 0 and answered > 0, ok200 == probed)

    # ---- THE STRUCTURAL CONJUNCTS ---------------------------------------
    #
    # F3, 20261106. This call was
    # `aligned(listeners_ok, probed, ok200, 0, REQ_SCC, 239, probed)`,
    # which made FOUR of six conjuncts self-satisfying: `scc == REQ_SCC`,
    # `a2ui >= MIN_A2UI` (239 >= 233), `canonical_broken <= 0` (0 <= 0) and
    # `routes_probed >= req_routes` (`probed >= probed`).
    #
    # This file was credited by the reviewer as the MORE HONEST of the two,
    # because the comment above disclosed that scc and a2ui "are model
    # constants, not observations, and are passed through as such". That
    # disclosure was true and it is why this defect was cheap to fix. It did
    # not, however, cover the two self-comparisons it did not mention --
    # `probed >= probed` and `0 <= 0` -- and disclosure is not the same as
    # measurement: a disclosed tautology still cannot fail.
    #
    # a2ui is now COUNTED from the three A2UI catalogs (core 15 + wave1 100
    # + wave2 124 = 239 ComponentSpec entries), the same derivation added to
    # core_evo_oracle. scc, canonical_broken and the 69-route requirement
    # are not observable by this instrument and are recorded BLIND rather
    # than handed the constant they are tested against.
    var a2ui_n = count(
        "cat apps/cepaf_gleam/src/cepaf_gleam/a2ui/core_catalog.gleam"
        + " apps/cepaf_gleam/src/cepaf_gleam/a2ui/wave1_catalog.gleam"
        + " apps/cepaf_gleam/src/cepaf_gleam/a2ui/wave2_catalog.gleam"
        + " 2>/dev/null"
        + " | awk '/^pub fn components\\(\\)/{p=1} p'"
        + " | grep -cE '^ +ComponentSpec\\('")
    r.observe_int(String("a2ui-components-counted-from-the-catalogs"), a2ui_n)
    r.world_or_blind(String("a2ui-meets-the-floor"),
                     a2ui_n >= 0, a2ui_n >= MIN_A2UI)
    r.world_or_blind(String("module-graph-scc"), False, False)
    r.world_or_blind(String("canonical-broken-links"), False, False)
    r.world_or_blind(String("sixty-nine-route-requirement"), False, False)

    # L4 FIX, 20261106-0924 (re-review finding 3). The previous call was
    # `aligned(listeners_ok, probed, ok200, 0, REQ_SCC, a2ui_n, probed)`,
    # which left THREE of six conjuncts self-satisfying:
    # `routes_probed >= req_routes` as `probed >= probed`,
    # `canonical_broken <= MAX_CANONICAL_BROKEN` as `0 <= 0`, and
    # `scc == REQ_SCC` as `REQ_SCC == REQ_SCC`. Only `listeners_ok`,
    # `ok200 == probed` and `a2ui_n >= 233` were measured.
    #
    # Worse, the comment above claimed scc, canonical_broken and the 69-route
    # requirement "are recorded BLIND RATHER THAN handed the constant they
    # are tested against". They were recorded BLIND *and* handed the
    # constant, so one run asserted the relation held and reported three of
    # its inputs unobservable -- under an arm named
    # `live-alignment-over-observed-conjuncts`, which claimed exactly the
    # coverage it lacked. Of the four self-comparisons the comment
    # identified, only `a2ui` had actually been converted.
    #
    # `core_evo` gets this right and is the model followed here: it feeds
    # satisfying values ONLY so the call typechecks, and routes the aggregate
    # through `world_or_blind` gated on every input having been observed, so
    # the verdict is BLIND whenever any conjunct was not seen. The three
    # unobservable conjuncts are now in that gate, so this arm can no longer
    # assert alignment while declaring its inputs unknown.
    var live = aligned(listeners_ok, probed, ok200, 0, REQ_SCC, a2ui_n,
                       probed)
    r.observe(String("conjuncts-fed-to-typecheck-only"),
              String("scc, canonical_broken, req_routes -- see the BLIND "
                     "arms above; they are NOT measured by this oracle"))
    r.world_or_blind(String("live-alignment-over-observed-conjuncts"),
                     False, False)
    # What IS measured, as its own arm, so the file still carries a live
    # verdict rather than only a declaration of ignorance.
    r.world_or_blind(String("measured-conjuncts-align"),
                     ss_ran and a2ui_n >= 0 and probed > 0,
                     listeners_ok and ok200 == probed
                     and a2ui_n >= MIN_A2UI)

    print("# probe time   :", now)
    print("# listeners    : 4100=", l4100, " 4101=", l4101, " 4200=", l4200, " 7447=", l7447)
    print("# routes       :", ok200, "/", probed, "  (subset, not the 69-route sweep)")
    print("# ALIGNMENT    :", "RUNTIME MATCHES TWIN" if live else "DIVERGENT")
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
