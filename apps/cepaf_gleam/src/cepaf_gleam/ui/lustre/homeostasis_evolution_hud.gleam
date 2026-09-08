//// Homeostasis GUI: one evidence denotation, explicit test/real selection.
//// SC-HOMEO-UI-001 / UOS-UI-QUALITY-001.
import cepaf_gleam/ha/homeostasis_evolution_engine.{type HomeostasisSystemState}
import cepaf_gleam/ui/homeostasis_data as data
import cepaf_gleam/ui/homeostasis_status as status
import cepaf_gleam/ui/tui/homeostasis_evolution_view as terminal
import gleam/int
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub const components = ["provenance", "controls", "pid", "phase", "physiology", "runtime", "pareto", "quorum", "stream", "checklist"]

pub fn render_hud(state: HomeostasisSystemState) -> Element(msg) {
  render_view(data.Selection(data.TestData, data.Nominal, 1), "all", status.simulated(state), state.metrics.timestamp_us)
}
pub fn render_unavailable() -> Element(msg) { render_snapshot(status.unavailable(), 0) }
pub fn render_snapshot(snapshot: status.Snapshot, now: Int) -> Element(msg) {
  render_view(data.default(), "all", snapshot, now)
}

fn panel(id: String, title: String, children: List(Element(msg))) -> Element(msg) {
  html.section([attribute.id("component-" <> id), attribute.attribute("data-component", id)], [
    html.h2([], [html.text(title)]), ..children
  ])
}

pub fn render_view(selection: data.Selection, component: String, snapshot: status.Snapshot, now: Int) -> Element(msg) {
  render_view_on_port(selection, component, snapshot, now, 4100)
}

