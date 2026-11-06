# PLANTED FIXTURE, FM-05: bare world() on an absent instrument. `ss` is
# simulated as missing, so contains() is False and a HEALTHY node reads as an
# outage rather than as BLIND.
from oracle_substrate import Receipt, capture, contains
def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    var ports = capture("no-such-command-xyz 2>/dev/null")
    r.algebra(String("fm05-real-arm"), True == True or False)
    r.world(String("fm05-port-listening"), contains(ports, String(":4100 ")))
    r.emit()
