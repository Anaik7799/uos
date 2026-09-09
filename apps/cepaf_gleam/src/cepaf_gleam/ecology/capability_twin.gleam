//// Bounded, pure two-lattice transaction model. No shared store is mutated.
//// SC-HOLON-001, SC-STM-001; #fractal-l3 #fractal-l8 #zero-muda
//// Lean/Quint companions: formal/{lean,quint}/Ecology_Capability_Twin.*
//// A model receipt is computation evidence, never a lease or effect authority.

pub type Snapshot {
  Snapshot(
    version: Int,
    value: String,
    owner: Int,
    epoch: Int,
    expires: Int,
    telemetry: Int,
  )
}

pub type Transaction {
  Transaction(actor: Int, token: Int, snapshot: Int, now: Int, write: String)
}

pub type Rejection {
  InvalidState
  WrongOwner
  StaleFence
  Expired
  SnapshotConflict
}

/// The runtime transition: strict expiry, exact owner/epoch and read version.
pub fn commit(s: Snapshot, t: Transaction) -> Result(Snapshot, Rejection) {
  case valid(s, t) {
    False -> Error(InvalidState)
    True ->
      case s.owner == t.actor && t.actor > 0 {
        False -> Error(WrongOwner)
        True ->
          case s.epoch == t.token {
            False -> Error(StaleFence)
            True ->
              case t.now < s.expires {
                False -> Error(Expired)
                True ->
                  case t.snapshot == s.version {
                    False -> Error(SnapshotConflict)
                    True ->
                      Ok(
                        Snapshot(
                          ..s,
                          version: s.version + 1,
                          value: t.write,
                          owner: 0,
                        ),
                      )
                  }
              }
          }
      }
  }
}

pub fn valid(s: Snapshot, t: Transaction) -> Bool {
  s.version >= 1
  && s.epoch >= 1
  && s.owner >= 0
  && s.expires >= 0
  && s.telemetry >= 0
  && t.now >= 0
  && t.snapshot >= 1
  && t.token >= 1
}

/// Independent predicate oracle: does not call commit or classify its errors.
pub fn reference(s: Snapshot, t: Transaction) -> Snapshot {
  case
    valid(s, t)
    && t.actor > 0
    && s.owner == t.actor
    && s.epoch == t.token
    && t.now < s.expires
    && t.snapshot == s.version
  {
    True -> Snapshot(s.version + 1, t.write, 0, s.epoch, s.expires, s.telemetry)
    False -> s
  }
}

/// Observation updates only telemetry; authoritative fields remain immutable.
pub fn observe(s: Snapshot) -> Snapshot {
  Snapshot(..s, telemetry: s.telemetry + 1)
}

pub fn reject_name(r: Rejection) -> String {
  case r {
    InvalidState -> "invalid_state"
    WrongOwner -> "wrong_owner"
    StaleFence -> "stale_fence"
    Expired -> "expired"
    SnapshotConflict -> "snapshot_conflict"
  }
}
