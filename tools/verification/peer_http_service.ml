#!/usr/bin/env -S opam exec -- ocaml
#use "./tests/acceptance/run.ml";;

(** @agent_intent: build and observe the actual Gleam peer diagnostic through
    a fixed CLI profile. Expected test observations never enter this interface.
    @laws: failed build, missing JSON, signal, quota or unreaped child rejects;
    successful observation may still have UNAVAILABLE/UNVERIFIED domain state. *)

type peer_profile = Current_peer | Obsolete_peer
let peer_profile_arg = function Current_peer -> "current" | Obsolete_peer -> "obsolete"
let peer_limits = { timeout_ms=600_000; stdout_limit=131_072; stderr_limit=131_072; term_grace_ms=100 }
let peer_succeeded expected result = result.termination=Exited expected
  && result.children_reaped && not result.stdout_truncated && not result.stderr_truncated

let peer_ebins () =
  let root="build/dev/erlang" in
  Sys.readdir root |> Array.to_list |> List.sort String.compare
  |> List.concat_map (fun name ->
    let path=Filename.concat (Filename.concat root name) "ebin" in
    if Sys.file_exists path && Sys.is_directory path then ["-pa";path] else [])

let peer_observe profile =
  let root=Sys.getcwd() in
  let deadline=monotonic_now()+.1190. in
  let run argv =
    let available=int_of_float ((deadline-.monotonic_now())*.1000.)-1000 in
    if available<=0 then Error "peer task budget exhausted"
    else Ok (run_bounded {peer_limits with timeout_ms=min 600_000 available} argv) in
  try Fun.protect ~finally:(fun()->Sys.chdir root) (fun()->
    Sys.chdir (Filename.concat root "apps/cepaf_gleam");
    match run ["gleam";"build"] with
    | Error _ as error -> error
    | Ok build when not(peer_succeeded 0 build) ->
        Error ("peer build did not pass: "^build.stderr)
    | Ok _ ->
        let argv=["erl";"-noshell"] @ peer_ebins() @
          ["-eval";"'cepaf_gleam@verification@peer_health_cli':main().";
           "-extra";peer_profile_arg profile] in
        match run argv with
        | Error _ as error -> error
        | Ok result when not(peer_succeeded 1 result) ->
            Error ("peer diagnostic must exit nonzero while unverified: "^result.stderr)
        | Ok result ->
            match parse_json_strict result.stdout with
            | Error e -> Error(string_of_contract_error e)
            | Ok (`Assoc fields as json) ->
                let get name=List.assoc_opt name fields in
                if get "schema"<>Some(`String "uos.peer-health.v1")
                   || get "system_green"<>Some(`Bool false)
                   || get "build_identity"<>Some(`String "UNKNOWN") then
                  Error "peer diagnostic violated its non-admission contract"
                else Ok json
            | Ok _ -> Error "peer diagnostic must emit a JSON object")
  with exn -> Error ("peer diagnostic setup: "^Printexc.to_string exn)

let peer_main () =
  let profile=match Array.to_list Sys.argv with
    | [_;"current"] -> Some Current_peer
    | [_;"obsolete"] -> Some Obsolete_peer
    | _ -> None in
  match profile with
  | None -> prerr_endline "usage: peer_http_service.ml current|obsolete";2
  | Some profile -> match peer_observe profile with
    | Error reason -> prerr_endline reason;2
    | Ok json -> print_endline(Yojson.Basic.to_string json);1

let () = if Filename.basename Sys.argv.(0)="peer_http_service.ml" then exit(peer_main())
