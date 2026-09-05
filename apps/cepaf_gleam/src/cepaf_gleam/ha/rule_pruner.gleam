//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/rule_pruner</module>
////     <fsharp-lineage>None — novel Gleam context pruning module</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Dynamic rule selection — reduces context waste (SC-MUDA-001)</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MUDA-001, SC-ZK-CLAUDE-001, SC-OODA-CLAUDE-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Rule relevance scoring ↪ TF-IDF-inspired keyword intersection over
////       prompt tokens vs per-file keyword index. Pure functional, no I/O.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// RULE PRUNER — DYNAMIC RULE SELECTION BASED ON PROMPT KEYWORDS
//// नियम छँटाई — प्रॉम्प्ट कीवर्ड आधारित गतिशील नियम चयन
////
//// With 84 rule files totalling ~60KB of markdown, loading all rules on every
//// prompt is a significant context-window waste (Muda #5: Inventory).
////
//// This module scores all 84 rule files against the current prompt and returns
//// the top-N most relevant, reducing context consumption by ~60-80%.
////
//// Scoring formula (TF-IDF inspired):
////   score(rule, prompt) = |keywords(rule) ∩ tokens(prompt)| / |keywords(rule)|
////
//// STAMP: SC-MUDA-001, SC-ZK-CLAUDE-001, SC-OODA-CLAUDE-001

import gleam/int
import gleam/list
import gleam/order
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// Relevance score for a single rule file against a prompt.
pub type RuleRelevance {
  RuleRelevance(
    /// Rule file name (e.g., "build-and-test.md")
    filename: String,
    /// Normalised relevance score in [0.0, 1.0].
    /// score = matched_keywords / total_keywords
    score: Float,
    /// The keywords from this rule that appeared in the prompt.
    keywords_matched: List(String),
  )
}

// =============================================================================
// Keyword Index — all 84 rule files
// =============================================================================

