//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/invariant_gate</module>
////     <fsharp-lineage>None — novel pre-render safety gate (Satya Plan Sprint 3)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>Pre-render invariant gate — blocks lies from reaching the operator</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001, SC-GLM-UI-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Pre-render gate pattern ↪ Gleam pure function wrapping any render fn.
////       SharedMeshState invariants evaluated before any HTML element is produced.
////       Violations produce safe fallback element — never panics, never exposes bad data.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// INVARIANT GATE — PRE-RENDER TRUTH GUARD
//// स्वधर्मे निधनं श्रेयः — Better to fail truthfully than succeed with lies (Gita 3.35)
////
//// This module is the enforcement layer for the Satya Plan (Sprint 3).
//// It wraps any Lustre page render function and REFUSES to render the page
//// if the underlying SharedMeshState violates structural invariants.
////
//// Guard logic:
////   check_state_invariants(state) → [] means all pass → normal render_fn(state)
////   check_state_invariants(state) → violations → render_safe_fallback(page, violations)
////
//// The four geometric invariants checked here are a lightweight subset of the
//// full 12-invariant suite in self_observer.gleam, focused on structural
//// correctness that MUST hold before ANY render can be trusted:
////
////   I-01: container_count >= healthy_count  (geometry of health)
////   I-02: healthy_count >= 0               (non-negative counts)
////   I-03: container_count >= 0             (non-negative counts)
////   I-04: quorum_healthy ∧ healthy_count == container_count → all-healthy state
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001

