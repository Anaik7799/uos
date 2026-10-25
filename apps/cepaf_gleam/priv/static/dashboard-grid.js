// UOS read-only recovery projection. No live health or admission authority.
(function () {
"use strict";
var data=null, view="grid", busy=false;
var demo=document.querySelector(".test-btn");
if(demo){demo.disabled=true;demo.removeAttribute("onclick");demo.textContent="DEMO DISABLED";demo.title="Simulated status changes are disabled in the recovery observation view.";}
function node(id){return document.getElementById(id);}
function set(id,text){var n=node(id);if(n)n.textContent=text;}
function el(tag,text){var n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
function render(){
 var host=node("dash-dynamic-content");if(!host)return;host.replaceChildren();
 var scope=el("p","Observed snapshot only. Live agent health, inference, transport and global admission are UNVERIFIED.");
 scope.id="dash-snapshot-scope";host.appendChild(scope);
 if(!data){host.appendChild(el("p","Snapshot unavailable. No zero-count or healthy fallback is inferred."));return;}
 var age=Date.now()-Date.parse(data.updated_at);
 set("dash-task-summary",data.tasks.length+" recorded tasks; observed "+data.updated_at+(age<0||age>300000?" (STALE or clock mismatch)":" (snapshot age under 5 minutes)"));
 if(view==="supervisors"){host.appendChild(el("p","Supervisor and agent runtime identities: UNOBSERVED. Declarations do not prove active agents."));}
 else if(view==="fractal"){host.appendChild(el("p","EV ceiling93; EV94..109 NOT_ADMITTED. No new EV identifier or execution authority."));}
 else if(view==="analytics"){
  host.appendChild(el("p","Recorded evidence: "+String(data.evidence.summary||"No summary attached.")));
  host.appendChild(el("p","Task completion counts are not test coverage, system health or admission."));
 }else{
  var input=node("dash-search-input"),query=input?input.value.toLowerCase():"";
  var table=el("table");table.id="dash-observed-tasks";table.style.width="100%";
  var head=el("tr");["Task","Recorded state","Title"].forEach(function(x){head.appendChild(el("th",x));});table.appendChild(head);
  data.tasks.filter(function(t){return[t.id,t.title,t.state].join(" ").toLowerCase().indexOf(query)>=0;}).forEach(function(t){
   var row=el("tr");[t.id,t.state,t.title].forEach(function(x){row.appendChild(el("td",x));});table.appendChild(row);
  });host.appendChild(table);
 }
}
async function refresh(){
 if(busy)return;busy=true;var ctrl=new AbortController(),timer=setTimeout(function(){ctrl.abort();},3000);
 try{
  var r=await fetch("/static/20260930-0633-restoration-state.json",{method:"GET",cache:"no-store",redirect:"error",credentials:"same-origin",signal:ctrl.signal});
  if(!r.ok)throw Error("snapshot HTTP "+r.status);
  var raw=await r.text();if(new TextEncoder().encode(raw).length>262144)throw Error("snapshot bound");
  var next=JSON.parse(raw);
  if(!next||!Array.isArray(next.tasks)||next.tasks.length>1000||!Number.isFinite(Date.parse(next.updated_at))||!next.evidence||
   !next.tasks.every(function(t){return t&&typeof t.id==="string"&&typeof t.state==="string"&&typeof t.title==="string";}))throw Error("invalid snapshot schema");
  data=next;set("dash-change-log","Snapshot received "+new Date().toISOString()+". Source observation time is shown above.");
 }catch(e){data=null;set("dash-task-summary","SNAPSHOT UNAVAILABLE");set("dash-change-log",String(e));}
 finally{clearTimeout(timer);busy=false;render();}
}
function init(){
 set("dash-ws-status","Read-only snapshot; no WebSocket or legacy NIF polling.");
 set("dash-ai-chat","Inference requires an authenticated, task-bound interface.");
 var labels={grid:"Tasks",supervisors:"Agent evidence",fractal:"Provenance",analytics:"Evidence"};
 document.querySelectorAll("#dash-view-toggle [data-view]").forEach(function(b){var v=b.getAttribute("data-view");b.textContent=labels[v]||v;b.onclick=function(){view=v;render();};});
 var input=node("dash-search-input");if(input){input.placeholder="Filter recorded tasks locally";input.oninput=render;}
 render();refresh();setInterval(refresh,30000);
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init);else init();
})();
