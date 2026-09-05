//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/git/intelligence</module>
////     <fsharp-lineage>Cepaf.Git.Intelligence.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Git Commit Intelligence &amp; Analysis</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6</criticality>
////     <stamp-controls>SC-GLM-CORE-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/string

// =============================================================================
// Type Definitions
// =============================================================================

/// Conventional commit type classification.
pub type CommitType {
  Feat
  Fix
  Docs
  Refactor
  Test
  Chore
  Security
  Perf
  Ci
}

/// ICP scope — maps commits to mesh domains (23 variants).
pub type IcpScope {
  ScopeCore
  ScopePlanning
  ScopeZenoh
  ScopePodman
  ScopeTelemetry
  ScopeKnowledge
  ScopeImmune
  ScopeMetabolic
  ScopeSubstrate
  ScopeVerification
  ScopeSecurity
  ScopeUI
  ScopeGit
  ScopeMcp
  ScopeAgui
  ScopeKms
  ScopeBoot
  ScopeConfig
  ScopeDb
  ScopeCockpit
  ScopeHolon
  ScopePrajna
  ScopeInfra
}

/// Commit message style classification.
pub type CommitStyle {
  Conventional
  Imperative
  Descriptive
  Abbreviated
  Multiline
  Freeform
  Unknown
}

/// Validation issues found in commit messages.
pub type ValidationIssue {
  SubjectTooLong(length: Int)
  SubjectTooShort(length: Int)
  MissingType
  MissingScope
  NonImperative
  TrailingPeriod
}

/// Parsed commit message structure.
pub type ParsedCommit {
  ParsedCommit(
    commit_type: CommitType,
    scope: IcpScope,
    subject: String,
    body: String,
    breaking: Bool,
  )
}

