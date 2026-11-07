# PLANTED FIXTURE, FM-11: Unsanctioned python3 invocation in agent failover or
# std.python import in Mojo tool (THM_FSYS_52, SC-ZERO-PYTHON-001).
from oracle_substrate import Receipt

def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String("formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean"))
    var planted_unsanctioned_py = 1
    var clean_py = 0
    r.algebra(String("fm11-zero-python-gate-rejects-nonzero"), planted_unsanctioned_py > clean_py)
    r.world_count(String("fm11-unsanctioned-python-refused"), planted_unsanctioned_py, 0)
    r.mutation_probe(String("fm11-probe"), clean_py == 0)
    r.emit()
