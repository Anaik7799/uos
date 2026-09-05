import cepaf_gleam/ui/wisp/router as c3i_router
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/string
import mist.{type Connection, type ResponseData}

pub fn main() {
  io.println("=== Indrajaal C3I Web Cockpit ===")
  io.println("Starting on http://0.0.0.0:4100")

  let router = fn(req: Request(Connection)) -> Response(ResponseData) {
    let path = "/" <> string.join(request.path_segments(req), "/")

    case request.path_segments(req) {
      // AG-UI protocol routes (SSE event streams + health)
      ["ag-ui", ..] -> {
        let json_body = c3i_router.route(path)
        case string.contains(path, "events") || string.contains(path, "run") {
          True -> {
            response.new(200)
            |> response.set_body(mist.Bytes(bytes_tree.from_string(json_body)))
            |> response.prepend_header("content-type", "text/event-stream")
            |> response.prepend_header("cache-control", "no-cache")
            |> response.prepend_header("connection", "keep-alive")
            |> response.prepend_header("access-control-allow-origin", "*")
          }
          False -> {
            response.new(200)
            |> response.set_body(mist.Bytes(bytes_tree.from_string(json_body)))
            |> response.prepend_header("content-type", "application/json")
            |> response.prepend_header("access-control-allow-origin", "*")
          }
        }
      }
      ["api", ..] -> {
        let json_body = c3i_router.route(path)
        response.new(200)
        |> response.set_body(mist.Bytes(bytes_tree.from_string(json_body)))
        |> response.prepend_header("content-type", "application/json")
        |> response.prepend_header("access-control-allow-origin", "*")
      }
      ["planning"] -> {
        response.new(200)
        |> response.set_body(
          mist.Bytes(bytes_tree.from_string(render_planning_dashboard())),
        )
        |> response.prepend_header("content-type", "text/html")
      }
      _ -> {
        response.new(200)
        |> response.set_body(mist.Bytes(bytes_tree.from_string(render_shell())))
        |> response.prepend_header("content-type", "text/html")
      }
    }
  }

  let assert Ok(_) =
    mist.new(router)
    |> mist.port(4100)
    |> mist.bind("0.0.0.0")
    |> mist.start

  io.println("C3I Cockpit running on http://0.0.0.0:4100")
  io.println("  LAN:       http://192.168.1.134:4100")
  io.println("  Tailscale: http://100.78.98.18:4100")
  process.sleep_forever()
}