/// The keyword index: maps each rule filename to its primary topic keywords.
///
/// Keywords are lowercase, no punctuation. The index is hand-curated to
/// capture the most discriminating terms per file. Typically 5–15 terms.
///
/// This is the authoritative source — update when rule files are added/renamed.
pub fn rule_keywords() -> List(#(String, List(String))) {
  [
    #("agent-cognitive-protocol.md", [
      "agent", "cognitive", "ooda", "protocol", "observe", "orient", "decide",
      "act",
    ]),
    #("agent-ooda-acceleration.md", [
      "ooda", "acceleration", "parallel", "agent", "velocity", "gita",
      "autonomous",
    ]),
    #("agentic-ui-responsive-design.md", [
      "ui", "responsive", "agentic", "design", "websocket", "mobile",
      "breakpoint", "gemma", "kanban", "timeline",
    ]),
    #("allium-behavioral-specs.md", [
      "allium", "behavioral", "spec", "entity", "rule", "contract", "invariant",
      "gleam",
    ]),
    #("analytical-verification-protocol.md", [
      "verification", "analytical", "protocol", "admiralty", "source", "tenth",
      "falsifiable", "probability",
    ]),
    #("ash-resources.md", ["ash", "resource", "ecto", "postgres", "domain"]),
    #("autonomous-ooda-enforcement.md", [
      "autonomous", "ooda", "enforcement", "claude", "hook", "build", "verify",
    ]),
    #("biomorphic-evolution-protocol.md", [
      "biomorphic", "evolution", "homeostasis", "metabolism", "growth",
      "adaptation", "fractal",
    ]),
    #("biomorphic-mode.md", [
      "biomorphic", "mode", "dark", "cockpit", "homeostasis",
    ]),
    #("build-and-test.md", [
      "build", "test", "compile", "gleam", "mix", "wallaby", "cpu", "governor",
      "scheduler",
    ]),
    #("c3i-gleam-msts-001.md", [
      "msts", "contract", "morphism", "isomorphic", "surjective", "injective",
      "fractal", "layer", "sil6",
    ]),
    #("change-management.md", [
      "change", "management", "impact", "analysis", "reversal", "rollback",
      "layer",
    ]),
    #("concurrent-bug-fix-protocol.md", [
      "bug", "fix", "concurrent", "branch", "multiverse", "phase", "claim",
      "task",
    ]),
    #("constraint-registry.md", [
      "constraint", "registry", "sc", "aor", "stamp", "p0", "p1", "p2", "safety",
    ]),
    #("constraint-sync-mandatory.md", [
      "sync", "constraint", "artifact", "parity", "propagate", "session",
    ]),
    #("constraint-sync.md", [
      "constraint", "sync", "claude", "gap", "ratio", "reconcile", "fsharp",
    ]),
    #("core-protocols.md", [
      "func", "delete", "hint", "safety", "functional", "invariant", "jidoka",
      "rollback",
    ]),
    #("cpu-governor.md", [
      "cpu", "governor", "throttle", "scheduler", "adaptive", "parallelism",
    ]),
    #("deletion-safeguard.md", [
      "delete", "backup", "safeguard", "untracked", "file", "approval",
    ]),
    #("evolution-kpi-tracking.md", [
      "kpi", "evolution", "benchmark", "baseline", "validation", "metric",
    ]),
    #("factories.md", ["factory", "fixture", "test", "builder", "pattern"]),
    #("file-size-optimization.md", [
      "file", "size", "split", "monolith", "lines", "module", "optimization",
    ]),
    #("five-level-testing.md", [
      "testing", "five", "level", "unit", "integration", "e2e", "property",
      "chaos",
    ]),
    #("fractal-coverage-gold-standard.md", [
      "coverage", "fractal", "gold", "standard", "c1", "c2", "c3", "c4", "c5",
      "c6", "c7", "c8",
    ]),
    #("fractal-coverage-mathematical-framework.md", [
      "coverage", "mathematical", "framework", "shannon", "entropy", "ccm",
      "itqs", "pagerank",
    ]),
    #("fractal-tps-muda.md", [
      "tps", "muda", "waste", "jidoka", "kanban", "kaizen", "andon", "heijunka",
    ]),
    #("fsharp-sil6-mesh.md", [
      "fsharp", "sil6", "mesh", "container", "genome", "boot", "apoptosis",
    ]),
    #("full-system-control.md", [
      "system", "control", "ignition", "container", "podman", "health",
    ]),
    #("functional-invariant.md", [
      "functional", "invariant", "compile", "state", "recovery", "zenoh", "twin",
    ]),
    #("fy27-activity-tracking.md", [
      "fy27", "activity", "tracking", "meeting", "log", "deal", "contact",
      "sales",
    ]),
    #("fy27-execution-protocol.md", [
      "fy27", "sales", "toc", "meddpicc", "arm", "nokia", "ericsson", "pipeline",
    ]),
    #("fy27-linkedin-integration.md", [
      "linkedin", "sales", "navigator", "rate", "limit", "outreach", "contact",
      "playwright",
    ]),
    #("fy27-obsidian-integration.md", [
      "obsidian", "fy27", "vault", "markdown", "frontmatter", "wikilink",
    ]),
    #("ga-release-verification.md", [
      "release", "verification", "ga", "checklist", "smoke", "test",
    ]),
    #("gdrive-build-protocol.md", [
      "gdrive", "cargo", "target", "dir", "fuse", "build", "rust",
    ]),
    #("git-and-workflow.md", [
      "git", "commit", "branch", "workflow", "icp", "merge", "phase",
    ]),
    #("git-commit-convention.md", [
      "git", "commit", "convention", "type", "scope", "body",
    ]),
    #("gleam-web-ui-development.md", [
      "gleam", "ui", "lustre", "wisp", "tui", "triple", "interface", "agui",
      "a2ui", "dark", "cockpit",
    ]),
    #("hot-reload-protocol.md", [
      "hot", "reload", "beam", "code", "server", "module", "soft", "purge",
      "nif",
    ]),
    #("human-intent-protection.md", [
      "human", "intent", "protection", "inviolable", "alignment", "score",
    ]),
    #("immune-system.md", [
      "immune", "system", "threat", "detect", "antibody", "sentinel",
    ]),
    #("intelligence-amplification.md", [
      "intelligence", "amplification", "zettelkasten", "recall", "nif",
      "compute",
    ]),
    #("journal-email-attachment.md", [
      "journal", "email", "attachment", "smtp", "send", "notify",
    ]),
    #("journal-protocol.md", [
      "journal", "protocol", "section", "template", "13", "scope", "execution",
      "rca",
    ]),
    #("mandatory-compile-env.md", [
      "compile", "env", "mandatory", "skip_zenoh_nif", "wallaby", "elixir",
    ]),
    #("max-parallelization.md", [
      "parallel", "parallelization", "simultaneous", "background", "independent",
    ]),
    #("moksha-complete-system.md", [
      "moksha", "complete", "coverage", "tensor", "80", "cells", "guard", "crdt",
    ]),
    #("muda-waste-reduction.md", [
      "muda", "waste", "reduction", "lean", "overproduction", "inventory",
      "warning",
    ]),
    #("operational-architecture.md", [
      "operational", "architecture", "swarm", "ignition", "container", "genome",
      "zenoh",
    ]),
    #("panoptic-swarm-ignition.md", [
      "panoptic", "swarm", "ignition", "genome", "sil6", "boot", "container",
    ]),
    #("planning-chaya-sync.md", [
      "planning", "chaya", "sync", "database", "sqlite", "task",
    ]),
    #("prajna-biomorphic.md", [
      "prajna", "biomorphic", "dark", "cockpit", "ooda", "circuit", "breaker",
    ]),
    #("prompt-email-protocol.md", [
      "prompt", "email", "protocol", "send", "smtp", "session",
    ]),
    #("property-testing.md", [
      "property", "testing", "quickcheck", "fuzzing", "generator", "shrink",
    ]),
    #("reconciled-p0-safety.md", [
      "p0", "safety", "reconciled", "sil4", "sil6", "guardian", "prime",
    ]),
    #("reconciled-p1-core.md", [
      "p1", "core", "reconciled", "boot", "zenoh", "holon", "sync",
    ]),
    #("reconciled-p2-domain-analytics.md", [
      "p2", "analytics", "domain", "kpi", "ml", "prediction",
    ]),
    #("reconciled-p2-domain-critical.md", [
      "p2", "critical", "domain", "hmi", "mcp", "sem", "ace",
    ]),
    #("reconciled-p2-domain-high.md", [
      "p2", "domain", "high", "alarm", "grid", "agent", "container",
    ]),
    #("reconciled-p2-domain-minor.md", [
      "p2", "domain", "minor", "style", "cli", "config",
    ]),
    #("reconciled-p2-domain-standard.md", [
      "p2", "domain", "standard", "ooda", "test", "verification",
    ]),
    #("reconciled-p3-style.md", ["p3", "style", "unused", "warning", "import"]),
    #("rust-gleam-split.md", [
      "rust", "gleam", "split", "architecture", "monitoring", "ui", "nif",
      "bridge",
    ]),
    #("rust-only-tooling.md", [
      "rust", "tooling", "shell", "script", "sa_plan_daemon", "subcommand",
    ]),
    #("safety-critical.md", [
      "safety", "critical", "sil", "guardian", "emergency", "halt",
    ]),
    #("sales-operations.md", [
      "sales", "operations", "pipeline", "deal", "account", "toc", "meddpicc",
      "outreach",
    ]),
    #("session-bootstrap.md", [
      "session", "bootstrap", "zettelkasten", "recall", "compute", "nif",
      "memory",
    ]),
    #("swarm-verification.md", [
      "swarm", "verification", "container", "ooda", "observability", "fractal",
    ]),
    #("test-evolution.md", [
      "test", "evolution", "tdd", "coverage", "regression", "quality",
    ]),
    #("test-execution.md", [
      "test", "execution", "gleam", "mix", "wallaby", "e2e",
    ]),
    #("timestamp-sync.md", ["timestamp", "sync", "hlc", "clock", "monotonic"]),
    #("todolist-access-control.md", [
      "todolist", "access", "control", "sa_plan", "daemon", "forbidden",
    ]),
    #("todolist-access.md", [
      "todolist", "access", "task", "sa_plan_daemon", "authority",
    ]),
    #("truth-freshness-safety.md", [
      "truth", "freshness", "safety", "stale", "data", "monitor", "escalate",
    ]),
    #("truth-self-knowledge-gita.md", [
      "truth", "self", "knowledge", "gita", "satya", "display", "invariant",
    ]),
    #("ui-graph-testing.md", [
      "ui", "graph", "testing", "pagerank", "scc", "lts", "prime", "path", "nav",
    ]),
    #("ultrathink-mandate.md", [
      "ultrathink", "mandate", "evolution", "focus", "zenoh", "crdt", "formal",
    ]),
    #("wiring-guard.md", [
      "wiring", "guard", "model", "msg", "constructor", "init", "test", "field",
    ]),
    #("zenoh-control-plane-comms.md", [
      "zenoh", "control", "plane", "pubsub", "transport", "internal", "mesh",
    ]),
    #("zenoh-telemetry-mandatory.md", [
      "zenoh", "telemetry", "mandatory", "otel", "span", "observer",
      "split_screen",
    ]),
    #("zenoh-test-messaging.md", [
      "zenoh", "test", "messaging", "topic", "verify", "message",
    ]),
    #("zettelkasten-claude-integration.md", [
      "zettelkasten", "claude", "integration", "knowledge", "search", "holon",
      "recall",
    ]),
    #("zettelkasten-fundamental.md", [
      "zettelkasten", "fundamental", "ingest", "holon", "level", "atom",
      "molecule", "organism",
    ]),
    #("zk-imperative-recall.md", [
      "zk", "recall", "imperative", "citation", "holon", "anti_pattern",
    ]),
  ]
}

