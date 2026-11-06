# ==========================================================================
# proof_plane_guard_oracle — tree-wide enforcement of the Lean/Mojo boundary
# over formal/lean/*.lean.
#
# WHY THIS REPLACED "CLEAR THE 18 SORRY"
# --------------------------------------
# The plan's Phase 3 was "clear the 18 prober-resident `sorry`". That phase
# had NO WORK IN IT, and the reason is instructive: the count came from
# grepping the WORD "sorry", which matched docstrings and banners like
# "0 sorry, 0 axioms". There were never any `sorry` PROOF TERMS in the
# canonical tree. The metric measured boasts about rigour, not rigour, and
# the 18/20 correlation it produced -- "incompleteness concentrates in
# prober files" -- was an artifact: files that print a PASS banner are
# exactly the files that boast about having no `sorry`.
#
# So Phase 3 became this: stop counting the word, start checking the claim,
# tree-wide, every run.
#
# WHY THE GREPS ARE GONE
# ----------------------
# Every arm below used to be a grep over raw Lean source, and greps cannot
# tell code from prose. Twice a file was reported as a BOUNDARY VIOLATION
# for documenting what it no longer does:
#
#   UosCoreEvoUnifiedDigitalTwin   "This file has no `def main`, no `IO.Process`"
#   BionicMojoLeanHighPerformance  "(5 `IO.Process.output` calls ... `IO.FS.writeFile`)"
#
# The first was patched by requiring the trailing member-access dot. That was
# not a fix but a narrower guess, and the second case has the dot -- inside a
# comment -- and tripped anyway. A guard that punishes a file for explaining
# itself teaches authors to stop explaining.
#
# All measurement now comes from `tools/lean_proof_plane_scan.ml`, which
# strips nested `/- -/` comments, `--` lines, `/-! -/` docstrings and string
# literals BEFORE matching. This oracle reads that scanner's JSONL and
# decides. One measurement source, four arms, no independently-wrong regexes.
#
# WHAT IT ENFORCES
# ----------------
#   G1   no `sorry` reported by the Lean ELABORATOR (checked by
#        tools/lean_mojo_differential.ml, which has the Lean toolchain; the
#        elaborator emits "declaration uses 'sorry'" and prose cannot fool it)
#   G2   no `axiom` declarations
#   G3a  HARD, NO EXEMPTION: no IO and no `def main` BEFORE the last theorem
#        of a theorem-bearing file. Lean requires declaration before use, so
#        a trailing IO section provably cannot be an input to any proof above
#        it -- and an IO declaration positioned above one provably can.
#   G3b  a theorem-bearing file with a TRAILING IO section is a renderer and
#        must be DECLARED in
#        governance/agents/policy/20261106-0358-lean-proof-plane-renderer-manifest.json
#        with a stated sanction. An undeclared one fails; a declared one that
#        exceeds its io_budget fails. The manifest cannot grow quietly and a
#        declared renderer cannot become a prober.
#   G4a  no frozen present-tense FIXTURES (`def observationNow`, `def *Now :`)
#   G4b  no frozen present-tense THEOREMS (`*_now`, `*_today`)
#   G5   no unconditional `=PASS` banners
#
# G3a is why this guard is not a name allowlist. A name allowlist says a file
# is trusted, not why, and nothing re-checks the why.
#
# G4 is the arm no existing check covered. A record like
#     def observationNow := { observedUtc := "2026-11-05T17:05:00Z", ... }
#     theorem THM_RUN_01_aligned_now : aligned expectation observationNow = true := by decide
# freezes a claim about a moving world into a kernel-checked proof. The kernel
# re-verifies the arithmetic forever and never re-verifies the fact. One such
# record stayed green for four hours after its subject became false.
# Historical fixtures are fine -- `observationDuringOutage` names a past
# moment and claims nothing about now. Present tense is not fine.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import (
    Receipt, capture, contains, json_int, json_norm, occurrences,
)

comptime SCANNER = "tools/lean_proof_plane_scan.ml"
comptime MANIFEST = (
    "governance/agents/policy/"
    "20261106-0358-lean-proof-plane-renderer-manifest.json")
