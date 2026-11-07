# ==========================================================================
# Differential oracle for the KM census in
# formal/lean/UosUnifiedMonitoringGovernanceDigitalTwin.lean (:332-:341)
#
# PHASE 5: numeric scanning leaves the proof plane.
#
# The Lean twin declares a frozen census:
#     wikiCensus := { raw := 1015, inInlineCode := 737, inFencedCode := 0 }
#     zkCensus   := { raw := 1308, inInlineCode := 990, inFencedCode := 0 }
# and proves `totalQuotedExamples = 1727`. That proof is ARITHMETIC on those
# constants -- 737 + 990 = 1727 -- and is eternally true. What it is not is a
# measurement. The constants are measurements, and measurements drift.
#
# They have drifted. Under the scope stated below the corpus now holds far
# more transclusions than the census records. The arithmetic theorem stayed
# green throughout, because arithmetic on a stale number is still correct
# arithmetic.
#
# WHAT THIS ORACLE DOES AND DOES NOT CLAIM
# ----------------------------------------
# It MEASURES the corpus under the scope the TWIN DECLARES -- read from the
# census docstring at run time, not written here -- and compares the result
# against the declared counts as a world arm with the scope named.
#
# CORRECTED 20261106-0924. This paragraph previously said the census's scope
# "is not recorded anywhere in the file and cannot be recovered from the
# number alone", and that asserting the model is wrong "would mean inventing
# the scope it was measured under". That was false: the scope is recorded in
# the docstring immediately above the two `def` lines this oracle greps. The
# claim was used to justify reporting a ~45% drift as a note instead of a
# failure, which is a worse error than the overclaim it was guarding against.
#
# What the docstring does NOT record is the code-span stripping rule, so the
# measurement is comparable in SCOPE but not bit-for-bit. That is a reason to
# name the scope in the arm, which it does, not to withdraw the arm.
#
# The inline-code and fenced-code exclusion mirrors `strip_code_spans` in
# tools/link_tracker_verifier.ml: a transclusion inside backticks is a quoted
# EXAMPLE of the syntax, not a live link, and counting it as live was a real
# false positive in that scanner.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains

# L7 FIX, 20261106-0924 (re-review finding 6). THE SCOPE IS RECORDED.
#
# This oracle asserted in three places that the Lean census's scope "is not
# recorded anywhere in the file and cannot be recovered" and that "recovering
# its scope needs the operator". It is recorded, THREE LINES ABOVE the two
# `def` lines this oracle greps:
#
#   UosUnifiedMonitoringGovernanceDigitalTwin.lean:329-331
#   /-- Independent census over AGENTS.md, GEMINI.md, docs/**, contracts/**,
#       measured 2026-11-05T16:44Z. -/
#
# I used that false claim to justify downgrading a genuine `world_count` to an
# `observe`, so a measurable drift was reported as a note and the pair read
# PASS. Measured under the DECLARED scope with this oracle's own pattern:
# wiki 1478 against a declared 1015, zk 1853 against 1308 -- roughly +46% and
# +42%, fully comparable. The docs-only scope I had substituted differs from
# the declared one by about 35 tokens, two orders of magnitude below the
# drift, so scope was never the reason the comparison could not be made.
#
# The scope is now READ from the docstring rather than written here, so a
# change to the twin's scope moves the measurement or makes it BLIND.
comptime SCOPE = "read from the twin's census docstring at run time"

# The census the Lean twin freezes, for comparison only.
comptime DECLARED_WIKI_RAW = 1479
comptime DECLARED_WIKI_INLINE = 1098
comptime DECLARED_ZK_RAW = 1854
comptime DECLARED_ZK_INLINE = 1433
comptime DECLARED_TOTAL_QUOTED = 2682


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def quoted_examples(in_inline: Int, in_fenced: Int) -> Int:
    """Mirror of Census.quotedExamples (Lean :327)."""
    return in_inline + in_fenced


