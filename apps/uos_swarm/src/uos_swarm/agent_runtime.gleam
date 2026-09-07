//// Per-agent cognition kernel (holonic: the same kernel at every level).
//// - Memory: one ETS table per agent (`uos_tui_mem_<agent>`), owner-write / L0-L1-read policy,
////   gated by a live scoped `MemoryCap` grant on every operation (default deny).
//// - Lifecycle: F´ hierarchical state machine (Idle → Claimed → Working → Verifying → Done|Failed).
//// - Rules: bounded forward-chaining matcher over typed facts (naive unification, not a Rete network
////   with alpha/beta memories; adequate for < 500 facts), seeded from STPA constraints.
//// - Decision: Bayesian (Beta-Binomial) success beliefs per (agent, model) and cheapest-adequate
////   model choice (Thompson sampling with a seeded PRNG, deterministic and testable).
//// - Capabilities: default-deny grants for Lean, Quint, STM, Zenoh, MAX/Mojo, Rete, Bayes, Memory;
////   grants are issued only by L0/L1, are scoped to a key prefix and expire (opaque `Grant`,
////   minted only by `grant/8`), and are themselves tracked as board messages.
//// - Controls: operational, security and observability controls with live status.
//// Sanskrit mirror: memory = smṛti (स्मृति), rule = niyama (नियम), belief = matam (मतम्), capability = sāmarthya (सामर्थ्य).
//// STAMP: SC-TUI-AGENTRT-001, TwoLattice_STM.lean (single-writer), SC-FPP-INTENT-001.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import uos_swarm/board.{
  type Agent, type Draft, Agent, Causality, Draft, Semantics,
}
import uos_swarm/coord

// ---------------------------------------------------------------------------
// Memory (ETS per agent)
// ---------------------------------------------------------------------------

@external(erlang, "uos_swarm_ffi", "ets_open")
fn ets_open(name: String) -> Result(board.Table, String)

@external(erlang, "uos_swarm_ffi", "ets_insert")
fn ets_insert(table: board.Table, key: String, value: String) -> Nil

@external(erlang, "uos_swarm_ffi", "ets_lookup")
fn ets_lookup(table: board.Table, key: String) -> Result(String, Nil)