comptime OCAML = "./toolchains/opam-ocaml/bin/ocaml -I +unix unix.cma"
comptime ONTOLOGY = (
    "governance/agents/policy/"
    "20261106-0430-uos-lean-mojo-ontology-and-naming-manifest.json")


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def sev_rank(verdict: String) -> Int:
    """Read one verdict's rank out of the driver's `severity` table.

    F11, 20261106: the lattice arms used to be integer literals. Reading the
    table means a renumbering, a reordering, or a verdict added without a
    rank all move the arms that depend on it.
    """
    var raw = capture(
        "awk '/^let severity = function/{p=1;next} p&&/^$/{exit} p' "
        + "tools/lean_mojo_differential.ml 2>/dev/null"
        + " | grep -E '\\| " + verdict + " ->' | grep -oE '[0-9]+'")
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(String(raw.strip()))
    except:
        return -1


def exit_rank(verdict: String) -> Int:
    """Read one verdict's PROCESS EXIT CODE out of the driver's `exit_of`.

    Deliberately separate from `sev_rank`. These are two different tables and
    conflating them is the error the literal arms concealed.
    """
    var raw = capture(
        "awk '/^let exit_of = function/{p=1;next} p&&/^$/{exit} p' "
        + "tools/lean_mojo_differential.ml 2>/dev/null"
        + " | grep -E '\\| " + verdict + " ->' | grep -oE '[0-9]+'")
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(String(raw.strip()))
    except:
        return -1


