// Bounded development builder, invoked through the Gleam development harness.
// Uses already-realized repository toolchains and compiled dependency metadata.
// No dependency resolution, downloads, canonical source edits, or deployment.
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const sourceRoot=path.resolve(__dirname,'../../..');
const canonical='/home/an/NAS-setup/uos';
const out=process.argv[2];
if(!out||!path.isAbsolute(out)||!out.startsWith(canonical+'/var/recovery-runtime/')||fs.existsSync(out))throw Error('new absolute recovery output required');
fs.mkdirSync(out,{recursive:true});
const modules=[
 'cepaf_gleam/telegram/mini_alert_io.gleam','cepaf_gleam/telegram/mini_alert_owner.gleam','cepaf_gleam/telegram/mini_alert_state.gleam','cepaf_gleam/telegram/mini_alerts.gleam','cepaf_gleam/telegram/mini_alerts_view.gleam',
 'cepaf_gleam/c3i/evidence.gleam','cepaf_gleam/c3i/nif.gleam',
 'cepaf_gleam/config/mesh_source.gleam','cepaf_gleam/config/mesh_config.gleam','cepaf_gleam/telegram/mini_config.gleam',
 'cepaf_gleam/telegram/auth.gleam','cepaf_gleam/telegram/types.gleam','cepaf_gleam/telegram/theme.gleam',
 'cepaf_gleam/telegram/mini_api.gleam','cepaf_gleam/telegram/mini_runtime.gleam','cepaf_gleam/telegram/mini_view.gleam',
 'cepaf_gleam/ui/wisp/mini_app_routes.gleam','cepaf_gleam/ui/wisp/router.gleam',
 'cepaf_gleam/harness/observer_policy.gleam','cepaf_gleam/web/mini_http.gleam','cepaf_gleam/web/server.gleam',
 'mini_app_clock_ffi.erl','sa_plan_observer_ffi.erl',
 "cepaf_gleam/harness/telegram_fmea_reader.gleam",
 "cepaf_gleam/harness/telegram_fmea_report.gleam",
 "cepaf_gleam/harness/telegram_verification_reader.gleam",
 "cepaf_gleam/harness/telegram_verification_report.gleam",
 "cepaf_gleam/harness/telegram_evidence_status.gleam",
 "cepaf_gleam/harness/telegram_knowledge_report.gleam",
 "telegram_coordination_binding.erl",
 "telegram_knowledge_files.erl",
 "telegram_risk_files.erl",
 "telegram_ecology_clock.erl",
 "cepaf_gleam/telegram/mini_evidence.gleam","cepaf_gleam/telegram/mini_podman.gleam"];
