//// Pure H0-H3 policy DATA. No process, admission, grant, billing or custody IO.
//// A caller must retain one current State; immutable branching is not distributed
//// atomicity. An authenticated OTP owner/durable store is not implemented here.

import cepaf_gleam/harness/agent_capabilities as agents
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Role {
  H0Program
  H1Subsystem
  H2Worker
  H3Review
}

pub opaque type Layer {
  Layer(Int)
}

pub fn layer(value: Int) -> Result(Layer, String) {
  case value >= 0 && value <= 9 {
    True -> Ok(Layer(value))
    False -> Error("L coordinate outside 0..9")
  }
}

pub fn layer_number(value: Layer) -> Int {
  let Layer(n) = value
  n
}

pub fn roles() -> List(Role) {
  [H0Program, H1Subsystem, H2Worker, H3Review]
}

pub fn role_name(value: Role) -> String {
  case value {
    H0Program -> "H0 program"
    H1Subsystem -> "H1 subsystem"
    H2Worker -> "H2 worker"
    H3Review -> "H3 review DATA"
  }
}

pub fn role_depth(value: Role) -> Int {
  case value {
    H0Program -> 0
    H1Subsystem -> 1
    H2Worker -> 2
    H3Review -> 3
  }
}

pub fn effect_authority() -> Bool {
  False
}

pub fn summary() -> String {
  "H0-H3 pure policy DATA; independent L0-L9 coordinates; authority NONE; runtime owner UNIMPLEMENTED. Configurable depth/fanout/slots; example defaults D=3,F=2,slots=4 are not performance claims. READY queue/fairness/runtime availability UNIMPLEMENTED."
}

pub opaque type Config {
  Config(depth: Int, fanout: Int, slots: Int, retained_nodes: Int)
}

/// Allocation bounds, not measured performance or deployment policy. The H
/// vocabulary ends at H3; fanout/storage remain explicitly configurable.
pub fn config(
  depth: Int,
  fanout: Int,
  slots: Int,
  retained_nodes: Int,
) -> Result(Config, String) {
  case
    depth >= 0
    && depth <= 3
    && fanout >= 1
    && fanout <= 8
    && slots >= 1
    && slots <= 1024
    && retained_nodes >= slots
    && retained_nodes <= 1024
  {
    True -> Ok(Config(depth, fanout, slots, retained_nodes))
    False -> Error("configuration outside bounded allocation envelope")
  }
}

/// Illustrative starting values only; caller controls config within bounds.
pub fn default_config() -> Config {
  Config(3, 2, 4, 64)
}

pub fn tree_capacity(c: Config) -> Int {
  tree_sum(c.depth, c.fanout, 1)
}

fn tree_sum(depth: Int, fanout: Int, width: Int) -> Int {
  case depth {
    0 -> width
    _ -> width + tree_sum(depth - 1, fanout, width * fanout)
  }
}

/// Resource and budget slots are untrusted observations, not monetary amounts
/// or authority. Missing data is an error; zero slots gives zero capacity.
pub fn capacity(
  c: Config,
  resource: Option(Int),
  budget: Option(Int),
) -> Result(Int, String) {
  case resource, budget {
    Some(r), Some(b) if r >= 0 && r <= 1024 && b >= 0 && b <= 1024 ->
      Ok(int.min(c.slots, int.min(tree_capacity(c), int.min(r, b))))
    _, _ -> Error("UNKNOWN or invalid capacity observation")
  }
}

/// Exact labels, not authenticated principal/epoch credentials.
pub type FenceData {
  FenceData(owner: String, epoch: Int, revision: Int)
}

pub opaque type State {
  State(
    config: Config,
    fence: FenceData,
    notes: List(String),
    nodes: List(NodeData),
    checked_clock: Option(ClockData),
    capacity_observation: Option(CapacityObservationData),
    hold_reason: Option(String),
  )
}

pub fn new(c: Config, owner: String, epoch: Int) -> Result(State, String) {
  case valid_label(owner) && epoch > 0 && epoch <= 1_000_000_000 {
    True -> Ok(State(c, FenceData(owner, epoch, 0), [], [], None, None, None))
    False -> Error("invalid owner/epoch DATA")
  }
}

fn valid_label(value: String) -> Bool {
  string.byte_size(value) > 0
  && string.byte_size(value) <= 128
  && !string.contains(value, "\u{0000}")
}

