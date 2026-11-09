# ==========================================================================
# oracle_substrate — shared substrate for UOS Lean/Mojo differential oracles.
#
# THE BOUNDARY
# ------------
# Lean owns the ALGEBRA : types, defs, theorems over finite domains,
#                         `by decide`. No IO.Process, no IO.FS, no sockets,
#                         and NO RECORDED OBSERVATIONS.
# Mojo owns the WORLD   : process spawn, HTTP, systemd, sqlite, filesystem
#                         scans, SIMD numerics. Never claims a proof.
#
# WHY THE SPLIT EXISTS (observed, not hypothesised)
# -------------------------------------------------
# formal/lean/UosMcpNameOwnershipTwin.lean used to carry `observationNow`
# with `unownedNamesInConfigs := 2` and a theorem proving divergence
# `by decide`. The underlying rename landed 2026-11-05T22:20Z. Every live
# config went to zero unowned names. The theorem stayed green, because a
# hardcoded constant cannot go stale in the kernel's eyes -- the proof
# outlived its subject. The Mojo oracle, evaluating the SAME algebra against
# the real world, disagreed, and that disagreement is what surfaced it.
#
# THREE KINDS OF CHECK, KEPT APART
# --------------------------------
# `algebra()` — re-evaluates something Lean proves symbolically. An algebra
#               failure while Lean still typechecks means the decide-domain
#               and the enumerated domain are NOT the same domain. That is
#               DIVERGENCE: the model drifted from itself. It is the most
#               serious verdict this system can produce and must never be
#               reported as an ordinary outage.
# `world()`   — compares the model against the live system. A world failure
#               is an ordinary operational failure: the model is coherent,
#               reality does not match it.
# `observe()` — records that the world could be LOOKED AT. Empty capture =>
#               BLIND, never a silent PASS. An oracle that observed nothing
#               has not agreed with anything.
#
# VACUITY
# -------
# An oracle that cannot fail is theatre. `mutation_probe` makes every oracle
# carry its own negative control: a deliberately wrong evaluation that MUST
# be rejected. If the wrong value is accepted the run is FAIL, however many
# positive checks passed, because the oracle has proved only that it is blind.
#
# AUTHORITY
# ---------
# Every receipt carries `"authority":"NONE"`. A PASS is evidence that a model
# and a concrete evaluation agree at one candidate. It is not admission, not
# a release gate, not a Sa-plan completion. EV ceiling 93; EV-94..109
# NOT_ADMITTED; no new EV number is minted here.
# ==========================================================================

from std.subprocess import run


comptime PROBE_TIMEOUT_SECS = 20
comptime CANONICAL_EV_CEILING_PATH = "governance/provenance/admitted_ev_ceiling.txt"


def shell_quote(s: String) -> String:
    """Single-quote `s` for safe nesting inside `sh -c '...'`.

    Needed because every probe is wrapped in a timeout, which means the
    command is nested one shell deeper than it was written. A naive wrap
    broke every probe containing a quote with "Unterminated quoted string"
    and -- worse -- those probes returned empty, which the substrate dutifully
    scored as BLIND. The run looked merely uninformative rather than broken.
    """
    var out = String("'")
    for c in s.codepoints():
        if c == Codepoint.ord("'"):
            out += String("'\\''")
        else:
            out += String(c)
    out += String("'")
    return out


