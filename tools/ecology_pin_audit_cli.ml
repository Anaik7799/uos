#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,yojson,cryptokit";;
#mod_use "km_provenance/km_adjudication.ml";;
#mod_use "ecology_pin_edit.ml";;
#mod_use "ecology_pin_audit.ml";;
let ()=
  let report=match Array.to_list Sys.argv with
  |[_;repository;home]->Ecology_pin_audit.Audit.canonical ~repository ~home
    |>Ecology_pin_audit.Audit.export
  |_->`Assoc["schema",`String "uos.ecology-pin-audit.v1";"status",`String "HOLD";
      "authority",`String "NONE";"reason",`String "explicit_repository_and_home_required"]in
  let body=Yojson.Safe.to_string report in
  if String.length body>262144 then(
    print_endline "{\"schema\":\"uos.ecology-pin-audit.v1\",\"status\":\"HOLD\",\"authority\":\"NONE\",\"reason\":\"output_bound\"}";exit 2)
  else print_endline body
