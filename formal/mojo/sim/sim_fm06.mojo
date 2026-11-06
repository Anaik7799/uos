# PLANTED FIXTURE, FM-06: bare world() on an absent SUBJECT. The count is 0
# because nothing was read, and `== 0` reads that as a clean world.
from oracle_substrate import Receipt, capture
def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    var legacy = capture("grep -c nothing /no/such/file 2>/dev/null | head -1")
    var n = 0
    r.algebra(String("fm06-real-arm"), n == 0)
    r.world(String("fm06-zero-legacy-names"), legacy.byte_length() == 0)
    r.emit()
