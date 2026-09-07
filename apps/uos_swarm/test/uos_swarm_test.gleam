import gleam/list
import gleam/option
import gleeunit
import gleeunit/should
import uos_swarm/board
import uos_swarm/coord
import uos_swarm/swarm

pub fn main() -> Nil {
  gleeunit.main()
}

/// The same swarm ledger `uos_swarm.gleam`'s `policy_and_roster` loads by default for
/// `board post` / `board post-acl` / `board ingest` authorization.
const default_swarm_ledger = "swarm/20260907-0440-swarm-ledger.json"

fn ledger() -> swarm.Ledger {
  let assert Ok(text) = board.file_read(default_swarm_ledger)
  let assert Ok(l) = swarm.decode(text)
  l
}

fn roster(l: swarm.Ledger) -> List(board.Agent) {
  let supervisor = board.Agent("L0-fable", "L0", "fable")
  [
    supervisor,
    coord.system_agent,
    ..list.map(l.agents, fn(a) { board.Agent(a.id, a.layer, a.model) })
  ]
}

fn draft(from: board.Agent, to: String, kind: board.Kind) -> board.Draft {
  board.Draft(
    from,
    to,
    kind,
    [
      #("decision_record", "generated/dr-test.json"),
      #("route_class", "R4"),
      #("route_tier", "claude/sonnet"),
    ],
    board.no_semantics,
    board.Causality(option.None, []),
    option.None,
    option.None,
  )
}

// Regression: the default authorization policy built from the live swarm ledger must never
// refuse the pipeline's own L0-fable posts (Dispatch/Integrate/Andon/Plan broadcasts) — the
// same policy `board post` / `board post-acl` / `board ingest` now authorize against before
// posting (Defect 5: CLI posting previously bypassed the authorization boundary entirely).
pub fn default_policy_authorizes_l0_fable_pipeline_kinds_test() {
  let l = ledger()
  let policy = coord.default_policy(roster(l), l.wip_limit)
  let supervisor = board.Agent("L0-fable", "L0", "fable")
  [board.Dispatch, board.Integrate, board.Andon, board.Plan]
  |> list.each(fn(k) {
    coord.authorize(policy, draft(supervisor, "broadcast", k))
    |> should.equal(Ok(Nil))
  })
}

// Regression: worker Report and verifier Verdict messages ingested from the workflow journal
// (`board.drafts_from_journal_labelled`) must authorize against the same ledger-derived
// policy: L2 workers may Report, L3 verifiers may Verdict, both toward the L0 supervisor.
pub fn default_policy_authorizes_ingested_worker_and_verifier_kinds_test() {
  let l = ledger()
  let policy = coord.default_policy(roster(l), l.wip_limit)
  let assert Ok(worker) = list.find(l.agents, fn(a) { a.role == "worker" })
  let assert Ok(verifier) = list.find(l.agents, fn(a) { a.role != "worker" })
  coord.authorize(
    policy,
    draft(
      board.Agent(worker.id, worker.layer, worker.model),
      "L0-fable",
      board.Report,
    ),
  )
  |> should.equal(Ok(Nil))
  coord.authorize(
    policy,
    draft(
      board.Agent(verifier.id, verifier.layer, verifier.model),
      "L0-fable",
      board.Verdict,
    ),
  )
  |> should.equal(Ok(Nil))
}
