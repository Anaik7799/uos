//// Coordination and sync layer for distributed agents on top of `uos_tui/board`.
//// - Hierarchical control: a `Policy` says which message kinds each layer (L0 supervisor,
////   L1 integrator/system, L2 worker, L3 verifier) may post and to whom; `Intent` may only
////   travel upward and is never executed here (Rocha cut). Violations are recorded and
////   surfaced as `Andon` messages from the system agent, never silently dropped.
//// - Fenced leases: single-writer leases with monotonically increasing epochs (TwoLattice STM
////   discipline); task claims are leases on `task:<id>`; expiry is explicit.
//// - Freshness: heartbeats per agent with a dead-man's-switch `stale` query.
//// - Ordering: Lamport clock merged with every absorbed remote message.
//// - Sync: reconcile the local ETS/JSONL board with the Zenoh storage (`c3i/a2a/**`), pulling
////   missing messages (digest-verified) and pushing local-only ones.
//// - Sharing: publish key system aspects (audit, KPIs, feature sheet, STPA, FMEA, usage) on
////   `uos/tui/state/<name>` so every agent can GET them from the router.
//// - Resource accounting: per-agent and global token/tool/wall-time usage with relative cost weights.
//// STAMP: SC-TUI-COORD-001, SC-FPP-INTENT-001, TwoLattice_STM.lean (single-writer lease).

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/string
import uos_swarm/board.{
  type Agent, type Board, type Draft, type Kind, type Message, Agent, Draft,
}

// ---------------------------------------------------------------------------
// Hierarchical control
// ---------------------------------------------------------------------------

@external(erlang, "uos_swarm_ffi", "file_append")
fn file_append(path: String, line: String) -> Result(Nil, String)

pub type Layer {
  L0
  L1
  L2
  L3
}

pub fn layer_of(agent: Agent) -> Layer {
  case agent.layer {
    "L0" -> L0
    "L1" -> L1
    "L2" -> L2
    _ -> L3
  }
}

pub fn layer_label(l: Layer) -> String {
  case l {
    L0 -> "L0"
    L1 -> "L1"
    L2 -> "L2"
    L3 -> "L3"
  }
}

pub type Violation {
  UnknownAgent(id: String)
  KindNotAllowed(kind: Kind, layer: Layer)
  TargetNotAllowed(from: String, to: String)
  IntentMustGoUpward(from: String, to: String)
  ControlKeyForbidden(from: String)
  DesignAuthorityRequired(from: String, model: String, kind: Kind)
  DuplicatePayloadKey(key: String)
  LeaseHeldByOther(resource: String, holder: String, epoch: Int)
  WrongEpoch(resource: String, expected: Int, given: Int)
  NoSuchLease(resource: String)
  LeaseExpired(resource: String, expired_us: Int)
  WipLimitReached(limit: Int)
  AckNotRecipient(from: String, target: String)
  DecisionRecordRequired(kind: Kind)
  RouteRecordRequired(kind: Kind)
}

pub fn violation_label(v: Violation) -> String {
  case v {
    DecisionRecordRequired(k) ->
      "kind "
      <> board.kind_label(k)
      <> " needs payload decision_record (uos-decision-record/v1 path)"
    RouteRecordRequired(k) ->
      "kind "
      <> board.kind_label(k)
      <> " needs payload route_class and route_tier (SC-INTEL-ROUTING-001)"
    AckNotRecipient(from, target) ->
      "ack by " <> from <> " on a message not addressed to it: " <> target
    UnknownAgent(id) -> "unknown agent " <> id
    KindNotAllowed(k, l) ->
      board.kind_label(k) <> " not allowed for " <> layer_label(l)
    TargetNotAllowed(f, t) -> f <> " may not address " <> t
    IntentMustGoUpward(f, t) ->
      "intent from " <> f <> " must target L0/L1, not " <> t
    ControlKeyForbidden(f) -> f <> " may not write control keys"
    DesignAuthorityRequired(f, m, k) ->
      f
      <> " ("
      <> m
      <> ") may not post "
      <> board.kind_label(k)
      <> ": design authority is "
      <> "fable-only"
    DuplicatePayloadKey(k) -> "duplicate payload key " <> k
    LeaseHeldByOther(r, h, e) ->
      r <> " held by " <> h <> " epoch " <> int.to_string(e)
    WrongEpoch(r, e, g) ->
      r <> " epoch " <> int.to_string(g) <> " != " <> int.to_string(e)
    NoSuchLease(r) -> "no lease " <> r
    LeaseExpired(r, e) -> "lease " <> r <> " expired at " <> int.to_string(e)
    WipLimitReached(n) -> "wip limit " <> int.to_string(n)
  }
}

