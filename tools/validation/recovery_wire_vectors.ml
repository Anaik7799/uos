#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,cryptokit,yojson,unix";;
(* Development-only cross-language factual codec fixture. No store/worker,
   grants, packages, resolver, shared build, task, runtime or VCS writes.
   argv SOURCE_ROOT TOOLCHAIN_ROOT PHASE EXPECTED_EXIT. Expected2 is a retained
   RED/mutation experiment, NEVER a passing capability. Private output retained.
   Tests require the actual pinned offline tools and fail if unavailable. *)
let require p s=if not p then failwith s
let unwrap=function Ok x->x|Error(`Msg s)->failwith s
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->
 let n=in_channel_length c in require(n<=1048576)"source bound";really_input_string c n)
let write p s=ignore(unwrap(Bos.OS.Dir.create(Fpath.v(Filename.dirname p))));
 let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->let rec loop n=if n<String.length s then
  let k=Unix.write_substring fd s n(String.length s-n)in require(k>0)"write";loop(n+k)in loop 0;Unix.fsync fd)
let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let native_tests={native|
module W=Sa_plan_recovery_wire
open Yojson.Safe.Util
let checks=ref 0
let check name b=incr checks;if not b then failwith name
let set k v=function `Assoc xs->`Assoc((k,v)::List.remove_assoc k xs)|_->failwith "fixture object"
let encode=Yojson.Safe.to_string
let decode x=W.decode(encode x)
let good=function Ok x->x|Error _->failwith "positive golden decode refused"
let bad x=check "negative input accepted" (match decode x with Error _->true|_->false)
let change_member v k replacement=match member "members" v with
 |`List(first::rest)->set "members" (`List(set k replacement first::rest)) v
 |_->failwith "members"
let ()=
 let raw=let c=open_in_bin Sys.argv.(1)in Fun.protect ~finally:(fun()->close_in c)(fun()->
  let n=in_channel_length c in if n>1048576 then failwith "fixture bound";really_input_string c n)in
 let vectors=Yojson.Safe.from_string raw|>member "vectors"|>to_list in
 List.iter(fun vector->let v=member "input" vector in let r=good(decode v)in
  check "literal canonical mismatch" (W.canonical_bytes r=to_string(member "canonical" vector));
  check "literal SHA mismatch" (W.request_sha256 r=to_string(member "sha256" vector));
  check "tag binding mismatch" (W.tagged_request_sha256 r="sha256:"^to_string(member "sha256" vector));
  let reversed=set "members" (`List(List.rev(to_list(member "members" v))))v in
  check "member permutation changes bytes" (W.canonical_bytes(good(decode reversed))=W.canonical_bytes r)
 )vectors;
 let v=member "input"(List.hd vectors)in let original=good(decode v)in
 List.iter(fun changed->check "semantic change retained digest"
  (W.request_sha256(good(decode changed))<>W.request_sha256 original))[
  set "request_id" (`String "other-request")v;set "plan" (`String "uos/other")v;
  set "snapshot_sha256" (`String("sha256:"^String.make 64 '1'))v;
  set "deadline_utc_ms" (`Int 1793487751776)v;
  change_member v "task_id" (`String "different-task");change_member v "worker" (`String "different-worker");
  change_member v "old_attempt" (`Int 99);change_member v "old_lease_ns" (`String "9223372036854775806");
  set "members" (`List(List.map(fun m->set "lease_ms" (`Int 2)m)(to_list(member "members" v))))v];
 let ms=to_list(member "members" v)in
 List.iter bad [set "request_id" (`String "bad:colon")v;set "plan" (`String "")v;
  set "authorized" (`Bool true)v;set "snapshot_sha256" (`String(String.make 64 'a'))v;
  set "snapshot_sha256" (`String("sha256:"^String.make 64 'A'))v;
  set "deadline_utc_ms" (`Int 9223372036855)v;set "deadline_utc_ms" (`Int 0)v;
  set "deadline_utc_ms" (`Float 1.)v;set "members" (`List(ms@ms))v;
  set "members" (`List [])v;set "members" (`List(List.init 3(fun _->List.hd ms)))v;
  change_member v "lease_ms" (`Int 2);change_member v "lease_ms" (`Int 0);
  change_member v "lease_ms" (`Int 3600001);change_member v "old_attempt" (`Int 0);
  change_member v "old_attempt" (`Int 1000000);change_member v "old_lease_ns" (`String "0");
  change_member v "old_lease_ns" (`String "01");change_member v "old_lease_ns" (`String "+1");
  change_member v "old_lease_ns" (`String "1e3");change_member v "old_lease_ns" (`String "9223372036854775808");
  change_member v "old_lease_ns" (`Int 1);change_member v "worker" (`String "nul\000worker")];
 List.iter(fun raw->check "raw strictness refusal"(match W.decode raw with Error _->true|_->false))[
  {|{"request_id":"a","request_id":"b"}|};"{} trailing";"[]";"null";"{";String.make 32769 ' ';
  "[[[[[[[[[[[[[0]]]]]]]]]]]]]" ];
 let raw=encode v in
 let without_request=match v with `Assoc xs->encode(`Assoc(List.remove_assoc "request_id" xs))|_->failwith "fixture root"in
 let unquoted="{request_id:"^encode(member "request_id" v)^","^String.sub without_request 1(String.length without_request-1)in
 List.iter(fun commented->check "nonstandard syntax in valid object accepted"(match W.decode commented with Error _->true|_->false))[
  "/* before */"^raw;"// before\n"^raw;"{/* inside */"^String.sub raw 1(String.length raw-1);
  "{// inside\n"^String.sub raw 1(String.length raw-1);raw^"/* after */";raw^"// after\n";unquoted;
  String.sub raw 0(String.length raw-1)^",}"];
 check "legal whitespace changes bytes" (W.canonical_bytes(good(W.decode(" \t\r\n"^raw^" \t\r\n")))=W.canonical_bytes original);
 ignore(good(decode(set "request_id" (`String "r//x")v)));check "slashes inside string allowed" true;
 Printf.printf "%d checks PASS factual_only=true authority=false\n%!" !checks
