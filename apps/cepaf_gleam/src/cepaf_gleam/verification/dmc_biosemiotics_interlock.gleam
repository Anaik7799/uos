//// =============================================================================
//// [C3I-SIL6-DMC] ROCHA BIOSEMIOTICS EVALUATOR & 13D TCM COORDINATE INTERLOCK
//// =============================================================================
//// Canonical implementation of:
//// 1. Rocha Biosemiotics Symbol-Matter Cut verification
//// 2. Traceability Coordinate Matrix (TCM) 13D conservation laws
//// 3. Hardware Storage Safety Interlock for host OS NVMe serial 25503L801736
//// =============================================================================

/// Strictly protected host OS NVMe drive serial (CHK-07-DRIVE / SC-STORAGE-SAFETY-001)
pub const hard_denied_system_os_serial: String = "25503L801736"

/// Status of the Rocha Biosemiotics Symbol-Matter Cut
pub type RochaCutStatus {
  RochaDecoupled
  RochaConflated
}

/// Invariant subset of 13-Dimensional Traceability Coordinates
pub type Tcm13DCoordinates {
  Tcm13DCoordinates(
    layer: Int,
    domain: String,
    authority: String,
    trust_indicator: Int,
  )
}

/// Verdict for safety/security interlock checks
pub type SecurityVerdict {
  AccessGranted
  AccessDenied(reason: String)
}

/// Evaluates whether the Rocha Biosemiotic cut is decoupled or conflated
pub fn verify_rocha_cut(is_decoupled: Bool) -> RochaCutStatus {
  case is_decoupled {
    True -> RochaDecoupled
    False -> RochaConflated
  }
}

/// Verifies 13D Coordinate Conservation Law: Delta T_13 = 0
/// Invariant coordinates (layer, domain, authority, trust_indicator)
/// must be conserved across state transformations.
pub fn verify_coordinate_conservation(
  t0: Tcm13DCoordinates,
  t1: Tcm13DCoordinates,
) -> Bool {
  t0.layer == t1.layer
  && t0.domain == t1.domain
  && t0.authority == t1.authority
  && t0.trust_indicator == t1.trust_indicator
}

/// Enforces the hardware safety interlock protecting the root OS NVMe drive
pub fn check_hardware_safety_interlock(serial: String) -> SecurityVerdict {
  case serial == hard_denied_system_os_serial {
    True ->
      AccessDenied("OS NVMe " <> hard_denied_system_os_serial <> " is locked")
    False -> AccessGranted
  }
}
