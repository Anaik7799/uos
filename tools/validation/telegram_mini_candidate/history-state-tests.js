// Actual private native-store state transition; never calls Telegram or a model.
const fs=require('fs'),cp=require('child_process'),crypto=require('crypto'),path=require('path');
const root='/home/an/NAS-setup/uos',out=__dirname;
const db='/home/an/uos-agent-runtime/20261024-0555/mini-history-20261025-0227/history.sqlite3';
const token='333444:synthetic-mini-test-token';
function signed(user=42){const p={auth_date:String(Math.floor(Date.now()/1000)),user:JSON.stringify({id:user,first_name:'Fixture'})};const secret=crypto.createHmac('sha256','WebAppData').update(token).digest();p.hash=crypto.createHmac('sha256',secret).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();}
async function read(user=42){const r=await fetch('http://nas-1.tail55d152.ts.net:49134/mini-app/api/data',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({init_data:signed(user),path:'/mini-app/chat'}),signal:AbortSignal.timeout(6000)});const j=await r.json();if(r.status!==200||j.status!=='observed')throw Error('history read unavailable');return j;}
(async()=>{const evidence={observed_at:new Date().toISOString(),scope:'Private persisted history change; no production or model effects',rows:[]};
try{const before=await read(),other=await read(43);if(before.fields['Stored exchanges']!=='1')throw Error('fixture already changed');evidence.rows.push({stage:'before',count:before.fields['Stored exchanges'],generation:before.fields.Generation});
const code='code:add_paths(filelib:wildcard("'+root+'/apps/cepaf_gleam/build/dev/erlang/*/ebin")),code:add_patha("'+out+'/build/ebin"),application:ensure_all_started(crypto),mini_history_fixture:append(<<"'+db+'">>,15,42,42,<<"Actual persisted second prompt">>,binary:copy(<<"LONG_HISTORY_TEXT_">>,240)),halt().';
const r=cp.spawnSync(root+'/toolchains/nix-profile/bin/erl',['+S','2:2','+A','2','-noshell','-eval',code],{encoding:'utf8',timeout:15000,env:{...process.env,ERL_CRASH_DUMP:'/dev/null'}});
evidence.native={exit:r.status,stdout:r.stdout,stderr:r.stderr,error:r.error?.message||null};if(r.status||r.error)throw Error('native fixture append failed');
const after=await read(),otherAfter=await read(43);const parts=Object.entries(after.fields).filter(([k])=>k.startsWith('Exchange 02 update 15 · 2 Assistant')).sort(([a],[b])=>a.localeCompare(b));if(after.fields['Stored exchanges']!=='2'||parts.map(x=>x[1]).join('')!=='LONG_HISTORY_TEXT_'.repeat(240))throw Error('persisted text not exact');
const keep=j=>Object.fromEntries(Object.entries(j.fields).filter(([k])=>k.startsWith('Exchange ')));if(JSON.stringify(keep(other))!==JSON.stringify(keep(otherAfter)))throw Error('other user history changed');if(JSON.stringify(after.fields).includes('OTHER_USER_SECRET'))throw Error('other identity leaked');
evidence.rows.push({stage:'after',count:after.fields['Stored exchanges'],generation:after.fields.Generation,reply_parts:parts.length,reply_bytes:Buffer.byteLength(parts.map(x=>x[1]).join(''))});evidence.other_user_history_unchanged=true;evidence.status='PASS_ACTUAL_HISTORY_CHANGE';}
catch(e){evidence.status='FAIL';evidence.error=e.message;process.exitCode=1;}
finally{fs.writeFileSync(out+'/history-state-change.json',JSON.stringify(evidence,null,2));console.log(evidence);}})();
