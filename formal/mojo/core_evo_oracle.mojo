# ==========================================================================
# Differential oracle for formal/lean/UosCoreEvoUnifiedDigitalTwin.lean
#
# Lean proves `runtimeAligned` (:1024) symbolically: THM_RUN_01..03 against
# fixtures, THM_RUN_04..08 universally quantified. This oracle re-evaluates
# the identical 15-conjunct relation concretely and feeds it a LIVE reading.
#
# WHY IT MATTERS HERE SPECIFICALLY
# --------------------------------
# Until 20261106-0108 that Lean file carried `observationNow` with
# `routes200 := 69` -- a number no prober measured; 5 routes were probed and
# 64 inferred -- and `THM_RUN_01_aligned_now` proved the system healthy from
# it. That theorem would have kept proving the system healthy with the
# cockpit in the ground, which is what `THM_VAC_01` in the same file says:
# staticModelObservesRuntime = false. The fixture is now named `idealReading`
# and makes no claim about any moment. The claim about THIS moment is made
# here, in Mojo, or not at all.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains
from oracle_substrate import json_flag, json_int, json_norm

# --- canonicalExpectation, Lean :988 -------------------------------------
comptime REQ_MODULES = 8
comptime REQ_CASTES = 5
comptime REQ_SERVICES = 8
comptime REQ_FPP_ACTORS = 40
comptime REQ_ZENOH_TOPICS = 12
comptime REQ_SCC = 1
comptime MIN_A2UI = 233
comptime MAX_CANONICAL_BROKEN = 0


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def runtime_aligned(
    cockpit_http: Bool, cockpit_https: Bool, sa_plan: Bool, zenoh: Bool,
    routes_probed: Int, routes_200: Int, req_routes: Int,
    modules: Int, castes: Int, services: Int,
    fpp_actors: Int, fpp_supervisor: Bool,
    zenoh_topics: Int, scc: Int, a2ui: Int, canonical_broken: Int,
) -> Bool:
    """Mirror of UOS.CoreEvoTwin.runtimeAligned (Lean :1024), conjunct for conjunct."""
    return (
        cockpit_http and cockpit_https and sa_plan and zenoh
        and routes_200 == routes_probed
        and routes_probed >= req_routes
        and modules == REQ_MODULES
        and castes == REQ_CASTES
        and services == REQ_SERVICES
        and fpp_actors == REQ_FPP_ACTORS
        and fpp_supervisor
        and zenoh_topics == REQ_ZENOH_TOPICS
        and scc == REQ_SCC
        and a2ui >= MIN_A2UI
        and canonical_broken <= MAX_CANONICAL_BROKEN
    )


