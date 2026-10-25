const fs=require('fs'),c=require('crypto'),cp=require('child_process'),assert=require('assert');
const out=process.argv[2],root='/home/an/NAS-setup/uos',base='http://nas-1.tail55d152.ts.net:49134';
function sign(){const p={auth_date:String(Math.floor(Date.now()/1000)),user:JSON.stringify({id:42,first_name:'RECOVERY_FIXTURE'})};const k=c.createHmac('sha256','WebAppData').update('333444:synthetic-mini-test-token').digest();p.hash=c.createHmac('sha256',k).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();}
async function post(path,body){let r=await fetch(base+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(55000)});return {code:r.status,data:await r.json()};}
function command(exe,args){let r=cp.spawnSync(exe,args,{encoding:'utf8',timeout:15000,env:{...process.env,ERL_CRASH_DUMP:'/dev/null'}});assert.equal(r.status,0,r.stderr||r.stdout);return r.stdout;}
function sa(args){return JSON.parse(command(root+'/tools/sa-plan',['--format','json',...args]).split('\n')[0]);}
async function main(){
 const prior=await post('/mini-app/api/data',{init_data:sign(),path:'/mini-app/chat'});assert.equal(prior.data.status,'observed');const f=prior.data.fields;
 const seed=JSON.parse(fs.readFileSync(out+'/memory-http.json')).seed_job;
 const rows=JSON.parse(command('/usr/bin/sqlite3',['-readonly','-json',root+'/var/sa-plan/uos.sqlite3',"SELECT args,worker FROM sa_plan_job WHERE id='"+seed+"';"]));assert.equal(rows.length,1);
 const nonce=c.randomBytes(16).toString('hex'),id='mini-control/'+c.createHash('sha256').update(JSON.stringify(['333444','42','clear_history',nonce,'42'])).digest('hex');
 const args={...JSON.parse(rows[0].args),expected:f['Context version'],target:f['Context SHA256']},worker=rows[0].worker;
 assert.equal(sa(['--job-enqueue',id,id,id,worker,JSON.stringify(args),'1']).state,'available');
 let claimed=sa(['--job-claim',id,worker,'60000000000']);assert.equal(claimed.id,id);assert.equal(claimed.attempt,'1');
 const profile=JSON.parse(fs.readFileSync(out+'/fixture-profile.json'));
 const ev='code:add_paths(filelib:wildcard("'+root+'/apps/cepaf_gleam/build/dev/erlang/*/ebin")),code:add_patha("'+out+'/build/ebin"),mini_memory_native:commit_for_job(<<"'+profile.memory.database+'">>,<<"'+id+'">>,'+Number(f['Context version'])+',<<"'+f['Context SHA256']+'">>),halt().';
 command(root+'/toolchains/nix-profile/bin/erl',['+S','2:2','+A','2','-noshell','-eval',ev]);
 const body={init_data:sign(),path:'/mini-app/chat',action:'clear_history',request_id:nonce,expected_version:Number(f['Context version']),expected_sha256:f['Context SHA256']};
 let r=await post('/mini-app/api/action-receipt',body);assert.equal(r.data.status,'terminal_receipt');assert.equal(JSON.parse(r.data.receipt).status,'history_cleared');assert.equal(r.data.effects_this_request,0);
 const after=await post('/mini-app/api/data',{init_data:sign(),path:'/mini-app/chat'});assert.equal(Number(after.data.fields['Context version']),Number(f['Context version'])+1);
 r=await post('/mini-app/api/action',body);assert.equal(r.data.status,'terminal_receipt');assert.equal(r.data.effects_this_request,0);
 const afterDuplicate=await post('/mini-app/api/data',{init_data:sign(),path:'/mini-app/chat'});assert.equal(afterDuplicate.data.fields['Context version'],after.data.fields['Context version']);
 // Test owner reconciles its claimed job; receipt endpoint itself remains read-only.
 assert.equal(sa(['--job-complete',id,worker,'1','OK','Private interrupted-completion test: actual native receipt reconciled, no replay']).state,'completed');
 fs.writeFileSync(out+'/memory-native-recovery.json',JSON.stringify({at:new Date().toISOString(),status:'PASS',checks:2,job:id,native_receipt_recovered_without_saplan_result:true,duplicate_never_reapplies:true},null,2));console.log({status:'PASS',checks:2});
}
main().catch(e=>{fs.writeFileSync(out+'/memory-native-recovery-failure.json',JSON.stringify({error:String(e)}));console.error(e);process.exitCode=1;});