pub fn fence_data(s: State) -> FenceData {
  s.fence
}

pub fn check_fence(s: State, expected: FenceData) -> Result(Nil, String) {
  case s.fence == expected && revision_capacity(expected, 1) {
    True -> Ok(Nil)
    False -> Error("stale or exhausted owner/epoch/revision DATA")
  }
}

/// Checked integer headroom for at most three local updates. DATA only.
pub fn revision_capacity(f: FenceData, updates: Int) -> Bool {
  updates >= 1
  && updates <= 3
  && f.revision >= 0
  && f.revision <= 1_000_000_000 - updates
}

/// A bounded audit note increments the pure revision; no evidence authentication.
pub fn note(
  s: State,
  expected: FenceData,
  value: String,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  case
    valid_label(value)
    && list.length(s.notes) < 32
    && !list.contains(s.notes, value)
  {
    True ->
      Ok(
        State(
          ..s,
          fence: FenceData(..s.fence, revision: s.fence.revision + 1),
          notes: [value, ..s.notes],
        ),
      )
    False -> Error("invalid, duplicate or exhausted note")
  }
}

/// Optional note lookup; UNKNOWN is never an authority constructor.
pub fn latest_note(s: State) -> Option(String) {
  case s.notes {
    [] -> None
    [n, ..] -> Some(n)
  }
}

pub type Phase {
  Reserved
  Starting
  Running
  Cancelling
  CleanupUnknown
  Released
}

pub type NodeData {
  NodeData(
    id: String,
    parent: Option(String),
    role: Role,
    agent: agents.Agent,
    phase: Phase,
    scope: Option(ScopeData),
    liability: LiabilityData,
    cost_mode: CostModeData,
    cleanup_ref: Option(String),
    custody: Option(CustodyData),
    review_receipt: Option(String),
  )
}

pub fn nodes(s: State) -> List(NodeData) {
  s.nodes
}

pub fn used(s: State) -> Int {
  list.count(s.nodes, fn(n) { active(n.phase) })
}

pub fn children_used(s: State, parent: String) -> Int {
  list.count(s.nodes, fn(n) { n.parent == Some(parent) && active(n.phase) })
}

fn node(s: State, id: String) -> Result(NodeData, String) {
  list.find(s.nodes, fn(n) { n.id == id })
  |> result.map_error(fn(_) { "unknown node" })
}

pub fn reserve_root(
  s: State,
  expected: FenceData,
  id: String,
  agent: agents.Agent,
  resource: Option(Int),
  budget: Option(Int),
  now: ClockData,
) -> Result(State, String) {
  case list.any(s.nodes, fn(n) { n.role == H0Program }) {
    True -> Error("root already retained")
    False ->
      reserve(s, expected, id, None, H0Program, agent, resource, budget, now)
  }
}

/// One immutable-State transition checks both global and parent capacity.
/// It cannot serialize two actors holding separate copies of the same State.
pub fn reserve_child(
  s: State,
  expected: FenceData,
  parent: String,
  id: String,
  agent: agents.Agent,
  resource: Option(Int),
  budget: Option(Int),
  now: ClockData,
) -> Result(State, String) {
  use p <- result.try(node(s, parent))
  use _ <- result.try(case p.phase == Running {
    True -> live_scope(s, p, now)
    False -> Error("parent is not delegation-eligible Running DATA")
  })
  use role <- result.try(case p.role {
    H0Program -> Ok(H1Subsystem)
    H1Subsystem -> Ok(H2Worker)
    H2Worker | H3Review -> Error("no ordinary delegation from worker/reviewer")
  })
  reserve(s, expected, id, Some(parent), role, agent, resource, budget, now)
}

fn reserve(
  s: State,
  expected: FenceData,
  id: String,
  parent: Option(String),
  role: Role,
  agent: agents.Agent,
  resource: Option(Int),
  budget: Option(Int),
  now: ClockData,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use _ <- result.try(check_capacity_observation(s, resource, budget, now))
  use cap <- result.try(capacity(s.config, resource, budget))
  let fanout_ok = case parent {
    None -> True
    Some(p) -> children_used(s, p) < s.config.fanout
  }
  case
    valid_label(id)
    && !list.any(s.nodes, fn(n) { n.id == id })
    && list.length(s.nodes) < s.config.retained_nodes
    && role_depth(role) <= s.config.depth
    && used(s) < cap
    && fanout_ok
  {
    True ->
      Ok(stamp(
        State(
          ..s,
          fence: FenceData(..s.fence, revision: s.fence.revision + 1),
          nodes: [
            NodeData(
              id,
              parent,
              role,
              agent,
              Reserved,
              None,
              NoRecordedLiability,
              CostUnclassified,
              None,
              None,
              None,
            ),
            ..s.nodes
          ],
        ),
        now,
      ))
    False -> Error("capacity, depth, retention or unique-id HOLD")
  }
}

