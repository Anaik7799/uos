#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
let root="/home/an/NAS-setup/uos"
let workspace=root^"/.uos-workspaces/codex-ev-admission-20260909-0210"
let require b why=if not b then failwith why
let hash=Receipt_validator.sha
let read p=let st=Unix.lstat p in
  require(st.st_kind=Unix.S_REG && st.st_size<=4_194_304)"bounded regular evidence";
  let ch=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr ch)(fun()->
    let fd=Unix.descr_of_in_channel ch in
    require(Receipt_validator.same_stat st(Unix.fstat fd))"evidence identity";
    let s=really_input_string ch st.st_size in
    require(Receipt_validator.same_stat st(Unix.fstat fd))"evidence changed";s)
let field=Yojson.Basic.Util.member
let string n j=field n j |> Yojson.Basic.Util.to_string
let items n j=field n j |> Yojson.Basic.Util.to_list
let json p=Yojson.Basic.from_string(read p)
let artifact p=let bytes=read p in `Assoc["path",`String p;"sha256",`String(hash bytes);"bytes",`Int(String.length bytes)]
let artifacts=ref []
let retain p=artifacts:=artifact p::!artifacts
let candidate revision path=Receipt_validator.run ~seconds:5. ~limit:4_194_304
  (root^"/toolchains/nix-profile/bin/jj")
  ["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace;
   "file";"show";"-r";"commit_id(\""^revision^"\")";"-T";"\"\"";"--";"root:"^path]
