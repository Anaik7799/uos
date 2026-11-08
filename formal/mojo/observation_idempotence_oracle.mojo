# ==========================================================================
# observation_idempotence_oracle — measures the real tree against
# formal/lean/UosObservationIdempotenceTwin.lean,
# apps/cepaf_gleam/src/mcp_stdio_ffi.erl and
# apps/cepaf_gleam/src/cepaf_gleam/mcp/runtime_gateway.gleam
#
# THE INCIDENT BEING MEASURED
# ---------------------------
# On 2026-11-08 `system_zenoh` published `degraded` /
# `zenoh_subscriber_status: stopped` from every stdio MCP session while the
# Zenoh SSE subscriber was in fact running in another node. The first repair
# added an owner-presence probe that `gen_tcp:connect`ed to the subscriber's
# mutex port. The mutex owner never calls `accept/1`, so each probe
# permanently consumed one of the 5 default backlog slots.
#
# Measured on this host, not assumed: six probes drove the socket to
# `LISTEN Recv-Q=6 Send-Q=5` with six CLOSE-WAIT entries, after which the
# probe reported the owner ABSENT while it was present. The observation
# inverted its own answer by being made.
#
# WHY THIS ORACLE EXISTS RATHER THAN A NOTE IN A JOURNAL
# ------------------------------------------------------
# "Do not probe a mutex by connecting to it" is a sentence nothing can read.
# The twin states the admissibility rule; `runtime_gateway.zenoh_subscriber_report/0`
# implements the admissible shape; and this oracle DERIVES that shape from
# the two source files rather than restating it, observes the socket without
# touching it, and calls the live classifier repeatedly to measure the
# repetition-invariance the twin proves.
#
# DERIVE, DO NOT RESTATE
# ----------------------
# The lock port is read out of the Erlang `-define`, not written here. The
# classifier's arm count is read out of the Gleam function body, not written
# here. A previous twin in this tree and its first oracle both hand-copied
# one of two allowlists and agreed perfectly on a wrong mapping; two copies
# of a wrong constant always agree.
#
# THIS ORACLE MUST NOT REPRODUCE THE DEFECT IT MEASURES. It observes the
# socket only through `ss -ltn`, which reads kernel state and opens no
# connection. If this file ever grows a connect to the lock port it becomes
# the incident.
#
# F-B5-01 discipline: the subject of this receipt is the Lean twin, and this
# oracle OPENS it. A declared subject is not a read subject.
#
# authority NONE. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV minted.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains, occurrences

comptime TWIN = "formal/lean/UosObservationIdempotenceTwin.lean"
comptime FFI = "apps/cepaf_gleam/src/mcp_stdio_ffi.erl"
comptime GATEWAY = "apps/cepaf_gleam/src/cepaf_gleam/mcp/runtime_gateway.gleam"
# The incident residue measured on this host 2026-11-08: the backlog the
# kernel gave the mutex socket. The twin's `pristine` is stated at this
# number. Read from the live socket below, never asserted equal to this.
comptime MEASURED_INCIDENT_BACKLOG = 5
comptime IDEMPOTENCE_CALLS = 8


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1


def read_text(path: String) -> String:
    return capture("cat " + path + " 2>/dev/null || true")


# ---- derive the lock port from the authority ---------------------------
# The Erlang `-define` is the sole source. If this returns -1 the macro was
# renamed or removed and every check below that depends on it goes BLIND
# rather than silently passing against a port nobody uses.
def derived_lock_port() -> Int:
    return count(
        "grep -oE '^-define\\(ZENOH_SUBSCRIBER_LOCK_PORT, *[0-9]+' " + FFI
        + " | grep -oE '[0-9]+$' | head -n 1")


# ---- derive the classifier's shape from the authority ------------------
# Arms of the `case` inside `zenoh_subscriber_report`, counted in the source.
# The twin proves a 2-state classifier is repetition-invariant; a third arm
# would be a different function and this must notice.
def derived_report_arms() -> Int:
    return count(
        "awk '/pub fn zenoh_subscriber_report/,/^}/' " + GATEWAY
        + " | grep -cE '^[[:space:]]+(True|False) ->'")


