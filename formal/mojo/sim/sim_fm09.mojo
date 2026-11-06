# PLANTED FIXTURE, FM-09: inverted polarity -- passes only while a defect
# count is nonzero, so repairing the system fails the arm.
from oracle_substrate import Receipt
def main():
    var r = Receipt(String("uos.oracle.v1"), String("sim"))
    var defects = 39
    var baseline = 7
    r.algebra(String("fm09-demands-the-defect-persist"),
              defects + baseline > baseline)
    r.emit()
