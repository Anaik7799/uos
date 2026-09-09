#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson,cryptokit";;

(* @agent_intent: Check and execute one reviewed UOS SessionStart advisory.
   Usage: ocaml tools/verify_codex_hooks.ml PATH_TO_HOOKS_JSON
   @laws: malformed configuration, command failure, or invalid output fails;
   execution is bounded; this observation grants no hook trust or admission.
   The installed app-server hooks/list loader is verified separately. *)

open Yojson.Basic.Util

let require condition message = if not condition then failwith message
let unwrap = function Ok x -> x | Error (`Msg message) -> failwith message
let contains text needle =
  let length = String.length needle in
  let rec loop i = i + length <= String.length text &&
    (String.sub text i length = needle || loop (i + 1)) in
  loop 0
let one label = function [value] -> value | _ -> failwith (label ^ ": expected one item")
let sha bytes = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) bytes
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())

let verify path =
  let bytes = unwrap (Bos.OS.File.read (Fpath.v path)) in
  require (String.length bytes <= 16384) "hook configuration exceeds 16 KiB";
  let config = Yojson.Basic.from_string bytes in
  let keys = config |> to_assoc |> List.map fst in
  require (List.for_all (fun key -> List.mem key ["description"; "hooks"]) keys)
    "unsupported top-level hook field";
  let events = config |> member "hooks" |> to_assoc in
  require (List.map fst events = ["SessionStart"]) "expected only SessionStart";
  let group = List.assoc "SessionStart" events |> to_list |> one "SessionStart group" in
  let hook = group |> member "hooks" |> to_list |> one "SessionStart handler" in
  require (hook |> member "type" |> to_string = "command") "expected command handler";
  require (hook |> member "timeout" |> to_int = 5) "expected five-second hook timeout";
  let command = hook |> member "command" |> to_string in
  require (contains command "test -d '/home/an/NAS-setup/uos/.jj'")
    "expected standalone workspace presence guard";
  let invocation = Bos.Cmd.(v "timeout" % "--kill-after=1s" % "5s" % "sh" % "-c" % command) in
  let stdout = unwrap (Bos.OS.Cmd.run_out invocation |> Bos.OS.Cmd.out_string
    |> Bos.OS.Cmd.success) in
  require (String.length stdout <= 4096) "hook output exceeds 4 KiB";
  let result = Yojson.Basic.from_string stdout |> member "hookSpecificOutput" in
  require (result |> member "hookEventName" |> to_string = "SessionStart")
    "expected SessionStart output";
  let context = result |> member "additionalContext" |> to_string in
  List.iter (fun required -> require (contains context required) ("missing reminder: " ^ required))
    ["AGENTS.md"; "Jujutsu"; "Zero-Muda"; "Gleam/OTP"; "Sa-plan"; "advisory";
     "does not enforce policy or establish runtime admission"];
  require (not (contains context "rules enforced")) "false policy enforcement claim";
  `Assoc ["status", `String "PASS"; "config_path", `String path;
    "config_sha256", `String (sha bytes); "command_exit", `Int 0;
    "hook_event", `String "SessionStart"; "additional_context", `String context;
    "loader_verified_by_this_command", `Bool false; "hook_trust_granted", `Bool false;
    "runtime_admission", `String "NOT_GRANTED"]

let () =
  try
    require (Array.length Sys.argv = 2) "usage: verify_codex_hooks.ml PATH_TO_HOOKS_JSON";
    verify Sys.argv.(1) |> Yojson.Basic.pretty_to_string |> print_endline
  with exn ->
    Yojson.Basic.to_string (`Assoc ["status", `String "FAIL";
      "error", `String (Printexc.to_string exn); "runtime_admission", `String "NOT_GRANTED"])
    |> prerr_endline;
    exit 1
