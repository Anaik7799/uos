// Private state-change acceptance; fixed cached image, no network or user containers.
const fs=require('fs'),cp=require('child_process'),crypto=require('crypto'),path=require('path');
const out=process.argv[2],base='http://nas-1.tail55d152.ts.net:49134';
if(!out||!path.isAbsolute(out)||!out.startsWith('/home/an/NAS-setup/uos/var/recovery-runtime/')||!fs.statSync(out).isDirectory())throw Error('private evidence directory required');
const nonce=crypto.randomUUID(),name='uos-mini-acceptance-'+nonce.slice(0,8);
const image='sha256:925ff61909aebae4bcc9bc04bb96a8bd15cd2271f13159fe95ce4338824531dd';
const report={observed_at:new Date().toISOString(),scope:'Disposable local rootless Podman fixture; no existing container mutations',nonce,name,rows:[],calls:[],cleanup:false,status:'RUNNING'};
let id=null,baselineFields=null;
function save(){fs.writeFileSync(out+'/podman-state-change.json',JSON.stringify(report,null,2)+'\n');}
function run(args){
 if(crypto.createHash("sha256").update(fs.readFileSync("/usr/bin/podman")).digest("hex")!=="6627da0abfd3b0189498089319f5759c7b132bb6a51130bf8ff43d7f102d9673")throw Error("Podman artifact changed");
 const r=cp.spawnSync('/usr/bin/podman',['--remote=false',...args],{encoding:'utf8',timeout:5000,maxBuffer:65536});
 report.calls.push({args,exit:r.status,stdout:r.stdout,stderr:r.stderr,error:r.error?.message||null});save();
 if(r.status!==0||r.error)throw Error('fixed Podman fixture operation failed: '+args[0]);
 return r.stdout.trim();
}
function owned(){
 if(!/^[0-9a-f]{64}$/.test(id||''))throw Error('no exact fixture ID');
 const found=run(['ps','--all','--no-trunc','--filter','id='+id,'--filter','label=uos.telegram.fixture='+nonce,'--format','{{.ID}}']);
 if(found!==id)throw Error('fixture identity/label no longer matches');
}
function signed(){
 const p={auth_date:String(Math.floor(Date.now()/1000)),user:JSON.stringify({id:42,first_name:'Fixture'})};
 const secret=crypto.createHmac('sha256','WebAppData').update('synthetic-mini-test-token').digest();
 p.hash=crypto.createHmac('sha256',secret).update(Object.keys(p).sort().map(k=>k+'='+p[k]).join('\n')).digest('hex');
 return new URLSearchParams(p).toString();
}
async function observe(stage){
 const r=await fetch(base+'/mini-app/api/data',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({init_data:signed(),path:'/mini-app/containers'}),signal:AbortSignal.timeout(6000),redirect:'error'});
 const j=await r.json();
 if(r.status!==200||j.status!=='observed'||j.source!=='local_podman_cli')throw Error('authenticated container observation failed');
 const value=id?j.fields['Container '+id]:null;
 report.rows.push({stage,http_status:r.status,status:j.status,at:j.observed_at,container_count:j.fields['Container count'],fixture_value:value??null});save();
 return {value,fields:j.fields};
}
(async()=>{
 let failure=null;
 try {
  const before=await observe('before');baselineFields=before.fields;
  id=run(['create','--pull=never','--name',name,'--network=none','--read-only','--cap-drop=all','--security-opt=no-new-privileges','--pids-limit=16','--memory=32m','--image-volume=ignore','--label','uos.telegram.fixture='+nonce,image,'/bin/true']);
  report.container_id=id;save();owned();
  const created=await observe('created');
  if(!created.value?.includes(name+' | created |'))throw Error('new backend state not reflected');
  owned();run(['start','--attach',id]);
  const exited=await observe('exited');
  if(!exited.value?.includes(name+' | exited |'))throw Error('changed backend state not reflected');
  if(created.value===exited.value)throw Error('unchanged rendered state');
 }catch(error){failure=error;report.error=error.message;}
 finally {
  if(id){try{owned();run(['rm',id]);report.cleanup=true;}catch(error){report.cleanup_error=error.message;failure||=error;}}
  save();
 }
 if(!failure){
  const removed=await observe('removed');
  if(removed.value!==undefined)throw Error('removed fixture still rendered');
  const existing=Object.keys(baselineFields).filter(k=>/^Container [0-9a-f]{64}$/.test(k)).sort();
  const current=Object.keys(removed.fields).filter(k=>/^Container [0-9a-f]{64}$/.test(k)).sort();
  if(JSON.stringify(existing)!==JSON.stringify(current)||existing.some(k=>baselineFields[k]!==removed.fields[k]))throw Error('preexisting inventory changed during fixture');
  report.preexisting_inventory_unchanged=true;
  report.status='PASS_ACTUAL_BACKEND_STATE_CHANGE';save();console.log({status:report.status,states:report.rows.map(x=>x.stage),cleanup:report.cleanup});
 }else {report.status='FAIL';save();throw failure;}
})().catch(error=>{report.status='FAIL';report.error=error.message;save();console.error(error.message);process.exitCode=1;});
