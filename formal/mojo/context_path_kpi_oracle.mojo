# ==========================================================================
# Differential oracle for formal/lean/UosContextPathKpiOtelTwin.lean
#
# Lean proves `spanWithinBudget` (:140) over the 10 L0..L9 span records. This
# oracle re-evaluates the identical 8-conjunct predicate concretely and READS
# BACK the OTEL artifacts that another process rendered, bounding their age so
# a stale file cannot pass as a current one.
#
# F5, 20261106 -- THE HEADER WAS FALSE. It said this oracle "renders the OTEL
# artifacts, and -- the part that matters -- CHECKS that the write landed
# instead of asserting it did", and the body below said "Artifact write, then
# VERIFY it by reading the file back". THERE IS NO WRITE IN THIS FILE. The
# only world contact is `test -d state`, `wc -l` on the jsonl and `cat` on
# the analytics json. So the arms measured a file some other process wrote at
# an unknown earlier time, with no freshness check of any kind.
#
# That is the `observationNow` defect this architecture exists to kill,
# relocated from a Lean constant to a filesystem artifact: a recorded value,
# re-read as current forever, re-verified by nothing. At the time the defect
# was found both artifacts were dated 02:34 while the oracle sources were
# last modified 02:54-06:15 -- the evidence predated the instrument, and the
# arm passed.
#
# Reading back an artifact another tool renders IS a legitimate division of
# labour. It stops being one when the file claims to have done the rendering
# and puts no bound on the artifact's age. The claim is corrected and the
# bound is added; the rendering stays where it actually lives.
#
# WHAT THE OLD PROBER DID
# -----------------------
# The `def main` removed from that Lean file bound the sqlite3 subprocess
# result to `_` and then printed `sqlite_synced=true` unconditionally. The
# banner was a literal, not a finding: it said "true" whether the write
# succeeded, failed, or sqlite3 was absent. Here the write is verified by
# reading the file back and comparing its line count.
#
# THE SQLITE SYNC IS NOT REPRODUCED. The old prober issued
# `DELETE FROM sa_plan_fractal_log` and INSERTs directly against
# var/sa-plan/uos.sqlite3 -- the Sa-plan execution authority's own store --
# bypassing every sa-plan command. SC-RISK-PRIORITY-001 section 8 bars direct
# database writes. Porting it to Mojo would move a governance violation, not
# fix it, so it is reported as an open operator question.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains
from oracle_substrate import json_int

# F5: an artifact older than this is not a current observation. Generous by
# intent -- it excludes a file from an arbitrary past run, it does not demand
# the renderer run on this oracle's schedule.
comptime MAX_ARTIFACT_AGE_MIN = 1440
# The MCP catalog target count the analytics artifact should declare.
comptime EXP_CATALOG_TARGETS = 12
comptime LAYERS = 10
comptime SEVERITY_NUMBER = 9
comptime SPAN_ID_LEN = 16
comptime EVIDENCE_SHA_LEN = 64
comptime STATE_DIR = "state"


def span_within_budget(
    observed_ns: Int, p99_ns: Int, budget_ns: Int,
    span_id_len: Int, parent_span_id_len: Int,
    severity_number: Int, pii_scrubbed: Int, heap_alloc_bytes: Int,
    evidence_sha_len: Int,
) -> Bool:
    """Mirror of UOS.ContextPathKpiOtelTwin.spanWithinBudget (Lean :140)."""
    return (
        observed_ns <= budget_ns
        and p99_ns <= budget_ns
        and span_id_len == SPAN_ID_LEN
        and parent_span_id_len == SPAN_ID_LEN
        and severity_number == SEVERITY_NUMBER
        and pii_scrubbed == 1
        and heap_alloc_bytes == 0
        and evidence_sha_len == EVIDENCE_SHA_LEN
    )


def span_timings_monotonic(observed_ns: Int, p99_ns: Int,
                           budget_ns: Int) -> Bool:
    """Mirror of UOS.ContextPathKpiOtelTwin.THM_KPI_06's predicate (:158-159).

    ADDED 20261106-0924. The twin proves `observedNs <= p99Ns && p99Ns <=
    budgetNs` over all ten layer spans, and this plane had no counterpart --
    the ordering was asserted by the kernel and checked by nothing here.
    """
    return observed_ns <= p99_ns and p99_ns <= budget_ns