pub type Policy {
  Policy(
    roster: List(Agent),
    allowed: List(#(Layer, List(Kind))),
    control_prefix: String,
    wip_limit: Int,
    design_models: List(String),
  )
}

/// Kinds that constitute design decisions: only design-authority models may post them.
pub const design_kinds = [board.Plan, board.Dispatch, board.Integrate]

/// Least privilege by layer. L0 may do everything; L1 runs the line; L2 reports and asks;
/// L3 judges. `Intent` is the only kind that carries a request for a side effect and may only
/// be posted by L2/L3 toward L0/L1 (and by L0/L1 toward L0).
pub fn default_policy(roster: List(Agent), wip_limit: Int) -> Policy {
  Policy(
    roster: roster,
    allowed: [
      #(L0, board.kinds),
      #(L1, [
        board.Plan,
        board.Dispatch,
        board.Integrate,
        board.Andon,
        board.Jidoka,
        board.LeaseGrant,
        board.LeaseRelease,
        board.Heartbeat,
        board.Progress,
        board.Report,
        board.Question,
        board.Answer,
        board.Intent,
      ]),
      #(L2, [
        board.Ack,
        board.Claim,
        board.Progress,
        board.Report,
        board.Question,
        board.Answer,
        board.Heartbeat,
        board.Intent,
      ]),
      #(L3, [
        board.Ack,
        board.Verdict,
        board.Andon,
        board.Jidoka,
        board.Report,
        board.Question,
        board.Answer,
        board.Heartbeat,
        board.Intent,
      ]),
    ],
    control_prefix: "uos/tui/control/",
    wip_limit: wip_limit,
    design_models: ["fable"],
  )
}

fn find_agent(policy: Policy, id: String) -> Option(Agent) {
  policy.roster |> list.find(fn(a) { a.id == id }) |> option.from_result
}

/// L0 outranks L1 outranks L2 outranks L3: L0=0 (highest authority) .. L3=3 (lowest).
fn layer_rank(l: Layer) -> Int {
  case l {
    L0 -> 0
    L1 -> 1
    L2 -> 2
    L3 -> 3
  }
}

/// The first payload key that appears more than once, if any.
fn first_duplicate_key(payload: List(#(String, String))) -> Option(String) {
  list.fold(payload, #([], None), fn(acc, p) {
    let #(seen, found) = acc
    case found {
      Some(_) -> acc
      None ->
        case list.contains(seen, p.0) {
          True -> #(seen, Some(p.0))
          False -> #([p.0, ..seen], None)
        }
    }
  }).1
}

/// Authorize a draft against the policy. Total; never posts.
pub fn authorize(policy: Policy, draft: Draft) -> Result(Nil, Violation) {
  use sender <- result.try(case find_agent(policy, draft.from.id) {
    Some(a) -> Ok(a)
    None -> Error(UnknownAgent(draft.from.id))
  })
  // Duplicate payload keys are refused at the boundary: no ambiguous key/value pairs travel
  // any further into the system.
  use _ <- result.try(case first_duplicate_key(draft.payload) {
    Some(k) -> Error(DuplicatePayloadKey(k))
    None -> Ok(Nil)
  })
  let layer = layer_of(sender)
  let kinds =
    policy.allowed
    |> list.find(fn(p) { p.0 == layer })
    |> result.map(fn(p) { p.1 })
    |> result.unwrap([])
  use _ <- result.try(case list.contains(kinds, draft.kind) {
    True -> Ok(Nil)
    False -> Error(KindNotAllowed(draft.kind, layer))
  })
  // Targets: broadcast, or a rostered agent.
  use _ <- result.try(
    case
      draft.to == "broadcast" || option.is_some(find_agent(policy, draft.to))
    {
      True -> Ok(Nil)
      False -> Error(TargetNotAllowed(draft.from.id, draft.to))
    },
  )
  // Rocha cut: intents go strictly upward — the sender's layer must outrank the target's
  // layer (lower rank number = higher authority), so L0 -> L1 and same-layer intents refuse.
  use _ <- result.try(case draft.kind {
    board.Intent ->
      case find_agent(policy, draft.to) {
        Some(t) ->
          case layer_rank(layer) > layer_rank(layer_of(t)) {
            True -> Ok(Nil)
            False -> Error(IntentMustGoUpward(draft.from.id, draft.to))
          }
        None -> Error(IntentMustGoUpward(draft.from.id, draft.to))
      }
    _ -> Ok(Nil)
  })
  // Control keys (leases, dispatch, integrate) are L0/L1 only.
  use _ <- result.try(
    case
      list.any(draft.payload, fn(p) {
        string.starts_with(p.1, policy.control_prefix)
      }),
      layer
    {
      True, L2 | True, L3 -> Error(ControlKeyForbidden(draft.from.id))
      _, _ -> Ok(Nil)
    },
  )
  // Decision gate (SC-HIVE-DECISION-001): a Plan, Dispatch or Integrate must reference its
  // prepared decision record; a Dispatch must also carry its routing record
  // (SC-INTEL-ROUTING-001). Missing records refuse the action before any effect.
  let has = fn(key: String) {
    case list.key_find(draft.payload, key) {
      Ok(v) -> v != ""
      Error(_) -> False
    }
  }
  use _ <- result.try(case draft.kind {
    board.Plan | board.Dispatch | board.Integrate ->
      case has("decision_record") {
        True -> Ok(Nil)
        False -> Error(DecisionRecordRequired(draft.kind))
      }
    _ -> Ok(Nil)
  })
  use _ <- result.try(case draft.kind {
    board.Dispatch ->
      case has("route_class") && has("route_tier") {
        True -> Ok(Nil)
        False -> Error(RouteRecordRequired(draft.kind))
      }
    _ -> Ok(Nil)
  })
  // Design decisions come only from the design authority (Fable); runtime intelligence is the cheapest tier.
  case
    list.contains(design_kinds, draft.kind)
    && !list.contains(policy.design_models, sender.model)
  {
    True ->
      Error(DesignAuthorityRequired(draft.from.id, sender.model, draft.kind))
    False -> Ok(Nil)
  }
}

