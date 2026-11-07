# PLANTED FIXTURE, FM-12: Provider API interaction state machine turn-order violation
# (consecutive ToolCallEmitted without ToolResultAppended on strict-alternation APIs
# or continuing after HTTP 402 credit-cap breach without transitioning to FailClosed)
# Prevented by THM_FSYS_54 & C-ABI Export #23 uos_lean_verify_provider_api_transition.
from std.ffi import OwnedDLHandle
from oracle_substrate import Receipt
from lean_ffi_bridge import LEAN_GUARD_SO

def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String("formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean"))
    var handle = OwnedDLHandle(LEAN_GUARD_SO)
    var verify_api = handle.get_function[UInt8]("uos_lean_verify_provider_api_transition")
    # Illegal transition: prev=2 (ToolCallEmitted) -> next=2 (ToolCallEmitted) with req_strict_alt=1
    var illegal_turn = Int(verify_api(UInt8(2), UInt8(2), UInt8(1), UInt8(1), UInt8(1)))
    # Legal transition: prev=3 (ToolResultAppended) -> next=2 (ToolCallEmitted) with req_strict_alt=1
    var legal_turn = Int(verify_api(UInt8(3), UInt8(2), UInt8(1), UInt8(1), UInt8(1)))
    # Credit cap breach: cap_ok=0 -> next=6 (FailClosed) is legal (1), next=2 is refused (0)
    var cap_fail_closed = Int(verify_api(UInt8(1), UInt8(6), UInt8(0), UInt8(1), UInt8(0)))
    var cap_bypass_refused = Int(verify_api(UInt8(1), UInt8(2), UInt8(0), UInt8(1), UInt8(0)))
    r.algebra(String("fm12-provider-api-turn-and-cap-guard"), legal_turn == 1 and cap_fail_closed == 1 and illegal_turn == 0 and cap_bypass_refused == 0)
    r.world_count(String("fm12-illegal-provider-api-transition-refused"), illegal_turn, 1)
    r.mutation_probe(String("fm12-probe"), legal_turn != illegal_turn)
    r.emit()
