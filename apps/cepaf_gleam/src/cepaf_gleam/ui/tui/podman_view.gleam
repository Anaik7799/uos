/// TUI view for Podman plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/podman.{type Container, type PodmanModel}
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: PodmanModel) -> String {
  let header = visuals.with_color("  PODMAN", "cyan")
  let summary = render_summary(model)
  let containers = render_containers(model.containers)
  let images = render_images(model)
  let volumes_nets = render_volumes_networks(model)
  string.join(
    [header, summary, "", containers, "", images, "", volumes_nets],
    "\n",
  )
}

fn render_summary(model: PodmanModel) -> String {
  let running = podman.running_count(model)
  let total = podman.container_count(model)
  "  Containers: "
  <> visuals.with_color(int.to_string(running), "green")
  <> "/"
  <> int.to_string(total)
  <> " running"
  <> "  Images: "
  <> int.to_string(list.length(model.images))
  <> "  Volumes: "
  <> int.to_string(list.length(model.volumes))
  <> "  Networks: "
  <> int.to_string(list.length(model.networks))
}

fn render_containers(containers: List(Container)) -> String {
  "  Containers:"
  <> "\n"
  <> {
    containers
    |> list.take(15)
    |> list.map(fn(c) {
      let color = case c.status {
        "running" -> "green"
        "exited" -> "red"
        "created" -> "yellow"
        _ -> "blue"
      }
      "    "
      <> visuals.with_color("[" <> c.status <> "]", color)
      <> " "
      <> c.name
      <> " ("
      <> c.image
      <> ")"
    })
    |> string.join("\n")
  }
}

fn render_images(model: PodmanModel) -> String {
  "  Images ("
  <> int.to_string(list.length(model.images))
  <> "):"
  <> "\n"
  <> {
    model.images
    |> list.take(5)
    |> list.map(fn(img) {
      "    "
      <> img.repository
      <> ":"
      <> img.tag
      <> " ("
      <> int.to_string(img.size_mb)
      <> "MB)"
    })
    |> string.join("\n")
  }
}

/// Render container controls (start/stop/restart/logs) for the selected container.
pub fn render_container_controls(
  selected_name: String,
  selected_status: String,
) -> String {
  let actions = case selected_status {
    "running" ->
      visuals.with_color("[x]Stop", "red")
      <> "  "
      <> visuals.with_color("[r]Restart", "yellow")
      <> "  "
      <> visuals.with_color("[l]Logs", "cyan")
    "exited" ->
      visuals.with_color("[s]Start", "green")
      <> "  "
      <> visuals.with_color("[l]Logs", "cyan")
    _ ->
      visuals.with_color("[s]Start", "green")
      <> "  "
      <> visuals.with_color("[l]Logs", "cyan")
  }

  "  Selected: " <> visuals.with_color(selected_name, "cyan") <> "  " <> actions
}

/// Render container log lines.
pub fn render_container_logs(log_lines: List(String), max_lines: Int) -> String {
  let header = visuals.with_color("  CONTAINER LOGS", "cyan")
  let lines =
    log_lines
    |> list.take(max_lines)
    |> list.map(fn(line) { "    " <> line })
    |> string.join("\n")
  header <> "\n" <> lines
}

fn render_volumes_networks(model: PodmanModel) -> String {
  let vols =
    model.volumes
    |> list.take(3)
    |> list.map(fn(v) { "    " <> v.name <> " (" <> v.driver <> ")" })
    |> string.join("\n")
  let nets =
    model.networks
    |> list.take(3)
    |> list.map(fn(n) {
      "    " <> n.name <> " " <> n.subnet <> " (" <> n.driver <> ")"
    })
    |> string.join("\n")
  "  Volumes:\n" <> vols <> "\n  Networks:\n" <> nets
}
