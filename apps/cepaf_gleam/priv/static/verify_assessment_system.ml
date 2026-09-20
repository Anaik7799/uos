#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson,digestif.ocaml,markup,uri";;
(* @agent_intent: verify artifact consistency and explicit hold, never safety.
   @laws: missing/changed files fail; each file checked against manifest;
   unknown provider state stays unknown; historical source truth not asserted. *)
let get = function Ok x -> x | Error (`Msg m) -> failwith m
let read p =
 let rec attempt n =
 let a=Unix.stat p in let s=get(Bos.OS.File.read(Fpath.v p)) in let second=get(Bos.OS.File.read(Fpath.v p)) in let b=Unix.stat p in
 if a.Unix.st_size=b.Unix.st_size && a.Unix.st_mtime=b.Unix.st_mtime && String.length s=b.Unix.st_size && s=second then s
 else if n=0 then failwith("unstable or short filesystem read: " ^ p)
 else (Unix.sleepf 0.1;attempt(n-1)) in attempt 2
let hash s = Digestif.SHA256.(to_hex(digest_string s))
let errors = ref []
let check b msg = if not b then errors := msg :: !errors
let contains s p =
 let n=String.length p in let rec loop i = i+n<=String.length s && (String.sub s i n=p || loop(i+1)) in loop 0
let same expected p = Sys.file_exists p && not(Sys.is_directory p) && hash(read p)=expected
let safe_relative p = Filename.is_relative p && not(List.exists(fun x->x="" || x=".." || x=".")(String.split_on_char '/' p))
let allowed_source p source = safe_relative source && (source=p || (p="Medical-Nordics-1.xlsx" && Filename.dirname source="versions/Medical-Nordics-1" && Filename.check_suffix source ".xlsx"))
let current p = List.mem p ["CODEX_HANDOVER.md";"PROJECTS_INDEX.md";"README.md";"SKILLS_AND_SUPERPOWERS_CATALOG.md"] || String.starts_with ~prefix:"governance/" p || String.starts_with ~prefix:"skills/" p
let inspect_html p s =
 check (String.starts_with ~prefix:"<!DOCTYPE html>" s) (p ^ ": missing doctype");
 check (contains s "<html lang=\"en\"") (p ^ ": language missing");
 check (contains s "Deployment hold.") (p ^ ": hold notice missing");
 check (not(contains s "<script")) (p ^ ": generated runtime script");
 let ids=Hashtbl.create 100 in
 let report (_loc,err) = errors := (p ^ ": " ^ Markup.Error.to_string err) :: !errors in
 s |> Markup.string |> Markup.parse_html ~report:(fun loc err -> report(loc,err)) |> Markup.signals |> Markup.iter(function
 | `Start_element ((_,_),attrs)->List.iter(fun ((_,k),v)->if k="id" then (check (not(Hashtbl.mem ids v))(p ^ ": duplicate id " ^ v); Hashtbl.replace ids v ()) else if k="href" && v<>"" && v.[0]<>'#' && not(String.contains v ':') then let path=Uri.pct_decode(List.hd(String.split_on_char '#' v)) in if path<>"" then check(Sys.file_exists path)(p ^ ": missing link " ^ path))attrs
 | _->())
