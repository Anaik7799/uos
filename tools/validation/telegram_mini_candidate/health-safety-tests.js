const fs=require('fs'),cp=require('child_process'),assert=require('assert'),path=require('path');
const root='/home/an/NAS-setup/uos',out=process.argv[2],exe=out+'/mini_health_snapshot.exe';
const helper='let () = let fd=Unix.openfile ("/run/user/"^string_of_int(Unix.getuid())^"/uos-mini-health.lock") [Unix.O_RDWR] 0 in Unix.lockf fd Unix.F_TLOCK 0; print_endline "LOCKED"; flush stdout; Unix.sleep 5';
fs.writeFileSync(out+'/lock_fixture.ml',helper);
cp.execFileSync(root+'/toolchains/opam-ocaml/bin/ocamlfind',['ocamlopt','-linkpkg','-package','unix','lock_fixture.ml','-o','lock_fixture.exe'],{cwd:out,timeout:10000});
(async()=>{
 const child=cp.spawn(out+'/lock_fixture.exe',[],{stdio:['ignore','pipe','pipe']});
 const exited=new Promise(resolve=>child.on('exit',resolve));
 try{
  await new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(Error('lock fixture timeout')),2000);child.stdout.once('data',d=>{clearTimeout(t);String(d).includes('LOCKED')?resolve():reject(Error('lock absent'));});child.once('error',reject);});
  const blocked=cp.spawnSync(exe,[],{encoding:'utf8',timeout:1000});
  assert.notEqual(blocked.status,0);assert(blocked.stderr.includes('collector_busy'));assert.equal(blocked.stdout,'');
  const fixture=fs.mkdtempSync('/tmp/uos-mini-health-test-lock-');fs.chmodSync(fixture,0o700);fs.mkdirSync(fixture+'/class/hwmon',{recursive:true});
  const isolated=cp.spawnSync(exe,['--fixture',fixture],{encoding:'utf8',timeout:1000});assert.equal(isolated.status,0,isolated.stderr);
 }finally{child.kill('SIGTERM');await exited;}
 const recovered=cp.spawnSync(exe,[],{encoding:'utf8',timeout:3000});assert.equal(recovered.status,0,recovered.stderr);assert(JSON.parse(recovered.stdout).devices.length>0);
 const bad=cp.spawnSync(root+'/tools/validation/obs_guardian.exe',['--exe',exe,'--sha256','0'.repeat(64),'--deadline-ms','2500','--max-bytes','32768','--'],{encoding:'utf8',timeout:4000,input:''});
 assert(!bad.stdout.includes('uos.mini.device-observation.v1'));assert(bad.status!==0||bad.stdout.includes('digest'));
 fs.writeFileSync(out+'/health-safety-tests.json',JSON.stringify({status:'PASS',at:new Date().toISOString(),checks:['single_collector_busy_refused','fixture_lock_independent_of_live','collector_capacity_recovers_after_exit','wrong_digest_no_observation'],d_state_injection:'UNRUN'},null,2));console.log('PASS health collector safety');
})().catch(e=>{console.error(e);process.exitCode=1});