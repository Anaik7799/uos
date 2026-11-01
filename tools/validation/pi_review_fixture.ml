#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Ordinary private ledger + actual installed Pi SDK with LOCAL in-memory
   endpoint/SSE fixtures. Never calls a public provider or reads real credentials. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-pi-argon-mcp-20261101"
let lib=root^"/.uos-workspaces/codex-recovery-observed-20261101/var/harness/integrated-ordinary-3b82e8/lib"
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p b=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let replace a b x=match Astring.String.cut~sep:a x with Some(p,q)->if Astring.String.is_infix~affix:a q then failwith"ambiguous fixture replacement";p^b^q|None->failwith"fixture source marker"
let modules=["harness/review_completion";"harness/review_dispatch";"harness/admission";"harness/operations";"harness/successor_mcp";"mcp/registry";"mcp/runtime_gateway";"mcp/route_convergence"]
let ()=
 if Array.length Sys.argv<>2||Sys.argv.(1)<>"--ordinary"then failwith"ordinary mode only";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"pi-review-ordinary-"""in Unix.unlink base;Unix.mkdir base 0o700;mkdir(base^"/case");mkdir(base^"/tmp");
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]and logs=ref[]in
 let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let copy p dst=write dst(capture p)in
 List.iter(fun p->ignore(capture p))[ws^"/tools/validation/pi_review_fixture.ml";ws^"/tools/ecology_budget.ml";root^"/tools/ecology_process.ml";ws^"/tools/pi_review_reserve.ml";root^"/toolchains/nix-profile/bin/node";"/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/package.json";"/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js";"/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/utils/provider-retry.js"];
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"OCAMLPATH",root^"/toolchains/opam-ocaml/lib";"ERL_CRASH_DUMP","/dev/null";"ERL_FLAGS","+S 4:4 +A 2";"TMPDIR",base^"/tmp";"DUNE_CACHE","disabled";"UOS_PI_REVIEW_CASE",base^"/case";"UOS_PI_REVIEW_ROOT",ws]in
 let run ?(input="") ?(mode="merged") ?(expected=0) label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"262144";mode;exe]@args in
  let command=base^"/"^label^"-command.json"in write command(Yojson.Basic.to_string(`List(List.map(fun x->`String x)argv)));
  match Bos.OS.Cmd.run_io~env(Bos.Cmd.of_list argv)(Bos.OS.Cmd.in_string input)|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(out,(_,`Exited n))->let log=base^"/"^label^".log"and status=base^"/"^label^".exit"in write log out;write status(string_of_int n^"\n");logs:=command::log::status::!logs;Printf.printf"%s exit%d\n%!"label n;if n<>expected then failwith(label^" failed; retained "^base);out
  |_->failwith("UNKNOWN retained "^base)in
 let package=base^"/package"in
 write(package^"/gleam.toml")"name = \"pi_review_private\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n[dependencies]\ncepaf_gleam = \">=0.0.0\"\nuos_swarm = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleam_otp = \">=0.0.0\"\ngleam_erlang = \">=0.0.0\"\ngleam_crypto = \">=0.0.0\"\nenvoy = \">=0.0.0\"\nsimplifile = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\n";
 List.iter(fun p->copy(ws^"/apps/cepaf_gleam/src/cepaf_gleam/"^p^".gleam")(package^"/src/cepaf_gleam/"^p^".gleam"))modules;
 copy(ws^"/apps/cepaf_gleam/test/harness_review_completion_test.gleam")(package^"/src/harness_review_completion_test.gleam");
 copy(ws^"/apps/cepaf_gleam/src/pi_review_io.erl")(package^"/src/pi_review_io.erl");
 ignore(run"01-gleam-build"(root^"/toolchains/gleam-1.16.0/bin/gleam")["compile-package";"--target";"erlang";"--package";package;"--out";base^"/out";"--lib";lib]);
 ignore(run"02-ffi-build"(root^"/toolchains/nix-profile/bin/erlc")["-o";base^"/out/ebin";package^"/src/pi_review_io.erl"]);
 let paths=Sys.readdir lib|>Array.to_list|>List.sort String.compare|>List.map(fun n->lib^"/"^n^"/ebin")|>List.filter Sys.file_exists in
 let erl_args=["+S";"4:4";"-noshell"]@List.concat_map(fun p->["-pa";p])paths@["-pa";base^"/out/ebin"]in
 ignore(run"03-prepare-case"(root^"/toolchains/nix-profile/bin/erl")(erl_args@["-eval";"harness_review_completion_test:write_case_files(),halt(0)."]));
 let database=base^"/case/private-budget.sqlite3"in
 ignore(run"04-private-ledger-init"(root^"/toolchains/opam-ocaml/bin/ocaml")[ws^"/tools/ecology_budget.ml";"init";database]);
 if read(ws^"/tools/ecology_budget.ml")<>capture(root^"/tools/ecology_budget.ml")then failwith"canonical budget source differs";
 let private_reserver=replace "root^\"/var/ecology/openrouter_budget.sqlite3\"" (Printf.sprintf "%S" database) (capture(ws^"/tools/pi_review_reserve.ml"))in
 write(base^"/private-reserver.ml")private_reserver;
 let reservation=run"05-real-private-reservation"(root^"/toolchains/opam-ocaml/bin/ocaml")[base^"/private-reserver.ml";read(base^"/case/ledger-request.json")]in
 let receipt=Yojson.Basic.from_string reservation in
 if Yojson.Basic.Util.member"status"receipt<>`String"reserved"||Yojson.Basic.Util.member"reservation_nanodollars"receipt<>`Int 250000000 then failwith"private reservation not real";
 write(base^"/case/reservation.json")reservation;
 let duplicate=run~expected:1~input:(read(base^"/case/ledger-request.json"))"05a-ordinary-duplicate-logical-id"(root^"/toolchains/opam-ocaml/bin/ocaml")[ws^"/tools/ecology_budget.ml";"reserve";database]in
 if Yojson.Basic.Util.member"reason"(Yojson.Basic.from_string duplicate)<>`String"duplicate_call_id"then failwith"duplicate not refused";
 let retained=run"05b-retained-liability-status"(root^"/toolchains/opam-ocaml/bin/ocaml")[ws^"/tools/ecology_budget.ml";"status";database]in
 let retained=Yojson.Basic.from_string retained in
 if Yojson.Basic.Util.member"reservation_count"retained<>`Int 1||Yojson.Basic.Util.member"daily_reserved_nanodollars"retained<>`Int 250000000 then failwith"liability changed";
 let worker=capture(ws^"/apps/cepaf_gleam/priv/uos_pi_review_once.mjs")in
 let mock={js|
// PRIVATE ordinary local fixture; NOT a production provider, key or price proof.
process.env.OPENROUTER_API_KEY='PUBLIC_FIXTURE_NOT_A_CREDENTIAL';
let localGets=0,localPosts=0;
const providerFetch=async(url,options)=>{
 if(String(url)==='https://openrouter.ai/api/v1/models/google/gemini-4-argon/endpoints') {
  localGets++;return new Response(JSON.stringify({data:{id:'google/gemini-4-argon',endpoints:[{tag:'google-ai-studio',supports_zdr:true,pricing:{prompt:'0.000002',completion:'0.000010',request:'0'}}]}}),{status:200});
 }
 if(String(url)==='https://openrouter.ai/api/v1/chat/completions'&&options.method==='POST') {
  localPosts++;
  const chunks=[{id:'gen-ordinary-fixture',model:'google/gemini-4-argon',choices:[{index:0,delta:{role:'assistant',content:'Ordinary fixture advisory'},finish_reason:null}]},
    {id:'gen-ordinary-fixture',model:'google/gemini-4-argon',choices:[{index:0,delta:{},finish_reason:'stop'}],usage:{prompt_tokens:32,completion_tokens:7,total_tokens:39}}];
  return new Response(chunks.map(x=>'data: '+JSON.stringify(x)+'\n\n').join('')+'data: [DONE]\n\n',{status:200,headers:{'content-type':'text/event-stream'}});
 }
 throw new Error('LOCAL_FIXTURE_UNKNOWN_ENDPOINT');
};
process.on('exit',()=>{if(localPosts!==1||localGets!==1)process.exitCode=2;});
|js}in
 let fixture=replace"const providerFetch = globalThis.fetch;"mock worker in
 write(base^"/pi-sdk-local-fixture.mjs")fixture;
 let body=read(base^"/case/body.json")in let n=String.length body in let frame=Bytes.create(n+4)in
 for i=0 to 3 do Bytes.set frame i(Char.chr((n lsr((3-i)*8))land 255))done;Bytes.blit_string body 0 frame 4 n;
 let reply=run~mode:"framed"~input:(Bytes.to_string frame)"06-actual-pi-sdk-local-completion"(root^"/toolchains/nix-profile/bin/node")[base^"/pi-sdk-local-fixture.mjs"]in
 write(base^"/case/pi-reply.json")reply;
 let loaded=List.map(fun p->"cepaf_gleam@"^String.concat"@"(String.split_on_char '/'p))modules@["harness_review_completion_test";"pi_review_io"]in
 let pins_eval=String.concat","(List.map(fun m->Printf.sprintf"%S=code:which('%s')"(base^"/out/ebin/"^m^".beam")m)loaded)in
 let output=run"07-ordinary-tests"(root^"/toolchains/nix-profile/bin/erl")(erl_args@["-eval";pins_eval^",case eunit:test(harness_review_completion_test,[verbose])of ok->halt(0);_->halt(2)end."])in
 if not(Astring.String.is_infix~affix:"All 6 tests passed"output)then failwith"ordinary marker";
 List.iter(fun(p,h)->if sha(read p)<>h then failwith("source drift "^p))!pins;
 let file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let receipt=base^"/receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.pi-review-private-development.v1";"author",`String"LOCAL_CODEX_RELAY";"authority",`String"NONE";"production_transport",`String"UNAVAILABLE_SOURCE_GATE";
 "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);
 "logs",`List(List.map file !logs);"actual_local_sdk_worker",file(base^"/pi-sdk-local-fixture.mjs");"actual_private_reserver",file(base^"/private-reserver.ml");
 "facts",`List(List.map(fun p->file(base^"/case/"^p))["body.json";"ledger-request.json";"reservation.json";"pi-reply.json"]);
 "ordinary_tests",`Int 6;"duplicate_logical_id",`String"REFUSED_RETAINED_ONE_ROW";"actual_public_provider_calls",`Int 0;"actual_credentials_used",`Bool false;
 "limits",`List(List.map(fun x->`String x)["Actual installed Pi1.4 SDK parser called through explicit local in-memory endpoint/SSE fixtures; one fetchPOST and one catalogGET in that fixture, not live provider eligibility/ZDR/billing or cryptographic runtime attestation.";"Existing canonical ledger implementation used on a NEW private synthetic DB only. $0.25 retained liability is separate from strict<$0.02 per-request worst-case and$10/day ledger ceiling; no canonical DB mutation/refund.";"Core IO callback authorization is test DATA, not real task/grant proof. Actual existing gateway refuses missing grant. Authenticated paid dispatch UNRUN and impossible through current production readiness source gate.";"Generic inherited-env transport, postcatalogeffect-timefence, transitiveSDK/runtime closure and actualZDR/price eligibility remain unverified. No source gate override or live-ready claim.";"Eight-module compile overlay on earlier reviewed dependencies; no fresh full app closure, powerloss/cgroup/hostileFS/timing/fullproof claim. No flagged fault/concurrent/partial-cache/adversarial/mutant tests.";"No real keys, task mutation, canonicalDB/runtime/config/JJ changes, package install or new external inference. SDKmodel/catalog traffic is replaced locally; not an OSnetworknamespace proof. LocalCodex cost UNKNOWN."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
