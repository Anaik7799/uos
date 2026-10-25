const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const mutation=process.argv[3]||'';if(!['','--baseline','--mutant-empty','--mutant-scale'].includes(mutation))throw Error('unknown test mode');
const root='/home/an/NAS-setup/uos',ws=path.resolve(__dirname,'../..'),out=process.argv[2],baseline=process.argv[3]==='--baseline';
if(!out||!path.isAbsolute(out)||!out.startsWith(root+'/var/recovery-runtime/')||fs.existsSync(out))throw Error('new private output required');
fs.mkdirSync(out,{recursive:true});const sources=[],calls=[];
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const src=['cepaf_gleam/semantics/sheaf_cohomology.gleam','cepaf_gleam/ha/lyapunov_proof.gleam'];
const tests=baseline?['numeric_legacy_boundary_test.gleam']:['numeric_legacy_boundary_test.gleam','numeric_contract_test.gleam','sheaf_cohomology_test.gleam','ha_lyapunov_proof_test.gleam'];
for(const rel of src.map(x=>'apps/cepaf_gleam/src/'+x).concat(tests.map(x=>'apps/cepaf_gleam/test/'+x))){
 const isProduct=rel.includes('/src/'),from=(baseline&&isProduct?root:ws)+'/'+rel,to=out+'/package/src/'+(isProduct?rel.split('/src/')[1]:path.basename(rel));
 fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(from,to);if(rel.endsWith('/sheaf_cohomology.gleam')&&mutation.startsWith('--mutant')){let bytes=fs.readFileSync(to,'utf8');if(mutation==='--mutant-empty')bytes=bytes.replace('charts_count >= 1','charts_count >= 0');if(mutation==='--mutant-scale')bytes=bytes.replace('int.to_float(to + 1) /. int.to_float(from + 1)','int.to_float(from + 1) /. int.to_float(to + 1)');fs.writeFileSync(to,bytes);}sources.push({path:from,sha256:sha(from),compiled_sha256:sha(to)});
}
let toml=fs.readFileSync(root+'/apps/cepaf_gleam/gleam.toml','utf8').replace('name = "cepaf_gleam"','name = "telegram_numeric_candidate"').replace('uos_swarm = { path = "../uos_swarm" }','uos_swarm = { path = "'+root+'/apps/uos_swarm" }').replace('[dev-dependencies]','');
fs.writeFileSync(out+'/package/gleam.toml',toml);
function run(exe,args){const r=cp.spawnSync(exe,args,{cwd:root,env:{...process.env,ERL_FLAGS:'+S 2:2 +A 2',ERL_CRASH_DUMP:'/dev/null'},encoding:'utf8',timeout:15000,maxBuffer:1048576});calls.push({exe,args,status:r.status,error:r.error?.message||null,stdout:r.stdout,stderr:r.stderr});fs.writeFileSync(out+'/results.json',JSON.stringify({observed_at:new Date().toISOString(),baseline,mutation,sources,calls},null,2)+'\n');process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');return !r.error&&r.status===0;}
if(!run(root+'/toolchains/gleam-1.16.0/bin/gleam',['compile-package','--target','erlang','--package',out+'/package','--out',out+'/build','--lib',root+'/apps/cepaf_gleam/build/dev/erlang']))process.exit(1);
const names=tests.map(x=>x.slice(0,-6)).join(',');
const expr='code:add_paths(filelib:wildcard("'+root+'/apps/cepaf_gleam/build/dev/erlang/*/ebin")),code:add_patha("'+out+'/build/ebin"),case eunit:test(['+names+'],[verbose]) of ok->halt(0);_->halt(1) end.';
if(!run(root+'/toolchains/nix-profile/bin/erl',['+S','2:2','+A','2','-noshell','-eval',expr]))process.exit(1);
