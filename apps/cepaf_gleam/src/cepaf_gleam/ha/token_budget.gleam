//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/token_budget</module>
////     <fsharp-lineage>None — novel context-budget estimation module (CE5)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Claude context-window token-budget estimation and alerting</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MUDA-001, SC-ARCH-SPLIT-002, SC-BOOTSTRAP-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Empirical token estimates ↪ TokenBudget struct with warning thresholds.
////       Enables proactive /compact before context exhaustion.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CLAUDE CONTEXT-WINDOW TOKEN BUDGET — Proactive /compact gating (CE5)
//// क्लॉड संदर्भ-विंडो टोकन बजट — सक्रिय /compact गेटिंग
////
//// Estimates how many tokens each structural input layer consumes so the
//// operator knows when to issue /compact or begin a new session.
////
//// Budget breakdown (Claude Sonnet/Opus, 200 000-token context):
////   • Rules (~84 files × ~180 tokens each)  ≈ 15 120 tokens
////   • MEMORY.md (~500 lines × ~4 tok/line)  ≈  2 000 tokens
////   • CLAUDE.md (~1 250 lines × ~4 tok/line)≈  5 000 tokens
////   • SessionStart + UserPromptSubmit hooks  ≈    700 tokens
////   • Conversation grows linearly per turn
////
//// Mathematical model:
////   remaining(t) = capacity - rules - memory - claude_md - hooks - Σconv(t)
////   warning_threshold  = 0.25 × capacity  (75% consumed)
////   critical_threshold = 0.10 × capacity  (90% consumed)
////
//// STAMP: SC-MUDA-001, SC-ARCH-SPLIT-002, SC-BOOTSTRAP-001
////
//// संकल्पात् कामः संजायते — From determination arises desire; from context
//// exhaustion arises confusion. Guard the budget. (inspired by Gita 2.62)

import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Snapshot of how the 200 000-token context window is allocated.
pub type TokenBudget {
  TokenBudget(
    /// Total context-window capacity in tokens.
    capacity: Int,
    /// Estimated tokens consumed by loaded rules (~84 rule files).
    rules_tokens: Int,
    /// Estimated tokens consumed by MEMORY.md.
    memory_tokens: Int,
    /// Estimated tokens consumed by CLAUDE.md.
    claude_md_tokens: Int,
    /// Estimated tokens consumed by SessionStart + UserPromptSubmit hook output.
    hook_tokens: Int,
    /// Cumulative tokens consumed by the conversation so far (grows per turn).
    conversation_tokens: Int,
    /// Remaining capacity: capacity - (all above).
    remaining: Int,
  )
}

// ---------------------------------------------------------------------------
// Constants — empirical baselines
// ---------------------------------------------------------------------------

/// Claude Sonnet/Opus context window: 200 000 tokens.
const default_capacity: Int = 200_000

/// Approximate tokens for ~84 loaded rule files at ~180 tokens each.
const default_rules_tokens: Int = 15_120

/// Approximate tokens for MEMORY.md (~500 lines).
const default_memory_tokens: Int = 2000

/// Approximate tokens for CLAUDE.md (~1 250 lines).
const default_claude_md_tokens: Int = 5000

/// Approximate tokens for SessionStart + UserPromptSubmit hooks.
const default_hook_tokens: Int = 700

/// Warning threshold: remaining < 25% of capacity.
const warning_fraction_denom: Int = 4

/// Critical threshold: remaining < 10% of capacity.
const critical_fraction_denom: Int = 10

/// Approximate characters per token (empirical for English/code).
const chars_per_token: Int = 4

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Empirical constants ↪ zero-conversation budget</morphism>
///   <formal-proof>
///     <P> Pre-condition: None. </P>
///     <C> Construct TokenBudget with default baselines, conversation_tokens=0. </C>
///     <Q> Post-condition: remaining = capacity - rules - memory - claude_md - hooks. </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Initialise a `TokenBudget` with default empirical baselines.
///
/// `conversation_tokens` starts at zero; call `add_conversation/2` for each turn.
pub fn init() -> TokenBudget {
  let fixed =
    default_rules_tokens
    + default_memory_tokens
    + default_claude_md_tokens
    + default_hook_tokens
  TokenBudget(
    capacity: default_capacity,
    rules_tokens: default_rules_tokens,
    memory_tokens: default_memory_tokens,
    claude_md_tokens: default_claude_md_tokens,
    hook_tokens: default_hook_tokens,
    conversation_tokens: 0,
    remaining: default_capacity - fixed,
  )
}

/// Estimate the number of tokens in a text string.
///
/// Uses the empirical rule of 4 characters per token, rounding up.
/// This is a conservative approximation; real tokenizers differ by content.
pub fn estimate_text_tokens(text: String) -> Int {
  let chars = string.length(text)
  { chars + chars_per_token - 1 } / chars_per_token
}

/// Record additional conversation tokens (one turn's worth).
///
/// Returns an updated `TokenBudget` with `remaining` reduced accordingly.
pub fn add_conversation(budget: TokenBudget, text_length: Int) -> TokenBudget {
  let extra = { text_length + chars_per_token - 1 } / chars_per_token
  let new_conv = budget.conversation_tokens + extra
  let new_remaining = budget.remaining - extra
  TokenBudget(..budget, conversation_tokens: new_conv, remaining: new_remaining)
}

/// Return `True` when remaining tokens are below 25% of capacity.
///
/// At this threshold, the operator should consider issuing `/compact`.
pub fn is_warning(budget: TokenBudget) -> Bool {
  budget.remaining < budget.capacity / warning_fraction_denom
}

/// Return `True` when remaining tokens are below 10% of capacity.
///
/// At this threshold, the operator MUST issue `/compact` or start a new session.
pub fn is_critical(budget: TokenBudget) -> Bool {
  budget.remaining < budget.capacity / critical_fraction_denom
}

/// Return the percentage of the context window that has been consumed.
///
/// E.g. 0.80 means 80% used, 20% remaining.
pub fn utilization_percent(budget: TokenBudget) -> Float {
  let used = budget.capacity - budget.remaining
  int.to_float(used) /. int.to_float(budget.capacity) *. 100.0
}

/// Return a human-readable one-line summary of the current token budget.
pub fn summary(budget: TokenBudget) -> String {
  let used = budget.capacity - budget.remaining
  let pct = float.round(utilization_percent(budget))
  let status = case is_critical(budget) {
    True -> "CRITICAL"
    False ->
      case is_warning(budget) {
        True -> "WARNING"
        False -> "OK"
      }
  }
  string.join(
    [
      "capacity=" <> int.to_string(budget.capacity),
      "used=" <> int.to_string(used),
      "remaining=" <> int.to_string(budget.remaining),
      "utilization=" <> int.to_string(pct) <> "%",
      "status=" <> status,
    ],
    " ",
  )
}
