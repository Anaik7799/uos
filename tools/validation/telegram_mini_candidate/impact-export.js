// Development-only exporter. Run under an owned Sa-plan task through the Gleam harness.
// Uses the full-build receipt and complete source inventory; never a live Telegram path.
"use strict";
const fs=require("fs"),path=require("path"),crypto=require("crypto"),cp=require("child_process");
const [workspace,build,candidate,output]=process.argv.slice(2);
const fail=x=>{throw Error(x)};
const hash=b=>crypto.createHash("sha256").update(b).digest("hex");
const read=(p,max)=>{const s=fs.lstatSync(p);if(!s.isFile()||s.size>max)fail("not bounded regular file");const fd=fs.openSync(p,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);try{const a=fs.fstatSync(fd);if(a.ino!==s.ino||a.dev!==s.dev)fail("changed file");const b=Buffer.alloc(max+1);let n=0,k;while(n<=max&&(k=fs.readSync(fd,b,n,Math.min(65536,max+1-n),null))>0)n+=k;const z=fs.fstatSync(fd);if(n>max||n!==z.size||a.size!==z.size||a.mtimeMs!==z.mtimeMs)fail("changed or oversized file");return b.subarray(0,n)}finally{fs.closeSync(fd)}};
const run=(exe,args,timeout=10000)=>{const r=cp.spawnSync(exe,args,{cwd:workspace,encoding:"utf8",timeout,maxBuffer:2000000});if(r.status!==0)fail("bounded subprocess failed: "+String(r.stderr).slice(-500));return r.stdout};
if(![workspace,build,output].every(x=>x&&path.isAbsolute(x)&&path.normalize(x)===x)||!/^[a-f0-9]{40}$/.test(candidate))fail("invalid arguments");
for(const dir of [workspace,build])if(!fs.lstatSync(dir).isDirectory()||fs.realpathSync(dir)!==dir)fail("symlinked scope");
const head=()=>run("/home/an/.cargo/bin/jj",["log","-r","@","--no-graph","-T","commit_id"]).trim();
if(head()!==candidate)fail("candidate differs from current workspace snapshot");
const receipt=JSON.parse(read(build+"/build.json",1000000));
if(receipt.code!==0)fail("full build did not pass");
const bindingsRaw=read(build+"/source-bindings.json",1000000),bindings=JSON.parse(bindingsRaw);
if(!Array.isArray(bindings)||bindings.length<1||bindings.length>2048)fail("invalid source bindings");
const inventory=[];
function walk(dir){for(const d of fs.readdirSync(workspace+"/"+dir,{withFileTypes:true})){const p=dir+"/"+d.name;if(d.isDirectory())walk(p);else if(d.isFile())inventory.push(p);else fail("unsupported source entry")}}
walk("apps/cepaf_gleam/src");
inventory.push("apps/cepaf_gleam/gleam.toml");
if(JSON.stringify(inventory.sort())!==JSON.stringify(bindings.map(x=>x.path).sort()))fail("incomplete full-app source manifest");
const expected=[];
for(const b of bindings){
 if(!inventory.includes(b.path)||!/^[a-f0-9]{64}$/.test(b.sha256))fail("invalid binding");
 const bytes=read(workspace+"/"+b.path,4000000);
 if(hash(bytes)!==b.sha256)fail("source changed since build");
 if(b.path.endsWith(".gleam"))expected.push(b.path.slice("apps/cepaf_gleam/src/".length,-6).replaceAll("/","@"));
 else if(b.path.endsWith(".erl")){const m=bytes.toString("utf8").match(/^-module\(\s*(?:'([^']+)'|([a-zA-Z0-9_@.]+))\s*\)\./m);if(!m)fail("unrecognized Erlang module");expected.push(m[1]||m[2]);}
}
expected.sort();
if(expected.length<1||expected.length>1024||new Set(expected).size!==expected.length)fail("invalid module inventory");
const ebin=build+"/lib/cepaf_gleam/ebin";
const found=fs.readdirSync(ebin).filter(n=>n.endsWith(".beam")).map(n=>n.slice(0,-5)).sort();
if(JSON.stringify(found)!==JSON.stringify(expected))fail("missing or unexpected compiled module");
for(const n of expected)read(ebin+"/"+n+".beam",4000000);
const expression='[Dir]=init:get_plain_arguments(),Files=lists:sort(filelib:wildcard(filename:join(Dir,"*.beam"))),true=length(Files)>0 andalso length(Files)=<1024,Rows=lists:map(fun(F)->{ok,B}=file:read_file(F),true=byte_size(B)=<4000000,{ok,{M,[{imports,I}]}}=beam_lib:chunks(B,[imports]),true=length(I)=<2048,#{name=>atom_to_binary(M,utf8),beam_sha256=>binary:encode_hex(crypto:hash(sha256,B),lowercase),imports=>[[atom_to_binary(A,utf8),atom_to_binary(N,utf8),K]||{A,N,K}<-lists:sort(I)]} end,Files),io:put_chars(json:encode(Rows)),halt().';
const rows=JSON.parse(run("/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl",["+S","2:2","+A","2","-noshell","-eval",expression,"-extra",ebin],15000));
if(JSON.stringify(rows.map(x=>x.name).sort())!==JSON.stringify(expected))fail("compiled module identity mismatch");
if(rows.reduce((n,r)=>n+r.imports.length,0)>32768)fail("import budget");
for(const r of rows)if(hash(read(ebin+"/"+r.name+".beam",4000000))!==r.beam_sha256)fail("beam changed");
const closure=hash(JSON.stringify(rows.map(x=>[x.name,x.beam_sha256]).sort((a,b)=>a[0]<b[0]?-1:a[0]>b[0]?1:0)));
const raw=JSON.stringify({schema:"uos.telegram.impact-snapshot.v1",candidate,closure_sha256:closure,source_kind:"compiled_beam_imports",modules:rows});
if(Buffer.byteLength(raw)>1048576)fail("snapshot size");
if(head()!==candidate)fail("workspace changed during export");
for(const b of bindings)if(hash(read(workspace+"/"+b.path,4000000))!==b.sha256)fail("source changed during export");
fs.writeFileSync(output,raw,{flag:"wx",mode:0o600});
const proof={schema:"uos.telegram.impact-export.v1",observed_at:new Date().toISOString(),candidate,snapshot_sha256:hash(raw),closure_sha256:closure,module_count:rows.length,import_count:rows.reduce((n,r)=>n+r.imports.length,0),source_manifest_sha256:hash(bindingsRaw),snapshot_bytes:Buffer.byteLength(raw),full_build:build,complete_module_set_verified:true,runtime_admission:"NOT_GRANTED"};
fs.writeFileSync(output+".receipt.json",JSON.stringify(proof,null,2)+"\n",{flag:"wx",mode:0o600});
console.log(JSON.stringify(proof));
