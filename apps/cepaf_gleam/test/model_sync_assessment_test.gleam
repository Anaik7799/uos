import cepaf_gleam/harness/model_sync_assessment as sync
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn candidate(revision: String) -> sync.CandidateData {
  sync.CandidateData(
    "candidate-7",
    revision,
    "formal/lean/Example.lean",
    "sha256:" <> string.repeat("a", 64),
  )
}

fn spec(path: String) -> sync.RequiredMapping {
  sync.RequiredMapping(path, "model:capacity", "code:capacity", "rev-7")
}

fn mapped(path: String) -> sync.MappingData {
  sync.MappingData(
    path,
    Some("model:capacity"),
    Some("code:capacity"),
    Some("rev-7"),
    sync.MappedData,
  )
}

fn input(
  required: List(sync.RequiredMapping),
  observed: List(sync.MappingData),
) -> sync.AssessmentInput {
  sync.AssessmentInput(
    Some(candidate("rev-7")),
    Some(candidate("rev-7")),
    required,
    observed,
  )
}

pub fn matching_candidate_and_mapping_data_still_hold_for_authority_test() {
  let result =
    sync.assess(
      input([spec("formal/lean/Model.lean")], [mapped("formal/lean/Model.lean")]),
    )
  result.candidate |> should.equal(sync.CandidateMatchedData)
  result.paths
  |> should.equal([
    sync.PathFinding(
      "formal/lean/Model.lean",
      "model:capacity",
      sync.ProvisionalMappingMatch,
    ),
  ])
  result.provisional |> should.equal(sync.ProvisionalDataAligned)
  result.readiness
  |> should.equal(sync.HoldRuntimeEvidenceUnverified)
}

pub fn absent_candidate_is_unknown_and_fail_closed_test() {
  let assessment =
    sync.assess(
      sync.AssessmentInput(
        None,
        Some(candidate("rev-7")),
        [spec("formal/lean/Model.lean")],
        [mapped("formal/lean/Model.lean")],
      ),
    )
  assessment.candidate |> should.equal(sync.CandidateUnknown)
  assessment.paths
  |> should.equal([
    sync.PathFinding("formal/lean/Model.lean", "model:capacity", sync.Unknown),
  ])
  assessment.provisional
  |> should.equal(sync.HoldMissingOrInvalidCandidate)
  assessment.readiness
  |> should.equal(sync.HoldRuntimeEvidenceUnverified)
}

pub fn malformed_candidate_fields_do_not_become_matching_data_test() {
  let missing_digest =
    sync.CandidateData("candidate-7", "rev-7", "model.lean", "sha256:bad")
  let assessment =
    sync.assess(
      sync.AssessmentInput(
        Some(missing_digest),
        Some(candidate("rev-7")),
        [spec("formal/lean/Model.lean")],
        [mapped("formal/lean/Model.lean")],
      ),
    )
  assessment.candidate |> should.equal(sync.CandidateUnknown)
  assessment.paths
  |> should.equal([
    sync.PathFinding("formal/lean/Model.lean", "model:capacity", sync.Unknown),
  ])
  assessment.provisional
  |> should.equal(sync.HoldMissingOrInvalidCandidate)
}

pub fn candidate_revision_mismatch_marks_each_required_path_stale_test() {
  let assessment =
    sync.assess(
      sync.AssessmentInput(
        Some(candidate("rev-7")),
        Some(candidate("rev-8")),
        [spec("model/a.md"), spec("model/b.md")],
        [mapped("model/a.md"), mapped("model/b.md")],
      ),
    )
  assessment.candidate |> should.equal(sync.CandidateRevisionMismatch)
  assessment.paths
  |> should.equal([
    sync.PathFinding("model/a.md", "model:capacity", sync.Stale),
    sync.PathFinding("model/b.md", "model:capacity", sync.Stale),
  ])
  assessment.provisional |> should.equal(sync.HoldCandidateRevisionMismatch)
}

pub fn candidate_nonrevision_field_mismatch_is_not_a_revision_match_test() {
  let assessment =
    sync.assess(
      sync.AssessmentInput(
        Some(candidate("rev-7")),
        Some(sync.CandidateData(
          "candidate-other",
          "rev-7",
          "formal/lean/Example.lean",
          "sha256:" <> string.repeat("a", 64),
        )),
        [spec("model/a.md")],
        [mapped("model/a.md")],
      ),
    )
  assessment.candidate |> should.equal(sync.CandidateFieldsMismatch)
  assessment.paths
  |> should.equal([
    sync.PathFinding("model/a.md", "model:capacity", sync.MappingFieldsMismatch),
  ])
  assessment.provisional |> should.equal(sync.HoldCandidateFieldsMismatch)
}

pub fn each_required_path_preserves_unknown_stale_unmapped_unsupported_test() {
  let paths = [
    #("unknown", sync.UnknownData, sync.Unknown),
    #("stale", sync.StaleData, sync.Stale),
    #("unmapped", sync.UnmappedData, sync.Unmapped),
    #("unsupported", sync.UnsupportedData, sync.Unsupported),
  ]
  let required = list.map(paths, fn(row) { spec("model/" <> row.0 <> ".md") })
  let observed =
    list.map(paths, fn(row) {
      sync.MappingData(
        "model/" <> row.0 <> ".md",
        Some("model:capacity"),
        Some("code:capacity"),
        Some("rev-7"),
        row.1,
      )
    })
  let expected =
    list.map(paths, fn(row) {
      sync.PathFinding("model/" <> row.0 <> ".md", "model:capacity", row.2)
    })
  let assessment = sync.assess(input(required, observed))
  assessment.paths |> should.equal(expected)
  assessment.provisional |> should.equal(sync.HoldPathFindings)
  assessment.readiness |> should.equal(sync.HoldRuntimeEvidenceUnverified)
}

