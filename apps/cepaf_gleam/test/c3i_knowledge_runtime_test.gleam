import cepaf_gleam/knowledge/c3i_knowledge_runtime
import gleeunit/should

pub fn compute_decayed_trust_nominal_test() {
  let t0 = 1.0
  let t1 = c3i_knowledge_runtime.compute_decayed_trust(t0, 30.0, 30.0)
  should.equal(t1, 0.5)

  let t2 = c3i_knowledge_runtime.compute_decayed_trust(t0, 60.0, 30.0)
  should.equal(t2, 0.25)

  let t_immortal = c3i_knowledge_runtime.compute_decayed_trust(t0, 0.0, 30.0)
  should.equal(t_immortal, 1.0)
}

pub fn create_envelope_and_port_call_ok_test() {
  let env =
    c3i_knowledge_runtime.create_envelope(
      "test_trace_123",
      "test_actor",
      "query",
      "{\"key\":\"val\"}",
      "IDEMP-001",
    )
  should.equal(env.trace_id, "test_trace_123")
  should.equal(env.operation, "query")

  let receipt = c3i_knowledge_runtime.execute_ocaml_worker_port_call(env)
  should.equal(receipt.status, "COMMITTED")
  should.equal(receipt.error_code, 0)
}

pub fn create_envelope_and_port_call_traps_test() {
  let env_nul =
    c3i_knowledge_runtime.create_envelope(
      "trace_nul",
      "test_actor",
      "query",
      "bad\u{0000}data",
      "IDEMP-NUL",
    )
  let rcpt_nul = c3i_knowledge_runtime.execute_ocaml_worker_port_call(env_nul)
  should.equal(rcpt_nul.status, "REJECTED")
  should.equal(rcpt_nul.error_code, -2)

  let env_sql =
    c3i_knowledge_runtime.create_envelope(
      "trace_sql",
      "test_actor",
      "query",
      "1; DROP TABLE users;",
      "IDEMP-SQL",
    )
  let rcpt_sql = c3i_knowledge_runtime.execute_ocaml_worker_port_call(env_sql)
  should.equal(rcpt_sql.status, "REJECTED")
  should.equal(rcpt_sql.error_code, -3)
}

pub fn ingest_c3i_inventory_and_query_recall_test() {
  let inventory = c3i_knowledge_runtime.ingest_c3i_knowledge_inventory()
  should.equal(inventory != [], True)

  let recall_all = c3i_knowledge_runtime.query_cited_recall("", 0.5)
  should.equal(recall_all.total_items, 5)
  should.equal(recall_all.ocaml_oracle_verified, True)

  let recall_filtered = c3i_knowledge_runtime.query_cited_recall("Rete", 0.9)
  should.equal(recall_filtered.total_items, 1)

  let json_str = c3i_knowledge_runtime.encode_recall_result_json(recall_all)
  should.equal(json_str != "", True)
}

pub fn detect_anti_patterns_test() {
  let clean_snippet = "let x = compute_something()"
  let bad_snippet = "let _ = enif_priv_data(env)"

  let no_anti = c3i_knowledge_runtime.detect_anti_patterns(clean_snippet)
  should.equal(no_anti, [])

  let found_anti = c3i_knowledge_runtime.detect_anti_patterns(bad_snippet)
  should.equal(found_anti != [], True)
}

pub fn get_c3i_knowledge_runtime_status_test() {
  let status_json = c3i_knowledge_runtime.get_c3i_knowledge_runtime_status()
  should.equal(status_json != "", True)
}
