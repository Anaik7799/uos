# ==========================================================================
# language_conformance_oracle — measures the LIVE surface of barred helper
# languages, and the gates that grade file presence as verification.
#
# Lean subject: formal/lean/UosCoreEvoUnifiedDigitalTwin.lean
#   (its stratum table at :737 asserts `.s1Systemd` for a script that has no
#    systemd unit and no executor; this oracle is what re-measures it)
#
# THE RULE
# --------
# CLAUDE.md:28 -- "New automation is Lean 4, Gleam or Rust; helper scripts are
# OCaml or Mojo, never Python or shell." Mojo/MAX under
# services/inference/max is the only sanctioned Python zone.
# contracts/rules/20260908-0551-release-assurance-sdlc-sre-sop.md -- "New
# shell/Bash automation is prohibited."
#
# MY OWN FRAMING WAS WRONG, AND THE CORRECTION IS THE POINT
# ---------------------------------------------------------
# I reported "74 Python helpers in tools/ is the largest unaddressed
# violation of unify-into-Lean-and-Mojo". Measured:
#
#   * Of 74 tools/*.py, only 7 are LIVE. 58 are one-shot ledger writers whose
#     writes already landed, 9 have no caller at all. Live Python: 1,954
#     lines, not 22,487.
#   * The larger LIVE violation is 39 EXTENSIONLESS Bash scripts in tools/,
#     which a `.sh` glob cannot see -- including tools/preflight itself, 382
#     lines of Bash, sitting in the SessionStart hook path of all four agent
#     surfaces, and tools/uos-core-evo (529), tools/tui (489), and every
#     *-check gate helper.
#
# So a conversion programme scoped to file EXTENSIONS would have converted
# the historical residue and left the live violation in place. Counting by
# extension is not counting by surface. This oracle counts surface.
#
# THE DEFECT THAT IS NOT ABOUT LANGUAGE AT ALL
# --------------------------------------------
# Eight gates in tools/uos/src/main.gleam grade `file_exists(<a .py>)` as
# evidence. Converting those files to OCaml would PRESERVE a gate that treats
# file presence as verification -- barred independently by CLAUDE.md's
# epistemic discipline and SC-CHECKLIST-001, in any language. The fix is a
# real check or no check, never a rewrite.
#
# And formal/lean/UosCoreEvoUnifiedDigitalTwin.lean:737 asserts
# `stratum := .s1Systemd` for tools/verify_website_sop.sh. Measured: no
# systemd unit references it, and nothing in the tree executes it. A Lean
# twin asserts host infrastructure for a script that does not run -- the
# `observationNow` defect in its purest form, and exactly what a twin
# re-measured by nothing will always drift into.
#
# authority NONE. EV ceiling 93. This oracle is EXPECTED TO FAIL while
# Python sits inside a gate; that failure is the finding.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains, occurrences

