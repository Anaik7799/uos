# ==========================================================================
# Differential oracle for formal/lean/UosProvenanceCeilingAndImpactTwin.lean
#
# Re-evaluates the L1..L7 gap-free ceiling derivation (`deriveVerifiedCeiling`),
# the Rete-UL forward-chaining verdict (`evaluateReteVerdict`), and the 5-phase
# tri-key ceiling transition state machine (`transitionAllowedCeiling`), then
# probes the live UOS repository across all 24 fractal L0..L9 EV-sensitive
# artifacts, `var/km/provenance-cycles.sqlite3`, and `tools/km-gate`.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains


def derive_verified_ceiling(base_ceiling: Int, eligible_mask_94_to_109: Int) -> Int:
    """Mojo twin of `UOS.ProvenanceCeilingAndImpactTwin.deriveVerifiedCeiling`.
    `eligible_mask_94_to_109` has bit (ev - 94) set iff EV is locally eligible (L1..L3).
    Advances contiguously from `base_ceiling` (93) up to 109 (L4..L5)."""
    var curr = base_ceiling
    for offset in range(16):
        var next_ev = 94 + offset
        if curr + 1 == next_ev and ((eligible_mask_94_to_109 >> offset) & 1) == 1:
            curr = next_ev
        else:
            break
    return curr


def evaluate_rete_verdict(
    chain_intact: Bool,
    policy_ceiling: Int,
    machine_ceiling: Int,
    quarantined_count: Int,
    moc_completeness_bps: Int,
    wiki_completeness_bps: Int,
    moc_marking_bps: Int,
    wiki_marking_bps: Int,
    entropy_bits_x1000: Int,
    entropy_floor_x1000: Int,
) -> Int:
    """Mojo twin of `evaluateReteVerdict` (0 = ANDON, 1 = HOLD, 2 = PASS)."""
    if not chain_intact:
        return 0
    if (
        policy_ceiling > machine_ceiling
        or moc_completeness_bps < 10000
        or wiki_completeness_bps < 10000
        or (quarantined_count > 0 and (moc_marking_bps < 10000 or wiki_marking_bps < 10000))
        or entropy_bits_x1000 < entropy_floor_x1000
    ):
        return 1
    return 2


def count_model_quorum_mask(mask4: Int) -> Int:
    """Count of distinct model families set in a 4-bit ratification mask (`0..15`):
    bit 0 = `codex`, bit 1 = `agy`, bit 2 = `claude`, bit 3 = `pi+openrouter+gemini+argon`."""
    var m = mask4 & 15
    return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1)