// ---------------------------------------------------------------------------
// Leases, claims, heartbeats, clocks, usage
// ---------------------------------------------------------------------------

pub type Lease {
  Lease(
    resource: String,
    holder: String,
    epoch: Int,
    granted_us: Int,
    expires_us: Int,
  )
}

pub type Usage {
  Usage(
    agent: String,
    model: String,
    input_tokens: Int,
    output_tokens: Int,
    cache_read: Int,
    cache_write: Int,
    tool_uses: Int,
    wall_ms: Int,
  )
}

pub type Coord {
  Coord(
    policy: Policy,
    leases: Dict(String, Lease),
    epochs: Dict(String, Int),
    heartbeats: Dict(String, Int),
    lamport: Int,
    usage: Dict(String, Usage),
    violations: List(#(Int, String, Violation)),
    retired: List(String),
  )
}

pub fn new(policy: Policy) -> Coord {
  Coord(policy, dict.new(), dict.new(), dict.new(), 0, dict.new(), [], [])
}

/// Agents that finished their slice are retired: never stale, never expected to beat.
pub fn retire(c: Coord, agent: String) -> Coord {
  Coord(..c, retired: [agent, ..c.retired] |> list.unique)
}

/// Acquire a fenced lease. A live lease held by another holder is refused; an expired or own lease is re-granted with a higher epoch.
pub fn acquire(
  c: Coord,
  resource: String,
  holder: String,
  now_us: Int,
  ttl_us: Int,
) -> Result(#(Coord, Lease), Violation) {
  case dict.get(c.leases, resource) {
    Ok(l) if l.holder != holder && l.expires_us > now_us ->
      Error(LeaseHeldByOther(resource, l.holder, l.epoch))
    _ -> {
      let epoch = dict.get(c.epochs, resource) |> result.unwrap(0) |> int.add(1)
      let lease =
        Lease(resource, holder, epoch, now_us, now_us + int.max(ttl_us, 1))
      Ok(#(
        Coord(
          ..c,
          leases: dict.insert(c.leases, resource, lease),
          epochs: dict.insert(c.epochs, resource, epoch),
        ),
        lease,
      ))
    }
  }
}

/// Renew only with the current epoch (fencing token).
pub fn renew(
  c: Coord,
  resource: String,
  holder: String,
  epoch: Int,
  now_us: Int,
  ttl_us: Int,
) -> Result(#(Coord, Lease), Violation) {
  case dict.get(c.leases, resource) {
    Error(_) -> Error(NoSuchLease(resource))
    Ok(l) if l.holder != holder ->
      Error(LeaseHeldByOther(resource, l.holder, l.epoch))
    Ok(l) if l.epoch != epoch -> Error(WrongEpoch(resource, l.epoch, epoch))
    Ok(l) if l.expires_us <= now_us ->
      Error(LeaseExpired(resource, l.expires_us))
    Ok(l) -> {
      let lease = Lease(..l, expires_us: now_us + int.max(ttl_us, 1))
      Ok(#(Coord(..c, leases: dict.insert(c.leases, resource, lease)), lease))
    }
  }
}

pub fn release(
  c: Coord,
  resource: String,
  holder: String,
  epoch: Int,
) -> Result(Coord, Violation) {
  case dict.get(c.leases, resource) {
    Error(_) -> Error(NoSuchLease(resource))
    Ok(l) if l.holder != holder ->
      Error(LeaseHeldByOther(resource, l.holder, l.epoch))
    Ok(l) if l.epoch != epoch -> Error(WrongEpoch(resource, l.epoch, epoch))
    Ok(_) -> Ok(Coord(..c, leases: dict.delete(c.leases, resource)))
  }
}

/// Drop expired leases; returns them.
pub fn expire(c: Coord, now_us: Int) -> #(Coord, List(Lease)) {
  let expired =
    c.leases |> dict.values |> list.filter(fn(l) { l.expires_us <= now_us })
  let leases =
    list.fold(expired, c.leases, fn(d, l) { dict.delete(d, l.resource) })
  #(Coord(..c, leases: leases), expired)
}

pub fn live_leases(c: Coord, now_us: Int) -> List(Lease) {
  c.leases
  |> dict.values
  |> list.filter(fn(l) { l.expires_us > now_us })
  |> list.sort(fn(a, b) { string.compare(a.resource, b.resource) })
}