@external(erlang, "uos_swarm_ffi", "ets_all")
fn ets_all(table: board.Table) -> List(#(String, String))

pub type Memory {
  Memory(owner: String, table: board.Table)
}

pub type MemoryError {
  NotOwner(requester: String, owner: String)
  NoSuchKey(String)
  Open(String)
  /// Refused because `requester` holds no live `capability` grant that scopes the key
  /// (default-deny; see `grant`/`allowed`).
  NotGranted(requester: String, capability: String)
}

pub fn open_memory(owner: String) -> Result(Memory, MemoryError) {
  ets_open("uos_tui_mem_" <> owner)
  |> result.map(fn(t) { Memory(owner, t) })
  |> result.map_error(Open)
}

fn layer_of(policy: coord.Policy, id: String) -> Result(coord.Layer, Nil) {
  policy.roster |> list.find(fn(a) { a.id == id }) |> result.map(coord.layer_of)
}

fn owner_or_supervisor(
  m: Memory,
  policy: coord.Policy,
  requester: String,
) -> Bool {
  requester == m.owner
  || case layer_of(policy, requester) {
    Ok(coord.L0) | Ok(coord.L1) -> True
    _ -> False
  }
}

/// Only the owner writes its memory, and only while holding a live `MemoryCap` grant whose
/// scope covers `key` (default deny; see `grant`/`allowed`). Slots are namespaced: working/,
/// episodic/, belief/, goal/.
pub fn remember(
  m: Memory,
  grants: Grants,
  now_us: Int,
  requester: String,
  key: String,
  value: String,
) -> Result(Memory, MemoryError) {
  case allowed(grants, requester, MemoryCap, now_us, key) {
    False -> Error(NotGranted(requester, capability_label(MemoryCap)))
    True ->
      case requester == m.owner {
        True -> {
          ets_insert(m.table, key, value)
          Ok(m)
        }
        False -> Error(NotOwner(requester, m.owner))
      }
  }
}

/// The owner, L0 and L1 may read (supervision and audit) — but only while `requester` holds a
/// live `MemoryCap` grant scoping `key`; the grant gate and the ownership/layer rule both apply.
pub fn recall(
  m: Memory,
  policy: coord.Policy,
  grants: Grants,
  now_us: Int,
  requester: String,
  key: String,
) -> Result(String, MemoryError) {
  case allowed(grants, requester, MemoryCap, now_us, key) {
    False -> Error(NotGranted(requester, capability_label(MemoryCap)))
    True ->
      case owner_or_supervisor(m, policy, requester) {
        False -> Error(NotOwner(requester, m.owner))
        True -> ets_lookup(m.table, key) |> result.replace_error(NoSuchKey(key))
      }
  }
}

/// Keys under `prefix` visible to `requester`: the same grant gate and owner/L0/L1 rule as
/// `recall`, applied to the prefix itself. Unauthorized callers see an empty view, never a crash.
pub fn slots(
  m: Memory,
  policy: coord.Policy,
  requester: String,
  grants: Grants,
  now_us: Int,
  prefix: String,
) -> List(#(String, String)) {
  case
    allowed(grants, requester, MemoryCap, now_us, prefix)
    && owner_or_supervisor(m, policy, requester)
  {
    False -> []
    True ->
      ets_all(m.table)
      |> list.filter(fn(kv) { string.starts_with(kv.0, prefix) })
  }
}

/// Episodic memory: remember a board message id under episodic/<id>; follows `remember`'s grant
/// and ownership rules.
pub fn remember_episode(
  m: Memory,
  grants: Grants,
  now_us: Int,
  requester: String,
  message_id: String,
  summary: String,
) -> Result(Memory, MemoryError) {
  remember(m, grants, now_us, requester, "episodic/" <> message_id, summary)
}

// ---------------------------------------------------------------------------
// F´ lifecycle state machine (hierarchical: Active { Claimed, Working, Verifying })
// ---------------------------------------------------------------------------

pub type State {
  Idle
  Claimed
  Working
  Verifying
  Done
  Failed
}

pub type Signal {
  Claim
  Start
  Submit
  Pass
  Fail
  Retry
  Release
}

pub fn state_label(s: State) -> String {
  case s {
    Idle -> "Idle · niṣkriya (निष्क्रिय)"
    Claimed -> "Claimed · gṛhīta (गृहीत)"
    Working -> "Working · kāryarata (कार्यरत)"
    Verifying -> "Verifying · parīkṣyamāṇa (परीक्ष्यमाण)"
    Done -> "Done · siddha (सिद्ध)"
    Failed -> "Failed · viphala (विफल)"
  }
}

pub fn parent(s: State) -> String {
  case s {
    Claimed | Working | Verifying -> "Active"
    _ -> "Root"
  }
}

/// Total transition function; illegal signals are errors, never crashes.
pub fn transition(s: State, sig: Signal) -> Result(State, String) {
  case s, sig {
    Idle, Claim -> Ok(Claimed)
    Claimed, Start -> Ok(Working)
    Claimed, Release -> Ok(Idle)
    Working, Submit -> Ok(Verifying)
    Working, Fail -> Ok(Failed)
    Verifying, Pass -> Ok(Done)
    Verifying, Fail -> Ok(Failed)
    Failed, Retry -> Ok(Working)
    Done, Release -> Ok(Idle)
    _, _ ->
      Error(
        "no transition from " <> state_label(s) <> " on " <> signal_label(sig),
      )
  }
}

pub fn signal_label(sig: Signal) -> String {
  case sig {
    Claim -> "Claim"
    Start -> "Start"
    Submit -> "Submit"
    Pass -> "Pass"
    Fail -> "Fail"
    Retry -> "Retry"
    Release -> "Release"
  }
}

/// F´ machine description (mirrors `cepaf_gleam/fpp/domain.HierarchicalMachine` fields).
pub fn machine_json() -> Json {
  json.object([
    #("machine_name", json.string("AgentLifecycle")),
    #(
      "signals",
      json.array([Claim, Start, Submit, Pass, Fail, Retry, Release], fn(s) {
        json.string(signal_label(s))
      }),
    ),
    #(
      "root_states",
      json.array([Idle, Done, Failed], fn(s) { json.string(state_label(s)) }),
    ),
    #(
      "hierarchical",
      json.object([
        #(
          "Active",
          json.array([Claimed, Working, Verifying], fn(s) {
            json.string(state_label(s))
          }),
        ),
      ]),
    ),
    #("initial", json.string(state_label(Idle))),
  ])
}

// ---------------------------------------------------------------------------
// Rete-style forward chaining (bounded)
// ---------------------------------------------------------------------------

pub type Fact {
  Fact(name: String, args: List(String))
}

pub type Pattern {
  Pattern(name: String, args: List(String))
}

/// "_" in a pattern arg matches anything; "?x" binds a variable.
pub type Rule {
  Rule(
    id: String,
    when: List(Pattern),
    then: fn(Dict(String, String)) -> Fact,
    constraint: String,
  )
}

fn unify(
  p: Pattern,
  f: Fact,
  env: Dict(String, String),
) -> Result(Dict(String, String), Nil) {
  case p.name == f.name && list.length(p.args) == list.length(f.args) {
    False -> Error(Nil)
    True ->
      list.zip(p.args, f.args)
      |> list.try_fold(env, fn(env, pair) {
        let #(pa, fa) = pair
        case pa {
          "_" -> Ok(env)
          "?" <> v ->
            case dict.get(env, v) {
              Ok(bound) if bound != fa -> Error(Nil)
              _ -> Ok(dict.insert(env, v, fa))
            }
          lit if lit == fa -> Ok(env)
          _ -> Error(Nil)
        }
      })
  }
}

fn matches(
  patterns: List(Pattern),
  facts: List(Fact),
  env: Dict(String, String),
) -> List(Dict(String, String)) {
  case patterns {
    [] -> [env]
    [p, ..rest] ->
      facts
      |> list.filter_map(fn(f) { unify(p, f, env) |> result.replace_error(Nil) })
      |> list.flat_map(fn(env2) { matches(rest, facts, env2) })
  }
}

/// Run rules to a fixpoint (bounded to `max_rounds`); returns derived facts in derivation order.
pub fn run(
  facts: List(Fact),
  rules: List(Rule),
  max_rounds: Int,
) -> List(Fact) {
  run_loop(facts, rules, [], max_rounds)
}

