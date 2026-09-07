#!/usr/bin/env -S opam exec -- ocaml
#use "./tools/verification/peer_http_service.ml";;

let () =
  let original=Sys.getcwd() in
  let build=Fun.protect ~finally:(fun()->Sys.chdir original)(fun()->
    Sys.chdir "apps/cepaf_gleam";
    run_bounded peer_limits ["gleam";"build"]) in
  if not(peer_succeeded 0 build) then failwith ("build failed: "^build.stderr);
  let result=Fun.protect ~finally:(fun()->Sys.chdir original)(fun()->
    Sys.chdir "apps/cepaf_gleam";
    let test="peer_health_test:refused_observation_remains_unavailable_test(), "^
      "peer_health_test:http_success_cannot_create_system_health_test(), "^
      "peer_health_test:malformed_and_foreign_identity_fail_closed_test(), "^
      "peer_health_test:failing_http_and_probe_quota_are_nonpassing_test(), "^
      "peer_health_test:unavailable_ui_and_json_share_the_actual_state_test(), "^
      "peer_health_test:duplicate_identity_and_trailing_documents_are_rejected_test(), "^
      "{error,_}=uos_peer_http_ffi:probe(<<\"http://127.0.0.1:4100/api/health\">>), halt(0)." in
    run_bounded peer_limits (["erl";"-noshell"]@peer_ebins()@["-eval";test])) in
  if not(peer_succeeded 0 result) then failwith ("peer test failure: "^result.stderr);
  match peer_observe Obsolete_peer with
  | Error reason -> failwith reason
  | Ok json ->
      let get name=Yojson.Basic.Util.member name json in
      if get "status"<>`String "UNAVAILABLE" || get "system_green"<>`Bool false
         || get "timeout_seconds"<>`Int 1200 then failwith "obsolete endpoint no longer matches unavailable control";
      print_endline "peer_http_service_test: six production functions, endpoint allowlist and actual obsolete diagnostic passed"