/// Claim a task: a lease on `task:<id>` subject to the WIP limit (one claim per agent counts once).
pub fn claim(
  c: Coord,
  task_id: String,
  agent: String,
  now_us: Int,
  ttl_us: Int,
) -> Result(#(Coord, Lease), Violation) {
  let wip =
    live_leases(c, now_us)
    |> list.filter(fn(l) {
      string.starts_with(l.resource, "task:") && l.holder != agent
    })
    |> list.length
  case wip >= c.policy.wip_limit {
    True -> Error(WipLimitReached(c.policy.wip_limit))
    False -> acquire(c, "task:" <> task_id, agent, now_us, ttl_us)
  }
}

/// Raise `c.epochs` to the maximum epoch seen in `messages` for each resource, so a fresh
/// coordinator that reconciles against the board can never hand out a stale (already-issued)
/// epoch after a restart. Scans `board.LeaseGrant` and `board.Claim` messages for the payload
/// keys `resource` and `epoch` (the same keys `acquire`'s `LeaseGrant` draft and a `Claim`
/// draft already carry — see `claim_ok` below). Messages missing either key, or with a
/// non-integer epoch, are ignored.
pub fn seed_epochs(c: Coord, messages: List(board.Message)) -> Coord {
  let epochs =
    list.fold(messages, c.epochs, fn(epochs, m) {
      case m.kind {
        board.LeaseGrant | board.Claim -> {
          let resource =
            m.payload
            |> list.find(fn(p) { p.0 == "resource" })
            |> result.map(fn(p) { p.1 })
            |> result.unwrap("")
          let epoch =
            m.payload
            |> list.find(fn(p) { p.0 == "epoch" })
            |> result.map(fn(p) { p.1 })
            |> result.try(int.parse)
            |> result.unwrap(-1)
          case resource {
            "" -> epochs
            _ ->
              case epoch >= 0 {
                False -> epochs
                True -> {
                  let prev = dict.get(epochs, resource) |> result.unwrap(0)
                  dict.insert(epochs, resource, int.max(prev, epoch))
                }
              }
          }
        }
        _ -> epochs
      }
    })
  Coord(..c, epochs: epochs)
}

pub fn beat(c: Coord, agent: String, now_us: Int) -> Coord {
  Coord(..c, heartbeats: dict.insert(c.heartbeats, agent, now_us))
}

/// Dead-man's switch: agents whose last heartbeat is older than `ttl_us` (or never seen among the roster).
pub fn stale(c: Coord, now_us: Int, ttl_us: Int) -> List(String) {
  c.policy.roster
  |> list.map(fn(a) { a.id })
  |> list.filter(fn(id) { !list.contains(c.retired, id) })
  |> list.filter(fn(id) {
    case dict.get(c.heartbeats, id) {
      Ok(t) -> now_us - t > ttl_us
      Error(_) -> True
    }
  })
}

pub fn tick(c: Coord) -> #(Coord, Int) {
  let l = c.lamport + 1
  #(Coord(..c, lamport: l), l)
}

/// Receiving a message is a Lamport event: the clock becomes max(local, received) + 1.
/// Lamport order is causal and is never equated with wall time (`ts_us` is separate).
pub fn merge_clock(c: Coord, remote: Int) -> Coord {
  Coord(..c, lamport: int.max(c.lamport, remote) + 1)
}

pub fn record_usage(c: Coord, u: Usage) -> Coord {
  let merged = case dict.get(c.usage, u.agent) {
    Ok(prev) ->
      Usage(
        ..prev,
        input_tokens: prev.input_tokens + u.input_tokens,
        output_tokens: prev.output_tokens + u.output_tokens,
        cache_read: prev.cache_read + u.cache_read,
        cache_write: prev.cache_write + u.cache_write,
        tool_uses: prev.tool_uses + u.tool_uses,
        wall_ms: prev.wall_ms + u.wall_ms,
      )
    Error(_) -> u
  }
  Coord(..c, usage: dict.insert(c.usage, u.agent, merged))
}

pub fn global_usage(c: Coord) -> Usage {
  c.usage
  |> dict.values
  |> list.fold(Usage("global", "mixed", 0, 0, 0, 0, 0, 0), fn(acc, u) {
    Usage(
      ..acc,
      input_tokens: acc.input_tokens + u.input_tokens,
      output_tokens: acc.output_tokens + u.output_tokens,
      cache_read: acc.cache_read + u.cache_read,
      cache_write: acc.cache_write + u.cache_write,
      tool_uses: acc.tool_uses + u.tool_uses,
      wall_ms: int.max(acc.wall_ms, u.wall_ms),
    )
  })
}

