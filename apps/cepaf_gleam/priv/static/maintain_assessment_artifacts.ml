#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson,digestif.ocaml";;
open Printf
(* @agent_intent: explicit scoped artifact sync; never install runtime credentials.
   @laws: preimage conflicts abort; unchanged preparation is idempotent;
   equality is byte equality, not evidence validity or deployment permission. *)
let get = function Ok x -> x | Error (`Msg m) -> failwith m
let read p =
 let rec attempt remaining =
  let a=Unix.stat p in let first=get(Bos.OS.File.read(Fpath.v p)) in
  let second=get(Bos.OS.File.read(Fpath.v p)) in let b=Unix.stat p in
  if a.Unix.st_size=b.Unix.st_size && a.Unix.st_mtime=b.Unix.st_mtime && String.length first=b.Unix.st_size && first=second then second
  else if remaining=0 then failwith("unstable or short filesystem read: " ^ p)
  else (Unix.sleepf 0.1; attempt(remaining-1)) in attempt 2
let hash s = Digestif.SHA256.(to_hex (digest_string s))
let digest p = if Sys.file_exists p then Some(hash(read p)) else None
let write p s =
 if Sys.file_exists p && read p=s then () else begin
 ignore(get(Bos.OS.Dir.create(Fpath.v(Filename.dirname p)))); get(Bos.OS.File.write(Fpath.v p)s); if read p<>s then failwith("write/read mismatch: " ^ p)
 end
let js = function None->`Null | Some s->`String s
let string j k = Yojson.Safe.Util.(j |> member k |> to_string)
let optional j k = match Yojson.Safe.Util.member k j with `Null->None | `String s->Some s | _->failwith("invalid " ^ k)
let base = "/home/an/dev/ver/c3i/sub-projects/work/gdrive/4-Temp/1-Bountytek"
let c3i = "/home/an/dev/ver/c3i"
let static = "/home/an/NAS-setup/uos/apps/cepaf_gleam/priv/static"
let stage = "/tmp/bountytek-governance-install-20260928"
let retired = ["verify_pharma_chemicals.mojo";"run_cycles_14_18.mojo";"run_cycles_19_23.mojo";"run_cycles_24_28.mojo";"build_presentation_deck.mojo"]
let skills = ["ach-admiralty-audit";"claude-extended-reasoning-audit";"agy-autonomous-orchestration";"codex-astra-sil6-invariant-guard";"nordic-medtech-go-to-market";"nordic-procurement-tender-intel"]
let policies = ["rules/bountytek-assessment.md";"agents/bountytek-assessment-reviewer.md";"plugins/bountytek-assessment-integrations.md"]
let governance = List.map(fun p->"governance/" ^ p)policies @ List.map(fun n->"skills/" ^ n ^ "/SKILL.md")skills
(* A native Google Sheet export shadows this binary workbook in rclone's mount.
   Its version manifest explicitly selects the immutable publication source. *)
let source_path p =
 if p<>"Medical-Nordics-1.xlsx" then p else
 let manifest=Filename.concat base "versions/Medical-Nordics-1/manifest.json" in
 if not(Sys.file_exists manifest) then p else
 let j=Yojson.Safe.from_string(read manifest) in
 let vs=Yojson.Safe.Util.(j |> member "versions" |> to_list) in
 let last=List.hd(List.rev vs) in let name=string last "snapshot" in
 if Filename.basename name<>name || not(Filename.check_suffix name ".xlsx") then failwith "unsafe medical workbook snapshot";
 let path="versions/Medical-Nordics-1/" ^ name in
 if digest(Filename.concat base path)<>Some(string last "sha256") then failwith "medical workbook snapshot checksum mismatch";
 path
let active_files () =
 let tops=Sys.readdir base |> Array.to_list |> List.filter(fun p->p<>"" && p.[0]<>'.' && not(Sys.is_directory(Filename.concat base p)) && not(List.mem p ("ASSESSMENT_SYSTEM_REGISTRY.json"::retired))) in
 List.sort String.compare (tops @ governance)
let role p =
 if List.mem p governance then "assessment_guidance"
 else if Filename.check_suffix p ".ml" then "automation"
 else if List.mem p ["CODEX_HANDOVER.md";"CODEX_HANDOVER.html";"PROJECTS_INDEX.md";"PROJECTS_INDEX.html";"README.md";"SKILLS_AND_SUPERPOWERS_CATALOG.md";"SKILLS_AND_SUPERPOWERS_CATALOG.html"] || String.starts_with ~prefix:"ACH_" p || String.starts_with ~prefix:"20260928-0934-ASSESSMENT_" p then "current_documentation"
 else if Filename.check_suffix p ".md" || Filename.check_suffix p ".html" then "historical_unvalidated_research"
 else "preserved_source_not_revalidated"
let json_write p j = write p (Yojson.Safe.pretty_to_string j ^ "\n")
let ensure_regular p = if Sys.file_exists p && (Unix.lstat p).Unix.st_kind <> Unix.S_REG then failwith("not a regular file: " ^ p)
let check_relative p = if not(Filename.is_relative p) || (String.split_on_char '/' p |> List.exists(fun x->x=".." || x="" || x=".")) then failwith("unsafe relative path: " ^ p)
let add_plan _n src dest =
 ensure_regular dest;
 let contents=Option.map read src in
 let before=digest dest and after=Option.map hash contents in
 if before=after then None else
 let snapshot=Filename.concat stage ("payload/" ^ Option.value ~default:"deleted" after) in
 Option.iter(write snapshot) contents;
 let rollback=Option.map(fun h->Filename.concat stage ("rollback/" ^ h))before in
 Option.iter(fun p->write p (read dest))rollback;
 Some(`Assoc["destination",`String dest;"snapshot",(match contents with None->`Null | Some _->`String snapshot);"before_sha256",js before;"after_sha256",js after;"rollback",js rollback])
let prepare () =
 let old_plan=stage ^ "/plan.json" in
 if Sys.file_exists old_plan then (let contents=read old_plan in write (stage ^ "/plans/" ^ hash contents ^ ".json")contents);
 let files=active_files() in
 List.iter check_relative files;
 let manifest=List.map(fun p->let src=source_path p in `Assoc["path",`String p;"source_path",`String src;"sha256",js(digest(Filename.concat base src));"role",`String(role p)])files in
 let plugin="/home/an/.codex/plugins/cache/openai-curated-remote/superpowers/6.4.2/.codex-plugin/plugin.json" in
 json_write "ASSESSMENT_SYSTEM_REGISTRY.json" (`Assoc[
 "schema_version",`Int 1;"scope",`String "Bountytek assessment artifacts; no global safety certification";
 "deployment_authorized",`Bool false;"decision",`String "HOLD_FOR_INDEPENDENT_SAFETY_REVIEW";
 "expected_engine_sha256",`String "fc1aed0907ba587116d9ce5eead09d17395269f950377d397f5b933aaafffe7c";
 "observed_provider_state",`String "historical trial: two usable of three; Claude access blocked";
 "plugins",`List[`Assoc["name",`String "superpowers";"version",`String "6.4.2";"manifest",`String plugin;"manifest_sha256",js(digest plugin);"state",`String "cached manifest observed; activation not attested; unchanged"]];
 "retired_paths",`List(List.map(fun p->`String p) retired);
 "files",`List manifest]);
 let all=files@["ASSESSMENT_SYSTEM_REGISTRY.json"] in
 List.iter(fun p->let src=Filename.concat base (source_path p) and dst=Filename.concat base ("projects/" ^ p) in ensure_regular dst; if digest src<>digest dst then write dst (read src))all;
 List.iter(fun p->let dst=Filename.concat base ("projects/" ^ p) in if Sys.file_exists dst then (write(Filename.concat base ("historical/20260928-pre-governance/projects/" ^ p))(read dst); get(Bos.OS.File.delete(Fpath.v dst))))retired;
 let changes=List.map(fun p->Some(Filename.concat base (source_path p)),Filename.concat static p)all @ List.map(fun p->None,Filename.concat static p)retired @
 List.concat_map(fun adapter->
 List.map(fun p->Some(Filename.concat base ("governance/" ^ p)),Filename.concat c3i (adapter ^ "/" ^ p))policies @
 List.map(fun n->let p="skills/" ^ n ^ "/SKILL.md" in Some(Filename.concat base p),Filename.concat c3i (adapter ^ "/" ^ p))skills
 )[".agents";".claude";".gemini";".codex"] in
 let entries=List.mapi(fun n (s,d)->add_plan n s d)changes |> List.filter_map Fun.id in
 json_write (stage ^ "/plan.json") (`Assoc["scope",`String "Bountytek artifact publication and C3I guidance mirrors only";"entries",`List entries]);
 let contents=read(stage ^ "/plan.json") in write(stage ^ "/plans/" ^ hash contents ^ ".json")contents;
 printf "%d registered files; local mirror synchronized; %d external changes staged in %s/plan.json\n" (List.length files) (List.length entries) stage
