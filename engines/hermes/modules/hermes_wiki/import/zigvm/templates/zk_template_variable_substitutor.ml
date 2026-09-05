#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "str";;
#require "unix";;

open Bos

let color_green = "\027[32m"
let color_red = "\027[31m"
let color_cyan = "\027[36m"
let color_reset = "\027[0m"

(**
  * @description ZK Template Variable Substitutor (L7 Fractal Script)
  * @agent_intent Substitutes {{DATE}}, {{AUTHOR}} and {{GIT_HASH}} in a
  *               template file with real system values and writes the result
  *               atomically. Usage: ... <template.md> <output.md>
  *
  * @laws
  * - L7-12 Deterministic Scaffolding: Generated notes must dynamically inherit mathematically bound system context.
  *)

let ( let* ) = Result.bind

let today () =
  let t = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d" (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday

let git_out args = OS.Cmd.run_out Cmd.(v "git" %% of_list args) |> OS.Cmd.to_string

let count_occurrences needle hay =
  let re = Str.regexp_string needle in
  let rec go i acc =
    match Str.search_forward re hay i with
    | exception Not_found -> acc
    | j -> go (j + String.length needle) (acc + 1)
  in
  go 0 0

let substitute template output =
  let* body = OS.File.read template in
  let* author = git_out [ "config"; "user.name" ] in
  let* hash = git_out [ "rev-parse"; "--short"; "HEAD" ] in
  let subs =
    [ ("{{DATE}}", today ()); ("{{AUTHOR}}", String.trim author); ("{{GIT_HASH}}", String.trim hash) ]
  in
  let counts = List.map (fun (k, _) -> (k, count_occurrences k body)) subs in
  let out =
    List.fold_left
      (fun acc (k, v) -> Str.global_replace (Str.regexp_string k) v acc)
      body subs
  in
  let tmp = Fpath.add_ext "tmp" output in
  let* () = OS.File.write tmp out in
  let* () = OS.Path.move ~force:true tmp output in
  Ok counts

let main () =
  match List.tl (Array.to_list Sys.argv) with
  | [ tpl; out ] -> (
      Printf.printf "%s==> L7 ZK Template Variable Substitutor Starting... <==%s\n" color_cyan color_reset;
      match substitute (Fpath.v tpl) (Fpath.v out) with
      | Ok counts ->
          let total = List.fold_left (fun a (_, c) -> a + c) 0 counts in
          List.iter (fun (k, c) -> Printf.printf "  %s: %d occurrence(s) substituted\n" k c) counts;
          Printf.printf "%s[SUCCESS] %d substitutions written to %s. L7 OK.%s\n" color_green total out color_reset;
          exit 0
      | Error (`Msg err) ->
          Printf.eprintf "%s[SUBSTITUTION ERROR] %s%s\n" color_red err color_reset;
          exit 1)
  | _ ->
      Printf.eprintf "usage: zk_template_variable_substitutor.ml <template.md> <output.md>\n";
      exit 2

let () = main ()