/// Relative cost in weight units (not currency): weights per model tier for (input+cache_write, output, cache_read).
pub fn weighted_cost(
  u: Usage,
  weights: List(#(String, #(Float, Float, Float))),
) -> Float {
  let #(wi, wo, wc) =
    weights
    |> list.find(fn(w) { w.0 == u.model })
    |> result.map(fn(w) { w.1 })
    |> result.unwrap(#(1.0, 1.0, 1.0))
  int.to_float(u.input_tokens + u.cache_write)
  *. wi
  +. int.to_float(u.output_tokens)
  *. wo
  +. int.to_float(u.cache_read)
  *. wc
}

/// Default relative weights: sonnet 1.0/1.0/0.1, haiku 0.27/0.27/0.03, fable 5.0/5.0/0.5 (per token, relative to sonnet input). Documented as relative units.
pub const default_weights = [
  #("sonnet", #(1.0, 5.0, 0.1)),
  #("haiku", #(0.27, 1.33, 0.027)),
  #("opus", #(5.0, 25.0, 0.5)),
  #("fable", #(5.0, 25.0, 0.5)),
]

pub fn usage_rows(c: Coord) -> List(List(String)) {
  c.usage
  |> dict.values
  |> list.sort(fn(a, b) { string.compare(a.agent, b.agent) })
  |> list.map(fn(u) {
    [
      u.agent,
      u.model,
      int.to_string(u.input_tokens),
      int.to_string(u.output_tokens),
      int.to_string(u.cache_read),
      int.to_string(u.tool_uses),
      int.to_string(u.wall_ms / 1000) <> "s",
      float.to_string(float_round2(weighted_cost(u, default_weights))),
    ]
  })
}

fn float_round2(f: Float) -> Float {
  int.to_float(float.round(f *. 100.0)) /. 100.0
}

pub fn usage_json(c: Coord) -> Json {
  let g = global_usage(c)
  json.object([
    #("global", usage_to_json(g)),
    #(
      "relative_cost_units",
      json.float(float_round2(
        c.usage
        |> dict.values
        |> list.fold(0.0, fn(acc, u) {
          acc +. weighted_cost(u, default_weights)
        }),
      )),
    ),
    #(
      "agents",
      json.array(
        c.usage
          |> dict.values
          |> list.sort(fn(a, b) { string.compare(a.agent, b.agent) }),
        usage_to_json,
      ),
    ),
  ])
}

fn usage_to_json(u: Usage) -> Json {
  json.object([
    #("agent", json.string(u.agent)),
    #("model", json.string(u.model)),
    #("input_tokens", json.int(u.input_tokens)),
    #("output_tokens", json.int(u.output_tokens)),
    #("cache_read", json.int(u.cache_read)),
    #("cache_write", json.int(u.cache_write)),
    #("tool_uses", json.int(u.tool_uses)),
    #("wall_ms", json.int(u.wall_ms)),
    #(
      "relative_cost_units",
      json.float(float_round2(weighted_cost(u, default_weights))),
    ),
  ])
}

// ---------------------------------------------------------------------------
// Guarded posting, sync, sharing
// ---------------------------------------------------------------------------

pub const system_agent = Agent("uos-coord", "L1", "system")

/// Authorize, then post. A violation is recorded and announced as an Andon from the system agent.
pub fn post(
  b: Board,
  c: Coord,
  draft: Draft,
) -> #(Board, Coord, Result(Message, Violation)) {
  case authorize(c.policy, draft) |> result.try(fn(_) { claim_ok(c, draft) }) {
    Ok(_) -> {
      let #(c, _) = tick(c)
      let #(b, m) = board.post(b, draft)
      // A posted message is liveness evidence for its sender.
      #(b, beat(c, draft.from.id, m.ts_us), Ok(m))
    }
    Error(v) -> {
      let #(c, l) = tick(c)
      let andon =
        Draft(
          system_agent,
          "broadcast",
          board.Andon,
          [
            #("violation", violation_label(v)),
            #("offender", draft.from.id),
            #("attempted_kind", board.kind_label(draft.kind)),
          ],
          board.Semantics(
            ["17 Aspect audit"],
            [1, 8],
            ["CA-emit_intent"],
            ["Defects"],
            1,
          ),
          board.Causality(None, []),
          None,
          None,
        )
      let #(b, _) = board.post(b, andon)
      #(
        b,
        Coord(..c, violations: [#(l, draft.from.id, v), ..c.violations]),
        Error(v),
      )
    }
  }
}

pub type SyncReport {
  SyncReport(
    pulled: Int,
    pushed: Int,
    push_rejected: Int,
    digest_rejected: Int,
    remote_total: Int,
    local_total: Int,
    policy_rejected: Int,
    signature_rejected: Int,
    conflicts: Int,
    chain_rejected: Int,
  )
}

/// Re-derive the draft a remote message claims to be and authorize it against our policy.
/// Recipient self-ACK rule: L0/L1 may acknowledge anything; every other sender may only
/// acknowledge a message addressed to it or broadcast. A target absent from the local
/// ledger is accepted only when an explicit causal-gap record documents it (the gap stays
/// visible; it is never treated as restored history).
pub fn ack_target_ok(
  policy: Policy,
  m: Message,
  local: List(Message),
) -> Result(Nil, Violation) {
  case m.kind {
    board.Ack ->
      case find_agent(policy, m.from.id) |> option.map(layer_of) {
        Some(L0) | Some(L1) -> Ok(Nil)
        _ -> {
          let target = case m.causality.in_reply_to {
            Some(id) -> id
            None -> list.key_find(m.payload, "ack") |> result.unwrap("")
          }
          case list.find(local, fn(x) { x.id == target }) {
            Ok(x) ->
              case x.to == m.from.id || x.to == "broadcast" {
                True -> Ok(Nil)
                False -> Error(AckNotRecipient(m.from.id, target))
              }
            Error(_) ->
              case list.contains(board.causal_gaps(local), target) {
                True -> Ok(Nil)
                False -> Error(AckNotRecipient(m.from.id, target))
              }
          }
        }
      }
    _ -> Ok(Nil)
  }
}