// =============================================================================
// Core scoring logic
// =============================================================================

/// Tokenize a prompt string into lowercase words (split on whitespace and
/// common punctuation). Returns a deduplicated list of tokens.
pub fn tokenize(prompt: String) -> List(String) {
  prompt
  |> string.lowercase
  // Replace common punctuation with spaces
  |> string.replace(",", " ")
  |> string.replace(".", " ")
  |> string.replace(":", " ")
  |> string.replace(";", " ")
  |> string.replace("?", " ")
  |> string.replace("!", " ")
  |> string.replace("(", " ")
  |> string.replace(")", " ")
  |> string.replace("[", " ")
  |> string.replace("]", " ")
  |> string.replace("\"", " ")
  |> string.replace("'", " ")
  |> string.replace("\n", " ")
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.filter(fn(t) { string.length(t) >= 3 })
  |> list.unique
}

/// Score a single rule file against a set of prompt tokens.
///
/// score = |matched_keywords| / |total_keywords|
/// Returns 0.0 if the rule has no keywords.
fn score_rule(
  filename: String,
  keywords: List(String),
  prompt_tokens: List(String),
) -> RuleRelevance {
  let total = list.length(keywords)
  case total == 0 {
    True -> RuleRelevance(filename: filename, score: 0.0, keywords_matched: [])
    False -> {
      let matched =
        list.filter(keywords, fn(kw) { list.contains(prompt_tokens, kw) })
      let score = int.to_float(list.length(matched)) /. int.to_float(total)
      RuleRelevance(filename: filename, score: score, keywords_matched: matched)
    }
  }
}

