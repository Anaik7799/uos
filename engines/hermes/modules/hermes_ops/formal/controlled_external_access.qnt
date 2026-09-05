// R31 temporal model. The OCaml state machine is authoritative; this bounded
// independent projection must hold its safety/liveness invariants and violate
// the named false control before it can contribute evidence.
module controlled_external_access {
  var phase: str
  var authorized: bool
  var mailboxDepth: int
  var mailboxCapacity: int
  var failuresInWindow: int
  var maxRestarts: int
  var predictionRecommendation: bool
  var predictionEffectAuthority: bool

  action init = all {
    phase' = "Declared",
    authorized' = false,
    mailboxDepth' = 0,
    mailboxCapacity' = 2,
    failuresInWindow' = 0,
    maxRestarts' = 3,
    predictionRecommendation' = false,
    predictionEffectAuthority' = false
  }

  action validate = all {
    phase == "Declared",
    phase' = "Validated",
    authorized' = authorized,
    mailboxDepth' = mailboxDepth,
    mailboxCapacity' = mailboxCapacity,
    failuresInWindow' = failuresInWindow,
    maxRestarts' = maxRestarts,
    predictionRecommendation' = predictionRecommendation,
    predictionEffectAuthority' = false
  }

  action authorize = all {
    phase == "Validated",
    phase' = "Admitted",
    authorized' = true,
    mailboxDepth' = mailboxDepth,
    mailboxCapacity' = mailboxCapacity,
    failuresInWindow' = failuresInWindow,
    maxRestarts' = maxRestarts,
    predictionRecommendation' = predictionRecommendation,
    predictionEffectAuthority' = false
  }

  action prepare = all {
    phase == "Admitted",
    authorized,
    phase' = "Prepared",
    authorized' = authorized,
    mailboxDepth' = mailboxDepth,
    mailboxCapacity' = mailboxCapacity,
    failuresInWindow' = failuresInWindow,
    maxRestarts' = maxRestarts,
    predictionRecommendation' = predictionRecommendation,
    predictionEffectAuthority' = false
  }

  action execute = all {
    phase == "Prepared",
    authorized,
    phase' = "Executed",
    authorized' = authorized,
    mailboxDepth' = mailboxDepth,
    mailboxCapacity' = mailboxCapacity,
    failuresInWindow' = failuresInWindow,
    maxRestarts' = maxRestarts,
    predictionRecommendation' = predictionRecommendation,
    predictionEffectAuthority' = false
  }

  action enqueue = all {
    mailboxDepth < mailboxCapacity,
    phase' = phase,
    authorized' = authorized,
    mailboxDepth' = mailboxDepth + 1,
    mailboxCapacity' = mailboxCapacity,
    failuresInWindow' = failuresInWindow,
    maxRestarts' = maxRestarts,
    predictionRecommendation' = predictionRecommendation,
    predictionEffectAuthority' = false
  }

  action predict = all {
    phase' = phase,
    authorized' = authorized,
    mailboxDepth' = mailboxDepth,
    mailboxCapacity' = mailboxCapacity,
    failuresInWindow' = failuresInWindow,
    maxRestarts' = maxRestarts,
    predictionRecommendation' = true,
    predictionEffectAuthority' = false
  }

  action stutter = all {
    phase' = phase,
    authorized' = authorized,
    mailboxDepth' = mailboxDepth,
    mailboxCapacity' = mailboxCapacity,
    failuresInWindow' = failuresInWindow,
    maxRestarts' = maxRestarts,
    predictionRecommendation' = predictionRecommendation,
    predictionEffectAuthority' = predictionEffectAuthority
  }

  action step = any { validate, authorize, prepare, execute, enqueue, predict, stutter }

  val authorizationDominatesExecution = phase == "Executed" implies authorized
  val mailboxBounded = mailboxDepth <= mailboxCapacity
  val restartStormCannotRestart = failuresInWindow >= maxRestarts implies phase != "Restarting"
  val predictionHasNoEffectAuthority = not(predictionEffectAuthority)

  // FALSE CONTROL: the predict action reaches recommendation=true, so this
  // must be Violated in the bounded run and proves the checker explored it.
  val predictionNeverOccurs = not(predictionRecommendation)
}
