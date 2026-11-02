#use "topfind";;
#require "bos,cryptokit,yojson";;
(* LOCAL Codex relay. @agent_intent: private cached build and actual packaged
   launch tests only. No production configuration/DB/task/VCS/network effects.
   @laws: closed env equality, no fallback, actual fd closure/cleanup/framing,
   deadline preparation refusal. Mutation fixtures never edit production bytes.
   Args SOURCE_ROOT TOOLCHAIN_ROOT. Outer OS guardian bounds this whole fixture.
   No compiler-closure, same-UID adversary, Nix lifetime or admission proof. *)
let require b s=if not b then failwith s
let ()=require(Array.length Sys.argv=3)"usage: finite_native_launch_fixture.ml SOURCE_ROOT TOOLCHAIN_ROOT"
let source=Unix.realpath Sys.argv.(1)and tc=Unix.realpath Sys.argv.(2)
let base=Filename.temp_file ~temp_dir:"/tmp" "uos-finite-native-fixture-" ""
let ()=Unix.unlink base;Unix.mkdir base 0o700
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->
 let n=in_channel_length c in require(n<=1048576)"fixture read bound";really_input_string c n)
let write p s=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->let rec put n=if n<String.length s then
 let k=Unix.write_substring fd s n(String.length s-n)in require(k>0)"write";put(n+k)in put 0;Unix.fsync fd)
let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let replace a b s=match Astring.String.cut ~sep:a s with
 |Some(x,y)->require(not(Astring.String.is_infix ~affix:a y))"unique fixture patch";x^b^y
 |_->failwith("fixture patch missing: "^a)
let env=Astring.String.Map.of_list["PATH",tc^"/toolchains/nix-profile/bin:/usr/bin:/bin";
 "OCAMLPATH",tc^"/toolchains/opam-ocaml/lib";"LANG","C.UTF-8";"ERL_CRASH_DUMP","/dev/null";
 "UOS_FINITE_NATIVE_FIXTURE",base]
