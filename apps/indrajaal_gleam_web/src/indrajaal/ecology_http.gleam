//// =============================================================================
//// [C3I-BOUNDED-ECOLOGY] UOS ECOLOGY OBSERVATION HTTP ADAPTER
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>indrajaal/ecology_http</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT through L6_ECOSYSTEM</layer>
////     <mesh-domain>Ecology HTTP Endpoints, Dynamic SVG Spectrogram & Swarm Telemetry</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>READ-OBSERVE; NOT SYSTEM ADMISSION</criticality>
////     <stamp-controls>
////       SC-HOLON-001, SC-BIO-HARMONY-001, SC-CHECKLIST-001, SC-TAILSCALE-WEB-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/ecology/andon
import cepaf_gleam/ecology/harmonic_song.{
  render_song_ascii_sparkline, render_song_svg, song_to_json,
}
import cepaf_gleam/ecology/living_swarm.{type SwarmEcology, swarm_to_json}
import cepaf_gleam/ecology/living_swarm_actor.{type LivingSwarmActorMsg}
import cepaf_gleam/ecology/super_agent
import cepaf_gleam/ui/ecology_refresh
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/http.{Get}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import mist.{type Connection, type ResponseData}

fn json_response(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("access-control-allow-origin", "*")
}

fn svg_response(svg_content: String) -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(svg_content)))
  |> response.set_header("content-type", "image/svg+xml; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("access-control-allow-origin", "*")
}

fn text_response(text: String) -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(text)))
  |> response.set_header("content-type", "text/plain; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("access-control-allow-origin", "*")
}

fn html_response(html: String) -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html)))
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("access-control-allow-origin", "*")
}

