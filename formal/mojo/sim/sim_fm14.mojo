# PLANTED FIXTURE, FM-14: Feature domain SDLC/SRE 17-aspect admission without tri-agent Codex+Claude verification
# or with incomplete 17-aspect (0x1FFFF), 12-stage SDLC (0xFFF), or 8-gate SRE (0xFF) masks.
# Prevented by THM_FSYS_61..62 & C-ABI Export #27 uos_lean_verify_sdlc_sre_feature_aspect_gate (1,632/1,632 states).
from std.ffi import OwnedDLHandle
from oracle_substrate import Receipt
from lean_ffi_bridge import LEAN_GUARD_SO

def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String("formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean"))
    var handle = OwnedDLHandle(LEAN_GUARD_SO)
    var verify_aspect = handle.get_function[UInt8]("uos_lean_verify_sdlc_sre_feature_aspect_gate")
    # Valid feature F5 (id=5), aspect A16 (idx=15), sdlc=1, sre=1, claude=1, codex=1 -> 1 (admitted)
    var legal_aspect = Int(verify_aspect(UInt8(5), UInt8(15), UInt8(1), UInt8(1), UInt8(1), UInt8(1)))
    # Bypass attempts: missing Codex audit (codex=0) or missing SRE gate (sre=0) -> 0 (refused)
    var missing_codex = Int(verify_aspect(UInt8(5), UInt8(15), UInt8(1), UInt8(1), UInt8(1), UInt8(0)))
    var missing_sre = Int(verify_aspect(UInt8(4), UInt8(6), UInt8(1), UInt8(0), UInt8(1), UInt8(1)))
    var bypass_accepted = 1 if (missing_codex == 1 or missing_sre == 1) else 0
    r.algebra(String("fm14-sdlc-sre-17-aspect-tri-agent-gate"), legal_aspect == 1 and missing_codex == 0 and missing_sre == 0)
    r.world_count(String("fm14-unverified-sdlc-sre-aspect-bypass-refused"), bypass_accepted, 1)
    r.mutation_probe(String("fm14-probe"), legal_aspect != missing_codex)
    r.emit()
