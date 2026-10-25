const fs=require('fs'),c=require('crypto'),assert=require('assert'),cp=require('child_process');
const base='http://nas-1.tail55d152.ts.net:49134',out=process.argv[2],checks=[];
function sign(id=42,chat,at=Math.floor(Date.now()/1000)){
 const p={auth_date:String(at),user:JSON.stringify({id,first_name:'MEMORY_FIXTURE'})};if(chat!==undefined)p.chat=JSON.stringify({id:chat});
 const k=c.createHmac('sha256','WebAppData').update('333444:synthetic-mini-test-token').digest();
 p.hash=c.createHmac('sha256',k).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();
}
async function post(path,body){const r=await fetch(base+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(55000)});return {code:r.status,body:await r.json()};}
async function observe(id=42,chat){const r=await post('/mini-app/api/data',{init_data:sign(id,chat),path:'/mini-app/chat'});assert.equal(r.body.status,'observed');return r.body.fields;}
function intent(f,id=42,chat,action='clear_history'){return {init_data:sign(id,chat),path:'/mini-app/chat',action,request_id:c.randomBytes(16).toString('hex'),expected_version:Number(f['Context version']),expected_sha256:f['Context SHA256']};}
function job(id){assert(/^mini-control\/[a-f0-9]{64}$/.test(id));const r=cp.spawnSync('/usr/bin/sqlite3',['-readonly','-json','/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3',"SELECT * FROM sa_plan_job WHERE id='"+id+"';"],{encoding:'utf8'});assert.equal(r.status,0);return JSON.parse(r.stdout)[0];}
async function main(){
 const f=await observe(),other=await observe(43),a=intent(f);
 let r=await post('/mini-app/api/action',a);assert.equal(r.body.status,'applied');assert.equal(r.body.receipt.status,'history_cleared');
 const id=r.body.job_id;assert.equal(job(id).state,'completed');assert.equal(job(id).attempt,1);
 let after=await observe();assert.equal(after['Stored exchanges'],'0');assert.equal(Number(after['Context version']),Number(f['Context version'])+1);
 const otherAfter=await observe(43);for(const k of Object.keys(other).filter(x=>x!=='Generation'))assert.deepEqual(otherAfter[k],other[k]);checks.push('clear_readback_canonical_receipt_and_other_user_isolation');
 r=await post('/mini-app/api/action',a);assert.equal(r.body.status,'terminal_receipt');assert.equal(r.body.effects_this_request,0);assert.equal((await observe())['Context version'],after['Context version']);checks.push('duplicate_no_replay');
 r=await post('/mini-app/api/action',{...a,expected_version:99});assert.equal(r.code,409);checks.push('nonce_payload_conflict');
 r=await post('/mini-app/api/action',intent(f));assert.equal(r.code,409);assert.equal(r.body.effects_this_request,0);checks.push('stale_expectation_no_effect');
 r=await post('/mini-app/api/action',intent(other,43));assert.equal(r.code,401);checks.push('read_grant_not_control_grant');
 r=await post('/mini-app/api/action',{...intent(after),init_data:sign(42,undefined,Math.floor(Date.now()/1000)-301)});assert.equal(r.code,401);checks.push('expired_auth_no_effect');
 r=await post('/mini-app/api/action',intent(after,42,-100124));assert.equal(r.code,409);assert.equal(r.body.effects_this_request,0);checks.push('ungranted_chat_no_effect');
 const group=await observe(42,-100123);r=await post('/mini-app/api/action',intent(group,42,-100123,'reset_history'));assert.equal(r.body.status,'applied');assert.equal((await observe(42,-100123))['Stored exchanges'],'0');checks.push('signed_group_reset');
 r=await post('/mini-app/api/action',intent(after,42,undefined,'reset_history'));assert.equal(r.body.status,'applied');const reset=await observe();assert.equal(Number(reset['Context version']),Number(after['Context version'])+1);checks.push('empty_reset_advances_version');
 const a1=intent(reset),a2=intent(reset);const race=await Promise.all([post('/mini-app/api/action',a1),post('/mini-app/api/action',a2)]);assert.deepEqual(race.map(x=>x.code).sort(),[200,409]);checks.push('competing_clears_only_one_effect');
 const final=await observe();r=await post('/mini-app/api/action',{...intent(final),extra:true});assert.equal(r.code,401);assert.equal((await observe())['Context version'],final['Context version']);checks.push('closed_schema');
 fs.writeFileSync(out+'/memory-http.json',JSON.stringify({at:new Date().toISOString(),status:'PASS',checks,seed_job:id},null,2));fs.writeFileSync(out+'/memory-signed.json',JSON.stringify({init_data:sign()}),{mode:384});console.log({status:'PASS',checks:checks.length});
}
main().catch(e=>{fs.writeFileSync(out+'/memory-http-failure.json',JSON.stringify({error:String(e),checks},null,2));console.error(e);process.exitCode=1;});
