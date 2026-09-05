//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/immune_learning</module>
////     <fsharp-lineage>None — novel adaptive immune actor (Symbiosis Sprint)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Adaptive immune learning — synthesises GRL rules from observed
////       attack patterns.  Antibodies begin as pending (unverified) and
////       must receive Guardian approval before entering the active rule set.
////       Confidence increases with repeated observations.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-BIO-EVO-001, SC-SIL4-001, SC-FUNC-002, SC-SAFETY-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Clonal selection + affinity maturation ↪ Gleam pure state machine.
////       Guardian approval modelled as explicit approve_antibody() call.
////       No side effects — all state passed by value.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// ADAPTIVE IMMUNE LEARNING — SYNTHESISE RULES FROM ATTACK PATTERNS
//// अहं सर्वस्य प्रभवो मत्तः सर्वं प्रवर्तते
//// From Me all proceeds — new rules emerge from each new threat (Gita 10.8)
////
//// Workflow:
////   1. observe_attack() — record a new attack or increment existing one
////   2. If new: action = RequestApproval(antibody)
////   3. Guardian calls approve_antibody() or reject_antibody()
////   4. Approved antibodies become active GRL rules via active_rules()
////
//// STAMP: SC-BIO-EVO-001, SC-SAFETY-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A synthesised immune antibody derived from observing an attack.
pub type LearnedAntibody {
  LearnedAntibody(
    /// Stable unique identifier, e.g. "ab-001"
    id: String,
    /// Name of the attack that triggered synthesis
    source_attack: String,
    /// Regex-like pattern string that characterises the attack
    pattern: String,
    /// Generated GRL rule text (salience proportional to confidence)
    rete_rule: String,
    /// Confidence score ∈ [0.0, 1.0] — grows with observation_count
    confidence: Float,
    /// How many times this attack pattern has been observed
    observation_count: Int,
    /// Sequence counter when first observed (0 = not yet observed)
    first_seen: Int,
    /// Sequence counter of most recent observation
    last_seen: Int,
    /// True when a Guardian has explicitly approved this antibody
    approved: Bool,
  )
}

/// Full immune memory state.
pub type ImmuneMemory {
  ImmuneMemory(
    /// Approved antibodies active in the rule engine
    learned: List(LearnedAntibody),
    /// Synthesised antibodies awaiting Guardian approval
    pending_approval: List(LearnedAntibody),
    /// Raw patterns that are unconditionally blocked (no rule synthesis)
    blocked_patterns: List(String),
    /// Total number of learning events processed
    learning_events: Int,
  )
}

/// Outcome of one observe_attack() call.
pub type LearningAction {
  /// New attack observed — synthesised antibody needs Guardian approval
  SynthesizeRule(antibody: LearnedAntibody)
  /// Attack pattern matches a known dangerous string — block immediately
  BlockPattern(pattern: String)
  /// Existing antibody confidence updated — request re-approval if threshold crossed
  RequestApproval(antibody: LearnedAntibody)
  /// Attack already covered by an approved antibody — no new action
  NoLearning
}

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

/// Create an empty immune memory.
pub fn init() -> ImmuneMemory {
  ImmuneMemory(
    learned: [],
    pending_approval: [],
    blocked_patterns: [],
    learning_events: 0,
  )
}

// ---------------------------------------------------------------------------
// Core learning
// ---------------------------------------------------------------------------