def ideal(req_routes: Int) -> Bool:
    """The synthetic ideal reading, as Lean's `idealReading` defines it."""
    return runtime_aligned(
        True, True, True, True, req_routes, req_routes, req_routes,
        REQ_MODULES, REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True,
        REQ_ZENOH_TOPICS, REQ_SCC, 239, 0,
    )


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/UosCoreEvoUnifiedDigitalTwin.lean"),
    )
    comptime RR = 69

    # ---- ALGEBRA ------------------------------------------------------
    # THM_RUN_01 -- the ideal reading aligns.
    r.algebra(String("run01:ideal-aligns"), ideal(RR))

    # THM_RUN_02 -- the recorded outage reading diverges.
    r.algebra(
        String("run02:outage-diverges"),
        not runtime_aligned(False, False, True, True, 0, 0, RR,
                            0, 0, 0, 0, False, 12, 0, 0, 1),
    )

    # THM_RUN_03 -- losing one FPP actor forces divergence: 39/40 is not the
    # modelled plane.
    r.algebra(
        String("run03:single-actor-loss"),
        not runtime_aligned(True, True, True, True, RR, RR, RR,
                            REQ_MODULES, REQ_CASTES, REQ_SERVICES, 39, True,
                            REQ_ZENOH_TOPICS, REQ_SCC, 239, 0),
    )

    # THM_RUN_04..07 -- the quantified fail-closed arms, each instantiated.
    r.algebra(String("run04:dead-cockpit"),
        not runtime_aligned(False, True, True, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))
    r.algebra(String("run05:dead-sa-plan"),
        not runtime_aligned(True, True, False, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))
    r.algebra(String("run06:stopped-supervisor"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, False, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))
    r.algebra(String("run07:partial-routes"),
        not runtime_aligned(True, True, True, True, RR, RR - 1, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))

    # Every remaining conjunct must also be load-bearing.
    r.algebra(String("conjunct:zenoh-down"),
        not runtime_aligned(True, True, True, False, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))
    r.algebra(String("conjunct:module-count"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, 6,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))
    r.algebra(String("conjunct:caste-count"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, REQ_MODULES,
            4, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))
    r.algebra(String("conjunct:service-count"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, 7, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 0))
    r.algebra(String("conjunct:zenoh-topics"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, 11,
            REQ_SCC, 239, 0))
    r.algebra(String("conjunct:scc-split"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            2, 239, 0))
    r.algebra(String("conjunct:a2ui-short"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 232, 0))
    r.algebra(String("conjunct:canonical-broken"),
        not runtime_aligned(True, True, True, True, RR, RR, RR, REQ_MODULES,
            REQ_CASTES, REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS,
            REQ_SCC, 239, 1))

    # ---- CONTROLS, BOTH DIRECTIONS ------------------------------------
    # F8, 20261106: the positive control is kept, as an OBSERVATION where it
    # belongs, and a real negative control is added. Routing a positive
    # control through `mutation_probe` spent the one slot reserved for the
    # negative one and left `vacuous` unable to increment, which makes
    # `Receipt.status()`'s first and gravest test dead code for this file.
    r.observe(String("positive-control-ideal-aligns"), String(ideal(RR)))
    r.mutation_probe(
        String("relation-rejects-a-single-broken-conjunct"),
        not runtime_aligned(
            True, True, True, True, RR, RR, RR, REQ_MODULES, REQ_CASTES,
            REQ_SERVICES, REQ_FPP_ACTORS, True, REQ_ZENOH_TOPICS, REQ_SCC,
            MIN_A2UI - 1, 0))

    # ---- WORLD --------------------------------------------------------
    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    var ports = capture("ss -ltn 2>/dev/null")
    r.observe(String("listeners"), ports)
    # F14, 20261106: these four were bare `world()` calls on
    # `contains(ports, ":4100")`. If `ss` is absent or fails, `ports` is the
    # empty string, every `contains` is False, and the oracle reports FOUR
    # MANUFACTURED OUTAGES on a healthy node -- a failure invented out of an
    # observability gap. `ss` is not a toolchain the preflight pins, so its
    # absence is not hypothetical. The instrument's own availability is now
    # the presence predicate, exactly as this file already does four lines
    # below for the FPP arm.
    #
    # F17, 20261106: the match was the bare substring ":4100", which also
    # matches ":41000".. ":41009". Anchoring on a trailing space is what
    # `ss -ltn` actually emits between the local address and the peer
    # column, so a longer port cannot satisfy a shorter prefix.
    var ss_ran = ports.byte_length() > 0
    var c_http = contains(ports, String(":4100 "))
    var c_https = contains(ports, String(":4101 "))
    var sa = contains(ports, String(":4200 "))
    var zh = contains(ports, String(":7447 "))
    r.world_or_blind(String("cockpit-4100"), ss_ran, c_http)
    r.world_or_blind(String("cockpit-4101"), ss_ran, c_https)
    r.world_or_blind(String("sa-plan-4200"), ss_ran, sa)
    r.world_or_blind(String("zenoh-7447"), ss_ran, zh)

    # Deep health: the FPP supervisor and its 40 live actors. The twin's
    # requiredFppActors = 40 is only meaningful if it is actually read.
    var health = capture(
        "curl -s --max-time 6 http://127.0.0.1:4100/api/health 2>/dev/null"
    )
    var core_status = capture(
        "curl -s --max-time 6 http://127.0.0.1:4100/api/v1/core-evo/status 2>/dev/null"
    )
    var zenoh_json = capture(
        "curl -s --max-time 6 http://127.0.0.1:4100/api/v1/zenoh 2>/dev/null"
    )
    r.observe(String("deep-health"), health)
    var sup_flag = json_flag(core_status, String("fpp_supervisor_running"))
    var actors_n = json_int(core_status, String("fpp_live_actors_alive"))
    var mods_n = json_int(core_status, String("module_count"))
    var svcs_n = json_int(core_status, String("service_count"))
    var ztopics_n = json_int(zenoh_json, String("topics_active"))
    r.world_json(String("fpp-supervisor-running"), sup_flag, True)
    r.world_count(String("fpp-40-actors-alive"), actors_n, REQ_FPP_ACTORS)
    var sup_present = sup_flag >= 0
    var actors_present = actors_n >= 0
    var sup = sup_flag == 1
    var actors40 = actors_n == REQ_FPP_ACTORS

    # The cockpit self-report is its own observation, separate from whether
    # it answers routes.
    var health_n = json_norm(health)
    var self_ok = contains(health_n, String("\"status\":\"ok\""))
    r.world_or_blind(String("cockpit-self-report-ok"),
        contains(health_n, String("\"status\":")), self_ok)

    # Route subset. The expectation is scaled to what is PROBED. The full
    # 69-route sweep is tools/link_tracker_verifier.exe's job and is not
    # claimed here -- inferring the other 64 is the exact bug this replaces.
    var probed = 0
    var ok200 = 0
    var answered = 0
    var routes = [
        String("/"), String("/wiki"), String("/zk"), String("/checklist"),
        String("/api/health"), String("/planning"), String("/core-evo"),
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
    r.observe_int(String("routes-that-answered-at-all"), answered)

    # ---- THE STRUCTURAL CONJUNCTS ---------------------------------------
    #
    # F3, 20261106. The live call used to be
    #
    #   runtime_aligned(c_http, c_https, sa, zh, probed, ok200, probed,
    #                   REQ_MODULES, REQ_CASTES, REQ_SERVICES,
    #                   40 if actors40 else 0, sup,
    #                   REQ_ZENOH_TOPICS, REQ_SCC, 239, 0)
    #
    # and `runtime_aligned` then evaluated `modules == REQ_MODULES`,
    # `castes == REQ_CASTES`, `services == REQ_SERVICES`,
    # `zenoh_topics == REQ_ZENOH_TOPICS`, `scc == REQ_SCC`,
    # `a2ui >= MIN_A2UI`, `canonical_broken <= MAX_CANONICAL_BROKEN` and
    # `routes_probed >= req_routes` -- with `req_routes` bound to `probed`.
    # EIGHT of fifteen conjuncts were handed the very constant they are
    # compared against, so eight were tautologies at runtime. The header
    # claimed the oracle "feeds it a LIVE reading". It fed seven.
    #
    # Two of the eight turned out to be genuinely derivable, and the derived
    # value is used instead of the constant:
    #
    #   castes -- `HiveCaste` in ecology/core_hive.gleam; counted and bound
    #             to the wip-limit sum, not merely to the cardinality.
    #   a2ui   -- the three A2UI catalogs (core 15 + wave1 100 + wave2 124)
    #             declare 239 ComponentSpec entries. The oracle previously
    #             passed the literal 239 while the count was available all
    #             along.
    #
    # The remaining six -- modules, services, zenoh_topics, scc,
    # canonical_broken, and the 69-route requirement -- I could NOT ground
    # in this tree without guessing. There are, for instance, eight
    # `core_*.gleam` files against a requiredServices of 8 and a
    # requiredModules of 7, and picking whichever count matches the expected
    # number is precisely the defect under repair: an oracle that invents
    # its own inputs cannot disagree with the model. So they are NOT passed
    # the constant and NOT passed a guess. Each is recorded BLIND -- not
    # observable by this instrument at this candidate -- which the lattice
    # ranks above PASS, and the aggregate relation is evaluated only over
    # what was actually seen and named accordingly.
    #
    # The effect is that this oracle now reports BLIND where it used to
    # report alignment. That is the honest verdict: it never measured those
    # six properties.
    # ---- L7 FIX, 20261106-0924: THE WRONG CARRIER --------------------
    #
    # This derived `castes` from `pub type TaskRole` -- ImplRole, RcaTpsRole,
    # SovereignGateRole, FmeaFormalRole, ConductorRole -- which shares ONLY
    # ITS CARDINALITY with what the subject means. The subject's `casteCount`
    # is the five-caste HOLARCHY: `UosCoreEvoUnifiedDigitalTwin.lean:184-190
    # holarchyCastes` declares QueenConductor, ForagerBuilder,
    # NurseDiagnostician, ArchitectSynthesizer, SovereignSentinel with wip
    # limits 1,4,2,2,2.
    #
    # `ecology/core_hive.gleam:29-34` declares `pub type HiveCaste` with
    # EXACTLY those five names, and `caste_wip_limit` gives exactly those five
    # limits, summing to 11 -- matching `THM_ONT_05`'s `totalHiveWip = 11`.
    # The available derivation corresponds member-for-member AND in its wip
    # limits; the one I chose shared a number.
    #
    # I picked a carrier because its count matched the expected value, in the
    # same change where I wrote that "picking whichever count matches the
    # expected number is the defect under repair" and declined the
    # `requiredServices` derivation on exactly that ground. The decline was
    # right; this pick was the thing the decline was guarding against.
    #
    # Binding on the wip SUM as well as the cardinality is what stops the
    # same mistake recurring: any five-member Gleam type would satisfy a
    # count of 5, but only the real caste type also sums to 11.
    comptime HIVE = "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_hive.gleam"
    var castes_n = count(
        "awk '/pub type HiveCaste/{p=1;next} p&&/^}/{exit} p{print}' "
        + String(HIVE) + " 2>/dev/null | grep -cE '^ +[A-Z]'")
    var caste_wip_sum = count(
        "awk '/pub fn caste_wip_limit/{p=1} p&&/^}/{exit} p{print}' "
        + String(HIVE) + " 2>/dev/null"
        + " | grep -oE '\\-> [0-9]+' | grep -oE '[0-9]+'"
        + " | awk '{s+=$1} END{print s+0}'")
    var lean_wip_total = count(
        "grep -oE 'totalHiveWip = [0-9]+' "
        + "formal/lean/UosCoreEvoUnifiedDigitalTwin.lean 2>/dev/null"
        + " | head -1 | grep -oE '[0-9]+$'")
    r.observe_int(String("hive-caste-wip-sum"), caste_wip_sum)
    r.observe_int(String("lean-total-hive-wip"), lean_wip_total)
    r.world_or_blind(String("caste-wip-sum-matches-the-twin"),
                     caste_wip_sum >= 0 and lean_wip_total >= 0,
                     caste_wip_sum == lean_wip_total)
    var a2ui_n = count(
        "cat apps/cepaf_gleam/src/cepaf_gleam/a2ui/core_catalog.gleam"
        + " apps/cepaf_gleam/src/cepaf_gleam/a2ui/wave1_catalog.gleam"
        + " apps/cepaf_gleam/src/cepaf_gleam/a2ui/wave2_catalog.gleam"
        + " 2>/dev/null"
        + " | awk '/^pub fn components\\(\\)/{p=1} p'"
        + " | grep -cE '^ +ComponentSpec\\('")
    r.observe_int(String("castes-counted-from-HiveCaste"), castes_n)
    r.observe_int(String("a2ui-components-counted-from-the-catalogs"), a2ui_n)
    r.world_count(String("castes-match-the-twin"), castes_n, REQ_CASTES)
    r.world_or_blind(String("a2ui-meets-the-floor"),
                     a2ui_n >= 0, a2ui_n >= MIN_A2UI)

    # Measured from /api/v1/core-evo/status, /api/v1/zenoh, and link_tracker_verifier.exe --json.
    #
    # SHARED CACHE, NOT A PER-ORACLE TEMP FILE. The verifier costs ~7.8 s and
    # monitoring_governance_oracle.mojo asked it the identical question, so the
    # pair paid ~15.6 s for one answer and then each deleted it.
    # /tmp/uos-ltv-cache.json is written at most once, guarded by `test ! -s`,
    # and is deliberately NOT removed: whichever oracle runs second -- and
    # every subsequent clean run -- reads it in ~0.01 s.
    #
    # GREP IS THE GATE, ON THE WRITE AND ON EVERY READ. Under the adverse PATH
    # in robustness_harness.mojo the world tools are shadowed or absent, and
    # with no `grep` this JSON cannot be parsed AT ALL -- so paying 7.8 s for
    # the verifier would buy nothing. `command -v grep` fails closed FIRST:
    # the exe is never invoked, each read returns empty, `count()` yields -1,
    # and the arms go BLIND in ~0.01 s. BLIND is the honest verdict there --
    # the probe could not obtain its evidence -- and it is now reached at the
    # cost of a `command -v` instead of a full structural walk.
    var ltv_gate = String("command -v grep >/dev/null 2>&1")
    var ltv_cache = String("/tmp/uos-ltv-cache.json")
    _ = capture(
        ltv_gate
        + " && (test ! -s " + ltv_cache
        + " || test -z \"$(find " + ltv_cache + " -mmin -5 2>/dev/null)\")"
        + " && ./tools/link_tracker_verifier.exe --json > " + ltv_cache + ".$$"
        + " 2>/dev/null && mv -f " + ltv_cache + ".$$ " + ltv_cache
    )
    var ltv_status = capture(
        ltv_gate + " && grep -oE '\"status\": *\"[a-z_]+\"' " + ltv_cache
        + " 2>/dev/null | head -1"
    )
    var ltv_total = count(
        ltv_gate + " && grep -oE '\"total_endpoints\": *[0-9]+' " + ltv_cache
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'"
    )
    var ltv_passed = count(
        ltv_gate + " && grep -oE '\"passed\": *[0-9]+' " + ltv_cache
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'"
    )
    var ltv_scc = count(
        ltv_gate + " && grep -oE '\"scc_count\": *[0-9]+' " + ltv_cache
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'"
    )
    var ltv_broken = count(
        ltv_gate + " && grep -oE '\"canonical_broken_transclusions\": *[0-9]+' "
        + ltv_cache + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'"
    )
    var ltv_ran = (
        ltv_status.byte_length() > 0
        and ltv_total >= 0
        and ltv_passed >= 0
        and ltv_scc >= 0
        and ltv_broken >= 0
    )

    r.world_count(String("modules-count"), mods_n, REQ_MODULES)
    r.world_count(String("services-count"), svcs_n, REQ_SERVICES)
    r.world_count(String("zenoh-topic-count"), ztopics_n, REQ_ZENOH_TOPICS)
    r.world_or_blind(String("module-graph-scc"), ltv_ran, ltv_scc == REQ_SCC)
    r.world_or_blind(String("canonical-broken-links"), ltv_ran, ltv_broken <= MAX_CANONICAL_BROKEN)
    r.world_or_blind(String("sixty-nine-route-requirement"), ltv_ran, ltv_total >= RR and ltv_passed == ltv_total)
    r.world_or_blind(String("every-probed-route-answers-200"),
                     probed > 0 and answered > 0, ok200 == probed)

    var live = runtime_aligned(
        c_http, c_https, sa, zh, ltv_total, ltv_passed, RR,
        mods_n, castes_n, svcs_n,
        actors_n if actors_present else -1, sup,
        ztopics_n, ltv_scc, a2ui_n, ltv_broken,
    )
    r.world_or_blind(String("live-alignment-over-observed-conjuncts"),
        sup_present and actors_present and ss_ran and answered > 0
        and mods_n >= 0 and svcs_n >= 0 and ztopics_n >= 0 and ltv_ran
        and castes_n >= 0 and a2ui_n >= 0, live)

    print("# probe time :", now)
    print("# listeners  : 4100=", c_http, " 4101=", c_https, " 4200=", sa, " 7447=", zh)
    print("# fpp        : supervisor=", sup, " actors40=", actors40)
    print("# routes     :", ok200, "/", probed, " (PROBED subset; 69-route sweep NOT claimed)")
    print("# ALIGNMENT  :", "RUNTIME MATCHES TWIN" if live else "DIVERGENT")
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
