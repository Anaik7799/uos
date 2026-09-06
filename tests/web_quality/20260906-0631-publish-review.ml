#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
#require "str";;
(* @agent_intent Publish first-party audit artifacts and metadata, never original
   source code, credentials, databases or external test fixtures.
   @laws Failures remain explicit; copies are bounded and digest checked. *)
open Bos
open Yojson.Basic.Util
let get=function Ok x->x|Error(`Msg e)->failwith e
let read path=get(OS.File.read(Fpath.v path))
let write path data=get(OS.File.write(Fpath.v path)data)
let str r k=match member k r with `String x->x|_->""
let arr r k=match member k r with `List xs->xs|_->[]
let s x=`String x
let replace a b text=Str.global_replace(Str.regexp_string a)b text
let escape text=text|>replace "&" "&amp;"|>replace "<" "&lt;"|>replace ">" "&gt;"|>replace "|" "&#124;"|>replace "\n" " "
let run args=get(OS.Cmd.(run_out(Cmd.of_list args)|>out_string|>success))|>String.trim
let sha source_path=String.sub(run["sha256sum";"--";source_path])0 64
let root="/home/an/NAS-setup/uos"
let prefix="20260906-0631-"
let base=root^"/docs/design/"^prefix
let evidence="var/evidence/"^prefix^"web-quality"
let mkdir path=ignore(get(OS.Dir.create ~path:true(Fpath.v path)))
let copy source_path target_path=write target_path(read source_path)
let header=read "/tmp/uos-report-navigation.md"
let footer=read "/tmp/uos-report-checklist.md"
let json path=Yojson.Basic.from_string(read path)
let write_json path doc=write path(Yojson.Basic.pretty_to_string doc^"\n")
let metadata path=
  let st=Unix.lstat path in
  if st.Unix.st_kind<>Unix.S_REG then failwith "Not a regular evidence file";
  `Assoc["path",s path;"bytes",`Int st.Unix.st_size;"sha256",s(sha path);"mtime_unix",`Float st.Unix.st_mtime]
let copy_media source_dir lane=
  let dest=root^"/"^evidence^"/"^lane in mkdir dest;
  let bytes=ref 0 in
  let files=Array.to_list(Sys.readdir source_dir)|>List.sort String.compare
    |>List.filter(fun name->String.starts_with ~prefix:"cycle-" name || name="manifest.json") in
  List.map(fun name->let source_path=source_dir^"/"^name in
    let st=Unix.lstat source_path in
    if st.Unix.st_kind<>Unix.S_REG || st.Unix.st_size>50_000_000 then failwith "Media quota";
    bytes:= !bytes+st.Unix.st_size;if !bytes>400_000_000 then failwith "Lane quota";
    let target=dest^"/"^name in copy source_path target;
    if sha source_path<>sha target then failwith "Media digest mismatch";
    `Assoc(("relative_path",s(evidence^"/"^lane^"/"^name))::to_assoc(metadata target)))files
let table headers rows=
  let row fields="| "^String.concat " | " fields^" |\n" in
  row headers^row(List.map(fun _->"---")headers)^String.concat ""(List.map row rows)
let template path replacements=
  List.fold_left(fun text(k,v)->replace("{{"^k^"}}")v text)(read path)
    (("navigation",header)::("checklist",footer)::replacements)
