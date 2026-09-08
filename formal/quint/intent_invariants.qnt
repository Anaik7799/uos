// Intent Invariants Quint Specification
// Formal model of the UOS Denotational Intent Engine state machine
// Evaluates capability tokens, serial lock invariants, and authorization transitions.
//
// NOTE ON INTENT IDENTITY (2026-09-08): intent ids were previously built by
// string concatenation ("attack-" + a) and INVARIANT 1 tested them with
// id.contains("attack-"). Neither is expressible in Quint: `+` is integer
// addition and there is no string concatenation operator, while `contains` is a
// SET operation, not a substring test. The model therefore never typechecked,
// which means INVARIANT 1 -- the HARD_DENIED_SERIAL storage lock -- was never
// actually verified. Intent identity is now a structured record, so the kind of
// an intent is a first-class field that can be tested directly.

module intent_invariants {
  type EffectDomain = str
  type Actor = str

  // Structured intent identity. `kind` is "int" for an ordinary intent and
  // "attack" for one minted by submitLockedSerialAttack.
  type IntentId = { kind: str, actor: Actor }

  type Token = { actor: Actor, domain: EffectDomain, maxCrit: int, expiresAt: int }
  type Intent = { id: IntentId, actor: Actor, domain: EffectDomain, targetSerial: str, crit: int }

  val VALID_DOMAINS = Set("ReadOnlyTelemetry", "ActorMessage", "PlanMutation", "StorageMutation", "HardwareControl")
  val HARD_DENIED_SERIAL = "25503L801736"
  val ACTORS = Set("claude-worker", "codex-worker", "agy-worker", "unauthorized-actor")

  var authorizedIntents: Set[IntentId]
  var vetoedIntents: Set[IntentId]
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
    val intentId = { kind: "int", actor: a }
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
    val intentId = { kind: "attack", actor: a }
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

  // INVARIANT 1: No attack targeting the locked serial is EVER authorized.
  // Now a direct field test on structured identity rather than a substring
  // search that Quint cannot express.
  val invStorageLockPreserved =
    authorizedIntents.forall(id => id.kind != "attack")

  // INVARIANT 2: An intent cannot be simultaneously authorized and vetoed
  val invDisjointResolution =
    authorizedIntents.intersect(vetoedIntents) == Set()
}
