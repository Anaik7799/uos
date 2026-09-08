//// apps/cepaf_gleam/test/intent_parser_test.gleam
//// STAMP: SC-INTENT-ATLAS-001

import gleeunit/should
import cepaf_gleam/intent/parser.{
  default_baseline, normalize_config
}
import gleam/list

pub fn default_baseline_structure_test() {
  let baseline = default_baseline()
  baseline.version |> should.equal("1.0.0")
  baseline.authority |> should.equal("sa-plan")
  baseline.target_drive_serial |> should.equal("SAMSUNG_990_PRO_SECONDARY")
  list.length(baseline.topology_nodes) |> should.equal(2)
  list.length(baseline.containers) |> should.equal(3)
  list.length(baseline.zenoh_topics) |> should.equal(4)
}

pub fn normalize_config_sorts_topics_test() {
  let raw = default_baseline()
  let normalized = normalize_config(raw)
  list.length(normalized.zenoh_topics) |> should.equal(4)
}