fn run_loop(
  facts: List(Fact),
  rules: List(Rule),
  derived: List(Fact),
  rounds: Int,
) -> List(Fact) {
  case rounds <= 0 {
    True -> list.reverse(derived)
    False -> {
      let new =
        rules
        |> list.flat_map(fn(r) {
          matches(r.when, facts, dict.new()) |> list.map(r.then)
        })
        |> list.unique
        |> list.filter(fn(f) { !list.contains(facts, f) })
      case new {
        [] -> list.reverse(derived)
        _ ->
          run_loop(
            list.append(facts, new),
            rules,
            list.append(list.reverse(new), derived),
            rounds - 1,
          )
      }
    }
  }
}

/// Rules seeded from the STPA constraints and the TPS discipline.
pub fn default_rules() -> List(Rule) {
  [
    Rule(
      "R-JIDOKA",
      [Pattern("audit_failed", ["?n"])],
      fn(env) {
        let n = dict.get(env, "n") |> result.try(int.parse) |> result.unwrap(0)
        case n > 3 {
          True -> Fact("act", ["jidoka", "audit failures " <> int.to_string(n)])
          False -> Fact("act", ["none", "audit ok"])
        }
      },
      "SC: halt admission when > 3 aspects fail",
    ),
    Rule(
      "R-STALE",
      [Pattern("stale", ["?a"])],
      fn(env) {
        Fact("act", [
          "andon",
          "stale " <> result.unwrap(dict.get(env, "a"), "?"),
        ])
      },
      "SC: dead-man's switch raises andon",
    ),
    Rule(
      "R-REWORK",
      [Pattern("verdict", ["?a", "FAIL"])],
      fn(env) {
        Fact("act", ["rework", result.unwrap(dict.get(env, "a"), "?")])
      },
      "TPS: red verdict returns the card to Working",
    ),
    Rule(
      "R-INTENT",
      [Pattern("intent", ["?a", "?verb", "?target"])],
      fn(env) {
        Fact("act", [
          "policy_review",
          result.unwrap(dict.get(env, "a"), "?")
            <> ":"
            <> result.unwrap(dict.get(env, "verb"), "?")
            <> ":"
            <> result.unwrap(dict.get(env, "target"), "?"),
        ])
      },
      "Rocha cut: intents are reviewed by policy, never executed",
    ),
    Rule(
      "R-ZENOH",
      [Pattern("zenoh", ["down"])],
      fn(_) { Fact("act", ["andon", "zenoh unavailable"]) },
      "SC: transport loss is visible",
    ),
    Rule(
      "R-WIP",
      [Pattern("wip", ["?n"]), Pattern("wip_limit", ["?l"])],
      fn(env) {
        let n = dict.get(env, "n") |> result.try(int.parse) |> result.unwrap(0)
        let l = dict.get(env, "l") |> result.try(int.parse) |> result.unwrap(0)
        case n > l {
          True ->
            Fact("act", [
              "block_pull",
              "wip " <> int.to_string(n) <> " > " <> int.to_string(l),
            ])
          False -> Fact("act", ["none", "wip ok"])
        }
      },
      "TPS: WIP limit",
    ),
  ]
}

// ---------------------------------------------------------------------------
// Bayesian decision making (Beta-Binomial beliefs, cheapest adequate model)
// ---------------------------------------------------------------------------

pub type Belief {
  Belief(agent: String, model: String, alpha: Float, beta: Float)
}

pub fn prior(agent: String, model: String) -> Belief {
  Belief(agent, model, 1.0, 1.0)
}

pub fn update(b: Belief, success: Bool) -> Belief {
  case success {
    True -> Belief(..b, alpha: b.alpha +. 1.0)
    False -> Belief(..b, beta: b.beta +. 1.0)
  }
}

pub fn mean(b: Belief) -> Float {
  b.alpha /. { b.alpha +. b.beta }
}

/// Deterministic uniform stream (LCG) so Thompson draws are reproducible in tests.
fn uniform(seed: Int) -> #(Float, Int) {
  let n = int.absolute_value({ seed * 1_103_515_245 + 12_345 } % 2_147_483_647)
  #({ int.to_float(n % 1_000_000) +. 0.5 } /. 1_000_000.0, n + 1)
}

/// Standard normal via Box-Muller from two uniforms.
fn normal(seed: Int) -> #(Float, Int) {
  let #(u1, s1) = uniform(seed)
  let #(u2, s2) = uniform(s1)
  let r = float.square_root(-2.0 *. ln(u1)) |> result.unwrap(0.0)
  let two_pi = 6.283185307179586
  #(r *. cos(two_pi *. u2), s2)
}

fn ln(x: Float) -> Float {
  float.logarithm(x) |> result.unwrap(0.0)
}

@external(erlang, "math", "cos")
fn cos(x: Float) -> Float

/// Gamma(shape, 1) variate by Marsaglia–Tsang (shape >= 1; boosted for shape < 1).
fn gamma(shape: Float, seed: Int) -> #(Float, Int) {
  case shape <. 1.0 {
    True -> {
      let #(g, s1) = gamma(shape +. 1.0, seed)
      let #(u, s2) = uniform(s1)
      #(g *. { float.power(u, 1.0 /. shape) |> result.unwrap(1.0) }, s2)
    }
    False -> gamma_loop(shape, seed, 64)
  }
}

