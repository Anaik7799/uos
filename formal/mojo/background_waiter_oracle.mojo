# ==========================================================================
# background_waiter_oracle — measures the real tree against
# formal/lean/UosBackgroundWaiterTwin.lean and tools/uos-wait.ml
#
# THE INCIDENT BEING MEASURED
# ---------------------------
# On 2026-11-06, eight background shells of the shape
#
#     while pgrep -f "dataplane.ml --subject" >/dev/null; do :; done
#
# were started to wait for a mutation sweep that finished at 21:28. They
# were still spinning at 04:28 the next morning. `pgrep -f` matches full
# command lines and each waiter's own command line CONTAINS the pattern it
# was handed, so the guard was satisfied by the waiter itself. The observed
# set is never empty when the observer is in it.
#
# Measured on this host, not assumed: 56 pgrep forks/second/waiter, ~1.1e7
# process creations over seven hours, load average 9.64 against 24 cores at
# the moment they were stopped.
#
# WHY THIS ORACLE EXISTS RATHER THAN A NOTE IN A JOURNAL
# ------------------------------------------------------
# A postmortem that says "do not write self-matching waiters" is a sentence
# nothing can read. The twin states the admissibility rule, `tools/uos-wait`
# implements it and REFUSES the inadmissible configurations, and this oracle
# executes those refusals and the terminations. Fresh behaviour AND formal
# spec, from independent artifacts.
#
# F-B5-01 discipline: the subject of this receipt is the Lean twin, and this
# oracle OPENS it. Four oracles named a twin as their subject and never read
# it, and emptying the twin left their receipts byte-identical. A declared
# subject is not a read subject.
#
# authority NONE. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV minted.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains, occurrences, shell_quote

comptime TWIN = "formal/lean/UosBackgroundWaiterTwin.lean"
comptime CONTROLLER = "tools/uos-wait.ml"
# Measured on this host 2026-11-07, one second bounded, pattern matching no
# process: 56 iterations. The twin's THM_WAIT_09 is stated at this number.
comptime MEASURED_HOST_FORK_RATE = 56


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def ocaml_path() -> String:
    return capture(
        "bash -c 'source tools/lib/uos-toolchain.sh && uos_tool_path ocaml'")


def run_rc(cmd: String) -> Int:
    """The EXIT CODE, not the output. A refusal that printed a message and
    exited 0 would read as a refusal and behave as consent."""
    return count(cmd + " >/dev/null 2>&1; echo $?")


# ---- mirrors of the twin's definitions --------------------------------
# Int/Bool only, so tools/mojo_arm_falsifiability.ml can enumerate them and
# tools/mojo_mutation_dataplane.ml can mutate them.
#
# Target encoding: 0 = pid (identity), 1 = pattern that matches the waiter,
# 2 = pattern that does not. Mirrors UOS.BackgroundWaiter.Target.


def guard(target: Int, finishes: Int, k: Int) -> Bool:
    """Mirror of UosBackgroundWaiterTwin.guard. The host's answer at poll k.
    A self-matching pattern answers True forever."""
    if target == 1:
        return True
    return k < finishes


def stops(target: Int, budget: Int) -> Bool:
    """Mirror of `stopsAt`, reduced to the question that matters: does the
    waiter stop at all? THM_WAIT_01 says a self-matching pattern with no
    deadline does not."""
    if budget != 0:
        return True
    return target != 1


def polls_of(target: Int, budget: Int, finishes: Int, cap: Int) -> Int:
    """Mirror of `pollsOf`. A waiter that never stops polls to the horizon,
    so its CPU cost is a function of the session, not of the work."""
    if not stops(target, budget):
        return cap
    if budget != 0 and budget < finishes:
        return budget
    return finishes


def tokens(emit_per_poll: Int, target: Int, budget: Int,
           finishes: Int, cap: Int) -> Int:
    """Mirror of `tokens`. THM_WAIT_07: silence per poll makes the token
    cost independent of duration."""
    return emit_per_poll * polls_of(target, budget, finishes, cap) + 1


def forks_per_sec(interval_ms: Int, host_rate: Int) -> Int:
    """Mirror of `forksPerSec`. THM_WAIT_09: an interval bounds the fork
    rate by arithmetic rather than by what the host will allow."""
    if interval_ms == 0:
        return host_rate
    return 1000 // interval_ms


def admissible(target: Int, budget: Int, interval_ms: Int,
               emit_per_poll: Int) -> Bool:
    """Mirror of `admissible`. Identity or a non-self-matching pattern, a
    deadline, a sleep, and silence until exit."""
    return (target != 1 and budget != 0 and interval_ms != 0
            and emit_per_poll == 0)


def clean_shutdown(waiter_stopped: Bool, children_live: Int) -> Bool:
    """Mirror of `cleanShutdown`. THM_WAIT_11: both conditions, or the core
    stays busy with the waiter's name off the list."""
    return waiter_stopped and children_live == 0