modules.push(...["cepaf_gleam/harness/telegram_store.gleam","cepaf_gleam/harness/telegram_store_transport.gleam","cepaf_gleam/harness/telegram_store_codec.gleam","cepaf_gleam/harness/telegram_ingress_guard.gleam","cepaf_gleam/harness/files.gleam","cepaf_gleam/harness/telegram_task_command.gleam","cepaf_gleam/harness/telegram_commands.gleam","cepaf_gleam/harness/telegram_delivery_ledger.gleam","cepaf_gleam/harness/telegram_lifecycle_adapter.gleam","cepaf_gleam/harness/telegram_conversation.gleam","telegram_store_transport_ffi.erl","telegram_store_codec_ffi.erl","telegram_lifecycle_ffi.erl","cepaf_gleam/telegram/mini_history.gleam"]);
modules.push('cepaf_gleam/telegram/mini_health_view.gleam','cepaf_gleam/telegram/mini_health.gleam','cepaf_gleam/telegram/mini_chat_view.gleam','cepaf_gleam/telegram/mini_memory_view.gleam','cepaf_gleam/telegram/mini_memory.gleam','cepaf_gleam/telegram/mini_control_view.gleam','cepaf_gleam/telegram/mini_control.gleam','mini_control_ffi.erl','cepaf_gleam/harness/development.gleam','cepaf_gleam/harness/clock.gleam','cepaf_gleam/planning/sa_plan_bridge.gleam','cepaf_gleam/telegram/mini_telemetry.gleam','cepaf_gleam/telegram/mini_telemetry_state.gleam','mini_telemetry_ffi.erl','cepaf_gleam/telegram/mini_dashboard.gleam','cepaf_gleam/ha/beam_metrics.gleam','beam_metrics_ffi.erl','cepaf_gleam/harness/telegram_coordination_reader.gleam','cepaf_gleam/harness/telegram_coordination_report.gleam','telegram_status_probe.erl','cepaf_gleam/telegram/mini_zenoh.gleam','cepaf_gleam/zenoh/rest.gleam','zenoh_rest_ffi.erl');
// Compile the shared polling implementations from this candidate, never older fallback metadata.
for(const name of fs.readdirSync(sourceRoot+'/apps/cepaf_gleam/src/cepaf_gleam/harness').filter(x=>x.startsWith('telegram_')&&x.endsWith('.gleam'))) { const m='cepaf_gleam/harness/'+name; if(!modules.includes(m))modules.push(m); }
for(const name of fs.readdirSync(sourceRoot+'/apps/cepaf_gleam/src').filter(x=>x.startsWith('telegram_')&&x.endsWith('.erl')))if(!modules.includes(name))modules.push(name);
const tests=['mini_alert_owner_test.gleam','mini_alert_state_test.gleam','mini_alerts_test.gleam','mini_config_test.gleam','mini_health_test.gleam','mini_memory_test.gleam','mini_control_test_ffi.erl','mini_control_test.gleam','mini_telemetry_test.gleam','mini_telemetry_test_ffi.erl','mini_dashboard_test.gleam','zenoh_rest_test.gleam','mini_zenoh_test.gleam','mini_history_test.gleam','mini_podman_test.gleam','mini_evidence_test.gleam','mini_boundary_test.gleam','mini_test_vectors.gleam','mini_boundary_test_ffi.erl'];
const pollingTests=['telegram_zenoh_report_test','telegram_chunk_test','telegram_budget_report_test','telegram_ha_report_test','telegram_bridge_test','telegram_action_service_test','telegram_commands_test','telegram_delivery_ledger_test','telegram_ingress_guard_test','telegram_task_command_test','telegram_conversation_test','telegram_memory_command_test','telegram_tool_command_test','telegram_cancellation_test','telegram_cancellation_record_test','telegram_action_intent_test','telegram_action_profile_test','telegram_approval_test'];
for(const name of pollingTests)tests.push(name+'.gleam');
tests.push('telegram_approval_test_crypto.erl','telegram_conversation_store_test.gleam');
tests.push('telegram_conversation_model_test.gleam','telegram_service_e2e_test.gleam','telegram_conversation_test_io.gleam');
// Include candidate test helpers transitively; child fixtures bind the actual loaded candidate beams.
for(let i=0;i<tests.length;i++){const body=fs.readFileSync(sourceRoot+'/apps/cepaf_gleam/test/'+tests[i],'utf8');for(const match of body.matchAll(/^import ([a-z_]+)(?:\s|$)/gm)){const name=match[1]+'.gleam';if(fs.existsSync(sourceRoot+'/apps/cepaf_gleam/test/'+name)&&!tests.includes(name))tests.push(name);}}
for(const name of fs.readdirSync(sourceRoot+'/apps/cepaf_gleam/test').filter(x=>x.startsWith('telegram_')&&x.endsWith('.erl')))if(!tests.includes(name))tests.push(name);
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const sources=[];
function copy(relative,to) {const from=path.join(sourceRoot,relative);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(from,to);sources.push({path:relative,sha256:sha(from)});}
for(const m of modules)copy('apps/cepaf_gleam/src/'+m,out+'/package/src/'+m);
copy('apps/uos_swarm/src/uos_swarm/session_store.gleam',out+'/package/src/uos_swarm/session_store.gleam');
copy('apps/uos_swarm/src/uos_openrouter_ffi.erl',out+'/package/src/uos_openrouter_ffi.erl');
for(const m of tests)copy('apps/cepaf_gleam/test/'+m,out+'/package/src/'+m);
for(const m of ['mini_memory_native.gleam','mini_history_fixture.gleam','mini_http_fixture.gleam','mini_browser.ml','mini_health_snapshot.ml','config-http-tests.js','alerts-http-tests.js','ack-http-tests.js','budget-native-tests.js','health-native-tests.js','health-safety-tests.js','health-http-tests.js','http-tests.js','podman-state-tests.js','history-state-tests.js','zenoh-http-tests.js','zenoh-state-tests.js','dashboard-http-tests.js','dashboard-state-tests.js','telemetry-http-tests.js','control-http-tests.js','control-recovery-tests.js','memory-http-tests.js','memory-recovery-tests.js','chat-http-tests.js'])copy('tools/validation/telegram_mini_candidate/'+m,out+'/'+(m.endsWith('.gleam')?'package/src/':'')+m);
if(sha(out+'/package/src/cepaf_gleam/telegram/auth.gleam')!=='1514b26366e1665c831fa8f8600ee82d778327e5365098c5580ebce218521c45')throw Error('accepted auth changed');
let toml=fs.readFileSync(sourceRoot+'/apps/cepaf_gleam/gleam.toml','utf8')
 .replace('name = "cepaf_gleam"','name = "telegram_mini_candidate"')
 .replace('uos_swarm = { path = "../uos_swarm" }','uos_swarm = { path = "'+canonical+'/apps/uos_swarm" }\ncepaf_gleam = { path = "'+canonical+'/apps/cepaf_gleam" }')
 .replace('[dev-dependencies]','');