def transition_allowed_ceiling(
    chain_intact: Bool,
    all16_two_key_bound: Bool,
    no_gap_94_to_109: Bool,
    codex_signed: Bool,
    agy_signed: Bool,
    claude_signed: Bool,
    pi_openrouter_gemini_argon_signed: Bool,
    operator_signed: Bool,
    all28_twins_aligned: Bool,
) -> Int:
    """Mojo twin of `UOS.ProvenanceCeilingAndImpactTwin.transitionAllowedCeiling`
    under the 2-of-4 model ratification quorum (any 2 of `{codex, agy, claude,
    pi+openrouter+gemini+argon}` plus Operator)."""
    var model_count = (
        (1 if codex_signed else 0)
        + (1 if agy_signed else 0)
        + (1 if claude_signed else 0)
        + (1 if pi_openrouter_gemini_argon_signed else 0)
    )
    if (
        chain_intact
        and all16_two_key_bound
        and no_gap_94_to_109
        and model_count >= 2
        and operator_signed
        and all28_twins_aligned
    ):
        return 109
    return 93


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/UosProvenanceCeilingAndImpactTwin.lean"),
    )

    # ---- 1. ALGEBRA: L1..L7 + Rete R0..R4 + 5-phase ceiling state machine ----
    var c_empty = derive_verified_ceiling(93, 0)
    r.algebra(String("L1-L2:empty-mask-stays-at-93"), c_empty == 93)
    var c_ev94 = derive_verified_ceiling(93, 1)
    r.algebra(String("L3:ev94-only-advances-to-94"), c_ev94 == 94)
    var c_gap94 = derive_verified_ceiling(93, 2)
    r.algebra(String("L4:gap-at-94-blocks-95"), c_gap94 == 93)
    var c_gap96 = derive_verified_ceiling(93, 1 | 2 | 8)
    r.algebra(String("L5:contiguous-94-95-with-gap-96-stops-at-95"), c_gap96 == 95)
    var c_all16 = derive_verified_ceiling(93, 0xFFFF)
    r.algebra(String("L6:all-16-eligible-advances-to-109"), c_all16 == 109)
    var rete_andon = evaluate_rete_verdict(False, 93, 92, 16, 10000, 10000, 10000, 10000, 3298, 2500)
    r.algebra(String("rete:broken-chain-forces-andon"), rete_andon == 0)
    var rete_hold = evaluate_rete_verdict(True, 93, 92, 16, 10000, 10000, 10000, 10000, 3298, 2500)
    r.algebra(String("rete:current-observed-state-is-hold"), rete_hold == 1)
    var rete_pass = evaluate_rete_verdict(True, 109, 109, 0, 10000, 10000, 10000, 10000, 3298, 2500)
    r.algebra(String("rete:converged-state-is-pass"), rete_pass == 2)
    var q_single_model = transition_allowed_ceiling(
        True, True, True, True, False, False, False, True, True
    )
    r.algebra(String("ratification-2of4:single-model-keeps-93"), q_single_model == 93)
    var q_codex_agy = transition_allowed_ceiling(
        True, True, True, True, True, False, False, True, True
    )
    r.algebra(String("ratification-2of4:codex-plus-agy-unlocks-109"), q_codex_agy == 109)
    var q_claude_pi = transition_allowed_ceiling(
        True, True, True, False, False, True, True, True, True
    )
    r.algebra(
        String("ratification-2of4:claude-plus-pi-openrouter-gemini-argon-unlocks-109"),
        q_claude_pi == 109,
    )

    # Exhaustive 16-state 4-bit model ratification quorum check:
    # exactly 6 pairs have popcount==2, 11 masks have popcount>=2, 5 masks have popcount<2
    var quorum_16_ok = 1
    var pairs_count = 0
    var quorum_count = 0
    for mask4 in range(16):
        var c0 = (mask4 & 1) == 1
        var c1 = ((mask4 >> 1) & 1) == 1
        var c2 = ((mask4 >> 2) & 1) == 1
        var c3 = ((mask4 >> 3) & 1) == 1
        var pop = count_model_quorum_mask(mask4)
        var allowed = transition_allowed_ceiling(
            True, True, True, c0, c1, c2, c3, True, True
        )
        if pop == 2:
            pairs_count += 1
        if pop >= 2:
            quorum_count += 1
            if allowed != 109:
                quorum_16_ok = 0
        else:
            if allowed != 93:
                quorum_16_ok = 0
    if pairs_count != 6 or quorum_count != 11:
        quorum_16_ok = 0
    r.algebra(
        String("ratification-2of4:exhaustive-16-model-masks-6-pairs-11-quorum"),
        quorum_16_ok == 1,
    )

    # Exhaustive 65,536-mask property & fuzz verification over all 16-bit EV-94..109 bitmasks
    var exhaustive_65536_ok = 1
    for m in range(65536):
        var c = derive_verified_ceiling(93, m)
        var in_range = c >= 93 and c <= 109
        var top_iff_all = (c == 109) == (m == 65535)
        var bit0_gate = (c == 93) if ((m & 1) == 0) else (c >= 94)
        if not (in_range and top_iff_all and bit0_gate):
            exhaustive_65536_ok = 0
            break
    r.algebra(String("property-fuzz:exhaustive-65536-masks-satisfy-range-top-and-gap-laws"), exhaustive_65536_ok == 1)

    # Monotonicity across all 16 contiguous prefixes (k = 0..15)
    var monotone_ok = 1
    for k in range(16):
        var m1 = (1 << k) - 1
        var m2 = (1 << (k + 1)) - 1
        var c1 = derive_verified_ceiling(93, m1)
        var c2 = derive_verified_ceiling(93, m2)
        if not (c1 == 93 + k and c2 == 93 + k + 1 and c1 < c2):
            monotone_ok = 0
            break
    r.algebra(String("property:strict-monotonicity-across-16-contiguous-prefixes"), monotone_ok == 1)

    var q_missing_op = transition_allowed_ceiling(
        True, True, True, True, True, True, True, False, True
    )
    r.mutation_probe(
        String("relation-rejects-missing-operator-despite-all-four-models"),
        q_missing_op != q_claude_pi,
    )

    # ---- 2. WORLD: Lean twin, forensic ledger, TSV manifest, SQLite chain, EV selftest ----
    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    var thm_raw = capture(
        "grep -c '^theorem THM_PROV_TWIN_' formal/lean/UosProvenanceCeilingAndImpactTwin.lean 2>/dev/null"
    )
    r.observe(String("lean-twin-theorems"), thm_raw)
    var n_thms: Int
    try:
        n_thms = Int(thm_raw)
    except:
        n_thms = -1
    r.world(String("lean-twin-has-44-theorems"), n_thms == 44)

    var ceiling_decl = capture(
        "grep -c 'def admittedEvCeiling : Nat := 93' formal/lean/UosProvenanceCeilingAndImpactTwin.lean 2>/dev/null"
    )
    r.observe(String("lean-twin-ceiling-decl"), ceiling_decl)
    r.world(String("lean-twin-pins-ceiling-93"), ceiling_decl == String("1"))

    var ledger_body = capture(
        "cat governance/provenance/20261031-1658-ev94-109-observed-adjudication-ledger.json 2>/dev/null"
    )
    r.observe(String("forensic-ledger"), ledger_body)
    r.world_or_blind(
        String("forensic-ledger-ceiling-93-and-hold"),
        ledger_body.byte_length() > 0,
        contains(ledger_body, String("\"admitted_ev_ceiling\":93"))
        and contains(ledger_body, String("\"status\":\"HOLD\"")),
    )

    var q_rows_raw = capture(
        "grep -c '^[^#]' governance/20260930-0535-quarantined-ev-claims.tsv 2>/dev/null"
    )
    r.observe(String("quarantined-tsv-rows"), q_rows_raw)
    r.world(String("quarantined-tsv-has-18-not-admitted-rows"), q_rows_raw == String("18"))

    var gate_verify = capture("bash tools/km-gate --gate 2>/dev/null")
    r.observe(String("km-gate-verify"), gate_verify)
    var cycle_rows_raw = capture(
        "sqlite3 var/km/provenance-cycles.sqlite3 'SELECT COUNT(*) FROM cycle;' 2>/dev/null"
    )
    r.observe(String("sqlite-cycle-rows"), cycle_rows_raw)
    r.world_or_blind(
        String("sqlite-332-cycle-chain-intact"),
        gate_verify.byte_length() > 0 and cycle_rows_raw.byte_length() > 0,
        contains(gate_verify, String("CHAIN_INTACT"))
        and contains(gate_verify, String("\"status\": \"PASS\""))
        and contains(gate_verify, String("\"adr_total\": 137"))
        and cycle_rows_raw == String("332"),
    )

    var rete_verify = capture("bash tools/km-gate --rete 2>/dev/null")
    r.observe(String("km-gate-rete"), rete_verify)
    r.world_or_blind(
        String("km-gate-rete-kmp-ceiling-split-hold"),
        rete_verify.byte_length() > 0,
        contains(rete_verify, String("KMP-CEILING-SPLIT"))
        and contains(rete_verify, String("\"verdict\": \"HOLD\"")),
    )

    var ev_selftest = capture("bash tools/km-gate --ev-selftest 2>/dev/null")
    r.observe(String("km-gate-ev-selftest"), ev_selftest)
    r.world_or_blind(
        String("km-gate-ev-selftest-17-of-17-pass"),
        ev_selftest.byte_length() > 0,
        contains(ev_selftest, String("17 checks, 0 failures")),
    )

    var rete_selftest = capture("bash tools/km-gate --rete-selftest 2>/dev/null")
    r.observe(String("km-gate-rete-selftest"), rete_selftest)
    r.world_or_blind(
        String("km-gate-rete-selftest-14-of-14-pass"),
        rete_selftest.byte_length() > 0,
        contains(rete_selftest, String("14 checks, 0 failures")),
    )

    var merge_selftest = capture("bash tools/km-gate --merge-selftest 2>/dev/null")
    r.observe(String("km-gate-merge-selftest"), merge_selftest)
    r.world_or_blind(
        String("km-gate-merge-selftest-16-of-16-pass"),
        merge_selftest.byte_length() > 0,
        contains(merge_selftest, String("16 checks, 0 failures")),
    )

    var metrics_selftest = capture("bash tools/km-gate --metrics-selftest 2>/dev/null")
    r.observe(String("km-gate-metrics-selftest"), metrics_selftest)
    r.world_or_blind(
        String("km-gate-metrics-selftest-10-of-10-pass"),
        metrics_selftest.byte_length() > 0,
        contains(metrics_selftest, String("metrics_selftest: 10 checks, 0 failed")),
    )

    var append_only_selftest = capture(
        "bash tools/km-gate --append-only-selftest 2>/dev/null"
    )
    r.observe(String("km-gate-append-only-selftest"), append_only_selftest)
    r.world_or_blind(
        String("km-gate-append-only-selftest-5-of-5-pass"),
        append_only_selftest.byte_length() > 0,
        contains(append_only_selftest, String("5 checks, 0 failures")),
    )

    # Extract the 28 fractal impact paths directly from the Lean twin and verify each exists on disk
    var impact_total = capture(
        "sed -n 's/.*artifactPath := \"\\([^\"]*\\)\".*/\\1/p' formal/lean/UosProvenanceCeilingAndImpactTwin.lean | wc -l"
    )
    r.observe(String("lean-inventory-declared-count"), impact_total)
    var impact_check = capture(
        "for f in $(sed -n 's/.*artifactPath := \"\\([^\"]*\\)\".*/\\1/p' formal/lean/UosProvenanceCeilingAndImpactTwin.lean); do "
        + "test -f \"$f\" && grep -qE '(93|SC-PROVENANCE-001)' \"$f\" && echo ok; done | wc -l"
    )
    r.observe(String("28-fractal-impact-files-aligned"), impact_check)
    r.world(
        String("all-28-fractal-impact-artifacts-exist-and-align-with-lean-inventory"),
        impact_total == String("28") and impact_check == String("28"),
    )

    print("# probe time                 :", now)
    print("# lean twin theorems         :", n_thms, "(expected 44)")
    print("# quarantined tsv rows       :", q_rows_raw, "(expected 18)")
    print("# fractal impact items synced:", impact_check, "/", impact_total)
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