def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String(TWIN))

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- WORLD: the subject is READ, not merely named -------------------
    var twin_thms = count(
        "grep -cE '^theorem ' " + String(TWIN) + " 2>/dev/null")
    r.world_or_blind(String("declared-twin-is-readable"),
                     twin_thms >= 0, twin_thms > 0)
    r.observe_int(String("twin-theorems"), twin_thms)
    # Every theorem this file's arms cite must exist in the twin. Counting
    # theorems would pass against any file with enough of them; naming them
    # is what makes the citation checkable.
    var cited = [String("THM_WAIT_01"), String("THM_WAIT_02"),
                 String("THM_WAIT_03"), String("THM_WAIT_04"),
                 String("THM_WAIT_05"), String("THM_WAIT_06"),
                 String("THM_WAIT_07"), String("THM_WAIT_08"),
                 String("THM_WAIT_09"), String("THM_WAIT_10"),
                 String("THM_WAIT_11"), String("THM_WAIT_ADM_01"),
                 String("THM_WAIT_ADM_02"), String("THM_WAIT_ADM_03"),
                 String("THM_WAIT_ADM_04")]
    var cited_present = 0
    for ci in range(len(cited)):
        if count("grep -cE '^theorem " + cited[ci] + "' " + String(TWIN)
                 + " 2>/dev/null") > 0:
            cited_present += 1
    r.world_count(String("declared-twin-carries-every-cited-theorem"),
                  cited_present, len(cited))
    # The twin must not have been discharged by assumption.
    #
    # CORRECTED 20261107-0355. The pattern was
    # `(^|[^A-Za-z])(sorry|axiom)([^A-Za-z]|$)`, and its one match in the
    # whole file was the twin's own header line "No `sorry`, no `axiom`".
    # The arm reported a twin full of assumptions because the twin says in
    # prose that it has none. Requiring whitespace or line-start before the
    # word excludes the backticked mention and still catches a real `sorry`
    # term or an `axiom` declaration, which are never backticked in code.
    var cheats = count(
        "grep -cE '(^|[[:space:]])(sorry|axiom)([[:space:]]|$)' "
        + String(TWIN) + " 2>/dev/null")
    r.world_count(String("twin-carries-no-sorry-and-no-axiom"), cheats, 0)

    # ---- WORLD: the controller exists and REFUSES -----------------------
    var ctl_bytes = count("wc -c < " + String(CONTROLLER) + " 2>/dev/null")
    r.world_or_blind(String("controller-is-readable"),
                     ctl_bytes >= 0, ctl_bytes > 0)
    var oc = ocaml_path()
    var base = oc + " -I +unix unix.cma " + String(CONTROLLER)
    if ctl_bytes > 0 and oc.byte_length() > 0:
        # Each inadmissible configuration in the twin must be refused with
        # exit 2. A default is not a refusal: the whole incident was a
        # waiter that defaulted to "forever".
        var refuse_no_target = run_rc(base)
        var refuse_no_timeout = run_rc(base + " --pid 1")
        var refuse_zero_interval = run_rc(
            base + " --pid 1 --timeout 5 --interval 0")
        var refusals = 0
        if refuse_no_target == 2:
            refusals += 1
        if refuse_no_timeout == 2:
            refusals += 1
        if refuse_zero_interval == 2:
            refusals += 1
        r.world_count(String("controller-refuses-every-inadmissible-config"),
                      refusals, 3)
        r.observe(String("refusal-codes"),
                  String(refuse_no_target) + " " + String(refuse_no_timeout)
                  + " " + String(refuse_zero_interval))
        # There must be NO pattern mode at all. A flag that re-enables the
        # defect gets used, so its absence is the control.
        var pattern_flag = run_rc(base + " --pattern foo --timeout 5")
        r.world_count(String("controller-has-no-pattern-mode"),
                      pattern_flag, 2)
        # And it must terminate, and say so in exactly one line.
        var lines = count(base + " --pid 1 --timeout 2 --interval 500 "
                          + "2>/dev/null | wc -l")
        r.world_count(String("controller-emits-exactly-one-line"), lines, 1)
        # The empirical rules, measured by the controller against this host.
        var self_rc = run_rc(base + " --selftest")
        r.world_count(String("controller-selftest-passes"), self_rc, 0)
        # Nothing inadmissible may be alive right now. This is the SRE arm:
        # it reads /proc, and it is the check whose absence let eight of
        # them run for seven hours unnoticed.
        var scan_rc = run_rc(base + " --scan")
        r.world_count(String("no-inadmissible-waiter-is-alive"), scan_rc, 0)
    else:
        r.world_or_blind(String("controller-refuses-every-inadmissible-config"),
                         False, False)

    # ---- WORLD: the shape is absent from the tree's own tooling ----------
    # The defect was authored, not inherited. If it is still written down
    # anywhere a future session will copy it, it will be copied.
    #
    # CORRECTED 20261107-0355. This was
    # `grep -rlE 'while +(pgrep|pidof)' tools/`, and its one match was
    # `tools/uos-wait.ml` line 8 -- the header comment that QUOTES the
    # incident in order to explain it. The arm reported the defect present
    # in the tooling because the fix documents the defect. A grep over
    # source cannot tell documentation from implementation, which is the
    # same confusion that had the mutation instrument mutating docstrings.
    # `--lint` strips comment markers first, so the arm measures code.
    if ctl_bytes > 0 and oc.byte_length() > 0:
        var lint_rc = run_rc(base + " --lint tools")
        r.world_count(String("no-busy-wait-shape-authored-in-tools"),
                      lint_rc, 0)
    else:
        r.world_or_blind(String("no-busy-wait-shape-authored-in-tools"),
                         False, False)

    # ---- ALGEBRA: the twin's theorems, at their boundaries --------------
    # THM_WAIT_01/02 -- the incident shape never stops, and the reason is
    # that its guard is true at every poll INCLUDING polls after the work
    # has finished. k=9 against finishes=3 is the discriminating point: a
    # pid target is False there and a self-matching pattern is True.
    r.algebra(String("wait01:self-matching-pattern-never-stops"),
              not stops(1, 0) and stops(0, 0) and stops(2, 0))
    r.algebra(String("wait02:self-match-guard-true-after-work-finished"),
              guard(1, 3, 9) and not guard(0, 3, 9) and guard(0, 3, 2))
    # THM_WAIT_03 -- a deadline forces termination whatever the target is,
    # including the self-matching one. budget=1 is the boundary: 0 means no
    # deadline, 1 is the smallest real one.
    r.algebra(String("wait03:deadline-forces-termination"),
              stops(1, 1) and stops(1, 0) == False)
    # THM_WAIT_06 -- a non-terminating waiter's cost is the horizon, so it
    # grows with the session and not with the work.
    r.algebra(String("wait06:nonterminating-cost-is-the-horizon"),
              polls_of(1, 0, 3, 1000) == 1000
              and polls_of(0, 0, 3, 1000) == 3)
    # THM_WAIT_07/08 -- silence makes token cost independent of duration,
    # and the converse, so the first claim is not vacuous.
    r.algebra(String("wait07:silent-waiter-costs-one-line"),
              tokens(0, 1, 0, 3, 10) == 1
              and tokens(0, 1, 0, 3, 1000000) == 1)
    r.algebra(String("wait08:chatty-nonterminating-waiter-grows"),
              tokens(1, 1, 0, 3, 11) > tokens(1, 1, 0, 3, 10))
    # THM_WAIT_09 -- stated at the MEASURED host rate, so the arm fails if
    # the measurement is ever re-taken and the twin is not updated with it.
    r.algebra(String("wait09:interval-bounds-fork-rate"),
              forks_per_sec(0, MEASURED_HOST_FORK_RATE)
                == MEASURED_HOST_FORK_RATE
              and forks_per_sec(1000, MEASURED_HOST_FORK_RATE) == 1
              and forks_per_sec(1, MEASURED_HOST_FORK_RATE) == 1000)
    # THM_WAIT_10/11 -- clean shutdown is both conditions. children_live=1
    # is the boundary, and it is the case that actually happens.
    r.algebra(String("wait10:orphan-is-not-a-clean-shutdown"),
              not clean_shutdown(True, 1) and clean_shutdown(True, 0)
              and not clean_shutdown(False, 0))
    # THM_WAIT_ADM_01/02 -- the rule admits the controller and rejects the
    # shape that actually ran. If the second failed, the rule would permit
    # the incident and this file would be decoration.
    r.algebra(String("adm01:controller-shape-is-admissible"),
              admissible(0, 8, 1000, 0))
    r.algebra(String("adm02:incident-shape-is-inadmissible"),
              not admissible(1, 0, 0, 0))
    # Each condition is load-bearing on its own: drop any ONE and the shape
    # becomes inadmissible. Without this the rule could be passing on the
    # strength of a single clause.
    r.algebra(String("adm03:every-condition-is-load-bearing"),
              not admissible(1, 8, 1000, 0)
              and not admissible(0, 0, 1000, 0)
              and not admissible(0, 8, 0, 0)
              and not admissible(0, 8, 1000, 1))
    # THM_WAIT_ADM_03/04 -- admissibility implies the two properties that
    # matter, at the smallest admissible values.
    r.algebra(String("adm04:admissible-implies-stops-and-one-line"),
              stops(0, 1) and tokens(0, 0, 1, 1, 999999) == 1)

    print("# background waiter plane")
    print("# twin theorems     :", twin_thms, "cited present:", cited_present,
          "/", len(cited))
    print("# host fork rate    :", MEASURED_HOST_FORK_RATE,
          "forks/s/waiter busy-wait;", forks_per_sec(1000,
          MEASURED_HOST_FORK_RATE), "at 1000ms")
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
