#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
#require "str";;
(* @agent_intent Validate first-party plan metadata; never execute acceptance
   adapters, production builds, external source ingestion or deployment. *)
open Bos
open Yojson.Basic.Util
let get = function Ok x -> x | Error (`Msg e) -> failwith e
let root="/home/an/NAS-setup/uos"
let prefix="20260906-0817"
let backlog_path="governance/planning/"^prefix^"-uos-full-implementation-backlog.json"
let run args=get(OS.Cmd.(run_out(Cmd.of_list args)|>out_string|>success))|>String.trim
let read path=get(OS.File.read(Fpath.v path))
let json path=Yojson.Basic.from_string(read path)
let sha path=String.sub(run["sha256sum";"--";path])0 64
let str key j=member key j|>to_string
let arr key j=member key j|>to_list
let strings key j=arr key j|>List.map to_string
let s x=`String x
let errors=ref []
let check ok message=if not ok then errors:=message::!errors
let unique xs=List.length xs=List.length(List.sort_uniq String.compare xs)
let contains body needle=try ignore(Str.search_forward(Str.regexp_string needle)body 0);true with Not_found->false
let metadata path=
  let st=Unix.lstat path in
  if st.Unix.st_kind<>Unix.S_REG || st.Unix.st_size>4_000_000 then failwith("metadata quota/type: "^path);
  let first=sha path in ignore(read path);let last=sha path in
  if first<>last then failwith("file changed while recording: "^path);
  `Assoc["path",s path;"resolved_path",s(Unix.realpath path);"bytes",`Int st.Unix.st_size;
    "sha256",s first;"stable_during_metadata_capture",`Bool true]
let fence=String.make 3(Char.chr 96)
let blocks language body=
  let rec loop inside buffer found=function
  | []->if inside then failwith"unclosed code fence"else List.rev found
  | line::tail->
    if not inside && String.trim line=fence^language then loop true [] found tail
    else if inside && String.trim line=fence then loop false [] (String.concat "\n"(List.rev buffer)::found)tail
    else if inside then loop true(line::buffer)found tail else loop false [] found tail
  in loop false [] [](String.split_on_char '\n' body)
let count_matches regexp body=
  let rec loop at count=try ignore(Str.search_forward regexp body at);loop(Str.match_end())(count+1)with Not_found->count
  in loop 0 0
let ()=
  if Sys.getcwd()<>root then failwith("run from "^root);
  let input=json backlog_path in
  let tasks=arr "tasks" input and reqs=arr "requirements" input and streams=arr "workstreams" input in
  let ids=List.map(str "id")tasks and req_ids=List.map(str "id")reqs in
  check(List.length tasks=60 && unique ids)"expected sixty unique tasks";
  check(List.length reqs=35 && unique req_ids)"expected thirty-five unique requirements";
  check(List.length streams=8 && unique(List.map(str "id")streams))"expected eight unique workstreams";
  let task id=List.find(fun t->str "id" t=id)tasks in
  List.iter(fun t->
    let id=str "id" t in
    check(str "status" t="PLANNED")(id^" claims implementation credit");
    List.iter(fun d->check(List.mem d ids)(id^" unknown dependency "^d))(strings "depends_on" t);
    List.iter(fun r->check(List.mem r req_ids)(id^" unknown requirement "^r))(strings "requirements" t);
    check(List.length(strings "implementation_steps" t)>=3)(id^" missing implementation steps");
    check(str "acceptance_gate" t<>"")(id^" missing acceptance gate");
    let case=member "acceptance_case" t in
    check(str "id" case=id^"-regression")(id^" inconsistent case ID");
    check(to_assoc(member "given" case)<>[] && to_assoc(member "expect" case)<>[])(id^" empty fixture");
    match arr "when" case with
    | [action]->check(str "op" action=str "operation"(member "interfaces" t))(id^" operation mismatch")
    | _->check false(id^" ambiguous action"))tasks;
  check(unique(List.map(fun t->str "operation"(member "interfaces" t))tasks))"duplicate operation";
  List.iter(fun r->check(List.exists(fun t->List.mem r(strings "requirements" t))tasks)("uncovered requirement "^r))req_ids;
  let visiting=Hashtbl.create 64 and visited=Hashtbl.create 64 in
  let rec visit id=
    if Hashtbl.mem visiting id then failwith("dependency cycle at "^id);
    if not(Hashtbl.mem visited id)then begin
      Hashtbl.add visiting id ();List.iter visit(strings "depends_on"(task id));
      Hashtbl.remove visiting id;Hashtbl.add visited id ()
    end in
  if !errors=[] then List.iter visit ids;
  let rec ancestors seen id=
    if List.mem id seen then seen else List.fold_left ancestors(id::seen)(strings "depends_on"(task id))in
  if !errors=[] then check(List.length(ancestors [] "R03")=60)"not all tasks reach final admission";
  let creators=List.concat_map(fun t->arr "files" t|>List.filter_map(fun f->
    if str "mode" f="create"then Some(str "path" f,str "id" t)else None))tasks in
  check(unique(List.map fst creators))"duplicate planned file creator";
  let current_files=ref 0 and planned_files=ref 0 in
  List.iter(fun t->List.iter(fun f->
    let path=str "path" f and mode=str "mode" f and id=str "id" t in
    check(Filename.is_relative path && not(List.mem ".."(String.split_on_char '/' path)))(id^" unsafe path "^path);
    if mode="create"then begin incr planned_files;
      check(not(Sys.file_exists path))(id^" create target exists; use modify: "^path)
    end else if mode="modify" || mode="inspect"then begin
      if Sys.file_exists path then incr current_files else
      match List.assoc_opt path creators with
      | Some owner->check(List.mem owner(ancestors [] id))(id^" missing creator dependency "^owner^": "^path)
      | None->check false(id^" missing "^mode^" target "^path)
    end else check false(id^" bad file mode "^mode))(arr "files" t))tasks;
  let master=str "master_path" input and journal=str "journal_path" input in
  let documents=master::journal::List.map(str "path")streams in
  let cases_seen=ref [] in
  List.iter(fun path->
    check(String.starts_with ~prefix:(prefix^"-")(Filename.basename path))("timestamp prefix "^path);
    let body=read path in
    List.iter(fun marker->check(contains body marker)("missing marker "^marker^" in "^path))
      ["http://nas-1.tail55d152.ts.net:4100";"#fractal-l0";"#fractal-l9"];
    check(count_matches(Str.regexp "CHK-[0-9][0-9]-")body=18)("checkpoint table "^path);
    List.iter(fun pattern->check(not(contains(String.lowercase_ascii body)pattern))("placeholder "^pattern^" in "^path))
      ["tbd";"fill in details";"implement later";"similar to task"];
    List.iter(fun block->
      let case=Yojson.Basic.from_string block in let id=str "id" case in cases_seen:=id::!cases_seen;
      match List.find_opt(fun t->str "id"(member "acceptance_case" t)=id)tasks with
      | Some t->check(case=member "acceptance_case" t)("fixture drift "^id)
      | None->check false("unregistered fixture "^id))(blocks "json" body))documents;
  check(List.length !cases_seen=60 && unique !cases_seen)"sixty fixtures must appear exactly once";
  let graph=member "diagram" input in let nodes=to_assoc(member "nodes" graph)in
  let edges=arr "edges" graph|>List.map(function `List[`String a;`String b]->a,b|_->failwith"bad edge")in
  let ascii=blocks "text"(read master)|>List.concat_map(fun b->String.split_on_char '\n' b)|>List.map String.trim|>List.filter(fun l->contains l "] --> [")in
  let mermaid=blocks "mermaid"(read master)|>List.concat_map(fun b->String.split_on_char '\n' b)|>List.map String.trim|>List.filter(fun l->contains l " --> ")in
  let label id=List.assoc id nodes|>to_string in
  let expected_ascii=List.map(fun(a,b)->"["^a^" "^label a^"] --> ["^b^" "^label b^"]")edges in
  let expected_mermaid=List.map(fun(a,b)->a^"[\""^label a^"\"] --> "^b^"[\""^label b^"\"]")edges in
  let sorted=List.sort String.compare in
  check(sorted ascii=sorted expected_ascii && sorted mermaid=sorted expected_mermaid)"master diagram parity";
  let sections=["Scope & Trigger";"Pre-State Assessment";"Execution Detail";"Root Cause Analysis";"Fix Taxonomy";
    "Patterns & Anti-Patterns Discovered";"Verification Matrix";"Files Modified";"Architectural Observations";
    "Remaining Gaps";"Metrics Summary";"STAMP & Constitutional Alignment";"Conclusion"]in
  let jbody=read journal in
  List.iteri(fun i title->check(contains jbody(Printf.sprintf "## %d. %s"(i+1)title))("journal section "^title))sections;
  let families=to_assoc(member "zenoh_family_mapping" input)in
  check(List.length families=16)"sixteen Zenoh families required";
  List.iter(fun(id,ts)->check(to_list ts<>[])("unmapped family "^id))families;
  check(List.length(to_assoc(member "previous_handover_mapping" input))=17)"seventeen prior tasks required";
  let source_paths=strings "source_inputs" input in check(unique source_paths)"duplicate source input";
  List.iter(fun path->check(Sys.file_exists path)("missing source "^path))source_paths;
  let sources=List.filter Sys.file_exists source_paths|>List.map metadata in
  let old=json "governance/sources/20260906-0631-web-quality-evidence.json"in
  let originals=arr "source_preservation" old in
  let changed=List.filter(fun row->sha(str "path" row)<>str "initial_sha256" row)originals in
  check(List.length originals=161 && changed=[])"selected original OCaml drift";
  let link_re=Str.regexp_string "](http://nas-1.tail55d152.ts.net:4100/"in
  let artifact_links=ref 0 and receipt_path=str "receipt_path" input in
  List.iter(fun path->
    let body=read path in
    let rec scan at=
      try ignore(Str.search_forward link_re body at);let first=Str.match_end()in
        let last=String.index_from body first ')'in
        let target=String.sub body first(last-first)|>String.split_on_char '#'|>List.hd in
        let target=if String.starts_with ~prefix:"files/"target then String.sub target 6(String.length target-6)else target in
        if List.exists(fun prefix->String.starts_with ~prefix target)["docs/";"governance/";"tests/";"contracts/";"formal/";"apps/";"tools/";".codex/"] || target="HANDOVER_TO_CODEX.md" || target="AGENTS.md"then begin
          incr artifact_links;check(target=receipt_path || Sys.file_exists target)("broken artifact link "^target^" in "^path)
        end;scan(last+1)
      with Not_found->()
    in scan 0)(documents@["HANDOVER_TO_CODEX.md";"docs/zk/moc-agent-handover.md"]);
  if !errors<>[]then begin List.iter prerr_endline(List.rev !errors);exit 1 end;
  let receipt=`Assoc[
    "schema",s "uos.full-implementation-plan-receipt.v1";
    "clock_utc",s(run["date";"-u";"+%Y-%m-%dT%H:%M:%SZ"]);
    "host_sync",s(run["chronyc";"tracking"]);
    "candidate_before_receipt",s(run["jj";"log";"-r";"@";"--no-graph";"-T";"change_id ++ \" \" ++ commit_id"]);
    "status",s "PLAN_METADATA_VALIDATED_IMPLEMENTATION_UNRUN";
    "tasks",`Int 60;"requirements",`Int 35;"workstreams",`Int 8;"concrete_regression_fixtures",`Int 60;
    "acyclic_dependencies",`Bool true;"all_tasks_reach_final_admission",`Bool true;
    "requirements_covered",`Bool true;"fixture_backlog_parity",`Bool true;"master_diagram_parity",`Bool true;
    "journal_sections",`Int 13;"checkpoints_per_document",`Int 18;"artifact_links",`Int !artifact_links;
    "existing_file_references",`Int !current_files;"planned_create_references",`Int !planned_files;
    "zenoh_families_mapped",`Int 16;"previous_handover_tasks_mapped",`Int 17;
    "original_ocaml_rechecked",`Int 161;"original_ocaml_changed",`Int 0;
    "backlog",metadata backlog_path;"validator",metadata Sys.argv.(0);
    "documents",`List(List.map metadata documents);"source_inputs",`List sources;
    "implementation_cases_executed",`Int 0;"external_code_ingested",`Bool false;"subagents_dispatched",`Int 0;
    "limitations",`List(List.map s[
      "Metadata validation is not execution of planned acceptance fixtures or proof of implementation correctness.";
      "Targeted source review only; no complete close reading or fresh system runtime/native/browser/formal certification.";
      "Shared workspace and external sources can change; source quiescence/admission remain execution gates.";
      "No full conformance census, native performance winner, browser completion, deployment or independent reviewer signature."])
  ]in
  let temp=receipt_path^".tmp"in
  get(OS.File.write(Fpath.v temp)(Yojson.Basic.pretty_to_string receipt^"\n"));Unix.rename temp receipt_path;
  Printf.printf "Plan validated: 60 tasks, 35 requirements, 8 workstreams, 60 fixtures; DAG/files checked; 16 Zenoh families; 161 originals unchanged; %d artifact links. Implementation cases executed: 0.\n%!" !artifact_links