def capture(cmd: String, secs: Int = PROBE_TIMEOUT_SECS) -> String:
    """Run a BOUNDED shell command; trimmed stdout, or "" if it could not run.

    `secs` added 20261107-2353, finding F-W-23. The bound was the fixed
    `PROBE_TIMEOUT_SECS = 20` for every caller, and razr15-1:8000 takes
    120.1 s to return its definite `502` (its own backend timeout is 120 s).
    So NO arm built on this function could observe that answer: the outer
    `timeout -k 5 20` killed the probe first, every HTTP arm against that
    gateway was structurally BLIND, and a `curl --max-time 150` added at a
    call site was inert because the smaller outer bound dominated. A fix that
    looks right and changes nothing is worse than no fix, because it stops
    the search.

    20 s stays the default deliberately -- it is the guard that keeps an
    oracle from inheriting its subject's hang -- and a caller that needs
    longer must say so, and say why, at the call site.

    Every probe is wrapped in `timeout -k 5 <N>`. Without that an oracle
    inherits the hang of whatever it observes: a curl against a listener that
    accepts the connection and never answers, or an MCP handshake against a
    gateway stuck in startup, would block the whole differential run
    indefinitely. A monitor that can hang on its subject shares a fate it was
    built to be independent of -- the co-residency defect in another hat.

    Fails soft: an absent tool or a timeout is an observation (empty), never a
    crash. A timeout is therefore reported as BLIND, which is correct -- the
    probe could not obtain its evidence.
    """
    try:
        return String(
            String(
                run(
                    "timeout -k 5 " + String(secs if secs > 0
                                             else PROBE_TIMEOUT_SECS)
                    + " sh -c " + shell_quote(cmd)
                )
            ).strip()
        )
    except:
        return String("")
def contains(hay: String, needle: String) -> Bool:
    return needle in hay


def canonical_ev_ceiling() -> Int:
    """Read the single canonical admitted EV ceiling from
    `governance/provenance/admitted_ev_ceiling.txt` (managed by
    `tools/uos_ev_ceiling_controller.lean`). Eliminates scattered magic numbers."""
    var raw = capture("cat " + String(CANONICAL_EV_CEILING_PATH) + " 2>/dev/null")
    if raw.byte_length() == 0:
        return 109
    try:
        return Int(raw)
    except:
        return 109



# --------------------------------------------------------------------------
# ONE JSON ONTOLOGY FOR EVERY ORACLE
#
# Six "world failures" in the razr15 oracle's first run were not failures.
# The endpoint emits `"all_data_plane_slos_pass": true` -- with a space after
# the colon -- and the probe asked for `"all_data_plane_slos_pass":true`. The
# probe could not find the field, so it scored the field as FALSE and
# manufactured six outages on a healthy node. That is the same defect
# `world_or_blind` exists to prevent, reintroduced one layer down in the
# string matching.
#
# So field lookup is not left to each oracle. `json_flag` returns a THREE-
# valued answer -- 1 true, 0 false, -1 ABSENT -- and `Receipt.world_json`
# routes -1 to BLIND. An oracle can no longer accidentally read "absent" as
# "false", because the type no longer lets it.
# --------------------------------------------------------------------------


def json_norm(s: String) -> String:
    """Strip insignificant whitespace so key lookups are format-independent.

    Safe for flags and numbers. NOT safe for string values that contain
    spaces -- use the raw body for those, via `contains`.
    """
    var out = String("")
    for c in s.codepoints():
        if c != Codepoint.ord(" ") and c != Codepoint.ord("\n") \
           and c != Codepoint.ord("\t") and c != Codepoint.ord("\r"):
            out += String(c)
    return out


def json_flag(body: String, key: String) -> Int:
    """1 = true, 0 = false, -1 = the key is not present at all."""
    var n = json_norm(body)
    var k = String("\"") + key + String("\":")
    if (k + String("true")) in n:
        return 1
    if (k + String("false")) in n:
        return 0
    return -1


def json_has(body: String, key: String) -> Bool:
    """Whether `key` is present at all, independent of its value.

    The companion to `json_signed`, which cannot use -1 as an absence
    sentinel because a genuine value may be negative.
    """
    return (String("\"") + key + String("\":")) in json_norm(body)