# Does any source file still carry the reverted owner-probe verdict?
def owned_elsewhere_occurrences() -> Int:
    return count(
        "grep -rl 'owned_elsewhere' apps/cepaf_gleam/src 2>/dev/null | wc -l")


# Does the FFI connect to the lock port anywhere? Derived from the source,
# not from this file's good intentions.
def connect_to_lock_port_occurrences() -> Int:
    return count(
        "grep -cE 'gen_tcp:connect\\([^)]*ZENOH_SUBSCRIBER_LOCK_PORT' " + FFI
        + " || true")


# ---- observe the socket WITHOUT touching it ----------------------------
# `ss -ltn` reads the kernel's listen table. No connection is opened, so
# repeating this cannot change what it reports -- the property the twin
# proves of `.passive` in THM_OBS_05 and THM_OBS_07.
def listen_field(port: Int, field: Int) -> Int:
    return count(
        "ss -ltn 2>/dev/null | awk '$4 ~ /:" + String(port)
        + "$/ {print $" + String(field) + "; exit}'")


def close_wait_count(port: Int) -> Int:
    return count(
        "ss -tn state close-wait 2>/dev/null | grep -c '127.0.0.1:"
        + String(port) + "' || true")


def socket_is_held(port: Int) -> Bool:
    return listen_field(port, 3) >= 0


# ---- live classifier, called repeatedly -------------------------------
# Fresh behaviour from the real BEAM, not a mirror. Returns the number of
# DISTINCT answers across IDEMPOTENCE_CALLS calls in one node; 1 means the
# classifier is repetition-invariant as THM_OBS_08 requires.
def distinct_live_answers() -> Int:
    var eval = String(
        "L=[cepaf_gleam@mcp@runtime_gateway:zenoh_subscriber_report()")
    var i = 1
    while i < IDEMPOTENCE_CALLS:
        eval += String(
            ",cepaf_gleam@mcp@runtime_gateway:zenoh_subscriber_report()")
        i += 1
    eval += String("],io:format(\\\"~p\\\",[length(lists:usort(L))]),halt(0).")
    return count(
        "bash -c 'source tools/lib/uos-toolchain.sh && uos_env && "
        + "erl -pa apps/cepaf_gleam/build/dev/erlang/*/ebin -noshell -eval \""
        + eval + "\" 2>/dev/null'")


# ---- mirrors of the twin's definitions --------------------------------
# Int/Bool only, so tools/mojo_arm_falsifiability.ml can enumerate them and
# tools/mojo_mutation_dataplane.ml can mutate them. Probe encoding:
# 0 connect, 1 bind, 2 passive, 3 none.

def consumes(probe: Int) -> Bool:
    return probe == 0


def denies(probe: Int) -> Bool:
    return probe == 1


def admissible(probe: Int) -> Bool:
    return not consumes(probe) and not denies(probe)


# `answer` for the connect probe: the truth conjoined with its own damage.
def connect_answer(held: Bool, queued: Int, backlog: Int) -> Bool:
    return held and queued < backlog


# Status encoding: 0 connected, 1 subscriber_not_local, 2 degraded.
# Report encoding: 0 connectedFresh, 1 reconnectingOrStale, 2 stopped,
# 3 disabled.
def status(mesh_up: Bool, report: Int) -> Int:
    if not mesh_up:
        return 2
    if report == 0:
        return 0
    if report == 3:
        return 1
    return 2


def status_superseded(mesh_up: Bool, report: Int) -> Int:
    if not mesh_up:
        return 2
    if report == 0:
        return 0
    return 2