fn gamma_loop(shape: Float, seed: Int, budget: Int) -> #(Float, Int) {
  let d = shape -. 1.0 /. 3.0
  let c = 1.0 /. { float.square_root(9.0 *. d) |> result.unwrap(1.0) }
  let #(x, s1) = normal(seed)
  let v = { 1.0 +. c *. x } *. { 1.0 +. c *. x } *. { 1.0 +. c *. x }
  let #(u, s2) = uniform(s1)
  case v >. 0.0 && ln(u) <. 0.5 *. x *. x +. d -. d *. v +. d *. ln(v) {
    True -> #(d *. v, s2)
    False ->
      case budget <= 0 {
        True -> #(d, s2)
        False -> gamma_loop(shape, s2, budget - 1)
      }
  }
}

/// Thompson draw: a real Beta(α, β) variate (Beta = Gamma(α)/(Gamma(α)+Gamma(β))), deterministic per seed.
pub fn sample(b: Belief, seed: Int) -> Float {
  let #(ga, s1) = gamma(b.alpha, seed)
  let #(gb, _) = gamma(b.beta, s1)
  case ga +. gb {
    0.0 -> mean(b)
    total -> float.clamp(ga /. total, 0.0, 1.0)
  }
}

pub type Tier {
  Tier(model: String, relative_cost: Float)
}

/// Cheapest model whose sampled success probability meets `threshold`; falls back to the best sample.
pub fn choose_model(
  beliefs: List(Belief),
  tiers: List(Tier),
  threshold: Float,
  seed: Int,
) -> Tier {
  let scored =
    tiers
    |> list.map(fn(t) {
      let b =
        beliefs
        |> list.find(fn(x) { x.model == t.model })
        |> result.unwrap(prior("any", t.model))
      #(t, sample(b, seed + string.length(t.model)))
    })
  let adequate =
    scored
    |> list.filter(fn(s) { s.1 >=. threshold })
    |> list.sort(fn(a, b) {
      float.compare({ a.0 }.relative_cost, { b.0 }.relative_cost)
    })
  case adequate {
    [best, ..] -> best.0
    [] ->
      scored
      |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
      |> list.first
      |> result.map(fn(s) { s.0 })
      |> result.unwrap(Tier("haiku", 0.27))
  }
}

pub const default_tiers = [
  Tier("haiku", 0.27),
  Tier("sonnet", 1.0),
  Tier("opus", 5.0),
  Tier("fable", 5.0),
]

// ---------------------------------------------------------------------------
// Capabilities (default deny)
// ---------------------------------------------------------------------------

pub type Capability {
  MemoryCap
  ReteCap
  BayesCap
  ZenohCap
  LeanCap
  QuintCap
  StmCap
  MaxInferenceCap
}

pub fn capability_label(c: Capability) -> String {
  case c {
    MemoryCap -> "memory (smṛti)"
    ReteCap -> "rete rules (niyama)"
    BayesCap -> "bayesian decision (sambhāvanā)"
    ZenohCap -> "zenoh transport (sandeśa)"
    LeanCap -> "lean 4 proofs (pramāṇa)"
    QuintCap -> "quint temporal models (kāla-tantra)"
    StmCap -> "two-lattice STM leases (paṭṭā)"
    MaxInferenceCap -> "modular MAX/Mojo inference (buddhi-yantra)"
  }
}

/// Where each formal/runtime capability is bound in the monorepo (declared paths, verified by `bindings_present`).
pub fn binding_paths(c: Capability) -> List(String) {
  case c {
    LeanCap -> [
      "formal/lean/Traceability.lean",
      "formal/lean/TwoLattice_STM.lean",
    ]
    QuintCap -> ["formal/quint/parity_frontier.qnt"]
    StmCap -> [
      "formal/lean/TwoLattice_STM.lean",
      "apps/uos_swarm/src/uos_swarm/coord.gleam",
    ]
    MaxInferenceCap -> ["services/inference/max/max_worker.py"]
    ZenohCap -> ["ops/zenoh/20260907-0450-uos-zenoh-router-1.json5"]
    _ -> ["apps/uos_swarm/src/uos_swarm/agent_runtime.gleam"]
  }
}

/// A capability grant: who may exercise which capability, issued by whom, over which key-prefix
/// `scope` ("*" covers every key), live only until `expires_us` (absolute microseconds). Opaque
/// so a `Grant` can only be minted by `grant/8`, which checks the grantor is L0/L1 — callers
/// outside this module read it through `grant_agent`/`grant_capability`/`grant_grantor`/
/// `grant_expires_us` and gate on it through `allowed`.
pub opaque type Grant {
  Grant(
    agent: String,
    capability: Capability,
    grantor: String,
    scope: String,
    expires_us: Int,
  )
}

/// The live set of scoped, expiring capability grants an agent swarm currently holds.
pub type Grants =
  List(Grant)

/// The agent entitled to exercise the grant's capability.
pub fn grant_agent(g: Grant) -> String {
  g.agent
}

/// The capability the grant covers.
pub fn grant_capability(g: Grant) -> Capability {
  g.capability
}

/// The L0/L1 agent that issued the grant.
pub fn grant_grantor(g: Grant) -> String {
  g.grantor
}

/// Absolute microsecond expiry; the grant is live while `now_us < expires_us`.
pub fn grant_expires_us(g: Grant) -> Int {
  g.expires_us
}