pub fn absent_mapping_is_unmapped_and_missing_mapping_fields_are_unknown_test() {
  let result =
    sync.assess(
      input([spec("model/absent.md"), spec("model/missing-fields.md")], [
        sync.MappingData(
          "model/missing-fields.md",
          None,
          Some("code:capacity"),
          Some("rev-7"),
          sync.MappedData,
        ),
      ]),
    )
  result.paths
  |> should.equal([
    sync.PathFinding("model/absent.md", "model:capacity", sync.Unmapped),
    sync.PathFinding("model/missing-fields.md", "model:capacity", sync.Unknown),
  ])
  result.provisional |> should.equal(sync.HoldUnexpectedMappings)
}

pub fn mismatched_revision_or_mapping_fields_fail_closed_per_path_test() {
  let result =
    sync.assess(
      input([spec("model/revision.md"), spec("model/fields.md")], [
        sync.MappingData(
          "model/revision.md",
          Some("model:capacity"),
          Some("code:capacity"),
          Some("rev-old"),
          sync.MappedData,
        ),
        sync.MappingData(
          "model/fields.md",
          Some("model:other"),
          Some("code:capacity"),
          Some("rev-7"),
          sync.MappedData,
        ),
      ]),
    )
  result.paths
  |> should.equal([
    sync.PathFinding("model/revision.md", "model:capacity", sync.Stale),
    sync.PathFinding(
      "model/fields.md",
      "model:capacity",
      sync.MappingFieldsMismatch,
    ),
  ])
  result.provisional |> should.equal(sync.HoldUnexpectedMappings)
}

pub fn empty_required_path_list_is_not_a_vacuous_pass_test() {
  let result = sync.assess(input([], []))
  result.paths |> should.equal([])
  result.provisional |> should.equal(sync.HoldEmptyRequiredPaths)
  result.readiness |> should.equal(sync.HoldRuntimeEvidenceUnverified)
}

pub fn duplicate_required_and_unexpected_mapping_keys_hold_test() {
  let duplicate =
    sync.assess(
      input([spec("model/a.md"), spec("model/a.md")], [mapped("model/a.md")]),
    )
  duplicate.provisional |> should.equal(sync.HoldDuplicateRequiredPaths)

  let extra =
    sync.assess(
      input([spec("model/a.md")], [
        mapped("model/a.md"),
        mapped("model/unexpected.md"),
      ]),
    )
  extra.unexpected_mapping_keys
  |> should.equal([
    sync.MappingKey("model/unexpected.md", Some("model:capacity")),
  ])
  extra.provisional |> should.equal(sync.HoldUnexpectedMappings)
}

pub fn duplicate_observations_for_one_path_are_mapping_mismatch_test() {
  let result =
    sync.assess(
      input([spec("model/a.md")], [mapped("model/a.md"), mapped("model/a.md")]),
    )
  result.paths
  |> should.equal([
    sync.PathFinding("model/a.md", "model:capacity", sync.MappingFieldsMismatch),
  ])
  result.provisional |> should.equal(sync.HoldPathFindings)
}

pub fn multiple_function_mappings_in_one_file_are_assessed_independently_test() {
  let first_spec = spec("apps/cepaf_gleam/harness/core.gleam")
  let second_spec =
    sync.RequiredMapping(
      "apps/cepaf_gleam/harness/core.gleam",
      "model:cleanup",
      "code:cleanup",
      "rev-7",
    )
  let first_observation = mapped(first_spec.path)
  let second_observation =
    sync.MappingData(
      second_spec.path,
      Some("model:cleanup"),
      Some("code:cleanup"),
      Some("rev-7"),
      sync.MappedData,
    )
  let result =
    sync.assess(
      input([first_spec, second_spec], [first_observation, second_observation]),
    )
  result.paths
  |> should.equal([
    sync.PathFinding(
      "apps/cepaf_gleam/harness/core.gleam",
      "model:capacity",
      sync.ProvisionalMappingMatch,
    ),
    sync.PathFinding(
      "apps/cepaf_gleam/harness/core.gleam",
      "model:cleanup",
      sync.ProvisionalMappingMatch,
    ),
  ])
  result.provisional |> should.equal(sync.ProvisionalDataAligned)
  result.readiness |> should.equal(sync.HoldRuntimeEvidenceUnverified)
}

pub fn unattributable_observation_holds_even_with_exact_mapping_test() {
  let path = "apps/cepaf_gleam/harness/core.gleam"
  let result =
    sync.assess(
      input([spec(path)], [
        mapped(path),
        sync.MappingData(path, None, None, None, sync.UnknownData),
      ]),
    )
  result.paths
  |> should.equal([
    sync.PathFinding(path, "model:capacity", sync.ProvisionalMappingMatch),
  ])
  result.unexpected_mapping_keys
  |> should.equal([sync.MappingKey(path, None)])
  result.provisional |> should.equal(sync.HoldUnexpectedMappings)
  result.readiness |> should.equal(sync.HoldRuntimeEvidenceUnverified)
}