/// Requested scope/identity DATA. These labels and deadlines are not a grant.
pub type ScopeData {
  ScopeData(
    plan: String,
    task: String,
    worker: String,
    session: String,
    attempt: Int,
    candidate: String,
    capabilities: List(agents.Capability),
    layers: List(Layer),
    expires_utc: Int,
    expires_mono: Int,
  )
}

fn valid_scope(c: ScopeData) -> Bool {
  list.all([c.plan, c.task, c.worker, c.session], valid_label)
  && c.attempt > 0
  && c.attempt <= 1_000_000_000
  && string.byte_size(c.candidate) == 71
  && string.starts_with(c.candidate, "sha256:")
  && string.to_graphemes(string.drop_start(c.candidate, 7))
  |> list.all(fn(ch) { string.contains("0123456789abcdef", ch) })
  && c.capabilities != []
  && list.length(c.capabilities) <= 7
  && list.length(list.unique(c.capabilities)) == list.length(c.capabilities)
  && c.layers != []
  && list.length(c.layers) <= 10
  && list.length(list.unique(c.layers)) == list.length(c.layers)
  && c.expires_utc > 0
  && c.expires_utc <= 9_000_000_000_000_000
  && c.expires_mono >= -9_000_000_000_000_000
  && c.expires_mono <= 9_000_000_000_000_000
}

fn attenuates(child: ScopeData, parent: ScopeData) -> Bool {
  child.plan == parent.plan
  && child.candidate == parent.candidate
  && child.worker != parent.worker
  && child.session != parent.session
  && child.expires_utc <= parent.expires_utc
  && child.expires_mono <= parent.expires_mono
  && list.all(child.capabilities, fn(c) {
    list.contains(parent.capabilities, c)
  })
  && list.all(child.layers, fn(c) { list.contains(parent.layers, c) })
}

pub fn bind_scope(
  s: State,
  expected: FenceData,
  id: String,
  scope: ScopeData,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(node(s, id))
  let permitted = case n.parent {
    None -> True
    Some(p) ->
      case node(s, p) {
        Ok(NodeData(scope: Some(parent), ..)) -> attenuates(scope, parent)
        _ -> False
      }
  }
  let duplicate_session =
    list.any(s.nodes, fn(n) {
      case n.scope {
        None -> False
        Some(other) -> other.session == scope.session
      }
    })
  case
    n.phase == Reserved
    && n.scope == None
    && valid_scope(scope)
    && permitted
    && !duplicate_session
  {
    True -> Ok(replace_node(s, NodeData(..n, scope: Some(scope))))
    False -> Error("scope DATA missing, widened, duplicate or immutable")
  }
}

fn replace_node(s: State, n: NodeData) -> State {
  State(
    ..s,
    fence: FenceData(..s.fence, revision: s.fence.revision + 1),
    nodes: list.map(s.nodes, fn(old) {
      case old.id == n.id {
        True -> n
        False -> old
      }
    }),
  )
}

pub fn active(phase: Phase) -> Bool {
  case phase {
    Reserved | Starting | Running | Cancelling | CleanupUnknown -> True
    Released -> False
  }
}

pub type LifecycleData {
  BeginStart
  ObserveRunning
  RequestCancellation
  ObserveCleanupUnknown
}

/// Reference to the existing budget ledger, not another spend store. Amount is
/// retained liability DATA in nanodollars, never observed/billed price. No
/// settlement/refund or native receipt authentication is provided here.
pub type LiabilityData {
  NoRecordedLiability
  RecordedLiability(reference: String, nanodollars: Int)
  CostUnknown(reference: String, nanodollars: Int)
}