def json_signed(body: String, key: String) -> Int:
    """The SIGNED integer at `key`. Presence must be asked separately.

    ADDED 20261106. `json_int` accumulates ASCII digits and stops at the
    first non-digit, so a leading `-` terminates the scan immediately and
    every negative field reads as -1, i.e. as ABSENT. Its docstring stated
    the precondition: "No UOS telemetry field is negative; if one ever is,
    this helper must gain a separate presence result rather than guess."
    That precondition is false and the mandate itself says so -- CLAUDE.md
    mandate 1 defines the fail-closed interception codes as embedded NUL
    `-2` and raw SQL `-3`, and `bionic_interception_oracle` reads
    `adversarial_sqli_trap_code: -3`. The substrate could not read the very
    codes the policy requires to exist.

    Found by migrating that oracle's hand-rolled string matches onto the
    three-valued readers (F4): the arm went BLIND, and the blindness was the
    reader's, not the subject's. Callers pair this with `json_has` and route
    absence through `world_or_blind`, so absence and a negative value stay
    distinct.
    """
    var n = json_norm(body)
    var k = String("\"") + key + String("\":")
    if k not in n:
        return 0
    var parts = n.split(k)
    if len(parts) < 2:
        return 0
    var tail = parts[1]
    var negative = False
    var digits = String("")
    var started = False
    for c in tail.codepoints():
        if not started and String(c) == String("-"):
            negative = True
            started = True
            continue
        if c.is_ascii_digit():
            started = True
            digits += String(c)
        else:
            break
    if digits.byte_length() == 0:
        return 0
    try:
        var v = Int(digits)
        return -v if negative else v
    except:
        return 0


def json_int(body: String, key: String) -> Int:
    # F18, 20261106: this TRUNCATES a float silently -- `"x": 0.95` reads as
    # 0 -- and reserves -1 for absence, so a genuinely negative value is
    # indistinguishable from a missing key. The absence convention is
    # deliberate and documented; the truncation was not, and is stated here
    # so a caller reading a ratio or a rate knows what it gets. Callers
    # needing a fractional field must scale it in the producing endpoint or
    # read it as a string.
    """The integer at `key`, or -1 when the key is absent or not an integer.

    -1 is reserved for absence, so a genuine -1 in the payload is reported
    as absent. No UOS telemetry field is negative; if one ever is, this
    helper must gain a separate presence result rather than guess.
    """
    var n = json_norm(body)
    var k = String("\"") + key + String("\":")
    if k not in n:
        return -1
    var parts = n.split(k)
    if len(parts) < 2:
        return -1
    var tail = parts[1]
    var digits = String("")
    for c in tail.codepoints():
        if c.is_ascii_digit():
            digits += String(c)
        else:
            break
    if digits.byte_length() == 0:
        return -1
    try:
        return Int(digits)
    except:
        return -1


def occurrences(hay: String, needle: String) -> Int:
    """How many times `needle` appears. Used to COUNT things the model
    declares a cardinality for -- seven data-plane stages, forty actors --
    instead of trusting a summary field to agree with the list beside it."""
    if needle.byte_length() == 0:
        return 0
    return len(hay.split(needle)) - 1

def last_line(s: String) -> String:
    """The final non-empty line, which is where `curl -w` puts its field.

    Returns "" for input with no non-empty line at all, and that empty
    return is load-bearing: `world_status` reads it as "no status", i.e.
    BLIND. A helper that invented "000" here would be indistinguishable
    from a real timeout, and a helper that returned the whole blob would
    make `http_code != "200"` true for every successful response.
    """
    var parts = s.split("\n")
    var i = len(parts) - 1
    while i >= 0:
        var cand = String(String(parts[i]).strip())
        if cand.byte_length() > 0:
            return cand
        i -= 1
    return String("")


def strip_last_line(s: String) -> String:
    """`s` without the trailing field `last_line` returns -- i.e. the body.

    Deliberately the exact complement of `last_line` over the same split, so
    the two cannot disagree about where the boundary is. Splitting twice with
    two different rules is how a body keeps its status code and a status code
    keeps a fragment of body.
    """
    var parts = s.split("\n")
    var keep = len(parts) - 1
    while keep > 0:
        if String(String(parts[keep]).strip()).byte_length() > 0:
            break
        keep -= 1
    var out = String("")
    for i in range(keep):
        if i > 0:
            out += String("\n")
        out += String(parts[i])
    return out


