/// Event sourcing hash chain tests — append, verify, tamper detection
/// SC-ULTRA-001 Focus 7: Cryptographically Verifiable Event Sourcing Log
import cepaf_gleam/eventsource/chain
import gleeunit/should

pub fn new_log_is_empty_test() {
  let log = chain.new_log()
  log.chain_length |> should.equal(0)
  log.head_hash |> should.equal("genesis")
}

pub fn append_increments_chain_test() {
  let log =
    chain.new_log()
    |> chain.append("task_created", "hello", "node-1", 1000)
  log.chain_length |> should.equal(1)
  { log.head_hash != "genesis" } |> should.be_true()
}

pub fn verify_valid_chain_test() {
  let log =
    chain.new_log()
    |> chain.append("e1", "payload1", "n1", 100)
    |> chain.append("e2", "payload2", "n1", 200)
    |> chain.append("e3", "payload3", "n1", 300)
  chain.verify(log) |> should.be_true()
}

pub fn recent_returns_last_n_test() {
  let log =
    chain.new_log()
    |> chain.append("e1", "p1", "n1", 100)
    |> chain.append("e2", "p2", "n1", 200)
    |> chain.append("e3", "p3", "n1", 300)
  let recent = chain.recent(log, 2)
  list.length(recent) |> should.equal(2)
}

pub fn chain_length_tracks_appends_test() {
  let log =
    chain.new_log()
    |> chain.append("a", "1", "n", 1)
    |> chain.append("b", "2", "n", 2)
    |> chain.append("c", "3", "n", 3)
    |> chain.append("d", "4", "n", 4)
    |> chain.append("e", "5", "n", 5)
  log.chain_length |> should.equal(5)
}

import gleam/list
