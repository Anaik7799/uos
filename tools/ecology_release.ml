#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson,cryptokit,mtime.clock.os";;

(* @agent_intent: Snapshot already-built ecology artifacts into a checked,
   immutable-by-permission release. No build, install, VCS, service or deploy action.
   @laws: Exact inventories reject missing/unexpected/changed files; source drift
   aborts before publication; dependency absence is not success; manifests are
   deterministic for identical input bytes. Owner permissions are not cryptographic
   immutability: verify again at runtime effects.
   Usage: ecology_release.ml stage ROOT | verify RELEASE | selftest *)

open Unix
open Yojson.Safe.Util
let need b m = if not b then failwith m
let get = function Ok x -> x | Error (`Msg m) -> failwith m
let s x = `String x
let obj x = `Assoc x
let arr x = `List x
let json x = Yojson.Safe.pretty_to_string x ^ "\n"
let mono () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9
let marker = "uos.ecology-release.v1\n"
let maximum_file = 128 * 1024 * 1024
let maximum_release = 512 * 1024 * 1024
let maximum_files = 20000
let started = mono ()
let deadline () = need(mono () -. started <= 120.) "120-second operation deadline exceeded"
let banned path =
  let parts=String.split_on_char '/' path in
  List.exists (fun p->List.mem p [".git";".jj";".pixi";".cache";"__pycache__";".env";"auth.json";"credentials.json"]) parts ||
  List.exists (fun ending->String.ends_with ~suffix:ending path)
    [".db";".sqlite";".sqlite3";"-wal";"-shm";".key";".pyc";".safetensors";".pt";".pkl"]
let hex n x = String.length x=n && String.for_all (function '0'..'9'|'a'..'f' -> true | _ -> false) x
let safe_relative x = Filename.is_relative x && x<>"" &&
  List.for_all (fun p -> p<>"" && p<>"." && p<>"..") (String.split_on_char '/' x) &&
  not (String.exists (fun c -> Char.code c<32 || c='\\') x)
let inside root p = p=root || String.starts_with ~prefix:(root^"/") p
let digest text = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) text
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let regular path = let st=lstat path in
  need (st.st_kind=S_REG && st.st_size>=0 && st.st_size<=maximum_file) ("non-regular or oversized file: "^path); st
let read path = ignore(regular path); get (Bos.OS.File.read (Fpath.v path))
let write path content =
  let fd=openfile path [O_WRONLY;O_CREAT;O_EXCL;O_CLOEXEC] 0o600 in
  let oc=out_channel_of_descr fd in
  Fun.protect (fun () -> output_string oc content;flush oc;fsync fd)
    ~finally:(fun () -> close_out_noerr oc)
