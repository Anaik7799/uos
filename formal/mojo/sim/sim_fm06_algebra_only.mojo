# Simulation fixture for FM-06a: algebra-only oracle with zero world checks.
# Prevented by SC-VP-01 in oracle_substrate.mojo: emits BLIND instead of PASS.
from oracle_substrate import Receipt

def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    var n = 0
    r.algebra(String("fm06a-algebra-only-arm"), n == 0)
    r.emit()
