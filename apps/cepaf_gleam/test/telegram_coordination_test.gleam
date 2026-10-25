import cepaf_gleam/harness/telegram_coordination_report as report
import cepaf_gleam/harness/telegram_coordination_reader as reader
import cepaf_gleam/harness/telegram_service as service
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync
import uos_swarm/board
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile
import gleeunit/should

fn state() {
  let peer = sync.Session("peer-a","codex","PRIVATE_WORKSPACE","rev-a",
    ["PRIVATE_REFERENCE"],"boot",100,False)
  sync.State(..sync.empty(),sessions:dict.from_list([#("peer-a",peer)]))
}
pub fn peers_preserve_freshness_and_redact_test() {
  let assert Ok(raw) = report.project(state(),"boot",101,"peers")
  string.contains(raw,"fresh-self-reported") |> should.be_true
  string.contains(raw,"PRIVATE") |> should.be_false
  string.contains(raw,"process liveness is not probed") |> should.be_true
  let assert Ok(stale) = report.project(state(),"different-boot",101,"peers")
  string.contains(stale,"\"status\":\"stale\"") |> should.be_true
  let assert Ok(aged) = report.project(state(),"boot",999_999_999,"peers")
  string.contains(aged,"\"status\":\"stale\"") |> should.be_true
}
pub fn peers_retired_and_truncation_test() {
  let assert Ok(peer) = dict.get(state().sessions,"peer-a")
  let peers = list.repeat(0,21) |> list.index_map(fn(_,i) {
    let id = "peer-" <> int.to_string(i)
    #(id,sync.Session(..peer,id:id,retired:True))
  }) |> dict.from_list
  let assert Ok(raw) = report.project(sync.State(..state(),sessions:peers),"boot",101,"peers")
  string.contains(raw,"\"shown\":20") |> should.be_true
  string.contains(raw,"\"total_sessions\":21") |> should.be_true
  string.contains(raw,"\"truncated\":true") |> should.be_true
  string.contains(raw,"\"status\":\"retired\"") |> should.be_true
}
pub fn projection_bounds_and_views_test() {
  let assert Ok(peer) = dict.get(state().sessions,"peer-a")
  let peers = list.repeat(0,257) |> list.index_map(fn(_,i){#(int.to_string(i),peer)}) |> dict.from_list
  report.project(sync.State(..state(),sessions:peers),"boot",101,"peers")
    |> should.equal(Error("coordination_projection_unavailable"))
  report.project(state(),"boot",101,"send") |> result.is_error |> should.be_true
  let huge=sync.Session(..peer,revision:string.repeat("x",40_000))
  report.project(sync.State(..state(),sessions:dict.from_list([#("peer-a",huge)])),"boot",101,"peers")
    |> result.is_error |> should.be_true
}
fn fresh() -> #(String,store.Store) {
  let path="/tmp/uos-telegram-coordination-" <> int.to_string(service.ffi_system_now_utc_us())
    <> "-" <> int.to_string(int.random(100000)) <> ".sqlite3"
  let assert Ok(db)=store.open(path)
  let assert Ok(_) = store.append(db,sync.Register("fixture-codex","codex",
    "/home/an/NAS-setup/uos","fixture-revision",["PRIVATE_REFERENCE"]),"fixture-register")
  #(path,db)
}
pub fn readonly_store_actual_message_counts_test() {
  let #(path,db)=fresh()
  let assert Ok(_) = store.append(db,sync.Send("fixture-codex","broadcast",
    board.Report,"PRIVATE_MESSAGE",["PRIVATE_REFERENCE"]),"fixture-message")
  let assert Ok(_) = store.close(db)
  // Settle the fixture writer WAL before comparing immutable database bytes.
  let assert Ok(checkpoint)=raw_open(path)
  let assert Ok(_)=raw_exec(checkpoint,"PRAGMA wal_checkpoint(TRUNCATE)")
  let assert Ok(_)=raw_close(checkpoint)
  let assert Ok(before)=simplifile.read_bits(path)
  let assert Ok(raw)=report.read(path,"board")
  string.contains(raw,"\"stored_messages\":1") |> should.be_true
  string.contains(raw,"\"kind\":\"Report\"") |> should.be_true
  string.contains(raw,"PRIVATE") |> should.be_false
  simplifile.read_bits(path) |> should.equal(Ok(before))
  let assert Ok(peer)=reader.observe(path,"peers")
  string.contains(peer,"fixture-codex") |> should.be_true
  string.contains(peer,"PRIVATE") |> should.be_false
}
pub fn missing_empty_and_recovery_hold_refused_test() {
  let #(path,db)=fresh()
  let assert Ok(_)=store.close(db)
  report.read(path<>".missing","peers") |> result.is_error |> should.be_true
  simplifile.link_info(path<>".missing") |> should.equal(Error(simplifile.Enoent))
  let assert Ok(_)=simplifile.write(path<>".recovery-lock","test-hold")
  report.read(path,"board") |> should.equal(Error("coordination_observation_unavailable"))
  let assert Ok(_)=simplifile.delete(path<>".recovery-lock")
  report.read(path,"board") |> result.is_ok |> should.be_true
  let assert Ok(empty)=store.open(path<>".empty")
  let assert Ok(_)=store.close(empty)
  report.read(path<>".empty","board") |> result.is_error |> should.be_true
}
@external(erlang,"session_store_ffi","open_existing")
fn raw_open(path:String)->Result(store.Conn,String)
@external(erlang,"session_store_ffi","exec")
fn raw_exec(conn:store.Conn,sql:String)->Result(Int,String)
@external(erlang,"session_store_ffi","close")
fn raw_close(conn:store.Conn)->Result(Nil,String)
pub fn changed_schema_or_digest_refused_test() {
  let #(path,db)=fresh()
  let assert Ok(_)=store.close(db)
  let assert Ok(conn)=raw_open(path)
  let assert Ok(_)=raw_exec(conn,"DROP TRIGGER events_no_update")
  let assert Ok(_)=raw_exec(conn,"UPDATE events SET digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'")
  let assert Ok(_)=raw_close(conn)
  report.read(path,"peers") |> should.equal(Error("coordination_observation_unavailable"))
  reader.observe(path,"peers") |> result.is_error |> should.be_true
}

pub fn oversized_ledger_refused_before_replay_test() {
  let #(path,db)=fresh()
  let assert Ok(_)=store.close(db)
  let assert Ok(conn)=raw_open(path)
  let assert Ok(_)=raw_exec(conn,"DROP TABLE events")
  let assert Ok(_)=raw_exec(conn,"CREATE TABLE events(body_json TEXT,command_json TEXT,digest TEXT)")
  let assert Ok(_)=raw_exec(conn,"WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<20001) INSERT INTO events SELECT '{}','{}','x' FROM n")
  let assert Ok(_)=raw_close(conn)
  store.observe_file(path,fn(_,_,_){Ok(Nil)})
    |> should.equal(Error(store.RefusedError("observation_ledger_bound")))
}
