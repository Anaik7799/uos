//// =============================================================================
//// Canonical Module: cepaf_gleam/knowledge/annotation_actor.gleam
//// Language: Pure Gleam / BEAM OTP 29
//// Security / Reliability: SIL-6 / Rocha Biosemiotic Semantic Closure
//// Contract: SC-ROCHA-001, SC-KM-001, SC-CHECKLIST-001
//// =============================================================================

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/string

/// Lifecycle status of the Knowledge Annotation Actor
pub type AnnotationStatus {
  Idle
  Running
  Completed
  Degraded(reason: String)
}

/// Inspection result for a single Markdown or Wiki document
pub type DocAnnotationResult {
  DocAnnotationResult(
    path: String,
    has_rocha_semiotics: Bool,
    has_cybernetics: Bool,
    has_km_triad: Bool,
    has_zero_muda: Bool,
    fractal_layer: String,
    wiki_transclusions_count: Int,
    zk_transclusions_count: Int,
    has_tailscale_link: Bool,
    is_semiotically_closed: Bool,
  )
}

/// Comprehensive metrics aggregated across knowledge annotation runs
pub type KnowledgeMetrics {
  KnowledgeMetrics(
    total_runs: Int,
    documents_scanned: Int,
    rocha_tagged_count: Int,
    cybernetics_tagged_count: Int,
    km_triad_tagged_count: Int,
    zero_muda_tagged_count: Int,
    tailscale_linked_count: Int,
    sheaf_coherence_score: Float,
    status: AnnotationStatus,
  )
}

/// Actor internal state
pub type State {
  State(
    total_runs: Int,
    documents_scanned: Int,
    rocha_tagged_count: Int,
    cybernetics_tagged_count: Int,
    km_triad_tagged_count: Int,
    zero_muda_tagged_count: Int,
    tailscale_linked_count: Int,
    status: AnnotationStatus,
  )
}

/// Messages accepted by the Knowledge Annotation Actor
pub type Message {
  TriggerAnnotationRun(reply_to: Subject(KnowledgeMetrics))
  ScanDocument(
    path: String,
    content: String,
    reply_to: Subject(DocAnnotationResult),
  )
  RecordDocResult(result: DocAnnotationResult)
  GetMetrics(reply_to: Subject(KnowledgeMetrics))
  Reset
}

/// Initial state builder
pub fn initial_state() -> State {
  State(
    total_runs: 0,
    documents_scanned: 0,
    rocha_tagged_count: 0,
    cybernetics_tagged_count: 0,
    km_triad_tagged_count: 0,
    zero_muda_tagged_count: 0,
    tailscale_linked_count: 0,
    status: Idle,
  )
}

/// Start the supervised Knowledge Annotation Actor
pub fn start() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(initial_state())
  |> actor.on_message(handle_message)
  |> actor.start()
}

/// Message handler for the actor
pub fn handle_message(
  state: State,
  msg: Message,
) -> actor.Next(State, Message) {
  case msg {
    ScanDocument(path, content, reply_to) -> {
      let result = inspect_document(path, content)
      process.send(reply_to, result)
      let new_state = update_state_with_result(state, result)
      actor.continue(new_state)
    }

    RecordDocResult(result) -> {
      let new_state = update_state_with_result(state, result)
      actor.continue(new_state)
    }

    TriggerAnnotationRun(reply_to) -> {
      let updated_runs = state.total_runs + 1
      let new_state =
        State(..state, total_runs: updated_runs, status: Completed)
      let metrics = state_to_metrics(new_state)
      process.send(reply_to, metrics)
      actor.continue(new_state)
    }

    GetMetrics(reply_to) -> {
      let metrics = state_to_metrics(state)
      process.send(reply_to, metrics)
      actor.continue(state)
    }

    Reset -> {
      actor.continue(initial_state())
    }
  }
}

