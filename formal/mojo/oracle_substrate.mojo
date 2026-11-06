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


def capture(cmd: String) -> String:
    """Run a BOUNDED shell command; trimmed stdout, or "" if it could not run.

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
                    "timeout -k 5 " + String(PROBE_TIMEOUT_SECS)
                    + " sh -c " + shell_quote(cmd)
                )
            ).strip()
        )
    except:
        return String("")
def contains(hay: String, needle: String) -> Bool:
    return needle in hay



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
            '","authority":"NONE","ev_ceiling":93}',
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
