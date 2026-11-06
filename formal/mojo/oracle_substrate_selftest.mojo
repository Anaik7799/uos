# Selftest for oracle_substrate: exercises all six verdict paths.
# Run: ./tools/mojo run -I formal/mojo formal/mojo/oracle_substrate_selftest.mojo
# Expected exit codes in order: 0 PASS, 3 DIVERGENT, 4 VACUOUS, 2 BLIND,
#   4 VACUOUS, 4 VACUOUS, 4 VACUOUS, 4 VACUOUS, 2 BLIND, 4 VACUOUS.
#
# CASE `c` CHANGED 20261106-1230, from WORLD_FAIL to VACUOUS. It records a
# failing world arm with NO observation, which SC-VP-02 now treats as an
# instrument that cannot discriminate rather than as an outage. The two new
# cases at the end exercise the guards directly.
#
# REVIEW FINDING F7, 20261106-0756. The last two cases are new, and they are
# the ones that matter. This selftest previously exercised zero-algebra
# vacuity ONLY in the clean case (`e` below: a world arm that passes, no
# blind). That combination is satisfied by the defective implementation as
# well as the correct one, so every expectation documented on this line was
# green while `status()` inverted the lattice. The exposing inputs are
# zero-algebra TOGETHER WITH a world failure, and zero-algebra together
# with a blind -- the two cases a real oracle actually produces when its
# input is unreadable. A selftest that cannot fail against the bug it is
# supposed to cover is the same defect as an oracle that cannot disagree
# with its subject.
from oracle_substrate import Receipt, capture, contains
def main() raises:
    # PASS
    var a = Receipt(String("uos.oracle.v1"), String("t-pass"))
    a.algebra(String("x"), True); a.world(String("y"), True)
    a.mutation_probe(String("m"), True); a.observe(String("clock"), capture("date -u +%Y"))
    a.emit(); print("exit=", a.exit_code())
    # DIVERGENT beats WORLD_FAIL
    var b = Receipt(String("uos.oracle.v1"), String("t-divergent"))
    b.algebra(String("x"), False); b.world(String("y"), False); b.emit(); print("exit=", b.exit_code())
    # WORLD_FAIL
    var c = Receipt(String("uos.oracle.v1"), String("t-world"))
    c.algebra(String("x"), True); c.world(String("y"), False); c.emit(); print("exit=", c.exit_code())
    # BLIND
    var d = Receipt(String("uos.oracle.v1"), String("t-blind"))
    d.algebra(String("x"), True); d.observe(String("nope"), capture("no-such-cmd-xyz 2>/dev/null"))
    d.emit(); print("exit=", d.exit_code())
    # VACUOUS: no algebra checks at all
    var e = Receipt(String("uos.oracle.v1"), String("t-vacuous-empty"))
    e.world(String("y"), True); e.emit(); print("exit=", e.exit_code())
    # VACUOUS: negative control accepted a wrong value
    var g = Receipt(String("uos.oracle.v1"), String("t-vacuous-probe"))
    g.algebra(String("x"), True); g.mutation_probe(String("m"), False); g.emit(); print("exit=", g.exit_code())
    # VACUOUS: zero algebra AND a world failure. Pre-fix this returned
    # WORLD_FAIL (exit 1), masking the graver verdict.
    var h = Receipt(String("uos.oracle.v1"), String("t-vacuous-with-world-fail"))
    h.world(String("y"), False); h.emit(); print("exit=", h.exit_code())
    # VACUOUS: zero algebra AND a blind observation. Pre-fix this returned
    # BLIND (exit 2). This is the shape `mcp_name_ownership_oracle` :105-111
    # produces when its allowlists are unreadable.
    var i = Receipt(String("uos.oracle.v1"), String("t-vacuous-with-blind"))
    i.observe(String("nope"), capture("no-such-cmd-xyz 2>/dev/null"))
    i.emit(); print("exit=", i.exit_code())
    # SC-VP-01: PASS requires a world check. Algebra arms alone establish
    # that the mirror is faithful, never that the system agrees with it.
    # Expect BLIND, exit 2.
    var j = Receipt(String("uos.oracle.v1"), String("t-sc-vp-01"))
    j.algebra(String("x"), True)
    j.observe(String("seen"), String("something"))
    j.emit(); print("exit=", j.exit_code())
    # SC-VP-02: a world FAILURE requires an observation behind it. Expect
    # VACUOUS, exit 4 -- and NOT WORLD_FAIL, which would be milder than the
    # verdict it replaces (the Lean refutation of THM_VP_17).
    var k = Receipt(String("uos.oracle.v1"), String("t-sc-vp-02"))
    k.algebra(String("x"), True)
    k.world(String("y"), False)
    k.emit(); print("exit=", k.exit_code())
