#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
#require "str";;
(* @agent_intent Validate and publish first-party handover metadata; external
   source trees remain read-only and no source code is admitted.
   @laws Stable bounded metadata reads, truthful states, digest-checked datasets. *)
open Bos
open Yojson.Basic.Util
let get=function Ok x->x|Error(`Msg e)->failwith e
let root="/home/an/NAS-setup/uos"
let prefix="20260906-0606"
let run args=get(OS.Cmd.(run_out(Cmd.of_list args)|>out_string|>success))|>String.trim
let read p=get(OS.File.read(Fpath.v p))
let write p text=get(OS.File.write(Fpath.v p)text)
let sha p=String.sub(run["sha256sum";"--";p])0 64
let s x=`String x
let list k j=match member k j with `List xs->xs|_->[]
let str k j=match member k j with `String x->x|_->""
let json p=Yojson.Basic.from_string(read p)
let write_json p j=write p(Yojson.Basic.pretty_to_string j^"\n")
let absolute p=if Filename.is_relative p then root^"/"^p else p
let metadata p=
  let full=absolute p in let st=Unix.lstat full in
  if st.Unix.st_kind<>Unix.S_REG || st.Unix.st_size>4_000_000 then failwith("metadata quota/type: "^p);
  let before=sha full in ignore(read full);
  let after=sha full in if before<>after then failwith("source changed while recording "^p);
  ["path",s p;"resolved_path",s(Unix.realpath full);"bytes",`Int st.Unix.st_size;"sha256",s before;"stable_during_metadata_capture",`Bool true]
let count_csv text=
  let quoted=ref false and lines=ref 0 in
  String.iter(fun c->if c='"' then quoted:=not !quoted else if c='\n' && not !quoted then incr lines)text;
  if !quoted then failwith "unclosed CSV quote";!lines-1
let artifact_links path=
  let body=read path in
  let marker="](http://nas-1.tail55d152.ts.net:4100/" in
  let re=Str.regexp_string marker in
  let rec loop at acc=
    match (try Some(Str.search_forward re body at)with Not_found->None)with
    | None->List.rev acc
    | Some found->
      let first=found+String.length marker in
      let last=String.index_from body first ')' in
      let target=String.sub body first(last-first) in
      let target=List.hd(String.split_on_char '#' target) in
      let target=if String.starts_with ~prefix:"files/" target then String.sub target 6(String.length target-6) else target in
      let is_artifact=List.exists(fun prefix->String.starts_with ~prefix target)["docs/";"governance/";"tests/"]||target="HANDOVER_TO_CODEX.md" in
      if is_artifact && not(Sys.file_exists(absolute target))then failwith("broken artifact link in "^path^": "^target);
      loop(last+1)(if is_artifact then target::acc else acc)
  in loop 0 []
let check_json_index path expected=
  let j=json path in
  let total=List.fold_left(fun total part->
    let path=str "path" part in
    if sha path<>str "sha256" part then failwith("part changed: "^path);
    let n=List.length(list "records"(json path)) in
    if n<>to_int(member "records" part) then failwith "part count";
    total+n)0(list "parts" j) in
  if total<>expected || to_int(member "record_count" j)<>expected then failwith "index count";
  `Assoc["path",s path;"records",`Int total;"parts",`Int(List.length(list "parts" j));"digest_verified",`Bool true]
