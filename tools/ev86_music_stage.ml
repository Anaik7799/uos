#use "topfind";;
#require "unix,yojson,cryptokit";;
let ws="/home/an/NAS-setup/uos/.uos-workspaces/ev98-wire-codec-20260909"
let revision=Sys.argv.(1)
let stage=Sys.argv.(2)
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c(in_channel_length c))
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o755)
let write p b=mkdir(Filename.dirname p);let c=open_out_bin p in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c b)
let records=ref[]
let copy a b=let bytes=read a in write b bytes;records:=`Assoc["source",`String a;"staged",`String b;"sha256",`String(sha bytes);"bytes",`Int(String.length bytes)]::!records
let rec tree a b=match(Unix.lstat a).st_kind with Unix.S_REG->copy a b|Unix.S_DIR->Array.iter(fun n->tree(a^"/"^n)(b^"/"^n))(Sys.readdir a)|_->failwith("nonregular input "^a)
let candidate path dest=
 let root="/home/an/NAS-setup/uos" in
 let receipt=stage^"/source-"^string_of_int(List.length!records)^".json"in
 let exe=root^"/toolchains/opam-ocaml/bin/ocamlrun"in
 let args=[exe;root^"/toolchains/opam-ocaml/bin/ocaml";root^"/.uos-workspaces/codex-ev-admission-20260909-0210/tools/ev_native.ml";"--cwd";ws;"--seconds";"30";"--receipt";receipt;"--";"jj";"--ignore-working-copy";"file";"show";"-r";"commit_id(\""^revision^"\")";"root:"^path]in
 let sink=Unix.openfile"/dev/null"[Unix.O_WRONLY]0 in
 let child=Unix.create_process exe(Array.of_list args)Unix.stdin sink Unix.stderr in Unix.close sink;
 if snd(Unix.waitpid[]child)<>Unix.WEXITED 0 then failwith("candidate read "^path);
 let j=Yojson.Safe.from_file receipt in let bytes=Yojson.Safe.Util.(j |> member"output" |> to_string)in
 write dest bytes;records:=`Assoc["source",`String("candidate:"^revision^":"^path);"staged",`String dest;"sha256",`String(sha bytes);"bytes",`Int(String.length bytes)]::!records
let ()=if not(String.starts_with ~prefix:"/tmp/" stage) || Sys.file_exists stage then failwith"fresh private full package required";
if String.length revision<>40 || not(String.for_all(fun c->(c>='0'&&c<='9')||(c>='a'&&c<='f'))revision)then failwith"full commit ID required";
mkdir stage;
List.iter(fun p->candidate("apps/indrajaal_gleam_web/src/"^p)(stage^"/full-package/src/"^p))["indrajaal_gleam_web.gleam";"indrajaal_gleam_web/types.gleam";"indrajaal_web_ffi.erl";"uos_web_runtime_ffi.erl";"indrajaal/runtime_identity.gleam";"indrajaal/ecology_service.gleam";"indrajaal/ecology_http.gleam";"indrajaal/homeostasis_http.gleam";"indrajaal/music_files.gleam"];
candidate "apps/indrajaal_gleam_web/gleam.toml"(stage^"/full-package/gleam.toml");
List.iter(fun p->candidate("apps/indrajaal_gleam_web/test/"^p)(stage^"/full-package/test/"^p))["music_files_test.gleam";"music_http_probe.gleam";"document_render_contract_test.gleam"];
List.iter(fun p->candidate p(stage^"/content/"^p))["docs/music/20260907-1052-swarm-durga-player.md";"docs/music/20260907-1145-cybernetic-raga-durga-and-22-shruti-studio.md";"generated/20260907-1100-uos-hive-sings-yaman-teentaal.wav";"generated/20260907-1230-uos-hive-sings-full-mix.wav"];
let lib="/home/an/NAS-setup/uos/apps/indrajaal_gleam_web/build/dev/erlang"in
Array.iter(fun n->if n<>"indrajaal_gleam_web" && (Unix.lstat(lib^"/"^n)).st_kind=Unix.S_DIR then List.iter(fun sub->let p=lib^"/"^n^"/"^sub in if Sys.file_exists p then tree p(stage^"/full-lib/"^n^"/"^sub))["_gleam_artefacts";"ebin"])(Sys.readdir lib);
write(stage^"/full-bindings.json")(Yojson.Safe.pretty_to_string(`Assoc["scope",`String"Full changed Indrajaal module type-check against realized dependency artifacts; dependency source admission not implied";"records",`List(List.rev!records)]));print_endline(string_of_int(List.length!records)^" bindings")