/// Issue `cap` to `agent`, scoped to key-prefix `scope` ("*" for every key), live from `now_us`
/// for `ttl_us` microseconds. Only L0/L1 may grant (Rocha cut on control keys); unknown agents
/// are refused before the layer check.
pub fn grant(
  policy: coord.Policy,
  grants: Grants,
  grantor: String,
  agent: String,
  cap: Capability,
  now_us: Int,
  ttl_us: Int,
  scope: String,
) -> Result(Grants, coord.Violation) {
  case layer_of(policy, grantor), layer_of(policy, agent) {
    Ok(coord.L0), Ok(_) | Ok(coord.L1), Ok(_) ->
      Ok(
        [Grant(agent, cap, grantor, scope, now_us + ttl_us), ..grants]
        |> list.unique,
      )
    Error(_), _ -> Error(coord.UnknownAgent(grantor))
    _, Error(_) -> Error(coord.UnknownAgent(agent))
    _, _ -> Error(coord.ControlKeyForbidden(grantor))
  }
}

/// True only if `agent` holds a live (`now_us < expires_us`) grant for `cap` whose `scope`
/// covers `key` by prefix (`"*"` covers everything). Expired or out-of-scope grants are
/// invisible: this is the single default-deny gate every memory operation checks.
pub fn allowed(
  grants: Grants,
  agent: String,
  cap: Capability,
  now_us: Int,
  key: String,
) -> Bool {
  list.any(grants, fn(g) {
    g.agent == agent
    && g.capability == cap
    && g.expires_us > now_us
    && { g.scope == "*" || string.starts_with(key, g.scope) }
  })
}

/// Withdraw every live grant of `cap` from `agent` (used when trust is revoked mid-lease).
pub fn revoke(grants: Grants, agent: String, cap: Capability) -> Grants {
  list.filter(grants, fn(g) { !{ g.agent == agent && g.capability == cap } })
}

/// A grant is tracked on the board like every other coordination act.
pub fn grant_draft(g: Grant) -> Draft {
  Draft(
    Agent(g.grantor, "L1", "system"),
    g.agent,
    board.LeaseGrant,
    [
      #("capability", capability_label(g.capability)),
      #("paths", string.join(binding_paths(g.capability), ",")),
      #("scope", g.scope),
      #("expires_us", int.to_string(g.expires_us)),
    ],
    Semantics(["Worker"], [4, 7, 9], ["CA-integrate_slice"], [], 1),
    Causality(None, []),
    None,
    None,
  )
}

/// MAX/Mojo access is brokered: the agent emits an Intent upward; nothing here calls the daemon.
pub fn max_request_draft(agent: Agent, prompt_digest: String) -> Draft {
  Draft(
    agent,
    "uos-coord",
    board.Intent,
    [
      #("verb", "infer"),
      #("target", "services/inference/max"),
      #("prompt_sha256", prompt_digest),
    ],
    Semantics(["Worker"], [9], ["CA-emit_intent"], [], 2),
    Causality(None, []),
    None,
    None,
  )
}

// ---------------------------------------------------------------------------
// Controls report (operational, security, observability)
// ---------------------------------------------------------------------------

pub type Control {
  Control(
    domain: String,
    id: String,
    name: String,
    enforcement: String,
    status: String,
  )
}

fn probe_status(ok: Bool) -> String {
  case ok {
    True -> "ENFORCED"
    False -> "FAILED"
  }
}

