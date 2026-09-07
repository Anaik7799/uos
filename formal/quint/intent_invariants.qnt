// Intent Invariants Quint Specification
// Formal model of the UOS Denotational Intent Engine state machine
// Evaluates capability tokens, serial lock invariants, and authorization transitions.

module intent_invariants {
  type EffectDomain = str
  type Actor = str
  type Token = { actor: Actor, domain: EffectDomain, maxCrit: int, expiresAt: int }
  type Intent = { id: str, actor: Actor, domain: EffectDomain, targetSerial: str, crit: int }

  val VALID_DOMAINS = Set("ReadOnlyTelemetry", "ActorMessage", "PlanMutation", "StorageMutation", "HardwareControl")
  val HARD_DENIED_SERIAL = "25503L801736"
  val ACTORS = Set("claude-worker", "codex-worker", "agy-worker", "unauthorized-actor")

  var authorizedIntents: Set[str]
  var vetoedIntents: Set[str]
  var currentEpoch: int

  action init = all {
    authorizedIntents' = Set(),
    vetoedIntents' = Set(),
    currentEpoch' = 1000,
  }

  def canAuthorize(tok: Token, i: Intent, now: int): bool = all {
    tok.actor == i.actor,
    tok.domain == i.domain,
    i.crit <= tok.maxCrit,
    now < tok.expiresAt,
    not(i.targetSerial == HARD_DENIED_SERIAL),
  }

  action submitValidIntent = {
    nondet a = oneOf(ACTORS.filter(x => x != "unauthorized-actor"))
    nondet dom = oneOf(VALID_DOMAINS)
    val tok = { actor: a, domain: dom, maxCrit: 3, expiresAt: 2000 }
    val intentId = "int-" + a
    val i = { id: intentId, actor: a, domain: dom, targetSerial: "SAFE_NVME_001", crit: 1 }
    if (canAuthorize(tok, i, currentEpoch)) all {
      authorizedIntents' = authorizedIntents.union(Set(intentId)),
      vetoedIntents' = vetoedIntents,
      currentEpoch' = currentEpoch + 10,
    } else all {
      authorizedIntents' = authorizedIntents,
      vetoedIntents' = vetoedIntents.union(Set(intentId)),
      currentEpoch' = currentEpoch + 10,
    }
  }

  action submitLockedSerialAttack = {
    nondet a = oneOf(ACTORS)
    val tok = { actor: a, domain: "StorageMutation", maxCrit: 5, expiresAt: 5000 }
    val intentId = "attack-" + a
    val i = { id: intentId, actor: a, domain: "StorageMutation", targetSerial: HARD_DENIED_SERIAL, crit: 1 }
    // Must always fail closed
    if (canAuthorize(tok, i, currentEpoch)) all {
      authorizedIntents' = authorizedIntents.union(Set(intentId)),
      vetoedIntents' = vetoedIntents,
      currentEpoch' = currentEpoch + 10,
    } else all {
      authorizedIntents' = authorizedIntents,
      vetoedIntents' = vetoedIntents.union(Set(intentId)),
      currentEpoch' = currentEpoch + 10,
    }
  }

  action step = any {
    submitValidIntent,
    submitLockedSerialAttack,
  }

  // INVARIANT 1: No attack targeting the locked serial is EVER authorized
  val invStorageLockPreserved =
    authorizedIntents.forall(id => not(id.contains("attack-")))

  // INVARIANT 2: An intent cannot be simultaneously authorized and vetoed
  val invDisjointResolution =
    authorizedIntents.intersect(vetoedIntents) == Set()
}