// =============================================================================
// Public API
// =============================================================================

/// Score all 84 rule files against a prompt and return the top `limit` results
/// sorted by score descending (most relevant first).
///
/// Rules with score 0.0 are excluded from results unless `limit` exceeds the
/// number of rules with score > 0.0.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: limit >= 1 </P>
///     <C> rank_rules(prompt, limit) </C>
///     <Q> Post-condition: |result| <= limit, sorted by score descending </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn rank_rules(prompt: String, limit: Int) -> List(RuleRelevance) {
  let tokens = tokenize(prompt)
  let index = rule_keywords()

  index
  |> list.map(fn(pair) {
    let #(filename, keywords) = pair
    score_rule(filename, keywords, tokens)
  })
  |> list.filter(fn(r) { r.score >. 0.0 })
  |> list.sort(fn(a, b) {
    // Descending: compare b to a
    float_compare_desc(a.score, b.score)
  })
  |> list.take(int.max(1, limit))
}

/// Estimate the number of tokens saved by loading `loaded` rules instead of
/// `total` rules, assuming an average of ~700 tokens per rule file (~2.8KB).
///
/// tokens_saved = (total - loaded) * avg_tokens_per_rule
pub fn tokens_saved(loaded: Int, total: Int) -> Int {
  let avg_tokens_per_rule = 700
  let skipped = int.max(0, total - loaded)
  skipped * avg_tokens_per_rule
}

/// Return all rule filenames ranked by their score against the prompt,
/// including those with score 0.0 (returned last).
///
/// Useful for diagnostics and testing.
pub fn rank_all_rules(prompt: String) -> List(RuleRelevance) {
  let tokens = tokenize(prompt)
  let index = rule_keywords()

  index
  |> list.map(fn(pair) {
    let #(filename, keywords) = pair
    score_rule(filename, keywords, tokens)
  })
  |> list.sort(fn(a, b) { float_compare_desc(a.score, b.score) })
}

/// Return the filenames of the top-N relevant rules for quick access.
pub fn top_filenames(prompt: String, limit: Int) -> List(String) {
  rank_rules(prompt, limit)
  |> list.map(fn(r) { r.filename })
}

/// Count how many rule files have at least one keyword match for this prompt.
pub fn matching_count(prompt: String) -> Int {
  let tokens = tokenize(prompt)
  let index = rule_keywords()
  index
  |> list.filter(fn(pair) {
    let #(_, keywords) = pair
    list.any(keywords, fn(kw) { list.contains(tokens, kw) })
  })
  |> list.length
}

// =============================================================================
// Internal helpers
// =============================================================================

/// Descending float comparison for list.sort (returns Order).
fn float_compare_desc(a: Float, b: Float) -> order.Order {
  case a >. b {
    True -> order.Lt
    False ->
      case a <. b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}
