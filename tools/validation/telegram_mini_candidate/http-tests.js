const fs=require('fs'), crypto=require('crypto'), http=require('http');
const base='http://nas-1.tail55d152.ts.net:49134', out=__dirname;
const token='333444:synthetic-mini-test-token', now=Math.floor(Date.now()/1000);
function sign(user=42,date=now,chat=null) {
 const p={auth_date:String(date),user:JSON.stringify({id:user,first_name:'Fixture'})};
 if(chat!==null)p.chat=JSON.stringify({id:chat});
 const secret=crypto.createHmac('sha256','WebAppData').update(token).digest();
 p.hash=crypto.createHmac('sha256',secret).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');
 return new URLSearchParams(p).toString();
}
const good=sign();fs.writeFileSync(out+'/http-fixture-identity.json',JSON.stringify({init_data:good,scope:'Synthetic identity for private HTTP/browser fixture only'})+'\n');
const rows=[];
async function check(name,path,expected,options={}) {
 const r=await fetch(base+path,{...options,redirect:'manual',signal:AbortSignal.timeout(5000)});
 const body=await r.text();const row={name,path,status:r.status,expected,pass:r.status===expected};
 if(options.method==='POST'&&r.status===200)row.payload=JSON.parse(body);
 if(!options.method&&path.startsWith('/mini-app/')&&!path.includes('does-not')) {
  row.checkpoints=(body.match(/type="checkbox"/g)||[]).length;
 }
 rows.push(row);if(!row.pass)throw Error(JSON.stringify(row));
 return {r,body};
}
(async()=>{
 try {
 const failureMode=process.argv.includes('--unavailable');
 if(failureMode){for(const page of ['fmea','verify','containers','chat']){const item=await check('unavailable '+page,'/mini-app/api/data',200,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({init_data:good,path:'/mini-app/'+page})});const payload=JSON.parse(item.body);if(payload.status!=='unavailable'||Object.keys(payload.fields).length!==0)throw Error('backend failure disguised '+page);}fs.writeFileSync(out+'/http-failures.json',JSON.stringify({status:'PASS_BACKEND_REFUSALS',observed_at:new Date().toISOString(),rows},null,2));console.log({status:'PASS_BACKEND_REFUSALS',checks:rows.length});return;}
 const paths=['dashboard','health','alerts','immune','tasks','inference','chat','config','containers','federation','verify','fmea','telemetry','zenoh'];
 for(const p of paths){const x=await check('public '+p,'/mini-app/'+p,200);if((x.body.match(/type="checkbox"/g)||[]).length!==18)throw Error('checklist missing '+p);if(x.body.includes('All Clear')||x.body.includes('>17<'))throw Error('fake defaults '+p);}
 await check('unknown','/mini-app/does-not-exist',404);
 await check('prefix alias','/mini-application',404);
 await check('query boundary','/mini-app/tasks?probe=1',200);
 await check('data method','/mini-app/api/data',405);
 await check('public wrong method','/mini-app/tasks',405,{method:'DELETE'});
 const post=(init=good,path='/mini-app/tasks')=>({method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({init_data:init,path})});
 const result=await check('authenticated native private task snapshot','/mini-app/api/data',200,post());
 const payload=JSON.parse(result.body);if(payload.status!=='observed'||payload.fields['Task FENCE']!=='executing (lease expired)')throw Error('native snapshot not actually observed '+result.body);
 for(const page of ['fmea','verify']){const item=await check('authenticated actual '+page+' record','/mini-app/api/data',200,post(good,'/mini-app/'+page));const value=JSON.parse(item.body),text=JSON.stringify(value.fields);if(value.status!=='observed'||!text.includes('NOT_GRANTED'))throw Error('missing actual scoped record '+page+' '+item.body);if(page==='fmea'&&(!text.includes('uos/telegram-runtime/20261001-1150')||!text.includes('RPN')))throw Error('FMEA records absent');if(page==='verify'&&(!text.includes('CHK-18-JJ')||!text.includes('UNKNOWN')||text.includes('RECORDED_PASS')))throw Error('verification evidence inflated');await check('unauthorized '+page,'/mini-app/api/data',401,post(sign(99),'/mini-app/'+page));}
 const inventory=await check('authenticated local Podman inventory','/mini-app/api/data',200,post(good,'/mini-app/containers'));
 const inventoryPayload=JSON.parse(inventory.body);
 if(inventoryPayload.status!=='observed'||inventoryPayload.source!=='local_podman_cli'||!Object.hasOwn(inventoryPayload.fields,'Container count')||inventoryPayload.fields['Runtime admission']!=='NOT_GRANTED')throw Error('Podman inventory not observed');
 await check('unauthorized containers','/mini-app/api/data',401,post(sign(99),'/mini-app/containers'));

 for(const [label,user,chat,expected,forbidden] of [
 ['private',42,null,'Retained private reply42','OTHER_USER_SECRET'],
 ['other user',43,null,'OTHER_USER_SECRET','Private prompt owned'],
 ['signed group',42,-100123,'Granted group reply','UNGRANTED_GROUP_SECRET'],
 ['empty own history',44,null,'No stored complete exchanges','Retained private reply42']]){
 const item=await check('authenticated history '+label,'/mini-app/api/data',200,post(sign(user,now,chat),'/mini-app/chat'));
 const v=JSON.parse(item.body),text=JSON.stringify(v.fields);
 if(v.status!=='observed'||!text.includes(expected)||text.includes(forbidden)||v.source!=='durable_telegram_conversation')throw Error('history scope '+label);
 }
 const refused=await check('ungranted signed chat history','/mini-app/api/data',200,post(sign(42,now,-100124),'/mini-app/chat'));
 const deniedHistory=JSON.parse(refused.body);if(deniedHistory.status!=='unavailable'||Object.keys(deniedHistory.fields).length)throw Error('ungranted chat leak');
 await check('unauthorized history','/mini-app/api/data',401,post(sign(99),'/mini-app/chat'));
 
 await check('forged signature','/mini-app/api/data',401,post(good+'0'));
 await check('wrong user','/mini-app/api/data',401,post(sign(99)));
 await check('expired identity','/mini-app/api/data',401,post(sign(42,now-301)));
 await check('missing identity','/mini-app/api/data',400,{method:'POST',headers:{'content-type':'application/json'},body:'{}'});
 await check('oversize body','/mini-app/api/data',413,{method:'POST',headers:{'content-type':'application/json'},body:'x'.repeat(8193)});
 await check('wrong content type','/mini-app/api/data',415,{method:'POST',headers:{'content-type':'text/plain'},body:'{}'});
 await check('other mutation still requires original auth','/api/v1/plan/update',401,{method:'POST',headers:{'content-type':'application/json'},body:'{}'});
 const unintegrated=await check('unintegrated backend truth','/mini-app/api/data',200,post(good,'/mini-app/health'));
 if(JSON.parse(unintegrated.body).status!=='unavailable')throw Error('unintegrated backend claimed available');
 const chunked=await new Promise((resolve,reject)=>{const req=http.request(base+'/mini-app/api/data',{method:'POST',headers:{'transfer-encoding':'chunked','content-type':'application/json'},timeout:3000},r=>{r.resume();r.on('end',()=>resolve(r.statusCode));});req.on('error',reject);req.on('timeout',()=>req.destroy(Error('timeout')));req.end('{}');});
 rows.push({name:'chunked refused',status:chunked,expected:400,pass:chunked===400});if(chunked!==400)throw Error('chunked accepted');
 fs.writeFileSync(out+'/http-results.json',JSON.stringify({status:'PASS_PRIVATE_HTTP',observed_at:new Date().toISOString(),rows,scope:'Actual candidate server normal middleware, Mini ingress, auth and private native Sa-plan read; synthetic identity, no Bot API'},null,2)+'\n');
 console.log(JSON.stringify({status:'PASS_PRIVATE_HTTP',checks:rows.length}));
 }catch(error){fs.writeFileSync(out+'/http-results.json',JSON.stringify({status:'FAIL',observed_at:new Date().toISOString(),error:error.message,rows},null,2)+'\n');throw error;}
})();