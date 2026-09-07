#!/usr/bin/env -S opam exec -- ocaml
#use "product_workflow.ml";;
(* A read-only database projection in the existing native document cockpit.
   The timestamp, candidate and expiry are visible. Refreshing is explicit;
   the document is never a second source of product or task authority. *)
let md text =
 let b=Buffer.create(String.length text) in
 String.iter(function '&'->Buffer.add_string b "&amp;"|'<'->Buffer.add_string b "&lt;"|'>'->Buffer.add_string b "&gt;"|
  '|'->Buffer.add_string b "\\|"|'\n'|'\r'->Buffer.add_char b ' '|c->Buffer.add_char b c)text;Buffer.contents b
let optional key j=match member key j with `String value->value|`Null->"—"|value->encoded value
let utc t=let x=Unix.gmtime t in Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (x.Unix.tm_year+1900)(x.Unix.tm_mon+1)x.Unix.tm_mday x.Unix.tm_hour x.Unix.tm_min x.Unix.tm_sec
let stamp t=let x=Unix.gmtime t in Printf.sprintf "%04d%02d%02d-%02d%02d" (x.Unix.tm_year+1900)(x.Unix.tm_mon+1)x.Unix.tm_mday x.Unix.tm_hour x.Unix.tm_sec
let render_view db candidate =
 let r=report db candidate in let manifest=get_candidate db candidate in
 let catalog=get_catalog db(text "spec_id" manifest)(text "revision" manifest) in
 let b=Buffer.create 32000 in let add=Buffer.add_string b in
 let now=member "observed" r |>to_number in
 add("# "^stamp now^" — Product, features and oracle evidence\n\n");
 add "#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda\n\n";
 add "[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Product specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1837-agentic-product-detailed-specification.md)\n\n";
 add("Generated from SQLite at **"^utc now^"**. This is a dated projection. Re-run the view command to observe later receipts or expiry.\n\n");
 add("**Product state: "^text "state" r^" · Admission: NOT_ADMITTED.** "^string_of_int(to_int(member "required_cases" r))^" required acceptance cases are counted independently of the internal oracle check.\n\n");
 add("Candidate: `"^candidate^"`. Current selected-source identity: `"^optional "source_current" r^"`. Owner: "^md(text "owner" r)^". Sa-plan reference: `"^md(text "sa_plan_ref" r)^"`.\n\n");
 add("Internal nine-boolean eligibility check: **"^text "native_eligibility" r^"**. Receipt count: "^optional "receipt_count" r^". It gives no automatic credit to the original infrastructure acceptance cases.\n\n");
 let task_ref=text "sa_plan_ref" r in
 add "## Execution and dependencies\n\n";
 (match String.split_on_char '#' task_ref with
 | [plan;task] ->
   let state=with_db ~readonly:true "var/sa-plan/uos.sqlite3" (fun sa->
    query sa "SELECT state,worker,attempt,lease_until_ns FROM sa_plan_task WHERE plan_id=? AND id=?" [s plan;s task]) in
   (match state with [[state;worker;attempt;lease]]->
     let show=function Sqlite3.Data.TEXT x->x|Sqlite3.Data.INT n->Int64.to_string n|Sqlite3.Data.NULL->"none"|_->"unknown" in
     add("Current Sa-plan task: **"^md(show state)^"**; worker "^md(show worker)^"; attempt "^md(show attempt)^"; lease UTC nanoseconds "^md(show lease)^".\n\n")
    |_->add "Sa-plan reference is unresolved; no execution authority inferred.\n\n")
 | _->add "Sa-plan reference is not a canonical plan#task locator; unresolved.\n\n");
 add "Containment is Product → Feature → Requirement → Acceptance. Every required child participates in completion. Cross-reference maps and oracle links do not add containment parents. Missing evidence remains UNRUN; stale identities, failed runs and invalid receipts withhold completion. Feature-specific planning references below are declared mappings and may be unresolved.\n\n";
 add "## Feature summary\n\n| Feature | Category | Declared map | Observed evidence | Oracle references |\n|---|---|---|---|---|\n";
 let nodes=items "nodes" r in
 let state id=match List.find_opt(fun n->text "id" n=id)nodes with None->"UNKNOWN"|Some n->text "state" n in
 List.iter(fun f->add("| "^md(text "id" f^" — "^text "name" f)^" | "^md(text "category" f)^" | "^text "status" f^" | "^state(text "id" f)^" | "^
  md(String.concat ", " (List.map to_string(items "oracle_ids" f)))^" |\n"))(items "features" catalog);
 add "\n## Detailed requirements and acceptance\n\n";
 List.iter(fun f->
  add("<details><summary>"^md(text "id" f^" — "^text "name" f)^"</summary>\n\n");
  add("Use case: "^md(text "use_case" f)^"\n\nNative implementation: "^md(text "implementation" f)^"\n\nRemaining gap: "^md(text "gap" f)^"\n\n");
  add("Declared task mapping: `"^md(optional "sa_plan_task" f)^"`. Catalog owner: "^md(text "owner" r)^".\n\n");
  List.iter(fun req->add("**"^md(text "id" req)^"** — "^md(text "shall" req)^"\n\n"))(items "requirements" f);
  add "| Acceptance | Assertion | Current state |\n|---|---|---|\n";
  List.iter(fun a->add("| "^md(text "id" a)^" | "^md(text "assertion" a)^" | "^state(text "id" a)^" |\n"))(items "acceptance" f);
  add "\nSource map (historical catalog observations):\n\n";
  List.iter(fun m->add("- `"^md(text "path" m)^"`: "^md(optional "status" m)^"; digest `"^md(optional "sha256" m)^"`.\n"))(items "mappings" f);
  add "\n</details>\n\n")(items "features" catalog);
 add "## Oracle registry\n\n| Oracle | Pin observation | Execution | Role |\n|---|---|---|---|\n";
 List.iter(fun o->add("| "^md(text "id" o)^" | "^md(text "status" o)^" | "^md(optional "execution_status" o)^" | "^md(optional "role" o)^" |\n"))(items "oracles" catalog);
 add "\nThese external oracle rows are source/reference observations, not executed parity. The internal executable comparison below pins local binaries and selected libraries; it does not establish an external source-build pin or service parity.\n\n";
 add "## Receipt history\n\n| Sequence | Case | Kind | Observed UTC | Expires UTC | Artifact version |\n|---|---|---|---|---|---|\n";
 let rows=query db "SELECT sequence,case_id,kind,observed,expires,artifact_id,artifact_revision FROM product_workflow_receipts WHERE candidate_id=? ORDER BY sequence" [s candidate] in
 let number=function Sqlite3.Data.FLOAT f->f|Sqlite3.Data.INT n->Int64.to_float n|_->fail "receipt timestamp" in
 List.iter(function [Sqlite3.Data.INT seq;case;kind;observed;expires;artifact;revision]->
  add("| "^Int64.to_string seq^" | "^md(data_text case)^" | "^md(data_text kind)^" | "^utc(number observed)^" | "^utc(number expires)^" | `"^md(data_text artifact)^"` / `"^md(data_text revision)^"` |\n")
  |_->fail "receipt history shape")rows;
 if rows=[] then add "| — | — | UNRUN | — | — | No execution receipts |\n";
 add "\n## Review findings\n\n";
 List.iter(fun f->add("- **"^md(text "id" f)^" / "^md(text "severity" f)^"** — "^md(text "title" f)^". Historical review status: "^md(optional "status" f)^".\n"))(items "findings" catalog);
 add "\n## Storage and freshness\n\nSQLite owns artifact bodies, JSON versions, hierarchy and receipts. Files are exports for review. Version conflicts and stale-writer CAS updates are rejected; history cannot be replaced through INSERT OR REPLACE. Digest checks detect changed stored bodies. WAL/FULL transactions and consistent backups reduce interrupted-write risk; the shared Unix account and storage hardware remain trust boundaries. Candidate changes require a new snapshot and fresh evidence.\n\n";
 let journal=read "docs/journal/20260907-2013-stabilization-swarm-initiation-journal.md" in
 let offset=Str.search_forward(Str.regexp_string "## Comprehensive verification checklist")journal 0 in
 add(String.sub journal offset (String.length journal-offset));
 Buffer.contents b
let save_view candidate =
 with_db ~readonly:false database(fun db->
  let body=render_view db candidate in let digest=sha body in
  let path="docs/reviews/"^stamp(Unix.gettimeofday())^"-product-cockpit-"^String.sub candidate 0 12^"-"^String.sub digest 0 12^".md" in
  let artifact=`Assoc["id",json_string("product-cockpit:"^candidate);"revision",json_string digest;
   "kind",json_string "product-cockpit-projection";"locator",json_string path;"content",json_string body;"sha256",json_string digest] in
  transaction db(fun()->authorize();store_artifact db artifact;authorize());
  require(not(Sys.file_exists path)) "projection file exists; immutable DB artifact retained";
  (match Bos.OS.File.write(Fpath.v path)body with Ok()->()|Error(`Msg e)->fail e);
  require(read path=body) "projection readback mismatch";
  print_endline path)
let ()=if not !Sys.interactive && Filename.basename Sys.argv.(0)="product_workflow_view.ml" then
 try match Array.to_list Sys.argv with [_;candidate]->save_view candidate|_->fail "usage: product_workflow_view.ml CANDIDATE"
 with e->prerr_endline("product-view: "^Printexc.to_string e);exit 1