fs.writeFileSync(out+'/package/gleam.toml',toml);
copy('tools/ecology_budget.ml',out+'/ecology_budget_source.ml');
const budgetSource=fs.readFileSync(out+'/ecology_budget_source.ml','utf8');
const preamble='#!/usr/bin/env -S opam exec -- ocaml\n#use "topfind";;\n#require "unix,sqlite3,yojson,mtime.clock";;\n';
if(!budgetSource.startsWith(preamble))throw Error('budget preamble changed');
fs.writeFileSync(out+'/ecology_budget.ml',budgetSource.slice(preamble.length));
const calls=[];
function run(exe,args,cwd=canonical) {
 const r=cp.spawnSync(exe,args,{cwd,env:{...process.env,ERL_FLAGS:'+S 2:2 +A 2',ERL_CRASH_DUMP:'/dev/null'},encoding:'utf8',timeout:30000,maxBuffer:1048576});
 calls.push({exe,args,exit:r.status,error:r.error?.message||null,stdout:r.stdout,stderr:r.stderr});
 fs.writeFileSync(out+'/build-results.json',JSON.stringify({observed_at:new Date().toISOString(),sources,calls},null,2)+'\n');
 if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);
 if(r.error||r.status!==0)throw Error('bounded candidate build failed');
}
run(canonical+'/toolchains/opam-ocaml/bin/ocamlfind',['ocamlopt','-linkpkg','-package','unix,sqlite3,yojson,mtime.clock','ecology_budget.ml','-o','ecology_budget.exe'],out);
run(canonical+'/toolchains/gleam-1.16.0/bin/gleam',['compile-package','--target','erlang','--package',out+'/package','--out',out+'/build','--lib',canonical+'/apps/cepaf_gleam/build/dev/erlang']);
run(canonical+'/toolchains/opam-ocaml/bin/ocamlfind',['ocamlopt','-linkpkg','-package','playwright,eio_main,cryptokit,yojson','mini_browser.ml','-o','mini_browser.exe'],out);
run(canonical+'/toolchains/opam-ocaml/bin/ocamlfind',['ocamlopt','-linkpkg','-package','yojson,unix','mini_health_snapshot.ml','-o','mini_health_snapshot.exe'],out);
const erlCode='code:add_paths(filelib:wildcard("'+canonical+'/apps/cepaf_gleam/build/dev/erlang/*/ebin")),code:add_patha("'+out+'/build/ebin"),case eunit:test([mini_alert_owner_test,mini_alert_state_test,mini_alerts_test,mini_config_test,mini_health_test,mini_memory_test,mini_control_test,mini_boundary_test,mini_evidence_test,mini_podman_test,mini_history_test,mini_zenoh_test,zenoh_rest_test,mini_dashboard_test,mini_telemetry_test,'+pollingTests.join(',')+'],[verbose]) of ok -> halt(0); _ -> halt(1) end.';
run(canonical+'/toolchains/nix-profile/bin/erl',['+S','2:2','+A','2','-noshell','-eval',erlCode]);
run('/usr/bin/node',[out+'/budget-native-tests.js',out]);
console.log('CANDIDATE_BUILD_AND_UNIT_TESTS_PASS '+out);
