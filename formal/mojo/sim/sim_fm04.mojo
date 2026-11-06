# PLANTED FIXTURE, FM-04: a control that PINS a subject value, so a legitimate
# change in the subject reports VACUOUS instead of a divergence.
from oracle_substrate import Receipt
def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    var observed_subject_value = 102   # the subject legitimately moved 101->102
    r.algebra(String("fm04-real-arm"), observed_subject_value > 0)
    r.mutation_probe(String("fm04-probe-pins-the-subject"),
                     observed_subject_value == 101)
    r.emit()