let sequence=ref 0
let run ?(extra=[]) ?(timeout=20000) ?(expected=0) label exe args=
 incr sequence;
 let environment=List.fold_left(fun e(k,v)->Astring.String.Map.add k v e)env extra in
 let argv=[tc^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";source^"/tools/ecology_process.ml";
 string_of_int timeout;"1048576";"merged";exe]@args in
 match Bos.OS.Cmd.run_out ~env:environment(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string ~trim:false with
 |Ok(text,(_,`Exited code))->let log=base^"/"^Printf.sprintf "%02d-%s.log" !sequence label in
   write log text;require(code=expected)(label^" failed code="^string_of_int code^" log="^log);text
 |_->failwith(label^" unknown")
let ()=
 let paths=["native/c/finite_environment_launch.c";"tools/ecology_native_build.ml";"tools/ecology_release.ml";
  "apps/cepaf_gleam/src/telegram_store_transport_ffi.erl";
  "apps/cepaf_gleam/src/cepaf_gleam/harness/native_launch.gleam";
  "apps/cepaf_gleam/src/cepaf_gleam/harness/telegram_store_transport.gleam";
  "apps/cepaf_gleam/test/harness_native_launch_test.gleam";
  "tools/validation/finite_native_launch_test.erl";"tools/validation/finite_native_launch_fixture.ml"]in
 let sources=List.map(fun p->p,read(source^"/"^p))paths in
 let get p=List.assoc p sources in
 let raw=run ~timeout:60000 "artifact"(tc^"/toolchains/opam-ocaml/bin/ocaml")
  [source^"/tools/ecology_native_build.ml";"build";source;tc]in
 let artifact=Yojson.Safe.from_string raw in
 let dir=Yojson.Safe.Util.(member "directory"artifact|>to_string)in
 let artifact_id=Yojson.Safe.Util.(member "artifact_id"artifact|>to_string)in
 let extra=["UOS_FINITE_NATIVE_ARTIFACT",dir]in
 List.iter(fun p->Unix.mkdir(base^"/"^p)0o700)
  ["project";"project/src";"project/src/cepaf_gleam";"project/src/cepaf_gleam/harness";"ebin"];
 write(base^"/project/gleam.toml")"name = \"finite_native_fixture\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \">= 0.0.0\"\ngleeunit = \">= 0.0.0\"\n";
 List.iter(fun p->write(base^"/project/src/"^p)(get("apps/cepaf_gleam/src/"^p)))
  ["cepaf_gleam/harness/native_launch.gleam";"cepaf_gleam/harness/telegram_store_transport.gleam";"telegram_store_transport_ffi.erl"];
 write(base^"/project/src/harness_native_launch_test.gleam")(get"apps/cepaf_gleam/test/harness_native_launch_test.gleam");
 ignore(run "gleam-compile"(tc^"/toolchains/gleam-1.16.0/bin/gleam")
  ["compile-package";"--target";"erlang";"--package";base^"/project";"--out";base^"/out";
   "--lib";tc^"/apps/indrajaal_gleam_web/build/dev/erlang"]);
 let ffi=get"apps/cepaf_gleam/src/telegram_store_transport_ffi.erl"in
 let delayed=ffi|>replace "-module(telegram_store_transport_ffi)." "-module(finite_transport_delayed)."
  |>replace "     %% No inherited-environment snapshot/overlay is a safety premise here."
   "     timer:sleep(5100),\n     %% No inherited-environment snapshot/overlay is a safety premise here."
  |>replace "     Port=open_port({spawn_executable,binary_to_list(Launcher)},"
   (Printf.sprintf "     ok=file:write_file(%S,<<\"PRIVATE\">>),\n     Port=open_port({spawn_executable,binary_to_list(Launcher)},"(base^"/spawn-boundary.marker"))in
 write(base^"/finite_transport_delayed.erl")delayed;
 write(base^"/finite_native_launch_test.erl")(get"tools/validation/finite_native_launch_test.erl");
 write(base^"/probe.c"){c|#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
extern char **environ;
static int exact(void*b,size_t n){char*p=b;while(n){ssize_t k=read(0,p,n);if(k<=0)return 0;p+=k;n-=k;}return 1;}
int main(int argc,char**argv){unsigned char h[4];if(argc!=2||!exact(h,4))return 2;
uint32_t n=((uint32_t)h[0]<<24)|((uint32_t)h[1]<<16)|((uint32_t)h[2]<<8)|h[3];if(n!=2)return 3;char req[2];if(!exact(req,2)||memcmp(req,"{}",2))return 4;
if(strstr(argv[0],"sleep_probe"))sleep(10);
const char*want[]={"PATH=/nonexistent","LANG=C","LC_ALL=C","TZ=UTC",0};int count=0,ok=1;
for(char**e=environ;*e;e++){count++;int found=0;for(int i=0;want[i];i++)if(!strcmp(*e,want[i]))found=1;if(!found)ok=0;}
int closed=fcntl(99,F_GETFD)==-1&&errno==EBADF;char body[128];
int printed=snprintf(body,sizeof body,"{\"exact_environment\":%s,\"fd99_closed\":%s}",ok&&count==4?"true":"false",closed?"true":"false");
if(printed<=0||printed>=(int)sizeof body)return 6;size_t len=(size_t)printed;unsigned char out[4]={len>>24,len>>16,len>>8,len};if(write(1,out,4)!=4||write(1,body,len)!=(ssize_t)len)return 5;return 0;}
|c};
 write(base^"/fd_parent.c"){c|#include <unistd.h>
#include <fcntl.h>
extern char **environ;
int main(int n,char**v){if(n!=9)return 3;int f=open(v[1],O_CREAT|O_RDWR,0600);if(f<0||dup2(f,99)!=99)return 4;if(f!=99)close(f);execve(v[2],v+2,environ);return 127;}
|c};
 write(base^"/fd_guard_probe.c"){c|#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
int main(void){if(fcntl(99,F_GETFD)==-1&&errno==EBADF){write(1,"FD_CLOSED",9);return 0;}write(1,"FD_OPEN",7);return 2;}
|c};
 write(base^"/poison.c")(Printf.sprintf "#include <fcntl.h>\n#include <unistd.h>\n__attribute__((constructor)) static void m(void){int f=open(%S,O_CREAT|O_WRONLY|O_EXCL,0600);if(f>=0){write(f,\"PRIVATE\",7);close(f);}}\n"(base^"/preload.marker"));
 let gcc="/nix/store/w88q44gqd1qg5wmkk7v0h97rpiqvam0l-gcc-wrapper-15.3.0/bin/gcc"in
 List.iter(fun name->ignore(run(name^"-compile")gcc["-O2";base^"/"^name^".c";"-o";base^"/"^name]))["probe";"fd_parent";"fd_guard_probe"];
 write(base^"/sleep_probe")(read(base^"/probe"));Unix.chmod(base^"/sleep_probe")0o700;
 ignore(run "poison-compile"gcc["-shared";"-fPIC";base^"/poison.c";"-o";base^"/poison.so"]);
 ignore(run "eunit-compile"(tc^"/toolchains/nix-profile/bin/erlc")["-Werror";"-o";base^"/ebin";base^"/finite_transport_delayed.erl";base^"/finite_native_launch_test.erl"]);
 let libs=tc^"/apps/indrajaal_gleam_web/build/dev/erlang"in
 let ebins=Sys.readdir libs|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=libs^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let common=["+S";"2:2";"-noshell";"-pa"]@ebins@["-pa";base^"/out/ebin";base^"/ebin"]in
 let log=run ~extra ~timeout:30000 "tests"(tc^"/toolchains/nix-profile/bin/erl")
  (common@["-eval";"io:format(\"OTP=~s ERTS=~s~n\",[erlang:system_info(otp_release),erlang:system_info(version)]),case eunit:test([harness_native_launch_test,finite_native_launch_test],[verbose])of ok->halt(0);_->halt(2)end."])in
 require(Astring.String.is_infix ~affix:"All 14 tests passed."log)"expected fourteen actual test groups";
 (* Independently observable mutants: each compiles, then the relevant actual
    boundary test must fail. No production source/binary replacement. *)
 let c=get"native/c/finite_environment_launch.c"in
 let flags=["-nostdlib";"-static";"-no-pie";"-ffreestanding";"-fno-builtin";
  "-fno-stack-protector";"-fno-pie";"-mno-red-zone";"-O2";"-Wall";"-Wextra";"-Werror";
  "-Wl,--build-id=none";"-Wl,-e,_start";"-Wl,-z,noexecstack"]in
 let compile_variant name text=write(base^"/"^name^".c")text;
  ignore(run(name^"-compile")gcc(flags@[base^"/"^name^".c";"-o";base^"/"^name]))in
 let inherit_env=c|>replace
  "static char *environment[]={\"PATH=/nonexistent\", \"LANG=C\", \"LC_ALL=C\", \"TZ=UTC\", 0};\n" ""
  |>replace "(long)environment" "(long)(stack+stack[0]+2)"in
 compile_variant "mutant-inherit"inherit_env;
 compile_variant "mutant-fd"(replace "  if(call3(436,3,0xffffffffUL,0)!=0)refuse();\n" "" c);
 let test=get"tools/validation/finite_native_launch_test.erl"in
 let replace_all a b text=String.concat b(Astring.String.cuts ~sep:a text)in
 List.iter(fun(name,which)->let module_name="finite_"^name^"_test"in
   let executable="mutant-"^name in
   let code=test|>replace "-module(finite_native_launch_test)." ("-module("^module_name^").")
    |>replace_all "artifact()++\"/finite_launcher.exe\"" ("base()++\"/"^executable^"\"")in
   write(base^"/"^module_name^".erl")code;
   ignore(run(module_name^"-compile")(tc^"/toolchains/nix-profile/bin/erlc")["-Werror";"-o";base^"/ebin";base^"/"^module_name^".erl"]);
   let failed=run ~extra ~expected:2(module_name^"-killed")(tc^"/toolchains/nix-profile/bin/erl")
    (common@["-eval";"case eunit:test(fun "^module_name^":"^which^"/0,[verbose])of ok->halt(0);_->halt(2)end."])in
   require(Astring.String.is_infix ~affix:"Failed: 1" failed)"mutant must fail exactly targeted group"
  )["inherit","finite_environment_and_legacy_separation_test";"fd","extra_inherited_descriptor_closed_before_guardian_test"];
 let delay_mutant=delayed|>replace
  "     true=Remaining>0,\n     ok=file:write_file" "     ok=file:write_file"in
 Unix.unlink(base^"/finite_transport_delayed.erl");write(base^"/finite_transport_delayed.erl")delay_mutant;
 ignore(run "deadline-mutant-compile"(tc^"/toolchains/nix-profile/bin/erlc")
  ["-Werror";"-o";base^"/ebin";base^"/finite_transport_delayed.erl"]);
 let failed=run ~extra ~expected:2 ~timeout:10000 "deadline-mutant-killed"(tc^"/toolchains/nix-profile/bin/erl")
  (common@["-eval";"case eunit:test({generator,fun finite_native_launch_test:expired_preparation_never_starts_launcher_test_/0},[verbose])of ok->halt(0);_->halt(2)end."])in
 require(Astring.String.is_infix ~affix:"Failed: 1" failed && Sys.file_exists(base^"/spawn-boundary.marker"))"deadline mutant must expose actual spawn boundary";
 compile_variant "unsupported-close-range"(replace "call3(436,3,0xffffffffUL,0)" "call3(999999,3,0xffffffffUL,0)" c);
 ignore(run ~expected:127 "unsupported-close-range-refused"(base^"/unsupported-close-range")
  ["linux-x86_64";"native-storage-v1";dir^"/guardian.exe";base^"/probe";base^"/public-config";"3000"]);
 write(base^"/unsupported-architecture.c")c;
 let rejected=run ~expected:1 "unsupported-architecture-compile-refused"gcc
  (flags@["-U__x86_64__";base^"/unsupported-architecture.c";"-o";base^"/unsupported-architecture"])in
 require(Astring.String.is_infix ~affix:"supports Linux x86_64 only"rejected && not(Sys.file_exists(base^"/unsupported-architecture")))"unsupported compiler architecture must refuse";
 List.iter(fun(p,text)->require(read(source^"/"^p)=text)"source drift")sources;
 let receipt=`Assoc["schema",`String"uos.finite-native-launch-fixture.v1";"attribution",`String"LOCAL_CODEX_RELAY";
  "status",`String"SCOPED_PASS";"fixture",`String base;"artifact_id",`String artifact_id;
  "sources",`List(List.map(fun(p,text)->`Assoc["path",`String p;"sha256",`String(sha text)])sources);
  "tests_log_sha256",`String(sha log);"authority",`String"NONE";"activation",`String"HOLD";
  "mutations",`List(List.map(fun s->`String s)["inherited envp: compile0, targeted test2";"omitted close_range: compile0, fd99 test2";"omitted deadline guard: compile0, actual spawn boundary test2"]);
  "negative_controls",`List(List.map(fun s->`String s)["unsupported close_range syscall: exit127/no fallback";"unsupported compiler architecture: compile1/no executable"]);
  "limits",`List(List.map(fun s->`String s)["Linux x86_64 / close_range only; no other architecture supported.";
   "Same-UID mutable paths and trusted parent BEAM startup remain external premises.";
   "Observed current profile Nix rooting is not independently managed release-lifetime retention.";
   "Local regular-filesystem/kernel scheduling and cgroup cleanup premises remain.";
   "Legacy transport retains separate denylist behavior; no service config changes."])]in
 write(base^"/receipt.json")(Yojson.Safe.pretty_to_string receipt^"\n");print_endline(base^"/receipt.json")
