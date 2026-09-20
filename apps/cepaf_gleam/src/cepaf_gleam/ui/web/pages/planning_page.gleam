import cepaf_gleam/planning/execution_observer
import cepaf_gleam/ui/state.{type SharedMeshState}
import cepaf_gleam/ui/web/pages/execution_progress
import lustre/element.{type Element}

pub fn view(_state: SharedMeshState) -> Element(msg) {
  execution_observer.observe() |> execution_progress.render
}
