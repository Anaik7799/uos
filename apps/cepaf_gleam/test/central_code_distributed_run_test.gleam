import cepaf_gleam/ha/central_code_distributed_run.{
  DistributionTarget, ParityDivergent, canonical_distribution_targets,
  evaluate_cluster_parity, target_to_json, verify_target_parity,
}
import gleam/json
import gleam/list
import gleeunit/should

pub fn canonical_targets_count_test() {
  let targets = canonical_distribution_targets("test-commit-1234")
  list.length(targets)
  |> should.equal(3)
}

pub fn verify_target_parity_match_test() {
  let targets = canonical_distribution_targets("commit-abc")
  let first = case targets {
    [t, ..] -> t
    [] -> panic as "Empty targets"
  }

  let #(is_match, reason) = verify_target_parity(first)
  is_match
  |> should.be_true

  should.be_true(reason != "")
}

pub fn verify_target_parity_divergent_test() {
  let targets = canonical_distribution_targets("commit-abc")
  let first = case targets {
    [t, ..] -> t
    [] -> panic as "Empty targets"
  }

  let divergent =
    DistributionTarget(
      ..first,
      deployed_commit_id: "divergent-untracked-commit",
      parity_state: ParityDivergent("Hash mismatch"),
    )

  let #(is_match, reason) = verify_target_parity(divergent)
  is_match
  |> should.be_false

  should.be_true(reason != "")
}

pub fn evaluate_cluster_parity_test() {
  let targets = canonical_distribution_targets("commit-current-sha")
  let #(all_match, reports) = evaluate_cluster_parity(targets)

  all_match
  |> should.be_true

  list.length(reports)
  |> should.equal(3)
}

pub fn target_to_json_test() {
  let targets = canonical_distribution_targets("commit-current-sha")
  let first = case targets {
    [t, ..] -> t
    [] -> panic as "Empty targets"
  }

  let json_str = json.to_string(target_to_json(first))
  should.be_true(json_str != "")
}