/// The listener supplies the port; request headers never determine navigation.
pub fn render_view_on_port(selection: data.Selection, component: String, snapshot: status.Snapshot, now: Int, port: Int) -> Element(msg) {
  let origin = "http://nas-1.tail55d152.ts.net:" <> int.to_string(port)
  let fields = status.fields(snapshot, now)
  let visibility = case component == "all" { True -> "" False -> ".homeostasis-evolution-hud section[data-component]{display:none}.homeostasis-evolution-hud #component-" <> component <> "{display:block}" }
  html.div([
    attribute.class("homeostasis-evolution-hud"),
    attribute.attribute("data-stream-url", "/api/v1/homeostasis/stream?" <> data.query(selection)),
  ], [
    html.style([], "body{margin:0;background:#101827;color:#e0e6ed;font:16px/1.5 system-ui,sans-serif}.homeostasis-evolution-hud{padding:1rem;max-width:100%;overflow-wrap:anywhere}a{color:#8bd6ff}:focus-visible{outline:3px solid #ffc857;outline-offset:3px}section{border:1px solid #34435b;border-radius:8px;padding:1rem;margin-block:1rem;max-width:100%;overflow-x:auto}h1{font-size:1.6rem}h2{font-size:1.15rem}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:.4rem}nav{display:flex;flex-wrap:wrap;gap:1rem}input,select,button{font:inherit;min-height:32px;max-width:100%}label{display:block;margin-top:.5rem}button{margin-top:.75rem}#homeostasis-live-stream-container{max-height:200px;overflow:auto}.fields{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,14rem),1fr));gap:.5rem}.field{padding:.4rem;background:#19263a}pre{white-space:pre-wrap}" <> visibility),
    html.nav([attribute.attribute("aria-label","Homeostasis navigation")], [
      link(origin <> "/", "Cockpit"),
      link(origin <> "/homeostasis?" <> data.query(selection), "Homeostasis"),
      link(origin <> "/homeostasis/evolution?" <> data.query(selection), "Evolution"),
      link(origin <> "/homeostasis/terminal?" <> data.query(selection), "Terminal view"),
    ]),
    html.details([], [html.summary([], [html.text("Component views")]), html.nav([attribute.attribute("aria-label","Homeostasis components")], list.map(components,fn(name){link(origin <> "/homeostasis/components?" <> data.query(selection) <> "&component=" <> name,name)}))]),
    html.h1([], [html.text("Homeostasis evidence and model evolution")]),
    html.p([attribute.id("mode-label")],[html.text("Mode: " <> data.mode_name(selection.mode) <> " | Component: " <> component)]),
    html.p([attribute.id("frame-marker")],[html.text("Received frames: 0")]),
    panel("provenance", "Data origin and freshness", [
      html.p([attribute.id("homeostasis-evidence-status"), attribute.attribute("role","status")], [html.text(status.label(status.status(snapshot,now)) <> ": " <> status.source(snapshot))]),
      html.p([], [html.text("Selected mode: " <> data.mode_name(selection.mode))]),
      html.p([attribute.id("homeostasis-source-time")], [html.text("Source UTC microseconds: " <> case status.observed_at(snapshot) { Some(at) -> int.to_string(at) _ -> "UNKNOWN" })]),
      html.p([], [html.text("Control authority: NONE. Model transitions and displayed evidence do not authorize deployment.")]),
    ]),
    panel("controls", "Data mode and review controls", [
      html.form([attribute.method("get"), attribute.attribute("action", ""), attribute.id("homeostasis-mode-form")], [
        html.input([attribute.type_("hidden"),attribute.name("component"),attribute.value(component)]),
        html.label([attribute.attribute("for","homeostasis-mode")], [html.text("Data mode")]),
        html.select([attribute.id("homeostasis-mode"),attribute.name("mode")], [
          html.option([attribute.value("real"),attribute.selected(selection.mode == data.RealData)],"Real data — observed local runtime"),
          html.option([attribute.value("test"),attribute.selected(selection.mode == data.TestData)],"Test data — deterministic simulation"),
        ]),
        html.label([attribute.attribute("for","homeostasis-scenario")],[html.text("Test scenario")]),
        html.select([attribute.id("homeostasis-scenario"),attribute.name("scenario")],list.map([data.Nominal,data.Disturbance,data.Recovery,data.MissingSource],fn(s){
          html.option([attribute.value(data.scenario_name(s)),attribute.selected(s==selection.scenario)],data.scenario_name(s))
        })),
        html.label([attribute.attribute("for","homeostasis-cycle")],[html.text("Test evolution cycle (1–30)")]),
        html.input([attribute.id("homeostasis-cycle"),attribute.name("cycle"),attribute.type_("number"),attribute.min("1"),attribute.max("30"),attribute.value(int.to_string(selection.cycle))]),
        html.label([attribute.attribute("for","homeostasis-cpu")],[html.text("CPU threshold ratio (review preview)")]),
        html.input([attribute.id("homeostasis-cpu"),attribute.name("cpu_limit"),attribute.type_("range"),attribute.min("0"),attribute.max("1"),attribute.step("0.01"),attribute.value("0.85")]),
        html.output([attribute.id("homeostasis-cpu-value"),attribute.attribute("for","homeostasis-cpu")],[html.text("0.85")]),
        html.label([attribute.attribute("for","homeostasis-memory")],[html.text("Memory threshold ratio (review preview)")]),
        html.input([attribute.id("homeostasis-memory"),attribute.name("memory_limit"),attribute.type_("range"),attribute.min("0"),attribute.max("1"),attribute.step("0.01"),attribute.value("0.75")]),
        html.output([attribute.id("homeostasis-memory-value"),attribute.attribute("for","homeostasis-memory")],[html.text("0.75")]),
        html.button([attribute.type_("submit")],[html.text("Apply data mode")]),
      ]),
      html.button([attribute.id("homeostasis-review"),attribute.type_("button")],[html.text("Request equilibrium review")]),
      html.p([attribute.id("homeostasis-review-result"),attribute.attribute("role","status")],[html.text("No review requested. Real-mode execution requires an authenticated Sa-plan authority.")]),
    ]),
    field_panel("pid","PID and sampled energy",fields,["health","error","control","energy","energy_change","stable"]),
    field_panel("phase","Model phase and evolution",fields,["phase","generation","model_time"]),
    field_panel("physiology","Physiological measurements",fields,["stress","cpu_pct","memory_pct","latency_ms","error_rate_pct"]),
    field_panel("runtime","Observed BEAM runtime counters",fields,["schedulers","processes","vm_memory","run_queue","uptime"]),
    field_panel("pareto","Pareto model",fields,["candidates"]),
    field_panel("quorum","Quorum evidence",fields,["quorum"]),
    panel("stream","Observation stream",[
      html.p([attribute.id("homeostasis-stream-status"),attribute.attribute("role","status"),attribute.attribute("aria-live","polite")],[html.text("DISCONNECTED: awaiting transport")]),
      html.div([attribute.id("homeostasis-live-stream-container")],[html.table([],[
        html.caption([],[html.text("Source observations; 50-row bound")]),
        html.thead([],[html.tr([],[html.th([],[html.text("Source UTC µs")]),html.th([],[html.text("State")]),html.th([],[html.text("Source")])])]),
        html.tbody([attribute.id("homeostasis-live-stream-body")],[]),
      ])]),
    ]),
    panel("terminal","Terminal projection (plain text)",[html.pre([attribute.id("homeostasis-terminal")],[html.text(terminal.render_snapshot(snapshot,now,120,100))])]),
    panel("checklist","Verification evidence",[
      html.details([attribute.class("checklist-accordion")],[
        html.summary([],[html.text("18 requirements / UNRUN — no candidate admission receipts attached")]),
        ..list.map([
          #("Metadata, time and navigation",["01 Time and freshness","02 Tailscale navigation","03 Fractal tags","04 Knowledge links"]),
          #("Purity and storage safety",["05 Zero-Muda scope","06 Native boundaries","07 Storage interlock"]),
          #("Tests and mathematics",["08 C1-C8 coverage","09 Mathematical claims","10 Test modalities","11 Interface regression"]),
          #("Control and observability",["12 OTP runtime","13 Hermes contracts","14 ZigVM execution","15 Inference isolation","16 Telemetry correlation"]),
          #("Governance and JJ",["17 Peer verification","18 JJ candidate identity"]),
        ],fn(domain){html.div([],[html.h3([],[html.text(domain.0)]),html.ul([],list.map(domain.1,fn(label){html.li([],[html.text("UNRUN: " <> label)])}))])}),

      ]),
    ]),
    html.footer([],[html.text("Read-only evidence surface. Missing sensors remain UNKNOWN. "),link(origin <> "/api/v1/runtime/identity","Runtime identity")]),
    html.script([],stream_script()),
  ])
}
fn link(url: String,label: String) -> Element(msg) { html.a([attribute.href(url)],[html.text(label)]) }
fn field_panel(id: String,title: String,fields: List(#(String,String,String)),ids: List(String)) -> Element(msg) {
  panel(id,title,[html.div([attribute.class("fields")],fields |> list.filter(fn(f){list.contains(ids,f.0)}) |> list.map(fn(f){
    html.div([attribute.class("field")],[html.strong([],[html.text(f.1)]),html.p([attribute.id("value-" <> f.0),attribute.attribute("data-field",f.0)],[html.text(f.2)])])
  }))])
}
pub fn stream_script() -> String {
  "(function(){var badge=document.getElementById('homeostasis-stream-status');var tbody=document.getElementById('homeostasis-live-stream-body');if(!badge||!tbody)return;if(!window.EventSource){badge.textContent='UNAVAILABLE: EventSource unsupported';return;}var src=new EventSource(document.querySelector('.homeostasis-evolution-hud').dataset.streamUrl);var last=0;var seen=0;var expires=0;var stopped=false;function invalidate(reason){var info=document.getElementById('homeostasis-evidence-status');if(info)info.textContent=reason;document.querySelectorAll('[data-field]').forEach(function(c){c.textContent='UNKNOWN';});var p=document.getElementById('homeostasis-terminal');if(p)p.textContent=reason+'; no current measurements';}badge.textContent='CONNECTING: telemetry remains unknown';src.onopen=function(){badge.textContent='CONNECTED: awaiting source observation';};src.addEventListener('homeostasis_status',function(e){try{if(e.data.length>16384)throw Error('oversize');var d=JSON.parse(e.data);if(d.schema_version!==1||['unavailable','simulated','observed','stale'].indexOf(d.status)<0||typeof d.source!=='string')throw Error('schema');var expected=Array.from(document.querySelectorAll('[data-field]')).map(function(c){return c.dataset.field;});if(d.control_authority!=='none'||!Array.isArray(d.fields)||d.fields.length!==expected.length||new Set(d.fields.map(function(f){return f&&f.id;})).size!==expected.length||!d.fields.every(function(f){return f&&expected.indexOf(f.id)>=0&&typeof f.label==='string'&&typeof f.value==='string'&&f.value.length<=1000;}))throw Error('field schema');var at=d.observed_at_us;if(d.status==='observed'&&(!Number.isSafeInteger(at)||at<=0||!Number.isSafeInteger(d.age_us)||!Number.isSafeInteger(d.ttl_us)||d.ttl_us<=0||d.age_us<0||d.age_us>=d.ttl_us||at<=seen))throw Error('stale or out-of-order');if(d.status==='observed')seen=at;last=performance.now();var marker=document.getElementById('frame-marker');if(marker){marker.dataset.count=String(Number(marker.dataset.count||0)+1);marker.textContent='Received frames: '+marker.dataset.count;}if(Array.isArray(d.fields)){d.fields.forEach(function(f){if(!f||typeof f.id!=='string'||typeof f.value!=='string')return;var cell=document.getElementById('value-'+f.id);if(cell){cell.textContent=f.value.slice(0,1000);cell.dataset.updates=String(Number(cell.dataset.updates||0)+1);}});}var pre=document.getElementById('homeostasis-terminal');if(pre&&Array.isArray(d.fields)){pre.textContent=('HOMEOSTASIS | '+d.status.toUpperCase()+'\\nSource: '+d.source+'\\n'+d.fields.map(function(f){return f.label+': '+f.value;}).join('\\n')+'\\nControl authority: NONE').split('').map(function(c){var n=c.charCodeAt(0);return n===10||(n>=32&&n<=126)?c:'?';}).join('');}var evidence=document.getElementById('homeostasis-evidence-status');if(evidence)evidence.textContent=d.status.toUpperCase()+': '+d.source;var time=document.getElementById('homeostasis-source-time');if(time)time.textContent='Source UTC microseconds: '+(at===null?'UNKNOWN':at);expires=d.status==='observed'?last+(d.ttl_us-d.age_us)/1000:0;badge.textContent='CONNECTED / '+d.status.toUpperCase()+' (no control authority)';var tr=document.createElement('tr');[at===null?'UNKNOWN':String(at),d.status.toUpperCase(),d.source].forEach(function(value){var td=document.createElement('td');td.textContent=value.slice(0,1000);tr.appendChild(td);});tbody.insertBefore(tr,tbody.firstChild);while(tbody.children.length>50)tbody.removeChild(tbody.lastChild);}catch(err){badge.textContent='UNAVAILABLE: rejected invalid or out-of-order frame';invalidate(badge.textContent);}});src.onerror=function(){badge.textContent='DISCONNECTED: source evidence unavailable; reconnecting';invalidate(badge.textContent);};var timer=setInterval(function(){if(expires>0&&performance.now()>=expires){badge.textContent='STALE: source observation expired';invalidate(badge.textContent);expires=0;}else if(last>0&&performance.now()-last>5000){badge.textContent='STALE: no stream update for 5 seconds';invalidate(badge.textContent);}},1000);function stop(){if(stopped)return;stopped=true;clearInterval(timer);src.close();badge.textContent='DISCONNECTED: stream closed';}window.addEventListener('pagehide',stop,{once:true});['cpu','memory'].forEach(function(name){var slider=document.getElementById('homeostasis-'+name);if(slider)slider.oninput=function(){document.getElementById('homeostasis-'+name+'-value').textContent=slider.value;};});var review=document.getElementById('homeostasis-review');if(review)review.onclick=function(){var output=document.getElementById('homeostasis-review-result');output.textContent='Review pending';fetch('/api/v1/homeostasis/review?'+new URLSearchParams(new FormData(document.getElementById('homeostasis-mode-form')))).then(function(r){return r.json();}).then(function(d){output.textContent=d.message;}).catch(function(){output.textContent='Review unavailable';});};})();"
}