let copies=[
 "/tmp/uos-web-quality-review-template.md","review-template.md.in";
 "/tmp/uos-report-navigation.md","navigation-template.md.in";
 "/tmp/uos-report-checklist.md","checklist-template.md.in";
 "/tmp/uos-browser-report-template.md","browser-template.md.in";
 "/tmp/uos-sources-template.md","sources-template.md.in";
 "/tmp/uos-research-register.json","research-register.json";
 "/tmp/uos-local-review-register.json","local-review-register.json";
 "/tmp/uos-web-quality-gate.json","gate-receipt.json";
 "/tmp/uos-web-quality-gate-concurrent-failure.json","concurrent-gate-failure.json"
]
let ()=
  let input=json("tests/web_quality/"^prefix^"-handover-source-inputs.json") in
  let assert_unique label values=
    if List.length values<>List.length(List.sort_uniq String.compare values) then failwith("duplicate "^label) in
  let source_ids=List.map(str "id")(list "local" input@list "web" input) in
  assert_unique "source identifier" source_ids;
  let programme=member "zenoh_feature_programme" input in
  let families=list "families" programme in
  let candidates=list "candidate_sources" programme in
  if families=[] || candidates=[] then failwith "missing Zenoh feature/candidate matrix";
  assert_unique "Zenoh feature family"(List.map(str "id")families);
  assert_unique "Zenoh candidate"(List.map(str "id")candidates);
  assert_unique "Zenoh flag"(List.map to_string(list "feature_flags_observed_1_9" programme));
  let check_refs rows=List.iter(fun r->List.iter(fun id->
    if not(List.mem(to_string id)source_ids)then failwith("unresolved Zenoh source: "^to_string id))rows) in
  List.iter(fun r->check_refs(list "source_ids" r)[r])candidates;
  check_refs(list "source_ids" programme)[programme];
  check_refs(list "benchmark_source_ids" programme)[programme];
  List.iter(fun field->if member field programme<>`Bool false then failwith("review cannot certify "^field))
    ["full_upstream_api_census_complete";"full_implementation_complete";"native_benchmarks_executed"];
  List.iter(fun row->
    if str "status" row<>"PLANNED" || member "runtime_executed" row<>`Bool false || member "implementation_verified" row<>`Bool false then
      failwith "feature family must retain planned/unexecuted evidence state")families;
  let local=List.map(fun r->`Assoc(List.filter(fun(k,_)->k<>"path")(to_assoc r)@metadata(str "path" r)))(list "local" input) in
  let retained=List.map(fun(src,name)->
    let dst="tests/web_quality/20260906-0631-inputs/20260906-0631-"^name in
    ignore(get(OS.Dir.create ~path:true(Fpath.v(Filename.dirname dst))));
    let st=Unix.lstat src in if st.Unix.st_kind<>Unix.S_REG || st.Unix.st_size>900_000 then failwith "input quota";
    write dst(read src);if sha src<>sha dst then failwith "copy mismatch";`Assoc(metadata dst))copies in
  let dataset_checks=[
    check_json_index "docs/design/20260906-0631-source-corpus-index.json" 8047;
    check_json_index "docs/design/20260906-0631-cross-project-test-catalogue.json" 770
  ] in
  let csv_parts=read "docs/design/20260906-0631-cross-project-test-cases.csv"|>String.split_on_char '\n'|>List.tl|>List.filter((<>)"") in
  let csv_total=List.fold_left(fun total line->match String.split_on_char ',' line with
    | [path;n;hash]->if sha path<>hash then failwith "CSV digest";let actual=count_csv(read path) in
      if actual<>int_of_string n then failwith "CSV row count";total+actual
    | _->failwith "CSV manifest format")0 csv_parts in
  if csv_total<>23765 then failwith "CSV aggregate count";
  let old=json "governance/sources/20260906-0631-web-quality-evidence.json" in
  let originals=list "source_preservation" old in
  let changed=List.filter(fun r->sha(str "path" r)<>str "initial_sha256" r)originals in
  if List.length originals<>161 || changed<>[] then failwith "original source changed";
  let docs=[
   "docs/design/"^prefix^"-uos-agy-codex-unified-master-prompt.md";
   "docs/zk/"^prefix^"-agy-handover-understanding-and-actor-ecology-plan.md";
   "docs/journal/20260906-0631-web-knowledge-verification-journal.md";
   "docs/design/20260906-0631-web-knowledge-verification-review.md";
   "HANDOVER_TO_CODEX.md";"docs/zk/moc-agent-handover.md";
   "tests/web_quality/"^prefix^"-replay-guide.md"
  ] in
  let expected_sections=["Scope & Trigger";"Pre-State Assessment";"Execution Detail";"Root Cause Analysis";"Fix Taxonomy";"Patterns & Anti-Patterns Discovered";"Verification Matrix";"Files Modified";"Architectural Observations";"Remaining Gaps";"Metrics Summary";"STAMP & Constitutional Alignment";"Conclusion"] in
  let journal=read(List.nth docs 2) in
  List.iteri(fun i title->let line=Printf.sprintf "## %d. %s" (i+1) title in
    if not(List.mem line(String.split_on_char '\n' journal)) then failwith("journal section "^line))expected_sections;
  let artifact_link_count=List.fold_left(fun n path->n+List.length(artifact_links path))0 docs in
  let source_roots=["/home/an/dev/ver/zigvm";"/home/an/dev/ver/c3i";"/home/an/dev/ver/harness-bionic";
    "/home/an/dev/ver/c3i/sub-projects/c3i";"/home/an/dev/ver/c3i/sub-projects/sutra"] in
  let source_revisions=List.map(fun path->
    `Assoc["path",s path;"resolved_path",s(Unix.realpath path);
      "head_at_capture",s(run["git";"--no-optional-locks";"-C";path;"rev-parse";"HEAD"]);
      "quiesced",`Bool false;"dirty_manifest",s "NOT_CAPTURED_FOR_ADMISSION; targeted read-only evidence only"])source_roots in
  let receipt=`Assoc[
   "schema",s "uos.agy-handover-source-receipt.v1";
   "clock_utc",s(run["date";"-u";"+%Y-%m-%dT%H:%M:%SZ"]);
   "host_sync",member "chrony" old;
   "host_sync_receipt_time",member "clock_utc" old;
   "candidate_before_receipt",s(run["jj";"log";"-r";"@";"--no-graph";"-T";"change_id ++ \" \" ++ commit_id"]);
   "status",s "PROMPT_AND_REVIEW_DELIVERED_IMPLEMENTATION_PROGRAMME_OPEN";
   "source_writers_quiesced",`Bool false;"external_code_ingested",`Bool false;
   "original_ocaml_rechecked",`Int 161;"original_ocaml_changed",`Int 0;
   "local_sources",`List local;"web_sources",member "web" input;"unsuccessful_fetches",member "unsuccessful_fetches" input;"source_revisions",`List source_revisions;
   "zenoh_feature_programme",programme;
   "zenoh_matrix_validation",`Assoc["family_count",`Int(List.length families);"candidate_count",`Int(List.length candidates);
     "identifiers_unique",`Bool true;"source_references_resolve",`Bool true;"planned_states_preserved",`Bool true;
     "validation_scope",s "Metadata consistency only; not native feature execution, exhaustive API enumeration or performance evidence"];
   "retained_first_party_inputs",`List retained;
   "datasets",`List(dataset_checks@[`Assoc["csv_rows",`Int csv_total;"parts",`Int(List.length csv_parts);"digest_verified",`Bool true]]);
   "documents",`List(List.map(fun path->`Assoc(metadata path))docs);
   "publisher",`Assoc(metadata Sys.argv.(0));
   "publisher_input",`Assoc(metadata("tests/web_quality/"^prefix^"-handover-source-inputs.json"));
   "local_artifact_links_verified",`Int artifact_link_count;
   "journal_13_sections",`Bool true;
   "runtime_receipt",s "governance/sources/20260906-0631-web-quality-evidence.json";
   "runtime_receipt_is_historical_scoped_evidence",`Bool true;
   "limitations",`List(List.map s [
    "No full DMC/TCM, FPP/SysML, actor-ecology or all-site certification.";
    "C3I NIF source matching is not successful native load or transport execution.";
    "C3I-derived Zenoh is the operator-selected common UOS messaging layer; migration remains open.";
    "Three inspected native candidates are compared; legacy Indrajaal has the broadest inspected exports, but no native performance winner is established.";
    "Zenoh feature families and flags are a planned census; every selected-version API and target still needs implementation and execution evidence.";
    "External source writers not quiesced; no source ingestion/admission.";
    "Media locally retained, not remotely backed up; browser fixtures not live deployment.";
    "Historical controller snapshots retain scratch paths; gate is separately runnable."])
  ] in
  write_json("governance/sources/"^prefix^"-agy-handover-source-receipt.json")receipt;
  Printf.printf "Published %d local and %d web source records; 161 originals unchanged; JSON/CSV parts verified; 13 journal sections verified.\n%!"
    (List.length local)(List.length(list "web" input))
