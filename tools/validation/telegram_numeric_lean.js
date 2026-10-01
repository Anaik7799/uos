// Bounded pinned Lean corpus checker. Compilation is not runtime admission.
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const root='/home/an/NAS-setup/uos',ws=path.resolve(__dirname,'../..'),out=process.argv[2],start=Number(process.argv[3]||0);
if(!out||!path.isAbsolute(out)||!out.startsWith(root+'/var/recovery-runtime/')||!Number.isInteger(start)||start<0)throw Error('private output and nonnegative batch start required');
if(start===0){if(fs.existsSync(out))throw Error('new output required');fs.mkdirSync(out,{recursive:true});}else if(!fs.existsSync(out+'/results.json'))throw Error('previous batch required');
const files=fs.readdirSync(ws+'/formal/lean').filter(x=>x.endsWith('.lean')).sort((a,b)=>a==='Telegram_Numeric_Counterexamples.lean'?1:b==='Telegram_Numeric_Counterexamples.lean'?-1:a.localeCompare(b));
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
let results=start===0?{scope:'Kernel elaboration of exact listed candidate sources; no system admission',toolchain_sha256:sha(root+'/toolchains/lean-4.33.0/bin/lean'),files,calls:[]}:JSON.parse(fs.readFileSync(out+'/results.json'));
if(JSON.stringify(results.files)!==JSON.stringify(files)||results.calls.length!==start)throw Error('ordered corpus changed or batch out of sequence');
for(const name of files.slice(start,start+6)){
 const source=ws+'/formal/lean/'+name,source_sha256=sha(source),args=['-o',out+'/'+name.replace(/\.lean$/,'.olean'),source];
 const r=cp.spawnSync(root+'/toolchains/lean-4.33.0/bin/lean',args,{cwd:root,env:{...process.env,LEAN_PATH:out},encoding:'utf8',timeout:7000,killSignal:'SIGKILL',maxBuffer:1048576});
 const after=sha(source);if(after!==source_sha256)throw Error('source changed during proof');
 fs.writeFileSync(out+'/'+name+'.log',(r.stdout||'')+(r.stderr||''));
 results.calls.push({name,source,source_sha256,olean_sha256:r.status===0?sha(args[1]):null,status:r.status,error:r.error?.message||null,signal:r.signal||null,log:name+'.log',log_sha256:sha(out+'/'+name+'.log'),observed_at:new Date().toISOString()});
 fs.writeFileSync(out+'/results.json',JSON.stringify(results,null,2)+'\n');
}
console.log(JSON.stringify({total:files.length,checked:results.calls.length,failed:results.calls.filter(x=>x.status!==0).map(x=>x.name),next:results.calls.length}));
if(results.calls.some(x=>x.status!==0))process.exitCode=1;