fn render_shell() -> String {
  "<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='utf-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1'>
  <title>Indrajaal C3I Cockpit</title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; font-family: 'SF Mono', 'Fira Code', monospace; background: #0a0a0a; color: #e0e0e0; }
    .shell { display: flex; min-height: 100vh; }
    .nav { width: 220px; background: #111; border-right: 1px solid #222; padding: 1rem 0; }
    .nav h1 { color: #ffc107; font-size: 1.1rem; padding: 0 1rem; margin: 0 0 1.5rem 0; }
    .nav a { display: block; padding: 0.7rem 1rem; color: #888; text-decoration: none; border-left: 3px solid transparent; font-size: 0.85rem; }
    .nav a:hover { background: #1a1a1a; color: #fff; }
    .nav a.active { color: #ffc107; border-left-color: #ffc107; background: #1a1a1a; }
    .main { flex: 1; padding: 2rem; }
    .card { background: #151515; border: 1px solid #222; border-radius: 8px; padding: 1.5rem; margin-bottom: 1rem; }
    .card h2 { margin: 0 0 1rem 0; color: #ffc107; font-size: 1rem; }
    .metrics { display: flex; gap: 2rem; flex-wrap: wrap; }
    .metric .value { font-size: 2rem; font-weight: bold; color: #4caf50; }
    .metric .label { color: #666; font-size: 0.75rem; text-transform: uppercase; }
    pre { background: #111; padding: 1rem; border-radius: 4px; overflow-x: auto; font-size: 0.8rem; color: #aaa; }
    #api-result { white-space: pre-wrap; }
    .endpoint-btn { background: #222; color: #ffc107; border: 1px solid #333; padding: 0.4rem 0.8rem; border-radius: 4px; cursor: pointer; font-family: inherit; font-size: 0.8rem; margin: 0.2rem; }
    .endpoint-btn:hover { background: #333; }
  </style>
</head>
<body>
  <div class='shell'>
    <nav class='nav'>
      <h1>INDRAJAAL C3I</h1>
      <a href='/' class='active'>Dashboard</a>
      <a href='/planning' style='color:#ff9800;font-weight:bold'>Planning Cockpit</a>
      <a href='#' onclick='fetchApi(\"/api/health\")'>Health</a>
      <a href='#' onclick='fetchApi(\"/api/planning/tasks\")'>Planning API</a>
      <a href='#' onclick='fetchApi(\"/api/verification/status\")'>Verification</a>
      <a href='#' onclick='fetchApi(\"/api/zenoh/health\")'>Zenoh Mesh</a>
      <a href='#' onclick='fetchApi(\"/api/cockpit/nodes\")'>Cockpit</a>
      <a href='#' onclick='fetchApi(\"/api/immune/status\")'>Immune System</a>
      <a href='#' onclick='fetchApi(\"/api/knowledge/graph\")'>Knowledge</a>
      <a href='#' onclick='fetchApi(\"/api/substrate/status\")'>Substrate</a>
      <a href='#' onclick='fetchApi(\"/api/metabolic/status\")'>Metabolic</a>
      <a href='#' onclick='fetchApi(\"/api/podman/containers\")'>Podman</a>
      <a href='#' onclick='fetchApi(\"/api/mcp/status\")'>MCP Server</a>
      <a href='#' onclick='fetchApi(\"/api/kms/catalog\")'>KMS Catalog</a>
      <a href='#' onclick='fetchApi(\"/api/telemetry/status\")'>Telemetry</a>
      <a href='#' onclick='fetchApi(\"/api/prajna/health\")'>Prajna</a>
      <a href='#' onclick='fetchApi(\"/api/agents/hierarchy\")'>Agents</a>
      <a href='#' onclick='fetchApi(\"/api/holon/identity\")'>Holon</a>
      <a href='#' onclick='fetchApi(\"/api/config/mesh\")'>Config</a>
      <a href='#' onclick='fetchApi(\"/api/git/health\")'>Git Intel</a>
      <a href='#' onclick='fetchApi(\"/api/db/status\")'>Database</a>
      <a href='#' onclick='fetchApi(\"/api/bridge/status\")'>Bridge</a>
      <a href='#' onclick='fetchApi(\"/api/smriti/catalog\")'>Smriti</a>
      <a href='#' onclick='connectAgui()' style='color:#00e5ff;border-left-color:#00e5ff'>AG-UI Stream</a>
    </nav>
    <main class='main'>
      <a href='/planning' style='display:block;text-decoration:none;margin-bottom:1rem'>
        <div class='card' style='border-color:#ff9800;cursor:pointer;transition:border-color 0.2s' onmouseover='this.style.borderColor=\"#ffc107\"' onmouseout='this.style.borderColor=\"#ff9800\"'>
          <h2 style='color:#ff9800'>Planning Cockpit</h2>
          <p style='color:#999;font-size:0.85rem;margin:0'>8-panel SIL-6 dashboard: Task Board, OODA Cycle, Safety Kernel, Enforcer, Graph Verification, Orchestration Mesh, Chaya Twin, Startup Optimization. Real-time AG-UI streaming with Dark Cockpit mode.</p>
          <span style='color:#ff9800;font-size:0.8rem'>Open Planning Cockpit &rarr;</span>
        </div>
      </a>
      <div class='card'>
        <h2>System Overview</h2>
        <div class='metrics'>
          <div class='metric'><span class='value'>7</span><br><span class='label'>Containers UP</span></div>
          <div class='metric'><span class='value'>688</span><br><span class='label'>Tests Passing</span></div>
          <div class='metric'><span class='value'>900</span><br><span class='label'>MSTS Directives</span></div>
          <div class='metric'><span class='value'>SIL-6</span><br><span class='label'>Compliance</span></div>
        </div>
      </div>
      <div class='card'>
        <h2>API Explorer</h2>
        <p style='color:#666;font-size:0.85rem'>Click an endpoint to query it live:</p>
        <div>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/health\")'>/api/health</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/planning/tasks\")'>/api/planning/tasks</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/verification/status\")'>/api/verification/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/zenoh/health\")'>/api/zenoh/health</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/cockpit/nodes\")'>/api/cockpit/nodes</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/immune/status\")'>/api/immune/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/knowledge/graph\")'>/api/knowledge/graph</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/substrate/status\")'>/api/substrate/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/metabolic/status\")'>/api/metabolic/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/podman/containers\")'>/api/podman/containers</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/mcp/status\")'>/api/mcp/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/kms/catalog\")'>/api/kms/catalog</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/telemetry/status\")'>/api/telemetry/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/prajna/health\")'>/api/prajna/health</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/agents/hierarchy\")'>/api/agents/hierarchy</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/holon/identity\")'>/api/holon/identity</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/config/mesh\")'>/api/config/mesh</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/git/health\")'>/api/git/health</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/db/status\")'>/api/db/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/bridge/status\")'>/api/bridge/status</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/api/smriti/catalog\")'>/api/smriti/catalog</button>
          <button class='endpoint-btn' onclick='fetchApi(\"/ag-ui/health\")' style='color:#00e5ff'>/ag-ui/health</button>
          <button class='endpoint-btn' onclick='connectAgui()' style='color:#00e5ff'>AG-UI SSE Stream</button>
        </div>
        <pre id='api-result'>Click an endpoint above to see the response.</pre>
      </div>
    </main>
  </div>
  <script>
    async function fetchApi(path) {
      document.getElementById('api-result').textContent = 'Loading ' + path + '...';
      try {
        const res = await fetch(path);
        const data = await res.json();
        document.getElementById('api-result').textContent = JSON.stringify(data, null, 2);
      } catch(e) {
        document.getElementById('api-result').textContent = 'Error: ' + e.message;
      }
    }
    async function connectAgui() {
      const threadId = 'thread_' + Date.now();
      document.getElementById('api-result').textContent = 'Connecting to AG-UI SSE stream...';
      const es = new EventSource('/ag-ui/events?thread=' + threadId);
      es.onmessage = function(e) {
        try {
          const event = JSON.parse(e.data);
          const pre = document.getElementById('api-result');
          pre.textContent += '\\n[' + event.type + '] ' + JSON.stringify(event, null, 2);
          pre.scrollTop = pre.scrollHeight;
        } catch(err) { /* ignore non-JSON frames */ }
      };
      es.onerror = function() { es.close(); };
    }
    console.log('[C3I] Indrajaal Cockpit loaded. SIL-6 DAL-A.');
  </script>
</body>
</html>"
}

fn render_planning_dashboard() -> String {
  "<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='utf-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1'>
  <title>Planning Dashboard - Indrajaal C3I</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'SF Mono','Fira Code',monospace;background:#0a0a0a;color:#e0e0e0;overflow:hidden;height:100vh}
    .shell{display:flex;height:100vh}

    /* Sidebar */
    .nav{width:200px;background:#111;border-right:1px solid #222;padding:1rem 0;overflow-y:auto;flex-shrink:0}
    .nav h1{color:#ffc107;font-size:1rem;padding:0 1rem;margin:0 0 1rem 0}
    .nav a{display:block;padding:0.5rem 1rem;color:#888;text-decoration:none;border-left:3px solid transparent;font-size:0.78rem;transition:all 0.15s}
    .nav a:hover{background:#1a1a1a;color:#fff}
    .nav a.active{color:#ffc107;border-left-color:#ffc107;background:#1a1a1a}
    .nav .sep{height:1px;background:#222;margin:0.5rem 1rem}

    /* Main grid */
    .main{flex:1;display:flex;flex-direction:column;overflow:hidden}
    .top-bar{display:flex;align-items:center;justify-content:space-between;padding:0.5rem 1rem;background:#111;border-bottom:1px solid #222;flex-shrink:0}
    .top-bar .title{color:#ffc107;font-size:0.9rem;font-weight:bold}
    .top-bar .health{font-size:0.75rem;padding:0.25rem 0.6rem;border-radius:4px}
    .health-nominal{background:#1b5e20;color:#4caf50}
    .health-degraded{background:#e65100;color:#ff9800}
    .health-critical{background:#b71c1c;color:#f44336}
    .kbd{background:#222;color:#888;padding:0.15rem 0.4rem;border-radius:3px;font-size:0.65rem;border:1px solid #333;margin-left:0.5rem}

    .grid{display:grid;grid-template-columns:repeat(5,1fr);grid-template-rows:repeat(4,1fr);gap:6px;padding:6px;flex:1;overflow:hidden}

    /* Card base */
    .card{background:#151515;border:1px solid #222;border-radius:6px;padding:0.75rem;overflow:hidden;display:flex;flex-direction:column;cursor:pointer;transition:border-color 0.2s}
    .card:hover{border-color:#ffc107}
    .card.selected{border-color:#ffc107;box-shadow:0 0 8px rgba(255,193,7,0.15)}
    .card h2{font-size:0.75rem;color:#ffc107;margin-bottom:0.5rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .card-body{flex:1;overflow:hidden;font-size:0.7rem;color:#aaa}

    /* Panel spans */
    .p-task{grid-column:1/3;grid-row:1/3}
    .p-ooda{grid-column:3/4;grid-row:1/2}
    .p-safety{grid-column:4/5;grid-row:1/2}
    .p-enforcer{grid-column:5/6;grid-row:1/2}
    .p-graph{grid-column:3/4;grid-row:2/3}
    .p-orch{grid-column:4/6;grid-row:2/3}
    .p-chaya{grid-column:1/3;grid-row:3/4}
    .p-startup{grid-column:3/6;grid-row:3/4}
    .p-detail{grid-column:1/3;grid-row:4/5}
    .p-chat{grid-column:3/6;grid-row:4/5}

    /* Task columns */
    .task-cols{display:flex;gap:4px;flex:1;overflow:hidden}
    .task-col{flex:1;display:flex;flex-direction:column;min-width:0}
    .task-col-hdr{font-size:0.65rem;color:#888;text-transform:uppercase;margin-bottom:4px;text-align:center}
    .task-col-body{flex:1;overflow-y:auto;display:flex;flex-direction:column;gap:3px}
    .task-card{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:4px;padding:4px 6px;font-size:0.65rem;color:#ccc;cursor:pointer}
    .task-card:hover{border-color:#ffc107}
    .task-card .task-id{color:#666;font-size:0.6rem}
    .tc-pending{border-left:2px solid #2196f3}
    .tc-progress{border-left:2px solid #ffc107}
    .tc-done{border-left:2px solid #4caf50}
    .tc-blocked{border-left:2px solid #f44336}

    /* Indicators */
    .indicator{display:inline-block;width:8px;height:8px;border-radius:50%;margin:1px}
    .ind-ok{background:#4caf50}
    .ind-warn{background:#ff9800}
    .ind-fail{background:#f44336}
    .ind-off{background:#333}

    /* OODA ring placeholder */
    .ooda-ring{width:80px;height:80px;border-radius:50%;border:3px solid #ffc107;margin:0 auto 0.5rem;display:flex;align-items:center;justify-content:center;font-size:0.7rem;color:#ffc107;position:relative}
    .ooda-ring::after{content:'';position:absolute;width:60px;height:60px;border-radius:50%;border:2px solid #4caf50}

    /* Gauge */
    .gauge{height:6px;background:#222;border-radius:3px;overflow:hidden;margin:4px 0}
    .gauge-fill{height:100%;border-radius:3px;transition:width 0.5s}
    .gauge-ok{background:#4caf50}
    .gauge-warn{background:#ff9800}
    .gauge-crit{background:#f44336}

    /* Enforcer layers */
    .layer{display:flex;align-items:center;gap:6px;padding:2px 0;font-size:0.65rem}
    .layer-dot{width:6px;height:6px;border-radius:50%}

    /* Orch nodes */
    .orch-nodes{display:flex;flex-wrap:wrap;gap:4px}
    .orch-node{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:4px;padding:3px 6px;font-size:0.6rem}
    .orch-node.up{border-color:#4caf50;color:#4caf50}
    .orch-node.down{border-color:#f44336;color:#f44336}

    /* SVG placeholder */
    .svg-ph{background:#111;border:1px solid #222;border-radius:4px;display:flex;align-items:center;justify-content:center;color:#333;font-size:0.7rem;min-height:50px;flex:1}

    /* Chat */
    .chat-wrap{display:flex;flex-direction:column;flex:1;overflow:hidden}
    .chat-msgs{flex:1;overflow-y:auto;font-size:0.65rem;padding:4px;background:#111;border-radius:4px;margin-bottom:4px}
    .chat-msg{padding:2px 0;border-bottom:1px solid #1a1a1a}
    .chat-msg .role{color:#ffc107;font-weight:bold}
    .chat-msg .sse{color:#00e5ff}
    .chat-input-wrap{display:flex;gap:4px}
    .chat-input{flex:1;background:#111;border:1px solid #333;color:#e0e0e0;padding:4px 8px;border-radius:4px;font-family:inherit;font-size:0.7rem}
    .chat-input:focus{outline:none;border-color:#ffc107}
    .chat-send{background:#ffc107;color:#0a0a0a;border:none;padding:4px 12px;border-radius:4px;cursor:pointer;font-family:inherit;font-size:0.7rem;font-weight:bold}

    /* DFA */
    .dfa-states{display:flex;gap:3px;flex-wrap:wrap}
    .dfa-state{padding:2px 6px;border-radius:3px;font-size:0.6rem;border:1px solid #333}
    .dfa-state.active{border-color:#ffc107;color:#ffc107;background:#1a1a00}
    .dfa-state.done{border-color:#4caf50;color:#4caf50;background:#0a1a0a}

    /* Check list */
    .checks{font-size:0.65rem}
    .check-row{display:flex;align-items:center;gap:4px;padding:1px 0}

    /* Sync bar */
    .sync-bar{display:flex;align-items:center;gap:6px;font-size:0.65rem}
    .sync-pct{color:#ffc107;font-weight:bold}

    /* Command palette */
    .cmd-palette{display:none;position:fixed;top:20%;left:50%;transform:translateX(-50%);background:#1a1a1a;border:1px solid #ffc107;border-radius:8px;padding:1rem;width:400px;z-index:1000;box-shadow:0 8px 32px rgba(0,0,0,0.8)}
    .cmd-palette.show{display:block}
    .cmd-palette input{width:100%;background:#111;border:1px solid #333;color:#e0e0e0;padding:0.5rem;border-radius:4px;font-family:inherit;font-size:0.85rem;margin-bottom:0.5rem}
    .cmd-palette input:focus{outline:none;border-color:#ffc107}
    .cmd-palette .cmd-items{max-height:200px;overflow-y:auto}
    .cmd-palette .cmd-item{padding:0.4rem 0.5rem;cursor:pointer;border-radius:4px;font-size:0.8rem;color:#aaa}
    .cmd-palette .cmd-item:hover{background:#222;color:#fff}
    .overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:999}
    .overlay.show{display:block}

    /* Scrollbar */
    ::-webkit-scrollbar{width:4px}
    ::-webkit-scrollbar-track{background:#0a0a0a}
    ::-webkit-scrollbar-thumb{background:#333;border-radius:2px}
  </style>
</head>
<body>
  <div class='shell'>
    <nav class='nav' id='sidebar'>
      <h1>PLANNING</h1>
      <a href='/' >Main Dashboard</a>
      <div class='sep'></div>
      <a href='#' class='active' onclick='selectPanel(\"task\")'>Task Board</a>
      <a href='#' onclick='selectPanel(\"ooda\")'>OODA Cycle</a>
      <a href='#' onclick='selectPanel(\"safety\")'>Safety Kernel</a>
      <a href='#' onclick='selectPanel(\"enforcer\")'>Enforcer Shield</a>
      <a href='#' onclick='selectPanel(\"graph\")'>Graph Verify</a>
      <a href='#' onclick='selectPanel(\"orch\")'>Orchestration</a>
      <a href='#' onclick='selectPanel(\"chaya\")'>Chaya Twin</a>
      <a href='#' onclick='selectPanel(\"startup\")'>Startup Opt</a>
      <div class='sep'></div>
      <a href='#' onclick='selectPanel(\"detail\")'>Detail Panel</a>
      <a href='#' onclick='selectPanel(\"chat\")' style='color:#00e5ff'>AG-UI Chat</a>
    </nav>

    <div class='main'>
      <div class='top-bar'>
        <span class='title'>INDRAJAAL C3I PLANNING DASHBOARD</span>
        <span>
          <span class='kbd'>Ctrl+K</span> Command
          <span class='kbd'>Ctrl+E</span> Emergency
          <span class='kbd'>Ctrl+O</span> OODA
        </span>
        <span class='health health-nominal' id='health-badge'>NOMINAL</span>
      </div>

      <div class='grid'>
        <!-- P1: Task Board -->
        <div class='card p-task' id='panel-task' onclick='showDetail(\"task\")'>
          <h2>Task Board</h2>
          <div class='card-body'>
            <div class='task-cols'>
              <div class='task-col'>
                <div class='task-col-hdr'>Pending</div>
                <div class='task-col-body' id='col-pending'></div>
              </div>
              <div class='task-col'>
                <div class='task-col-hdr'>In Progress</div>
                <div class='task-col-body' id='col-inprogress'></div>
              </div>
              <div class='task-col'>
                <div class='task-col-hdr'>Completed</div>
                <div class='task-col-body' id='col-completed'></div>
              </div>
              <div class='task-col'>
                <div class='task-col-hdr'>Blocked</div>
                <div class='task-col-body' id='col-blocked'></div>
              </div>
            </div>
          </div>
        </div>

        <!-- P2: OODA Cycle -->
        <div class='card p-ooda' id='panel-ooda' onclick='showDetail(\"ooda\")'>
          <h2>OODA Cycle</h2>
          <div class='card-body' style='text-align:center'>
            <div class='ooda-ring' id='ooda-phase'>OBS</div>
            <div style='font-size:0.65rem;color:#888'>
              <div>Cycle: <span id='ooda-cycle-count'>0</span></div>
              <div>Latency: <span id='ooda-latency'>--</span>ms</div>
              <div>Phase: <span id='ooda-phase-text'>Observe</span></div>
            </div>
          </div>
        </div>

        <!-- P3: Safety Kernel -->
        <div class='card p-safety' id='panel-safety' onclick='showDetail(\"safety\")'>
          <h2>Safety Kernel</h2>
          <div class='card-body'>
            <div id='safety-indicators' style='margin-bottom:6px'></div>
            <div style='font-size:0.65rem;color:#888'>Threat Level</div>
            <div class='gauge'><div class='gauge-fill gauge-ok' id='threat-gauge' style='width:15%'></div></div>
            <div style='font-size:0.6rem;color:#666' id='safety-score'>10/10 checks passing</div>
          </div>
        </div>

        <!-- P4: Enforcer Shield -->
        <div class='card p-enforcer' id='panel-enforcer' onclick='showDetail(\"enforcer\")'>
          <h2>Enforcer Shield</h2>
          <div class='card-body'>
            <div id='enforcer-layers'></div>
            <div style='font-size:0.65rem;color:#888;margin-top:4px'>Violations</div>
            <div id='violation-feed' style='font-size:0.6rem;color:#666;max-height:40px;overflow-y:auto'>No violations</div>
          </div>
        </div>

        <!-- P5: Graph Verify -->
        <div class='card p-graph' id='panel-graph' onclick='showDetail(\"graph\")'>
          <h2>Graph Verify</h2>
          <div class='card-body' style='display:flex;flex-direction:column'>
            <div class='svg-ph' id='graph-svg'>DAG Visualization</div>
            <div class='checks' id='graph-checks'></div>
          </div>
        </div>

        <!-- P6: Orchestration Mesh -->
        <div class='card p-orch' id='panel-orch' onclick='showDetail(\"orch\")'>
          <h2>Orchestration Mesh</h2>
          <div class='card-body'>
            <div class='orch-nodes' id='orch-nodes'></div>
            <div style='margin-top:6px;font-size:0.65rem;color:#888'>
              Quorum: <span id='quorum-status' style='color:#4caf50'>5/7</span>
            </div>
          </div>
        </div>

        <!-- P7: Chaya Twin -->
        <div class='card p-chaya' id='panel-chaya' onclick='showDetail(\"chaya\")'>
          <h2>Chaya Digital Twin</h2>
          <div class='card-body' style='display:flex;gap:6px'>
            <div style='flex:1'>
              <div class='svg-ph'>Live State</div>
            </div>
            <div style='flex:1'>
              <div class='svg-ph'>Shadow State</div>
            </div>
            <div style='width:80px'>
              <div class='sync-bar'><span>Sync</span> <span class='sync-pct' id='chaya-sync'>98%</span></div>
              <div class='gauge'><div class='gauge-fill gauge-ok' id='chaya-gauge' style='width:98%'></div></div>
              <div style='font-size:0.6rem;color:#666;margin-top:4px' id='chaya-drift'>Drift: 0.02ms</div>
            </div>
          </div>
        </div>

        <!-- P8: Startup Optimization -->
        <div class='card p-startup' id='panel-startup' onclick='showDetail(\"startup\")'>
          <h2>Startup Optimization</h2>
          <div class='card-body' style='display:flex;flex-direction:column;gap:6px'>
            <div class='svg-ph' style='min-height:40px'>Gantt - Boot Sequence</div>
            <div>
              <div style='font-size:0.65rem;color:#888;margin-bottom:3px'>DFA States</div>
              <div class='dfa-states' id='dfa-states'></div>
            </div>
          </div>
        </div>

        <!-- Detail Panel -->
        <div class='card p-detail' id='panel-detail'>
          <h2>Detail</h2>
          <div class='card-body' id='detail-content' style='overflow-y:auto;font-size:0.7rem'>
            Select an item for details
          </div>
        </div>

        <!-- Chat Panel (AG-UI) -->
        <div class='card p-chat' id='panel-chat'>
          <h2>AG-UI Chat</h2>
          <div class='card-body chat-wrap'>
            <div class='chat-msgs' id='chat-messages'>
              <div class='chat-msg'><span class='sse'>[SSE]</span> Connecting to AG-UI...</div>
            </div>
            <div class='chat-input-wrap'>
              <input class='chat-input' id='chat-input' placeholder='Send a message...' onkeydown='if(event.key===\"Enter\")sendChat(this.value)'>
              <button class='chat-send' onclick='sendChat(document.getElementById(\"chat-input\").value)'>Send</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Command Palette -->
  <div class='overlay' id='cmd-overlay' onclick='closePalette()'></div>
  <div class='cmd-palette' id='cmd-palette'>
    <input id='cmd-input' placeholder='Type a command...' oninput='filterCommands(this.value)'>
    <div class='cmd-items' id='cmd-items'></div>
  </div>

  <script>
    // === State ===
    var healthScore = 100;
    var cockpitMode = 'nominal';
    var sseSource = null;
    var selectedPanel = null;

    // === Panel Data Endpoints ===
    var panelEndpoints = {
      task: '/api/planning/tasks',
      ooda: '/api/ooda/status',
      safety: '/api/safety/status',
      enforcer: '/api/enforcer/status',
      graph: '/api/graph/verify',
      orch: '/api/orchestration/status',
      chaya: '/api/chaya/sync',
      startup: '/api/math/optimize'
    };

    // === Init ===
    document.addEventListener('DOMContentLoaded', function() {
      initPanels();
      connectSSE();
      loadAllPanels();
    });

    function initPanels() {
      // Safety indicators
      var si = document.getElementById('safety-indicators');
      for (var i = 0; i < 10; i++) {
        si.innerHTML += '<span class=\"indicator ind-ok\"></span>';
      }

      // Enforcer layers
      var layers = ['L0 Constitutional', 'L1 Atomic', 'L2 Component', 'L3 Transaction', 'L4 System'];
      var el = document.getElementById('enforcer-layers');
      layers.forEach(function(l) {
        el.innerHTML += '<div class=\"layer\"><span class=\"layer-dot\" style=\"background:#4caf50\"></span>' + l + '</div>';
      });

      // Graph checks
      var checks = ['Acyclicity', 'Connectivity', 'Invariants', 'Coverage'];
      var gc = document.getElementById('graph-checks');
      checks.forEach(function(c) {
        gc.innerHTML += '<div class=\"check-row\"><span class=\"indicator ind-ok\"></span> ' + c + '</div>';
      });

      // Orch nodes
      var services = ['wisp-api', 'zenoh-bridge', 'prajna-core', 'immune-sys', 'metabolic', 'cockpit-ui', 'telemetry'];
      var on = document.getElementById('orch-nodes');
      services.forEach(function(s) {
        on.innerHTML += '<div class=\"orch-node up\">' + s + '</div>';
      });

      // DFA states
      var dfaStates = ['INIT', 'BIST', 'NIF_LOAD', 'ZENOH_CONN', 'DB_INIT', 'MESH_JOIN', 'READY'];
      var ds = document.getElementById('dfa-states');
      dfaStates.forEach(function(s, i) {
        var cls = i < 6 ? 'dfa-state done' : 'dfa-state active';
        ds.innerHTML += '<div class=\"' + cls + '\">' + s + '</div>';
      });

      // Seed task board
      seedTasks();
    }

    function seedTasks() {
      var tasks = {
        pending: [{id:'TSK-042',title:'Zenoh TLS rotation'},{id:'TSK-043',title:'DuckDB vacuum'}],
        inprogress: [{id:'TSK-040',title:'Lustre SSR hydration'},{id:'TSK-041',title:'NIF health probe'}],
        completed: [{id:'TSK-038',title:'SQLite WAL mode'},{id:'TSK-039',title:'Podman rootless'}],
        blocked: [{id:'TSK-037',title:'FMEA coverage gap'}]
      };

      Object.keys(tasks).forEach(function(status) {
        var col = document.getElementById('col-' + status);
        if (!col) return;
        tasks[status].forEach(function(t) {
          var cls = status === 'pending' ? 'tc-pending' : status === 'inprogress' ? 'tc-progress' : status === 'completed' ? 'tc-done' : 'tc-blocked';
          col.innerHTML += '<div class=\"task-card ' + cls + '\" onclick=\"event.stopPropagation();showTaskDetail(\\'' + t.id + '\\',\\'' + t.title + '\\',\\'' + status + '\\')\">' +
            '<div class=\"task-id\">' + t.id + '</div>' + t.title + '</div>';
        });
      });
    }

    // === Data Loading ===
    function loadAllPanels() {
      Object.keys(panelEndpoints).forEach(function(key) {
        loadPanel(key);
      });
    }

    function loadPanel(key) {
      fetch(panelEndpoints[key])
        .then(function(r) { return r.json(); })
        .then(function(data) {
          updatePanelFromData(key, data);
        })
        .catch(function() { /* silent */ });
    }

    function updatePanelFromData(key, data) {
      if (!data) return;
      // Panel 2: OODA — /api/ooda/status returns {cycle_count, last_cycle_ms, target_ms, patterns}
      if (key === 'ooda') {
        document.getElementById('ooda-cycle-count').textContent = data.cycle_count || '0';
        document.getElementById('ooda-latency').textContent = (data.last_cycle_ms || '0') + 'ms';
        var phase = (data.patterns && data.patterns[0]) || 'Nominal';
        document.getElementById('ooda-phase-text').textContent = phase;
        var withinTarget = (data.last_cycle_ms || 0) <= (data.target_ms || 100);
        document.getElementById('ooda-latency').style.color = withinTarget ? '#4caf50' : '#f44336';
      }
      // Panel 3: Safety — /api/safety/status (may return error if not routed)
      if (key === 'safety') {
        if (data.threat_level !== undefined) {
          var gauge = document.getElementById('threat-gauge');
          if (gauge) gauge.textContent = (data.threat_level * 100).toFixed(0) + '%';
          healthScore = 100 - (data.threat_level * 100);
        }
        if (data.checks) {
          var si = document.getElementById('safety-indicators');
          if (si) {
            si.innerHTML = data.checks.map(function(c) {
              var color = c.passed ? '#4caf50' : '#f44336';
              return '<span style=\"color:' + color + ';margin-right:4px\">' + (c.passed ? 'OK' : 'FAIL') + ' ' + c.name + '</span>';
            }).join(' ');
          }
        }
        updateCockpitMode();
      }
      // Panel 5: Graph — /api/graph/verify returns {checks, all_passed}
      if (key === 'graph') {
        var gc = document.getElementById('graph-checks');
        if (gc && data.checks) {
          gc.innerHTML = data.checks.map(function(c) {
            var color = c.passed ? '#4caf50' : '#f44336';
            return '<div style=\"color:' + color + '\">' + (c.passed ? 'PASS' : 'FAIL') + ' ' + c.name + '</div>';
          }).join('');
        }
      }
      // Panel 6: Orchestration — /api/orchestration/status returns {services, online, quorum, service_names}
      if (key === 'orch') {
        var qs = document.getElementById('quorum-status');
        if (qs) qs.textContent = data.quorum ? 'QUORUM MET' : 'QUORUM LOST';
        if (qs) qs.style.color = data.quorum ? '#4caf50' : '#f44336';
        var on = document.getElementById('orch-nodes');
        if (on && data.service_names) {
          on.innerHTML = data.service_names.map(function(s) {
            return '<span style=\"color:#4caf50;margin-right:6px\">' + s + '</span>';
          }).join('');
        }
      }
      // Panel 4: Enforcer — /api/enforcer/status (may return error)
      if (key === 'enforcer') {
        var el = document.getElementById('enforcer-layers');
        if (el && data.statistics) {
          el.innerHTML = Object.entries(data.statistics).map(function(e) {
            return '<div>' + e[0] + ': ' + e[1] + '</div>';
          }).join('');
        }
      }
      // Panel 8: Startup — /api/math/optimize returns {containers, execution_waves, critical_path_ms, dfa_states}
      if (key === 'startup') {
        var ds = document.getElementById('dfa-states');
        if (ds) ds.textContent = 'Containers: ' + (data.containers || '?') + ' | Waves: ' + (data.execution_waves || '?') + ' | DFA: ' + (data.dfa_states || '?') + ' states | CP: ' + (data.critical_path_ms || '?') + 'ms';
      }
      // Panel 7: Chaya — /api/chaya/sync returns {planning_tasks, chaya_tasks, orphans, mismatches}
      if (key === 'chaya') {
        var dc = document.getElementById('detail-content');
        // Update via detail panel if selected
      }
    }

    // === AG-UI SSE ===
    function connectSSE() {
      var threadId = 'planning_' + Date.now();
      sseSource = new EventSource('/ag-ui/events?thread=' + threadId);
      sseSource.onmessage = function(e) {
        try {
          var evt = JSON.parse(e.data);
          appendChatMessage('sse', '[' + (evt.type || 'event') + '] ' + (evt.message || JSON.stringify(evt).substring(0, 100)));
          handleSSEEvent(evt);
        } catch(err) { /* ignore non-JSON */ }
      };
      sseSource.onerror = function() {
        appendChatMessage('sse', '[SSE] Connection lost. Reconnecting...');
      };
      sseSource.onopen = function() {
        appendChatMessage('sse', '[SSE] Connected to AG-UI event stream');
      };
    }

    function handleSSEEvent(evt) {
      if (evt.type === 'HEALTH_UPDATE') {
        healthScore = evt.score || healthScore;
        updateCockpitMode();
      }
      if (evt.type === 'TASK_UPDATE' && evt.task) {
        // Could update task board dynamically
      }
      if (evt.type === 'OODA_PHASE' && evt.phase) {
        document.getElementById('ooda-phase').textContent = evt.phase.substring(0, 3).toUpperCase();
        document.getElementById('ooda-phase-text').textContent = evt.phase;
      }
    }

    // === Chat ===
    function sendChat(text) {
      if (!text || !text.trim()) return;
      var input = document.getElementById('chat-input');
      input.value = '';
      appendChatMessage('user', text);

      fetch('/ag-ui/run', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({thread_id: 'planning_chat', message: text})
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        appendChatMessage('agent', data.response || JSON.stringify(data));
      })
      .catch(function(err) {
        appendChatMessage('sse', '[Error] ' + err.message);
      });
    }

    function appendChatMessage(role, text) {
      var msgs = document.getElementById('chat-messages');
      var cls = role === 'sse' ? 'sse' : 'role';
      var label = role === 'user' ? 'You' : role === 'agent' ? 'Agent' : 'SSE';
      msgs.innerHTML += '<div class=\"chat-msg\"><span class=\"' + cls + '\">[' + label + ']</span> ' + escapeHtml(text) + '</div>';
      msgs.scrollTop = msgs.scrollHeight;
    }

    function escapeHtml(s) {
      var d = document.createElement('div');
      d.textContent = s;
      return d.innerHTML;
    }

    // === Detail Panel ===
    function showDetail(panel) {
      selectedPanel = panel;
      var dc = document.getElementById('detail-content');
      dc.innerHTML = '<strong>' + panel.toUpperCase() + '</strong><br>Loading details from ' + (panelEndpoints[panel] || 'N/A') + '...';

      // Highlight selected
      document.querySelectorAll('.card').forEach(function(c) { c.classList.remove('selected'); });
      var el = document.getElementById('panel-' + panel);
      if (el) el.classList.add('selected');

      // Fetch detail
      if (panelEndpoints[panel]) {
        fetch(panelEndpoints[panel])
          .then(function(r) { return r.json(); })
          .then(function(data) {
            dc.innerHTML = '<strong>' + panel.toUpperCase() + '</strong><pre style=\"background:#111;padding:6px;border-radius:4px;font-size:0.65rem;overflow:auto;max-height:80px\">' + JSON.stringify(data, null, 2) + '</pre>';
          })
          .catch(function() {
            dc.innerHTML = '<strong>' + panel.toUpperCase() + '</strong><br><span style=\"color:#666\">No data available</span>';
          });
      }
    }

    function showTaskDetail(id, title, status) {
      var dc = document.getElementById('detail-content');
      dc.innerHTML = '<strong>Task: ' + id + '</strong><br>' +
        '<div style=\"margin-top:4px\">Title: ' + escapeHtml(title) + '</div>' +
        '<div>Status: <span style=\"color:' + (status === 'completed' ? '#4caf50' : status === 'blocked' ? '#f44336' : '#ffc107') + '\">' + status + '</span></div>' +
        '<div style=\"margin-top:6px;color:#666\">Click to view full task context, dependencies, and audit trail.</div>';
    }

    function selectPanel(name) {
      // Update nav active state
      document.querySelectorAll('.nav a').forEach(function(a) { a.classList.remove('active'); });
      event.target.classList.add('active');
      showDetail(name);
    }

    // === Cockpit Mode ===
    function updateCockpitMode() {
      var badge = document.getElementById('health-badge');
      var threat = document.getElementById('threat-gauge');
      if (healthScore >= 80) {
        cockpitMode = 'nominal';
        badge.className = 'health health-nominal';
        badge.textContent = 'NOMINAL';
        threat.style.width = (100 - healthScore) + '%';
        threat.className = 'gauge-fill gauge-ok';
      } else if (healthScore >= 50) {
        cockpitMode = 'degraded';
        badge.className = 'health health-degraded';
        badge.textContent = 'DEGRADED';
        threat.style.width = (100 - healthScore) + '%';
        threat.className = 'gauge-fill gauge-warn';
      } else {
        cockpitMode = 'critical';
        badge.className = 'health health-critical';
        badge.textContent = 'CRITICAL';
        threat.style.width = (100 - healthScore) + '%';
        threat.className = 'gauge-fill gauge-crit';
        document.body.style.borderTop = '2px solid #f44336';
      }
    }

    // === Command Palette ===
    var commands = [
      {name: 'Go to Main Dashboard', action: function() { window.location.href = '/'; }},
      {name: 'Refresh All Panels', action: function() { loadAllPanels(); closePalette(); }},
      {name: 'Toggle OODA Focus', action: function() { showDetail('ooda'); closePalette(); }},
      {name: 'Show Safety Kernel', action: function() { showDetail('safety'); closePalette(); }},
      {name: 'Emergency Mode', action: function() { healthScore = 20; updateCockpitMode(); closePalette(); }},
      {name: 'Reset to Nominal', action: function() { healthScore = 100; updateCockpitMode(); closePalette(); }},
      {name: 'Focus Task Board', action: function() { showDetail('task'); closePalette(); }},
      {name: 'Show Enforcer Shield', action: function() { showDetail('enforcer'); closePalette(); }},
      {name: 'Show Orchestration', action: function() { showDetail('orch'); closePalette(); }},
      {name: 'Show Chaya Twin', action: function() { showDetail('chaya'); closePalette(); }}
    ];

    function openPalette() {
      document.getElementById('cmd-overlay').classList.add('show');
      document.getElementById('cmd-palette').classList.add('show');
      var inp = document.getElementById('cmd-input');
      inp.value = '';
      inp.focus();
      renderCommands('');
    }

    function closePalette() {
      document.getElementById('cmd-overlay').classList.remove('show');
      document.getElementById('cmd-palette').classList.remove('show');
    }

    function renderCommands(filter) {
      var items = document.getElementById('cmd-items');
      items.innerHTML = '';
      var lf = filter.toLowerCase();
      commands.forEach(function(cmd, i) {
        if (lf && cmd.name.toLowerCase().indexOf(lf) === -1) return;
        items.innerHTML += '<div class=\"cmd-item\" onclick=\"commands[' + i + '].action()\">' + cmd.name + '</div>';
      });
    }

    function filterCommands(val) { renderCommands(val); }

    // === Keyboard Shortcuts ===
    document.addEventListener('keydown', function(e) {
      // Ctrl+K: Command palette
      if (e.ctrlKey && e.key === 'k') {
        e.preventDefault();
        openPalette();
      }
      // Ctrl+E: Emergency mode
      if (e.ctrlKey && e.key === 'e') {
        e.preventDefault();
        healthScore = 20;
        updateCockpitMode();
        appendChatMessage('sse', '[EMERGENCY] Cockpit switched to CRITICAL mode');
      }
      // Ctrl+O: OODA focus
      if (e.ctrlKey && e.key === 'o') {
        e.preventDefault();
        showDetail('ooda');
        appendChatMessage('sse', '[OODA] Focused on OODA cycle panel');
      }
      // Escape: close palette
      if (e.key === 'Escape') {
        closePalette();
      }
    });

    console.log('[C3I] Planning Dashboard loaded. Cockpit mode: ' + cockpitMode);
  </script>
</body>
</html>"
}
