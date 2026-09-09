#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
let root="/home/an/NAS-setup/uos"
let workspace=root^"/.uos-workspaces/codex-ev-admission-20260909-0210"
let runtime=root^"/toolchains/opam-ocaml/bin/ocamlrun"
let ocaml=root^"/toolchains/opam-ocaml/bin/ocaml"
let adapter=workspace^"/tools/ev_native.ml"
let revision="14057e08112c1cd5d44297eac6a9c853e8287b7a"
let variant=Sys.argv.(1)
let target=Sys.argv.(2)
let require b why=if not b then failwith why
let run program argv=Receipt_validator.run ~seconds:100. ~limit:4_194_304 program argv
let read p=let st=Unix.lstat p in
  require(st.st_kind=Unix.S_REG && st.st_size<=4_194_304)"bounded regular input";
  let ch=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr ch)(fun()->
    require(Receipt_validator.same_stat st(Unix.fstat(Unix.descr_of_in_channel ch)))"input identity";
    let s=really_input_string ch st.st_size in
    require(Receipt_validator.same_stat st(Unix.fstat(Unix.descr_of_in_channel ch)))"input changed";s)
let write=Ev_campaign.write
let hash=Receipt_validator.sha
let ()=
  require(List.mem variant["report";"cleanup";"receive";"quota"] && not(Sys.file_exists target))"fresh private closed fault fixture";
  print_string(run runtime[ocaml;"/tmp/ev_composed_peer_stage.ml";revision;target;"transport"]);
  let source="tools/ev_transport_"^variant^"_fault.ml" in
  let helper=run(root^"/toolchains/nix-profile/bin/jj")
    ["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace;
     "file";"show";"-r";"commit_id(\""^revision^"\")";"-T";"\"\"";"--";"root:"^source] in
  let helper_path=target^"/mutator.ml" in write helper_path helper;
  print_string(run runtime[ocaml;helper_path;target^"/package"]);
  let open Yojson.Basic.Util in
  let original=Yojson.Basic.from_string(read(target^"/bindings.json")) in
  let changes=original |> member "sources" |> to_list |> List.filter_map(fun j->
    let staged=j |> member "staged" |> to_string in let bytes=read staged in
    let old_hash=j |> member "sha256" |> to_string in
    if hash bytes=old_hash then None else Some(`Assoc[
      "source",member "source" j;"staged",`String staged;"baseline_sha256",`String old_hash;
      "variant_sha256",`String(hash bytes);"variant_bytes",`Int(String.length bytes)])) in
  require(List.length changes=2)"exact two-file private fault variant required";
  write(target^"/fault-bindings.json")(Yojson.Basic.pretty_to_string(`Assoc[
    "source_candidate",`String revision;"variant",`String variant;"authority",`String "NONE";
    "baseline_manifest_sha256",`String(hash(read(target^"/bindings.json")));
    "mutator_source",`String source;"mutator_sha256",`String(hash helper);
    "changes",`List changes;"review_driver_sha256",`String(hash(read "/tmp/ev_transport_independent_fault.ml"))])^"\n");
  print_string(run runtime[ocaml;adapter;"--cwd";target^"/package";"--seconds";"60";
    "--receipt";target^"/compile.json";"--";"gleam";"compile-package";"--target";"erlang";
    "--package";target^"/package";"--out";target^"/compiled";"--lib";target^"/lib"]);
  let erlexec="/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/erts-17.0.5/bin/erlexec" in
  print_string(run runtime([ocaml;adapter;"--cwd";target;"--seconds";"35";
    "--receipt";target^"/runtime.json";"--";"native";erlexec;"-noshell";"-noinput"] @
    List.concat_map(fun name->["-pa";target^"/lib/"^name^"/ebin"])
      ["gleam_stdlib";"gleam_erlang";"gleam_otp";"gleam_json";"gleeunit"] @
    ["-pa";target^"/compiled/ebin";"-s";"mesh_zenoh_live_test";"main";"-s";"init";"stop"]))