def main():
    var r = Receipt(String("uos.oracle.v1"), String(TWIN))

    # ---- the twin is OPENED, not merely named -------------------------
    var twin_src = read_text(String(TWIN))
    var twin_thms = occurrences(twin_src, String("theorem THM_OBS_"))
    r.observe_int(String("twin:theorems"), twin_thms)
    r.world(String("twin:subject-is-readable"), twin_src.byte_length() > 0)
    # An emptied twin must not leave this receipt byte-identical.
    r.world(String("twin:carries-theorems"), twin_thms >= 20)
    # Cited by name: if a theorem this oracle checks is renamed away, say so.
    r.world(String("twin:cites-inadmissibility"),
            contains(twin_src, String("THM_OBS_12_incident_is_inadmissible")))
    r.world(String("twin:cites-superseded-disagreement"),
            contains(twin_src,
                     String("THM_OBS_16_superseded_reported_a_healthy_system")))
    # The twin must stay a pure specification (exclude backticked prose in comments).
    var twin_sorry = count(
        "grep -v '^[[:space:]]*--' " + String(TWIN)
        + " | grep -cE '(^|[[:space:]])sorry([[:space:]]|$)' || true")
    var twin_axiom = count(
        "grep -v '^[[:space:]]*--' " + String(TWIN)
        + " | grep -cE '(^|[[:space:]])axiom([[:space:]]|$)' || true")
    r.world(String("twin:no-sorry"), twin_sorry == 0)
    r.world(String("twin:no-axiom"), twin_axiom == 0)

    # ---- derived from the authority -----------------------------------
    var port = derived_lock_port()
    r.observe_int(String("authority:derived-lock-port"), port)
    r.world(String("authority:lock-port-is-derivable"), port > 0)

    var arms = derived_report_arms()
    r.observe_int(String("authority:report-arms"), arms)
    # Two arms is the admissible shape the twin proves invariant. Three would
    # be the reverted owner-probe classifier coming back.
    r.world(String("authority:classifier-has-two-arms"), arms == 2)

    var oe = owned_elsewhere_occurrences()
    r.observe_int(String("authority:files-with-owned-elsewhere"), oe)
    r.world(String("authority:owner-probe-verdict-absent"), oe == 0)

    var cx = connect_to_lock_port_occurrences()
    r.observe_int(String("authority:connects-to-lock-port"), cx)
    r.world(String("authority:no-connect-probe-on-mutex"), cx == 0)

    # This oracle must not be the thing it forbids (measure code lines, excluding
    # comments and the authority-source grep on line 106).
    var self_connects = count(
        "grep -vE '^[[:space:]]*#|ZENOH_SUBSCRIBER_LOCK_PORT' "
        + "formal/mojo/observation_idempotence_oracle.mojo "
        + "| grep -cE '[g]en_tcp:connect|[n]c +-z' || true")
    r.world(String("oracle:opens-no-connection-to-the-mutex"),
            self_connects == 0)

    # ---- observed passively, no connection opened ---------------------
    var held = socket_is_held(port)
    var backlog = listen_field(port, 3)
    var recvq = listen_field(port, 2)
    var cw = close_wait_count(port)
    r.observe_int(String("observed:listen-backlog"), backlog)
    r.observe_int(String("observed:listen-recvq"), recvq)
    r.observe_int(String("observed:close-wait-entries"), cw)
    # No owner running is a legitimate state of this host, not a failure of
    # the rule: go BLIND rather than claim a pass we did not observe.
    r.world_or_blind(String("observed:mutex-owner-present"), held, held)
    # The incident residue: the queue overshot the backlog it was given.
    # Recorded as an observation, never as a pass, while verifying the kernel
    # listen backlog itself is positive and readable.
    var residue = (recvq - backlog) if (recvq > backlog and backlog >= 0) else 0
    r.observe_int(String("observed:queue-overshoot-residue"), residue)
    r.world_or_blind(String("observed:listen-backlog-positive"),
                     held and backlog >= 0 and recvq >= 0,
                     backlog > 0)

    # ---- fresh behaviour: repetition invariance on the real BEAM ------
    var distinct = distinct_live_answers()
    r.observe_int(String("live:distinct-answers-across-calls"), distinct)
    r.world_or_blind(String("live:classifier-is-repetition-invariant"),
                     distinct > 0, distinct == 1)
    # And the socket did not move while we called it IDEMPOTENCE_CALLS times.
    var recvq_after = listen_field(port, 2)
    r.observe_int(String("live:listen-recvq-after-calls"), recvq_after)
    r.world_or_blind(String("live:classifier-consumed-nothing"),
                     held and recvq >= 0 and recvq_after >= 0,
                     recvq_after == recvq)

    # ---- algebra: re-evaluate what Lean proves symbolically -----------
    # THM_OBS_02/03 -- the connect probe told the truth once and then lied,
    # at the backlog this host actually gave the socket.
    r.algebra(String("obs02:sixth-connect-inverts-the-answer"),
              connect_answer(True, 6, MEASURED_INCIDENT_BACKLOG) == False)
    r.algebra(String("obs03:first-connect-told-the-truth"),
              connect_answer(True, 0, MEASURED_INCIDENT_BACKLOG) == True)
    # THM_OBS_09 -- so it is not repetition-invariant: same owner, two answers.
    r.algebra(String("obs09:connect-is-not-repetition-invariant"),
              connect_answer(True, 0, MEASURED_INCIDENT_BACKLOG)
              != connect_answer(True, 6, MEASURED_INCIDENT_BACKLOG))
    # THM_OBS_10/11 -- only the bind shape can deny a free resource.
    r.algebra(String("obs10:bind-denies-a-free-resource"), denies(1))
    r.algebra(String("obs11:others-do-not-deny"),
              not denies(0) and not denies(2) and not denies(3))
    # THM_OBS_12/13/14 -- the rule rejects both failed shapes and admits the
    # adopted one. If the last failed the rule would permit the incident and
    # this file would be decoration.
    r.algebra(String("obs12:incident-shape-is-inadmissible"),
              not admissible(0))
    r.algebra(String("obs13:rejected-repair-is-inadmissible"),
              not admissible(1) and not consumes(1) and denies(1))
    r.algebra(String("obs14:adopted-shape-is-admissible"),
              admissible(3) and admissible(2))
    # Each clause is load-bearing: neither alone rejects both failed shapes.
    r.algebra(String("obs14b:both-clauses-are-load-bearing"),
              consumes(0) and not denies(0) and denies(1) and not consumes(1))
    # THM_OBS_15/16 -- the repair changes an outcome rather than restating
    # one: the superseded classifier called a healthy system degraded.
    r.algebra(String("obs15:disabled-is-not-a-fault"), status(True, 3) == 1)
    r.algebra(String("obs16:superseded-disagreed-on-exactly-that-case"),
              status_superseded(True, 3) == 2
              and status(True, 3) != status_superseded(True, 3))
    # THM_OBS_17 -- degraded still means a fault.
    r.algebra(String("obs17:degraded-only-for-real-faults"),
              status(True, 1) == 2 and status(True, 2) == 2
              and status(True, 3) != 2 and status(True, 0) != 2)
    # THM_OBS_18 -- and connected still requires local freshness.
    r.algebra(String("obs18:connected-requires-local-freshness"),
              status(True, 0) == 0 and status(True, 3) != 0
              and status(False, 0) != 0)
    # THM_OBS_19 -- a dead mesh cannot be masked by the subscriber case.
    r.algebra(String("obs19:mesh-down-is-always-degraded"),
              status(False, 0) == 2 and status(False, 3) == 2)
    # Negative control: admitting a consuming connect probe (0) or treating
    # a disabled stdio subscriber as degraded must be rejected.
    r.mutation_probe(
        String("inadmissible-connect-probe-and-superseded-degraded-rejected"),
        not admissible(0) and not admissible(1)
        and status(True, 3) != status_superseded(True, 3))

    print("# observation idempotence plane")
    print("# twin theorems     :", twin_thms)
    print("# derived lock port :", port, "(from", FFI, "-define)")
    print("# classifier arms   :", arms, "derived from", GATEWAY)
    print("# socket observed   : held:", held, "backlog:", backlog,
          "recv-q:", recvq, "close-wait:", cw, "(ss only, no connection)")
    print("# live calls        :", IDEMPOTENCE_CALLS, "->", distinct,
          "distinct answer(s)")
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