def ideal_span() -> Bool:
    return span_within_budget(100, 200, 1000, 16, 16, 9, 1, 0, 64)


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
        String("formal/lean/UosContextPathKpiOtelTwin.lean"),
    )

    # ---- ALGEBRA: each of the 8 conjuncts must be load-bearing ---------
    r.algebra(String("span:ideal-within-budget"), ideal_span())
    r.algebra(String("conjunct:observed-over-budget"),
        not span_within_budget(1001, 200, 1000, 16, 16, 9, 1, 0, 64))
    r.algebra(String("conjunct:p99-over-budget"),
        not span_within_budget(100, 1001, 1000, 16, 16, 9, 1, 0, 64))
    r.algebra(String("conjunct:short-span-id"),
        not span_within_budget(100, 200, 1000, 15, 16, 9, 1, 0, 64))
    r.algebra(String("conjunct:short-parent-span-id"),
        not span_within_budget(100, 200, 1000, 16, 15, 9, 1, 0, 64))
    r.algebra(String("conjunct:wrong-severity"),
        not span_within_budget(100, 200, 1000, 16, 16, 8, 1, 0, 64))
    r.algebra(String("conjunct:pii-not-scrubbed"),
        not span_within_budget(100, 200, 1000, 16, 16, 9, 0, 0, 64))
    r.algebra(String("conjunct:heap-allocated"),
        not span_within_budget(100, 200, 1000, 16, 16, 9, 1, 1, 64))
    r.algebra(String("conjunct:short-evidence-digest"),
        not span_within_budget(100, 200, 1000, 16, 16, 9, 1, 0, 63))
    # L7 FIX, 20261106-0924 (re-review finding 12). THE WITHDRAWAL WAS WRONG.
    #
    # This arm began as `200 >= 100`, a literal. I replaced it with an
    # assertion that `span_within_budget` REJECTS an inverted p99/observed
    # pair; that went DIVERGENT, and I concluded the ordering was "an
    # unconstrained property, on both planes" and filed it as an `observe` of
    # a `String(Bool)` -- a channel that is never empty and so never BLIND
    # and never failing. So a literal became a recorded falsehood.
    #
    # The correct conclusion was narrower. `spanWithinBudget`
    # (`UosContextPathKpiOtelTwin.lean:141`) does not constrain the ordering,
    # which is why the mirror was faithful and my first replacement was
    # wrong. But the TWIN DOES constrain it, in a separate theorem:
    #
    #   :158-159  THM_KPI_06_monotonic_span_timings --
    #     allLayerSpans.all (fun s => s.observedNs <= s.p99Ns
    #                              && s.p99Ns <= s.budgetNs) = true
    #
    # and THM_KPI_06 had NO MOJO COUNTERPART AT ALL. The gap was not that
    # neither plane constrains the ordering; it was that one plane proves it
    # and the other never checked. Two self-corrections in a row moved away
    # from that, each one narrowing a true statement into a false one.
    #
    # The counterpart is added here as its own predicate, mirroring
    # THM_KPI_06 rather than spanWithinBudget, and applied to the spans the
    # twin declares.
    r.algebra(String("kpi06:predicate-rejects-p99-below-observed"),
              not span_timings_monotonic(200, 100, 1000))
    r.algebra(String("kpi06:predicate-rejects-p99-above-budget"),
              not span_timings_monotonic(100, 1001, 1000))
    r.algebra(String("kpi06:ideal-ordering-is-accepted"),
              span_timings_monotonic(100, 200, 1000))
    # And the budget conjunct spanWithinBudget genuinely does carry, kept
    # because it is a different claim from the ordering.
    r.algebra(String("budget:predicate-rejects-p99-over-budget"),
              not span_within_budget(100, 1001, 1000, 16, 16, 9, 1, 0, 64))

    # BOUNDARY ARMS, added 20261107-2147, finding F-W-19.
    #
    # The mirror mutation sweep killed every `and -> or` and `== -> !=` flip
    # on these two mirrors but THREE `<= -> <` flips SURVIVED, at lines 72,
    # 73 and 91. The reason is that every existing call passes strictly
    # separated values -- ideal_span() is span_within_budget(100, 200, 1000,
    # ...), and the negative arms above use 1001 against 1000 -- so no input
    # ever sat ON the bound, and `<=` and `<` agree everywhere except there.
    # Interior test points leave every comparison-operator flip alive. Same
    # defect class as F-W-04, which was closed for classify_archetype and
    # classify_regime earlier today and is now closed here.
    #
    # Each arm isolates ONE comparison by putting exactly one argument on the
    # bound and keeping the other strictly inside it, so a survivor names the
    # line it belongs to instead of being absorbed by a neighbour.
    r.algebra(String("bound:observed-exactly-at-budget-is-within"),
              span_within_budget(1000, 500, 1000, 16, 16, 9, 1, 0, 64))
    r.algebra(String("bound:observed-one-over-budget-is-not"),
              not span_within_budget(1001, 500, 1000, 16, 16, 9, 1, 0, 64))
    r.algebra(String("bound:p99-exactly-at-budget-is-within"),
              span_within_budget(100, 1000, 1000, 16, 16, 9, 1, 0, 64))
    r.algebra(String("bound:monotonic-allows-observed-equal-to-p99"),
              span_timings_monotonic(100, 100, 500))
    r.algebra(String("bound:monotonic-allows-p99-equal-to-budget"),
              span_timings_monotonic(100, 500, 500))
    r.algebra(String("bound:monotonic-allows-all-three-equal"),
              span_timings_monotonic(500, 500, 500))
    r.algebra(String("bound:monotonic-rejects-observed-one-over-p99"),
              not span_timings_monotonic(101, 100, 500))

    # F8, 20261106: the positive control is kept, as an OBSERVATION where it
    # belongs, and a real negative control is added. Routing a positive
    # control through `mutation_probe` spent the one slot reserved for the
    # negative one and left `vacuous` unable to increment, which makes
    # `Receipt.status()`'s first and gravest test dead code for this file.
    r.observe(String("positive-control-ideal-span-passes"),
              String(ideal_span()))
    r.mutation_probe(
        String("predicate-rejects-a-single-broken-field"),
        not span_within_budget(100, 200, 1000, 16, 16, 9, 0, 0, 64))

    # ---- WORLD ---------------------------------------------------------
    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # The Lean model must still declare exactly 10 layer spans. If someone
    # adds an L10 without updating the budget theorems, this catches it.
    var declared = capture(
        "grep -c 'layer :=' formal/lean/UosContextPathKpiOtelTwin.lean"
        + " 2>/dev/null")
    r.observe(String("declared-span-count"), declared)
    var n_declared: Int
    try:
        n_declared = Int(declared)
    except:
        n_declared = -1
    # F14, 20261106: bare `world()`. If the Lean subject were missing,
    # `Int("")` raises, `n_declared` is -1, and the arm reports "the wrong
    # span count" rather than "I could not read the subject".
    r.world_or_blind(String("ten-layer-spans-declared"),
                     n_declared >= 0, n_declared == LAYERS)

    # Artifact READ-BACK, with an age bound. This oracle does not render
    # these files; see the F5 note in the header.
    var state_ok = capture("test -d " + String(STATE_DIR) + " && echo yes")
    r.observe(String("state-dir"), state_ok)

    var jsonl = String(STATE_DIR) + "/context-fastpath-l0-l9.otel.jsonl"
    # F5: freshness. An artifact older than this bound is not a current
    # observation of anything, however well-formed it is. BLIND, not PASS:
    # the property was not observable at this candidate because nobody
    # rendered it recently. MAX_ARTIFACT_AGE_MIN is deliberately generous --
    # the point is to exclude a file from an arbitrary past run, not to
    # demand the renderer run on this oracle's schedule.
    var jsonl_age = count(
        "test -f " + jsonl + " && echo $(( ( $(date +%s)"
        + " - $(stat -c %Y " + jsonl + ") ) / 60 ))")
    r.observe_int(String("otel-jsonl-age-minutes"), jsonl_age)
    # FIXED 20261107-2140, finding F-W-14. This was
    #   world_or_blind(name, jsonl_age >= 0, jsonl_age <= MAX)
    # and `world_or_blind`'s first parameter is FIELD PRESENCE. A stale age is
    # present, just large, so the arm reported WORLD_FAIL -- contradicting the
    # F5 comment directly above, which says BLIND. `world_fresh` scores stale
    # and unknowable ages as BLIND, which is what this file always claimed.
    r.world_fresh(String("otel-jsonl-is-fresh"),
                  jsonl_age, MAX_ARTIFACT_AGE_MIN)

    var existing = capture("wc -l < " + jsonl + " 2>/dev/null")
    r.observe(String("otel-jsonl-readback"), existing)
    var n_lines: Int
    try:
        n_lines = Int(existing)
    except:
        n_lines = -1
    # One JSONL line per layer span. A short file means a partial write, which
    # the old `sqlite_synced=true` banner would have reported as success.
    # Gated on freshness: a correct line count in a stale file is not
    # evidence that the current pipeline produces one span per layer.
    r.world_or_blind(String("otel-jsonl-has-one-line-per-span"),
        n_lines >= 0 and jsonl_age >= 0
        and jsonl_age <= MAX_ARTIFACT_AGE_MIN,
        n_lines == LAYERS)

    var analytics = String(STATE_DIR) + "/context-fastpath-analytics.json"
    var an_body = capture("cat " + analytics + " 2>/dev/null")
    r.observe(String("analytics-readback"), an_body)
    var an_age = count(
        "test -f " + analytics + " && echo $(( ( $(date +%s)"
        + " - $(stat -c %Y " + analytics + ") ) / 60 ))")
    r.observe_int(String("analytics-age-minutes"), an_age)
    # FIXED 20261107-2140, finding F-W-14 -- same defect as otel-jsonl-is-fresh
    # above. This arm is what actually produced the PASS -> WORLD_FAIL -> PASS
    # oscillation: at 04:00Z the analytics file was 1600 minutes old against a
    # 1440 bound, and a WORLD_FAIL was recorded for a file nobody had
    # re-rendered. Stale is now BLIND, in this arm and in the arm that reads
    # the file's contents.
    r.world_fresh(String("analytics-is-fresh"),
                  an_age, MAX_ARTIFACT_AGE_MIN)
    # F18, 20261106: this arm was named "...-declares-twelve-catalog-targets"
    # and tested `contains(an_body, "l5_mcp_catalog_observed")` -- the
    # presence of a KEY NAME, not the number twelve. Presence-as-evidence:
    # the arm passed on a file that mentioned the field with any value at
    # all, including a wrong one. The value is now read and compared.
    var catalog_observed = json_int(an_body, String("l5_mcp_catalog_observed"))
    r.observe_int(String("analytics-l5-mcp-catalog-observed"),
                  catalog_observed)
    # FIXED 20261107-2145, finding F-W-14. This was `world_count`, a HARD
    # world arm, reading a value out of the analytics file whose freshness is
    # bounded by a DIFFERENT arm (`analytics-is-fresh`, above). The age bound
    # was honest and reported BLIND; this arm, independently, reported
    # `world:...:got-N-want-12` from the very same stale bytes. The guard and
    # the read it licenses were in separate arms, so the guard gated nothing.
    #
    # Consequence, measured on this host: PASS yesterday -> WORLD_FAIL at
    # ~04:00Z today (age 1600 min against MAX_ARTIFACT_AGE_MIN 1440, crossing
    # ~01:34Z) -> PASS again at 20:36Z (age 31 min; the renderer ran 20:05Z).
    # No code changed on either side. A stale artifact is now BLIND here, in
    # the same arm that reads it.
    r.world_count_fresh(String("analytics-declares-twelve-catalog-targets"),
                        catalog_observed, EXP_CATALOG_TARGETS,
                        an_age, MAX_ARTIFACT_AGE_MIN)

    # The sa-plan store must NOT have been written by this plane. Report the
    # open question rather than performing or claiming the sync.
    print("# OPEN (operator): the removed prober wrote sa_plan_fractal_log")
    print("#   directly in var/sa-plan/uos.sqlite3, bypassing sa-plan.")
    print("#   Not ported. Needs a decision on which sa-plan command owns it.")

    print("# probe time        :", now)
    print("# declared spans    :", n_declared, "(expected", LAYERS, ")")
    print("# otel jsonl lines  :", n_lines)
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