/// Reported pricing DATA only: references cannot authenticate fee-free
/// eligibility, a price quote, custody or a spend grant.
pub type CostModeData {
  CostUnclassified
  ReportedFree(evidence_ref: String)
  ReportedPaid(evidence_ref: String)
  ReportedUnknown(evidence_ref: String)
}

pub fn record_free_cost(
  s: State,
  expected: FenceData,
  id: String,
  evidence_ref: String,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(node(s, id))
  case
    n.phase == Reserved
    && n.cost_mode == CostUnclassified
    && n.liability == NoRecordedLiability
    && valid_label(evidence_ref)
  {
    True ->
      Ok(replace_node(s, NodeData(..n, cost_mode: ReportedFree(evidence_ref))))
    False -> Error("free-cost DATA missing, immutable or not Reserved")
  }
}

pub fn record_liability(
  s: State,
  expected: FenceData,
  id: String,
  reference: String,
  amount: Int,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(node(s, id))
  let duplicate =
    list.any(s.nodes, fn(other) {
      case other.liability {
        NoRecordedLiability -> False
        RecordedLiability(r, _) | CostUnknown(r, _) -> r == reference
      }
    })
  case
    n.phase == Reserved
    && n.liability == NoRecordedLiability
    && n.cost_mode == CostUnclassified
    && valid_label(reference)
    && amount > 0
    && amount <= 1_000_000_000_000
    && !duplicate
  {
    True ->
      Ok(replace_node(
        s,
        NodeData(
          ..n,
          liability: RecordedLiability(reference, amount),
          cost_mode: ReportedPaid(reference),
        ),
      ))
    False -> Error("liability missing, duplicate or immutable")
  }
}

pub fn record_cost_unknown(
  s: State,
  expected: FenceData,
  id: String,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(node(s, id))
  case n.cost_mode, n.liability {
    ReportedPaid(_), RecordedLiability(r, amount) ->
      Ok(replace_node(
        s,
        NodeData(
          ..n,
          liability: CostUnknown(r, amount),
          cost_mode: ReportedUnknown(r),
        ),
      ))
    ReportedFree(r), NoRecordedLiability ->
      Ok(replace_node(s, NodeData(..n, cost_mode: ReportedUnknown(r))))
    _, _ -> Error("no new unknown-cost observation")
  }
}

pub fn retained_liability(s: State) -> Int {
  list.fold(s.nodes, 0, fn(total, n) {
    total
    + case n.liability {
      NoRecordedLiability -> 0
      RecordedLiability(_, amount) | CostUnknown(_, amount) -> amount
    }
  })
}

/// Pure counterfactual cleanup observation. Caller-supplied reference is NOT an
/// OS reap witness. An actual owner must authenticate it before using this model.
/// Physical capacity in DATA releases; recorded monetary liability never does.
pub fn record_cleanup(
  s: State,
  expected: FenceData,
  id: String,
  receipt_ref: String,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(node(s, id))
  case n.role {
    H3Review -> Error("review cleanup requires separate custody DATA route")
    H0Program | H1Subsystem | H2Worker -> cleanup(s, n, receipt_ref)
  }
}

fn cleanup(
  s: State,
  n: NodeData,
  receipt_ref: String,
) -> Result(State, String) {
  case
    { n.phase == Cancelling || n.phase == CleanupUnknown }
    && valid_label(receipt_ref)
    && children_used(s, n.id) == 0
  {
    True ->
      Ok(replace_node(
        s,
        NodeData(..n, phase: Released, cleanup_ref: Some(receipt_ref)),
      ))
    False -> Error("cleanup DATA absent or active descendants retained")
  }
}

/// Lifecycle observations are DATA; no spawn/reap witness or effect permission.
pub fn lifecycle(
  s: State,
  expected: FenceData,
  id: String,
  event: LifecycleData,
  now: ClockData,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(node(s, id))
  case n.role {
    H3Review -> Error("review lifecycle requires separate custody DATA route")
    H0Program | H1Subsystem | H2Worker -> apply_lifecycle(s, n, event, now)
  }
}

