pub type Entry {
  Entry(path: String, sha256: String)
}

pub type ReadError {
  NotFound
  CannotRead
}

pub type Finding {
  Changed(path: String)
  Missing(path: String)
  Unreadable(path: String)
  InvalidInventory(reason: String)
}

pub type ReadDepth {
  UnreadableDepth
  Indexed
  Hashed
  CloseRead
}

pub type SourceKind {
  TestSource
  HelperSource
  Document
  Generated
  Binary
}

pub type ExecutionState {
  Unrun
  Passed
  Failed
  Skipped
  Unknown
}

pub type CensusInput {
  CensusInput(
    files: List(String),
    registered_tests: List(String),
    ast_sites: Int,
    unreadable: List(String),
  )
}

pub type CensusRecord {
  CensusRecord(
    source_id: String,
    path: String,
    kind: SourceKind,
    registered: Bool,
    oracle: String,
    coverage_scope: String,
    browser_class: String,
    transfer: String,
    runner: String,
    execution_state: ExecutionState,
    read_depth: ReadDepth,
  )
}

pub type CensusSummary {
  CensusSummary(
    records: List(CensusRecord),
    files_accounted: Int,
    unreadable_count: Int,
    complete_review: Bool,
    executed_tests: Int,
    registered_test_files: Int,
    ast_sites: Int,
    reviewed_files: Int,
    classified_exclusions: Int,
    frontier_count: Int,
    review_frontier: List(String),
  )
}

pub type CensusObservation {
  CensusObservation(
    files_accounted: Int,
    unreadable_count: Int,
    complete_review: Bool,
    executed_tests: Int,
    registered_test_files: Int,
    ast_sites: Int,
    reviewed_files: Int,
    classified_exclusions: Int,
    frontier_count: Int,
    review_frontier: List(String),
  )
}

pub type CensusError {
  EmptyScope
  TooManyFiles
  InvalidAstSiteCount
  NoncanonicalPath
  DuplicatePath
  RegisteredTestOutsideScope
  UnreadableOutsideScope
}

fn unique(values: List(String)) -> Bool {
  let #(_, unique) =
    list.fold(values, #(set.new(), True), fn(acc, value) {
      let #(seen, unique) = acc
      #(set.insert(seen, value), unique && !set.contains(seen, value))
    })
  unique
}

fn subset(values: List(String), members: List(String)) -> Bool {
  list.all(values, fn(value) { list.contains(members, value) })
}

pub fn validate_census(input: CensusInput) -> Result(CensusInput, CensusError) {
  case input {
    CensusInput(files, registered_tests, ast_sites, unreadable) ->
      case
        files,
        list.length(files) > 100_000,
        ast_sites < 0 || ast_sites > 10_000_000,
        list.all(files, canonical_relative_path),
        unique(files) && unique(registered_tests) && unique(unreadable),
        subset(registered_tests, files),
        subset(unreadable, files)
      {
        [], _, _, _, _, _, _ -> Error(EmptyScope)
        _, True, _, _, _, _, _ -> Error(TooManyFiles)
        _, _, True, _, _, _, _ -> Error(InvalidAstSiteCount)
        _, _, _, False, _, _, _ -> Error(NoncanonicalPath)
        _, _, _, _, False, _, _ -> Error(DuplicatePath)
        _, _, _, _, _, False, _ -> Error(RegisteredTestOutsideScope)
        _, _, _, _, _, _, False -> Error(UnreadableOutsideScope)
        _, False, False, True, True, True, True -> Ok(input)
      }
  }
}

fn path_kind(path: String, registered: Bool) -> SourceKind {
  case
    registered,
    string.ends_with(path, ".md"),
    string.ends_with(path, ".beam")
    || string.ends_with(path, ".cmx")
    || string.ends_with(path, ".cmo"),
    string.ends_with(path, ".generated") || string.contains(path, "~")
  {
    True, _, _, _ -> TestSource
    False, True, _, _ -> Document
    False, _, True, _ -> Binary
    False, _, _, True -> Generated
    False, False, False, False -> HelperSource
  }
}

fn runner(path: String, registered: Bool) -> String {
  case
    registered,
    string.ends_with(path, ".ml"),
    string.ends_with(path, ".gleam"),
    string.ends_with(path, ".exs"),
    string.ends_with(path, ".feature")
  {
    False, _, _, _, _ -> "none"
    True, True, _, _, _ -> "dune/ocaml test registration"
    True, _, True, _, _ -> "gleeunit"
    True, _, _, True, _ -> "exunit"
    True, _, _, _, True -> "gherkin"
    True, False, False, False, False -> "registered runner requires review"
  }
}

fn census_record(input: CensusInput, path: String) -> CensusRecord {
  let CensusInput(_, registered_tests, _, unreadable) = input
  let registered = list.contains(registered_tests, path)
  let kind = path_kind(path, registered)
  let transfer = case kind {
    TestSource -> "PORT_CANDIDATE"
    Generated | Binary -> "EXCLUDE_GENERATED_OR_BINARY"
    HelperSource | Document -> "RETAIN_EVIDENCE"
  }
  CensusRecord(
    source_id: "uos:census:v1:" <> string.slice(digest(<<path:utf8>>), 0, 24),
    path: path,
    kind: kind,
    registered: registered,
    oracle: case registered {
      True -> "oracle pending per-case close reading"
      False -> "not a registered test case"
    },
    coverage_scope: case registered {
      True -> "registered file; AST sites are aggregate input evidence"
      False -> "source classification only"
    },
    browser_class: "BROWSER_REVIEW_REQUIRED",
    transfer: transfer,
    runner: runner(path, registered),
    execution_state: Unrun,
    read_depth: case list.contains(unreadable, path) {
      True -> UnreadableDepth
      False -> Indexed
    },
  )
}

