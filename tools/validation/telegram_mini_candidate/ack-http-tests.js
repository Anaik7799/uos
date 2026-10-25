const fs=require('fs'),c=require('crypto'),assert=require('assert'),cp=require('child_process');
const out=process.argv[2];if(!out)throw Error('output directory required');
const base='http://nas-1.tail55d152.ts.net:49134';
function sign(id=42,date=Math.floor(Date.now()/1000)){const p={auth_date:String(date),user:JSON.stringify({id,first_name:'Fixture'})};const secret=c.createHmac('sha256','WebAppData').update('333444:synthetic-mini-test-token').digest();p.hash=c.createHmac('sha256',secret).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();}
const rows=[];function save(status,error){fs.writeFileSync(out+'/ack-http.json',JSON.stringify({at:new Date().toISOString(),status,error,scope:'Private full-app Mist ingress, synthetic identity, actual canonical Sa-plan receipts and live alert producers; not production or real Telegram acceptance',rows},null,2));}
async function post(path,body){const r=await fetch(base+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(55000)});return {http:r.status,payload:await r.json()};}
async function observe(){const r=await post('/mini-app/api/data',{init_data:sign(),path:'/mini-app/alerts'});assert.equal(r.http,200);assert.equal(r.payload.status,'observed');assert.equal(r.payload.fields['Reader user'],'42');return r.payload.fields;}
function alerts(f){return Object.entries(f).filter(([k])=>/^Alert [0-9]+$/.test(k)).map(([,v])=>JSON.parse(v));}
function request(f,action='acknowledge_all',target='all'){return {init_data:sign(),path:'/mini-app/alerts',action,request_id:c.randomBytes(16).toString('hex'),expected_episode_set:f['Episode set SHA256'],target_episode:target};}
async function check(name,path,body,status,expected){const r=await post(path,body);rows.push({name,...r});save('RUNNING');assert.equal(r.http,status,name);assert.equal(r.payload.status,expected,name);return r.payload;}
(async()=>{
 const first=await observe(),list=alerts(first);assert(list.length>=2);assert(list.every(a=>a.review===null));assert(/^[a-f0-9]{64}$/.test(first['Owner incarnation']));rows.push({name:'observed_owner',count:list.length,instance:first['Owner incarnation']});
 const one=request(first,'acknowledge_alert',list[0].episode);
 const done=await check('single','/mini-app/api/action',one,200,'alerts_acknowledged');assert.equal(done.effects_this_request,1);
 const second=await observe();assert(alerts(second).some(a=>a.episode===list[0].episode&&a.review?.user===42));
 assert.notEqual(second['Episode set SHA256'],first['Episode set SHA256']);
 const replay=await check('nonce_replay','/mini-app/api/action',one,200,'terminal_receipt');assert.equal(replay.effects_this_request,0);
 await check('nonce_conflict','/mini-app/api/action',{...one,target_episode:list[1].episode},409,'request_id_conflict');
 await check('old_all_set','/mini-app/api/action',request(first),409,'alert_set_changed_or_empty');
 const all=request(await observe());const allDone=await check('all','/mini-app/api/action',all,200,'alerts_acknowledged');
 const after=await observe(),afterRows=alerts(after);assert(afterRows.every(a=>a.review));assert.equal(afterRows.length,list.length);
 for(const a of list){const found=afterRows.find(x=>x.episode===a.episode);assert(found);assert.equal(found.severity,a.severity);assert.equal(found.condition,a.condition);}
 await check('receipt_only','/mini-app/api/action-receipt',all,200,'terminal_receipt');
 await check('already_reviewed','/mini-app/api/action',request(after),409,'already_acknowledged');
 await check('denied_identity','/mini-app/api/action',{...request(after),init_data:sign(99)},401,'unauthorized');
 await check('expired_identity','/mini-app/api/action',{...request(after),init_data:sign(42,Math.floor(Date.now()/1000)-301)},401,'unauthorized');
 const id=allDone.job_id;assert(/^mini-control\/[a-f0-9]{64}$/.test(id));
 const durable=JSON.parse(cp.execFileSync('/usr/bin/sqlite3',['-readonly','-json','/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3',"SELECT id,state,attempt,args,result FROM sa_plan_job WHERE id='"+id+"';"],{encoding:'utf8',timeout:3000}))[0];
 assert.equal(durable.state,'completed');assert.equal(durable.attempt,1);const receipt=JSON.parse(JSON.parse(durable.result).native_receipt);assert.equal(receipt.condition_cleared,false);assert.equal(receipt.owner_incarnation,first['Owner incarnation']);assert.equal(receipt.user,42);assert(receipt.episodes.length>0);assert(!durable.args.includes('init_data'));rows.push({name:'canonical_receipt',job:id,state:durable.state,receipt});
 fs.writeFileSync(out+'/ack-browser-identity.json',JSON.stringify({init_data:sign(),scope:'synthetic Telegram fixture'}),{mode:0o600});
 save('PASS');console.log(JSON.stringify({status:'PASS',cases:rows.length}));
})().catch(e=>{save('FAIL',e.message);console.error(e);process.exitCode=1;});
