(* Fixed native templates interpret only parsed expressions/tactics. Execution
   is delegated to the existing bounded ecology process-group guardian. This
   is not a sandbox for arbitrary programs; the parser is the source boundary. *)
open Openrouter_eval_expr
open Openrouter_eval_catalog
open Openrouter_eval_validate
type status = Passed | Failed | Unsupported | Unrun | Not_required
type execution={code:int;output:string;elapsed:float}
type evidence={status:status;tool:string;version:string;detail:string;executions:execution list;identity:Yojson.Safe.t}
let root="/home/an/NAS-setup/uos"
let tc=root^"/toolchains"
let tool = function
 | Gleam_case->tc^"/gleam-1.16.0/bin/gleam"
 | Ocaml_case|Stm_case|Bayesian_case|Rete_case|Stpa_case|Fmea_case->tc^"/opam-ocaml/bin/ocamlopt"
 | Mojo_case->root^"/services/inference/max/.pixi/envs/default/bin/mojo"
 | Lean_case->tc^"/lean-4.33.0/bin/lean"
 | Quint_case->tc^"/nix-profile/bin/quint"
let status_name=function Passed->"passed"|Failed->"failed"|Unsupported->"unsupported"|Unrun->"unrun"|Not_required->"not_required"
let requires_native=function Gleam_case|Ocaml_case|Mojo_case|Lean_case|Quint_case->true|Stm_case|Bayesian_case|Rete_case|Stpa_case|Fmea_case->false
let none status detail={status;tool="";version="";detail;executions=[];identity=`Null}
(* Stream public tool bytes, including the 139MB Mojo executable. Refuse a
   changed file instead of attesting a partial or moving executable. *)
let tool_identity path =
 let stable_fields stat=(stat.Unix.st_dev,stat.st_ino,stat.st_kind,stat.st_perm,stat.st_uid,stat.st_gid,stat.st_size,stat.st_mtime,stat.st_ctime) in
 let realpath=Unix.realpath path in
 let input=open_in_bin realpath in
 Fun.protect(fun()->
  let before=Unix.fstat(Unix.descr_of_in_channel input) in
  require(before.Unix.st_kind=Unix.S_REG && before.st_size>0 && before.st_size<=536870912) "tool identity byte bound";
  let sha=Cryptokit.hash_channel(Cryptokit.Hash.sha256())~len:before.st_size input |> Cryptokit.transform_string(Cryptokit.Hexa.encode()) in
  let after=Unix.fstat(Unix.descr_of_in_channel input) in
  require(stable_fields before=stable_fields after && Unix.realpath path=realpath && stable_fields(Unix.stat realpath)=stable_fields before) "tool changed during attestation";
  `Assoc["path",`String path;"realpath",`String realpath;"bytes",`Int before.st_size;"sha256",`String sha;"closure_scope",`String "Executable or wrapper bytes; transitive libraries are not independently rehashed"]
 )~finally:(fun()->close_in_noerr input)
let mkdir path=Unix.mkdir path 0o700
let scratch()=let p=Filename.temp_file "uos-openrouter-case-" "" in Unix.unlink p;mkdir p;p
let write path contents=
 let channel=open_out_gen[Open_wronly;Open_creat;Open_excl;Open_binary]0o600 path in
 Fun.protect(fun()->output_string channel contents)~finally:(fun()->close_out_noerr channel)
let read path=
 let stat=Unix.lstat path in require(stat.Unix.st_kind=Unix.S_REG && stat.st_size<=1048576)"native fixture input bound";
 let channel=open_in_bin path in Fun.protect(fun()->really_input_string channel stat.st_size)~finally:(fun()->close_in_noerr channel)
let environment directory =
 [|"PATH="^tc^"/nix-profile/bin:"^tc^"/opam-ocaml/bin:"^tc^"/gleam-1.16.0/bin:/usr/bin:/bin";
   "LANG=C.UTF-8";"ERL_FLAGS=+S 4:4 +A 4";"ERL_CRASH_DUMP=/dev/null";
   "TMPDIR="^directory;"XDG_CACHE_HOME="^directory^"/cache";
   "MODULAR_HOME="^root^"/services/inference/max/.pixi/envs/default/share/max"|]
let run ?(milliseconds=30000) directory executable args =
 require(milliseconds>0 && milliseconds<=30000)"native deadline bound";
 let guardian=tc^"/opam-ocaml/bin/ocaml" in
 let argv=Array.of_list([guardian;"-I";"+unix";root^"/tools/ecology_process.ml";string_of_int milliseconds;"1048576";"merged";executable]@args) in
 let started=Mtime_clock.elapsed() in
 let r,w=Unix.pipe~cloexec:true() in
 let pid=Unix.fork() in
 if pid=0 then (try Unix.close r;Unix.chdir directory;Unix.dup2 w Unix.stdout;Unix.dup2 w Unix.stderr;Unix.close w;
   let input=Unix.openfile"/dev/null"[Unix.O_RDONLY]0 in Unix.dup2 input Unix.stdin;Unix.close input;
   Unix.execve guardian argv(environment directory) with _->Unix._exit 127);
 Unix.close w;
 let channel=Unix.in_channel_of_descr r in
 let bytes=Bytes.create 8192 and output=Buffer.create 4096 in
 let rec collect()=let count=input channel bytes 0(Bytes.length bytes)in
  if count>0 then(require(Buffer.length output+count<=1052672)"guardian output bound";Buffer.add_subbytes output bytes 0 count;collect())in
 let result=try collect();close_in_noerr channel; snd(Unix.waitpid[]pid) with e->
  (try Unix.kill pid Sys.sigterm with _->());(try ignore(Unix.waitpid[]pid)with _->());close_in_noerr channel;raise e in
 let code=match result with Unix.WEXITED c->c|Unix.WSIGNALED _|Unix.WSTOPPED _->125 in
 {code;output=Buffer.contents output;elapsed=Mtime.Span.to_float_ns(Mtime.Span.abs_diff(Mtime_clock.elapsed())started)/.1e9}
let literal language value=match value with Number n->if n<0 then(if language=Gleam then"{"else"(")^string_of_int n^(if language=Gleam then"}"else")")else string_of_int n|Boolean b->if language=Gleam||language=Mojo then(if b then"True"else"False")else string_of_bool b
let call c language environment =
 let arguments=List.map(fun name->literal language(List.assoc name environment))(variables c.domain) in
 if language=Ocaml then "candidate "^String.concat " " arguments else "candidate("^String.concat ", " arguments^")"
let template c fragment =match fragment,c.domain with
 | Expression expression,Gleam_case ->
   let code="pub fn candidate(requested: Int, limit: Int, permitted: Bool) -> Bool { "^render Gleam expression^" }\npub fn main() -> Nil {\n" in
   code^String.concat "\n"(List.map(fun(e,v)->"  let assert "^literal Gleam v^" = "^call c Gleam e)(samples c))^"\n  Nil\n}\n"
 | Expression expression,Ocaml_case ->
   "let candidate now expires token epoch expected version = "^render Ocaml expression^"\nlet () =\n"^
   String.concat "\n"(List.map(fun(e,v)->" assert (("^call c Ocaml e^") = "^literal Ocaml v^");")(samples c))^"\n print_endline \"NATIVE_BEHAVIOR_PASS\"\n"
 | Expression expression,Mojo_case ->
   "from std.testing import assert_equal\ndef candidate(value: Int, lower: Int, upper: Int) -> Int:\n    return "^render Mojo expression^"\ndef main() raises:\n"^
   String.concat "\n"(List.map(fun(e,v)->"    assert_equal("^call c Mojo e^", "^literal Mojo v^")")(samples c))^"\n    print(\"NATIVE_BEHAVIOR_PASS\")\n"
 | Proof proof,Lean_case ->
   "set_option maxRecDepth 1000\ntheorem stale_after_commit (version expected : Nat) (same : version = expected) : version + 1 ≠ expected := "^proof^"\n#print axioms stale_after_commit\n"
 | Expression expression,Quint_case ->
   "module openrouter_eval {\n pure def candidate(held:int, granted:int):bool = "^render Quint expression^"\n var held:int\n var granted:int\n action init=all{held'=0,granted'=0}\n action take=all{candidate(held,granted),held'=1,granted'=granted+1}\n action release=all{held'=0,granted'=granted}\n action step=any{take,release}\n val inv=held>=0 and held<=1 and granted>=0 and granted<=2\n"^
   String.concat "\n"(List.mapi(fun i(e,v)->" run behavior"^string_of_int i^"Test=init.expect("^call c Quint e^" == "^literal Quint v^")")(samples c))^
   "\n run productiveTest=init.then(take).then(release).then(take).expect(granted==2 and held==1 and inv)\n}\n"
 | _,_ -> reject "native template does not match parsed case"
let contains source fragment=
 let len=String.length fragment in
 let rec loop i=i+len<=String.length source && (String.sub source i len=fragment || loop(i+1))in loop 0
let witness domain combined=match domain with
 | Lean_case ->
   let lines=String.split_on_char '\n' combined |> List.filter(fun line->contains line "stale_after_commit" && (contains line "axioms")) in
   (match lines with [line]->List.mem(String.trim line)[
     "'stale_after_commit' does not depend on any axioms";
     "'stale_after_commit' depends on axioms: [propext]";
     "'stale_after_commit' depends on axioms: [Quot.sound]";
     "'stale_after_commit' depends on axioms: [propext, Quot.sound]";
     "'stale_after_commit' depends on axioms: [Quot.sound, propext]"]|_->false)
 | Quint_case -> contains combined "7 passing" && List.for_all(fun name->contains combined name)["behavior0Test";"behavior1Test";"behavior2Test";"behavior3Test";"behavior4Test";"behavior5Test";"productiveTest"]
 | Ocaml_case|Mojo_case -> contains combined "NATIVE_BEHAVIOR_PASS"
 | Gleam_case -> contains combined "Running openrouter_eval_fixture.main"
 | Stm_case|Bayesian_case|Rete_case|Stpa_case|Fmea_case -> false
let availability executable =
 if Sys.file_exists executable then None else Some{(none Unsupported "Pinned tool absent; no fallback or download")with tool=executable}
let run_case c validation =
 if not(requires_native c.domain)then none Not_required (if c.domain=Rete_case then "Independent relational semantics only; full Rete-UL network/unlinking is unsupported by the canonical naive matcher" else "Independent OCaml behavioral oracle")
 else if not(passed validation)then none Unrun "Semantic precheck failed; native execution skipped"
 else
 let executable=tool c.domain in
 if not(Sys.file_exists executable)then {(none Unsupported "Pinned tool absent; no fallback or download")with tool=executable}
 else
 let identity=tool_identity executable in
 let directory=scratch() in
 let version_args=if c.domain=Ocaml_case then["-version"]else["--version"]in
 let version_run=run directory executable version_args in
 if version_run.code<>0 then {status=Unsupported;tool=executable;version="";detail="Pinned tool identity check failed";executions=[version_run];identity}
 else
 let version=String.trim version_run.output in
 let source=template c validation.fragment in
 let checks=match c.domain with
 | Gleam_case ->
   mkdir(directory^"/src");write(directory^"/gleam.toml")"name = \"openrouter_eval_fixture\"\nversion = \"1.0.0\"\ntarget = \"erlang\"\n";
   write(directory^"/src/openrouter_eval_fixture.gleam")source;
   [run directory executable["run";"--target";"erlang"]]
 | Ocaml_case ->
   write(directory^"/fixture.ml")source;
   let compiled=run directory executable["-w";"+8";"-warn-error";"+8";"-o";directory^"/fixture";directory^"/fixture.ml"]in
   if compiled.code=0 then [compiled;run directory(directory^"/fixture")[]]else[compiled]
 | Mojo_case ->write(directory^"/fixture.mojo")source;[run directory executable["run";"--num-threads";"1";"-O0";"-I";root^"/services/inference/max/.pixi/envs/default/lib/mojo";directory^"/fixture.mojo"]]
 | Lean_case ->write(directory^"/fixture.lean")source;[run directory executable["-j";"1";"-M";"512";"-T";"1000000";directory^"/fixture.lean"]]
 | Quint_case ->
   write(directory^"/fixture.qnt")source;
   [run directory executable["test";directory^"/fixture.qnt";"--backend=typescript";"--seed=1";"--max-samples=1"]]
 | Stm_case|Bayesian_case|Rete_case|Stpa_case|Fmea_case -> [] in
 let stable_identity=tool_identity executable=identity in
 let all_zero=checks<>[] && List.for_all(fun e->e.code=0)checks && stable_identity in
 let combined=String.concat "\n"(List.map(fun e->e.output)checks)in
 let witnessed=witness c.domain combined in
 {status=(if all_zero && witnessed then Passed else Failed);tool=executable;version;
  detail=(if all_zero && witnessed then (if c.domain=Quint_case then"Seven named bounded scenarios executed; not exhaustive temporal verification"else if c.domain=Lean_case then "Fixed theorem checked with only explicitly permitted foundational axioms propext/Quot.sound; actual dependencies in output" else"Parsed fixed template passed native checking and behavioral assertions")else"Native failure, changed executable or missing nonvacuous execution witness");executions=version_run::checks;identity}
let evidence_json evidence=`Assoc[
 "status",`String(status_name evidence.status);"tool",`String evidence.tool;"version",`String evidence.version;"detail",`String evidence.detail;"identity",evidence.identity;
 "executions",`List(List.map(fun e->`Assoc["exit_code",`Int e.code;"elapsed_seconds",`Float e.elapsed;"output",`String e.output])evidence.executions)]
