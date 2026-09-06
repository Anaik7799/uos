//// =============================================================================
//// Test Module: test/zigvm_feature_tracker_test.gleam
//// Subject: ZigVM Wiki, ZK & KM In-Code Feature Tracking & Verification
//// =============================================================================

import cepaf_gleam/knowledge/zigvm_feature_tracker.{
  PermanentAdrRecord, RatifiedActive, Tier3FormalProof, ZkMcpTool, all_features,
  count_features, get_feature, get_summary, render_ascii_table,
  render_markdown_table, verify_feature_registry,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn total_features_count_test() {
  let count = count_features()
  // Must track at least 100 features across all categories
  { count >= 120 } |> should.equal(True)
}

pub fn feature_id_uniqueness_test() {
  let features = all_features()
  let ids = list.map(features, fn(f) { f.id })
  let unique_ids = list.unique(ids)
  list.length(ids) |> should.equal(list.length(unique_ids))
}

pub fn category_coverage_test() {
  let summary = get_summary()
  // Verify exact counts
  summary.wiki_core_count |> should.equal(6)
  summary.zk_mcp_tool_count |> should.equal(7)
  summary.wiki_script_count |> should.equal(23)
  summary.zk_script_count |> should.equal(42)
  summary.harness_law_count |> should.equal(8)
  summary.sheaf_formal_count |> should.equal(4)
  summary.render_suite_count |> should.equal(13)
  summary.adr_count |> should.equal(16)
  summary.moc_count |> should.equal(12)
  summary.episodic_cluster_count |> should.equal(10)
  summary.service_topology_count |> should.equal(4)
}

pub fn feature_lookup_test() {
  // Check ADR-001
  let res_adr = get_feature("ADR-001")
  res_adr |> should.be_ok
  case res_adr {
    Ok(adr) -> {
      adr.name |> should.equal("Closed Rete-UL Fact Schema & Strict Typing")
      adr.category |> should.equal(PermanentAdrRecord)
      adr.status |> should.equal(RatifiedActive)
      adr.tier |> should.equal(Tier3FormalProof)
    }
    Error(_) -> panic as "ADR-001 not found"
  }

  // Check zk_search MCP tool
  let res_mcp = get_feature("ZK-MCP-001")
  res_mcp |> should.be_ok
  case res_mcp {
    Ok(tool) -> {
      tool.name |> should.equal("zk_search")
      tool.category |> should.equal(ZkMcpTool)
    }
    Error(_) -> panic as "ZK-MCP-001 not found"
  }
}

pub fn table_rendering_test() {
  let ascii_tbl = render_ascii_table()
  string.contains(ascii_tbl, "Feature ID") |> should.equal(True)
  string.contains(ascii_tbl, "ADR-001") |> should.equal(True)
  string.contains(ascii_tbl, "zk_search") |> should.equal(True)

  let md_tbl = render_markdown_table()
  string.contains(md_tbl, "| Feature ID | Feature Name |") |> should.equal(True)
  string.contains(md_tbl, "`ADR-001`") |> should.equal(True)
  string.contains(md_tbl, "`ZK-MCP-001`") |> should.equal(True)
}

pub fn registry_verification_test() {
  let res = verify_feature_registry()
  res |> should.be_ok
}