let execution path=
  let j=json path in
  require(field "exit_code" j=`Int 0 && field "failure" j=`Null) ("nonpassing invocation: "^path);
  require(field "child_termination" j=`Assoc["kind",`String "EXITED";"code",`Int 0])"termination mismatch";
  require(hash(string "output" j)=string "output_sha256" j)"output digest mismatch";
  retain path;j
let prefixed prefix text=String.split_on_char '\n' text |> List.filter_map(fun l->
  if String.starts_with ~prefix l then Some(String.sub l(String.length prefix)(String.length l-String.length prefix))else None)
let passes n j=let found=prefixed "PASS " (string "output" j) in
  require(List.length found=n && List.length(List.sort_uniq String.compare found)=n)"PASS label set mismatch";found
let beam_artifacts directory=
  Sys.readdir(directory^"/compiled/ebin") |> Array.to_list |> List.sort String.compare
  |> List.iter(fun n->if Filename.check_suffix n ".beam" then retain(directory^"/compiled/ebin/"^n))
let verify_binding revision changed j=
  let path=string "staged" j and old=string "sha256" j in
  let expected=match List.find_opt(fun c->string "staged" c=path)changed with
    |None->old|Some c->require(string "baseline_sha256" c=old)"variant baseline mismatch";string "variant_sha256" c in
  require(hash(read path)=expected)("staged bytes changed: "^path);
  let source=string "source" j in
  if String.starts_with ~prefix:"candidate:" source then
    require(hash(candidate revision(String.sub source 10(String.length source-10)))=old)"immutable source mismatch"
  else if String.starts_with ~prefix:"/" source then
    require(hash(read source)=old)"dependency or probe changed"
let verify_stage revision directory changed=
  let manifest=json(directory^"/bindings.json") in
  require(string "candidate" manifest=revision)"stage candidate mismatch";
  List.iter(verify_binding revision changed)(items "sources" manifest @ items "dependencies" manifest @ items "independent_probes" manifest);
  let profile=field "private_build_profile" manifest in
  require(hash(read(string "staged" profile))=string "sha256" profile)"private compiler profile changed";
  require(List.length(items "sources" manifest)=23 && List.length(items "dependencies" manifest)=211)"transport input closure size";
  retain(directory^"/bindings.json");beam_artifacts directory
let now=Unix.gettimeofday()
let g=Unix.gmtime now
let stamp=Printf.sprintf "%04d%02d%02d-%02d%02d"(g.tm_year+1900)(g.tm_mon+1)g.tm_mday g.tm_hour g.tm_sec
let strings xs=`List(List.map(fun s->`String s)xs)
let finish directory label revision details limits=
  retain "/tmp/ev_independent_reviews_record.ml";
  let report=`Assoc[
    "schema",`String("uos.ev98-"^label^"-independent-review.v1");
    "source_candidate",`String revision;"observed_at",`Float now;
    "reviewer",`String "Codex parent, independent of component author";
    "verdict",`String("APPROVE_BOUNDED_"^String.uppercase_ascii label);
    "authority",`String "NONE";"admission",`String "NOT_GRANTED";
    "checks",details;"artifacts",`List(List.rev !artifacts);"limits",strings limits] in
  let p=directory^"/"^stamp^"-"^label^"-independent-approval.json" in
  Ev_campaign.write p(Yojson.Basic.pretty_to_string report^"\n");
  Printf.printf "%s\nsha256=%s\n"p(hash(read p))
let sync ()=
  let revision="0d9bd0a8a8ecf26014904975a5e8e9a6c97d8d8d" in
  let directory="/tmp/ev-sync-root-reorder-green-1508" in
  let bindings=json(directory^"/bindings.json") in
  require(string "candidate" bindings=revision && List.length(items "files" bindings)=174)"sync stage manifest";
  List.iter(verify_binding revision [])(items "files" bindings);
  let probe=directory^"/package/test/ev_sync_reorder_probe.gleam" in
  require(read probe=read "/tmp/ev-sync-root-reorder-red-1429/package/test/ev_sync_reorder_probe.gleam")"independent RED/GREEN probe changed";
  retain probe;retain(directory^"/bindings.json");retain "/tmp/ev_sync_reorder_stage.ml";
  List.iter retain ["/tmp/ev-sync-root-reorder-red-1429/bindings.json";"/tmp/ev-sync-root-reorder-red-1429/compile.json";
    "/tmp/ev-sync-root-reorder-red-1429/stale-ack.json";"/tmp/ev-sync-root-reorder-red-1429/stale-delta.json"];
  require(string "output" (execution(directory^"/compile.json"))="")"sync compilation warnings";
  let observed=passes 2(execution(directory^"/runtime.json")) in
  require(observed=["independent_stale_ack_after_newer_digest";"independent_stale_delta_after_newer_digest"])"independent sync cases";
  beam_artifacts directory;
  let author_path="/tmp/ev98-sync-status-frontier-candidate-20260909-1529.json" in
  let author=json author_path in
  require(string "candidate_commit" author=revision)"author sync candidate";
  let author_workspace=root^"/.uos-workspaces/ev98-health-formal-20260909/" in
  List.iter(fun j->let absolute=string "path" j in
    require(String.starts_with ~prefix:author_workspace absolute)"author source locator";
    let relative=String.sub absolute(String.length author_workspace)(String.length absolute-String.length author_workspace) in
    require(hash(candidate revision relative)=string "sha256" j)"author immutable source binding") (items "candidate_files" author);
  List.iter(fun j->let p=string "path" j in require(hash(read p)=string "sha256" j)"author receipt digest";retain p)(items "receipts_and_artifact" author);
  retain author_path;
  ignore(passes 11(execution "/tmp/ev98-sync-status-frontier-green-run-20260909-1510.json"));
  ignore(passes 72(execution "/tmp/ev98-sync-status-retained-frontier-run-20260909-1518.json"));
  finish directory "sync_status" revision
    (`Assoc["independent_unchanged_reorder_probes",strings observed;"immutable_source_files",`Int 5;
      "all_staged_bindings",`Int 174;"author_focused_invocations",`Int 11;"author_retained_invocations",`Int 72;
      "reviewed_invariants",strings["Peer observed clocks merge monotonically after queue admission.";
        "Synchronized requires equal local clock and coverage of the retained peer frontier.";
        "Local changes and incoming merges invalidate affected peer coverage.";
        "Queue refusal preserves prior state, frontier and synchronization metadata."]])
    ["Current in-memory incarnation only; registration/restart is not durable clock recovery.";
     "Clock equality assumes honest unique causal writers; it does not authenticate a producer or prove payload equality against malicious clocks.";
     "Nominal fixture endpoints are not observed deployment evidence.";
     "Two independent probes were rebuilt and executed by the reviewer. Author 11/72 results are rehashed observations, with overlapping properties.";
     "Production and composed peer/transport behavior require separate acceptance. No full EV98 admission.";
     "Direct native ERTS was used; complete descendant execution and shared-library closure were not established.";
     "A fresh active task check is required for scoped completion."]
let transport ()=
  let revision="14057e08112c1cd5d44297eac6a9c853e8287b7a" in
  let directory="/tmp/ev-transport-root-independent-1450" in
  verify_stage revision directory [];
  require(string "output" (execution(directory^"/compile.json"))="")"transport compile warnings";
  let main=execution(directory^"/runtime.json") in ignore(passes 102 main);
  require(List.length(prefixed "START " (string "output" main))=72)"retained START count";
  let live=execution(directory^"/live-corrected.json") in
  require(passes 1 live=["owned_zenoh_two_actor_roundtrip"])"live group";
  let records=String.split_on_char '\n'(string "output" live) |> List.filter_map(fun l->
    if String.starts_with ~prefix:"{" l then Some(Yojson.Basic.from_string l)else None) in
  let kind k=List.filter(fun j->string "kind" j=k)records in
  let one k=match kind k with[x]->x|_->failwith("live singleton "^k)in
  let run=string "run"(one "owned_run") in
  require(run="r1788965700482010-1")"independent broker run identity";
  let equal=one "producer_consumer_equal_bytes" in
  require(string "producer_wire" equal=string "consumer_wire" equal)"actual wire bytes mismatch";
  let stats=one "transport_stats" in
  List.iter(fun n->require(field n stats=`Int 3)"live transport count") ["a_published";"b_published";"a_applied";"b_applied"];
  List.iter(fun n->require(field n stats=`Int 0)"live transport failures") ["a_failures";"b_failures"];
  let prefix="uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/"^run^"/" in
  let expected=List.concat_map(fun route->List.map(fun n->prefix^route^"/"^string_of_int n)[1;2;3])["a/b";"b/a"] in
  let broker=kind "broker_readback" in
  require(List.sort String.compare(List.map(string "key")broker)=List.sort String.compare expected)"exact six owned broker keys";
  let broker_bindings=List.map(fun j->let key=string "key" j and body=string "body" j in
    let entry=match Yojson.Basic.from_string body with `List[x]->x|_->failwith "broker body shape" in
    require(string "key" entry=key)"broker returned wrong key";
    let wire=match field "value" entry with
      |`List[`String "uos.ev98.transport.v1";`String _;`String _;`Int _;`Int _;`String wire]->wire
      |_->failwith "broker envelope" in
    if key=prefix^"a/b/1" then require(wire=string "wire"(one "producer_wire"))"produced digest mismatch";
    if key=prefix^"a/b/3" then require(wire=string "producer_wire" equal)"broker final ACK mismatch";
    `Assoc["key",`String key;"body_sha256",`String(hash body);"wire_sha256",`String(hash wire)])broker in
  let application=one "peer_applied" in
  require(string "worker" application="worker-owned-live" && field "health" application=`Float 0.91 && string "run" application=run)"live applied value";
  let http_directory="/tmp/ev-http-independent-1442" in
  retain(http_directory^"/bindings.json");
  require(string "output"(execution(http_directory^"/compile.json"))="")"HTTP probe compile warnings";
  ignore(passes 4(execution(http_directory^"/runtime.json")));
  List.iter(fun variant->
    let d="/tmp/ev-transport-root-fault-"^variant^"-1511" in
    let change=json(d^"/fault-bindings.json") in
    require(string "source_candidate" change=revision && string "variant" change=variant)"fault variant identity";
    require(hash(candidate revision(string "mutator_source" change))=string "mutator_sha256" change)"immutable fault mutator mismatch";
    require(hash(read(d^"/mutator.ml"))=string "mutator_sha256" change)"executed fault mutator mismatch";
    verify_stage revision d(items "changes" change);retain(d^"/fault-bindings.json");retain(d^"/mutator.ml");
    require(string "output"(execution(d^"/compile.json"))="")"fault compilation warnings";
    if variant<>"cleanup" then retain(d^"/runtime.json");
    let run_path=d^(if variant="cleanup"then "/runtime.json"else "/runtime-network-permitted.json")in
    ignore(passes 1(execution run_path))) ["report";"cleanup";"receive";"quota"];
  let author_dir=root^"/.uos-workspaces/ev98-peer-loop-20260909/" in
  let author_path=author_dir^"docs/reviews/20260909-1445-transport-verification.json" in
  require(hash(read author_path)="1260c72e594cb804f3dc4766f7264cc94141b6311a28bbc2786824dc9b63421c")"author transport manifest changed";
  List.iter(fun j->let p=author_dir^string "path" j in require(hash(read p)=string "sha256" j)"author durable receipt changed";retain p)
    (items "durable_receipts"(json author_path));
  retain author_path;retain(author_dir^"docs/reviews/20260909-1450-transport-header-bound-addendum.json");
  List.iter retain["/tmp/ev_composed_peer_stage.ml";"/tmp/ev_transport_independent_fault.ml";"/tmp/ev_transport_independent_http.gleam";
    "/tmp/ev-transport-pre-release-active-1505.json";"/tmp/ev-transport-release-observation-1505.json"];
  finish directory "transport" revision
    (`Assoc["main_distinct_PASS_labels",`Int 102;"independent_http_groups",`Int 4;"synthetic_fault_groups",`Int 4;
      "actual_broker_roundtrips",`Int 1;"owned_run",`String run;"exact_broker_records",`List broker_bindings;
      "observed_application",application;"actual_wire_sha256",`String(hash(string "producer_wire" equal));
      "staged_candidate_inputs",`Int 23;"private_dependency_files",`Int 211;"actual_total_header_bound_bytes",`Int 8194])
    ["Both peer actors ran on one NAS ERTS instance. Real network broker I/O is not multihost peer execution.";
     "GET-before-PUT and readback are cooperative collision detection, not atomic CAS against another writer.";
     "VM-local registration and routing equality are not authenticated identity or cross-VM fencing.";
     "Cursors, outbox and peer clocks are in memory; no crash-durable recovery is claimed.";
     "CleanupUnconfirmed halt is synthetic fault injection. An actually unreapable OS process was not created.";
     "Watchdog registration follows child spawn; atomic immediate owner-death cleanup is not claimed.";
     "Three private listener runs were refused with sandbox EPERM; unchanged compiled artifacts passed after approved socket access. Refusals are preserved.";
     "Initial live invocation had an incorrect executable path and failed before child execution; corrected explicit native ERTS invocation is retained.";
     "The first release arrived after task lease expiry and was refused. Attempt recovery and a fresh active check are required before completion.";
     "Trusted callers must bound mailbox demand. Full descendant exec and library closure were not established.";
     "The branch still contains the old SyncStatus dependency. Its separate causal fix requires composition and regression.";
     "No production startup, complete formal transport proof, or EV admission is established."]
let ()=match Array.to_list Sys.argv with [_;"sync"]->sync()|[_;"transport"]->transport()|_->failwith "closed review mode required"