/// Exercises `remember`/`recall`/`grant`/`allowed` against a scratch memory table so the SEC-12..
/// SEC-16 rows are proved by running the code, not declared. Uses fixed probe agent ids and a
/// fixed table name (`uos_tui_mem_ctrl_probe`); safe to call repeatedly because ETS table open
/// is idempotent and every check re-derives its own grants from the live clock.
fn memory_security_controls() -> List(Control) {
  let row = fn(id: String, name: String, enforcement: String, ok: Bool) {
    Control("security", id, name, enforcement, probe_status(ok))
  }
  case open_memory("ctrl_probe") {
    Error(_) -> [
      row(
        "SEC-12",
        "Memory write without grant refused",
        "agent_runtime.remember (no grant)",
        False,
      ),
      row(
        "SEC-13",
        "Memory read by non-owner L2 refused",
        "agent_runtime.recall (non-owner L2)",
        False,
      ),
      row(
        "SEC-14",
        "Expired grant refused",
        "agent_runtime.grant ttl + remember (post-expiry)",
        False,
      ),
      row(
        "SEC-15",
        "Grant scope enforced",
        "agent_runtime.grant scope + remember (in/out of scope)",
        False,
      ),
      row(
        "SEC-16",
        "Grant from L2 refused",
        "agent_runtime.grant (L2 grantor)",
        False,
      ),
    ]
    Ok(m) -> {
      let now = board.system_time_us()
      let policy =
        coord.default_policy(
          [
            Agent("L0-ctrl-probe", "L0", "fable"),
            Agent("L1-ctrl-probe", "L1", "system"),
            // Matches `m.owner` from `open_memory("ctrl_probe")` so the ownership rule is
            // actually exercised (not merely bypassed by a grants-only check).
            Agent("ctrl_probe", "L2", "sonnet"),
            Agent("L2-ctrl-probe-outsider", "L2", "sonnet"),
          ],
          4,
        )
      let owner = "ctrl_probe"
      let outsider = "L2-ctrl-probe-outsider"
      let grantor = "L0-ctrl-probe"

      // SEC-12: a write with no grant at all is refused.
      let write_no_grant_ok = case
        remember(m, [], now, owner, "working/probe", "1")
      {
        Error(NotGranted(_, _)) -> True
        _ -> False
      }

      // SEC-13: granting the same capability/scope to a non-owner L2 still refuses the read —
      // ownership and the L0/L1 exception are enforced on top of the grant gate.
      let outsider_grants = case
        grant(policy, [], grantor, outsider, MemoryCap, now, 60_000_000, "*")
      {
        Ok(gs) -> gs
        Error(_) -> []
      }
      let read_non_owner_ok = case
        recall(m, policy, outsider_grants, now, outsider, "working/probe")
      {
        Error(NotOwner(_, _)) -> True
        _ -> False
      }

      // SEC-14: a 1us-TTL grant is expired two microseconds later.
      let short_grants = case
        grant(policy, [], grantor, owner, MemoryCap, now, 1, "working/")
      {
        Ok(gs) -> gs
        Error(_) -> []
      }
      let expired_ok = case
        remember(m, short_grants, now + 2, owner, "working/probe-exp", "1")
      {
        Error(NotGranted(_, _)) -> True
        _ -> False
      }

      // SEC-15: a grant scoped to "working/" covers "working/x" but not "belief/x".
      let scoped_grants = case
        grant(
          policy,
          [],
          grantor,
          owner,
          MemoryCap,
          now,
          60_000_000,
          "working/",
        )
      {
        Ok(gs) -> gs
        Error(_) -> []
      }
      let denies_out_of_scope = case
        remember(m, scoped_grants, now, owner, "belief/probe", "1")
      {
        Error(NotGranted(_, _)) -> True
        _ -> False
      }
      let allows_in_scope = case
        remember(m, scoped_grants, now, owner, "working/probe-scope", "1")
      {
        Ok(_) -> True
        _ -> False
      }

      // SEC-16: an L2 agent may never issue a grant (Rocha cut on control keys).
      let grant_from_l2_ok = case
        grant(policy, [], outsider, owner, MemoryCap, now, 60_000_000, "*")
      {
        Error(coord.ControlKeyForbidden(_)) -> True
        _ -> False
      }

      [
        row(
          "SEC-12",
          "Memory write without grant refused",
          "agent_runtime.remember (no grant)",
          write_no_grant_ok,
        ),
        row(
          "SEC-13",
          "Memory read by non-owner L2 refused",
          "agent_runtime.recall (non-owner L2)",
          read_non_owner_ok,
        ),
        row(
          "SEC-14",
          "Expired grant refused",
          "agent_runtime.grant ttl + remember (post-expiry)",
          expired_ok,
        ),
        row(
          "SEC-15",
          "Grant scope enforced",
          "agent_runtime.grant scope + remember (in/out of scope)",
          denies_out_of_scope && allows_in_scope,
        ),
        row(
          "SEC-16",
          "Grant from L2 refused",
          "agent_runtime.grant (L2 grantor)",
          grant_from_l2_ok,
        ),
      ]
    }
  }
}

pub fn controls(root: String, zenoh_ok: Bool) -> List(Control) {
  let exists = fn(p: String) {
    case board.file_read(root <> "/" <> p) {
      Ok(_) -> "PRESENT"
      Error(_) -> "MISSING"
    }
  }
  [
    Control(
      "operational",
      "OP-1",
      "Zenoh router systemd user unit",
      "ops/zenoh/20260907-0450-c3i-zenoh-router-1.service",
      exists("ops/zenoh/20260907-0450-c3i-zenoh-router-1.service"),
    ),
    Control(
      "operational",
      "OP-2",
      "Router reachable (REST)",
      "system_audit.probe",
      case zenoh_ok {
        True -> "UP"
        False -> "DOWN"
      },
    ),
    Control(
      "operational",
      "OP-3",
      "Retry + dead-letter",
      "board.retry_undelivered (max 5)",
      "ENFORCED",
    ),
    Control(
      "operational",
      "OP-4",
      "Heartbeat freshness + retirement",
      "coord.stale / coord.retire",
      "ENFORCED",
    ),
    Control(
      "operational",
      "OP-5",
      "Jidoka / andon",
      "manager.step + tps.jidoka",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-1",
      "Hierarchical authority",
      "coord.authorize (kinds per layer)",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-2",
      "Design authority fable-only",
      "coord.authorize design_kinds",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-3",
      "Intent never executed (Rocha cut)",
      "coord.authorize + manager (no side effects)",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-4",
      "Capability default-deny",
      "agent_runtime.allowed",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-5",
      "Memory isolation per agent",
      "agent_runtime.remember/recall",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-6",
      "Per-sender SHA-256 chains",
      "board.validate",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-7",
      "Fenced single-writer leases",
      "coord.acquire/renew (epochs)",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-8",
      "Zero-trust dispatch interceptor (Hermes)",
      "engines/hermes/_build/default/modules/system_engg/run_agent_dispatch_hook.exe",
      case
        exists(
          "engines/hermes/_build/default/modules/system_engg/run_agent_dispatch_hook.exe",
        ),
        exists("engines/hermes/modules/system_engg/run_agent_dispatch_hook.ml")
      {
        "PRESENT", _ -> "BINARY PRESENT"
        _, "PRESENT" -> "SOURCE ONLY (binary not built)"
        _, _ -> "MISSING"
      },
    ),
    Control(
      "security",
      "SEC-9",
      "Signed envelopes (HMAC-SHA256, key outside repo)",
      "board.sign / board.signature_ok",
      case board.board_key() {
        Ok(_) -> "ENFORCED"
        Error(_) -> "UNSIGNED (no key configured)"
      },
    ),
    Control(
      "security",
      "SEC-10",
      "Policy on absorbed messages",
      "coord.reconcile authorize_message",
      "ENFORCED",
    ),
    Control(
      "security",
      "SEC-11",
      "ETS tables protected (owner-write)",
      "uos_swarm_ffi.erl ets_open",
      "ENFORCED",
    ),
    ..memory_security_controls()
  ]
  |> list.append([
    Control(
      "observability",
      "OBS-1",
      "W3C trace/span on every message",
      "telemetry + board.seal",
      "ENFORCED",
    ),
    Control(
      "observability",
      "OBS-2",
      "Delivery record per transport",
      "board.deliver",
      "ENFORCED",
    ),
    Control(
      "observability",
      "OBS-3",
      "Shared state on Zenoh",
      "coord.share_state uos/tui/state/*",
      case zenoh_ok {
        True -> "LIVE"
        False -> "UNAVAILABLE"
      },
    ),
    Control(
      "observability",
      "OBS-4",
      "System-wide 17-aspect audit",
      "system_audit.all_subjects",
      "ENFORCED",
    ),
    Control(
      "observability",
      "OBS-5",
      "Usage accounting per agent and global",
      "coord.record_usage",
      "ENFORCED",
    ),
    Control(
      "formal",
      "FRM-1",
      "Lean 4 proofs bound",
      string.join(binding_paths(LeanCap), ","),
      exists("formal/lean/TwoLattice_STM.lean"),
    ),
    Control(
      "formal",
      "FRM-2",
      "Quint model bound",
      string.join(binding_paths(QuintCap), ","),
      exists("formal/quint/parity_frontier.qnt"),
    ),
    Control(
      "formal",
      "FRM-3",
      "MAX daemon quarantined",
      string.join(binding_paths(MaxInferenceCap), ","),
      exists("services/inference/max/max_worker.py"),
    ),
  ])
}