/// Analysis result for a collection of commits.
pub type CommitAnalysis {
  CommitAnalysis(
    type_distribution: List(#(CommitType, Int)),
    scope_compliance: Float,
    health_score: Float,
  )
}

// =============================================================================
// Functions (10)
// =============================================================================

/// Convert a commit type to its string representation.
pub fn commit_type_to_string(ct: CommitType) -> String {
  case ct {
    Feat -> "feat"
    Fix -> "fix"
    Docs -> "docs"
    Refactor -> "refactor"
    Test -> "test"
    Chore -> "chore"
    Security -> "security"
    Perf -> "perf"
    Ci -> "ci"
  }
}

/// Convert an ICP scope to its string representation.
pub fn scope_to_string(scope: IcpScope) -> String {
  case scope {
    ScopeCore -> "core"
    ScopePlanning -> "planning"
    ScopeZenoh -> "zenoh"
    ScopePodman -> "podman"
    ScopeTelemetry -> "telemetry"
    ScopeKnowledge -> "knowledge"
    ScopeImmune -> "immune"
    ScopeMetabolic -> "metabolic"
    ScopeSubstrate -> "substrate"
    ScopeVerification -> "verification"
    ScopeSecurity -> "security"
    ScopeUI -> "ui"
    ScopeGit -> "git"
    ScopeMcp -> "mcp"
    ScopeAgui -> "agui"
    ScopeKms -> "kms"
    ScopeBoot -> "boot"
    ScopeConfig -> "config"
    ScopeDb -> "db"
    ScopeCockpit -> "cockpit"
    ScopeHolon -> "holon"
    ScopePrajna -> "prajna"
    ScopeInfra -> "infra"
  }
}

/// Map an ICP scope to its fractal layer string.
pub fn scope_to_fractal_layer(scope: IcpScope) -> String {
  case scope {
    ScopeCore | ScopeBoot -> "L0_CONSTITUTIONAL"
    ScopeDb | ScopeSubstrate -> "L1_ATOMIC_DEBUG"
    ScopeConfig | ScopeHolon -> "L2_COMPONENT"
    ScopePlanning | ScopePrajna -> "L3_TRANSACTION"
    ScopePodman | ScopeInfra -> "L4_SYSTEM"
    ScopeZenoh | ScopeTelemetry | ScopeKnowledge -> "L5_COGNITIVE"
    ScopeImmune | ScopeMetabolic | ScopeVerification -> "L6_ECOSYSTEM"
    ScopeSecurity
    | ScopeUI
    | ScopeGit
    | ScopeMcp
    | ScopeAgui
    | ScopeKms
    | ScopeCockpit -> "L7_FEDERATION"
  }
}

/// Classify a commit message into a style.
pub fn classify_style(message: String) -> CommitStyle {
  let trimmed = string.trim(message)
  case trimmed {
    "" -> Unknown
    _ -> {
      let has_colon = string.contains(trimmed, ":")
      let has_paren = string.contains(trimmed, "(")
      let line_count =
        string.split(trimmed, on: "\n")
        |> list.length
      let len = string.length(trimmed)

      case has_colon && has_paren {
        True -> Conventional
        False ->
          case line_count > 1 {
            True -> Multiline
            False ->
              case len < 10 {
                True -> Abbreviated
                False ->
                  case has_colon {
                    True -> Descriptive
                    False -> {
                      // Check for imperative mood (starts with capital verb-like)
                      let first_char =
                        string.slice(trimmed, at_index: 0, length: 1)
                      case first_char == string.uppercase(first_char) {
                        True -> Imperative
                        False -> Freeform
                      }
                    }
                  }
              }
          }
      }
    }
  }
}

/// Validate a commit subject line and return found issues.
pub fn validate_subject(subject: String) -> List(ValidationIssue) {
  let trimmed = string.trim(subject)
  let len = string.length(trimmed)
  let issues: List(ValidationIssue) = []

  // Check length
  let issues = case len > 72 {
    True -> [SubjectTooLong(length: len), ..issues]
    False -> issues
  }
  let issues = case len < 3 {
    True -> [SubjectTooShort(length: len), ..issues]
    False -> issues
  }

  // Check trailing period
  let issues = case string.ends_with(trimmed, ".") {
    True -> [TrailingPeriod, ..issues]
    False -> issues
  }

  // Check for type prefix
  let has_type =
    list.any(
      [
        "feat:",
        "fix:",
        "docs:",
        "refactor:",
        "test:",
        "chore:",
        "security:",
        "perf:",
        "ci:",
      ],
      fn(prefix) { string.starts_with(string.lowercase(trimmed), prefix) },
    )
    || list.any(
      [
        "feat(", "fix(", "docs(", "refactor(", "test(", "chore(", "security(",
        "perf(", "ci(",
      ],
      fn(prefix) { string.starts_with(string.lowercase(trimmed), prefix) },
    )

  let issues = case has_type {
    False -> [MissingType, ..issues]
    True -> issues
  }

  issues
}

/// Compute a health score from three normalized metrics (0.0 - 1.0 each).
/// Formula: weighted average with compliance_rate having highest weight.
pub fn compute_health_score(
  compliance_rate: Float,
  entropy_ratio: Float,
  consistency: Float,
) -> Float {
  // Weights: compliance=0.5, entropy=0.3, consistency=0.2
  let weighted =
    float.add(
      float.multiply(compliance_rate, 0.5),
      float.add(
        float.multiply(entropy_ratio, 0.3),
        float.multiply(consistency, 0.2),
      ),
    )
  // Clamp to [0.0, 1.0]
  float.min(1.0, float.max(0.0, weighted))
}

/// Compute the Shannon entropy of a commit type distribution.
pub fn type_entropy(types: List(CommitType)) -> Float {
  let total = int.to_float(list.length(types))
  case float.compare(total, 0.0) {
    order.Gt -> {
      let counts = count_types(types)
      let probs =
        list.map(counts, fn(pair) {
          let #(_, count) = pair
          float.divide(int.to_float(count), total)
          |> result.unwrap(0.0)
        })
      compute_shannon_entropy(probs)
    }
    _ -> 0.0
  }
}

/// Maximum possible entropy for n categories: log2(n).
pub fn max_entropy(n: Int) -> Float {
  case n > 0 {
    True -> log2(int.to_float(n))
    False -> 0.0
  }
}

/// Serialize a CommitAnalysis to JSON.
pub fn analysis_to_json(analysis: CommitAnalysis) -> json.Json {
  json.object([
    #(
      "type_distribution",
      json.array(analysis.type_distribution, fn(pair) {
        let #(ct, count) = pair
        json.object([
          #("type", json.string(commit_type_to_string(ct))),
          #("count", json.int(count)),
        ])
      }),
    ),
    #("scope_compliance", json.float(analysis.scope_compliance)),
    #("health_score", json.float(analysis.health_score)),
  ])
}

/// Serialize a ParsedCommit to JSON.
pub fn parsed_commit_to_json(commit: ParsedCommit) -> json.Json {
  json.object([
    #("type", json.string(commit_type_to_string(commit.commit_type))),
    #("scope", json.string(scope_to_string(commit.scope))),
    #("subject", json.string(commit.subject)),
    #("body", json.string(commit.body)),
    #("breaking", json.bool(commit.breaking)),
  ])
}

// =============================================================================
// Private helpers
// =============================================================================

@external(erlang, "math", "log")
fn math_log(x: Float) -> Float

fn ln2() -> Float {
  math_log(2.0)
}

fn log2(x: Float) -> Float {
  float.divide(math_log(x), ln2())
  |> result.unwrap(0.0)
}

fn compute_shannon_entropy(probs: List(Float)) -> Float {
  probs
  |> list.filter(fn(p) {
    case float.compare(p, 0.0) {
      order.Gt -> True
      _ -> False
    }
  })
  |> list.fold(0.0, fn(acc, p) {
    float.add(acc, float.negate(float.multiply(p, log2(p))))
  })
}

fn count_types(types: List(CommitType)) -> List(#(CommitType, Int)) {
  let all_variants = [
    Feat,
    Fix,
    Docs,
    Refactor,
    Test,
    Chore,
    Security,
    Perf,
    Ci,
  ]
  all_variants
  |> list.map(fn(variant) {
    let count =
      list.filter(types, fn(t) { t == variant })
      |> list.length
    #(variant, count)
  })
  |> list.filter(fn(pair) {
    let #(_, count) = pair
    count > 0
  })
}
