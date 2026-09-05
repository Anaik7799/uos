/// TUI view for KMS Catalog plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/kms.{type KmsModel}
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: KmsModel) -> String {
  let header = visuals.with_color("  KMS CATALOG", "cyan")
  let summary = render_summary(model)
  let checkpoints = render_checkpoints(model)
  string.join([header, summary, "", checkpoints], "\n")
}

fn render_summary(model: KmsModel) -> String {
  let active_color = case model.active_keys {
    0 -> "red"
    _ -> "green"
  }
  "  Total Keys: "
  <> int.to_string(model.total_keys)
  <> "  Active: "
  <> visuals.with_color(int.to_string(model.active_keys), active_color)
  <> "  Checkpoints: "
  <> int.to_string(kms.checkpoint_count(model))
}

fn render_checkpoints(model: KmsModel) -> String {
  "  Checkpoints ("
  <> int.to_string(kms.checkpoint_count(model))
  <> "):"
  <> "\n"
  <> {
    model.checkpoints
    |> list.take(8)
    |> list.map(fn(cp) {
      "    "
      <> visuals.with_color(cp.id, "blue")
      <> " "
      <> cp.label
      <> " keys="
      <> int.to_string(cp.key_count)
      <> " t="
      <> int.to_string(cp.timestamp)
    })
    |> string.join("\n")
  }
}
