/// TUI view for Prajna Operator plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/domain.{
  Critical, Degraded, Healthy, Unknown, layer_to_string,
}
import cepaf_gleam/ui/lustre/prajna.{type PrajnaModel}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: PrajnaModel) -> String {
  let header = visuals.with_color("  PRAJNA OPERATOR", "cyan")
  let holons = render_holons(model)
  let threat = render_threat(model)
  let cockpit = render_cockpit(model)
  let circuit = render_circuit(model)
  let routed = render_routed(model)
  let integrity = render_integrity(model)
  let vectors = render_vectors(model)
  let matrix = render_matrix(model)
  let homeostasis = render_homeostasis(model)
  let release = render_release(model)
  let singularity = render_singularity(model)

  string.join(
    [
      header,
      holons,
      threat,
      cockpit,
      circuit,
      routed,
      integrity,
      vectors,
      matrix,
      homeostasis,
      release,
      singularity,
    ],
    "\n",
  )
}

fn render_holons(model: PrajnaModel) -> String {
  "  Holons: " <> visuals.with_color(int.to_string(model.holon_count), "blue")
}

fn render_threat(model: PrajnaModel) -> String {
  let color = case model.threat_level {
    "nominal" -> "green"
    "elevated" -> "yellow"
    "critical" -> "red"
    _ -> "red"
  }
  "  Threat: " <> visuals.with_color(model.threat_level, color)
}

fn render_cockpit(model: PrajnaModel) -> String {
  let color = case model.cockpit_mode {
    "dark" -> "green"
    "alert" -> "yellow"
    _ -> "magenta"
  }
  "  Cockpit: " <> visuals.with_color(model.cockpit_mode, color)
}

fn render_circuit(model: PrajnaModel) -> String {
  let color = case model.circuit_state {
    "closed" -> "green"
    "half-open" -> "yellow"
    "open" -> "red"
    _ -> "yellow"
  }
  "  Circuit: " <> visuals.with_color(model.circuit_state, color)
}

fn render_routed(model: PrajnaModel) -> String {
  "  Messages Routed: " <> int.to_string(model.messages_routed)
}

fn render_integrity(model: PrajnaModel) -> String {
  let integrity = model.integrity
  let hs = "Hs: " <> float.to_string(integrity.hs)
  let eps = "eps: " <> float.to_string(integrity.epsilon)
  let ds = "Ds: " <> float.to_string(integrity.ds)
  "  Integrity: "
  <> visuals.with_color(string.join([hs, eps, ds], " | "), "cyan")
}

fn render_vectors(model: PrajnaModel) -> String {
  let vectors = model.vectors
  let v1 = "V1: " <> float.to_string(vectors.v1)
  let v2 = "V2: " <> float.to_string(vectors.v2)
  let v3 = "V3: " <> float.to_string(vectors.v3)
  let v4 = "V4: " <> float.to_string(vectors.v4)
  "  Vectors: "
  <> visuals.with_color(string.join([v1, v2, v3, v4], " | "), "magenta")
}

fn render_matrix(model: PrajnaModel) -> String {
  let levels =
    list.map(model.matrix.levels, fn(level_status) {
      let #(layer, status) = level_status
      let layer_name = layer_to_string(layer)
      let status_color = case status {
        Healthy -> "green"
        Degraded(_) -> "yellow"
        Critical(_) -> "red"
        Unknown -> "white"
      }
      visuals.with_color(layer_name, status_color)
    })
  "  Biomorphic Matrix: " <> string.join(levels, " ")
}

fn render_homeostasis(model: PrajnaModel) -> String {
  let h = model.homeostasis
  let pid =
    "PID: ("
    <> float.to_string(h.kp)
    <> ", "
    <> float.to_string(h.ki)
    <> ", "
    <> float.to_string(h.kd)
    <> ")"
  let sp = "SP: " <> float.to_string(h.set_point)
  let cur = "PV: " <> float.to_string(h.current_value)
  let err = "Err: " <> float.to_string(h.error)
  "  Homeostasis: "
  <> visuals.with_color(string.join([pid, sp, cur, err], " | "), "yellow")
}

fn render_release(model: PrajnaModel) -> String {
  let r = model.release
  let k1 = case r.key1_signed {
    True -> visuals.with_color("KEY1", "green")
    False -> visuals.with_color("KEY1", "red")
  }
  let k2 = case r.key2_signed {
    True -> visuals.with_color("KEY2", "green")
    False -> visuals.with_color("KEY2", "red")
  }
  let auth = case r.authorized_by {
    Some(user) -> " | Auth: " <> user
    None -> ""
  }
  "  Bicameral Release: [" <> k1 <> "][" <> k2 <> "]" <> auth
}

fn render_singularity(model: PrajnaModel) -> String {
  let s = model.singularity
  let time = "T-Sing: " <> int.to_string(s.time_to_singularity_ms) <> "ms"
  let conf = "Conf: " <> float.to_string(s.confidence_interval)
  let color = case s.critical_threshold_reached {
    True -> "red"
    False -> "green"
  }
  "  Singularity: " <> visuals.with_color(time <> " | " <> conf, color)
}
