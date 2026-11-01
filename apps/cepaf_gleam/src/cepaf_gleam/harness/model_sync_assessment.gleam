//// Pure assessment of model/code synchronization DATA.
////
//// Matching candidate labels, revisions, paths, or SHA-shaped strings are
//// caller-supplied DATA only. This module reads no files, computes no actual
//// artifact hashes, authenticates no owner, performs no effects, and cannot
//// establish full integration. A complete-looking assessment remains HOLD:
//// actual hash verification, complete coverage, authenticated ownership,
//// refinement, and separate effect/release authorization remain external.
//// Inputs have no size bounds, and repeated list scans are quadratic in the
//// supplied mapping counts. No latency/capacity guarantee or live ingress is
//// established; bound and measure before any such integration.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Candidate metadata copied into an assessment. These fields are not proof
/// that the named candidate or manifest exists or that the string is a hash.
pub type CandidateData {
  CandidateData(
    candidate_id: String,
    revision: String,
    manifest_path: String,
    manifest_sha256: String,
  )
}

/// Expected model/code mapping fields, all treated as unauthenticated DATA.
pub type RequiredMapping {
  RequiredMapping(
    path: String,
    source_field: String,
    target_field: String,
    candidate_revision: String,
  )
}

/// A caller-supplied report about one path. `MappedData` is a label, not a
/// verified filesystem observation.
pub type MappingDataStatus {
  MappedData
  UnknownData
  StaleData
  UnmappedData
  UnsupportedData
}

pub type MappingData {
  MappingData(
    path: String,
    source_field: Option(String),
    target_field: Option(String),
    candidate_revision: Option(String),
    status: MappingDataStatus,
  )
}

pub type CandidateStatus {
  CandidateUnknown
  CandidateMatchedData
  CandidateRevisionMismatch
  CandidateFieldsMismatch
}

pub type PathStatus {
  ProvisionalMappingMatch
  Unknown
  Stale
  Unmapped
  Unsupported
  MappingFieldsMismatch
}

pub type PathFinding {
  PathFinding(path: String, source_field: String, status: PathStatus)
}

pub type MappingKey {
  MappingKey(path: String, source_field: Option(String))
}

pub type ProvisionalVerdict {
  ProvisionalDataAligned
  HoldMissingOrInvalidCandidate
  HoldCandidateRevisionMismatch
  HoldCandidateFieldsMismatch
  HoldEmptyRequiredPaths
  HoldDuplicateRequiredPaths
  HoldUnexpectedMappings
  HoldPathFindings
}

/// The only readiness this pure module can emit. There is no Ready/Granted
/// constructor, and no caller-provided boolean can change this value.
pub type Readiness {
  HoldRuntimeEvidenceUnverified
}

pub type AssessmentInput {
  AssessmentInput(
    expected_candidate: Option(CandidateData),
    observed_candidate: Option(CandidateData),
    required_mappings: List(RequiredMapping),
    mapping_data: List(MappingData),
  )
}

pub type Assessment {
  Assessment(
    candidate: CandidateStatus,
    paths: List(PathFinding),
    unexpected_mapping_keys: List(MappingKey),
    provisional: ProvisionalVerdict,
    readiness: Readiness,
  )
}

fn nonempty_data(value: String) -> Bool {
  string.length(value) > 0 && !string.contains(value, "\u{0000}")
}

/// Format check only. It does not calculate or authenticate a digest.
pub fn sha256_shaped_data(value: String) -> Bool {
  string.length(value) == 71
  && string.starts_with(value, "sha256:")
  && list.all(string.to_graphemes(string.drop_start(value, 7)), fn(char) {
    string.contains("0123456789abcdef", char)
  })
}

fn candidate_data_well_formed(candidate: CandidateData) -> Bool {
  nonempty_data(candidate.candidate_id)
  && nonempty_data(candidate.revision)
  && nonempty_data(candidate.manifest_path)
  && sha256_shaped_data(candidate.manifest_sha256)
}

fn mapping_spec_well_formed(mapping: RequiredMapping) -> Bool {
  nonempty_data(mapping.path)
  && nonempty_data(mapping.source_field)
  && nonempty_data(mapping.target_field)
  && nonempty_data(mapping.candidate_revision)
}

fn compare_candidates(
  expected: Option(CandidateData),
  observed: Option(CandidateData),
) -> CandidateStatus {
  case expected, observed {
    Some(wanted), Some(got) ->
      case
        candidate_data_well_formed(wanted) && candidate_data_well_formed(got)
      {
        False -> CandidateUnknown
        True ->
          case wanted.revision == got.revision {
            False -> CandidateRevisionMismatch
            True ->
              case
                wanted.candidate_id == got.candidate_id
                && wanted.manifest_path == got.manifest_path
                && wanted.manifest_sha256 == got.manifest_sha256
              {
                True -> CandidateMatchedData
                False -> CandidateFieldsMismatch
              }
          }
      }
    _, _ -> CandidateUnknown
  }
}

