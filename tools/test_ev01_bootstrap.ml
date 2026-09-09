#use "topfind";;
#require "unix,yojson,cryptokit,str";;
(* Closed private campaign. Invoke using native ocamlrun -> ocaml, followed by
   WORKSPACE FULL_COMMIT_ID. No shell, Git executable or live repository writes. *)
open Yojson.Safe.Util
let root="/home/an/NAS-setup/uos"
let tc=root^"/toolchains"
let ocamlrun=tc^"/opam-ocaml/bin/ocamlrun"
let ocaml=tc^"/opam-ocaml/bin/ocaml"
let adapter=root^"/.uos-workspaces/codex-ev-admission-20260909-0210/tools/ev_native.ml"
let jj="/nix/store/vzrnnii3369cn2a2bgdlkx9gh6m297fj-jujutsu-0.44.0/bin/jj"
let erts="/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/erts-17.0.5/bin/erlexec"
let check label condition=if not condition then failwith label
let read path=let c=open_in_bin path in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->
 let size=in_channel_length c in check "bounded file"(size<=67108864);really_input_string c size)
let sha bytes=Cryptokit.hash_string(Cryptokit.Hash.sha256())bytes|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir path=if not(Sys.file_exists path)then(mkdir(Filename.dirname path);Unix.mkdir path 0o700)
let write path bytes=mkdir(Filename.dirname path);let c=open_out_bin path in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c bytes)
let rec files root relative=let path=root^"/"^relative in match (Unix.lstat path).Unix.st_kind with
 |Unix.S_REG->[relative]
 |Unix.S_DIR->Sys.readdir path|>Array.to_list|>List.sort String.compare|>List.concat_map(fun name->files root(if relative=""then name else relative^"/"^name))
 |_->failwith("nonregular staged input: "^path)