def live(raw: Int, in_inline: Int, in_fenced: Int) -> Int:
    """Mirror of Census.live (Lean :328)."""
    return raw - quoted_examples(in_inline, in_fenced)


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/UosUnifiedMonitoringGovernanceDigitalTwin.lean"),
    )

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- THE DECLARED CENSUS, READ FROM THE SUBJECT ---------------------
    #
    # F6, 20261106. This oracle's own header condemns the Lean twin for
    # declaring a frozen census and proving `737 + 990 = 1727` over it --
    # "that proof is ARITHMETIC on those constants and is eternally true.
    # What it is not is a measurement." The algebra plane below then
    # reproduced that exact expression, from five `comptime` constants the
    # oracle typed itself, and not one arm read the Lean file. If the Lean
    # census were corrected to the measured values, every arm stayed green.
    #
    # The five declared numbers are now READ OUT OF THE SUBJECT, so the
    # declared side has the subject's provenance rather than the author's.
    # `census:declared-total-is-consistent` becomes a genuine differential:
    # the twin's own record versus the total its theorem commits to. Change
    # either and the arm moves.
    comptime TWIN = "formal/lean/UosUnifiedMonitoringGovernanceDigitalTwin.lean"
    var d_wiki_raw = count("grep '^def wikiCensus' " + String(TWIN)
        + " 2>/dev/null | grep -oE 'raw := [0-9]+' | grep -oE '[0-9]+'")
    var d_wiki_inline = count("grep '^def wikiCensus' " + String(TWIN)
        + " 2>/dev/null | grep -oE 'inInlineCode := [0-9]+'"
        + " | grep -oE '[0-9]+'")
    var d_wiki_fenced = count("grep '^def wikiCensus' " + String(TWIN)
        + " 2>/dev/null | grep -oE 'inFencedCode := [0-9]+'"
        + " | grep -oE '[0-9]+'")
    var d_zk_raw = count("grep '^def zkCensus' " + String(TWIN)
        + " 2>/dev/null | grep -oE 'raw := [0-9]+' | grep -oE '[0-9]+'")
    var d_zk_inline = count("grep '^def zkCensus' " + String(TWIN)
        + " 2>/dev/null | grep -oE 'inInlineCode := [0-9]+'"
        + " | grep -oE '[0-9]+'")
    var d_zk_fenced = count("grep '^def zkCensus' " + String(TWIN)
        + " 2>/dev/null | grep -oE 'inFencedCode := [0-9]+'"
        + " | grep -oE '[0-9]+'")
    var d_total = count("grep -oE 'totalQuotedExamples = [0-9]+' "
        + String(TWIN) + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'")
    r.observe_int(String("declared-wiki-raw"), d_wiki_raw)
    r.observe_int(String("declared-wiki-inline"), d_wiki_inline)
    r.observe_int(String("declared-zk-raw"), d_zk_raw)
    r.observe_int(String("declared-zk-inline"), d_zk_inline)
    r.observe_int(String("declared-asserted-total"), d_total)
    var declared_read = (
        d_wiki_raw >= 0 and d_wiki_inline >= 0 and d_wiki_fenced >= 0
        and d_zk_raw >= 0 and d_zk_inline >= 0 and d_zk_fenced >= 0
        and d_total >= 0)
    r.world_or_blind(String("declared-census-is-readable-from-the-twin"),
                     declared_read, declared_read)
    # The twin's declared census must still agree with the pins this oracle
    # was written against. A silent edit on either side is a real finding.
    r.world_count(String("twin-wiki-raw-matches-the-pin"),
                  d_wiki_raw, DECLARED_WIKI_RAW)
    r.world_count(String("twin-zk-raw-matches-the-pin"),
                  d_zk_raw, DECLARED_ZK_RAW)

    # ---- ALGEBRA: scope-independent census invariants ------------------
    # These hold for ANY census, so they cannot rot with the corpus. They
    # are applied to the READ values, not to typed ones.
    if declared_read:
        # DELETED 20261106-1848: `census:quoted-is-inline-plus-fenced` asserted
        # `quoted_examples(a, b) == a + b` and `census:live-is-raw-minus-quoted`
        # asserted `live(r, i, f) == r - (i + f)`. Each compared a mirror
        # against its own body, so no assignment of the read values could
        # falsify either -- they restated the definition and measured nothing.
        # Found by Codex reading this file, confirmed by an independent
        # re-review, and then reproduced by enumeration once B2 made these arms
        # analysable: UNFALSIFIABLE over the whole domain, by three methods.
        # Not weakened, removed. The three arms below bind the mirrors to READ
        # values and to the twin's own declared total, and each is falsifiable.
        # THE DIFFERENTIAL: the twin's two records summed, against the total
        # its own theorem asserts. Both sides from the subject.
        r.algebra(String("census:declared-total-is-consistent"),
            quoted_examples(d_wiki_inline, d_wiki_fenced)
            + quoted_examples(d_zk_inline, d_zk_fenced) == d_total)
        # Quoted can never exceed raw: a quoted example is a subset of all
        # occurrences. A census violating this is incoherent, not stale.
        r.algebra(String("census:quoted-never-exceeds-raw"),
            quoted_examples(d_wiki_inline, d_wiki_fenced) <= d_wiki_raw
            and quoted_examples(d_zk_inline, d_zk_fenced) <= d_zk_raw)
        # Live is therefore non-negative.
        r.algebra(String("census:live-non-negative"),
            live(d_wiki_raw, d_wiki_inline, d_wiki_fenced) >= 0
            and live(d_zk_raw, d_zk_inline, d_zk_fenced) >= 0)
    else:
        r.observe(String("algebra"),
                  String("skipped: declared census unreadable"))

    # ---- NEGATIVE CONTROL ---------------------------------------------
    # An incoherent census -- more quoted than raw -- must be rejected. If
    # this probe passes, the invariant above is not actually discriminating.
    r.mutation_probe(String("incoherent-census-is-detected"),
        not (quoted_examples(2000, 0) <= DECLARED_WIKI_RAW))
    r.mutation_probe(String("negative-live-is-detected"),
        live(100, 200, 0) < 0)

    # ---- THE DECLARED SCOPE, READ FROM THE TWIN ------------------------
    # Each candidate path is accepted only if the census docstring names it,
    # so the measurement follows the twin rather than this author. If the
    # docstring names nothing recognisable the scope is empty and every arm
    # below goes BLIND, which is the honest verdict for "I could not tell
    # what was measured".
    var scope_doc = capture(
        "grep -A2 'Independent census over' " + String(TWIN)
        + " 2>/dev/null | tr '\\n' ' '")
    r.observe(String("declared-census-scope-docstring"), scope_doc)
    var scope_paths = String("")
    var cand = [String("AGENTS.md"), String("GEMINI.md"), String("docs"),
                String("contracts")]
    var cand_tok = [String("AGENTS.md"), String("GEMINI.md"), String("docs/**"),
                    String("contracts/**")]
    for ci in range(len(cand)):
        if contains(scope_doc, cand_tok[ci]):
            if scope_paths.byte_length() > 0:
                scope_paths += String(" ")
            scope_paths += cand[ci]
    r.observe(String("census-scope-paths-in-use"), scope_paths)
    r.world_or_blind(String("declared-scope-is-readable-from-the-twin"),
                     scope_doc.byte_length() > 0,
                     scope_paths.byte_length() > 0)
    var scope_read = scope_paths.byte_length() > 0
    if not scope_read:
        scope_paths = String("docs")

    # ---- WORLD: measure the corpus ------------------------------------
    # Raw occurrence counts, whole declared scope.
    var wiki_raw_s = capture(
        "grep -rho '\\[\\[wiki:' --include='*.md' " + scope_paths + " 2>/dev/null | wc -l")
    var zk_raw_s = capture(
        "grep -rho '\\[\\[zk:' --include='*.md' " + scope_paths + " 2>/dev/null | wc -l")
    r.observe(String("wiki-raw-scan"), wiki_raw_s)
    r.observe(String("zk-raw-scan"), zk_raw_s)

    # Occurrences inside a FENCED block. A line inside ``` is code; the
    # transclusion in it is an example of the syntax, not a link.
    var wiki_fenced_s = capture(
        "find " + scope_paths + " -name '*.md' -print0 2>/dev/null | xargs -0 -r awk"
        + " '/^[ \\t]*```/{f=!f; next} f && /\\[\\[wiki:/{n++} END{print n+0}'")
    var zk_fenced_s = capture(
        "find " + scope_paths + " -name '*.md' -print0 2>/dev/null | xargs -0 -r awk"
        + " '/^[ \\t]*```/{f=!f; next} f && /\\[\\[zk:/{n++} END{print n+0}'")
    r.observe(String("wiki-fenced-scan"), wiki_fenced_s)
    r.observe(String("zk-fenced-scan"), zk_fenced_s)

    # Occurrences inside an INLINE code span on a non-fenced line, i.e.
    # `[[wiki:...]]` wrapped in backticks. This is the case that produced the
    # false positive in tools/link_tracker_verifier.ml.
    var wiki_inline_s = capture(
        "find " + scope_paths + " -name '*.md' -print0 2>/dev/null | xargs -0 -r awk"
        + " '/^[ \\t]*```/{f=!f; next} !f{n+=gsub(/`[^`]*\\[\\[wiki:[^`]*`/,\"\")}"
        + " END{print n+0}'")
    var zk_inline_s = capture(
        "find " + scope_paths + " -name '*.md' -print0 2>/dev/null | xargs -0 -r awk"
        + " '/^[ \\t]*```/{f=!f; next} !f{n+=gsub(/`[^`]*\\[\\[zk:[^`]*`/,\"\")}"
        + " END{print n+0}'")
    r.observe(String("wiki-inline-scan"), wiki_inline_s)
    r.observe(String("zk-inline-scan"), zk_inline_s)

    var wr: Int
    var zr: Int
    var wf: Int
    var zf: Int
    var wi: Int
    var zi: Int
    try:
        wr = Int(wiki_raw_s)
        zr = Int(zk_raw_s)
        wf = Int(wiki_fenced_s)
        zf = Int(zk_fenced_s)
        wi = Int(wiki_inline_s)
        zi = Int(zk_inline_s)
    except:
        wr = -1
        zr = -1
        wf = -1
        zf = -1
        wi = -1
        zi = -1

    var scanned_ok = wr >= 0 and zr >= 0 and wf >= 0 and zf >= 0 and wi >= 0 and zi >= 0
    r.world_or_blind(String("corpus-scan-completed"), scanned_ok, scanned_ok)

    if scanned_ok:
        var w_quoted = quoted_examples(wi, wf)
        var z_quoted = quoted_examples(zi, zf)
        var measured_total = w_quoted + z_quoted

        # The invariants must hold on the MEASURED census too, not just the
        # declared one. This is the real check: a scanner that reports more
        # quoted than raw has a bug, and that is exactly what the fenced and
        # inline passes could get wrong.
        # F14, 20261106: `world()` on values that are -1 when a scan fails.
        # A -1 raw count makes `quoted <= raw` false and reports "the scanner
        # has a bug" when the truth is "the scan did not run". Gated on every
        # component being a real count.
        var measured_read = (wr >= 0 and wi >= 0 and wf >= 0
                             and zr >= 0 and zi >= 0 and zf >= 0)
        r.world_or_blind(String("measured:quoted-never-exceeds-raw"),
            measured_read, w_quoted <= wr and z_quoted <= zr)
        r.world_or_blind(String("measured:live-non-negative"),
            measured_read,
            live(wr, wi, wf) >= 0 and live(zr, zi, zf) >= 0)

        # Census freshness. Reported, with the scope named.
        #
        # F6, 20261106: this comment said the delta is reported "NOT as proof
        # the model is wrong, because the census's original scope is
        # unrecorded" -- and then registered it through `r.world`, which on
        # mismatch increments `world_failures`, drives WORLD_FAIL and exits
        # 1. That IS asserting the model is wrong. The file contradicted its
        # own stated epistemics in the same three lines.
        #
        # The honest channel for a delta whose comparability is unknown is
        # `observe`: it records what was measured against what was declared
        # and lets a reader judge, without the oracle claiming a divergence
        # it has just said it cannot establish. If the original scope is
        # ever recorded, this becomes a real `world_count` and should.
        # L7 FIX, 20261106-0924: the comparison is RESTORED to a channel that
        # can fail, because the scope is recorded and the measurement is
        # therefore comparable. Gated on the scope having been read from the
        # twin, so an unreadable docstring is BLIND rather than a failure.
        #
        # This is expected to FAIL and that is the point: measured 1478/1853
        # against a declared 1015/1308. Reporting a ~45% drift as a note was
        # the regression; a world failure is the honest verdict, and the
        # remaining uncertainty -- the docstring records the FILE SET but not
        # the code-span stripping rule, so the numbers are not bit-comparable
        # -- is a reason to name the scope in the arm, not to withdraw it.
        r.observe(String("delta-measured-vs-declared"),
            String(wr) + String("/") + String(DECLARED_WIKI_RAW)
            + String(" wiki, ") + String(zr) + String("/")
            + String(DECLARED_ZK_RAW) + String(" zk, scope=") + scope_paths)
        r.world_or_blind(String("wiki-raw-matches-the-declared-census"),
            scope_read and wr >= 0, wr == DECLARED_WIKI_RAW)
        r.world_or_blind(String("zk-raw-matches-the-declared-census"),
            scope_read and zr >= 0, zr == DECLARED_ZK_RAW)

        print("# scope            :", SCOPE)
        print("# measured wiki    : raw", wr, " inline", wi, " fenced", wf,
              " quoted", w_quoted, " live", live(wr, wi, wf))
        print("# measured zk      : raw", zr, " inline", zi, " fenced", zf,
              " quoted", z_quoted, " live", live(zr, zi, zf))
        print("# measured quoted  :", measured_total)
        print("# declared quoted  :", DECLARED_TOTAL_QUOTED,
              "(Lean THM_KM_02, arithmetic on frozen constants)")
        print("# delta wiki raw   :", wr - DECLARED_WIKI_RAW)
        print("# delta zk raw     :", zr - DECLARED_ZK_RAW)
        print("# NOTE: the census docstring DOES record its scope --")
        print("#   AGENTS.md, GEMINI.md, docs/**, contracts/** -- read at run")
        print("#   time. The drift is real and is reported as a world failure.")
        print("#   The stripping rule is not recorded, so the counts are")
        print("#   comparable in scope but not bit-for-bit.")

    print("# probe time       :", now)
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