fn escape_html_text(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

/// Render full HTML page for the living swarm ecology cockpit with 18-checkpoint verification.
pub fn render_ecology_html(swarm: SwarmEcology) -> String {
  let song = swarm.current_song
  let svg = render_song_svg(song)

  let holon_rows =
    list.map(swarm.holons, fn(h) {
      "<tr>"
      <> "<td style=\"padding:6px 12px;border-bottom:1px solid #1f293d;\"><code>"
      <> h.id
      <> "</code></td>"
      <> "<td style=\"padding:6px 12px;border-bottom:1px solid #1f293d;\">"
      <> h.name
      <> "</td>"
      <> "<td style=\"padding:6px 12px;border-bottom:1px solid #1f293d;\"><span style=\"background:#16243b;color:#00d4ff;padding:2px 8px;border-radius:4px;\">"
      <> h.plane
      <> "</span></td>"
      <> "<td style=\"padding:6px 12px;border-bottom:1px solid #1f293d;\">"
      <> super_agent.lifecycle_to_string(h.lifecycle)
      <> " · "
      <> super_agent.mode_to_string(h.mode)
      <> " · "
      <> int.to_string(h.successful_invocations)
      <> " observed invocations</td>"
      <> "</tr>"
    })
    |> list.fold("", fn(acc, row) { acc <> row })

  "<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
  <title>Living Swarm Ecology & Cybernetic Singing Cockpit | UOS</title>
  <style>
    body { background:#070b14; color:#e2e8f0; font-family:system-ui,-apple-system,sans-serif; margin:0; padding:24px; }
    .container { max-width:1100px; margin:0 auto; }
    h1 { color:#00ffc4; font-family:monospace; margin-bottom:8px; }
    .card { background:#0d1527; border:1px solid #1f293d; border-radius:8px; padding:20px; margin-bottom:24px; }
    .checklist { background:#090e1c; border:1px solid #1f293d; border-radius:6px; padding:16px; margin-bottom:20px; }
    table { width:100%; border-collapse:collapse; text-align:left; font-size:14px; }
    th { padding:8px 12px; border-bottom:2px solid #2d3f5e; color:#94a3b8; font-size:12px; text-transform:uppercase; }
    code { font-family:monospace; color:#38bdf8; }
    a { color:#38bdf8; text-decoration:none; }
    a:hover { text-decoration:underline; }
    .badge { display:inline-block; padding:4px 10px; border-radius:4px; font-weight:bold; font-size:12px; }
    .badge-harmonic { background:#064e3b; color:#34d399; }
  </style>
</head>
<body>
  <div class=\"container\">
    <div style=\"display:flex;justify-content:space-between;align-items:center;\">
      <h1>UOS LIVING SWARM ECOLOGY</h1>
      <div>
        <span class=\"badge badge-harmonic\">HARMONIC CONSONANCE: <span id=\"ecology-consonance\">" <> float.to_string(
    song.harmonic_consonance *. 100.0,
  ) <> "</span>%</span>
        <a href=\"http://nas-1.tail55d152.ts.net:4100/\" style=\"margin-left:16px;\">Back to Cockpit &rarr;</a>
      </div>
    </div>
    <p style=\"color:#94a3b8;margin-top:0;\">
      <span id=\"ecology-participants\">" <> int.to_string(list.length(
    swarm.holons,
  )) <> "</span> participants · 11 discoverable capabilities · Observed cycle <span id=\"ecology-cycle\">" <> int.to_string(
    swarm.cycle_counter,
  ) <> "</span> · Invocation receipts <span id=\"ecology-invocations\">" <> int.to_string(
    swarm.invocation_sequence,
  ) <> "</span>
      <br>Participant models share one ecology actor; external system bindings are absent.
      <br>Local cognition and diagnostics; backend availability and system admission require separate evidence.
    </p>
    <p id=\"ecology-refresh-status\" role=\"status\" aria-live=\"polite\">Initial snapshot; awaiting live refresh.</p>
    <div class=\"card\"><h3>Shared service Andon</h3>
      <pre id=\"ecology-service-andon\" aria-live=\"polite\" style=\"white-space:pre-wrap\">" <> escape_html_text(
    andon.summary(swarm.service_andon),
  ) <> "</pre>
    </div>

    <!-- Comprehensive Verification Checklist Accordion (SC-CHECKLIST-001) -->
    <details class=\"checklist\" open>
      <summary style=\"cursor:pointer;font-weight:bold;color:#38bdf8;\">
        Comprehensive Verification Checklist: evidence required (SC-CHECKLIST-001)
      </summary>
      <div style=\"margin-top:12px;font-size:13px;display:grid;grid-template-columns:1fr 1fr;gap:8px;\">
        <details><summary>1. Metadata and navigation</summary>
          <p><code>CHK-01-TIME</code>: host observation " <> int.to_string(
    swarm.epoch_us,
  ) <> " µs; synchronization gate separate</p>
          <p><code>CHK-02-TAIL</code>: Tailnet navigation provided</p>
          <p><code>CHK-03-FRACT</code>: local actor scope L4–L6</p>
          <p><code>CHK-04-KM</code>: grouped artifacts require revision review</p>
        </details>
        <details><summary>2. Purity and storage safety</summary>
          <p><code>CHK-05-MUDA</code>: fleet gate UNRUN in this view</p>
          <p><code>CHK-06-GRAPH</code>: renderer observation only</p>
          <p><code>CHK-07-DRIVE</code>: hardware interlock UNRUN in this view</p>
        </details>
        <details><summary>3. Tests and mathematics</summary>
          <p><code>CHK-08-C1C8</code>: full UI suite UNRUN in this view</p>
          <p><code>CHK-09-MATH</code>: song metrics grant no proof admission</p>
          <p><code>CHK-10-9MOD</code>: candidate test receipts required</p>
          <p><code>CHK-11-REGR</code>: regression monitoring UNRUN in this view</p>
        </details>
        <details><summary>4. Runtime and observability</summary>
          <p><code>CHK-12-GLEAM</code>: persistent actor state observed</p>
          <p><code>CHK-13-HERMES</code>: invocation receipts retain backend outcomes</p>
          <p><code>CHK-14-ZIGVM</code>: kernel execution UNRUN in this view</p>
          <p><code>CHK-15-MAX</code>: inference requires an engaged receipt</p>
          <p><code>CHK-16-OTEL</code>: full trace correlation UNRUN in this view</p>
        </details>
        <details><summary>5. Governance and VCS</summary>
          <p><code>CHK-17-SOV</code>: system admission NOT_ADMITTED</p>
          <p><code>CHK-18-JJ</code>: integration authority separate</p>
        </details>
        <details><summary>6. Provenance</summary>
          <p><code>CHK-PROV</code>: EV-93 ceiling; this runtime mints no EV number</p>
        </details>
      </div>
    </details>

    <div class=\"card\">
      <h3 style=\"color:#38bdf8;margin-top:0;\">Initial Cybernetic Singing Snapshot (Pure SVG)</h3>
      <div style=\"text-align:center;overflow-x:auto;\">
        " <> svg <> "
      </div>
      <div style=\"display:flex;justify-content:space-between;margin-top:12px;font-size:13px;color:#94a3b8;\">
        <div><strong>Raga:</strong> " <> song.raga_name <> "</div>
        <div><strong>Teentaal Beat:</strong> " <> int.to_string(
    song.beat_number,
  ) <> "/16 (" <> song.current_bol.bol_name <> ")</div>
        <div><strong>Drone Frequencies:</strong> 261.63Hz, 392.44Hz, 523.25Hz</div>
      </div>
    </div>

    <div class=\"card\">
      <h3 style=\"color:#38bdf8;margin-top:0;\">Participating Holons across 7 Systemic Planes</h3>
      <table>
        <thead>
          <tr>
            <th>Holon Identifier</th>
            <th>Name & Subsystem</th>
            <th>Systemic Plane</th>
            <th>Biological Lifecycle</th>
          </tr>
        </thead>
        <tbody id=\"ecology-participant-rows\" data-layout=\"full\">
          " <> holon_rows <> "
        </tbody>
      </table>
    </div>

    <details class=\"card\"><summary>Latest observed receipts</summary>
      <pre id=\"ecology-receipts-json\" style=\"overflow:auto;max-height:32rem\"></pre>
    </details>

    <footer style=\"margin-top:32px;font-size:12px;color:#64748b;text-align:center;\">
      Unified Operational System &bull; <a href=\"http://nas-1.tail55d152.ts.net:4100\">nas-1.tail55d152.ts.net:4100</a> &bull; BEAM OTP 29
    </footer>
  </div>
  <script>" <> ecology_refresh.script() <> "</script>
</body>
</html>"
}

/// Main HTTP request handler for the ecology endpoints.
pub fn handle(
  req: Request(Connection),
  runtime: Subject(LivingSwarmActorMsg),
) -> Response(ResponseData) {
  handle_snapshot(req, living_swarm_actor.get_swarm(runtime, 250))
}

pub fn handle_snapshot(
  req: Request(body),
  snapshot: Result(SwarmEcology, String),
) -> Response(ResponseData) {
  case snapshot {
    Error(reason) ->
      json_response(
        503,
        json.to_string(
          json.object([
            #("status", json.string("unavailable")),
            #("reason", json.string(reason)),
          ]),
        ),
      )
    Ok(swarm) -> handle_live(req, swarm)
  }
}

fn handle_live(
  req: Request(body),
  swarm: SwarmEcology,
) -> Response(ResponseData) {
  let song = swarm.current_song

  case req.method, request.path_segments(req) {
    Get, ["ecology"] -> html_response(render_ecology_html(swarm))
    Get, ["ecology", "swarm"] | Get, ["api", "v1", "ecology", "swarm"] ->
      json_response(200, json.to_string(swarm_to_json(swarm)))
    Get, ["ecology", "song"] | Get, ["api", "v1", "ecology", "song"] ->
      json_response(200, json.to_string(song_to_json(song)))
    Get, ["ecology", "spectrogram.svg"]
    | Get, ["api", "v1", "ecology", "spectrogram.svg"]
    -> svg_response(render_song_svg(song))
    Get, ["ecology", "sparkline"]
    | Get, ["api", "v1", "ecology", "sparkline"]
    -> text_response(render_song_ascii_sparkline(song))
    _, _ -> json_response(404, "{\"error\":\"not_found\",\"path\":\"ecology\"}")
  }
}
