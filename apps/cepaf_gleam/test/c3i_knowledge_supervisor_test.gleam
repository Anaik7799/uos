import cepaf_gleam/knowledge/c3i_knowledge_supervisor.{
  run_knowledge_mesh_patrol, start_knowledge_mesh,
}
import gleeunit/should

pub fn start_and_patrol_knowledge_mesh_test() {
  let assert Ok(#(knowledge_started, ingestion_started)) =
    start_knowledge_mesh()

  let report =
    run_knowledge_mesh_patrol(knowledge_started.data, ingestion_started.data)

  report.all_green |> should.be_true()
  report.zero_trust_secure |> should.be_true()
  report.total_inventory |> should.equal(5)
  report.anti_patterns_count |> should.equal(3)
  report.supervised_port_mode |> should.equal("SUPERVISED_PORT_STDIO")
}
