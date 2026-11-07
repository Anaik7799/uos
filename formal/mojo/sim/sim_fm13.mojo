# PLANTED FIXTURE, FM-13: Provider API unrecovered HTTP 402/429/5xx crash when failover is available
# Prevented by THM_FSYS_55 & C-ABI Export #24 uos_lean_resolve_provider_api_recovery (64/64 states).
from std.ffi import OwnedDLHandle
from oracle_substrate import Receipt
from lean_ffi_bridge import LEAN_GUARD_SO

def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String("formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean"))
    var handle = OwnedDLHandle(LEAN_GUARD_SO)
    var resolve_rec = handle.get_function[UInt8]("uos_lean_resolve_provider_api_recovery")
    # HTTP 402 (st=2) with affordable=0, google_direct=1 -> must return 4 (FailoverGoogleDirectV1Beta), never 6 (Halt)
    var rec_402_google = Int(resolve_rec(UInt8(2), UInt8(0), UInt8(0), UInt8(1), UInt8(1)))
    # HTTP 429/503 (st=3) with google_direct=0, local_qwen=1 -> must return 5 (FailoverLocalMaxQwen), never 6 (Halt)
    var rec_503_qwen = Int(resolve_rec(UInt8(3), UInt8(0), UInt8(0), UInt8(0), UInt8(1)))
    # Only when BOTH google_direct=0 and local_qwen=0 and affordable=0 does st=2 or st=3 return 6 (FailClosedAndonHalt)
    var rec_all_down = Int(resolve_rec(UInt8(3), UInt8(0), UInt8(0), UInt8(0), UInt8(0)))
    var unrecovered_crash_when_failover_available = 1 if (rec_402_google == 6 or rec_503_qwen == 6) else 0
    r.algebra(String("fm13-provider-api-multi-tier-graceful-recovery"), rec_402_google == 4 and rec_503_qwen == 5 and rec_all_down == 6)
    r.world_count(String("fm13-unrecovered-crash-when-failover-available-refused"), unrecovered_crash_when_failover_available, 1)
    r.mutation_probe(String("fm13-probe"), rec_402_google != rec_all_down)
    r.emit()
