const fs=require('fs'),c=require('crypto'),assert=require('assert');
const base='http://nas-1.tail55d152.ts.net:49134',out=process.argv[2],log=process.argv[3],checks=[];
function sign(id=42,chat,at=Math.floor(Date.now()/1000)){
 const p={auth_date:String(at),user:JSON.stringify({id,first_name:'CHAT_FIXTURE'})};if(chat!==undefined)p.chat=JSON.stringify({id:chat});
 const k=c.createHmac('sha256','WebAppData').update('333444:synthetic-mini-test-token').digest();
 p.hash=c.createHmac('sha256',k).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();
}
async function post(path,body){const r=await fetch(base+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(55000)});return{code:r.status,body:await r.json()};}
async function observe(id=42,chat){const r=await post('/mini-app/api/data',{init_data:sign(id,chat),path:'/mini-app/chat'});assert.equal(r.body.status,'observed');return r.body.fields;}
function intent(f,prompt='A fixture chat question',id=42,chat){return{init_data:sign(id,chat),path:'/mini-app/chat',action:'send_message',request_id:c.randomBytes(16).toString('hex'),prompt,expected_version:Number(f['Context version']),expected_sha256:f['Context SHA256']};}
function calls(){return fs.existsSync(log)?fs.readFileSync(log,'utf8').trim().split('\n').filter(Boolean).length:0;}
function receipt(r){let p=r.body.receipt;if(typeof p==='string')p=JSON.parse(p);return p?.native_receipt?JSON.parse(p.native_receipt):p;}
async function main(){
 let f=await observe(),other=await observe(43),a=intent(f),n=calls();
 let r=await post('/mini-app/api/action',a);assert.equal(r.body.status,'applied',JSON.stringify(r));assert.equal(receipt(r).status,'completed');assert.equal(calls(),n+1);
 let after=await observe();assert.equal(Number(after['Stored exchanges']),Number(f['Stored exchanges'])+1);assert.equal(Number(after['Context version']),Number(f['Context version'])+1);assert(JSON.stringify(after).includes('Fixture reply'));checks.push('send_model_once_and_durable_history_readback');
 r=await post('/mini-app/api/action',a);assert.equal(r.body.status,'terminal_receipt');assert.equal(receipt(r).status,'completed');assert.equal(calls(),n+1);checks.push('duplicate_action_recovers_without_model_replay');
 r=await post('/mini-app/api/action-receipt',a);assert.equal(receipt(r).reply,'Fixture reply <script>not executed</script>');assert.equal(calls(),n+1);checks.push('receipt_only_returns_exact_reply');
 r=await post('/mini-app/api/action',{...a,prompt:'changed'});assert.equal(r.code,409);assert.equal(calls(),n+1);checks.push('same_nonce_changed_prompt_refused');
 r=await post('/mini-app/api/action',intent(f));assert.equal(r.code,409);assert.equal(calls(),n+1);checks.push('stale_context_no_model');
 r=await post('/mini-app/api/action',intent(other,'forbidden',43));assert.equal(r.code,401);checks.push('read_grant_cannot_send');
 r=await post('/mini-app/api/action',intent(after,'forbidden',42,-100124));assert.equal(r.code,409);checks.push('ungranted_signed_chat_refused');
 r=await post('/mini-app/api/action',{...intent(after),init_data:sign(42,undefined,Math.floor(Date.now()/1000)-301)});assert.equal(r.code,401);checks.push('expired_signature_refused');
 r=await post('/mini-app/api/action',{...intent(after),extra:true});assert.equal(r.code,401);checks.push('closed_request_schema');
 r=await post('/mini-app/api/action',intent(after,'x'.repeat(4097)));assert.equal(r.code,401);assert.equal(calls(),n+1);checks.push('oversize_prompt_before_model');
 const failed=intent(after,'fixture-model-fail');r=await post('/mini-app/api/action',failed);assert.equal(receipt(r).status,'model_failed');assert(!JSON.stringify(r).includes('PRIVATE FIXTURE'));assert.equal(calls(),n+2);assert.equal((await observe())['Context version'],after['Context version']);checks.push('failed_provider_no_history_and_no_raw_error');
 r=await post('/mini-app/api/action',failed);assert.equal(receipt(r).status,'model_failed');assert.equal(calls(),n+2);checks.push('failed_provider_not_retried');
 let otherAfter=await observe(43);for(const k of Object.keys(other).filter(x=>x!=='Generation'))assert.deepEqual(otherAfter[k],other[k]);checks.push('other_user_context_unchanged');
 const group=await observe(42,-100123);r=await post('/mini-app/api/action',intent(group,'group question',42,-100123));assert.equal(receipt(r).status,'completed');assert.equal((await observe())['Context version'],after['Context version']);checks.push('signed_group_send_isolated');
 after=await observe();const pair=await Promise.all([post('/mini-app/api/action',intent(after,'race one')),post('/mini-app/api/action',intent(after,'race two'))]);assert.deepEqual(pair.map(x=>x.code).sort(),[200,409]);assert.equal(calls(),n+4);checks.push('competing_sends_one_model_call');
 fs.writeFileSync(out+'/chat-http.json',JSON.stringify({at:new Date().toISOString(),status:'PASS',checks,model_calls:calls()-n,provider:'synthetic test adapter; no live inference'},null,2));
 fs.writeFileSync(out+'/chat-signed.json',JSON.stringify({init_data:sign()}),{mode:384});
 fs.writeFileSync(out+'/chat-restart-request.json',JSON.stringify(a),{mode:384});console.log({status:'PASS',checks:checks.length,model_calls:calls()-n});
}
main().catch(e=>{fs.writeFileSync(out+'/chat-http-failure.json',JSON.stringify({error:String(e),checks},null,2));console.error(e);process.exitCode=1;});