let json path value=write path(Yojson.Safe.pretty_to_string value)
let ()=check "usage WORKSPACE FULL_COMMIT_ID"(Array.length Sys.argv=3)
let workspace=Unix.realpath Sys.argv.(1)
let revision=Sys.argv.(2)
let ()=check "full commit ID"(String.length revision=40 && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)revision)
let stage=Filename.temp_dir ~temp_dir:"/tmp" "ev01-bootstrap-campaign-" ""
let bindings=ref[] and observations=ref[] and counter=ref 0 and checks=ref 0
let copy source destination bytes=write destination bytes;bindings:=`Assoc["source",`String source;"staged",`String destination;"sha256",`String(sha bytes)]::!bindings
let record label condition=incr checks;check label condition;Printf.printf "PASS %s\n%!"label
let invoke cwd label tool args=
 incr counter;let receipt=Printf.sprintf "%s/receipts/%03d-%s.json"stage !counter label in
 mkdir(Filename.dirname receipt);
 let log=receipt^".driver-output"in
 let fd=Unix.openfile log[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 let input=Unix.openfile "/dev/null"[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
 let argv=Array.of_list([ocamlrun;ocaml;adapter;"--cwd";cwd;"--seconds";"60";"--receipt";receipt;"--";tool]@args)in
 let pid=Unix.create_process_env ocamlrun argv(Unix.environment())input fd fd in
 Unix.close input;Unix.close fd;let _,status=Unix.waitpid[]pid in
 let observation=Yojson.Safe.from_file receipt in
 let code=observation|>member "exit_code"|>to_int and output=observation|>member "output"|>to_string in
 check "adapter reports actual normal code"(status=Unix.WEXITED code);
 check "captured output digest"(sha output=(observation|>member "output_sha256"|>to_string));
 observations:=`Assoc["label",`String label;"receipt",`String receipt;"sha256",`String(sha(read receipt))]::!observations;
 code,output
let success cwd label tool args=let code,output=invoke cwd label tool args in check(label^": "^output)(code=0);output
let query args=success workspace "candidate" "jj"(["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace]@args)
let expr="commit_id(\""^revision^"\")"
let bootstrap=["bootstrap_model.ml";"bootstrap_model.mli";"bootstrap_observer.ml";"bootstrap_observer.mli";"bootstrap_check.ml";"test_bootstrap_model.ml";"dune";"dune-project"]
let source path=query["file";"show";"-r";expr;"--";"root:"^path]
let fixture name=let path=stage^"/fixtures/"^name in mkdir path;path
let install path=
 List.iter(fun name->let relative="tools/bootstrap/"^name in write(path^"/"^relative)(read(stage^"/"^relative)))bootstrap;
 write(path^"/AGENTS.md")"Private native EV01 fixture; not admission.\n"
let init name colocated=let path=fixture name in
 ignore(success stage("init-"^name)"jj"["git";"init";(if colocated then "--colocate" else "--no-colocate");path]);install path;path
let gate label path expected=
 let code,output=invoke path label "native"[erts;"-noshell";"-noinput";"-pa";stage^"/lib/gleam_stdlib/ebin";stage^"/compiled/ebin";"-s";"uos";"main";"-s";"init";"stop";"-extra";"gate";"G-BOOT1"]in
 let reports=String.split_on_char '\n' output|>List.filter(fun line->String.starts_with ~prefix:"{" line)in
 let status=match reports with [line]->Yojson.Safe.from_string line|>member "status"|>to_string|_->"MISSING_OR_AMBIGUOUS"in
 record label(if expected then code=0 && status="OBSERVED_STANDALONE_JJ" else code=1 && status="REFUSED");
 output
let private_jj path label args=success path label "jj"(["--no-pager";"--color";"never";"-R";path]@args)
let current path=String.trim(private_jj path "current"["--ignore-working-copy";"log";"-r";"@";"--no-graph";"-T";"self.commit_id()"])
let ()=
 print_endline stage;
 check "exact candidate"(query["log";"-r";expr;"--no-graph";"-T";"self.commit_id() ++ \"\\n\""]=revision^"\n");
 List.iter(fun path->copy("candidate:"^path)(stage^"/package/"^String.sub path 10(String.length path-10))(source path))
 ["tools/uos/src/main.gleam";"tools/uos/src/uos.gleam";"tools/uos/src/uos_ffi.erl";"tools/uos/gleam.toml";"tools/uos/manifest.toml"];
 List.iter(fun name->let path="tools/bootstrap/"^name in copy("candidate:"^path)(stage^"/"^path)(source path))bootstrap;
 copy "candidate:tools/test_ev01_bootstrap.ml"(stage^"/test_ev01_bootstrap.ml")(source "tools/test_ev01_bootstrap.ml");
 check "executed driver equals candidate bytes"(read Sys.argv.(0)=read(stage^"/test_ev01_bootstrap.ml"));
 let deps=root^"/tools/uos/build/dev/erlang"in
 List.iter(fun name->files deps name|>List.iter(fun path->copy(deps^"/"^path)(stage^"/lib/"^path)(read(deps^"/"^path))))["gleam_stdlib";"gleeunit"];
 ignore(success stage "compile-cli" "gleam"["compile-package";"--target";"erlang";"--package";stage^"/package";"--out";stage^"/compiled";"--lib";stage^"/lib"]);
 let model=stage^"/tools/bootstrap"in
 ignore(success model "compile-model-observer" "dune"["build";"--root";model;"--build-dir";stage^"/model-build";"test_bootstrap_model.bc";"bootstrap_model.cma";"bootstrap_observer.cma"]);
 let model_output=success model "formal-truth-table" "native"[ocamlrun;stage^"/model-build/default/test_bootstrap_model.bc"]in
 record "formal exhaustive and independent oracle"(String.starts_with ~prefix:"PASS bootstrap formal predicate:" model_output);
 let absent=fixture "absent" in install absent;ignore(gate "absent-refuses" absent false);
 let fake=fixture "empty-jj"in install fake;mkdir(fake^"/.jj");ignore(gate "empty-jj-refuses" fake false);
 let file=fixture "file-jj"in install file;write(file^"/.jj")"fake";ignore(gate "file-jj-refuses" file false);
 let colocated=init "colocated" true in ignore(gate "colocated-refuses" colocated false);
 let good=init "standalone" false in
 ignore(private_jj good "snapshot-a"["describe";"-m";"private bootstrap A"]);
 let first=current good in let checkout=read(good^"/.jj/working_copy/checkout")in
 ignore(gate "standalone-passes" good true);
 record "gate leaves revision and checkout unchanged"(first=current good && checkout=read(good^"/.jj/working_copy/checkout"));
 mkdir(good^"/.git");let marker=Unix.lstat(good^"/.git")in
 let output=gate "empty-git-marker-passes" good true in
 record "empty marker is explicitly reported"(try ignore(Str.search_forward(Str.regexp_string "EMPTY_NON_OPERATIONAL_DIRECTORY")output 0);true with Not_found->false);
 let after_marker=Unix.lstat(good^"/.git")in
 let marker_identity s=s.Unix.st_dev,s.st_ino,s.st_kind,s.st_perm,s.st_mtime,s.st_ctime in
 record "empty marker identity mode mtime ctime preserved"(marker_identity marker=marker_identity after_marker);Unix.rmdir(good^"/.git");
 write(good^"/.git")"gitdir: elsewhere\n";ignore(gate "git-file-refuses" good false);Unix.unlink(good^"/.git");
 Unix.symlink "missing"(good^"/.git");ignore(gate "git-symlink-refuses" good false);Unix.unlink(good^"/.git");
 mkdir(good^"/.git");Unix.chmod(good^"/.git")0;
 Fun.protect ~finally:(fun()->Unix.chmod(good^"/.git")0o700)(fun()->ignore(gate "unreadable-git-refuses" good false));Unix.rmdir(good^"/.git");
 mkdir(good^"/.git");write(good^"/.git/config")"metadata";ignore(gate "nonempty-git-refuses" good false);Unix.unlink(good^"/.git/config");Unix.rmdir(good^"/.git");
 let target=good^"/.jj/repo/store/git_target"in let saved=read target in
 write target "/tmp/external";ignore(gate "external-store-refuses" good false);write target saved;
 let kind=good^"/.jj/repo/store/type"in let saved_kind=read kind in write kind "fake";ignore(gate "bad-store-type-refuses" good false);write kind saved_kind;
 let store=good^"/.jj/repo/store"in Unix.rename store(good^"/detached-store");Unix.symlink "../../detached-store" store;
 ignore(gate "symlink-store-refuses" good false);Unix.unlink store;Unix.rename(good^"/detached-store")store;
 let metadata=good^"/.jj"in Unix.rename metadata(good^"/detached-jj");Unix.symlink "detached-jj" metadata;
 ignore(gate "symlink-jj-refuses" good false);Unix.unlink metadata;Unix.rename(good^"/detached-jj")metadata;
 let checkout_path=good^"/.jj/working_copy/checkout"in write checkout_path "corrupt";
 ignore(gate "corrupt-checkout-refuses" good false);write checkout_path checkout;
 write(good^"/bootstrap-proof.txt")"alpha\n";ignore(private_jj good "snapshot-alpha"["describe";"-m";"private alpha"]);
 let alpha=current good in
 write(good^"/bootstrap-proof.txt")"beta\n";ignore(private_jj good "snapshot-beta"["describe";"-m";"private beta"]);
 let beta=current good in
 record "snapshot revision changes"(alpha<>beta);
 record "old immutable bytes retained"(private_jj good "read-alpha"["--ignore-working-copy";"file";"show";"-r";"commit_id(\""^alpha^"\")";"--";"root:bootstrap-proof.txt"]="alpha\n");
 record "new snapshot bytes retained"(private_jj good "read-beta"["--ignore-working-copy";"file";"show";"-r";"commit_id(\""^beta^"\")";"--";"root:bootstrap-proof.txt"]="beta\n");
 let sibling=stage^"/fixtures/sibling"in
 ignore(private_jj good "workspace-add"["workspace";"add";"--name";"bootstrap-sibling";"-r";"commit_id(\""^beta^"\")";sibling]);install sibling;
 ignore(gate "additional-workspace-passes" sibling true);
 write(sibling^"/bootstrap-proof.txt")"sibling\n";ignore(private_jj sibling "snapshot-sibling"["describe";"-m";"private sibling"]);
 record "workspace edits isolated"(read(good^"/bootstrap-proof.txt")="beta\n");
 let pointer=sibling^"/.jj/repo"in let saved_pointer=read pointer in write pointer "bad\n";
 ignore(gate "corrupt-pointer-refuses" sibling false);write pointer saved_pointer;
 let nested=good^"/nested/path"in mkdir nested;ignore(gate "nested-cli-resolves-root" nested true);
 let code,_=invoke good "checker-args-refuse" "ocaml"[good^"/tools/bootstrap/bootstrap_check.ml";"--help"]in record "checker refuses caller arguments"(code=2);
 (* Actual compiled designated predicate mutant: no compiler error can count. *)
 let mutant=stage^"/mutant-model"in List.iter(fun name->write(mutant^"/"^name)(read(model^"/"^name)))["bootstrap_model.ml";"bootstrap_model.mli";"test_bootstrap_model.ml";"dune-project"];
 let original=read(mutant^"/bootstrap_model.ml")in
 let mutant_bytes=original^"\nlet verify _ = Ok Verified\n"in write(mutant^"/bootstrap_model.ml")mutant_bytes;
 write(mutant^"/dune")"(executable (name test_bootstrap_model) (modes byte) (link_flags -without-runtime) (modules bootstrap_model test_bootstrap_model) (flags (:standard -warn-error -a)))\n";
 ignore(success mutant "compile-designated-mutant" "dune"["build";"--root";mutant;"--build-dir";stage^"/mutant-build";"test_bootstrap_model.bc"]);
 let code,output=invoke mutant "designated-mutant-fails" "native"[ocamlrun;stage^"/mutant-build/default/test_bootstrap_model.bc"]in
 record "compiled mutant fails designated oracle assertion"(code=2 && (try ignore(Str.search_forward(Str.regexp_string "predicate agrees with independent universal oracle")output 0);true with Not_found->false));
 let duplicate=stage^"/mutant-duplicate"in
 List.iter(fun name->write(duplicate^"/"^name)(read(mutant^"/"^name)))["bootstrap_model.mli";"test_bootstrap_model.ml";"dune-project";"dune"];
 let anchor="if List.mem fact seen then Error Malformed_observations"in
 let duplicate_bytes=Str.global_replace(Str.regexp_string anchor)"if List.mem fact seen then collect seen failed rest" original in
 check "exact duplicate mutant anchor"(duplicate_bytes<>original);
 write(duplicate^"/bootstrap_model.ml")duplicate_bytes;
 ignore(success duplicate "compile-duplicate-mutant" "dune"["build";"--root";duplicate;"--build-dir";stage^"/duplicate-build";"test_bootstrap_model.bc"]);
 let duplicate_code,duplicate_output=invoke duplicate "duplicate-mutant-fails" "native"[ocamlrun;stage^"/duplicate-build/default/test_bootstrap_model.bc"]in
 record "compiled duplicate mutant fails distinct assertion"(duplicate_code=2 && (try ignore(Str.search_forward(Str.regexp_string "duplicate refuses")duplicate_output 0);true with Not_found->false));
 let artifacts=(files stage "compiled" @ ["model-build/default/test_bootstrap_model.bc";"model-build/default/bootstrap_model.cma";"model-build/default/bootstrap_observer.cma";"mutant-build/default/test_bootstrap_model.bc";"duplicate-build/default/test_bootstrap_model.bc"])
 |>List.map(fun path->`Assoc["path",`String(stage^"/"^path);"sha256",`String(sha(read(stage^"/"^path)))])in
 List.iter(fun binding->let p=binding|>member "staged"|>to_string in check "staged source/dependency unchanged"(sha(read p)=(binding|>member "sha256"|>to_string)))!bindings;
 let tool_bindings=List.map(fun path->let actual=Unix.realpath path in `Assoc["path",`String path;"actual",`String actual;"sha256",`String(sha(read actual))])[ocamlrun;ocaml;adapter;jj;erts;tc^"/gleam-1.16.0/bin/gleam";tc^"/opam-ocaml/bin/dune"]in
 json(stage^"/verification.json")(`Assoc["schema",`String "uos.ev01-bootstrap-campaign.v1";"candidate",`String revision;"status",`String "COMPONENT_OBSERVATIONS_PASS";"admission",`String "NOT_GRANTED";"checks",`Int !checks;"source_dependencies",`List(List.rev !bindings);"tools",`List tool_bindings;"artifacts",`List artifacts;"observations",`List(List.rev !observations);"mutant_source_sha256",`String(sha mutant_bytes);"duplicate_mutant_source_sha256",`String(sha duplicate_bytes)]);
 Printf.printf "PASS %d checks; %d native invocations; %s/verification.json\n" !checks !counter stage