pub fn authorize_message(policy: Policy, m: Message) -> Result(Nil, Violation) {
  authorize(
    policy,
    Draft(
      m.from,
      m.to,
      m.kind,
      m.payload,
      m.semantics,
      m.causality,
      Some(m.trace_id),
      m.parent_span_id,
    ),
  )
}

/// Pure set reconciliation: which remote messages are missing locally (digest-verified) and vice versa.
pub fn diff_sets(
  local: List(Message),
  remote: List(Message),
) -> #(List(Message), List(Message), List(String)) {
  let lids = list.map(local, fn(m) { m.id })
  let rids = list.map(remote, fn(m) { m.id })
  let #(missing_local, rejected) =
    list.fold(remote, #([], []), fn(acc, m) {
      case list.contains(lids, m.id), board.digest_ok(m) {
        True, _ -> acc
        False, True -> #([m, ..acc.0], acc.1)
        False, False -> #(acc.0, [m.id, ..acc.1])
      }
    })
  let missing_remote = list.filter(local, fn(m) { !list.contains(rids, m.id) })
  #(list.reverse(missing_local), missing_remote, list.reverse(rejected))
}

/// Among `remote` messages whose id already exists in `local`, count those whose digest
/// differs from the local copy's. These are conflicts: quarantined by refusal (never absorbed
/// — the local copy stays authoritative), not silently dropped.
pub fn count_conflicts(local: List(Message), remote: List(Message)) -> Int {
  list.count(remote, fn(m) {
    case list.find(local, fn(l) { l.id == m.id }) {
      Ok(l) -> l.digest != m.digest
      Error(_) -> False
    }
  })
}

/// Among local-only messages destined for the shared Zenoh store, keep only those that
/// would themselves survive the pull-side gates this same board enforces on every other
/// peer: a self-consistent digest, policy authorization, and (when the board is keyed) a
/// valid signature. A hand-shaped or tampered local row must never reach the shared store —
/// pushing it would hand every other peer evidence this board itself would refuse to absorb
/// on the way back in.
pub fn filter_pushable(
  policy: Policy,
  key: Option(String),
  push: List(Message),
) -> #(List(Message), Int) {
  list.partition(push, fn(m) {
    board.digest_ok(m)
    && authorize_message(policy, m) == Ok(Nil)
    && case key {
      Some(_) -> board.signature_ok(m, key)
      None -> True
    }
  })
  |> fn(p) { #(p.0, list.length(p.1)) }
}

/// Reconcile the local board with the Zenoh storage: pull missing (verified) messages, push local-only ones.
pub fn reconcile(
  b: Board,
  c: Coord,
) -> Result(#(Board, Coord, SyncReport), String) {
  use base <- result.try(option.to_result(
    b.zenoh_base,
    "no zenoh base configured",
  ))
  use remote <- result.try(board.zenoh_fetch(base))
  let local = board.timeline(b)
  let #(pull, push, rejected) = diff_sets(local, remote)
  let pull = list.sort(pull, fn(x, y) { string.compare(x.id, y.id) })
  let conflicts = count_conflicts(local, remote)
  // Every pulled message must pass policy (forgery of a higher layer is refused) and, when keyed, the signature.
  let #(pull, policy_rejected) =
    list.partition(pull, fn(m) {
      authorize_message(c.policy, m) == Ok(Nil)
      && ack_target_ok(c.policy, m, local) == Ok(Nil)
    })
    |> fn(p) { #(p.0, list.length(p.1)) }
  let #(pull, signature_rejected) = case b.key {
    Some(_) ->
      list.partition(pull, fn(m) { board.signature_ok(m, b.key) })
      |> fn(p) { #(p.0, list.length(p.1)) }
    None -> #(pull, 0)
  }
  // Absorb one by one so a message whose per-sender predecessor is not our head
  // (a forked or gapped chain, e.g. one sender writing from two ledger copies) is
  // counted and quarantined instead of vanishing silently. The quarantine file sits
  // beside the ledger; the message is never rewritten and never treated as absorbed.
  let #(b, chain_rejected) =
    list.fold(pull, #(b, 0), fn(acc, m) {
      let #(b, n) = acc
      let b2 = board.absorb(b, m)
      // Absorbed but not extending the sender's head: a fork or a gap in that chain.
      let extended = dict.get(b2.heads, m.from.id) == Ok(m.digest)
      case !extended {
        True -> {
          let _ = case b.ledger_path {
            Some(path) ->
              file_append(
                path <> ".chain-forks.jsonl",
                board.to_string(m) <> "\n",
              )
            None -> Ok(Nil)
          }
          #(b2, n + 1)
        }
        False -> #(b2, n)
      }
    })
  let c = list.fold(pull, c, fn(c, m) { merge_clock(c, m.lamport) })
  // Never hand out a stale epoch: raise `c.epochs` to whatever the board already shows.
  let c = seed_epochs(c, pull)
  // Never push a local-only row the pull path would itself refuse: the same digest,
  // policy and (when keyed) signature gates apply symmetrically before anything leaves
  // this board for the shared store.
  let #(pushable, push_rejected) = filter_pushable(c.policy, b.key, push)
  let pushed =
    list.count(pushable, fn(m) {
      board.zenoh_put(base, m.key_expr, board.to_string(m)) == Ok(Nil)
    })
  Ok(#(
    b,
    c,
    SyncReport(
      list.length(pull),
      pushed,
      push_rejected,
      list.length(rejected),
      list.length(remote),
      list.length(local),
      policy_rejected,
      signature_rejected,
      conflicts,
      chain_rejected,
    ),
  ))
}

