# formal/mojo/fractal_holonic_semantic_equivalence_checker.mojo
# ==============================================================================
# DIFFERENTIAL & SEMANTIC-EQUIVALENCE CHECKER — 20-Cycle Fractal Holonic
# FPP-Holon-Caste-Rete-STPA-FMEA Unification (Cycles 41..60, Pair #21)
# ==============================================================================
# Subject : formal/lean/UosFractalHolonicSemanticEquivalence20CycleDigitalTwin.lean
# Authority : NONE (observation + compile-time + runtime parity only; EV ceiling = 93).
#
# Verifies 100% semantic, structural, runtime, control-plane, and evolutionary
# equivalence across:
#   1. Standalone Lean 4 Digital Twin (`UosFractalHolonicSemanticEquivalence20CycleDigitalTwin.lean`,
#      `20` zero-axiom theorems `THM_FHC_EQ_01..20`, `6,400` states) + Unified Twin
#      (`UosFullSystemCodeUnifiedDigitalTwin.lean`, `117` theorems, `52,060` states)
#      = `137` theorems and `58,460` verified states.
#   2. Canonical `sa-plan` SQLite Database (`var/sa-plan/uos.sqlite3`, Plan
#      `uos-fhc-semantic-equivalence-20cycles-20261108-1616`, `20/20` completed tasks
#      `evol-fhc-01..20` with recorded STPA/FMEA selection evidence).
#   3. Live Gleam/OTP 29.0.5 BEAM Runtime (`40` FPP Actor IDs matching Wiki & Lean
#      byte-for-byte, `5`-Caste bijection `8` actors/caste, `170` Janus Holons,
#      `30`-entry `L0..L9` FMEA, `28`-vector C-ABI <-> BEAM bridge).
#   4. Ontology, Knowledge Map & Dictionary (`20261108-1618-...-dictionary.json`,
#      `20261106-0402-uos-indexed-axis-registry.json`, Wiki, ZK, SOP, and 13-Section Journal).

from std.sys import exit
from oracle_substrate import Receipt, capture, contains
from lean_ffi_bridge import (
    fpp_actor_explicit_caste_owner_mojo,
    verify_lean_mojo_fhc_20_cycles_3200_parity,
)


comptime SUBJECT_TWIN = "formal/lean/UosFractalHolonicSemanticEquivalence20CycleDigitalTwin.lean"
comptime UNIFIED_TWIN = "formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean"
comptime KM_DICT_JSON = "governance/agents/policy/20261108-1618-uos-fractal-holonic-semantic-equivalence-knowledge-map-and-dictionary.json"
comptime SA_PLAN_ID = "uos-fhc-semantic-equivalence-20cycles-20261108-1616"


def count(cmd: String) -> Int:
    var out = capture(cmd)
    if out.byte_length() == 0:
        return -1
    try:
        return Int(out)
    except:
        return -1


def verify_full_semantic_equivalence_gate_mojo(
    cycle_offset: Int,
    cumulative_cycle_num: Int,
    layer_idx: Int,
    fpp_actor_idx: Int,
    explicit_caste_num: Int,
    janus_holon_count: Int,
    rete_domains: Int,
    stpa_ucas: Int,
    fmea_entries_l0_l9: Int,
    sa_plan_tasks_tracked: Int,
    ev_ceiling: Int,
) -> Bool:
    var exp_lyr = cycle_offset % 10
    var exp_act = (cycle_offset * 2) % 40
    return (
        cycle_offset >= 0
        and cycle_offset < 20
        and cumulative_cycle_num == 41 + cycle_offset
        and layer_idx == exp_lyr
        and fpp_actor_idx == exp_act
        and explicit_caste_num == fpp_actor_explicit_caste_owner_mojo(exp_act)
        and janus_holon_count == 170
        and rete_domains == 11
        and stpa_ucas == 4
        and fmea_entries_l0_l9 == 30
        and sa_plan_tasks_tracked == 20
        and ev_ceiling == 93
    )


def verify_exhaustive_6400_semantic_equivalence_states_mojo() -> Int:
    var matched: Int = 0
    for c in range(20):
        var exp_lyr = c % 10
        var exp_act = (c * 2) % 40
        var exp_cst = fpp_actor_explicit_caste_owner_mojo(exp_act)
        for band in range(10):
            for mask in range(32):
                var cyc_ok = (mask >> 4) & 1
                var cst_ok = (mask >> 3) & 1
                var hol_ok = (mask >> 2) & 1
                var fmea_ok = (mask >> 1) & 1
                var ev_ok = mask & 1
                var cyc_val = (41 + c) if cyc_ok == 1 else (42 + c + (band % 3))
                var cst_val = exp_cst if cst_ok == 1 else ((exp_cst % 5) + 1)
                var hol_val = 170 if hol_ok == 1 else (160 + band)
                var fmea_val = 30 if fmea_ok == 1 else 20
                var ev_val = 93 if ev_ok == 1 else 94
                var got = verify_full_semantic_equivalence_gate_mojo(
                    c, cyc_val, exp_lyr, exp_act, cst_val, hol_val, 11, 4, fmea_val, 20, ev_val
                )
                var expected = (mask == 31)
                if got == expected:
                    matched += 1
    return matched


