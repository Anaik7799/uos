# NEGATIVE CONTROL for tools/mojo_arm_falsifiability.ml.
#
# Six expressions KNOWN to have no falsifying assignment, plus four known to
# have one. The detector must flag exactly the first six. If it cannot catch
# what it was built for, it is refused -- the rule the oracles are held to,
# applied to the thing that holds them.
#
# This file is a fixture, not an oracle: it is named *_falsify_probe.mojo so
# the differential driver's *_oracle.mojo glob does not pick it up as a pair.
from oracle_substrate import Receipt


def main():
    var r = Receipt(String("uos.oracle.v1"), String("control"))
    var x = 0
    var a = 0
    var b = 0
    var n = 0

    # --- MUST be reported UNFALSIFIABLE (6) ---------------------------------
    r.algebra(String("ctl-01-two-x-never-three"), x != 3 - x)
    r.algebra(String("ctl-02-double-reversal-identity"), 3 - (3 - x) == x)
    r.algebra(String("ctl-03-odd-reversal-never-fixed"), (3 - x) != x)
    r.algebra(String("ctl-04-sum-exceeds-part"), a + b > a or b <= 0)
    r.algebra(String("ctl-05-literal-tautology"), 93 == 93)
    r.algebra(String("ctl-06-self-comparison"), n == n)

    # --- MUST be reported FALSIFIABLE (4) ----------------------------------
    r.algebra(String("ctl-07-genuine-equality"), a == b)
    r.algebra(String("ctl-08-genuine-bound"), n <= 40)
    r.algebra(String("ctl-09-genuine-relation"), a + b == 93)
    r.algebra(String("ctl-10-genuine-inequality"), x > 0)
    r.emit()
