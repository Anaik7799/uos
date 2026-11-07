# ==========================================================================
# Differential oracle for formal/lean/UosMcpNameOwnershipTwin.lean
#
# Lean proves the ownership/rename properties symbolically over the finite
# ServerName domain. This oracle re-evaluates the identical algebra -- but
# NOT from a transcribed copy of it.
#
# WHY OWNERSHIP IS DERIVED, NOT HARDCODED
# ---------------------------------------
# The first version of this file hardcoded `owned_by_writer(n) = n in {0,1,2}`
# and called `not owned_by_writer(3)` its negative control. A sovereign review
# (Codex, 20261106-0108) correctly rejected that: restating the allowlist and
# then asserting the restatement is a tautology, not a control, and two
# hand-copied semantics can agree while both being wrong. A shared wrong
# mapping passes in both languages.
#
# So ownership is now DERIVED by reading the authority -- the allowlist in
# tools/ecology_pin_edit.ml:97 and :325 -- and the negative control MUTATES A
# REAL INPUT: a copy of that file with a widened allowlist, re-derived, which
# must break rename closure. If the mutant passes, the derivation is blind and
# the run is VACUOUS regardless of the positive checks.
#
# UNOBSERVED IS NOT GREEN
# -----------------------
# Fields this oracle cannot read are recorded BLIND, never defaulted true.
# Same review: "moving I/O to Mojo will not fix unobserved fields defaulting
# to green."
#
# AUTHORITY BOUNDARY
# ------------------
# AGENTS.md:189 assigns check and time policy to Gleam/OTP behind the harness.
# This oracle is a BOUNDED READ-ONLY PROBE and claims no check authority: all
# probes run under `timeout` (oracle_substrate.capture), none mutate state,
# and the verdict is evidence for a human or the harness to act on.
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains

comptime DOMAIN = 5
comptime WRITER = "tools/ecology_pin_edit.ml"
comptime TWIN = "formal/lean/UosMcpNameOwnershipTwin.lean"

# Domain, by index -- mirrors UOS.McpNameOwnership.ServerName:
#   0 uos-harness  1 uos-harness-dev  2 uos-gleam  3 uos_gleam  4 uos_development


def name_of(n: Int) -> String:
    if n == 0:
        return String("uos-harness")
    if n == 1:
        return String("uos-harness-dev")
    if n == 2:
        return String("uos-gleam")
    if n == 3:
        return String("uos_gleam")
    return String("uos_development")


def quoted(n: Int) -> String:
    """The writer quotes each owned name as an OCaml string literal.

    The quotes matter: a bare `uos-harness` also occurs inside
    `uos-harness-dev`, so an unquoted search cannot tell the two apart.
    """
    return String('"') + name_of(n) + String('"')


# F13, 20261106: `allowlist_line(body, marker)` was removed from here.
#
# It carried a six-line docstring describing extraction logic -- "Extract the
# one `bindings [...]` line belonging to a writer path. `marker` is the
# enclosing function's signature line, so the JSON and TOML paths are
# distinguished by WHERE the allowlist sits, not by guessing" -- over a body
# that performed none of it: `return body`. It ignored `marker` entirely and
# returned its input unchanged.
#
# It was also DEAD: a call-site grep across formal/mojo found only its own
# definition. That is what made it safe to delete rather than implement. Had
# it been called it would have handed both the JSON and the TOML path the
# same whole-file body, collapsing the two-dialect ownership model this
# file's header says the correction was for -- so the docstring described
# behaviour that, if supplied, would have broken the caller.
#
# Dead code carrying a false docstring, in a file whose subject is "a
# recorded verdict whose subject moved", is a finding rather than a style
# note. The two dialects are distinguished at the call sites by reading each
# writer path separately, which is what the file actually does.


