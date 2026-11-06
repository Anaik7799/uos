# PLANTED FIXTURE, FM-07: a zero-algebra run WITH a world failure. Pre-fix the
# substrate returned WORLD_FAIL here, masking the graver VACUOUS.
from oracle_substrate import Receipt
def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    r.world(String("fm07-world-arm-fails"), False)
    r.emit()