fn summarize(input: CensusInput, records: List(CensusRecord)) -> CensusSummary {
  let CensusInput(_, registered_tests, ast_sites, _) = input
  let unreadable_count =
    records
    |> list.filter(fn(record) { record.read_depth == UnreadableDepth })
    |> list.length
  let review_frontier =
    list.filter_map(records, fn(record) {
      case record.kind, record.read_depth {
        Generated, _ | Binary, _ -> Error(Nil)
        _, CloseRead -> Error(Nil)
        _, UnreadableDepth -> Ok(record.path <> ":unreadable")
        _, Indexed -> Ok(record.path <> ":indexed_not_close_read")
        _, Hashed -> Ok(record.path <> ":hashed_not_close_read")
      }
    })
  let reviewed_files =
    records
    |> list.filter(fn(record) { record.read_depth == CloseRead })
    |> list.length
  let classified_exclusions =
    records
    |> list.filter(fn(record) {
      record.kind == Generated || record.kind == Binary
    })
    |> list.length
  CensusSummary(
    records: records,
    files_accounted: list.length(records),
    unreadable_count: unreadable_count,
    complete_review: list.is_empty(review_frontier),
    executed_tests: 0,
    registered_test_files: list.length(registered_tests),
    ast_sites: ast_sites,
    reviewed_files: reviewed_files,
    classified_exclusions: classified_exclusions,
    frontier_count: list.length(review_frontier),
    review_frontier: review_frontier,
  )
}

/// Initial list interpretation used as the independent census oracle.
pub fn classify_census_reference(
  input: CensusInput,
) -> Result(CensusSummary, CensusError) {
  use input <- result.try(validate_census(input))
  let CensusInput(files, _, _, _) = input
  files
  |> list.map(census_record(input, _))
  |> summarize(input, _)
  |> Ok
}

/// Fold interpretation used by the production inventory path.
pub fn classify_census(
  input: CensusInput,
) -> Result(CensusSummary, CensusError) {
  use input <- result.try(validate_census(input))
  let CensusInput(files, _, _, _) = input
  files
  |> list.fold([], fn(records, path) { [census_record(input, path), ..records] })
  |> list.reverse
  |> summarize(input, _)
  |> Ok
}

pub fn observe_census(summary: CensusSummary) -> CensusObservation {
  CensusObservation(
    files_accounted: summary.files_accounted,
    unreadable_count: summary.unreadable_count,
    complete_review: summary.complete_review,
    executed_tests: summary.executed_tests,
    registered_test_files: summary.registered_test_files,
    ast_sites: summary.ast_sites,
    reviewed_files: summary.reviewed_files,
    classified_exclusions: summary.classified_exclusions,
    frontier_count: summary.frontier_count,
    review_frontier: summary.review_frontier,
  )
}

pub fn verify_entries(
  entries: List(Entry),
  read: fn(String) -> Result(BitArray, ReadError),
) -> List(Finding) {
  let invalid = validate(entries)
  case invalid {
    [] ->
      list.filter_map(entries, fn(entry) {
        case read(entry.path) {
          Error(NotFound) -> Ok(Missing(entry.path))
          Error(CannotRead) -> Ok(Unreadable(entry.path))
          Ok(bytes) ->
            case digest(bytes) == entry.sha256 {
              True -> Error(Nil)
              False -> Ok(Changed(entry.path))
            }
        }
      })
    _ -> invalid
  }
}

pub fn digest(bytes: BitArray) -> String {
  bytes
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn canonical_relative_path(path: String) -> Bool {
  !string.contains(path, "\\")
  && !string.contains(path, "\u{0}")
  && list.all(string.split(path, "/"), fn(segment) {
    segment != "" && segment != "." && segment != ".."
  })
}

pub fn validate(entries: List(Entry)) -> List(Finding) {
  let count = list.length(entries)
  case count == 0 || count > 100_000 {
    True -> [InvalidInventory("expected 1..100000 entries")]
    False -> {
      let #(_, errors) =
        list.fold(entries, #(set.new(), []), fn(acc, entry) {
          let #(seen, errors) = acc
          let error = case canonical_relative_path(entry.path) {
            False -> [
              InvalidInventory("noncanonical relative path: " <> entry.path),
            ]
            True ->
              case set.contains(seen, entry.path) {
                True -> [InvalidInventory("duplicate path: " <> entry.path)]
                False ->
                  case
                    string.length(entry.sha256) == 64
                    && list.all(string.to_graphemes(entry.sha256), fn(c) {
                      string.contains("0123456789abcdef", c)
                    })
                  {
                    True -> []
                    False -> [
                      InvalidInventory("invalid SHA256: " <> entry.path),
                    ]
                  }
              }
          }
          #(set.insert(seen, entry.path), list.append(errors, error))
        })
      errors
    }
  }
}

import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/result
import gleam/set
import gleam/string
