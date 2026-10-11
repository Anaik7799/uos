// Creates only a new private Sa-plan fixture through the canonical CLI.
const fs=require('fs'),path=require('path'),cp=require('child_process');
const root='/home/an/NAS-setup/uos',out=process.argv[2];
if(!out||!path.isAbsolute(out)||!out.startsWith(root+'/var/recovery-runtime/')||!fs.statSync(out).isDirectory())throw Error('existing private recovery build directory required');
const db=out+'/fixture.sqlite3';
if(fs.existsSync(db))throw Error('new fixture required');
const calls=[];
function run(args){
 const r=cp.spawnSync(root+'/engines/hermes/_build/default/modules/sa_plan/test/sa_plan_main.exe',args,{cwd:root,env:{...process.env,UOS_SA_PLAN_DB:db},encoding:'utf8',timeout:3000,maxBuffer:262144});
 calls.push({args,status:r.status,error:r.error?.message||null,stdout:r.stdout,stderr:r.stderr});
 fs.writeFileSync(out+'/fixture-creation.json',JSON.stringify({observed_at:new Date().toISOString(),database:db,scope:'PRIVATE TEST ONLY; no canonical planning authority',calls},null,2)+'\n');
 if(r.status!==0||r.error)throw Error('private fixture creation failed');
}
run(['plan','create','private/telegram-fence-review','private/mini-private','Private Mini task read fixture']);
run(['task','create','private/telegram-fence-review','FENCE','private/fence','Expired lease rendering fixture','-','','1']);
run(['task','claim','private-fixture-worker','private/telegram-fence-review','1','FENCE']);
console.log(db);