import cepaf_gleam/ui/state.{type SharedMeshState}
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A detected structural invariant violation in SharedMeshState.
/// Carries enough information for the fallback page to display actionable detail.
pub type InvariantViolation {
  InvariantViolation(
    /// Stable short ID — e.g. "I-01", "I-04"
    id: String,
    /// Human-readable description of the rule that was broken
    description: String,
    /// What the value should satisfy
    expected: String,
    /// What the state actually contains
    actual: String,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Guard a page render — check invariants BEFORE rendering.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pre-render guard ↪ normal render or safe fallback</morphism>
///   <formal-proof>
///     <P> Pre: SharedMeshState is a well-typed value; render_fn is pure </P>
///     <C> guard_render(state, page_name, render_fn) </C>
///     <Q> Post: Element(msg) is always returned; lies are replaced by fallback </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn guard_render(
  state: SharedMeshState,
  page_name: String,
  render_fn: fn(SharedMeshState) -> Element(msg),
) -> Element(msg) {
  case check_state_invariants(state) {
    // All invariants pass — render normally
    [] -> render_fn(state)
    // At least one violation — show safe fallback instead of potentially wrong data
    violations -> render_safe_fallback(page_name, violations)
  }
}

/// Evaluate the four structural invariants against a SharedMeshState.
/// Returns an empty list when all pass; each violation becomes an InvariantViolation.
pub fn check_state_invariants(
  state: SharedMeshState,
) -> List(InvariantViolation) {
  let acc = check_i01(state, [])
  let acc = check_i02(state, acc)
  let acc = check_i03(state, acc)
  check_i04(state, acc)
}

// ---------------------------------------------------------------------------
// Structural invariants
// ---------------------------------------------------------------------------

/// I-01: container_count >= healthy_count
/// A container cannot be healthy if it does not exist.
fn check_i01(
  state: SharedMeshState,
  acc: List(InvariantViolation),
) -> List(InvariantViolation) {
  case state.container_count >= state.healthy_count {
    True -> acc
    False -> [
      InvariantViolation(
        id: "I-01",
        description: "container_count must be >= healthy_count",
        expected: "container_count >= healthy_count",
        actual: "container_count="
          <> int.to_string(state.container_count)
          <> " < healthy_count="
          <> int.to_string(state.healthy_count),
      ),
      ..acc
    ]
  }
}

/// I-02: healthy_count >= 0
/// Negative healthy containers are physically impossible.
fn check_i02(
  state: SharedMeshState,
  acc: List(InvariantViolation),
) -> List(InvariantViolation) {
  case state.healthy_count >= 0 {
    True -> acc
    False -> [
      InvariantViolation(
        id: "I-02",
        description: "healthy_count must be non-negative",
        expected: "healthy_count >= 0",
        actual: "healthy_count=" <> int.to_string(state.healthy_count),
      ),
      ..acc
    ]
  }
}

/// I-03: container_count >= 0
/// A negative container fleet is physically impossible.
fn check_i03(
  state: SharedMeshState,
  acc: List(InvariantViolation),
) -> List(InvariantViolation) {
  case state.container_count >= 0 {
    True -> acc
    False -> [
      InvariantViolation(
        id: "I-03",
        description: "container_count must be non-negative",
        expected: "container_count >= 0",
        actual: "container_count=" <> int.to_string(state.container_count),
      ),
      ..acc
    ]
  }
}

/// I-04: quorum_healthy ∧ healthy_count == container_count → state is all-healthy
/// When quorum reports healthy AND all containers are healthy, the data must agree.
/// Inconsistency here means source data was corrupted before reaching the gate.
fn check_i04(
  state: SharedMeshState,
  acc: List(InvariantViolation),
) -> List(InvariantViolation) {
  let all_healthy =
    state.quorum_healthy && state.healthy_count == state.container_count
  case all_healthy {
    // Precondition not met — invariant not applicable
    False -> acc
    True -> {
      // When quorum_healthy=true AND all containers healthy, container_count must be > 0
      // (a zero-container fleet with quorum=true is logically incoherent)
      case state.container_count > 0 {
        True -> acc
        False -> [
          InvariantViolation(
            id: "I-04",
            description: "quorum_healthy=true requires at least one container",
            expected: "container_count > 0 when quorum_healthy=true",
            actual: "container_count=0 with quorum_healthy=true",
          ),
          ..acc
        ]
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Safe fallback renderer
// ---------------------------------------------------------------------------

/// Render a safety warning page instead of the requested page.
/// This is the fallback displayed when invariants are violated.
///
/// Operator sees:
///   - Which page was requested
///   - How many invariants failed
///   - Each violation with id / description / expected / actual
///   - A clear statement that correct data was NOT rendered
fn render_safe_fallback(
  page: String,
  violations: List(InvariantViolation),
) -> Element(msg) {
  let count = list.length(violations)
  html.div([attribute.class("invariant-violation-page")], [
    html.div([attribute.class("violation-banner")], [
      html.h1([attribute.class("violation-title")], [
        element.text("Data Inconsistency Detected"),
      ]),
      html.p([attribute.class("violation-subtitle")], [
        element.text(
          "Page: "
          <> page
          <> " — "
          <> int.to_string(count)
          <> " invariant"
          <> case count == 1 {
            True -> ""
            False -> "s"
          }
          <> " violated",
        ),
      ]),
    ]),
    html.div(
      [attribute.class("violation-list")],
      list.map(violations, render_violation_card),
    ),
    html.p([attribute.class("violation-footer")], [
      element.text(
        "The system refused to render potentially incorrect data. "
        <> "Resolve the violations above to restore normal display. "
        <> "स्वधर्मे निधनं श्रेयः",
      ),
    ]),
  ])
}

/// Render a single violation as a card.
fn render_violation_card(v: InvariantViolation) -> Element(msg) {
  html.div([attribute.class("violation-card")], [
    html.span([attribute.class("violation-id")], [element.text(v.id)]),
    html.span([attribute.class("violation-description")], [
      element.text(v.description),
    ]),
    html.div([attribute.class("violation-detail")], [
      html.span([attribute.class("violation-expected")], [
        element.text("Expected: " <> v.expected),
      ]),
      html.span([attribute.class("violation-actual")], [
        element.text("Actual: " <> v.actual),
      ]),
    ]),
  ])
}
