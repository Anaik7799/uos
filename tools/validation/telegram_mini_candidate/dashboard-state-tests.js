// Actual private Podman state change through the authenticated dashboard.
const fs=require('fs'),cp=require('child_process'),crypto=require('crypto'),path=require('path');
const out=process.argv[2],base='http://nas-1.tail55d152.ts.net:49134';
if(!out||!path.isAbsolute(out)||!out.startsWith('/home/an/NAS-setup/uos/var/recovery-runtime/')||!fs.statSync(out).isDirectory())throw Error('private output required');
const nonce=crypto.randomUUID(),name='uos-dashboard-test-'+nonce.slice(0,8),image='sha256:925ff61909aebae4bcc9bc04bb96a8bd15cd2271f13159fe95ce4338824531dd';
let id=null;const report={observed_at:new Date().toISOString(),nonce,name,scope:'Only disposable labeled fixture; existing containers untouched',calls:[],rows:[],cleanup:false};
function save(){fs.writeFileSync(out+'/dashboard-state-change.json',JSON.stringify(report,null,2));}
function run(args){
 if(crypto.createHash('sha256').update(fs.readFileSync('/usr/bin/podman')).digest('hex')!=='6627da0abfd3b0189498089319f5759c7b132bb6a51130bf8ff43d7f102d9673')throw Error('Podman hash');
 const r=cp.spawnSync('/usr/bin/podman',['--remote=false',...args],{encoding:'utf8',timeout:5000,maxBuffer:65536});
 report.calls.push({args,exit:r.status,stdout:r.stdout,stderr:r.stderr});save();if(r.status!==0)throw Error('fixture command '+args[0]);return r.stdout.trim();
}
function owned(){if(!/^[0-9a-f]{64}$/.test(id||''))throw Error('no fixture');const exact=run(['ps','--all','--no-trunc','--filter','id='+id,'--filter','label=uos.telegram.fixture='+nonce,'--format','{{.ID}}']);if(exact!==id)throw Error('fixture owner mismatch');}
function sign(){let p={auth_date:String(Math.floor(Date.now()/1000)),user:JSON.stringify({id:42,first_name:'Fixture'})};let secret=crypto.createHmac('sha256','WebAppData').update('333444:synthetic-mini-test-token').digest();p.hash=crypto.createHmac('sha256',secret).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');return new URLSearchParams(p).toString();}
async function observe(stage){const r=await fetch(base+'/mini-app/api/data',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({init_data:sign(),path:'/mini-app/dashboard'}),signal:AbortSignal.timeout(6000)});const j=await r.json();if(r.status!==200||j.status!=='observed'||j.source!=='operational_dashboard')throw Error('dashboard unavailable');const n=Number(j.fields['Container count']);if(!Number.isInteger(n)||n<0)throw Error('no measured count');report.rows.push({stage,count:n,observed_at:j.observed_at,fields:j.fields});save();return n;}
(async()=>{let failure=null,baseline,inventory;try{
 inventory=run(['ps','--all','--no-trunc','--format','{{.ID}} {{.State}}']).split('\n').sort().join('\n');baseline=await observe('before');
 id=run(['create','--pull=never','--name',name,'--network=none','--read-only','--cap-drop=all','--security-opt=no-new-privileges','--pids-limit=16','--memory=32m','--image-volume=ignore','--label','uos.telegram.fixture='+nonce,image,'/bin/true']);report.container_id=id;owned();
 const after=await observe('created');if(after!==baseline+1)throw Error('created count not reflected');
 }catch(e){failure=e;report.error=e.message;}finally{if(id){try{owned();run(['rm',id]);report.cleanup=true;}catch(e){failure||=e;report.cleanup_error=e.message;}}save();}
 if(failure)throw failure;const restored=await observe('removed');if(restored!==baseline)throw Error('removed count not restored');
 const now=run(['ps','--all','--no-trunc','--format','{{.ID}} {{.State}}']).split('\n').sort().join('\n');if(now!==inventory)throw Error('existing inventory changed');
 report.preexisting_inventory_unchanged=true;report.status='PASS';save();console.log({status:'PASS_DASHBOARD_STATE_CHANGE',counts:report.rows.map(r=>r.count),cleanup:report.cleanup});
})().catch(e=>{report.status='FAIL';report.error=e.message;save();console.error(e);process.exitCode=1;});