/// Observe an attack and update immune memory.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Attack event ↪ updated ImmuneMemory + LearningAction</morphism>
///   <formal-proof>
///     <P> Pre: attack_name and pattern are non-empty strings </P>
///     <C> observe_attack(memory, attack_name, pattern, timestamp) </C>
///     <Q> Post: if pattern blocked → BlockPattern;
///         if existing pending → increment confidence + RequestApproval when > 0.8;
///         if existing learned → increment, NoLearning;
///         if new → SynthesizeRule with pending antibody created </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn observe_attack(
  memory: ImmuneMemory,
  attack_name: String,
  pattern: String,
  timestamp: Int,
) -> #(ImmuneMemory, LearningAction) {
  // 1. Immediately blocked patterns
  case is_blocked(memory, pattern) {
    True -> {
      let new_memory =
        ImmuneMemory(..memory, learning_events: memory.learning_events + 1)
      #(new_memory, BlockPattern(pattern))
    }
    False -> {
      // 2. Already approved — bump count, no action
      let in_learned =
        list.find(memory.learned, fn(ab) { ab.source_attack == attack_name })
      case in_learned {
        Ok(existing) -> {
          let updated =
            LearnedAntibody(
              ..existing,
              observation_count: existing.observation_count + 1,
              confidence: confidence_from_count(existing.observation_count + 1),
              last_seen: timestamp,
            )
          let new_learned =
            list.map(memory.learned, fn(ab) {
              case ab.id == existing.id {
                True -> updated
                False -> ab
              }
            })
          let new_memory =
            ImmuneMemory(
              ..memory,
              learned: new_learned,
              learning_events: memory.learning_events + 1,
            )
          #(new_memory, NoLearning)
        }
        Error(_) -> {
          // 3. In pending — bump count, maybe request re-approval
          let in_pending =
            list.find(memory.pending_approval, fn(ab) {
              ab.source_attack == attack_name
            })
          case in_pending {
            Ok(existing) -> {
              let new_count = existing.observation_count + 1
              let new_conf = confidence_from_count(new_count)
              let updated =
                LearnedAntibody(
                  ..existing,
                  observation_count: new_count,
                  confidence: new_conf,
                  last_seen: timestamp,
                  rete_rule: generate_grl_rule(
                    LearnedAntibody(..existing, confidence: new_conf),
                  ),
                )
              let new_pending =
                list.map(memory.pending_approval, fn(ab) {
                  case ab.id == existing.id {
                    True -> updated
                    False -> ab
                  }
                })
              let new_memory =
                ImmuneMemory(
                  ..memory,
                  pending_approval: new_pending,
                  learning_events: memory.learning_events + 1,
                )
              let action = case new_conf >. 0.8 {
                True -> RequestApproval(updated)
                False -> NoLearning
              }
              #(new_memory, action)
            }
            Error(_) -> {
              // 4. Completely new attack — synthesise antibody
              let id =
                "ab-"
                <> int.to_string(
                  list.length(memory.learned)
                  + list.length(memory.pending_approval)
                  + 1,
                )
              let conf = confidence_from_count(1)
              let antibody =
                LearnedAntibody(
                  id: id,
                  source_attack: attack_name,
                  pattern: pattern,
                  rete_rule: "",
                  confidence: conf,
                  observation_count: 1,
                  first_seen: timestamp,
                  last_seen: timestamp,
                  approved: False,
                )
              let with_rule =
                LearnedAntibody(
                  ..antibody,
                  rete_rule: generate_grl_rule(antibody),
                )
              let new_memory =
                ImmuneMemory(
                  ..memory,
                  pending_approval: [with_rule, ..memory.pending_approval],
                  learning_events: memory.learning_events + 1,
                )
              #(new_memory, SynthesizeRule(with_rule))
            }
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Guardian approval
// ---------------------------------------------------------------------------

/// Move an antibody from pending to learned (Guardian approved).
pub fn approve_antibody(memory: ImmuneMemory, id: String) -> ImmuneMemory {
  let maybe_ab = list.find(memory.pending_approval, fn(ab) { ab.id == id })
  case maybe_ab {
    Error(_) -> memory
    Ok(ab) -> {
      let approved_ab = LearnedAntibody(..ab, approved: True)
      let new_pending =
        list.filter(memory.pending_approval, fn(a) { a.id != id })
      ImmuneMemory(
        ..memory,
        learned: [approved_ab, ..memory.learned],
        pending_approval: new_pending,
      )
    }
  }
}

/// Remove an antibody from pending (Guardian rejected).
pub fn reject_antibody(memory: ImmuneMemory, id: String) -> ImmuneMemory {
  let new_pending = list.filter(memory.pending_approval, fn(ab) { ab.id != id })
  ImmuneMemory(..memory, pending_approval: new_pending)
}

// ---------------------------------------------------------------------------
// GRL rule generation
// ---------------------------------------------------------------------------

/// Generate a GRL rule text string for an antibody.
///
/// Salience is proportional to confidence * 100.
pub fn generate_grl_rule(antibody: LearnedAntibody) -> String {
  let salience_int = float.round(antibody.confidence *. 100.0)
  string.join(
    [
      "rule \"",
      antibody.id,
      "\" salience ",
      int.to_string(salience_int),
      " when pattern(\"",
      antibody.pattern,
      "\") then block_attack(\"",
      antibody.source_attack,
      "\")",
    ],
    "",
  )
}

// ---------------------------------------------------------------------------
// Query helpers
// ---------------------------------------------------------------------------

/// GRL rule strings for all approved antibodies.
pub fn active_rules(memory: ImmuneMemory) -> List(String) {
  memory.learned
  |> list.filter(fn(ab) { ab.approved })
  |> list.map(fn(ab) { ab.rete_rule })
}

/// True when `pattern` is in the unconditional block list.
pub fn is_blocked(memory: ImmuneMemory, pattern: String) -> Bool {
  list.contains(memory.blocked_patterns, pattern)
}

/// Add `pattern` to the unconditional block list.
pub fn block_pattern(memory: ImmuneMemory, pattern: String) -> ImmuneMemory {
  case is_blocked(memory, pattern) {
    True -> memory
    False ->
      ImmuneMemory(..memory, blocked_patterns: [
        pattern,
        ..memory.blocked_patterns
      ])
  }
}

/// Number of antibodies awaiting Guardian approval.
pub fn pending_count(memory: ImmuneMemory) -> Int {
  list.length(memory.pending_approval)
}

/// Number of approved antibodies in active memory.
pub fn learned_count(memory: ImmuneMemory) -> Int {
  list.length(memory.learned)
}

/// Human-readable summary of immune memory.
pub fn summary(memory: ImmuneMemory) -> String {
  string.join(
    [
      "ImmuneMemory[learned=",
      int.to_string(learned_count(memory)),
      " pending=",
      int.to_string(pending_count(memory)),
      " blocked=",
      int.to_string(list.length(memory.blocked_patterns)),
      " events=",
      int.to_string(memory.learning_events),
      "]",
    ],
    "",
  )
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Confidence grows logarithmically with observation count.
/// Returns a value in [0.1, 0.99] clamped.
fn confidence_from_count(n: Int) -> Float {
  let base = case n {
    1 -> 0.1
    2 -> 0.2
    3 -> 0.35
    4 -> 0.5
    5 -> 0.6
    6 -> 0.7
    7 -> 0.8
    8 -> 0.85
    9 -> 0.9
    _ -> 0.95
  }
  base
}