fn apply_lifecycle(
  s: State,
  n: NodeData,
  event: LifecycleData,
  now: ClockData,
) -> Result(State, String) {
  use _ <- result.try(check_clock(s, now))
  use _ <- result.try(case event {
    BeginStart | ObserveRunning -> live_scope(s, n, now)
    RequestCancellation | ObserveCleanupUnknown -> Ok(Nil)
  })
  let parent_running = case n.parent, n.role {
    _, H3Review -> True
    None, _ -> True
    Some(p), _ ->
      case node(s, p) {
        Ok(parent) -> parent.phase == Running
        Error(_) -> False
      }
  }
  use phase <- result.try(case event, n.phase {
    BeginStart, Reserved if n.scope != None && parent_running -> Ok(Starting)
    ObserveRunning, Starting -> Ok(Running)
    RequestCancellation, Reserved
    | RequestCancellation, Starting
    | RequestCancellation, Running
    -> Ok(Cancelling)
    ObserveCleanupUnknown, Starting
    | ObserveCleanupUnknown, Running
    | ObserveCleanupUnknown, Cancelling
    -> Ok(CleanupUnknown)
    _, _ -> Error("invalid lifecycle DATA transition")
  })
  Ok(stamp(replace_node(s, NodeData(..n, phase: phase)), now))
}

/// Structural separation only. Distinct strings are NOT authenticated subjects,
/// independent reviewer custody or permission to assign/reap a verifier.
pub type CustodyData {
  CustodyData(
    custodian: String,
    custody_session: String,
    reviewer: String,
    reviewer_session: String,
    candidate: String,
  )
}

pub fn assign_review(
  s: State,
  expected: FenceData,
  worker_id: String,
  review_id: String,
  agent: agents.Agent,
  scope: ScopeData,
  custody: CustodyData,
  resource: Option(Int),
  budget: Option(Int),
  now: ClockData,
) -> Result(State, String) {
  use _ <- result.try(case revision_capacity(expected, 3) {
    True -> Ok(Nil)
    False -> Error("insufficient revision headroom for composite review update")
  })
  use worker <- result.try(node(s, worker_id))
  use _ <- result.try(live_scope(s, worker, now))
  use implementer <- result.try(case worker.scope {
    Some(c) if worker.role == H2Worker && worker.phase == Running -> Ok(c)
    _ -> Error("review target not a scoped running H2 DATA node")
  })
  case
    list.all(
      [
        custody.custodian,
        custody.custody_session,
        custody.reviewer,
        custody.reviewer_session,
      ],
      valid_label,
    )
    && custody.custodian != implementer.worker
    && custody.custody_session != implementer.session
    && custody.reviewer != implementer.worker
    && custody.reviewer_session != implementer.session
    && custody.reviewer == scope.worker
    && custody.reviewer_session == scope.session
    && custody.candidate == implementer.candidate
    && scope.candidate == implementer.candidate
  {
    False -> Error("independent custody/identity/candidate DATA mismatch")
    True -> {
      use next <- result.try(reserve(
        s,
        expected,
        review_id,
        Some(worker_id),
        H3Review,
        agent,
        resource,
        budget,
        now,
      ))
      use next <- result.try(bind_scope(next, next.fence, review_id, scope))
      use reviewer <- result.try(node(next, review_id))
      Ok(replace_node(next, NodeData(..reviewer, custody: Some(custody))))
    }
  }
}

fn review_node(
  s: State,
  id: String,
  custody: CustodyData,
) -> Result(NodeData, String) {
  use n <- result.try(node(s, id))
  case n.role == H3Review && n.custody == Some(custody) {
    True -> Ok(n)
    False -> Error("not matching review custody DATA")
  }
}

pub fn review_lifecycle(
  s: State,
  expected: FenceData,
  id: String,
  custody: CustodyData,
  event: LifecycleData,
  now: ClockData,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(review_node(s, id, custody))
  apply_lifecycle(s, n, event, now)
}

pub fn review_cleanup(
  s: State,
  expected: FenceData,
  id: String,
  custody: CustodyData,
  receipt_ref: String,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(review_node(s, id, custody))
  cleanup(s, n, receipt_ref)
}

/// Retains one candidate-bound receipt reference, NOT an approval/verdict/grant.
pub fn record_review(
  s: State,
  expected: FenceData,
  id: String,
  custody: CustodyData,
  candidate: String,
  receipt_ref: String,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(review_node(s, id, custody))
  case
    n.phase == Running
    && n.review_receipt == None
    && candidate == custody.candidate
    && valid_label(receipt_ref)
  {
    True ->
      Ok(replace_node(s, NodeData(..n, review_receipt: Some(receipt_ref))))
    False -> Error("review reference absent, conflicting or immutable")
  }
}

