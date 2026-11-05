#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,yojson,cryptokit";;
#mod_use "km_provenance/km_adjudication.ml";;
#mod_use "ecology_pin_edit.ml";;
#mod_use "ecology_pin_audit.ml";;
module P=Ecology_pin_edit.Pin
module A=Ecology_pin_audit.Audit
let repin_target ~root ~relative ~format ~capsule ~payload_sha256 =
  let path=Filename.concat root relative in
  if Sys.file_exists path then (
    let st=Unix.lstat path in
    if st.Unix.st_kind=Unix.S_REG && st.st_nlink=1 && st.st_uid=Unix.geteuid() && st.st_perm land 0o7022=0 then (
      let ic=open_in_bin path in
      let body=Fun.protect ~finally:(fun()->close_in ic)(fun()->really_input_string ic(in_channel_length ic))in
      let observed=match format with A.Json->P.inspect_all_json body|A.Toml->P.inspect_all_toml body in
      match observed with
      |Ok meta when meta<>[] ->
        let servers=List.map(fun (m:P.metadata)->m.server)meta|>List.sort_uniq String.compare in
        let edited=match format with
          |A.Json->P.json ~servers ~capsule ~payload_sha256 body
          |A.Toml->P.toml ~servers ~capsule ~payload_sha256 body in
        (match edited with
        |Ok prep ->
          let next=P.bytes_for_private_commit prep in
          if next<>body then (
            let tmp=path^".repin-tmp" in
            let fd=Unix.openfile tmp[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_TRUNC;Unix.O_CLOEXEC]st.Unix.st_perm in
            let oc=Unix.out_channel_of_descr fd in
            Fun.protect ~finally:(fun()->close_out oc)(fun()->output_string oc next);
            Unix.rename tmp path)
        |Error _->())
      |_->()))
let ()=
  let report=match Array.to_list Sys.argv with
  |[_;repository;home]->A.canonical ~repository ~home|>A.export
  |[_;"repin";repository;home;capsule;payload_sha256]->
    List.iter(fun(_,scope,relative,format)->
      let root=match scope with A.Repository->repository|A.Home->home in
      repin_target ~root ~relative ~format ~capsule ~payload_sha256)A.catalog;
    A.canonical ~repository ~home|>A.export
  |_->`Assoc["schema",`String "uos.ecology-pin-audit.v1";"status",`String "HOLD";
      "authority",`String "NONE";"reason",`String "explicit_repository_and_home_required"]in
  let body=Yojson.Safe.to_string report in
  if String.length body>262144 then(
    print_endline "{\"schema\":\"uos.ecology-pin-audit.v1\",\"status\":\"HOLD\",\"authority\":\"NONE\",\"reason\":\"output_bound\"}";exit 2)
  else print_endline body
