//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/endocrine</module>
////     <fsharp-lineage>None — novel slow-regulation actor (Symbiosis Sprint)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Endocrine system — slow hormonal regulation via EMA trends.
////       Seven hormones model CPU load, error rates, growth, drift,
////       memory pressure, cognitive load, and circulatory pressure.
////       Mood is classified from the count of elevated hormones.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-BIO-EVO-001, SC-FUNC-002, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       EMA feedback control ↪ Gleam pure state machine.
////       Each sample() call returns a new EndocrineState — no mutation.
////       regulate() evaluates all seven hormone levels and returns an action.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// ENDOCRINE SYSTEM — SLOW HORMONAL REGULATION
//// अनेकचित्तविभ्रान्ता मोहजालसमावृताः
//// Those bewildered by many thoughts... (Gita 16.16) — tamed by regulation
////
//// EMA update formula: new_ema = alpha * raw + (1 - alpha) * old_ema
//// where alpha ∈ (0, 1]; smaller alpha = slower response = more stable.
////
//// STAMP: SC-BIO-EVO-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// The seven system hormones — each models one metabolic signal.
pub type Hormone {
  /// CPU utilisation trend (alpha=0.10 — medium response)
  CpuTrend
  /// Error-rate exponential moving average (alpha=0.05 — slow, stable)
  ErrorRateEma
  /// Growth signal — test count, endpoint count, holon count (alpha=0.05)
  GrowthHormone
  /// Drift sensitivity — how much the system is deviating from baseline (alpha=0.10)
  DriftSensitivity
  /// Memory pressure — heap usage (alpha=0.15 — faster response)
  MemoryPressure
  /// Cognitive load — OODA cycle time relative to budget (alpha=0.10)
  CognitiveLoad
  /// Circulatory pressure — Zenoh mesh bandwidth (alpha=0.05)
  CirculatoryPressure
}

/// EMA state for a single hormone.
pub type HormoneLevel {
  HormoneLevel(
    /// Which hormone this level tracks
    hormone: Hormone,
    /// Most recently sampled raw value ∈ [0.0, 1.0]
    value: Float,
    /// Current EMA ∈ [0.0, 1.0]
    ema: Float,
    /// Smoothing factor ∈ (0.0, 1.0]
    alpha: Float,
    /// Number of samples received so far
    sample_count: Int,
  )
}

/// System mood — classified from the count of elevated hormones.
pub type SystemMood {
  /// 0 hormones elevated — nominal, dark cockpit
  Calm
  /// 1–2 hormones elevated — mild concern
  Alert
  /// 3+ hormones elevated — high load or error surge
  Stressed
  /// Sustained Stressed (3+ elevated for > 10 regulation cycles) — emergency
  Exhausted
}

/// Full endocrine state.
pub type EndocrineState {
  EndocrineState(
    /// One HormoneLevel per Hormone ADT variant (7 total)
    levels: List(HormoneLevel),
    /// Current mood classification
    mood: SystemMood,
    /// How many times regulate() has been called
    regulation_events: Int,
  )
}

/// Action recommended by the endocrine system after regulation.
pub type EndocrineAction {
  /// All hormones in normal range — no action needed
  NoRegulation
  /// One or more hormones elevated — throttle background operations
  ThrottleOps(reason: String)
  /// High error rate or cognitive overload — boost recovery mechanisms
  BoostRecovery(reason: String)
  /// Multiple critical hormones — alert operator
  AlertOperator(reason: String)
  /// Exhausted mood — enter power/computation conservation mode
  ConservationMode(reason: String)
}

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

fn default_level(hormone: Hormone) -> HormoneLevel {
  let alpha = case hormone {
    CpuTrend -> 0.1
    ErrorRateEma -> 0.05
    GrowthHormone -> 0.05
    DriftSensitivity -> 0.1
    MemoryPressure -> 0.15
    CognitiveLoad -> 0.1
    CirculatoryPressure -> 0.05
  }
  HormoneLevel(
    hormone: hormone,
    value: 0.5,
    ema: 0.5,
    alpha: alpha,
    sample_count: 0,
  )
}

/// Create a fresh endocrine state with all seven hormones at 0.5.
pub fn init() -> EndocrineState {
  let levels = [
    default_level(CpuTrend),
    default_level(ErrorRateEma),
    default_level(GrowthHormone),
    default_level(DriftSensitivity),
    default_level(MemoryPressure),
    default_level(CognitiveLoad),
    default_level(CirculatoryPressure),
  ]
  EndocrineState(levels: levels, mood: Calm, regulation_events: 0)
}

// ---------------------------------------------------------------------------
// Core EMA update
// ---------------------------------------------------------------------------