/// Caller DATA only. Host, boot and VM clock domain are independent labels;
/// actual trusted clocks/authenticated measurements remain external obligations.
pub type ClockData {
  ClockData(host: String, boot: String, domain: String, utc: Int, mono: Int)
}

pub type CapacityObservationData {
  CapacityObservationData(
    resource: Int,
    budget: Int,
    observed_at: ClockData,
    expires_utc: Int,
    expires_mono: Int,
  )
}

fn valid_clock(c: ClockData) -> Bool {
  list.all([c.host, c.boot, c.domain], valid_label)
  && c.utc >= 0
  && c.utc <= 9_000_000_000_000_000
  && c.mono >= -9_000_000_000_000_000
  && c.mono <= 9_000_000_000_000_000
}

fn clock_after(a: ClockData, b: ClockData) -> Bool {
  a.host == b.host
  && a.boot == b.boot
  && a.domain == b.domain
  && a.utc >= b.utc
  && a.mono >= b.mono
}

pub fn check_clock(s: State, now: ClockData) -> Result(Nil, String) {
  let consistent = case s.checked_clock {
    None -> True
    Some(previous) -> clock_after(now, previous)
  }
  case valid_clock(now) && consistent {
    True -> Ok(Nil)
    False -> Error("invalid or regressing clock/domain DATA")
  }
}

fn stamp(s: State, now: ClockData) -> State {
  State(..s, checked_clock: Some(now))
}

/// New observation is explicit, not a heartbeat refresh. Immutable observation
/// timestamps/expiry survive subsequent state changes. Only successful returned
/// states advance their local clock high-water; branching is not prevented.
pub fn observe_capacity(
  s: State,
  expected: FenceData,
  observation: CapacityObservationData,
) -> Result(State, String) {
  use _ <- result.try(check_fence(s, expected))
  use _ <- result.try(check_clock(s, observation.observed_at))
  use _ <- result.try(capacity(
    s.config,
    Some(observation.resource),
    Some(observation.budget),
  ))
  let now = observation.observed_at
  case
    observation.expires_utc > now.utc
    && observation.expires_utc - now.utc <= 3_600_000
    && observation.expires_mono > now.mono
    && observation.expires_mono - now.mono <= 3_600_000
  {
    True ->
      Ok(stamp(
        State(
          ..s,
          fence: FenceData(..s.fence, revision: s.fence.revision + 1),
          capacity_observation: Some(observation),
        ),
        now,
      ))
    False -> Error("invalid bounded capacity observation window")
  }
}

fn check_capacity_observation(
  s: State,
  resource: Option(Int),
  budget: Option(Int),
  now: ClockData,
) -> Result(Nil, String) {
  use _ <- result.try(check_clock(s, now))
  let unknown_cost =
    list.any(s.nodes, fn(n) {
      case n.cost_mode, n.liability {
        ReportedUnknown(_), _ | _, CostUnknown(_, _) -> True
        _, _ -> False
      }
    })
  case s.capacity_observation {
    Some(o) ->
      case
        resource == Some(o.resource)
        && budget == Some(o.budget)
        && now.utc < o.expires_utc
        && now.mono < o.expires_mono
        && !unknown_cost
      {
        True -> Ok(Nil)
        False ->
          Error("stale, UNKNOWN or mismatching capacity/cost DATA: no scale-up")
      }
    None -> Error("UNKNOWN capacity DATA: no scale-up")
  }
}

fn live_scope(s: State, n: NodeData, now: ClockData) -> Result(Nil, String) {
  use _ <- result.try(check_clock(s, now))
  case n.scope {
    Some(c) if now.utc < c.expires_utc && now.mono < c.expires_mono -> {
      use _ <- result.try(
        case
          list.contains(c.capabilities, agents.AdvisoryCompletion),
          n.cost_mode,
          n.liability
        {
          False, _, _
          | True, ReportedFree(_), NoRecordedLiability
          | True, ReportedPaid(_), RecordedLiability(_, _)
          -> Ok(Nil)
          _, _, _ ->
            Error(
              "advisory cost DATA unclassified/unknown or missing matching liability",
            )
        },
      )
      case n.parent, n.role {
        _, H3Review -> Ok(Nil)
        None, _ -> Ok(Nil)
        Some(id), _ -> {
          use p <- result.try(node(s, id))
          case p.phase == Running {
            True -> live_scope(s, p, now)
            False -> Error("ancestor execution DATA not Running")
          }
        }
      }
    }
    _ -> Error("missing or expired scope DATA")
  }
}

