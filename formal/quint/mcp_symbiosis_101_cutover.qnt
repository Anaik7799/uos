// Finite transition abstraction, not extracted implementation or crypto proof.
// Production receive idle deadline is 30s; health freshness window is 60s.
module mcp_symbiosis_101_cutover {
  val Agents = Set("agy", "claude", "codex", "pi")
  val Transports = Set("stdio", "http", "zenoh")
  val Surfaces = 0.to(10)
  val Capsule = "capsule1811-verified"
  type ReceiptLedger = str -> str
  type State = {
    ledger: ReceiptLedger, verified: Set[str], subscribers: Set[str],
    pins: int -> str, effects: int, forgedMutation: bool,
    uncertainReplay: bool, mismatchEffect: bool, evCeiling: int,
    applicationAdmitted: bool, now: int, lastChunk: int, connected: bool,
  }
  var s: State
  val initial = {
    ledger: Agents.mapBy(a => "Prepared"), verified: Set(), subscribers: Set(),
    pins: Surfaces.mapBy(i => Capsule), effects: 0, forgedMutation: false,
    uncertainReplay: false, mismatchEffect: false, evCeiling: 93,
    applicationAdmitted: false, now: 0, lastChunk: 0, connected: false,
  }
  action init = s' = initial
  def coherent(pins: int -> str): bool = Surfaces.forall(i => pins.get(i) == Capsule)
  def authenticated(t: str, bearer: bool, hmac: bool): bool =
    Transports.contains(t) and (t != "http" or bearer) and (t != "zenoh" or hmac)
  action call(a: str, t: str, bearer: bool, hmac: bool): bool = {
    val allowed = coherent(s.pins) and authenticated(t, bearer, hmac)
    val execute = allowed and s.ledger.get(a) == "Prepared"
    val terminal = allowed and Set("Committed", "Reconciled").contains(s.ledger.get(a))
    val ledgerNext = if (execute) s.ledger.set(a, "Committed") else s.ledger
    s' = s.with("ledger", ledgerNext)
      .with("verified", if (execute or terminal) s.verified.union(Set(a)) else s.verified)
      .with("effects", s.effects + (if (execute) 1 else 0))
      .with("forgedMutation", s.forgedMutation or (t == "zenoh" and not(hmac) and ledgerNext != s.ledger))
      .with("uncertainReplay", s.uncertainReplay or (s.ledger.get(a) == "Uncertain" and execute))
      .with("mismatchEffect", s.mismatchEffect or (not(coherent(s.pins)) and execute))
  }
  action acquire(a: str, stdioMode: bool): bool =
    s' = if (s.subscribers == Set() and not(stdioMode))
      s.with("subscribers", Set(a)) else s
  action disconnect = s' = s.with("subscribers", Set()).with("connected", false)
  action reconnect = s' = if (s.subscribers.size() == 1)
    s.with("connected", true).with("lastChunk", s.now) else s
  action tick = {
    val nextTime = s.now + 31000
    s' = s.with("now", nextTime).with("connected", if (nextTime - s.lastChunk > 30000) false else s.connected)
  }
  action makeUncertain(a: str): bool = s' = if (s.ledger.get(a) == "Prepared")
    s.with("ledger", s.ledger.set(a, "Uncertain")) else s
  action reconcile(a: str): bool = s' = if (s.ledger.get(a) == "Uncertain")
    s.with("ledger", s.ledger.set(a, "Reconciled")) else s
  action changePin(i: int, good: bool): bool =
    s' = s.with("pins", s.pins.set(i, if (good) Capsule else "mismatch"))
  action step = {
    nondet a = oneOf(Agents)
    nondet t = oneOf(Transports)
    nondet b = oneOf(Set(true, false))
    nondet i = oneOf(Surfaces)
    any { call(a,t,b,b), acquire(a,b), disconnect, reconnect, tick,
          makeUncertain(a), reconcile(a), changePin(i,b) }
  }
  val invAtMostOneZenohSubscriber = s.subscribers.size() <= 1
  val invForgedHmacNeverMutatesLedger = not(s.forgedMutation)
  val invUncertainNeverBlindlyReplayed = not(s.uncertainReplay)
  val invPinMismatchRefused = not(s.mismatchEffect)
  val invEvCeiling93Preserved = s.evCeiling == 93 and not(s.applicationAdmitted)
  val invNegativeControlNoAllFourAgentsComplete = s.verified != Agents
  run allFourReachable = init.then(call("agy","stdio",true,true))
    .then(call("claude","http",true,true)).then(call("codex","zenoh",true,true))
    .then(call("pi","stdio",true,true)).expect(s.verified == Agents)
  run forgedHmacControl = init.then(call("codex","zenoh",true,false))
    .expect(s.ledger == initial.ledger and s.effects == 0)
  run uncertainControl = init.then(makeUncertain("codex"))
    .then(call("codex","stdio",true,true)).expect(s.effects == 0 and s.ledger.get("codex") == "Uncertain")
  run pinControl = init.then(changePin(0,false)).then(call("codex","http",true,true))
    .expect(s.effects == 0 and s.verified == Set())
}