|native}
let ()=
 require(Array.length Sys.argv=5)"SOURCE_ROOT TOOLCHAIN_ROOT PHASE EXPECTED_EXIT";
 let source=Unix.realpath Sys.argv.(1)and tc=Unix.realpath Sys.argv.(2)in
 let phase=Sys.argv.(3)and expected=int_of_string Sys.argv.(4)in
 require(String.length phase>0&&String.length phase<=80&&String.for_all(function 'a'..'z'|'0'..'9'|'-'->true|_->false)phase)"phase";
 require(expected=0||expected=2)"expected exit";
 let paths=["apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_wire.gleam";
  "apps/cepaf_gleam/test/harness_recovery_wire_test.gleam";
  "engines/hermes/modules/sa_plan/sa_plan_recovery_wire.ml";
  "engines/hermes/modules/sa_plan/sa_plan_recovery_wire.mli";
  "tools/validation/recovery_wire_vectors.ml";"tools/validation/fixtures/recovery_wire_v1.json"]in
 let inputs=List.map(fun p->p,read(source^"/"^p))paths in let get p=List.assoc p inputs in
 let base=Filename.temp_file ~temp_dir:"/tmp" "uos-recovery-wire-fixture-" ""in
 Unix.unlink base;Unix.mkdir base 0o700;
 Printf.printf "PRIVATE_FIXTURE=%s PHASE=%s\n%!"base phase;
 let records=ref []in
 let run label exe args=
  let command=[tc^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";tc^"/tools/ecology_process.ml";
    "60000";"65536";"merged";exe]@args in
  let output,(_,status)=unwrap(Bos.OS.Cmd.run_out(Bos.Cmd.of_list command)|>Bos.OS.Cmd.out_string ~trim:false)in
  let code=match status with `Exited n->n|`Signaled n->128+n in
  write(base^"/"^label^".log")output;records:=(label,`Assoc["exit",`Int code;"sha256",`String(sha output)])::!records;
  Printf.printf "%s exit=%d\n%s%!" label code output;code in
 let native=base^"/native"in ignore(unwrap(Bos.OS.Dir.create(Fpath.v native)));
 List.iter(fun extension->write(native^"/sa_plan_recovery_wire."^extension)(get("engines/hermes/modules/sa_plan/sa_plan_recovery_wire."^extension)))["mli";"ml"];
 write(native^"/native_tests.ml")native_tests;
 let find=tc^"/toolchains/opam-ocaml/bin/ocamlfind"in
 let common=["ocamlopt";"-w";"+a-4-40-42-44-45-48-70";"-warn-error";"+a-4-40-42-44-45-48-70";"-package";"yojson,digestif.c";"-I";native]in
 List.iter(fun ext->require(run("native-"^ext)find(common@["-c";native^"/sa_plan_recovery_wire."^ext;"-o";native^"/sa_plan_recovery_wire."^(if ext="mli"then"cmi"else"cmx")])=0)"native compile")["mli";"ml"];
 require(run "native-link" find(common@["-linkpkg";native^"/sa_plan_recovery_wire.cmx";native^"/native_tests.ml";"-o";native^"/tests"])=0)"native link";
 require(run "native-tests" (native^"/tests")[source^"/tools/validation/fixtures/recovery_wire_v1.json"]=expected)"native test result";
 let project=base^"/project"in
 write(project^"/gleam.toml")"name = \"recovery_wire_private\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \">= 0.0.0\"\ngleam_json = \">= 0.0.0\"\ngleam_crypto = \">= 0.0.0\"\ngleeunit = \">= 0.0.0\"\ncepaf_gleam = \">= 0.0.0\"\n";
 write(project^"/src/cepaf_gleam/harness/recovery_wire.gleam")(get(List.nth paths 0));
 write(project^"/src/harness_recovery_wire_test.gleam")(get(List.nth paths 1));
 let env=tc^"/toolchains/nix-profile/bin/env"and lib=tc^"/apps/indrajaal_gleam_web/build/dev/erlang"in
 let envargs=["-i";"PATH="^tc^"/toolchains/nix-profile/bin:"^tc^"/toolchains/gleam-1.16.0/bin:/usr/bin:/bin";"ERL_FLAGS=+S 2:2 +A 2"]in
 require(run "gleam-compile" env(envargs@[tc^"/toolchains/gleam-1.16.0/bin/gleam";"compile-package";"--target";"erlang";"--package";project;"--out";base^"/gleam";"--lib";lib])=0)"gleam compile";
 let ebins=unwrap(Bos.OS.Dir.contents(Fpath.v lib))|>List.map(fun p->Fpath.to_string p^"/ebin")|>List.filter Sys.file_exists in
 require(run "gleam-tests" env(envargs@["UOS_RECOVERY_WIRE_FIXTURE="^source^"/tools/validation/fixtures/recovery_wire_v1.json";
  tc^"/toolchains/nix-profile/bin/erl";"+S";"2:2";"+A";"2";"-noshell";"-pa";base^"/gleam/ebin"]@ebins@[
  "-eval";"case eunit:test(harness_recovery_wire_test,[verbose])of ok->halt(0);_->halt(2)end."])=expected)"gleam test result";
 List.iter(fun(p,s)->require(read(source^"/"^p)=s)"source drift")inputs;
 let receipt=`Assoc["schema",`String"uos.recovery-factual-wire-private-check.v1";"phase",`String phase;
  "expected_exit",`Int expected;"status",`String(if expected=0 then"SCOPED_PASS"else"EXPECTED_FAILURE_NOT_PASS");
  "authority",`String"NONE";"effects",`Bool false;"source_stable",`Bool true;"private_directory",`String base;
  "sources",`Assoc(List.map(fun(p,s)->p,`String(sha s))inputs);"observations",`Assoc(List.rev!records);
  "limits",`List(List.map(fun s->`String s)["Pure factual request encoding, never authority or authenticated envelope.";
   "Input nanosecond strings retain Int64 precision; expiry is a caller datum, not a clock observation.";
   "Existing native v1 does not bind proposal/review/portfolio/capability; their future envelope is unimplemented.";
   "Both codecs checked against literal canonical bytes and independent sha256sum-generated fixture hashes.";
   "No production effect path, Store mutator, worker dispatch, model/network/package fetch, or full refinement proof."])]in
 write(base^"/receipt.json")(Yojson.Basic.pretty_to_string receipt^"\n");print_endline(base^"/receipt.json")