/// Checked intent DATA STILL returns AdmissionRequired, never a permit.
pub fn inspect_intent(
  s: State,
  expected: FenceData,
  id: String,
  now: ClockData,
) -> Result(agents.AuthorityState, String) {
  use _ <- result.try(check_fence(s, expected))
  use n <- result.try(node(s, id))
  use _ <- result.try(live_scope(s, n, now))
  case n.phase == Running {
    True -> Ok(agents.AdmissionRequired)
    False -> Error("not Running DATA")
  }
}

/// Execution HOLD leaves H3 custody untouched. No process stop IO is performed.
pub fn hold_execution(
  s: State,
  expected: FenceData,
  id: String,
  reason: String,
) -> Result(State, String) {
  use target <- result.try(node(s, id))
  use _ <- result.try(check_fence(s, expected))
  use _ <- result.try(case valid_label(reason) {
    True -> Ok(Nil)
    False -> Error("invalid HOLD reason DATA")
  })
  case target.role {
    H3Review -> Error("execution HOLD cannot cancel review custody DATA")
    H0Program | H1Subsystem | H2Worker -> {
      let next =
        State(
          ..s,
          fence: FenceData(..s.fence, revision: s.fence.revision + 1),
          hold_reason: Some(reason),
        )
      Ok(
        State(
          ..next,
          nodes: list.map(next.nodes, fn(n) {
            case
              n.role != H3Review
              && active(n.phase)
              && belongs_to(next, n, id, 3)
            {
              True ->
                case n.phase {
                  CleanupUnknown -> n
                  _ -> NodeData(..n, phase: Cancelling)
                }
              False -> n
            }
          }),
        ),
      )
    }
  }
}

fn belongs_to(s: State, n: NodeData, ancestor: String, remaining: Int) -> Bool {
  case n.id == ancestor {
    True -> True
    False ->
      case n.parent, remaining > 0 {
        Some(p), True ->
          case node(s, p) {
            Ok(parent) -> belongs_to(s, parent, ancestor, remaining - 1)
            Error(_) -> False
          }
        _, _ -> False
      }
  }
}

pub type ConfigData {
  ConfigData(
    depth: Int,
    fanout: Int,
    global_slots: Int,
    retained_nodes: Int,
    tree_bound: Int,
  )
}

pub type SnapshotData {
  SnapshotData(
    config: ConfigData,
    fence: FenceData,
    nodes: List(NodeData),
    capacity_used: Int,
    retained_liability_nanodollars: Int,
    unknown_cost_nodes: Int,
    checked_at: Option(ClockData),
    observation: Option(CapacityObservationData),
    hold_reason: Option(String),
    authority: agents.AuthorityState,
  )
}

pub fn snapshot(s: State) -> SnapshotData {
  SnapshotData(
    ConfigData(
      s.config.depth,
      s.config.fanout,
      s.config.slots,
      s.config.retained_nodes,
      tree_capacity(s.config),
    ),
    s.fence,
    s.nodes,
    used(s),
    retained_liability(s),
    list.count(s.nodes, fn(n) {
      case n.cost_mode {
        ReportedUnknown(_) -> True
        _ -> False
      }
    }),
    s.checked_clock,
    s.capacity_observation,
    s.hold_reason,
    agents.AdmissionRequired,
  )
}

/// Source declarations only; current runtime/provider/model remain unobserved.
pub fn source_attribution(n: NodeData) -> agents.SourceInference {
  agents.source_inference(n.agent)
}

pub fn format_state(s: State) -> String {
  let view = snapshot(s)
  summary()
  <> "\nPure capacity-used DATA: "
  <> int.to_string(view.capacity_used)
  <> "; configured slots: "
  <> int.to_string(view.config.global_slots)
  <> "; tree upper bound: "
  <> int.to_string(view.config.tree_bound)
  <> "; retained known liability DATA subtotal nanodollars: "
  <> int.to_string(view.retained_liability_nanodollars)
  <> "; unknown-cost nodes: "
  <> int.to_string(view.unknown_cost_nodes)
  <> ". Observations, identity and cleanup UNAUTHENTICATED; observed runtime/model UNKNOWN; authority AdmissionRequired."
}