/// Pure document inspection function implementing Rocha Triad & Sheaf properties
pub fn inspect_document(path: String, content: String) -> DocAnnotationResult {
  let has_rocha = string.contains(content, "#rocha-semiotics")
  let has_cybernetics = string.contains(content, "#cybernetics")
  let has_km = string.contains(content, "#km-triad")
  let has_muda = string.contains(content, "#zero-muda")
  let has_tail = string.contains(content, "nas-1.tail55d152.ts.net:4100")

  let wiki_transclusions = count_occurrences(content, "[[wiki:")
  let zk_transclusions = count_occurrences(content, "[[zk:")

  let fractal = extract_fractal_layer(content)

  // Rocha Triad semantic closure (S, M, E):
  // Sign: Has transclusion or fractal coordinates
  // Mediator: Valid schema/tag structure
  // Effect: Tailscale addressable and zero-muda compliant
  let is_closed =
    { has_rocha || has_cybernetics }
    && has_tail
    && has_muda
    && {
      wiki_transclusions > 0 || zk_transclusions > 0 || fractal != "unknown"
    }

  DocAnnotationResult(
    path: path,
    has_rocha_semiotics: has_rocha,
    has_cybernetics: has_cybernetics,
    has_km_triad: has_km,
    has_zero_muda: has_muda,
    fractal_layer: fractal,
    wiki_transclusions_count: wiki_transclusions,
    zk_transclusions_count: zk_transclusions,
    has_tailscale_link: has_tail,
    is_semiotically_closed: is_closed,
  )
}

/// Update state counter with single document result
fn update_state_with_result(
  state: State,
  result: DocAnnotationResult,
) -> State {
  State(
    ..state,
    documents_scanned: state.documents_scanned + 1,
    rocha_tagged_count: state.rocha_tagged_count
      + case result.has_rocha_semiotics {
        True -> 1
        False -> 0
      },
    cybernetics_tagged_count: state.cybernetics_tagged_count
      + case result.has_cybernetics {
        True -> 1
        False -> 0
      },
    km_triad_tagged_count: state.km_triad_tagged_count
      + case result.has_km_triad {
        True -> 1
        False -> 0
      },
    zero_muda_tagged_count: state.zero_muda_tagged_count
      + case result.has_zero_muda {
        True -> 1
        False -> 0
      },
    tailscale_linked_count: state.tailscale_linked_count
      + case result.has_tailscale_link {
        True -> 1
        False -> 0
      },
  )
}

/// Convert internal state to public metrics
pub fn state_to_metrics(state: State) -> KnowledgeMetrics {
  let coherence = calculate_sheaf_coherence(state)
  KnowledgeMetrics(
    total_runs: state.total_runs,
    documents_scanned: state.documents_scanned,
    rocha_tagged_count: state.rocha_tagged_count,
    cybernetics_tagged_count: state.cybernetics_tagged_count,
    km_triad_tagged_count: state.km_triad_tagged_count,
    zero_muda_tagged_count: state.zero_muda_tagged_count,
    tailscale_linked_count: state.tailscale_linked_count,
    sheaf_coherence_score: coherence,
    status: state.status,
  )
}

/// Calculate Sheaf Coherence Score in range [0.0, 1.0]
pub fn calculate_sheaf_coherence(state: State) -> Float {
  case state.documents_scanned {
    0 -> 1.0
    total -> {
      let rocha_ratio =
        int.to_float(state.rocha_tagged_count) /. int.to_float(total)
      let tail_ratio =
        int.to_float(state.tailscale_linked_count) /. int.to_float(total)
      let muda_ratio =
        int.to_float(state.zero_muda_tagged_count) /. int.to_float(total)

      // Harmonic mean of the 3 primary sheaf sections
      { rocha_ratio +. tail_ratio +. muda_ratio } /. 3.0
    }
  }
}

/// Extract primary fractal layer from document content
fn extract_fractal_layer(content: String) -> String {
  let layers = [
    "#fractal-l0",
    "#fractal-l1",
    "#fractal-l2",
    "#fractal-l3",
    "#fractal-l4",
    "#fractal-l5",
    "#fractal-l6",
    "#fractal-l7",
    "#fractal-l8",
    "#fractal-l9",
  ]
  find_first_layer(layers, content)
}

fn find_first_layer(layers: List(String), content: String) -> String {
  case layers {
    [] -> "unknown"
    [layer, ..rest] ->
      case string.contains(content, layer) {
        True -> layer
        False -> find_first_layer(rest, content)
      }
  }
}

/// Count substring occurrences
fn count_occurrences(source: String, pattern: String) -> Int {
  case string.split(source, pattern) {
    [] -> 0
    parts -> list.length(parts) - 1
  }
}