let mkdir path = ignore(get (Bos.OS.Dir.create ~mode:0o700 ~path:true (Fpath.v path)))
let sha path =
  deadline ();
  let before=regular path and hash=Cryptokit.Hash.sha256 () in
  let ic=open_in_bin path and buffer=Bytes.create 65536 in
  Fun.protect (fun () ->
    let opened=fstat (descr_of_in_channel ic) in
    need (before.st_dev=opened.st_dev && before.st_ino=opened.st_ino) "file swapped before read";
    let rec loop total = let n=input ic buffer 0 (Bytes.length buffer) in
      if n>0 then (deadline ();need(total+n<=maximum_file) "file grew beyond bound";
        hash#add_substring buffer 0 n;loop(total+n)) in
    loop 0;
    let after=fstat(descr_of_in_channel ic) in
    need (opened.st_size=after.st_size && opened.st_mtime=after.st_mtime && opened.st_ctime=after.st_ctime) "file changed while hashing";
    Cryptokit.transform_string (Cryptokit.Hexa.encode ()) hash#result)
    ~finally:(fun () -> close_in_noerr ic)
let rec files root rel =
  deadline ();
  let path=if rel="" then root else root^"/"^rel in
  need (List.length(String.split_on_char '/' rel)<=24) "directory depth bound";
  match (lstat path).st_kind with
  | S_REG -> need(safe_relative rel) "invalid relative file"; [rel]
  | S_DIR -> Sys.readdir path |> Array.to_list |> List.sort String.compare
      |> List.concat_map(fun name -> files root (if rel="" then name else rel^"/"^name))
  | _ -> failwith("unsupported inventory entry: "^path)
let inventory root =
  let names=files root "" |> List.filter((<>)"release-manifest.json") in
  need(List.length names>0 && List.length names<=maximum_files) "inventory count bound";
  let total=ref 0 in
  names |> List.map(fun path -> let st=regular(root^"/"^path) in
    total:= !total+st.st_size;need(!total<=maximum_release) "inventory byte bound";
    obj["path",s path;"sha256",s(sha(root^"/"^path));"bytes",`Int st.st_size])
let canonical x =
  let rec sort = function `Assoc xs -> `Assoc(List.sort compare(List.map(fun(k,v)->k,sort v)xs))
    | `List xs -> `List(List.map sort xs) | v -> v in
  Yojson.Safe.to_string(sort x)
let same a b = canonical a=canonical b
let run root exe args =
  need(not(Filename.is_relative exe)) "absolute executable required";
  let ocaml=if Sys.file_exists(root^"/.uos-ecology-release") then
    read(root^"/runtime-dependencies.json") |> Yojson.Safe.from_string
      |> member "ocaml" |> member "path" |> to_string
    else root^"/toolchains/opam-ocaml/bin/ocaml" in
  let command=Bos.Cmd.of_list(ocaml::"-I"::"+unix"::(root^"/tools/ecology_process.ml")::
    "20000"::"1048576"::"merged"::exe::args) in
  let env=Astring.String.Map.of_list ["PATH",root^"/toolchains/nix-profile/bin:/usr/bin:/bin";
    "LANG","C.UTF-8";"ERL_CRASH_DUMP","/dev/null"] in
  get(Bos.OS.Cmd.run_out ~env command |> Bos.OS.Cmd.out_string |> Bos.OS.Cmd.success)
let dependency root rel executable =
  need(safe_relative rel && String.starts_with ~prefix:"toolchains/" rel) "toolchain locator must be repository-owned";
  let path=realpath(root^"/"^rel) in
  need(inside(root^"/toolchains")path || String.starts_with ~prefix:"/nix/store/" path) "unowned toolchain target";
  let st=regular path in need(not executable || st.st_perm land 0o111<>0) "tool not executable";
  obj["path",s path;"sha256",s(sha path)]
let runtime_dependencies root =
  let bound rel = let p=realpath(root^"/"^rel) in
    need(inside root p) "MAX metadata escaped repository";
    obj["path",s p;"sha256",s(sha p)] in
  let environment=realpath(root^"/services/inference/max/.pixi/envs/default") in
  need(inside(root^"/services/inference/max/.pixi")environment) "MAX environment escaped expected root";
  let python=realpath(environment^"/bin/python") in ignore(regular python);
  obj["schema",s"uos.ecology-runtime-dependencies.v1";
    "ocaml",dependency root "toolchains/opam-ocaml/bin/ocaml" true;
    "pixi",dependency root "toolchains/pixi/bin/pixi" true;
    "erl",dependency root "toolchains/nix-profile/bin/erl" true;
    "max_manifest",bound "services/inference/max/pixi.toml";
    "max_lock",bound "services/inference/max/pixi.lock";
    "environment_locator",s environment;
    "environment_python",obj["path",s python;"sha256",s(sha python)];
    "environment_mode",s"existing --no-install --frozen; environment closure is not copied";
    "repository_resources",obj["path",s root;"mode",s"source/toolchain locator only; dedicated ecology listener does not publish repository files"]]
let verify_dependencies doc =
  need(doc |> member "schema" |> to_string = "uos.ecology-runtime-dependencies.v1") "runtime dependency schema";
  List.iter(fun name -> let v=doc|>member name in
    let path=v|>member "path"|>to_string and expected=v|>member "sha256"|>to_string in
    need(not(Filename.is_relative path) && realpath path=path && hex 64 expected) "invalid realized dependency";
    need(sha path=expected) ("runtime dependency changed: "^name))
    ["ocaml";"pixi";"erl";"max_manifest";"max_lock";"environment_python"]
let otp_identity root erl =
  let result=run root erl ["+S";"2:2";"-noshell";"-eval";
    "io:put_chars(json:encode(#{otp_release => list_to_binary(erlang:system_info(otp_release)), erts_version => list_to_binary(erlang:system_info(version)), root_dir => list_to_binary(code:root_dir())})),halt()."]
    |> Yojson.Safe.from_string in
  need(result|>member "otp_release"|>to_string="29") "only actual OTP29 allowed";
  need(String.starts_with ~prefix:"17." (result|>member "erts_version"|>to_string)) "OTP29/ERTS mismatch";
  result
let build_apps root =
  let collect owner = let base="apps/"^owner^"/build/dev/erlang" in
    Sys.readdir(root^"/"^base) |> Array.to_list |> List.sort String.compare
    |> List.filter_map(fun app -> let rel=base^"/"^app^"/ebin/"^app^".app" in
      if Sys.file_exists(root^"/"^rel) then Some(app,base^"/"^app) else None) in
  let web=collect "indrajaal_gleam_web" in
  need(List.mem_assoc "cepaf_gleam" web && List.mem_assoc "indrajaal_gleam_web" web) "missing root application artifacts";
  web
let verify_app_closure root erl apps =
  let paths=List.map(fun(name,p)->root^"/"^p^"/ebin/"^name^".app")apps in
  let eval="Ps=init:get_plain_arguments(), A=lists:map(fun(P)->{ok,[{application,N,V}]}=file:consult(P),{N,proplists:get_value(applications,V,[]),[M||M<-proplists:get_value(modules,V,[]),not filelib:is_regular(filename:join(filename:dirname(P),atom_to_list(M)++\".beam\"))]} end,Ps), Ns=[N||{N,_,_}<-A], Missing=lists:usort([D||{_,Ds,_}<-A,D<-Ds,not lists:member(D,Ns),code:lib_dir(D)=:={error,bad_name}]), MissingModules=lists:usort(lists:append([Ms||{_,_,Ms}<-A])),io:put_chars(json:encode(#{applications=>[atom_to_binary(N)||N<-Ns],missing=>[atom_to_binary(N)||N<-Missing],missing_modules=>[atom_to_binary(N)||N<-MissingModules]})),case {Missing,MissingModules} of {[],[]}->halt(0);_->halt(1) end." in
  run root erl (["+S";"2:2";"-noshell";"-eval";eval;"-extra"]@paths) |> Yojson.Safe.from_string
let static_names = ["material.css";"planning-radical.css";"agui-chrome.bundled.js";
  "shell-runtime.bundled.js";"sw-register.bundled.js";"sw.bundled.js";
  "dashboard-grid.bundled.js";"agents-grid.bundled.js";"knowledge-grid.bundled.js";
  "zenoh-grid.bundled.js";"telemetry-grid.bundled.js";"podman-grid.bundled.js";
  "substrate-grid.bundled.js";"page-grid.bundled.js";"verification-grid.bundled.js";
  "immune-grid.bundled.js";"cockpit-grid.bundled.js";"planning-grid.bundled.js";
  "planning-utils.bundled.js";"jobs-live.html";"c3i-status.html";"page-spec.html"]
let payload root apps =
  let beams=List.concat_map(fun(name,path)->
    files(root^"/"^path^"/ebin")"" |> List.filter_map(fun file ->
      if Filename.extension file=".beam" || file=name^".app" then
        Some(path^"/ebin/"^file,"apps/"^name^"/ebin/"^file)
      else None))apps in
  let optional app rel = if List.mem_assoc app apps then
    let src=List.assoc app apps ^"/priv/"^rel in
    if Sys.file_exists(root^"/"^src) then [src,"apps/"^app^"/priv/"^rel] else [] else [] in
  let assets=List.map(fun n->let p="apps/cepaf_gleam/priv/static/"^n in p,p)static_names in
  beams @ assets @ optional "certifi" "cacerts.pem" @ optional "esqlite" "esqlite3_nif.so" @
  List.map(fun n->"apps/indrajaal_gleam_web/build/packages/lustre/priv/static/"^n,"apps/lustre/priv/static/"^n)
    ["lustre-server-component.mjs";"lustre-server-component.min.mjs"] @
  List.map(fun p->p,p)["tools/ecology_process.ml";"services/inference/max/ecology_max_worker.py"]
let source_inputs root payload =
  let app_sources=List.concat_map(fun app -> let base="apps/"^app in
    if Sys.file_exists(root^"/"^base^"/src") then
      (List.concat_map(fun dir ->
        if Sys.file_exists(root^"/"^base^"/"^dir) then
          files(root^"/"^base^"/"^dir)"" |> List.map(fun p->base^"/"^dir^"/"^p)
        else []) ["src";"test"]) @
      [base^"/gleam.toml";base^"/manifest.toml"] else [])
    ["cepaf_gleam";"indrajaal_gleam_web";"uos_swarm";"uos_tui"] in
  List.map fst payload @ app_sources @
    ["flake.nix";"flake.lock";"devenv.nix";"tools/ecology_release.ml";
     "tools/ecology_release.mojo";"services/inference/max/pixi.toml";"services/inference/max/pixi.lock"]
  |> List.sort_uniq String.compare
let source_manifest root inputs =
  need(List.length inputs<=maximum_files) "source count bound";
  let total=ref 0 in
  let entries=List.map(fun path -> need(safe_relative path && not(banned path)) "invalid or excluded source path";
    let resolved=realpath(root^"/"^path) in need(inside root resolved) "source escaped repository";
    let st=regular(root^"/"^path) in
    total:= !total+st.st_size;need(!total<=maximum_release) "source byte bound";
    obj["path",s path;"bytes",`Int st.st_size;"sha256",s(sha(root^"/"^path))])inputs in
  obj["schema",s"uos.ecology-source-manifest.v1";"source_root",s root;"inputs",arr entries;
    "scope",s"Exact source/artifact bytes; build-to-source correspondence remains a separate build receipt"]
let disk_preflight root needed =
  let text=run root "/usr/bin/df" ["-P";"-B1";root] in
  let rows=String.split_on_char '\n' (String.trim text) in
  let row=List.hd(List.rev rows) in
  let fields=String.split_on_char ' ' row |> List.filter((<>)"") in
  need(List.length fields>=6) "disk observation unknown";
  let available=int_of_string(List.nth fields 3) in
  need(available>=needed+needed/5 && available-needed>=512*1024*1024) "disk headroom or 512MiB floor unavailable"
let verify ?(staging=false) release =
  let root=realpath release in need(read(root^"/.uos-ecology-release")=marker) "release marker";
  let m=read(root^"/release-manifest.json") |> Yojson.Safe.from_string in
  need(m|>member "schema"|>to_string="uos.ecology-release-manifest.v1") "release manifest schema";
  need(m|>member "application_admitted"|>to_bool=false) "package cannot grant admission";
  let candidate=m|>member "candidate_sha256"|>to_string in
  need(hex 64 candidate && candidate=digest(canonical(obj(List.remove_assoc "candidate_sha256" (to_assoc m))))) "candidate identity";
  need(staging || String.ends_with ~suffix:("-"^candidate) (Filename.basename root)) "candidate directory identity";
  let expected=m|>member "files"|>to_list in
  List.iter(fun v->let p=v|>member "path"|>to_string in
    need(safe_relative p && hex 64(v|>member "sha256"|>to_string)) "invalid manifest entry")expected;
  need(same(arr expected)(arr(inventory root))) "release inventory differs (missing, unexpected or changed file)";
  need(digest(canonical(arr expected))=(m|>member "payload_sha256"|>to_string)) "payload identity";
  if not staging then (
    let rec permissions p = let st=lstat p in
      need(st.st_perm land 0o222=0) "published release entry is writable";
      if st.st_kind=S_DIR then Array.iter(fun n->permissions(p^"/"^n))(Sys.readdir p) in
    permissions root);
  let source=read(root^"/source-manifest.json") in
  need(digest source=(m|>member "source_sha256"|>to_string)) "source manifest identity";
  let deps=read(root^"/runtime-dependencies.json")|>Yojson.Safe.from_string in verify_dependencies deps;
  let otp=m|>member "otp" in
  let erl=otp|>member "executable" in
  let executable=erl|>member "path"|>to_string in
  need(sha executable=(erl|>member "sha256"|>to_string)) "OTP executable changed";
  need(same erl (deps|>member "erl")) "OTP must match explicit hashed runtime dependency";
  need(same(otp_identity root executable)(otp|>member "identity")) "actual OTP identity changed";
  m
let freeze root =
  List.iter(fun p->chmod(root^"/"^p)0o444)(files root "");
  let rec dirs p=Array.iter(fun n->let q=p^"/"^n in if(lstat q).st_kind=S_DIR then dirs q)(Sys.readdir p);chmod p 0o555 in dirs root
let stage source =
  let root=realpath source in need(Sys.file_exists(root^"/.jj")) "standalone UOS root required";
  let erl=dependency root "toolchains/nix-profile/bin/erl" true in
  let exe=erl|>member "path"|>to_string in
  let identity=otp_identity root exe and deps=runtime_dependencies root in
  let apps=build_apps root in let closure=verify_app_closure root exe apps in
  let copied=payload root apps in let inputs=source_inputs root copied in
  let before=source_manifest root inputs in
  let expected_sources=before|>member "inputs"|>to_list|>List.map(fun v->(v|>member "path"|>to_string),(v|>member "sha256"|>to_string)) in
  need(List.length copied=List.length(List.sort_uniq String.compare(List.map snd copied))) "duplicate destination";
  let size=List.fold_left(fun n (p,_)->n+(regular(root^"/"^p)).st_size)0 copied in
  need(size<=maximum_release) "release size bound";disk_preflight root (size+4194304);
  let parent=root^"/var/releases/ecology" in mkdir parent;
  let temporary=Filename.temp_file ~temp_dir:parent ".staging-" "" in unlink temporary;mkdir temporary;
  List.iter(fun(src,dst)->need(safe_relative dst)"invalid destination";
    let destination=temporary^"/"^dst in mkdir(Filename.dirname destination);
    let bytes=read(root^"/"^src) in
    need(digest bytes=List.assoc src expected_sources) "source changed before copy";
    write destination bytes)copied;
  write(temporary^"/.uos-ecology-release")marker;
  write(temporary^"/runtime-dependencies.json")(json deps);
  write(temporary^"/source-manifest.json")(json before);
  let content=inventory temporary in
  let payload_hash=digest(canonical(arr content)) in
  let manifest=obj["schema",s"uos.ecology-release-manifest.v1";
    "build_mode",s"dev";
    "test_artifacts",s"Exact dev BEAM inventory retained; test source is manifest-only; dedicated ecology entrypoint exposes no test invocation API";
    "artifact_closure",s"Entire final indrajaal_gleam_web build closure, including its cepaf_gleam dependency; no independently compiled production modules merged";
    "payload_sha256",s payload_hash;"source_sha256",s(digest(json before));
    "otp",obj["executable",erl;"identity",identity];"application_closure",closure;
    "files",arr content;"application_admitted",`Bool false] in
  let candidate=digest(canonical manifest) in
  let manifest=obj(("candidate_sha256",s candidate)::to_assoc manifest) in
  write(temporary^"/release-manifest.json")(json manifest);
  need(same before(source_manifest root inputs)) "source changed during packaging; partial stage retained";
  verify_dependencies deps;ignore(verify ~staging:true temporary);freeze temporary;
  let now=gmtime(gettimeofday()) in
  let stamp=Printf.sprintf "%04d%02d%02d-%02d%02d" (now.tm_year+1900)(now.tm_mon+1)now.tm_mday now.tm_hour now.tm_sec in
  let final=parent^"/"^stamp^"-"^candidate in
  need(not(Sys.file_exists final)) "release target already exists";rename temporary final;
  let fd=openfile parent [O_RDONLY;O_CLOEXEC] 0 in Fun.protect(fun()->fsync fd)~finally:(fun()->close fd);
  obj["status",s"PASS";"release",s final;"candidate_sha256",s candidate;"payload_sha256",s payload_hash;
    "source_sha256",s(digest(json before));"files",`Int(List.length content);
    "payload_bytes",`Int size;"otp",identity;"application_admitted",`Bool false]
let selftest () =
  let count=ref 0 in let check name f=need(f())("selftest failed: "^name);incr count in
  let rejects f=try f();false with _ -> true in
  check "traversal" (fun()->not(safe_relative "a/../b"));
  check "absolute" (fun()->not(safe_relative "/etc/passwd"));
  check "newline" (fun()->not(safe_relative "a\nb"));
  check "stable-json" (fun()->same(obj["b",`Int 1;"a",`Int 2])(obj["a",`Int 2;"b",`Int 1]));
  let dir=Filename.temp_file "uos-ecology-package-test-" "" in unlink dir;mkdir dir;
  write(dir^"/one.beam")"fixture";let first=inventory dir in
  check "stable-inventory" (fun()->same(arr first)(arr(inventory dir)));
  write(dir^"/extra.db")"fixture";
  check "unexpected-file" (fun()->not(same(arr first)(arr(inventory dir))));
  unlink(dir^"/extra.db");unlink(dir^"/one.beam");
  check "missing-file" (fun()->rejects(fun()->ignore(inventory dir)));
  write(dir^"/one.beam")"mutated";
  check "tampered-file" (fun()->not(same(arr first)(arr(inventory dir))));
  symlink "/etc/passwd" (dir^"/escape");
  check "symlink-refusal" (fun()->rejects(fun()->ignore(inventory dir)));
  unlink(dir^"/escape");
  let path=dir^"/one.beam" in let dep=obj["path",s path;"sha256",s(sha path)] in
  let dependencies=obj(("schema",s"uos.ecology-runtime-dependencies.v1")::List.map(fun n->n,dep)["ocaml";"pixi";"erl";"max_manifest";"max_lock";"environment_python"]) in
  verify_dependencies dependencies;
  unlink path;write path "changed-dependency";
  check "dependency-tampering" (fun()->rejects(fun()->verify_dependencies dependencies));
  unlink path;
  check "missing-dependency" (fun()->rejects(fun()->verify_dependencies dependencies));
  (* Exercise the public verifier's negative path, not just inventory helpers.
     No valid executable/dependency is supplied: failures must occur at the exact
     inventory boundary before any runtime dependency read or subprocess. *)
  write(dir^"/.uos-ecology-release")marker;
  write(dir^"/one.beam")"fixture";
  let expected=inventory dir in
  let m=obj["schema",s"uos.ecology-release-manifest.v1";"files",arr expected;
    "payload_sha256",s(digest(canonical(arr expected)));"application_admitted",`Bool false] in
  let m=obj(("candidate_sha256",s(digest(canonical m)))::to_assoc m) in
  write(dir^"/release-manifest.json")(json m);
  let refused_at_inventory () = try ignore(verify ~staging:true dir);false with
    | Failure m -> m="release inventory differs (missing, unexpected or changed file)"
    | _ -> false in
  write(dir^"/unexpected.txt")"fixture";
  check "verify-unexpected-file" refused_at_inventory;unlink(dir^"/unexpected.txt");
  unlink path;check "verify-missing-file" refused_at_inventory;
  write path "tampered";check "verify-tampered-file" refused_at_inventory;
  unlink path;write path "fixture";
  unlink(dir^"/release-manifest.json");
  let changed=obj(("application_admitted",`Bool true)::List.remove_assoc "application_admitted" (to_assoc m)) in
  write(dir^"/release-manifest.json")(json changed);
  check "verify-admission-refusal" (fun()->try ignore(verify ~staging:true dir);false with Failure e -> e="package cannot grant admission" | _->false);
  List.iter(fun p->unlink(dir^"/"^p))(files dir "");
  rmdir dir;
  obj["status",s"PASS";"checks",`Int !count;"scope",s"bounded filesystem and direct release-verifier falsifiers; no external subprocesses or admission"]
let () = try
  need(Array.length Sys.argv<=3 && Array.for_all(fun x->String.length x<=4096)Sys.argv) "usage: ecology_release.ml stage ROOT | verify RELEASE | selftest";
  let result=match Array.to_list Sys.argv with
    | [_;"stage";root] -> stage root
    | [_;"verify";release] -> let m=verify release in obj["status",s"PASS";"release",s release;"payload_sha256",member "payload_sha256" m;"application_admitted",`Bool false]
    | [_;"selftest"] -> selftest()
    | _ -> failwith "usage: ecology_release.ml stage ROOT | verify RELEASE | selftest" in
  print_string(json result)
with e -> prerr_endline(Yojson.Safe.to_string(obj["status",s"FAIL";"error",s(Printexc.to_string e);"application_admitted",`Bool false]));exit 1