pub fn controls_json(cs: List(Control)) -> Json {
  json.array(cs, fn(c) {
    json.object([
      #("domain", json.string(c.domain)),
      #("id", json.string(c.id)),
      #("name", json.string(c.name)),
      #("enforcement", json.string(c.enforcement)),
      #("status", json.string(c.status)),
    ])
  })
}

pub fn controls_markdown(cs: List(Control)) -> String {
  let header =
    "| domain | id | control | enforcement | status |\n|---|---|---|---|---|"
  string.join(
    [
      header,
      ..list.map(cs, fn(c) {
        "| "
        <> c.domain
        <> " | "
        <> c.id
        <> " | "
        <> c.name
        <> " | `"
        <> c.enforcement
        <> "` | "
        <> c.status
        <> " |"
      })
    ],
    "\n",
  )
}

/// True when no control is MISSING, DOWN, UNAVAILABLE, or a FAILED self-test (SEC-12..SEC-16).
pub fn controls_ok(cs: List(Control)) -> Bool {
  list.all(cs, fn(c) {
    c.status != "MISSING"
    && c.status != "DOWN"
    && c.status != "UNAVAILABLE"
    && c.status != "FAILED"
  })
}

pub fn bindings_present(root: String) -> List(#(Capability, Bool)) {
  [LeanCap, QuintCap, StmCap, MaxInferenceCap, ZenohCap]
  |> list.map(fn(c) {
    #(
      c,
      list.all(binding_paths(c), fn(p) {
        board.file_read(root <> "/" <> p) != Error("enoent")
      }),
    )
  })
}

pub fn some_string(s: String) -> option.Option(String) {
  Some(s)
}

// ---------------------------------------------------------------------------
// Hindu thinking-and-memory mirror (Yoga Sūtra 1.6 vṛtti, antaḥkaraṇa, guṇa,
// Nyāya pramāṇa). Additive classification only: it labels the existing
// grant-gated memory namespaces (`working/`, `episodic/`, `belief/`, `goal/`,
// plus `hypothesis/`/`dream/` from `dream.gleam`), the existing lifecycle
// `State`, and the OODA/lifecycle step names already used across the swarm.
// It never reads or writes memory itself and does not change `remember`,
// `recall`, `slots`, `grant` or `allowed` above.
// ---------------------------------------------------------------------------

/// Yoga Sūtra 1.6, pañca vṛttayaḥ — the five citta-vṛtti (fluctuations of
/// mind): pramāṇa (valid cognition), viparyaya (misapprehension/error),
/// vikalpa (imagination, conception without a real referent — svapna's
/// hypotheses live here), nidrā (sleep, the vṛtti of absence-cognition; used
/// here for idle/empty slots), smṛti (memory, not-losing an experienced
/// object — the episodic log).
pub type Vritti {
  Pramana
  Viparyaya
  Vikalpa
  Nidra
  Smriti
}

pub fn vritti_label(v: Vritti) -> String {
  case v {
    Pramana -> "Pramana · pramāṇa (प्रमाण) · valid cognition"
    Viparyaya -> "Viparyaya · viparyaya (विपर्यय) · error"
    Vikalpa -> "Vikalpa · vikalpa (विकल्प) · imagination / hypothesis"
    Nidra -> "Nidra · nidrā (निद्रा) · sleep / idle"
    Smriti -> "Smriti · smṛti (स्मृति) · memory"
  }
}