let run full =
 let j=Yojson.Safe.from_string(read "ASSESSMENT_SYSTEM_REGISTRY.json") in
 let open Yojson.Safe.Util in
 check (j |> member "deployment_authorized" = `Bool false) "registry lacks deployment hold";
 let expected=j |> member "expected_engine_sha256" |> to_string in
 check (same expected "ach_admiralty_engine.ml") "ENGINE CONFLICT: current engine is not reviewed v2.1";
 let files=j |> member "files" |> to_list in
 List.iter(fun e->let p=e |> member "path" |> to_string and h=e |> member "sha256" |> to_string in
  let source=match e |> member "source_path" with `Null->p | `String s->s | _->failwith "invalid source_path" in
  check(safe_relative p)("unsafe manifest path " ^ p);
  check(safe_relative source)("unsafe source path " ^ source);
  check(allowed_source p source)("unexpected source redirection " ^ p);
  if p="Medical-Nordics-1.xlsx" && source<>p then begin
   let version_log=Yojson.Safe.from_string(read "versions/Medical-Nordics-1/manifest.json") in
   let latest=List.hd(List.rev(version_log |> member "versions" |> to_list)) in
   check(source="versions/Medical-Nordics-1/" ^ (latest |> member "snapshot" |> to_string) && h=(latest |> member "sha256" |> to_string)) "medical workbook registry does not select the latest version"
  end;
  if safe_relative p then begin
   if safe_relative source then check(same h source)("source changed/missing: " ^ source);
   check(same h ("projects/" ^ p)) ("project mirror changed/missing: " ^ p);
   if full then check(same h ("/home/an/NAS-setup/uos/apps/cepaf_gleam/priv/static/" ^ p)) ("served mirror changed/missing: " ^ p);
   if current p then List.iter(fun forbidden->check(not(contains(read p)forbidden))(p ^ ": stale claim: " ^ forbidden))["DECISIVELY CONFIRMED";"uncontested 24-month";"64k tokens";"100.0% Pass Rate"];
   if Filename.check_suffix p ".html" && contains(read p) "Bountytek OCaml static docs v3" then inspect_html p (read p)
  end)files;
 let registry_hash=hash(read "ASSESSMENT_SYSTEM_REGISTRY.json") in
 check(same registry_hash "projects/ASSESSMENT_SYSTEM_REGISTRY.json") "registry local mirror mismatch";
 if full then check(same registry_hash "/home/an/NAS-setup/uos/apps/cepaf_gleam/priv/static/ASSESSMENT_SYSTEM_REGISTRY.json") "served registry mismatch";
 let retired=j |> member "retired_paths" |> to_list |> List.map to_string in
 List.iter(fun p->List.iter(fun root->check(not(Sys.file_exists(root ^ p)))("retired path still active: " ^ root ^ p))(["";"projects/"] @ if full then ["/home/an/NAS-setup/uos/apps/cepaf_gleam/priv/static/"] else []))retired;
 if full then List.iter(fun e->let p=e |> member "path" |> to_string and h=e |> member "sha256" |> to_string in
  if String.starts_with ~prefix:"governance/" p || String.starts_with ~prefix:"skills/" p then
  let rel=if String.starts_with ~prefix:"governance/" p then String.sub p 11 (String.length p-11) else p in
  List.iter(fun adapter->check(same h ("/home/an/dev/ver/c3i/" ^ adapter ^ "/" ^ rel))("C3I mirror mismatch: " ^ adapter ^ "/" ^ rel))[".agents";".claude";".gemini";".codex"])files;
 if !errors=[] then Printf.printf "ARTIFACT_CHECK_PASS files=%d scope=%s; truth, model activation and operational safety NOT certified.\n" (List.length files) (if full then "local+served+C3I" else "local")
 else (List.iter prerr_endline(List.rev !errors); Printf.eprintf "ARTIFACT_CHECK_FAIL errors=%d\n" (List.length !errors); exit 1)
let self_test () =
 check(hash "abc"="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") "SHA256 oracle";
 check(not(same (hash "") "/tmp/bountytek-deliberately-nonexistent-file")) "missing must fail";
 check(not(safe_relative "../outside")) "reject parent escape";
 check(not(safe_relative "/tmp/outside")) "reject absolute";
 check(safe_relative "skills/a/SKILL.md") "accept bounded child";
 check(allowed_source "Medical-Nordics-1.xlsx" "versions/Medical-Nordics-1/v0001.xlsx") "accept explicit workbook snapshot";
 check(not(allowed_source "ach_admiralty_engine.ml" "versions/Medical-Nordics-1/v0001.xlsx")) "reject unrelated artifact redirection";
 check(not(allowed_source "Medical-Nordics-1.xlsx" "versions/Medical-Nordics-1/../escape.xlsx")) "reject workbook parent escape";
 check(contains "incomplete" "complete") "substring cannot distinguish provider completeness";
 let j=Yojson.Safe.from_string "{\"assessment_complete\":false}" in
 check (Yojson.Safe.Util.member "assessment_complete" j=`Bool false) "typed false stays false";
 if !errors<>[] then (List.iter prerr_endline !errors;exit 1);
 print_endline "Artifact verifier: 10 boundary checks passed."
let () = try match Array.to_list Sys.argv with
 | [_] -> run false
 | [_;"--all-mirrors"] -> run true
 | [_;"--self-test"] -> self_test()
 | _ -> failwith "usage: ocaml verify_assessment_system.ml [--all-mirrors|--self-test]"
 with Failure m -> prerr_endline m; exit 1