struct Receipt(Copyable, Movable):
    """Accumulates one oracle run and emits a uos.oracle.v1 record."""

    var schema: String
    var subject: String
    var checks: Int
    var algebra_checks: Int
    var algebra_failures: Int
    var world_checks: Int
    var world_failures: Int
    var observations: Int
    var blind: Int
    var vacuous: Int
    var detail: String

    def __init__(out self, schema: String, subject: String):
        self.schema = schema
        self.subject = subject
        self.checks = 0
        self.algebra_checks = 0
        self.algebra_failures = 0
        self.world_checks = 0
        self.world_failures = 0
        self.observations = 0
        self.blind = 0
        self.vacuous = 0
        self.detail = String("")

    def _note(mut self, tag: String):
        if self.detail.byte_length() > 0:
            self.detail += String(",")
        self.detail += String('"') + tag + String('"')

    def algebra(mut self, name: String, ok: Bool):
        """Re-evaluate a property Lean proves symbolically.

        A failure here means the two sides disagree about the same algebra.
        """
        self.checks += 1
        self.algebra_checks += 1
        if not ok:
            self.algebra_failures += 1
            self._note(String("algebra:") + name)

    def world(mut self, name: String, ok: Bool):
        """Compare a coherent model against the live system."""
        self.checks += 1
        self.world_checks += 1
        if not ok:
            self.world_failures += 1
            self._note(String("world:") + name)

    def observe(mut self, name: String, raw: String):
        """Record that the world could be looked at. Empty => BLIND."""
        self.checks += 1
        self.observations += 1
        if raw.byte_length() == 0:
            self.blind += 1
            self._note(String("blind:") + name)

    def observe_int(mut self, name: String, value: Int):
        """Record a COUNTED observation, where a negative value is BLIND.

        F15, 20261106. `observe` detects blindness by `raw.byte_length() == 0`,
        which an `Int` can never satisfy: `String(-1)` is two characters. Every
        `count()` helper in this tree returns -1 for "could not read", so 52
        call sites of the form `observe(name, String(some_count))` recorded a
        successful observation of nothing. A receipt could report
        `observations: 3, blind: 0` when all three greps had failed, which
        overstates how much of the world was actually seen and inflates
        `checks` with it.

        The oracles that pass raw captures to `observe` got correct BLIND
        accounting for free; this gives the counted ones the same thing
        without asking every author to remember the sentinel.
        """
        self.checks += 1
        self.observations += 1
        if value < 0:
            self.blind += 1
            self._note(String("blind:") + name + String(":uncountable"))

    def world_or_blind(mut self, name: String, field_present: Bool, value_ok: Bool):
        """Distinguish "it is broken" from "I could not look at it".

        A field the endpoint never emits is NOT evidence of failure. Scoring
        it as a world failure manufactures an outage out of an observability
        gap; scoring it as PASS hides one. It is BLIND: the property was not
        observable at this candidate, and the run must not claim agreement.

        Concretely: /api/health on the pinned capsule carries no
        `fpp_supervisor_running` key at all, so asking whether the supervisor
        is up returns nothing, not false.
        """
        self.checks += 1
        if not field_present:
            self.blind += 1
            self._note(String("blind:") + name + String(":field-absent"))
            return
        self.world_checks += 1
        if not value_ok:
            self.world_failures += 1
            self._note(String("world:") + name)

    def world_json(mut self, name: String, flag: Int, expected: Bool):
        """Record a boolean JSON field whose ABSENCE is already distinguished.

        `flag` comes from `json_flag`: -1 means the endpoint never emitted
        the key, which is BLIND, not false. This is the three-valued form of
        `world_or_blind` and is preferred wherever the evidence is a JSON
        field, because it removes the step where an oracle author has to
        remember to compute presence separately from value.
        """
        self.checks += 1
        if flag < 0:
            self.blind += 1
            self._note(String("blind:") + name + String(":field-absent"))
            return
        self.world_checks += 1
        if (flag == 1) != expected:
            self.world_failures += 1
            # F18, 20261106: this emitted a bare `name`, while `world()` and
            # `algebra()` both prefix their channel. A world_json failure was
            # therefore indistinguishable in `detail` from an algebra failure
            # -- i.e. an outage read as a divergence between the two planes.
            self._note(String("world:") + name)

    def world_count(mut self, name: String, observed: Int, expected: Int):
        """Compare a COUNTED cardinality against the model's declared one.

        `observed < 0` means the thing could not be counted => BLIND. A
        count of 0 is a real count and is compared, not excused.
        """
        self.checks += 1
        if observed < 0:
            self.blind += 1
            self._note(String("blind:") + name + String(":uncountable"))
            return
        self.world_checks += 1
        if observed != expected:
            self.world_failures += 1
            # F18, 20261106: `world:` prefix added, as for world_json.
            self._note(String("world:") + name + String(":got-")
                       + String(observed) + String("-want-")
                       + String(expected))

    def world_fresh(mut self, name: String, age_min: Int, max_age_min: Int):
        """Report an artifact's freshness, with STALE scored as BLIND.

        Finding F-W-14, second and deeper half. The freshness arms in
        context_path_kpi_oracle.mojo were written as

            world_or_blind(name, age >= 0, age <= MAX)

        and `world_or_blind`'s first parameter is FIELD PRESENCE, not
        freshness. A stale age is present -- it is merely large -- so
        `field_present` was true, `value_ok` was false, and the arm reported
        WORLD_FAIL. Meanwhile the comment directly above it read: "BLIND, not
        PASS: the property was not observable at this candidate because
        nobody rendered it recently."

        The prose said BLIND and the code manufactured an outage. That is the
        whole PASS -> WORLD_FAIL -> PASS oscillation of 2026-11-07, with no
        code change on any side, driven purely by an external renderer's
        schedule. An oracle that does not render a file cannot report its
        age as that file's failure.

        Zero-muda: this delegates to `world_count_fresh` rather than
        restating the three-way logic. The comparison 0 == 0 always holds, so
        the arm's only outcomes are PASS (fresh) and BLIND (stale or
        unknowable) -- which is exactly the claim being made. One
        implementation of staleness in this substrate, not two that agree
        until they drift.

        Consequence for mutation coverage, stated rather than hidden: as a
        one-line delegation this method has no operator the L1 mutation
        instrument can apply, so it will report UNMEASURED, like `owned_in`.
        Its behaviour is covered transitively through `world_count_fresh`.
        """
        self.world_count_fresh(name, 0, 0, age_min, max_age_min)

    def world_count_fresh(mut self, name: String, observed: Int,
                          expected: Int, age_min: Int, max_age_min: Int):
        """`world_count` that knows STALE from BROKEN. Finding F-W-14.

        `world_count` above distinguishes two cases: a value that could not be
        counted (BLIND) and a value that disagrees (WORLD_FAIL). It has no
        third case for a value that was read correctly out of a file too old
        to describe anything current. So an oracle would bound an artifact's
        age in ONE arm and read a value out of that same artifact in ANOTHER,
        and a stale file produced `blind:...-is-fresh` beside
        `world:...:got-N-want-M` -- an outage manufactured from an
        observability gap, which is exactly what `world_or_blind` exists to
        prevent for absent fields.

        Observed, not theorised: context_path_kpi_oracle went
        PASS -> WORLD_FAIL -> PASS across 2026-11-07 with NO code change on
        any side, purely because an external renderer's output crossed
        MAX_ARTIFACT_AGE_MIN (1440) at ~01:34Z and was re-rendered at 20:05Z.
        A verdict that tracks a renderer's schedule is not evidence about the
        candidate.

        The general rule this encodes: an arm that READS a file is not an arm
        that VALIDATED that file. The freshness predicate must gate the read
        it licenses, in the same arm, or it gates nothing.

        age_min < 0 means the age itself could not be determined, which is
        BLIND for the same reason: a missing age is not a fresh age. A
        max_age_min of 0 means "must be from this minute", which is legal and
        strict, not a disabled check.
        """
        self.checks += 1
        if observed < 0:
            self.blind += 1
            self._note(String("blind:") + name + String(":uncountable"))
            return
        if age_min < 0:
            self.blind += 1
            self._note(String("blind:") + name + String(":age-unknown"))
            return
        if age_min > max_age_min:
            self.blind += 1
            self._note(String("blind:") + name + String(":stale-")
                       + String(age_min) + String("min-max-")
                       + String(max_age_min))
            return
        self.world_checks += 1
        if observed != expected:
            self.world_failures += 1
            self._note(String("world:") + name + String(":got-")
                       + String(observed) + String("-want-")
                       + String(expected))

    def world_status(mut self, name: String, http_code: String,
                     body_ok: Bool):
        """Verdict for an HTTP probe, deciding on the ANSWER, not the budget.

        Finding F-W-23, 20261107-2353. Two oracles probed the SAME broken
        endpoint and returned two different verdicts:

          razr15_max_qwen_oracle  `curl --max-time 12`  -> empty -> BLIND
          model_evaluation_oracle `curl` (no cap)       -> 502   -> WORLD_FAIL

        Exactly one can be right, and the one that was wrong was wrong for a
        reason that has nothing to do with the subject: razr15-1:8000 answers
        a definite `502 {"error":"<urlopen error timed out>"}` after 120s,
        because its own backend timeout is 120s (max_qwen_server.py:602). A
        12-second probe therefore cannot reach the answer, reads empty, and
        calls a KNOWN, REPRODUCIBLE failure unobservable.

        That is the mirror image of F-W-14. F-W-14 scored unobservability as
        an outage (over-reporting); this scored an outage as unobservability
        (under-reporting). Same root pathology both times: the verdict was
        decided by the measuring apparatus instead of by the measurement.

        So the discriminator is the STATUS, which `curl -w '%{http_code}'`
        yields from the same request at no extra cost:

          no status / "000"  the request did not complete inside the budget.
                             Nothing was observed. BLIND -- and honestly so,
                             because a longer budget might well answer.
          status != expected the server ANSWERED, and its answer was a
                             failure. That is an observation. WORLD_FAIL.
          status == expected the transport worked; `body_ok` decides.

        Note what this does NOT do: it does not lower a verdict. A caller
        that reaches a definite error now reports WORLD_FAIL where it used to
        report BLIND, so severity RISES. Proved as THM_PROBE_05 in
        formal/lean/Razr15_Max_Qwen_Digital_Twin.lean, together with the
        control that matters (THM_PROBE_03: a pass still requires both a
        200 and a good body, so no failure can become a pass).

        The budget remains the caller's business, with one rule: it must
        exceed the subject's own failure latency, or this helper is handed
        "000" forever and reports BLIND forever. A long budget costs nothing
        on a healthy endpoint -- it returns in milliseconds -- and costs time
        only when something is actually wrong, which is exactly when the
        definite answer is worth waiting for.
        """
        self.checks += 1
        # "000" is curl's no-answer code; "0" is what an Int-typed status
        # field stringifies to when its parse never happened. Both mean the
        # same thing -- no status was obtained -- and accepting only one of
        # them would make the verdict depend on which caller did the parsing.
        if (http_code.byte_length() == 0 or http_code == String("000")
                or http_code == String("0")):
            self.blind += 1
            self._note(String("blind:") + name + String(":no-status-within-budget"))
            return
        self.world_checks += 1
        if http_code != String("200"):
            self.world_failures += 1
            self._note(String("world:") + name + String(":http-") + http_code)
            return
        if not body_ok:
            self.world_failures += 1
            self._note(String("world:") + name + String(":http-200-bad-body"))

    def mutation_probe(mut self, name: String, wrong_is_rejected: Bool):
        """Negative control: a deliberately wrong evaluation MUST be rejected."""
        self.checks += 1
        if not wrong_is_rejected:
            self.vacuous += 1
            self._note(String("vacuous:") + name)

    def status(self) -> String:
        # Order matters. Vacuity first: a blind oracle's other verdicts are
        # worthless. Then divergence, which is graver than any outage.
        #
        # REVIEW FINDING F7, 20261106-0756. Vacuity has TWO forms, and only
        # the probe-failure form used to be tested first. The zero-algebra
        # form sat BELOW `world_failures` and `blind`, so any oracle that
        # bailed out before reaching its algebra -- which is exactly what an
        # oracle does when its input is unreadable -- was labelled
        # WORLD_FAIL or BLIND instead of VACUOUS. Three oracles take that
        # path deliberately, each with a comment saying every verdict below
        # would be vacuous (`axis_registry_oracle` :96,
        # `mcp_name_ownership_oracle` :108, `twin_coverage_oracle` :87).
        # The authors were right and this function contradicted them, one
        # line under a comment reading "Vacuity first".
        #
        # `tools/lean_mojo_differential.ml` ranks Vacuous at severity 5,
        # above World_fail 2 and Blind 1, so the inversion was real and not
        # a difference of convention. The driver tests zero-algebra vacuity
        # first on its own, so the damage was confined to this receipt's
        # `status` field -- the artifact of record -- and to the exit code a
        # human or hook sees running the oracle directly.
        #
        # Both forms are now tested together, before everything else.
        if self.vacuous != 0 or self.algebra_checks == 0:
            return String("VACUOUS")
        if self.algebra_failures != 0:
            return String("DIVERGENT")

        # ---- SC-VP-02, ADDED 20261106-1230 -------------------------------
        # A world FAILURE requires an observation behind it. A receipt that
        # asserts the world is broken while having observed nothing is
        # asserting a failure about a world nobody looked at -- the
        # manufactured-outage shape, measured at RPN 80, the highest in the
        # plane's FMEA, and detected by no instrument until now.
        #
        # `UosVerificationPlaneTwin.lean` THM_VP_12 proves that state is
        # reachable in exactly two steps. BLIND is the honest verdict: the
        # property was not observable, so the run must not claim a failure.
        # CORRECTED 20261106-1230, by a Lean refutation. This first resolved
        # to BLIND, and `THM_VP_17_guarding_never_weakens_a_verdict` came back
        # FALSE: BLIND is severity 1 and WORLD_FAIL is severity 2, so the
        # guard LOWERED severity and a genuine outage could have been
        # laundered into "I could not look".
        #
        # VACUOUS is the correct verdict and the reasoning is the lattice's
        # own. A receipt asserting a world failure with zero observations is
        # not saying "I could not look"; it is saying "I claimed something I
        # could not know". That is an instrument that cannot discriminate,
        # which is exactly what vacuity means here -- and at severity 5 it
        # outranks the WORLD_FAIL it replaces, so the guard can only make a
        # verdict graver.
        #
        # No `_note`: `status()` takes `self` by value, and making it mutating
        # to add a detail line would change its contract for every caller.
        if self.world_failures != 0 and self.observations == 0:
            return String("VACUOUS")
        if self.world_failures != 0:
            return String("WORLD_FAIL")
        if self.blind != 0:
            return String("BLIND")

        # ---- SC-VP-01, ADDED 20261106-1230 -------------------------------
        # PASS requires that the world was actually checked. Algebra arms
        # alone establish that the MIRROR is faithful, never that the system
        # agrees with it, so a receipt reaching PASS with zero world checks
        # has verified a model against itself.
        #
        # THM_VP_11 proves that state is reachable in ONE step -- a single
        # passing algebra arm -- so "PASS" has never meant "the world was
        # observed". Measured at RPN 75 and detected by nothing.
        #
        # BLAST RADIUS MEASURED BEFORE THIS LANDED: all 16 oracles carry
        # world_checks >= 4 and observations >= 7, so this breaks none of
        # them today. It is a REGRESSION GUARD against a reachable state,
        # not a fix for a live defect, and saying otherwise would overstate
        # what changed.
        if self.world_checks == 0:
            return String("BLIND")
        return String("PASS")

    def emit(self):
        var ev_ceil = canonical_ev_ceiling()
        print(
            '{"schema":"', self.schema,
            '","subject":"', self.subject,
            '","checks":', self.checks,
            ',"algebra_checks":', self.algebra_checks,
            ',"algebra_failures":', self.algebra_failures,
            ',"world_checks":', self.world_checks,
            ',"world_failures":', self.world_failures,
            ',"observations":', self.observations,
            ',"blind":', self.blind,
            ',"vacuous":', self.vacuous,
            ',"detail":[', self.detail,
            '],"status":"', self.status(),
            '","authority":"NONE","ev_ceiling":', ev_ceil, '}',
            sep="",
        )

    def exit_code(self) -> Int:
        """0 PASS · 1 WORLD_FAIL · 2 BLIND · 3 DIVERGENT · 4 VACUOUS."""
        var s = self.status()
        if s == String("PASS"):
            return 0
        if s == String("WORLD_FAIL"):
            return 1
        if s == String("BLIND"):
            return 2
        if s == String("DIVERGENT"):
            return 3
        return 4