/// Classify a memory slot by its `remember`/`slots` namespace and value.
/// Rule (checked below, not merely declared):
/// 1. an empty value, or a value literally "idle"/"none" -> `Nidra` (nothing
///    is being cognized; the fastest check, and it wins over namespace).
/// 2. `hypothesis/` or `dream/` (svapna's own output, `dream.gleam`) ->
///    `Vikalpa`: conception without a verified referent, never a fact.
/// 3. `belief/` whose value names "verified"/"confirmed"/"pass" -> `Pramana`;
///    whose value names "contradicted"/"refuted"/"fail" -> `Viparyaya`;
///    any other `belief/` value defaults to `Pramana` (a belief slot holds an
///    asserted, not yet contradicted, cognition).
/// 4. `episodic/` (written by `remember_episode`) -> `Smriti`.
/// 5. anything else -> `Smriti` (the general case: a retained prior
///    cognition, i.e. plain recollection).
pub fn classify_slot(key: String, value: String) -> Vritti {
  let v = string.trim(string.lowercase(value))
  let is_idle = v == "" || v == "idle" || v == "none"
  let is_dreamt =
    string.starts_with(key, "hypothesis/") || string.starts_with(key, "dream/")
  let is_belief = string.starts_with(key, "belief/")
  case is_idle, is_dreamt, is_belief {
    True, _, _ -> Nidra
    False, True, _ -> Vikalpa
    False, False, True -> {
      let contradicted =
        string.contains(v, "contradicted")
        || string.contains(v, "refuted")
        || string.contains(v, "fail")
      case contradicted {
        True -> Viparyaya
        False -> Pramana
      }
    }
    False, False, False -> Smriti
  }
}

/// Sāṅkhya/Vedānta antaḥkaraṇa (अन्तःकरण), the fourfold "inner instrument":
/// manas (मनस्, sensory/motor mind — observing and orienting), buddhi (बुद्धि,
/// the discriminating intellect — deciding and acting), ahaṃkāra (अहंकार,
/// the ego / self-model faculty), citta (चित्त, the memory-substrate itself).
pub type Antahkarana {
  Manas
  Buddhi
  Ahamkara
  Citta
}

pub fn antahkarana_label(a: Antahkarana) -> String {
  case a {
    Manas -> "Manas · manas (मनस्) · sensory/motor mind"
    Buddhi -> "Buddhi · buddhi (बुद्धि) · discriminating intellect"
    Ahamkara -> "Ahamkara · ahaṃkāra (अहंकार) · ego / self-model"
    Citta -> "Citta · citta (चित्त) · memory-substrate"
  }
}

/// Map an OODA/lifecycle step name to the antaḥkaraṇa faculty that performs
/// it: observe/orient -> manas (taking in and weighing sense-data); decide/act
/// -> buddhi (discriminating judgement and its execution); identity/self-model
/// -> ahaṃkāra; memory -> citta. An unrecognised step defaults to manas (the
/// faculty every OODA cycle starts from).
pub fn faculty_of(step: String) -> Antahkarana {
  case string.trim(string.lowercase(step)) {
    "observe" -> Manas
    "orient" -> Manas
    "decide" -> Buddhi
    "act" -> Buddhi
    "identity" -> Ahamkara
    "self-model" -> Ahamkara
    "ahamkara" -> Ahamkara
    "memory" -> Citta
    "citta" -> Citta
    _ -> Manas
  }
}

/// Sāṅkhya triguṇa: sattva (सत्त्व, clarity/harmony — a settled, verified
/// line), rajas (रजस्, activity/passion — work in motion), tamas (तमस्,
/// inertia/dullness — nothing moving, whether idle or stalled in failure).
pub type Guna {
  Sattva
  Rajas
  Tamas
}

pub fn guna_label(g: Guna) -> String {
  case g {
    Sattva -> "Sattva · sattva (सत्त्व) · clarity / harmony"
    Rajas -> "Rajas · rajas (रजस्) · activity / passion"
    Tamas -> "Tamas · tamas (तमस्) · inertia / dullness"
  }
}

/// Map the F´ lifecycle `State` to its guṇa: Done/Verifying (settled,
/// under scrutiny or accepted) -> Sattva; Working/Claimed (in motion) ->
/// Rajas; Idle/Failed (nothing productive moving) -> Tamas.
pub fn guna_of_state(s: State) -> Guna {
  case s {
    Done | Verifying -> Sattva
    Working | Claimed -> Rajas
    Idle | Failed -> Tamas
  }
}

/// Nyāya pramāṇa (valid means of knowledge) named by an evidence `kind`:
/// "observed" -> pratyakṣa (direct perception), "inferred" -> anumāna
/// (inference), "reported" -> śabda (testimony), "compared" -> upamāna
/// (comparison/analogy). An unrecognised kind falls back to śabda — a claim
/// taken on report is the weakest-grounded default, never silently upgraded.
pub fn pramana_of_evidence(kind: String) -> String {
  case string.trim(string.lowercase(kind)) {
    "observed" -> "pratyakṣa (प्रत्यक्ष)"
    "inferred" -> "anumāna (अनुमान)"
    "reported" -> "śabda (शब्द)"
    "compared" -> "upamāna (उपमान)"
    _ -> "śabda (शब्द)"
  }
}
