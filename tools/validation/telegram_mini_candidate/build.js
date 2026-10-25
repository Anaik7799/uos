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
const tests=['mini_history_test.gleam','mini_podman_test.gleam','mini_evidence_test.gleam','mini_boundary_test.gleam','mini_test_vectors.gleam','mini_boundary_test_ffi.erl'];
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const sources=[];
function copy(relative,to) {const from=path.join(sourceRoot,relative);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(from,to);sources.push({path:relative,sha256:sha(from)});}
for(const m of modules)copy('apps/cepaf_gleam/src/'+m,out+'/package/src/'+m);
for(const m of tests)copy('apps/cepaf_gleam/test/'+m,out+'/package/src/'+m);
for(const m of ['mini_history_fixture.gleam','mini_http_fixture.gleam','mini_browser.ml','http-tests.js','podman-state-tests.js','history-state-tests.js'])copy('tools/validation/telegram_mini_candidate/'+m,out+'/'+(m.endsWith('.gleam')?'package/src/':'')+m);
if(sha(out+'/package/src/cepaf_gleam/telegram/auth.gleam')!=='1514b26366e1665c831fa8f8600ee82d778327e5365098c5580ebce218521c45')throw Error('accepted auth changed');
let toml=fs.readFileSync(sourceRoot+'/apps/cepaf_gleam/gleam.toml','utf8')
 .replace('name = "cepaf_gleam"','name = "telegram_mini_candidate"')
 .replace('uos_swarm = { path = "../uos_swarm" }','uos_swarm = { path = "'+canonical+'/apps/uos_swarm" }\ncepaf_gleam = { path = "'+canonical+'/apps/cepaf_gleam" }')
 .replace('[dev-dependencies]','');
fs.writeFileSync(out+'/package/gleam.toml',toml);
const calls=[];
function run(exe,args,cwd=canonical) {
 const r=cp.spawnSync(exe,args,{cwd,env:{...process.env,ERL_FLAGS:'+S 2:2 +A 2',ERL_CRASH_DUMP:'/dev/null'},encoding:'utf8',timeout:30000,maxBuffer:1048576});
 calls.push({exe,args,exit:r.status,error:r.error?.message||null,stdout:r.stdout,stderr:r.stderr});
 fs.writeFileSync(out+'/build-results.json',JSON.stringify({observed_at:new Date().toISOString(),sources,calls},null,2)+'\n');
 if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);
 if(r.error||r.status!==0)throw Error('bounded candidate build failed');
}
run(canonical+'/toolchains/gleam-1.16.0/bin/gleam',['compile-package','--target','erlang','--package',out+'/package','--out',out+'/build','--lib',canonical+'/apps/cepaf_gleam/build/dev/erlang']);
run(canonical+'/toolchains/opam-ocaml/bin/ocamlfind',['ocamlopt','-linkpkg','-package','playwright,eio_main,cryptokit,yojson','mini_browser.ml','-o','mini_browser.exe'],out);
const erlCode='code:add_paths(filelib:wildcard("'+canonical+'/apps/cepaf_gleam/build/dev/erlang/*/ebin")),code:add_patha("'+out+'/build/ebin"),case eunit:test([mini_boundary_test,mini_evidence_test,mini_podman_test,mini_history_test],[verbose]) of ok -> halt(0); _ -> halt(1) end.';
run(canonical+'/toolchains/nix-profile/bin/erl',['+S','2:2','+A','2','-noshell','-eval',erlCode]);
console.log('CANDIDATE_BUILD_AND_UNIT_TESTS_PASS '+out);