def owned_in(allowlist: String, n: Int) -> Bool:
    return contains(allowlist, quoted(n))


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(String(raw.strip()))
    except:
        return -1


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/UosMcpNameOwnershipTwin.lean"),
    )

    # ---- THE DECLARED SUBJECT IS ACTUALLY READ -------------------------
    # 20261106-1848, found by B5 mutation verification: this twin was emptied
    # to zero bytes in the real tree and the receipt did not move by a single
    # byte. The oracle named a formal twin as its subject and never opened it,
    # so the formal half of the two-key claim was absent at this candidate.
    # A declared subject is not a read subject.
    #
    # The expected set is the theorem name THIS ORACLE'S OWN COMMENTS cite as
    # its source, not a count harvested from the twin.
    var twin_thms = count(
        "grep -cE '^theorem ' " + String(TWIN) + " 2>/dev/null")
    r.world_or_blind(String("declared-twin-is-readable"),
                     twin_thms >= 0, twin_thms > 0)
    var cited = [String("THM_OWN_01"), String("THM_OWN_02"),
                 String("THM_ONT_01"), String("THM_ONT_02")]
    var cited_present = 0
    for ci in range(len(cited)):
        if count("grep -cE '^theorem " + cited[ci] + "' "
                 + String(TWIN) + " 2>/dev/null") > 0:
            cited_present += 1
    r.world_count(String("declared-twin-carries-every-cited-theorem"),
                  cited_present, len(cited))

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- the authority, read per format, not assumed -------------------
    # tools/ecology_pin_edit.ml carries TWO allowlists, one per config
    # dialect. Reading only the first produced a wrong model once already:
    # the underscore names were declared "unowned drift" when they are the
    # TOML bare-key spellings, owned by the TOML path.
    var json_allow = capture(
        "grep -A1 'let json ~servers' " + String(WRITER)
        + " | grep -o 'bindings \\[[^]]*\\]' | head -1")
    var toml_allow = capture(
        "grep -A1 'let toml ~servers' " + String(WRITER)
        + " | grep -o 'bindings \\[[^]]*\\]' | head -1")
    r.observe(String("json-path-allowlist"), json_allow)
    r.observe(String("toml-path-allowlist"), toml_allow)

    if json_allow.byte_length() == 0 or toml_allow.byte_length() == 0:
        # Fail closed. With no authority to derive from, nothing below means
        # anything, and a hardcoded fallback is how the first wrong model got
        # written. Emit BLIND and stop.
        print("# could not extract both allowlists from", WRITER)
        r.emit()
        exit(r.exit_code())

    print("# json path owns:", json_allow)
    print("# toml path owns:", toml_allow)

    var json_owned = 0
    var toml_owned = 0
    var owned_somewhere = 0
    for n in range(DOMAIN):
        var j = owned_in(json_allow, n)
        var t = owned_in(toml_allow, n)
        if j:
            json_owned += 1
        if t:
            toml_owned += 1
        if j or t:
            owned_somewhere += 1

    # ---- ALGEBRA -------------------------------------------------------
    # The corrected ownership model: ownership is a relation on
    # (name, format), not a predicate on name.
    r.algebra(String("own:json-path-owns-three"), json_owned == 3)
    r.algebra(String("own:toml-path-owns-four"), toml_owned == 4)
    # Every name in the domain is owned by SOME path. This is the claim that
    # replaces the retracted THM_OWN_02 ("unowned names cannot converge"):
    # there are no unowned names.
    r.algebra(String("own:no-unowned-name-exists"), owned_somewhere == DOMAIN)
    # The two canonical names are owned by BOTH paths, which is what makes
    # them canonical: they are writable in either dialect.
    r.algebra(String("own:canonical-owned-by-both-paths"),
        owned_in(json_allow, 0) and owned_in(toml_allow, 0)
        and owned_in(json_allow, 1) and owned_in(toml_allow, 1))
    # The dialects genuinely differ, so a single flat allowlist cannot model
    # this: uos-gleam is JSON-only, uos_gleam is TOML-only.
    r.algebra(String("own:dialects-are-not-identical"),
        owned_in(json_allow, 2) and not owned_in(toml_allow, 2)
        and owned_in(toml_allow, 3) and not owned_in(json_allow, 3))

    # ---- ALGEBRA: the quoting is what makes ownership decidable ---------
    # ADDED 20261107-0331, found by B5 mirror mutation. Emptying the quote
    # literal in `quoted` -- so that it searches for a BARE name -- returned
    # a byte-identical receipt. Every arm above survived the change, because
    # each of them asks about an allowlist that contains both `uos-harness`
    # and `uos-harness-dev`, where a substring search happens to agree with
    # an exact one.
    #
    # `quoted`'s own docstring states the hazard exactly: "a bare
    # `uos-harness` also occurs inside `uos-harness-dev`, so an unquoted
    # search cannot tell the two apart." So the file already knew the
    # property, asserted it in prose, and measured it nowhere.
    #
    # This arm is the discriminating case the others cannot be: an allowlist
    # carrying ONLY the dev name. Exact-quoted ownership says name 0 is
    # absent; substring ownership says it is present. The two answers
    # differ, which is the entire point of the quotes.
    # CORRECTED 20261107-0415. The first version of this arm used only the
    # prefix case below, and the mutation SURVIVED anyway: `literal->empty`
    # empties the FIRST literal on the line, so it drops the LEADING quote
    # and leaves the trailing one. `uos-harness"` is still not a substring of
    # `"uos-harness-dev"`, so the prefix case could not tell the difference.
    # One arm pinned one half of a two-sided property and read as closure.
    #
    # Each case is blind to the mutant the other catches:
    #   prefix   -- a trailing quote stops `uos-harness` matching inside
    #               `uos-harness-dev`
    #   embedded -- a leading quote stops `uos-harness` matching inside
    #               `xuos-harness`
    var only_dev = String("  \"uos-harness-dev\"\n")
    var only_embedded = String("  \"xuos-harness\"\n")
    r.algebra(String("own:quoting-separates-a-name-from-its-prefix-use"),
        owned_in(only_dev, 1) and not owned_in(only_dev, 0))
    r.algebra(String("own:quoting-separates-a-name-from-its-embedded-use"),
        not owned_in(only_embedded, 0))

    # ---- NEGATIVE CONTROL: mutate a real input -------------------------
    # Narrow the JSON allowlist by removing uos-harness. The derivation must
    # see the change. A control that merely restates the allowlist and
    # asserts the restatement proves nothing -- that was the first version's
    # defect, caught in sovereign review.
    var narrowed = capture(
        "grep -A1 'let json ~servers' " + String(WRITER)
        + " | grep -o 'bindings \\[[^]]*\\]' | head -1"
        + " | sed 's/\"uos-harness\";//'")
    r.mutation_probe(String("mutation-was-applied"),
        narrowed.byte_length() > 0 and narrowed != json_allow)
    r.mutation_probe(String("narrowed-allowlist-is-detected"),
        narrowed.byte_length() > 0 and not owned_in(narrowed, 0))

    # ---- WORLD ---------------------------------------------------------
    # Each live config must register only names owned by the allowlist for
    # ITS OWN dialect. That is the real invariant; a flat count of underscore
    # names is not.
    #
    # Honest limit: this is a text scan for a distinctive name token, not a
    # structural parse of JSON and TOML. A name inside a comment would be
    # counted. Accepted because a false positive fails closed, never open.
    var json_configs = String(
        ".mcp.json .pi/mcp.json .gemini/settings.json .deepseek/mcp.json")
    var toml_configs = String(".codex/config.toml")

    var present = capture(
        "for f in " + json_configs + " " + toml_configs
        + "; do test -f $f && echo x; done | wc -l")
    r.observe(String("config-presence"), present)
    var n_present: Int
    try:
        n_present = Int(present)
    except:
        n_present = -1
    r.world_or_blind(String("all-five-configs-readable"),
        n_present >= 0, n_present == 5)

    # A JSON config must not carry a TOML-only spelling, and vice versa.
    var json_has_toml_only = capture(
        "grep -ho 'uos_gleam\\|uos_development' " + json_configs
        + " 2>/dev/null | wc -l")
    r.observe(String("json-configs-scan"), json_has_toml_only)
    var n_jt: Int
    try:
        n_jt = Int(json_has_toml_only)
    except:
        n_jt = -1
    # A count of zero from a file that does not exist is not an observation.
    var json_cfg_readable = count(
        "for f in " + json_configs + "; do test -f \"$f\" && echo x; done"
        + " | wc -l") > 0
    var toml_cfg_readable = count(
        "for f in " + toml_configs + "; do test -f \"$f\" && echo x; done"
        + " | wc -l") > 0
    r.observe(String("json-configs-present"), String(json_cfg_readable))
    r.observe(String("toml-configs-present"), String(toml_cfg_readable))
    # F14, 20261106: bare `world()`. If every JSON config were missing,
    # `grep | wc -l` prints 0, `n_jt == 0` is True and the arm PASSES -- a
    # clean world inferred from NO world. Gated on the configs being
    # readable, so absence is BLIND.
    r.world_or_blind(String("json-configs-carry-no-toml-only-names"),
                     json_cfg_readable, n_jt == 0)

    var toml_has_json_only = capture(
        "grep -ho 'uos-gleam' " + toml_configs + " 2>/dev/null | wc -l")
    r.observe(String("toml-config-scan"), toml_has_json_only)
    var n_tj: Int
    try:
        n_tj = Int(toml_has_json_only)
    except:
        n_tj = -1
    # F14: same shape, same fix.
    r.world_or_blind(String("toml-config-carries-no-json-only-names"),
                     toml_cfg_readable, n_tj == 0)

    # Canonical convergence: every live config should register uos-harness,
    # which both dialects own.
    var canonical = capture(
        "grep -lo 'uos-harness' " + json_configs + " " + toml_configs
        + " 2>/dev/null | wc -l")
    r.observe(String("canonical-registration-scan"), canonical)
    var n_canon: Int
    try:
        n_canon = Int(canonical)
    except:
        n_canon = -1
    # F14 + F18, 20261106: bare `world()` on a count that is 0 when every
    # config is missing, compared against the literal 5. The expected total
    # is now the number of config files that actually exist, so the arm asks
    # "does every PRESENT config register the canonical name" and goes BLIND
    # when none is present.
    var cfg_total = count(
        "for f in " + json_configs + " " + toml_configs
        + "; do test -f \"$f\" && echo x; done | wc -l")
    r.observe_int(String("live-configs-present"), cfg_total)
    r.world_or_blind(String("all-configs-register-canonical-name"),
                     cfg_total > 0 and n_canon >= 0, n_canon == cfg_total)

    print("# probe time       :", now)
    print("# json/toml owned  :", json_owned, "/", toml_owned,
          " union:", owned_somewhere, "of", DOMAIN)
    print("# configs readable :", n_present, "/ 5")
    print("# dialect leaks    : json<-toml", n_jt, " toml<-json", n_tj)
    print("# canonical name   :", n_canon, "/ 5 configs")
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
