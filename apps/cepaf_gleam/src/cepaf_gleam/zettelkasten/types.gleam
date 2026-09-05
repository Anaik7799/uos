//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/types</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SMRITI-131, SC-IKE-001, SC-XHOLON-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Core types for the Indrajaal Zettelkasten — declarative long-term memory.
//// Implements the five forms of self-knowledge: Identity, History, Intent, Constraints, Aspiration.
//// STAMP: SC-SMRITI-131, SC-IKE-001, SC-IKE-002, SC-IKE-003

import gleam/option.{type Option}

/// Holon knowledge level — fractal hierarchy from atomic fact to ecosystem overview.
pub type HolonLevel {
  /// Single fact, constraint, function signature
  Atomic
  /// Actionable sequence: plan, spec, rule set
  Molecular
  /// Session narrative, incident report, feature chronicle
  Organism
  /// System-wide architecture, vision, evaluation framework
  Ecosystem
}

/// Rhetorical function — what role does this knowledge play?
pub type RhetoricalFunction {
  /// Non-negotiable truth: SC-* constraints, architectural decisions
  Axiom
  /// Testable claim: plans, predictions, cost estimates
  Hypothesis
  /// Observed fact: pipeline traces, test results, journal entries
  Evidence
  /// Subjective input: chat conversations, preferences
  Anecdote
}

/// Trust score derived from rhetorical function.
pub type TrustScore {
  TrustScore(value: Float, function: RhetoricalFunction)
}

/// Entropy decay rate — how fast does this knowledge become stale?
pub type DecayRate {
  /// Architecture docs, constraints — rarely change
  Slow
  /// Journal entries, specs — contextual relevance fades
  Medium
  /// Chat conversations, predictions — quickly outdated
  Fast
}

/// Knowledge source — where did this zettel come from?
pub type KnowledgeSource {
  /// Markdown document ingested from filesystem
  DocumentSource(path: String)
  /// Code module parsed for doc comments and STAMP refs
  CodeSource(module_path: String, language: String)
  /// Git commit message (ICP v2.0 format)
  GitCommitSource(sha: String)
  /// Pipeline trace auto-captured
  PipelineTraceSource(intent_id: String)
  /// Operator interaction (Telegram/GChat)
  InteractionSource(chat_id: String, intent_id: String)
  /// OODA decision recorded
  OodaDecisionSource(cycle_id: String)
  /// Cache learning event
  CacheLearningSource(prompt_hash: String)
  /// Session summary (Claude/Gemini)
  SessionSummarySource(session_id: String)
  /// Manual creation
  ManualSource(author: String)
}

/// A Holon (zettel) in the knowledge graph.
pub type Holon {
  Holon(
    uuid: String,
    title: String,
    content: String,
    tags: List(String),
    level: HolonLevel,
    rhetorical: RhetoricalFunction,
    entropy: Float,
    decay_rate: DecayRate,
    source: KnowledgeSource,
    content_hash: String,
    cluster: Option(String),
    stamp_refs: List(String),
    created_at: String,
    updated_at: String,
    verified_at: Option(String),
  )
}

/// Edge link type between holons.
pub type LinkType {
  /// Explicit wiki-style reference [[target]]
  Wiki
  /// Computed semantic similarity
  Semantic
  /// Code reference (module imports, SC-* citations)
  Code
  /// Auto-generated reverse link
  Backlink
}

/// An edge in the knowledge graph.
pub type HolonEdge {
  HolonEdge(
    source_id: String,
    target_id: String,
    link_type: LinkType,
    weight: Float,
  )
}

/// Self-knowledge category — the five forms from the metacognition vision.
pub type SelfKnowledge {
  /// "I know what I am" — architecture docs, CLAUDE.md
  Identity
  /// "I know what happened" — journals, git commits
  History
  /// "I know what I should do" — Allium specs, plans
  Intent
  /// "I know what I must not do" — SC-* constraints, rules
  Constraints
  /// "I know what I want to become" — vision docs, ultrathink mandates
  Aspiration
}

/// Auto-zettel trigger — what system event generates a new zettel?
pub type AutoZettelTrigger {
  OnGitCommit
  OnPipelineFinish
  OnOodaDecide
  OnCacheWrite
  OnApoptosisEvent
  OnTestRun
  OnSessionEnd
  OnFmeaAnalysis
}

// =============================================================================
// Constructors
// =============================================================================

/// Default trust score for a rhetorical function.
pub fn trust_for(function: RhetoricalFunction) -> TrustScore {
  let value = case function {
    Axiom -> 1.0
    Evidence -> 0.9
    Hypothesis -> 0.5
    Anecdote -> 0.3
  }
  TrustScore(value: value, function: function)
}

/// Default decay rate for a holon level.
pub fn decay_for_level(level: HolonLevel) -> DecayRate {
  case level {
    Ecosystem -> Slow
    Molecular -> Medium
    Organism -> Medium
    Atomic -> Fast
  }
}

/// Map a document path to the appropriate holon level.
pub fn level_for_path(path: String) -> HolonLevel {
  case path {
    "docs/architecture/" <> _ -> Ecosystem
    "docs/journal/" <> _ -> Organism
    "docs/plans/" <> _ -> Molecular
    "specs/allium/" <> _ -> Molecular
    "specs/tla/" <> _ -> Molecular
    "specs/formal/" <> _ -> Molecular
    "specs/wolfram/" <> _ -> Molecular
    ".claude/rules/" <> _ -> Atomic
    _ -> Atomic
  }
}

/// Map a document path to rhetorical function.
pub fn rhetorical_for_path(path: String) -> RhetoricalFunction {
  case path {
    ".claude/rules/" <> _ -> Axiom
    "docs/architecture/" <> _ -> Axiom
    "specs/" <> _ -> Hypothesis
    "docs/plans/" <> _ -> Hypothesis
    "docs/journal/" <> _ -> Evidence
    _ -> Anecdote
  }
}

/// Map a document path to self-knowledge category.
pub fn self_knowledge_for_path(path: String) -> SelfKnowledge {
  case path {
    "docs/architecture/" <> _ -> Identity
    "docs/journal/" <> _ -> History
    "specs/allium/" <> _ -> Intent
    "docs/plans/" <> _ -> Intent
    ".claude/rules/" <> _ -> Constraints
    _ -> Identity
  }
}

/// Level to string for DB storage.
pub fn level_to_string(level: HolonLevel) -> String {
  case level {
    Atomic -> "atomic"
    Molecular -> "molecular"
    Organism -> "organism"
    Ecosystem -> "ecosystem"
  }
}

/// Decay rate to string for DB storage.
pub fn decay_to_string(rate: DecayRate) -> String {
  case rate {
    Slow -> "slow"
    Medium -> "medium"
    Fast -> "fast"
  }
}

/// Link type to string for DB storage.
pub fn link_type_to_string(lt: LinkType) -> String {
  case lt {
    Wiki -> "wiki"
    Semantic -> "semantic"
    Code -> "code"
    Backlink -> "backlink"
  }
}
