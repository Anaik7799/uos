const fs=require('fs'),c=require('crypto'),assert=require('assert'),cp=require('child_process');
const base='http://nas-1.tail55d152.ts.net:49134',out=process.argv[2],checks=[];
function sign(id=42,at=Math.floor(Date.now()/1000)){
 const p={auth_date:String(at),user:JSON.stringify({id,first_name:'CONTROL_FIXTURE'})},k=c.createHmac('sha256','WebAppData').update('333444:synthetic-mini-test-token').digest();
 p.hash=c.createHmac('sha256',k).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();
}
async function post(path,body){const r=await fetch(base+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(55000)});return {code:r.status,body:await r.json()};}
async function observe(){const r=await post('/mini-app/api/data',{init_data:sign(),path:'/mini-app/telemetry'});assert.equal(r.body.status,'observed');return r.body.fields['VM logger level'];}
function intent(expected,target,id=42){return {init_data:sign(id),path:'/mini-app/telemetry',action:'set_vm_logger_level',request_id:c.randomBytes(16).toString('hex'),expected_level:expected,target_level:target};}
function row(id){assert(/^mini-control\/[a-f0-9]{64}$/.test(id));const r=cp.spawnSync('/usr/bin/sqlite3',['-readonly','-json','/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3',"SELECT * FROM sa_plan_job WHERE id='"+id+"';"],{encoding:'utf8'});assert.equal(r.status,0);return JSON.parse(r.stdout)[0];}
async function main(){
 const prior=await observe(),target=prior==='debug'?'info':'debug',a=intent(prior,target);
 let r=await post('/mini-app/api/action',a);console.log('initial',r);assert.equal(r.code,200);assert.equal(r.body.status,'applied');assert.equal(await observe(),target);
 const job=row(r.body.job_id);assert.equal(job.state,'completed');assert.equal(job.attempt,1);checks.push({name:'actual_vm_change_and_canonical_receipt',job:job.id});
 r=await post('/mini-app/api/action',a);assert.equal(r.body.status,'terminal_receipt');assert.equal(r.body.effects_this_request,0);assert.equal(row(job.id).attempt,1);assert.equal(await observe(),target);checks.push({name:'same_nonce_no_replay'});
 r=await post('/mini-app/api/action',{...a,target_level:'warning'});assert.equal(r.code,409);assert.equal(r.body.status,'request_id_conflict');assert.equal(await observe(),target);checks.push({name:'changed_payload_nonce_conflict'});
 r=await post('/mini-app/api/action',intent(target,'notice',43));assert.equal(r.code,401);assert.equal(r.body.effects_this_request,0);assert.equal(await observe(),target);checks.push({name:'read_grant_not_control_grant'});
 r=await post('/mini-app/api/action',intent(prior,'warning'));assert.equal(r.code,409);assert.equal(r.body.status,'level_mismatch');assert.equal(await observe(),target);checks.push({name:'expected_level_conflict'});
 r=await post('/mini-app/api/action',{...intent(target,'warning'),init_data:sign(42,Math.floor(Date.now()/1000)-301)});assert.equal(r.code,401);assert.equal(await observe(),target);checks.push({name:'stale_auth_no_effect'});
 for(const patch of [{request_id:'x'},{action:'restart_host'},{target_level:'invented'},{extra:true},{path:'/mini-app/config'}]){
  r=await post('/mini-app/api/action',{...intent(target,'warning'),...patch});assert(r.code>=400);assert.equal(r.body.effects_this_request,0);
 }checks.push({name:'closed_request_schema_and_action_enum'});
 const a1=intent(target,'info'),a2=intent(target,'notice');
 const race=await Promise.all([post('/mini-app/api/action',a1),post('/mini-app/api/action',a2)]);
 assert.deepEqual(race.map(x=>x.body.status).sort(),['applied','level_mismatch']);checks.push({name:'serialized_same_prior_race'});
 const current=await observe();
 if(current!==prior){r=await post('/mini-app/api/action',intent(current,prior));assert.equal(r.body.status,'applied');}
 assert.equal(await observe(),prior);checks.push({name:'explicit_restore_prior_level'});
 fs.writeFileSync(out+'/control-http.json',JSON.stringify({at:new Date().toISOString(),status:'PASS',checks,seed_job:job.id},null,2));
 console.log(JSON.stringify({status:'PASS',checks:checks.length,seed_job:job.id}));
}
main().catch(e=>{fs.writeFileSync(out+'/control-http-failure.json',JSON.stringify({error:String(e),checks},null,2));console.error(e);process.exitCode=1;});