let allowed dest =
 let static_relative = if String.starts_with ~prefix:(static ^ "/") dest then Some(String.sub dest (String.length static+1) (String.length dest-String.length static-1)) else None in
 match static_relative with
 | Some p -> check_relative p; List.mem p (active_files()@["ASSESSMENT_SYSTEM_REGISTRY.json"]@retired)
 | None -> List.exists(fun adapter->List.exists(fun p->dest=Filename.concat c3i(adapter ^ "/" ^ p))policies || List.exists(fun n->dest=Filename.concat c3i(adapter ^ "/skills/" ^ n ^ "/SKILL.md"))skills)[".agents";".claude";".gemini";".codex"]
let install guidance_only dry_run =
 if not guidance_only && digest (Filename.concat base "ach_admiralty_engine.ml") <> Some "fc1aed0907ba587116d9ce5eead09d17395269f950377d397f5b933aaafffe7c" then failwith "engine differs from reviewed v2.1 source; resolve writer conflict before installation";
 let all=Yojson.Safe.Util.(Yojson.Safe.from_string(read(stage ^ "/plan.json")) |> member "entries" |> to_list) in
 let entries=if guidance_only then List.filter(fun e->not(String.starts_with ~prefix:(static ^ "/") (string e "destination")))all else all in
 (* Preflight the entire plan before the first mutation. Do not weaken a conflict. *)
 List.iter(fun e->let dest=string e "destination" in if not(allowed dest) then failwith("destination outside scope: " ^ dest); ensure_regular dest;
   if digest dest<>optional e "before_sha256" && digest dest<>optional e "after_sha256" then failwith("concurrent modification: " ^ dest);
   match optional e "snapshot" with None->() | Some p->
   if not(String.starts_with ~prefix:(stage ^ "/payload/") p) || digest p<>optional e "after_sha256" then failwith("payload changed: " ^ p);
   let source = if String.starts_with ~prefix:(static ^ "/") dest then Filename.concat base (source_path (String.sub dest (String.length static+1) (String.length dest-String.length static-1)))
    else let rel=String.sub dest (String.length c3i+1) (String.length dest-String.length c3i-1) in let slash=String.index rel '/' in let tail=String.sub rel (slash+1) (String.length rel-slash-1) in Filename.concat base (if String.starts_with ~prefix:"skills/" tail then tail else "governance/" ^ tail) in
   if digest source<>optional e "after_sha256" then failwith("source changed since staging: " ^ source))entries;
 if dry_run then Printf.printf "PLAN_CHECK_PASS entries=%d scope=%s; no writes.\n" (List.length entries) (if guidance_only then "C3I guidance" else "full")
 else begin
 List.iter(fun e->let dest=string e "destination" in if digest dest<>optional e "after_sha256" then begin
   if digest dest<>optional e "before_sha256" then failwith("concurrent modification before write: " ^ dest);
   (match optional e "snapshot" with None->get(Bos.OS.File.delete(Fpath.v dest)) | Some p->write dest (read p)) end;
   if digest dest<>optional e "after_sha256" then failwith("write verification failed: " ^ dest))entries;
 json_write(stage ^ (if guidance_only then "/guidance-receipt.json" else "/receipt.json"))(`Assoc["status",`String "artifact_files_installed_not_runtime_activated";"scope",`String(if guidance_only then "C3I guidance only" else "full artifact set");"changes",`Int(List.length entries);"plan_sha256",js(digest(stage ^ "/plan.json"));"deployment_authorized",`Bool false]);
 printf "Installed and byte-verified %d scoped artifact changes. No agents/plugins activated.\n" (List.length entries)
 end
let () = try
 if Sys.getcwd()<>base then failwith("run from " ^ base);
 match Array.to_list Sys.argv with [_;"--prepare"]->prepare() | [_;"--install"]->install false false | [_;"--install-guidance"]->install true false | [_;"--check-guidance-plan"]->install true true | _->failwith "usage: ocaml maintain_assessment_artifacts.ml --prepare|--install|--install-guidance|--check-guidance-plan"
 with Failure m -> prerr_endline m; exit 1
