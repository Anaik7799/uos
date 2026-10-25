const fs=require('fs'),cp=require('child_process'),c=require('crypto'),assert=require('assert');
const out=process.argv[2],base='http://nas-1.tail55d152.ts.net:49134',cli='/home/an/NAS-setup/uos/tools/sa-plan',db='/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3',checks=[];
function row(id){const r=cp.spawnSync('/usr/bin/sqlite3',['-readonly','-json',db,"SELECT * FROM sa_plan_job WHERE id='"+id+"';"],{encoding:'utf8'});assert.equal(r.status,0);return JSON.parse(r.stdout)[0];}
function run(args){const r=cp.spawnSync(cli,['--format','json',...args],{encoding:'utf8',timeout:10000});assert.equal(r.status,0,r.stderr);return JSON.parse(r.stdout.split('\n')[0]);}
function sign(){const p={auth_date:String(Math.floor(Date.now()/1000)),user:JSON.stringify({id:42,first_name:'CONTROL_FIXTURE'})},k=c.createHmac('sha256','WebAppData').update('333444:synthetic-mini-test-token').digest();p.hash=c.createHmac('sha256',k).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();}
async function post(path,b){const r=await fetch(base+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(b),signal:AbortSignal.timeout(55000)});return {code:r.status,data:await r.json()};}
async function main(){
 const summary=JSON.parse(fs.readFileSync(out+'/control-http.json')),seed=row(summary.seed_job),args=JSON.parse(seed.args);
 const read={init_data:sign(),path:'/mini-app/telemetry'},before=await post('/mini-app/api/data',read);
 for(const executing of [false,true]){
  const nonce=c.randomBytes(16).toString('hex'),id='mini-control/'+c.createHash('sha256').update(JSON.stringify(['333444','42','set_vm_logger_level',nonce])).digest('hex');
  const b={...read,action:'set_vm_logger_level',request_id:nonce,expected_level:args.expected,target_level:args.target};
  run(['--job-enqueue',id,id,id,seed.worker,seed.args,'1']);
  if(executing){const claim=run(['--job-claim',id,seed.worker,'60000000000']);assert.equal(claim.id,id);assert.equal(String(claim.attempt),'1');}
  const result=await post('/mini-app/api/action',b),lookup=await post('/mini-app/api/action-receipt',b),after=row(id);
  assert.equal(result.data.status,executing?'uncertain_no_replay':'unclaimed_no_replay');
  assert.equal(result.data.effects_this_request,0);assert.equal(lookup.data.status,result.data.status);
  assert.equal(after.attempt,executing?1:0);assert.equal(after.state,executing?'executing':'available');
  const vm=await post('/mini-app/api/data',read);assert.equal(vm.data.fields['VM logger level'],before.data.fields['VM logger level']);
  checks.push({name:executing?'interrupted_claim_never_reclaimed':'orphaned_available_never_claimed',job:id,observed_state:after.state,observed_attempt:after.attempt,mutation_replay:false,receipt_lookup:true});
  // Explicit test teardown, not an action retry: no effect adapter is invoked.
  if(!executing){const claim=run(['--job-claim',id,seed.worker,'60000000000']);assert.equal(claim.id,id);}
  const done=run(['--job-complete',id,seed.worker,'1','ERROR',JSON.stringify({status:'synthetic_recovery_fixture_cleanup',effect_count:0})]);
  assert.equal(done.state,'discarded');
 }
 fs.writeFileSync(out+'/control-recovery.json',JSON.stringify({status:'PASS',at:new Date().toISOString(),checks,cleanup:'Canonical explicit no-effect fixture teardown; no row deletion'},null,2));console.log(JSON.stringify({status:'PASS',checks:checks.length}));
}
main().catch(e=>{fs.writeFileSync(out+'/control-recovery-failure.json',JSON.stringify({error:String(e),checks}));console.error(e);process.exitCode=1;});