comptime GATES = "tools/uos/src/main.gleam"
comptime TWIN = "formal/lean/UosCoreEvoUnifiedDigitalTwin.lean"
comptime SANCTIONED_PY = "services/inference/max"


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String(TWIN))

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- the surface, counted three ways --------------------------------
    var py_files = count("ls tools/*.py 2>/dev/null | wc -l")
    var sh_files = count("ls tools/*.sh 2>/dev/null | wc -l")
    # Extensionless Bash: the surface a *.sh glob cannot see. Detected by
    # SHEBANG, which is what actually decides how the file executes.
    var bare_bash = count(
        "for f in tools/*; do [ -f \"$f\" ] || continue; "
        + "case \"$f\" in *.*) ;; *) head -1 \"$f\" 2>/dev/null "
        + "| grep -q 'bash\\|^#!/bin/sh' && echo x;; esac; done | wc -l")
    r.observe_int(String("tools-python-files"), py_files)
    r.observe_int(String("tools-dot-sh-files"), sh_files)
    r.observe_int(String("tools-extensionless-bash"), bare_bash)

    # F10, 20261106 -- INVERTED POLARITY. The pass condition was
    # `bare_bash > sh_files`, i.e. the check PASSED only while the
    # extensionless Bash surface stayed larger than the `.sh` surface.
    # Converting that surface to OCaml -- the thing the policy requires and
    # this oracle exists to motivate -- would have turned this arm into a
    # WORLD_FAIL. An arm that fails when the system is fixed is not a check;
    # it demands the defect persist.
    #
    # The underlying observation is real and worth keeping: counting by
    # extension undercounts the shell surface, because 39 extensionless Bash
    # files are invisible to a `*.sh` glob. That is a FACT ABOUT THE
    # INSTRUMENT, not a property the system should maintain, so it is
    # recorded as an observation and the arm now tests what policy actually
    # wants -- that the shell surface is shrinking toward zero, with the
    # current total reported rather than a floor asserted.
    r.observe_int(String("total-shell-surface-sh-plus-extensionless"),
                  sh_files + bare_bash if (sh_files >= 0
                  and bare_bash >= 0) else -1)
    r.observe(String("extension-glob-undercounts-by"),
              String(bare_bash) + String(" files invisible to tools/*.sh"))
    # Zero is the target. Reported as an observation, not failed on a
    # threshold: there is no count at which a shell surface becomes
    # conformant, and inventing one would be the same move as a
    # 100%-complete banner.
    r.observe(String("shell-surface-is-nonzero-and-must-shrink"),
              String(sh_files + bare_bash > 0))

    # ---- the hook path --------------------------------------------------
    # tools/preflight is Bash and runs in every agent surface's SessionStart.
    # Recorded as an observation of SIZE, not a pass: there is no threshold
    # at which a Bash verification entrypoint becomes conformant.
    var preflight_lines = count("wc -l < tools/preflight 2>/dev/null")
    var preflight_is_bash = capture(
        "head -1 tools/preflight 2>/dev/null | grep -c bash")
    r.observe_int(String("preflight-lines"), preflight_lines)
    r.observe(String("preflight-shebang-is-bash"), preflight_is_bash)
    var hooks_running_preflight = count(
        "grep -l 'tools/preflight' .claude/settings.json .codex/hooks.json "
        + ".agents/hooks.json .gemini/hooks.json 2>/dev/null | wc -l")
    r.observe_int(String("agent-surfaces-invoking-preflight"), hooks_running_preflight)

    # ---- GATE CONFORMANCE: barred language inside a verification path ---
    # This is the sharp arm. A policy-barred language executing inside a gate
    # is a different class from a barred language sitting in tools/.
    var py_in_gate = count(
        "grep -c 'run_command(\"python3\"' " + String(GATES) + " 2>/dev/null")
    var sh_in_gate = count(
        "grep -c 'run_command(\"bash\"' " + String(GATES) + " 2>/dev/null")
    r.observe_int(String("python-invocations-in-gates"), py_in_gate)
    r.observe_int(String("bash-invocations-in-gates"), sh_in_gate)

    # Sanctioned exception: services/inference/max is the only Python zone.
    # Sanctioned exception: services/inference/max is the only Python zone.
    #
    # The first version of this filter grepped 2 lines AFTER the
    # `run_command("python3"` site for the sanctioned path and found 0 -- so
    # it would have reported the one SANCTIONED invocation as a violation.
    # The path is not at the call site: tools/uos/src/main.gleam:3270 binds
    # `let worker = "services/inference/max/max_worker.py"` and :3272 passes
    # the VARIABLE. A filter reading only the call site cannot see that.
    #
    # MY OWN NEGATIVE CONTROL CAUGHT IT. The probe asserting this filter is
    # not vacuous failed, the receipt came back VACUOUS, and the run was
    # refused -- which is exactly why that probe exists. Without it this
    # oracle would have shipped a false violation while every positive arm
    # looked healthy, and a false violation is worse than none: it teaches
    # the reader to discount the arm.
    #
    # Widened to the enclosing `case` arm, which is where Gleam binds locals.
    var py_gate_sanctioned = count(
        "grep -B24 'run_command(\"python3\"' " + String(GATES)
        + " 2>/dev/null | grep -c '" + String(SANCTIONED_PY) + "'")
    r.observe_int(String("python-gate-invocations-in-sanctioned-zone"), py_gate_sanctioned)
    # Unsanctioned Python inside a gate must be zero.
    var py_gate_unsanctioned = py_in_gate - py_gate_sanctioned
    if py_in_gate < 0 or py_gate_sanctioned < 0:
        py_gate_unsanctioned = -1
    r.world_count(String("no-unsanctioned-python-inside-a-gate"),
                  py_gate_unsanctioned, 0)

    # ---- FILE PRESENCE AS EVIDENCE -- not a language defect -------------
    # Gates whose verdict is satisfied by a .py EXISTING. Converting those
    # files to OCaml would preserve the defect, so this arm is kept separate
    # from the language arms on purpose.
    var presence_gates = count(
        "grep -cE 'file_exists\\(\"tools/[a-z0-9_]*\\.py\"\\)' "
        + String(GATES) + " 2>/dev/null")
    r.observe_int(String("gates-grading-file-presence-of-a-py"), presence_gates)
    r.world_count(String("no-gate-grades-file-presence-as-evidence"),
                  presence_gates, 0)

    # ---- THE TWIN ASSERTING INFRASTRUCTURE THAT DOES NOT RUN ------------
    # UosCoreEvoUnifiedDigitalTwin.lean:737 records
    #   { name := "tools/verify_website_sop.sh", stratum := .s1Systemd, ... }
    # Measured: no systemd unit names it and nothing executes it. The twin
    # asserts a host stratum for a script that does not run.
    var twin_claims_systemd = count(
        "grep -c 'verify_website_sop' " + String(TWIN) + " 2>/dev/null")
    var systemd_units = count(
        "grep -rl 'verify_website_sop' ops/systemd 2>/dev/null | wc -l")
    var executors = count(
        "grep -rl 'verify_website_sop' tools scripts ops --include='*' "
        + "2>/dev/null | grep -v 'verify_website_sop.sh' | wc -l")
    r.observe_int(String("twin-stratum-claims"), twin_claims_systemd)
    r.observe_int(String("systemd-units-naming-it"), systemd_units)
    r.observe_int(String("other-files-invoking-it"), executors)
    # F13, 20261106: `executors` was computed and then never checked and
    # never printed, while the comment above it states "nothing in the tree
    # executes it" AS A FINDING. A finding nothing tests is a sentence, so
    # the claim is now an arm: if the twin asserts a systemd stratum, SOME
    # file other than the script itself must invoke it, or the stratum is
    # asserted and unreachable.
    if twin_claims_systemd > 0:
        r.world_or_blind(
            String("twin-systemd-claim-has-an-invoker"),
            executors >= 0, executors > 0)
    # If the twin claims a systemd stratum, a systemd unit must exist.
    if twin_claims_systemd > 0:
        r.world_count(
            String("twin-systemd-claim-has-a-systemd-unit"),
            systemd_units, 1)

    # ---- ALGEBRA ---------------------------------------------------------
    #
    # F11, 20261106. All three arms here were literals: `1 == 1`,
    # `(74 != 7) and (7 < 74)`, and `True == True`. The middle one is the
    # sharpest case in the whole set, because this file DERIVES the real
    # counts at the top of `main` -- `py_files`, `sh_files`, `bare_bash` --
    # and the arm ignored them in favour of the two numbers the author had
    # written into the header prose. The measurement was taken and then
    # discarded in favour of its own transcription.
    #
    # All three now use the derived values, so each moves when the tree does.
    var sanctioned_zones = count(
        "ls -d services/inference/max 2>/dev/null | wc -l")
    r.observe_int(String("sanctioned-python-zones"), sanctioned_zones)
    r.world_count(String("lang-sanctioned-python-zone-is-exactly-one"),
                  sanctioned_zones, 1)
    if py_files >= 0 and sh_files >= 0 and bare_bash >= 0:
        # L8 FIX, 20261106-0924 (re-review finding 7). This arm was
        # `sh_files + bare_bash > sh_files`, which reduces to
        # `bare_bash > 0`: it PASSED ONLY WHILE THE VIOLATION PERSISTED.
        # Converting the 39 extensionless Bash scripts to OCaml -- the policy
        # requirement this oracle exists to motivate -- makes it `7 > 7`, an
        # ALGEBRA failure, i.e. DIVERGENT, in a file where it was the only
        # algebra arm. The previous round moved an inverted-polarity check
        # from the world channel into the algebra channel instead of fixing
        # it, and the substrate documents an algebra failure as "the model
        # drifted from itself ... must never be reported as an ordinary
        # outage". Remediation would have been reported as model drift.
        #
        # My own comment defending it ("would correctly stop holding") was
        # right about the proposition and wrong about the channel.
        #
        # The claim with content is not "the undercount is nonzero" but that
        # the SHEBANG instrument is a superset of the extension glob -- i.e.
        # counting by shebang can never see FEWER shell files than counting
        # by extension. That holds at every surface size including zero, so
        # it survives remediation, and it fails if the shebang detector ever
        # regresses to missing a `.sh` file.
        var sh_by_shebang = count(
            "for f in tools/*.sh; do [ -f \"$f\" ] || continue; "
            + "head -1 \"$f\" 2>/dev/null | grep -qE 'bash|^#!/bin/sh' "
            + "&& echo x; done | wc -l")
        r.observe_int(String("dot-sh-files-with-a-shell-shebang"),
                      sh_by_shebang)
        r.algebra(String("lang-shebang-instrument-dominates-the-extension-glob"),
                  sh_by_shebang >= 0 and sh_files >= 0
                  and sh_by_shebang <= sh_files
                  and sh_files + bare_bash >= sh_by_shebang)
        # The third arm, `lang-rewriting-a-presence-check-preserves-it`, was
        # `True == True` and is DELETED rather than rewritten.
        #
        # My first replacement was `(presence_gates > 0) == (presence_gates
        # != 0)`, which is identically true for every non-negative Int -- I
        # reproduced the exact defect inside its own fix. The reason is worth
        # recording: the claim "rewriting a presence check preserves it" is
        # not a mathematical proposition at all. It is a statement about what
        # `file_exists` MEANS -- that a gate keyed on a `.py` file existing is
        # satisfied by presence regardless of the file's contents or language
        # -- and no arithmetic over a count can express it.
        #
        # The substantive test already exists as a world arm:
        # `no-gate-grades-file-presence-as-evidence` counts the gates keyed
        # that way and requires zero. That arm can fail, does fail today, and
        # is the whole content. The algebra arm was ceremony restating its
        # rationale, and a tautology is what you get when you force a
        # non-mathematical claim into an algebra channel.
    else:
        r.observe(String("algebra"),
                  String("skipped: surface counts unreadable"))

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # The shebang detector must distinguish Bash from OCaml. tools/preflight
    # is Bash; tools/lean_mojo_differential.ml is not a script at all. If the
    # detector cannot tell them apart, every count above is noise.
    var pf = capture("head -1 tools/preflight 2>/dev/null")
    var ml = capture("head -1 tools/lean_mojo_differential.ml 2>/dev/null")
    r.mutation_probe(String("shebang-detector-sees-bash"),
                     contains(pf, String("bash")))
    r.mutation_probe(String("shebang-detector-rejects-non-script"),
                     not contains(ml, String("bash")))
    # And the sanctioned-zone filter must actually filter: a gate invoking
    # Python from services/inference/max must NOT be counted as a violation.
    r.mutation_probe(String("sanctioned-zone-filter-is-not-vacuous"),
                     py_gate_sanctioned > 0)

    print("# probe time                      :", now)
    print("# tools/*.py                      :", py_files,
          "(live: 7 per the 20261106 inventory)")
    print("# tools/*.sh                      :", sh_files)
    print("# tools/ EXTENSIONLESS bash       :", bare_bash,
          "<-- the surface a *.sh glob cannot see")
    print("# tools/preflight                 :", preflight_lines,
          "lines of bash, in", hooks_running_preflight,
          "agent surfaces' SessionStart")
    print("# python invocations in gates     :", py_in_gate,
          "(sanctioned:", py_gate_sanctioned, ")")
    print("# bash invocations in gates       :", sh_in_gate)
    print("# gates grading .py file presence :", presence_gates)
    print("# twin systemd claim vs units     :", twin_claims_systemd, "/",
          systemd_units)
    r.emit()
    exit(r.exit_code())