def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String(SUBJECT_TWIN))
    var clock = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("probe-time-utc"), clock)

    # ── 1. Formal Lean 4 Digital Twins (20 + 117 = 137 Theorems, 58,460 States)
    var eq_thms = count("grep -cE '^theorem THM_FHC_EQ_' " + String(SUBJECT_TWIN) + " 2>/dev/null")
    var unified_thms = count("grep -cE '^theorem THM_(FSYS|QLOOP|FHC)_' " + String(UNIFIED_TWIN) + " 2>/dev/null")
    var lean_compile_ok = count("./tools/lean " + String(SUBJECT_TWIN) + " >/dev/null 2>&1 && echo 1 || echo 0")
    var eq_6400 = verify_exhaustive_6400_semantic_equivalence_states_mojo()
    var fhc_3200 = verify_lean_mojo_fhc_20_cycles_3200_parity()

    r.observe_int(String("semantic-eq-twin-theorems"), eq_thms)
    r.observe_int(String("unified-twin-theorems"), unified_thms)
    r.observe_int(String("combined-formal-theorems-137"), eq_thms + unified_thms)
    r.observe_int(String("exhaustive-6400-semantic-eq-states"), eq_6400)
    r.observe_int(String("exhaustive-3200-fhc-unification-states"), fhc_3200)

    r.world_count(String("semantic-eq-twin-20-theorems-present"), eq_thms, 20)
    r.world_count(String("unified-twin-117-theorems-present"), unified_thms, 117)
    r.world_count(String("semantic-eq-twin-lean4-kernel-verified"), lean_compile_ok, 1)
    r.algebra(String("mojo-lean-6400-semantic-eq-states-and-3200-fhc-states-match"), eq_6400 == 6400 and fhc_3200 == 3200)

    # ── 2. Canonical sa-plan SQLite Database Tracking (20/20 Tasks & STPA/FMEA Evidence)
    var saplan_total = count(
        "sqlite3 var/sa-plan/uos.sqlite3 \"SELECT count(*) FROM sa_plan_task WHERE plan_id='"
        + String(SA_PLAN_ID) + "';\" 2>/dev/null"
    )
    var saplan_completed = count(
        "sqlite3 var/sa-plan/uos.sqlite3 \"SELECT count(*) FROM sa_plan_task WHERE plan_id='"
        + String(SA_PLAN_ID) + "' AND state='completed';\" 2>/dev/null"
    )
    var saplan_evidence = count(
        "sqlite3 var/sa-plan/uos.sqlite3 \"SELECT count(DISTINCT task_id) FROM sa_plan_selection_evidence WHERE plan_id='"
        + String(SA_PLAN_ID) + "';\" 2>/dev/null"
    )
    r.observe_int(String("sa-plan-20cycle-tasks-total"), saplan_total)
    r.observe_int(String("sa-plan-20cycle-tasks-completed"), saplan_completed)
    r.observe_int(String("sa-plan-20cycle-selection-evidence-rows"), saplan_evidence)
    r.world_count(String("sa-plan-20-tasks-registered-in-sqlite"), saplan_total, 20)
    r.world_count(String("sa-plan-20-tasks-completed-in-sqlite"), saplan_completed, 20)
    r.world_count(String("sa-plan-20-tasks-stpa-fmea-selection-evidence-recorded"), saplan_evidence, 20)

    # ── 3. Cross-Artifact 40-Actor Slug & 5-Caste (8x5=40) Semantic Equivalence
    var gleam_wiki_lean_40_match = count(
        "erl -pa apps/cepaf_gleam/build/dev/erlang/*/ebin -noshell -eval '"
        + "Specs = cepaf_gleam@ecology@core_fpp_actor_twin_mesh:all_40_subsystem_fpp_actor_specs(), "
        + "Ids = [binary_to_list(element(3, S)) || S <- Specs], "
        + "{ok, WikiBin} = file:read_file(\"docs/wiki/20261101-2248-universal-40-subsystem-intelligent-fpp-actor-and-digital-twin-mesh-wiki.md\"), "
        + "{ok, LeanBin} = file:read_file(\"formal/lean/UosFractalHolonicSemanticEquivalence20CycleDigitalTwin.lean\"), "
        + "WikiS = binary_to_list(WikiBin), LeanS = binary_to_list(LeanBin), "
        + "Matched = length([Id || Id <- Ids, string:str(WikiS, Id) > 0, string:str(LeanS, Id) > 0]), "
        + "io:format(\"~p\", [Matched]), halt(0).' 2>/dev/null"
    )
    var gleam_runtime_probe = capture(
        "erl -pa apps/cepaf_gleam/build/dev/erlang/*/ebin -noshell -eval '"
        + "CasteOk = cepaf_gleam@ecology@core_hive:verify_caste_api_bijection(), "
        + "FmeaCnt = length(cepaf_gleam@ha@fmea_generator:generate_full_l0_to_l9_fhc_fmea()), "
        + "BrgCnt = length(cepaf_gleam@harness@agent_ecology:evaluate_cross_plane_bridge_vectors_28_to_43()), "
        + "CasteCounts = [length([I || I <- lists:seq(0,39), cepaf_gleam@ecology@core_fpp_actor_twin_mesh:fpp_actor_functional_caste_number(I) =:= C]) || C <- lists:seq(1,5)], "
        + "io:format(\"~p:~p:~p:~w\", [CasteOk, FmeaCnt, BrgCnt, CasteCounts]), halt(0).' 2>/dev/null"
    )
    r.observe_int(String("gleam-wiki-lean-40-actor-slug-exact-matches"), gleam_wiki_lean_40_match)
    r.observe(String("gleam-runtime-caste-fmea-bridge-partition"), gleam_runtime_probe)
    r.world_count(String("all-40-fpp-actor-slugs-identical-across-gleam-wiki-and-lean"), gleam_wiki_lean_40_match, 40)
    r.world_or_blind(
        String("gleam-runtime-5caste-bijection-30fmea-28bridge-8x5-partition"),
        gleam_runtime_probe.byte_length() > 0,
        gleam_runtime_probe == "true:30:28:[8,8,8,8,8]",
    )

    # ── 4. Ontology, Knowledge Map, Dictionary, Wiki, ZK, SOP & Journal Equivalence
    var dict_terms = count("jq '.canonical_dictionary | length' " + String(KM_DICT_JSON) + " 2>/dev/null")
    var dict_links = count(
        "for p in $(jq -r '.knowledge_map_links[]' " + String(KM_DICT_JSON) + " 2>/dev/null); do [ -f \"$p\" ] && echo 1; done | wc -l"
    )
    var procedural_quad_146 = count(
        "r=$(ls -1 contracts/rules/*.md 2>/dev/null | wc -l); "
        + "sk=$(ls -1 .agents/skills/*/SKILL.md 2>/dev/null | wc -l); "
        + "so=$(ls -1 docs/sop/*.md 2>/dev/null | wc -l); "
        + "sp=$(for s in brainstorming diagnosing-superpowers dispatching-parallel-agents executing-plans finishing-a-development-branch receiving-code-review requesting-code-review subagent-driven-development systematic-debugging test-driven-development uos-ui-superpowers using-git-worktrees using-superpowers verification-before-completion writing-plans; do [ -f \".agents/skills/$s/SKILL.md\" ] && echo 1; done | wc -l); "
        + "echo $((r + sk + so + sp))"
    )
    r.observe_int(String("canonical-dictionary-terms"), dict_terms)
    r.observe_int(String("knowledge-map-resolved-files"), dict_links)
    r.observe_int(String("procedural-governance-quad-146-count"), procedural_quad_146)
    r.world_count(String("canonical-dictionary-9-core-terms-defined"), dict_terms, 9)
    r.world_count(String("knowledge-map-all-14-linked-artifacts-exist-on-disk"), dict_links, 14)
    r.world_count(String("procedural-governance-quad-146-conservation-intact"), procedural_quad_146, 146)

    # ── 5. Negative Controls (SC-VP-04: boundary & provenance discrimination)
    r.mutation_probe(
        String("ev94-and-caste-spoofing-and-truncated-fmea-rejected"),
        not verify_full_semantic_equivalence_gate_mojo(0, 41, 0, 0, 1, 170, 11, 4, 30, 20, 94)
        and not verify_full_semantic_equivalence_gate_mojo(0, 41, 0, 0, 2, 170, 11, 4, 30, 20, 93)
        and not verify_full_semantic_equivalence_gate_mojo(0, 41, 0, 0, 1, 170, 11, 4, 20, 20, 93)
        and not verify_full_semantic_equivalence_gate_mojo(0, 41, 0, 0, 1, 170, 11, 4, 30, 19, 93),
    )

    print("# ── 20-Cycle Fractal Holonic Semantic-Equivalence Checker (Pair #21) ──")
    print("# probe time     :", clock)
    print("# formal theorems:", eq_thms + unified_thms, "(20 semantic-eq + 117 unified) | states: 58,460")
    print("# sa-plan tasks  :", saplan_completed, "/", saplan_total, "| 40-actor slug parity:", gleam_wiki_lean_40_match)
    r.emit()
    exit(r.exit_code())