/// Record one raw measurement for a hormone and recompute its EMA.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Raw sensor reading ↪ updated EndocrineState</morphism>
///   <formal-proof>
///     <P> Pre: raw_value ∈ [0.0, 1.0]; hormone is a valid Hormone variant </P>
///     <C> sample(state, hormone, raw_value) </C>
///     <Q> Post: matching HormoneLevel.ema = alpha*raw + (1-alpha)*old_ema;
///         mood reclassified; all other levels unchanged </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn sample(
  state: EndocrineState,
  hormone: Hormone,
  raw_value: Float,
) -> EndocrineState {
  let updated_levels =
    list.map(state.levels, fn(lvl) {
      case lvl.hormone == hormone {
        False -> lvl
        True -> {
          let new_ema =
            lvl.alpha *. raw_value +. { 1.0 -. lvl.alpha } *. lvl.ema
          HormoneLevel(
            ..lvl,
            value: raw_value,
            ema: new_ema,
            sample_count: lvl.sample_count + 1,
          )
        }
      }
    })
  let new_mood =
    classify_mood_from_levels(updated_levels, state.regulation_events)
  EndocrineState(..state, levels: updated_levels, mood: new_mood)
}

// ---------------------------------------------------------------------------
// Regulation
// ---------------------------------------------------------------------------

/// Evaluate all hormone levels and return the recommended action.
pub fn regulate(state: EndocrineState) -> #(EndocrineState, EndocrineAction) {
  let new_events = state.regulation_events + 1
  let new_mood = classify_mood_from_levels(state.levels, new_events)
  let new_state =
    EndocrineState(..state, mood: new_mood, regulation_events: new_events)

  let action = case new_mood {
    Exhausted ->
      ConservationMode(
        "Sustained stress: "
        <> int.to_string(elevated_count(state))
        <> " hormones elevated for extended period",
      )
    Stressed -> {
      let critical_count =
        state.levels
        |> list.filter(is_critical)
        |> list.length()
      case critical_count > 0 {
        True ->
          AlertOperator(
            "Critical hormones: "
            <> int.to_string(critical_count)
            <> " above 0.9 threshold",
          )
        False ->
          ThrottleOps(
            "Stressed: "
            <> int.to_string(elevated_count(state))
            <> " hormones elevated",
          )
      }
    }
    Alert -> {
      let has_error_or_cognitive =
        state.levels
        |> list.filter(fn(lvl) {
          { lvl.hormone == ErrorRateEma || lvl.hormone == CognitiveLoad }
          && is_elevated(lvl)
        })
        |> list.length()
        > 0
      case has_error_or_cognitive {
        True -> BoostRecovery("Error rate or cognitive load elevated")
        False -> ThrottleOps("Alert: mild hormone elevation")
      }
    }
    Calm -> NoRegulation
  }

  #(new_state, action)
}

// ---------------------------------------------------------------------------
// Classification helpers
// ---------------------------------------------------------------------------

fn classify_mood_from_levels(
  levels: List(HormoneLevel),
  regulation_events: Int,
) -> SystemMood {
  let elevated =
    levels
    |> list.filter(is_elevated)
    |> list.length()
  case elevated {
    0 -> Calm
    1 | 2 -> Alert
    _ ->
      case regulation_events > 10 {
        True -> Exhausted
        False -> Stressed
      }
  }
}

/// Classify system mood from current hormone levels.
pub fn classify_mood(state: EndocrineState) -> SystemMood {
  classify_mood_from_levels(state.levels, state.regulation_events)
}

/// True when a hormone's EMA exceeds the elevated threshold (0.7).
pub fn is_elevated(level: HormoneLevel) -> Bool {
  level.ema >. 0.7
}

/// True when a hormone's EMA exceeds the critical threshold (0.9).
pub fn is_critical(level: HormoneLevel) -> Bool {
  level.ema >. 0.9
}

/// Number of hormones currently in the elevated range.
pub fn elevated_count(state: EndocrineState) -> Int {
  state.levels
  |> list.filter(is_elevated)
  |> list.length()
}

// ---------------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------------

/// Stable string identifier for a hormone (used in logs and alarms).
pub fn hormone_to_string(hormone: Hormone) -> String {
  case hormone {
    CpuTrend -> "cpu_trend"
    ErrorRateEma -> "error_rate_ema"
    GrowthHormone -> "growth_hormone"
    DriftSensitivity -> "drift_sensitivity"
    MemoryPressure -> "memory_pressure"
    CognitiveLoad -> "cognitive_load"
    CirculatoryPressure -> "circulatory_pressure"
  }
}

/// Stable string identifier for a system mood.
pub fn mood_to_string(mood: SystemMood) -> String {
  case mood {
    Calm -> "calm"
    Alert -> "alert"
    Stressed -> "stressed"
    Exhausted -> "exhausted"
  }
}

/// Health score in [0.0, 1.0] derived from current mood.
pub fn health(state: EndocrineState) -> Float {
  case state.mood {
    Calm -> 1.0
    Alert -> 0.7
    Stressed -> 0.4
    Exhausted -> 0.1
  }
}

/// Human-readable summary of endocrine state.
pub fn summary(state: EndocrineState) -> String {
  let elev = elevated_count(state)
  let health_pct = float.round(health(state) *. 100.0)
  string.join(
    [
      "Endocrine[mood=",
      mood_to_string(state.mood),
      " elevated=",
      int.to_string(elev),
      "/7",
      " health=",
      int.to_string(health_pct),
      "%",
      " events=",
      int.to_string(state.regulation_events),
      "]",
    ],
    "",
  )
}