let local_register ()=
  let doc=json "/tmp/uos-local-review-register.json" in
  let enrich r=
    let path=str r "path" in
    let fallback="/home/an/.codex/skills/"^str r "name"^"/SKILL.md" in
    let path=if Sys.file_exists path then path else if str r "name"<>"" && Sys.file_exists fallback then fallback else path in
    if Sys.file_exists path then `Assoc(List.filter(fun(k,_)->k<>"path")(to_assoc r)@["path",s path;"sha256_at_publication",s(sha path)])
    else `Assoc(to_assoc r@["status_at_publication",s "PATH_NOT_FOUND"]) in
  `Assoc["documents",`List(List.map enrich(arr doc "documents"));"skills",`List(List.map enrich(arr doc "skills"))]
let ()=
  mkdir(root^"/"^evidence);mkdir(root^"/tests/web_quality");mkdir(root^"/governance/sources");
  let lanes=["document-repair","/tmp/uos-document-candidate-browser";"mobile-repair","/tmp/uos-document-mobile-fixed-browser";"navigation-repair","/tmp/uos-document-navigation-fixed-browser"] in
  let artifacts=copy_media "/tmp/uos-browser-cycles" "baseline" @List.concat_map(fun(lane,path)->copy_media path lane)lanes in
  let helpers=["browser-baseline.ml","/tmp/uos-browser-cycles.ml";"document-candidate-browser.ml","/tmp/uos-document-candidate-probe.ml";"cross-corpus.ml","/tmp/uos-cross-corpus.ml";"cross-publish.ml","/tmp/uos-cross-publish.ml";"chunk-evidence.ml","/tmp/uos-chunk-evidence.ml";"publish-review.ml","/tmp/uos-publish-review.ml";"agy-config-repair.ml","/tmp/uos-agy-config-repair.ml"] in
  List.iter(fun(name,path)->copy path(root^"/tests/web_quality/"^prefix^name))helpers;
  let fixtures=["document-initial.html","/tmp/uos-document-candidate.html";"document-mobile.html","/tmp/uos-document-candidate-mobile-fix.html";"document-navigation.html","/tmp/uos-document-candidate-navigation-fix.html"] in
  List.iter(fun(name,path)->copy path(root^"/"^evidence^"/"^name))fixtures;
  let research=json "/tmp/uos-research-register.json" and local=local_register() in
  write_json(base^"source-register.json")(`Assoc["web",research;"local",local]);
  let web_rows=arr research "sources"|>List.map(fun r->[str r "id"^" — ["^escape(str r "title")^"]("^str r "url"^")";escape(str r "version_or_revision");escape(str r "use")]) in
  let local_rows=arr local "documents"|>List.map(fun r->[str r "id";escape(str r "path");escape(str r "review_depth");escape(str r "finding")]) in
  let skill_rows=arr local "skills"|>List.map(fun r->[str r "name";escape(str r "path");str r "status";escape(str r "use")]) in
  let failed_rows=arr research "unsuccessful_fetches"|>List.map(fun r->[escape(str r "url");escape(str r "result")]) in
  write(base^"sources-and-research.md")(template "/tmp/uos-sources-template.md" [
    "web",table["Primary source";"Version and scope";"Proposed use"]web_rows;
    "local",table["ID";"Filesystem locator";"Review depth";"Finding"]local_rows;
    "skills",table["Skill";"Source";"Role";"Adaptation"]skill_rows;
    "failed",table["Attempted source";"Result"]failed_rows]);
  let baseline=json "/tmp/uos-browser-cycles/manifest.json" in
  let rows=arr baseline "pages"|>List.map(fun route->let route=to_string route in
    let rs=arr baseline "results"|>List.filter(fun r->str r "route"=route) in
    let status cycle=match List.find_opt(fun r->member "cycle" r=`Int cycle)rs with None->"UNRUN"|Some r->str r "status" in
    let reasons=List.concat_map(fun r->List.map to_string(arr r "violations"))rs|>List.sort_uniq String.compare
      |>List.filter(fun v->not(String.starts_with ~prefix:"control_overflow:" v)) in
    ["["^escape route^"](http://nas-1.tail55d152.ts.net:4100"^route^")";status 1;status 2;status 3;status 4;escape(String.concat "; " reasons)]) in
  let lane_rows=List.map(fun(name,path)->let rs=arr(json(path^"/manifest.json"))"results" in
    let checks=List.concat_map(fun r->arr r "checks")rs in
    let passed=List.length(List.filter(fun c->member "passed" c=`Bool true)checks) in
    let overflow=List.fold_left(fun n r->n+List.length(arr r "overflowing_control_indices"))0 rs in
    [name;string_of_int(List.length rs);Printf.sprintf "%d/%d"passed(List.length checks);string_of_int overflow])lanes in
  write(base^"browser-verification.md")(template "/tmp/uos-browser-report-template.md" ["routes",table["Route";"Desktop";"Mobile";"Tablet";"Wide";"Other failures (overflow also in ledger)"]rows;"lanes",table["Iteration";"Contexts";"Semantic checks passing";"Control overflows"]lane_rows]);
  write(base^"web-knowledge-verification-review.md")(template "/tmp/uos-web-quality-review-template.md" []);
  let inv=json(root^"/docs/journal/20260906-0428-ocaml-web-tests-inventory.json") in
  let preservation=arr inv "records"|>List.map(fun r->let path="/home/an/dev/ver/zigvm/"^str r "path" in
    let current=sha path in `Assoc["path",s path;"initial_sha256",member "sha256" r;"current_sha256",s current;"unchanged",`Bool(current=str r "sha256")]) in
  let inputs=["tools/web_quality_gate.ml";"apps/cepaf_gleam/src/cepaf_gleam/verification/web_quality_contract.gleam";"apps/cepaf_gleam/test/web_quality_contract_test.gleam";"apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam";"apps/indrajaal_gleam_web/test/document_render_contract_test.gleam"]|>List.map(fun p->metadata(root^"/"^p)) in
  let receipt=`Assoc["schema",s "uos.web-quality-review-evidence.v1";"clock_utc",s(run["date";"-u";"+%Y-%m-%dT%H:%M:%SZ"]);"chrony",s(run["chronyc";"tracking"]);
    "current_jj",s(run["jj";"log";"--no-graph";"-r";"@";"-T";"change_id ++ \" \" ++ commit_id"]);
    "admission",s "NOT_ADMITTED_SITE_FAILURES_AND_UNRUN_SCOPE_REMAIN";"source_writers_quiesced",`Bool false;"external_source_ingestion",s "NONE_METADATA_AND_REVIEW_ONLY";
    "gate",json "/tmp/uos-web-quality-gate.json";"concurrent_build_failure",json "/tmp/uos-web-quality-gate-concurrent-failure.json";
    "web_unit_tests",s "8 passed, no failures; scoped apps/indrajaal_gleam_web invocation";
    "baseline",`Assoc["pages",`Int 46;"attempts",`Int 184;"pass",`Int 0;"fail",`Int 183;"error",`Int 1];
    "candidate_browser_lanes",`List(List.map(fun(name,path)->`Assoc["name",s name;"manifest",json(path^"/manifest.json")])lanes);
    "source_preservation",`List preservation;"current_inputs",`List inputs;
    "fixture_hashes",`List(List.map(fun(name,_)->metadata(root^"/"^evidence^"/"^name))fixtures);
    "helper_hashes",`List(List.map(fun(name,_)->metadata(root^"/tests/web_quality/"^prefix^name))helpers);"artifacts",`List artifacts] in
  write_json(root^"/governance/sources/"^prefix^"web-quality-evidence.json")receipt;
  Printf.printf "Published reports; %d artifacts; %d original source digests checked.\n%!"(List.length artifacts)(List.length preservation)