def field_total(scan: String, key: String) -> Int:
    """Sum one scanner field across every file row. -1 if unreadable, which
    the substrate scores BLIND rather than zero: an unreadable scan is not a
    clean tree."""
    if scan.byte_length() == 0:
        return -1
    var total = 0
    var k = String("\"") + key + String("\":")
    var parts = scan.split(k)
    if len(parts) < 2:
        return -1
    for i in range(1, len(parts)):
        var digits = String("")
        for c in parts[i].codepoints():
            if c.is_ascii_digit():
                digits += String(c)
            else:
                break
        if digits.byte_length() > 0:
            try:
                total += Int(digits)
            except:
                return -1
    return total


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/*.lean (tree-wide proof-plane guard)"),
    )

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- the single measurement -----------------------------------------
    var scan = capture(
        String(OCAML) + " " + String(SCANNER) + " formal/lean 2>/dev/null")
    r.observe(String("scanner-output"), scan)
    var files = occurrences(scan, String("{\"file\":"))
    r.observe_int(String("file-inventory"), files)
    # A scanner that returned nothing must not read as a clean tree.
    r.world_or_blind(String("scanner-produced-rows"),
                     scan.byte_length() > 0, files > 0)
    r.world_or_blind(String("inventory-is-plausible"),
                     files > 0, files >= 100)

    # ---- G2: axiom declarations -----------------------------------------
    # `axiom` adds an unproved assumption to the kernel. The tree claims 0.
    var axioms = field_total(scan, String("axioms"))
    r.world_count(String("g2-axiom-declarations"), axioms, 0)

    # ---- G3a: observation positioned where a proof can consume it -------
    var io_pre = field_total(scan, String("io_before_last_theorem"))
    var main_pre = field_total(scan, String("main_before_last_theorem"))
    r.world_count(String("g3a-io-before-last-theorem"), io_pre, 0)
    r.world_count(String("g3a-main-before-last-theorem"), main_pre, 0)
    if io_pre > 0 or main_pre > 0:
        print("# G3a VIOLATIONS -- observation above a proof that could use it:")
        print(capture(
            String(OCAML) + " " + String(SCANNER) + " formal/lean"
            + " 2>/dev/null | grep -v '\"io_before_last_theorem\":0,"
            + "\"main_before_last_theorem\":0'"))

    # ---- G3b: trailing renderers must be DECLARED -----------------------
    # Every file with theorems AND a trailing IO section is listed by name in
    # the manifest with a sanction. Undeclared => fail. This is the arm that
    # keeps the exemption set from growing in the dark.
    var trailing_list = capture(
        String(OCAML) + " " + String(SCANNER) + " formal/lean 2>/dev/null"
        + " | grep '\"trailing_io_section\":true'"
        + " | sed 's/.*\"file\":\"\\([^\"]*\\)\".*/\\1/'")
    var manifest = capture("cat " + String(MANIFEST) + " 2>/dev/null")
    r.observe(String("manifest"), manifest)

    var trailing_n = 0
    var undeclared = String("")
    if trailing_list.byte_length() > 0:
        for line in trailing_list.split(String("\n")):
            var f = String(line).strip()
            if String(f).byte_length() == 0:
                continue
            trailing_n += 1
            if not contains(manifest, String(f)):
                if undeclared.byte_length() > 0:
                    undeclared += String(" ")
                undeclared += String(f)
    r.observe(String("trailing-renderer-census"), String(trailing_n))
    r.world_or_blind(String("g3b-every-trailing-renderer-is-declared"),
                     manifest.byte_length() > 0,
                     undeclared.byte_length() == 0)
    if undeclared.byte_length() > 0:
        print("# G3b VIOLATIONS -- trailing IO with no declared sanction:")
        print(undeclared)

    # G3b-budget: the declared IO BUDGET is compared against what the scanner
    # actually counts, per file.
    #
    # CODEX FINDING, 20261106: without this, G3b was "a string-based name
    # allowlist in JSON". The arm searched the manifest text for a path and
    # checked that listed files exist; it never read `io_budget` or
    # `main_budget`. So a declared renderer could acquire ten new
    # `IO.Process.output` calls and stay green, and my own manifest claimed
    # "exceeding io_budget fails" -- which was not true of the code.
    # Substring matching also made it worse: a path appearing anywhere in the
    # manifest's prose would authorise the file.
    #
    # This is the difference between a sanction that is asserted and one that
    # is checked. A budget nothing compares is the same defect as a proof
    # that outlives its subject, one level up in the stack.
    var over_budget = String("")
    var budget_checked = 0
    if trailing_list.byte_length() > 0 and manifest.byte_length() > 0:
        for line in trailing_list.split(String("\n")):
            var f = String(String(line).strip())
            if f.byte_length() == 0:
                continue
            # Declared budgets for THIS file, read from the manifest entry
            # that names it. `-A6` bounds the window to the entry's own
            # fields so a neighbouring entry's budget cannot be borrowed.
            var declared_io = count(
                "grep -A6 '\"file\": \"" + f + "\"' " + String(MANIFEST)
                + " 2>/dev/null | grep -oE '\"io_budget\": *[0-9]+'"
                + " | grep -oE '[0-9]+' | head -1")
            var declared_main = count(
                "grep -A6 '\"file\": \"" + f + "\"' " + String(MANIFEST)
                + " 2>/dev/null | grep -oE '\"main_budget\": *[0-9]+'"
                + " | grep -oE '[0-9]+' | head -1")
            # Observed counts for the same file, from the one Lean reader.
            var row = capture(
                String(OCAML) + " " + String(SCANNER) + " " + f
                + " 2>/dev/null")
            var seen_io = json_int(row, String("io_total"))
            var seen_main = json_int(row, String("main_total"))
            if declared_io < 0 or declared_main < 0 or seen_io < 0 \
               or seen_main < 0:
                # A budget that cannot be read is not a satisfied budget.
                if over_budget.byte_length() > 0:
                    over_budget += String(" ")
                over_budget += f + String("(unreadable)")
                continue
            budget_checked += 1
            if seen_io > declared_io or seen_main > declared_main:
                if over_budget.byte_length() > 0:
                    over_budget += String(" ")
                over_budget += (
                    f + String("(io ") + String(seen_io) + String(">")
                    + String(declared_io) + String(", main ")
                    + String(seen_main) + String(">")
                    + String(declared_main) + String(")"))
    r.observe(String("budgets-compared"), String(budget_checked))
    r.world_or_blind(String("g3b-no-renderer-exceeds-its-declared-budget"),
                     budget_checked > 0,
                     over_budget.byte_length() == 0)
    if over_budget.byte_length() > 0:
        print("# G3b BUDGET VIOLATIONS -- declared renderer grew new IO:")
        print(over_budget)

    # The manifest must also not list files that no longer exist, or the
    # sanction outlives its subject -- the same defect as a frozen fixture,
    # one level up.
    var stale_entries = count(
        "grep -o '\"file\": \"formal/lean/[^\"]*\"' " + String(MANIFEST)
        + " 2>/dev/null | sed 's/.*\"\\(formal[^\"]*\\)\"/\\1/' | sort -u"
        + " | while read -r p; do [ -f \"$p\" ] || echo \"$p\"; done | wc -l")
    r.world_count(String("g3b-manifest-names-no-absent-file"),
                  stale_entries, 0)

    # ---- G6: vacuity by argument discard -------------------------------
    #
    # A vacuity shape G4 does not catch, found 20261106 and verified:
    #
    #   def fractalCellCovered (l) (d) (a) (c) (h) : Bool :=
    #     let _ := (l, d, a, c, h)
    #     true
    #
    #   theorem THM_HFB_ONT_05_full_fractal_coverage_10x10x17x13x5_complete :
    #     ... (allLayers.all (fun l => ... allHarnesses.all (fun h =>
    #           fractalCellCovered l d a c h))) = true := by decide
    #
    # The `decide` genuinely enumerates 110,500 combinations. Every one is
    # `true` BY CONSTRUCTION. The theorem's name claims "110,500 verified
    # fractal cells with zero gaps"; it establishes that `true` is `true`
    # 110,500 times.
    #
    # G4 catches a RECORDED value that went stale. This catches a value that
    # is never consulted at all -- so there is nothing to go stale, and
    # nothing to be right either. It is the larger failure of the two,
    # because the kernel's work makes it look like evidence: a quintuply
    # nested enumeration is expensive, visible, and completely empty.
    #
    # `let _ := (args)` is the idiom for silencing unused-variable warnings,
    # which is why it is dangerous -- it is a deliberate, legible marker that
    # the arguments are not consulted, and it reads as tidiness.
    #
    # Measured on stripped code, 3 hits across 108 files, 0 false positives.
    # Counted and reported rather than failed: a definition MAY legitimately
    # ignore its arguments. What cannot stand is a theorem quantifying over
    # them, discharging by `decide`, and claiming coverage. Separating those
    # needs the theorem's text, which is the operator's call, so the guard
    # names the files and the count instead of pretending to adjudicate.
    var arg_discard = field_total(scan, String("arg_discarding_defs"))
    r.observe(String("g6-argument-discarding-defs"), String(arg_discard))
    var discard_files = capture(
        String(OCAML) + " " + String(SCANNER) + " formal/lean 2>/dev/null"
        + " | grep -v '\"arg_discarding_defs\":0}'"
        + " | sed 's/.*\"file\":\"\\([^\"]*\\)\".*/\\1/'")
    if arg_discard > 0:
        print("# G6 VACUITY BY ARGUMENT DISCARD --",
              arg_discard, "def(s) that ignore every argument:")
        print(discard_files)
        print("#   Any theorem quantifying over those arguments and")
        print("#   discharging by `decide` proves `true = true`, however")
        print("#   many cells it enumerates.")
    # The arm that DOES fail: the count must not grow. A regression guard,
    # which is the honest framing for a defect whose existing instances are
    # another author's to adjudicate.
    r.world_or_blind(String("g6-argument-discard-count-has-not-grown"),
                     arg_discard >= 0, arg_discard <= 3)

    # ---- N1/N2: naming and ontology conformance -------------------------
    # Measured, not assumed. Two naming "drifts" recorded in the first pass
    # of this work were artifacts of my own measurement:
    #
    #   I was about to canonise THM_<FAM>_<nn>_<claim> tree-wide. Census:
    #   185 of 1,492 theorems use it. It is the MINORITY regime, and the one
    #   that puts an opaque family code where the claim already is.
    #
    #   I then counted ~146 "information-free" names from prefix shapes
    #   t<n>_, T<n>_, c<n>_, math<n>_. Exact count of names that are ONLY an
    #   index: zero. Every one of those prefixes is followed by its claim.
    #
    # So the enforced rule is the one both regimes already satisfy -- a
    # theorem name states its claim -- and N1 is a REGRESSION guard for a
    # property the tree already has, not a cleanup that was never needed.
    var index_only = field_total(scan, String("index_only_theorems"))
    r.world_count(String("n1-index-only-theorem-names"), index_only, 0)

    # N2: every namespace root is UOS or a root DECLARED in the ontology
    # manifest with a reason. Same mechanism as G3b: the exception set
    # cannot grow in the dark. `Ruliad` is a sanctioned second root (a
    # self-contained 18-file library); four flat roots are cited by
    # immutable journals and the ZK/wiki corpus, so renaming them would
    # dangle those citations, which INV-PROV-03 forbids.
    var onto = capture("cat " + String(ONTOLOGY) + " 2>/dev/null")
    r.observe(String("ontology-manifest"), onto)
    var roots = capture(
        String(OCAML) + " " + String(SCANNER) + " formal/lean 2>/dev/null"
        + " | grep -o '\"namespace_root\":\"[^\"]*\"'"
        + " | cut -d'\"' -f4 | sort -u")
    var undeclared_roots = String("")
    var root_n = 0
    if roots.byte_length() > 0:
        for line in roots.split(String("\n")):
            var root = String(line).strip()
            if String(root).byte_length() == 0:
                continue
            root_n += 1
            if String(root) == String("UOS"):
                continue
            if not contains(onto, String(root)):
                if undeclared_roots.byte_length() > 0:
                    undeclared_roots += String(" ")
                undeclared_roots += String(root)
    r.observe(String("namespace-root-census"), String(root_n))
    r.world_or_blind(String("n2-namespace-root-is-declared"),
                     onto.byte_length() > 0,
                     undeclared_roots.byte_length() == 0)
    if undeclared_roots.byte_length() > 0:
        print("# N2 VIOLATIONS -- namespace roots with no declared reason:")
        print(undeclared_roots)

    # ---- G4: frozen present-tense observations --------------------------
    var frozen_fix = field_total(scan, String("frozen_fixtures"))
    var frozen_thm = field_total(scan, String("frozen_theorems"))
    r.world_count(String("g4a-present-tense-fixtures"), frozen_fix, 0)
    r.world_count(String("g4b-present-tense-theorems"), frozen_thm, 0)

    # ---- G5: verdict banners printed from the proof plane ---------------
    # A Lean file's only evidence is that it typechecks. Printing
    #   "..._AND_DIGITAL_TWINS=PASS (13 Kernel-Checked Theorems, 0 sorry)"
    # from `lean --run` makes a typecheck read as a system verdict, which is
    # what THM_VAC_01 denies: staticModelObservesRuntime = false. Five such
    # banners became `=MODEL_CONSISTENT` on 20261106-0108. A CONDITIONAL
    # result is not matched: the generator's
    # `if fails == 0 then "SELFTEST PASS" else "SELFTEST FAIL"` reports a
    # real computation that can come out either way.
    var banners = field_total(scan, String("pass_banners"))
    r.world_count(String("g5-unconditional-pass-banners"), banners, 0)

    # ---- ALGEBRA: the guard's own decision function ---------------------
    # The verdict lattice `tools/lean_mojo_differential.ml` relies on,
    # re-evaluated here so the guard is not merely a pile of counts.
    # F11, 20261106. These six arms were the ENTIRE algebra plane of this
    # file and every one was arithmetic on literals the author typed:
    # `3 > 1`, `4 > 3`, `7 > 6`, `2 != 0`, `(0==0) and not (1==0)` and
    # `(205 < 266) and not (266 < 205)`. The comment above them claimed they
    # were "the guard's own decision function... re-evaluated here so the
    # guard is not merely a pile of counts". Nothing was re-evaluated.
    #
    # Two compounding errors the literals made undetectable:
    #
    #  1. The numerals matched `exit_of` (the PROCESS EXIT-CODE table, where
    #     World_fail is 1 and Blind is 2), not `severity` (the worst-wins
    #     LATTICE, where Blind is 1 and World_fail is 2). The arms were named
    #     for the lattice and transcribed the other table. Because any two
    #     distinct integers satisfy `>` in some order, both still passed.
    #  2. NO ARM ASSERTED that WORLD_FAIL outranks BLIND -- precisely the one
    #     ordering where the two tables disagree, and precisely the ordering
    #     F7 showed `Receipt.status()` was mishandling. The arm set covered
    #     everything except the thing that was wrong.
    #
    # The lattice is now READ from the driver that defines it, so these arms
    # fail if the table is renumbered, reordered, or if a verdict is added
    # without a rank. The exit-code table is read too, and the two are
    # explicitly asserted to DIFFER on the Blind/World_fail pair -- a
    # standing reminder that they are distinct tables, which is what the
    # original confusion needed and did not have.
    comptime DRIVER = "tools/lean_mojo_differential.ml"
    var sev_pass = sev_rank(String("Pass"))
    var sev_blind = sev_rank(String("Blind"))
    var sev_world = sev_rank(String("World_fail"))
    var sev_div = sev_rank(String("Divergent"))
    var sev_vac = sev_rank(String("Vacuous"))
    var sev_lean = sev_rank(String("Lean_fail"))
    var sev_unrun = sev_rank(String("Unrun"))
    var exit_blind = exit_rank(String("Blind"))
    var exit_world = exit_rank(String("World_fail"))
    r.observe_int(String("severity-pass"), sev_pass)
    r.observe_int(String("severity-blind"), sev_blind)
    r.observe_int(String("severity-world-fail"), sev_world)
    r.observe_int(String("severity-divergent"), sev_div)
    r.observe_int(String("severity-vacuous"), sev_vac)
    r.observe_int(String("severity-unrun"), sev_unrun)
    var lattice_read = (
        sev_pass >= 0 and sev_blind >= 0 and sev_world >= 0
        and sev_div >= 0 and sev_vac >= 0 and sev_lean >= 0
        and sev_unrun >= 0 and exit_blind >= 0 and exit_world >= 0)
    r.world_or_blind(String("verdict-lattice-is-readable-from-the-driver"),
                     lattice_read, lattice_read)
    if lattice_read:
        r.algebra(String("lattice-pass-is-the-minimum"),
                  sev_pass == 0
                  and sev_pass < sev_blind and sev_pass < sev_world
                  and sev_pass < sev_div and sev_pass < sev_vac
                  and sev_pass < sev_lean and sev_pass < sev_unrun)
        # THE ORDERING THE OLD ARM SET OMITTED.
        r.algebra(String("lattice-world-fail-outranks-blind"),
                  sev_world > sev_blind)
        r.algebra(String("lattice-divergent-outranks-world-fail"),
                  sev_div > sev_world)
        r.algebra(String("lattice-vacuous-outranks-divergent"),
                  sev_vac > sev_div)
        r.algebra(String("lattice-unrun-outranks-every-verdict"),
                  sev_unrun > sev_lean and sev_unrun > sev_vac
                  and sev_unrun > sev_div and sev_unrun > sev_world
                  and sev_unrun > sev_blind and sev_unrun > sev_pass)
        # The two tables are DIFFERENT tables. Asserted, so a future reader
        # cannot repeat the transcription the literals permitted.
        r.algebra(String("exit-codes-are-not-the-severity-lattice"),
                  exit_world < exit_blind and sev_world > sev_blind)
    else:
        r.observe(String("lattice-arms"),
                  String("skipped: driver lattice unreadable"))
    # The ordering rule's soundness, stated as the arithmetic it rests on:
    # an offset before the last theorem is strictly less than it, and Lean's
    # declaration-before-use makes that the whole criterion.
    # F11: was `(205 < 266) and not (266 < 205)` -- two literals, asserting
    # that `<` is asymmetric. It restated a property of the integers under a
    # name about the guard's criterion, and the guard was never consulted.
    #
    # I looked for the real offsets to compare and the scanner does not
    # publish a last-theorem line, only `first_offending_line`. Rather than
    # invent a second offset so the arm could keep its original shape --
    # which is how an oracle ends up measuring its own arithmetic -- the arm
    # now tests the CONSISTENCY of the two fields the scanner does publish:
    # a tree with no IO before its last theorem must report no offending
    # line, and a nonzero count must name one. An inconsistency there means
    # the reader is wrong, which is the only thing this arm was ever in a
    # position to detect.
    var offending_line = field_total(scan, String("first_offending_line"))
    r.observe_int(String("scanner-first-offending-line-total"),
                  offending_line)
    # L4 FIX, 20261106-0924 (re-review finding 17). This compared
    # `io_pre == 0` against `offending_line == 0`, but
    # `tools/lean_proof_plane_scan.ml:379-380` sets `first_offending_line`
    # from `min_opt (io_pre @ main_pre)` -- BOTH lists. So a file with a
    # `def main` before its last theorem and no IO token yields
    # `io_before_last_theorem = 0` and `first_offending_line > 0`, and the arm
    # reported "the reader is wrong" when the reader was right. Both counts
    # are already in hand, so the consistency check uses both.
    var main_pre_total = field_total(scan, String("main_before_last_theorem"))
    r.observe_int(String("scanner-main-before-last-theorem-total"),
                  main_pre_total)
    r.world_or_blind(String("scanner-offence-count-and-line-agree"),
                     io_pre >= 0 and main_pre_total >= 0
                     and offending_line >= 0,
                     ((io_pre + main_pre_total) == 0)
                     == (offending_line == 0))

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # The scanner must SEE a violation and must NOT see prose. Plant both in
    # a scratch tree: one file with a real frozen fixture above a theorem,
    # one file whose COMMENT describes the same thing. If the first is not
    # caught the guard is blind; if the second IS caught the guard punishes
    # documentation, which is how the previous grep version behaved.
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
        probe = String("./.uos-guardprobe-tmp")
    _ = capture("rm -rf " + probe + " && mkdir -p " + probe)
    _ = capture(
        "printf 'def observationNow : Nat := 1\\n"
        + "theorem t_aligned_now : True := trivial\\n'"
        + " > " + probe + "/Real.lean")
    _ = capture(
        "printf '/-! This file has no def main, no IO.Process.output,\\n"
        + "no IO.FS.writeFile, no def observationNow, and no\\n"
        + "theorem t_aligned_now. -/\\ntheorem t_clean : True := trivial\\n'"
        + " > " + probe + "/Prose.lean")
    var pscan = capture(
        String(OCAML) + " " + String(SCANNER) + " " + probe + " 2>/dev/null")
    var p_fix = field_total(pscan, String("frozen_fixtures"))
    var p_thm = field_total(pscan, String("frozen_theorems"))
    var p_io = field_total(pscan, String("io_before_last_theorem"))
    var p_main = field_total(pscan, String("main_before_last_theorem"))
    r.mutation_probe(String("scanner-sees-a-real-frozen-fixture"), p_fix == 1)
    r.mutation_probe(String("scanner-sees-a-real-frozen-theorem"), p_thm == 1)
    r.mutation_probe(String("scanner-does-not-flag-prose-io"), p_io == 0)
    r.mutation_probe(String("scanner-does-not-flag-prose-main"), p_main == 0)
    _ = capture("rm -rf " + probe)

    print("# probe time                 :", now)
    print("# lean files guarded         :", files)
    print("# G2 axiom declarations      :", axioms)
    print("# G3a io  before last theorem:", io_pre)
    print("# G3a main before last thm   :", main_pre)
    print("# G3b trailing renderers     :", trailing_n, "(all declared)"
          if undeclared.byte_length() == 0 else "(UNDECLARED PRESENT)")
    print("# G4a present-tense fixtures :", frozen_fix)
    print("# G4b present-tense theorems :", frozen_thm)
    print("# G5 unconditional banners   :", banners)
    print("# N1 index-only theorem names:", index_only)
    if undeclared_roots.byte_length() == 0:
        print("# N2 namespace roots         :", root_n, "(all declared)")
    else:
        print("# N2 namespace roots         :", root_n, "(UNDECLARED PRESENT)")
    print("# (G1 sorry is checked by tools/lean_mojo_differential.ml via the")
    print("#  Lean elaborator, which prose cannot fool)")
    r.emit()
    exit(r.exit_code())
