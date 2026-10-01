// Audit actual compiled candidate theorem closures; no admission authority.
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const root='/home/an/NAS-setup/uos',ws=path.resolve(__dirname,'../..'),out=process.argv[2],start=Number(process.argv[3]||0);
if(!out||!path.isAbsolute(out)||!out.startsWith(root+'/var/recovery-runtime/')||!Number.isInteger(start)||start<0)throw Error('private compiled output and ordered batch required');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const compiled=JSON.parse(fs.readFileSync(out+'/results.json'));
const lean=root+'/toolchains/lean-4.33.0/bin/lean';
if(compiled.calls.length!==compiled.files.length||compiled.calls.some(x=>x.status!==0)||sha(lean)!==compiled.toolchain_sha256)throw Error('complete successful matching compilation required');
const target=out+'/axiom-results.json';
let results=start===0?{scope:'Actual compiled theorem axiom closures, including generated theorems; does not assert implementation correspondence',compile_manifest_sha256:sha(out+'/results.json'),calls:[]}:JSON.parse(fs.readFileSync(target));
if(start===0&&fs.existsSync(target))throw Error('audit already exists');
if(results.calls.length!==start||results.compile_manifest_sha256!==sha(out+'/results.json'))throw Error('audit sequence or compilation changed');
const template="import Lean\nimport Telegram_Numeric_Contract\n\nopen Lean Elab Command in\nrun_elab do\n  let env ← getEnv\n  let some target := env.getModuleIdx? `Telegram_Numeric_Contract\n    | throwError \"target module not found\"\n  let mut count := 0\n  for (name, info) in env.constants do\n    if env.getModuleIdxFor? name == some target then\n      if info matches .thmInfo _ then\n        let axs ← Lean.collectAxioms name\n        for ax in axs do\n          unless #[`propext, `Classical.choice, `Quot.sound].contains ax do\n            throwError \"unexpected axiom {ax} in {name}\"\n        logInfo m!\"AXIOM_AUDIT {name} {axs}\"\n        count := count + 1\n  logInfo m!\"AXIOM_COUNT {count}\"\n";
for(const item of compiled.calls.slice(start,start+6)){
 if(item.source_sha256!==sha(item.source)||path.dirname(item.source)!==ws+'/formal/lean')throw Error('compiled source changed or wrong workspace');
 const module=item.name.replace(/\.lean$/,''),olean=out+'/'+module+'.olean',olean_sha256=sha(olean);
 if(!item.olean_sha256||item.olean_sha256!==olean_sha256)throw Error('compiled artifact changed before audit');
 const driver=out+'/Audit_'+module+'.lean', log=driver+'.log';
 fs.writeFileSync(driver,template.replaceAll('Telegram_Numeric_Contract',module)+'\n');
 const r=cp.spawnSync(lean,[driver],{cwd:root,env:{...process.env,LEAN_PATH:out},encoding:'utf8',timeout:7000,killSignal:'SIGKILL',maxBuffer:1048576});
 fs.writeFileSync(log,(r.stdout||'')+(r.stderr||''));
 const match=(r.stdout||'').match(/AXIOM_COUNT (\d+)/);
 if(sha(olean)!==olean_sha256||sha(item.source)!==item.source_sha256)throw Error('candidate changed during audit');
 results.calls.push({module,source_sha256:item.source_sha256,olean_sha256,status:r.status,error:r.error?.message||null,signal:r.signal||null,theorem_count:match?Number(match[1]):null,log,log_sha256:sha(log),observed_at:new Date().toISOString()});
 fs.writeFileSync(target,JSON.stringify(results,null,2)+'\n');
}
const failures=results.calls.filter(x=>x.status!==0||x.theorem_count===null);
console.log(JSON.stringify({checked:results.calls.length,total:compiled.calls.length,theorem_closures:results.calls.reduce((n,x)=>n+(x.theorem_count||0),0),failures:failures.map(x=>x.module)}));
if(failures.length)process.exitCode=1;
