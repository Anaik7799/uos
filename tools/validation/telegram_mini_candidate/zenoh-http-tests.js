const fs=require('fs'),crypto=require('crypto'),cp=require('child_process');
const base='http://nas-1.tail55d152.ts.net:49134',out=process.argv[2],prefix='uos/tui/recovery/telegram-mini/20261025-0258/',token='333444:synthetic-mini-test-token';
const now=Math.floor(Date.now()/1000);
function sign(id=42,date=now){const p={auth_date:String(date),user:JSON.stringify({id,first_name:'Fixture'})};const secret=crypto.createHmac('sha256','WebAppData').update(token).digest();p.hash=crypto.createHmac('sha256',secret).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();}
const rows=[];
async function check(name,id,topic,expected=200,path='/mini-app/zenoh',date=now){
 const body={init_data:sign(id,date),path};if(topic!==null)body.topic=topic;
 const r=await fetch(base+'/mini-app/api/data',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(5500)});
 const j=await r.json();if(r.status!==expected)throw Error(name+' unexpected '+r.status+' '+JSON.stringify(j));
 rows.push({name,http:r.status,payload:j});return j;
}
(async()=>{try{
 let j=await check('scoped topic list',42,null);if(j.source!=='server_topic_grants'||j.fields['Topic count']!=='2'||JSON.stringify(j).includes('other-user'))throw Error('topic list scope');
 j=await check('actual selected retained sample',42,prefix+'topic-a');if(j.source!=='zenoh_rest'||j.fields['Message part 01']!=='First retained sample <script>literal</script>')throw Error('actual sample missing');
 j=await check('no retained reply explicit',42,prefix+'missing');if(j.fields['Query result']!=='No retained reply')throw Error('absence hidden');
 await check('cross-user topic refused',42,prefix+'other-user',403);
 await check('ungranted user refused',44,null,403);
 await check('wildcard refused',42,prefix+'**',403);
 await check('path traversal refused',42,prefix+'../other-user',403);
 await check('topic cannot select another page backend',42,prefix+'topic-a',400,'/mini-app/chat');
 await check('unauthorized identity',99,prefix+'topic-a',401);
 await check('expired identity',42,prefix+'topic-a',401,'/mini-app/zenoh',now-301);
 j=await check('other user isolated sample',43,prefix+'other-user');if(j.fields['Message part 01']!=='OTHER_USER_TOPIC_SECRET'||JSON.stringify(j).includes('topic-a'))throw Error('other user scope');
 fs.writeFileSync(out+'/zenoh-http.json',JSON.stringify({status:'PASS',observed_at:new Date().toISOString(),rows},null,2));
 fs.writeFileSync(out+'/zenoh-browser-identity.json',JSON.stringify({init_data:sign(),scope:'Synthetic Telegram fixture only'}));
 console.log({status:'PASS_ZENOH_HTTP',checks:rows.length});
 }catch(e){fs.writeFileSync(out+'/zenoh-http-failure.json',JSON.stringify({error:e.message,rows},null,2));throw e;}})().catch(e=>{console.error(e);process.exitCode=1;});
