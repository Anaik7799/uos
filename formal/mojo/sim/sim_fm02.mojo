# PLANTED FIXTURE, FM-02: structurally unfalsifiable -- the derived value
# appears and cancels out. This is the class the literal scanner was blind to.
from oracle_substrate import Receipt
def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    var derived = 2
    r.algebra(String("fm02-variable-cancels"), derived != 3 - derived)
    r.emit()
