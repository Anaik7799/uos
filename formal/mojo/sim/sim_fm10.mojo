# PLANTED FIXTURE, FM-10: Cross-model tool-call replay without thoughtSignature
# or "skip_thought_signature_validator" waiver (THM_FSYS_51, C-ABI Export #21).
from std.ffi import OwnedDLHandle
from oracle_substrate import Receipt
from lean_ffi_bridge import LEAN_GUARD_SO

def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String("formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean"))
    var handle = OwnedDLHandle(LEAN_GUARD_SO)
    var verify_prov = handle.get_function[UInt8]("uos_lean_verify_tool_call_provenance")
    var res = Int(verify_prov(UInt8(1), UInt8(0), UInt8(1), UInt8(0), UInt8(1)))
    var waived = Int(verify_prov(UInt8(1), UInt8(0), UInt8(1), UInt8(1), UInt8(1)))
    r.algebra(String("fm10-waiver-restores-admissibility"), waived == 1 and res == 0)
    r.world_count(String("fm10-unwaived-cross-model-replay-refused"), res, 1)
    r.mutation_probe(String("fm10-probe"), waived != res)
    r.emit()