/// Publish key system aspects on `uos/tui/state/<name>` so every agent can GET them.
pub fn share_state(
  base: String,
  entries: List(#(String, Json)),
) -> #(Int, List(String)) {
  list.fold(entries, #(0, []), fn(acc, e) {
    case board.zenoh_put(base, "uos/tui/state/" <> e.0, json.to_string(e.1)) {
      Ok(_) -> #(acc.0 + 1, acc.1)
      Error(err) -> #(acc.0, [e.0 <> ": " <> err, ..acc.1])
    }
  })
}

/// Live proof of at-least-once delivery with acknowledgement: sender board A posts to a recipient,
/// a fresh recipient board B (own ETS table, no ledger) pulls from Zenoh, finds it in its inbox,
/// acknowledges, and A observes the acknowledgement after its own sync. Every step is real I/O.
pub type Proof {
  Proof(
    sent: String,
    seen_in_inbox: Bool,
    acked: Bool,
    sender_saw_ack: Bool,
    state: String,
  )
}

pub fn prove_delivery(a: Board, recipient: Agent) -> Result(Proof, String) {
  use base <- result.try(option.to_result(
    a.zenoh_base,
    "no zenoh base configured",
  ))
  let #(a, sent) =
    board.post(
      a,
      Draft(
        Agent("L0-fable", "L0", "fable"),
        recipient.id,
        board.Question,
        [#("probe", "delivery-proof")],
        board.Semantics(
          ["Message / Event"],
          [10, 13],
          ["CA-emit_intent"],
          [],
          0,
        ),
        board.Causality(None, []),
        None,
        None,
      ),
    )
  use b <- result.try(board.open(
    a.swarm,
    "uos_tui_board_proof_" <> recipient.id,
    None,
    Some(base),
  ))
  use remote <- result.try(board.zenoh_fetch(base))
  let remote = list.sort(remote, fn(x, y) { string.compare(x.id, y.id) })
  let b = list.fold(remote, b, board.absorb)
  let seen =
    board.inbox(board.timeline(b), recipient.id)
    |> list.any(fn(m) { m.id == sent.id })
  let #(_, ackm) = board.ack(b, recipient, sent.id)
  let acked =
    list.any(ackm.deliveries, fn(d) {
      string.starts_with(d.transport, "zenoh") && d.status == board.Delivered
    })
  use remote2 <- result.try(board.zenoh_fetch(base))
  let remote2 = list.sort(remote2, fn(x, y) { string.compare(x.id, y.id) })
  let a = list.fold(remote2, a, board.absorb)
  let tl = board.timeline(a)
  let saw = board.acked_by(tl, sent.id, recipient.id)
  Ok(Proof(
    sent.id,
    seen,
    acked,
    saw,
    board.state_label(board.delivery_state(tl, sent)),
  ))
}

pub fn state_url(base: String, name: String) -> String {
  base <> "/uos/tui/state/" <> name
}

// ---------------------------------------------------------------------------
// OTP actor (supervisable)
// ---------------------------------------------------------------------------

pub type Msg {
  Post(Draft, Subject(Result(Message, Violation)))
  Beat(String)
  Acquire(String, String, Int, Subject(Result(Lease, Violation)))
  Release(String, String, Int, Subject(Result(Nil, Violation)))
  Tick
  Reconcile(Subject(Result(SyncReport, String)))
  Snapshot(Subject(#(List(Message), Coord)))
  Stop
}

type State {
  State(
    board: Board,
    coord: Coord,
    now: fn() -> Int,
    lease_ttl_us: Int,
    heartbeat_ttl_us: Int,
    self: Subject(Msg),
    tick_ms: Int,
  )
}

/// Start the coordinator actor and return only its message subject, for callers that do not
/// need the pid directly. Prefer `start_actor` when the pid is needed (e.g. supervision).
pub fn start(
  b: Board,
  c: Coord,
  tick_ms: Int,
) -> Result(Subject(Msg), actor.StartError) {
  start_actor(b, c, tick_ms) |> result.map(fn(started) { started.data })
}

/// Start the coordinator actor, returning the real actor pid alongside its message subject.
/// The actor owns its own tick timer: the initialiser and every `Tick` handler schedule the
/// next one with `process.send_after`, so no detached process is spawned and nothing is left
/// running (or double-ticking) once the actor stops.
pub fn start_actor(
  b: Board,
  c: Coord,
  tick_ms: Int,
) -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  let ms = int.max(tick_ms, 50)
  actor.new_with_initialiser(1000, fn(self) {
    process.send_after(self, ms, Tick)
    State(b, c, board.system_time_us, 300_000_000, 120_000_000, self, ms)
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// A supervisable child specification. Uses `start_actor` so the supervisor monitors the
/// actor's real pid rather than the caller's.
pub fn child_spec(
  b: Board,
  c: Coord,
  tick_ms: Int,
) -> ChildSpecification(Subject(Msg)) {
  supervision.worker(fn() { start_actor(b, c, tick_ms) })
}

fn handle(s: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Post(draft, reply) -> {
      let #(b, c, r) = post(s.board, s.coord, draft)
      process.send(reply, r)
      actor.continue(State(..s, board: b, coord: c))
    }
    Beat(agent) ->
      actor.continue(State(..s, coord: beat(s.coord, agent, s.now())))
    Acquire(resource, holder, ttl, reply) -> {
      case acquire(s.coord, resource, holder, s.now(), ttl) {
        Ok(#(c, lease)) -> {
          let grant =
            Draft(
              system_agent,
              holder,
              board.LeaseGrant,
              [#("resource", resource), #("epoch", int.to_string(lease.epoch))],
              board.Semantics([], [17], ["CA-integrate_slice"], [], 1),
              board.Causality(None, []),
              None,
              None,
            )
          let #(b, _) = board.post(s.board, grant)
          process.send(reply, Ok(lease))
          actor.continue(State(..s, board: b, coord: c))
        }
        Error(v) -> {
          process.send(reply, Error(v))
          actor.continue(s)
        }
      }
    }
    Release(resource, holder, epoch, reply) -> {
      case release(s.coord, resource, holder, epoch) {
        Ok(c) -> {
          process.send(reply, Ok(Nil))
          actor.continue(State(..s, coord: c))
        }
        Error(v) -> {
          process.send(reply, Error(v))
          actor.continue(s)
        }
      }
    }
    Tick -> {
      let #(c, _) = expire(s.coord, s.now())
      process.send_after(s.self, s.tick_ms, Tick)
      actor.continue(State(..s, coord: c))
    }
    Reconcile(reply) -> {
      case reconcile(s.board, s.coord) {
        Ok(#(b, c, report)) -> {
          process.send(reply, Ok(report))
          actor.continue(State(..s, board: b, coord: c))
        }
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(s)
        }
      }
    }
    Snapshot(reply) -> {
      process.send(reply, #(board.timeline(s.board), s.coord))
      actor.continue(s)
    }
    Stop -> actor.stop()
  }
}

/// Forgery probe: a message claiming L0 authority injected via the transport must be refused by
/// reconcile (policy: the roster decides the layer; signature: the attacker has no key).
pub fn forgery_probe(
  b: Board,
  c: Coord,
) -> Result(#(Bool, SyncReport), String) {
  use base <- result.try(option.to_result(
    b.zenoh_base,
    "no zenoh base configured",
  ))
  let forged =
    board.seal(
      Draft(
        Agent("L0-fable", "L0", "fable"),
        "broadcast",
        board.Dispatch,
        [#("command", "halt_production")],
        board.Semantics(["App"], [1], [], [], 0),
        board.Causality(None, []),
        None,
        None,
      ),
      b.swarm,
      board.system_time_us(),
      999_999,
      "f0f0f0f0f0f0f0f0",
      board.head_of(b, "L0-fable"),
    )
  use _ <- result.try(board.zenoh_put(
    base,
    forged.key_expr,
    board.to_string(forged),
  ))
  use #(b2, _, report) <- result.try(reconcile(b, c))
  let absorbed = list.any(board.timeline(b2), fn(m) { m.id == forged.id })
  Ok(#(!absorbed, report))
}

/// A Claim must carry the epoch of a live lease held by the sender (board-level fencing).
fn claim_ok(c: Coord, draft: Draft) -> Result(Nil, Violation) {
  case draft.kind {
    board.Claim -> {
      let epoch =
        draft.payload
        |> list.find(fn(p) { p.0 == "epoch" })
        |> result.map(fn(p) { p.1 })
        |> result.try(int.parse)
        |> result.unwrap(-1)
      let resource =
        draft.payload
        |> list.find(fn(p) { p.0 == "resource" })
        |> result.map(fn(p) { p.1 })
        |> result.unwrap("")
      case dict.get(c.leases, resource) {
        Ok(l) if l.holder == draft.from.id && l.epoch == epoch -> Ok(Nil)
        Ok(l) if l.holder != draft.from.id ->
          Error(LeaseHeldByOther(resource, l.holder, l.epoch))
        Ok(l) -> Error(WrongEpoch(resource, l.epoch, epoch))
        Error(_) -> Error(NoSuchLease(resource))
      }
    }
    _ -> Ok(Nil)
  }
}
