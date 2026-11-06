# PLANTED FIXTURE, FM-01: a literal tautology arm. Fixture only; not an oracle.
from oracle_substrate import Receipt
def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    r.algebra(String("fm01-literal-tautology"), 93 == 93)
    r.emit()
