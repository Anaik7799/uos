// Run only against a unique private fixture under the candidate output.
const fs=require('fs'),cp=require('child_process'),crypto=require('crypto'),path=require('path');
const out=process.argv[2],root='/home/an/NAS-setup/uos';
if(!out?.startsWith(root+'/var/recovery-runtime/')||path.resolve(out)!==out)throw Error('private candidate required');
const dir=out+'/budget-native-'+crypto.randomUUID();fs.mkdirSync(dir);
const exe=out+'/ecology_budget.exe',sha=crypto.createHash('sha256').update(fs.readFileSync(exe)).digest('hex'),db=dir+'/budget.sqlite3',checks=[];
function run(exe,args,input){return cp.spawnSync(exe,args,{cwd:root,input,encoding:'utf8',timeout:7000,maxBuffer:32768});}
function check(name,truth){checks.push({name,pass:!!truth});if(!truth)throw Error(name);}
function ledger(args,input){const r=run(exe,args,input);return {code:r.status,data:JSON.parse(r.stdout)};}
function observe(db,pin=sha){
 const binary=s=>'<<'+JSON.stringify(s)+'>>';
 const expression='code:add_paths(filelib:wildcard("'+root+'/apps/cepaf_gleam/build/dev/erlang/*/ebin")),code:add_patha("'+out+'/build/ebin"),case cepaf_gleam@harness@telegram_budget_report:observe({source,'+[exe,pin,db].map(binary).join(',')+'}) of {ok,R}->io:put_chars(R),halt();{error,_}->io:put_chars("unavailable"),halt(3) end.';
 return run(root+'/toolchains/nix-profile/bin/erl',['+S','2:2','+A','2','-noshell','-eval',expression]);
}
function bytes(){return ['', '-wal'].map(s=>fs.existsSync(db+s)&&fs.statSync(db+s).size>0?crypto.createHash('sha256').update(fs.readFileSync(db+s)).digest('hex'):null);}
try {
 check('initialize_private_fixture',ledger(['init',db]).code===0);
 const request=i=>JSON.stringify({call_id:'fixture-'+i,model:'z-ai/glm-5.3',max_tokens:128,input_bytes:16,body_bytes:128});
 check('reserve_private_liability',ledger(['reserve',db],request(1)).code===0);
 const before=bytes(),observed=observe(db),data=JSON.parse(observed.stdout);
 check('live_nonzero_liability_projection',observed.status===0&&data.reservation_count===1&&data.daily_reserved_nanodollars===250000000&&data.remaining_nanodollars===9750000000&&data.actual_spend_nanodollars===null);
 check('read_preserves_main_and_nonempty_wal_bytes',JSON.stringify(before)===JSON.stringify(bytes()));
 check('no_path_or_request_identifier_disclosure',!observed.stdout.includes(db)&&!observed.stdout.includes('fixture-'));
 check('duplicate_reservation_refused',ledger(['reserve',db],request(1)).code!==0);
 for(let i=2;i<=40;i++)if(ledger(['reserve',db],request(i)).code!==0)throw Error('fixture reservation '+i);
 const exhausted=observe(db),exhaustedData=JSON.parse(exhausted.stdout);
 check('exhausted_ledger_projected',exhausted.status===0&&exhaustedData.reservation_count===40&&exhaustedData.remaining_nanodollars===0&&exhaustedData.daily_reserved_nanodollars===10000000000);
 check('forty_first_reservation_refused',ledger(['reserve',db],request(41)).code!==0);
 check('wrong_executable_pin_refused',observe(db,'0'.repeat(64)).status===3);
 const missing=dir+'/missing.sqlite3';
 check('missing_ledger_refused_and_not_created',observe(missing).status===3&&!fs.existsSync(missing));
 const corrupt=dir+'/corrupt.sqlite3';fs.writeFileSync(corrupt,'invalid SQLite');
 check('corrupt_ledger_refused',observe(corrupt).status===3);
} finally {fs.writeFileSync(out+'/budget-native-results.json',JSON.stringify({at:new Date().toISOString(),executable_sha256:sha,scope:'private synthetic ledger; no provider calls',checks},null,2)+'\n');}
console.log('BUDGET_NATIVE_'+checks.length+'_PASS');