fn path_mappings(
  path: String,
  mappings: List(MappingData),
) -> List(MappingData) {
  list.filter(mappings, fn(mapping) { mapping.path == path })
}

fn matching_mappings(
  path: String,
  source_field: String,
  mappings: List(MappingData),
) -> List(MappingData) {
  list.filter(mappings, fn(mapping) {
    mapping.path == path && mapping.source_field == Some(source_field)
  })
}

fn evaluate_path(
  candidate_status: CandidateStatus,
  expected_candidate: Option(CandidateData),
  specification: RequiredMapping,
  observations: List(MappingData),
) -> PathStatus {
  case candidate_status {
    CandidateUnknown -> Unknown
    CandidateRevisionMismatch -> Stale
    CandidateFieldsMismatch -> MappingFieldsMismatch
    CandidateMatchedData ->
      case expected_candidate {
        None -> Unknown
        Some(candidate) ->
          case mapping_spec_well_formed(specification) {
            False -> Unknown
            True ->
              case specification.candidate_revision == candidate.revision {
                False -> Stale
                True ->
                  case
                    matching_mappings(
                      specification.path,
                      specification.source_field,
                      observations,
                    )
                  {
                    [] ->
                      case path_mappings(specification.path, observations) {
                        [] -> Unmapped
                        same_path ->
                          case
                            list.any(same_path, fn(mapping) {
                              mapping.source_field == None
                            })
                          {
                            True -> Unknown
                            False -> MappingFieldsMismatch
                          }
                      }
                    [only] -> evaluate_mapping_data(specification, only)
                    [_, ..] -> MappingFieldsMismatch
                  }
              }
          }
      }
  }
}

fn evaluate_mapping_data(
  specification: RequiredMapping,
  observation: MappingData,
) -> PathStatus {
  case observation.status {
    UnknownData -> Unknown
    StaleData -> Stale
    UnmappedData -> Unmapped
    UnsupportedData -> Unsupported
    MappedData ->
      case observation.candidate_revision {
        None -> Unknown
        Some(revision) ->
          case revision == specification.candidate_revision {
            False -> Stale
            True ->
              case observation.source_field, observation.target_field {
                Some(source), Some(target) ->
                  case
                    source == specification.source_field
                    && target == specification.target_field
                  {
                    True -> ProvisionalMappingMatch
                    False -> MappingFieldsMismatch
                  }
                _, _ -> Unknown
              }
          }
      }
  }
}

fn duplicate_required_mappings(mappings: List(RequiredMapping)) -> Bool {
  let keys =
    list.map(mappings, fn(mapping) { #(mapping.path, mapping.source_field) })
  list.length(keys) != list.length(list.unique(keys))
}

fn unexpected_mapping_keys(
  required: List(RequiredMapping),
  observations: List(MappingData),
) -> List(MappingKey) {
  observations
  |> list.filter(fn(observation) {
    case observation.source_field {
      Some(source_field) ->
        !list.any(required, fn(mapping) {
          mapping.path == observation.path
          && mapping.source_field == source_field
        })
      // A path-only report cannot be safely attributed to one required
      // source field, even when another exact pair is also present.
      None -> True
    }
  })
  |> list.map(fn(observation) {
    MappingKey(observation.path, observation.source_field)
  })
}

fn all_paths_provisional(paths: List(PathFinding)) -> Bool {
  paths != []
  && list.all(paths, fn(finding) { finding.status == ProvisionalMappingMatch })
}

/// Compares only supplied DATA. Empty required mappings, missing/invalid
/// candidates, duplicate (path, source_field) keys, extra mapped keys, any
/// unattributable observation, or any per-path defect fail closed. Even an
/// all-matching result remains HOLD.
pub fn assess(input: AssessmentInput) -> Assessment {
  let candidate =
    compare_candidates(input.expected_candidate, input.observed_candidate)
  let paths =
    list.map(input.required_mappings, fn(specification) {
      PathFinding(
        specification.path,
        specification.source_field,
        evaluate_path(
          candidate,
          input.expected_candidate,
          specification,
          input.mapping_data,
        ),
      )
    })
  let unexpected =
    unexpected_mapping_keys(input.required_mappings, input.mapping_data)
  let provisional = case input.required_mappings {
    [] -> HoldEmptyRequiredPaths
    _ ->
      case duplicate_required_mappings(input.required_mappings) {
        True -> HoldDuplicateRequiredPaths
        False ->
          case unexpected != [] {
            True -> HoldUnexpectedMappings
            False ->
              case candidate {
                CandidateUnknown -> HoldMissingOrInvalidCandidate
                CandidateRevisionMismatch -> HoldCandidateRevisionMismatch
                CandidateFieldsMismatch -> HoldCandidateFieldsMismatch
                CandidateMatchedData ->
                  case all_paths_provisional(paths) {
                    True -> ProvisionalDataAligned
                    False -> HoldPathFindings
                  }
              }
          }
      }
  }
  Assessment(
    candidate,
    paths,
    unexpected,
    provisional,
    HoldRuntimeEvidenceUnverified,
  )
}
