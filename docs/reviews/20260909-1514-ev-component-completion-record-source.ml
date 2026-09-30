#use "topfind";;
#require "unix,str,yojson,cryptokit,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
let root="/home/an/NAS-setup/uos"
let workspace=root^"/.uos-workspaces/codex-ev-admission-20260909-0210"
let revision="903a1cbc71b83a9914fc1dea36727388ae98e8e4"
let require b why=if not b then failwith why
let hash=Receipt_validator.sha
let read p=let st=Unix.lstat p in
  require(st.st_kind=Unix.S_REG && st.st_size<=4_194_304)"bounded regular artifact required";
  let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->
    require(Receipt_validator.same_stat st(Unix.fstat(Unix.descr_of_in_channel c)))"artifact identity changed";
    let bytes=really_input_string c st.st_size in
    require(Receipt_validator.same_stat st(Unix.fstat(Unix.descr_of_in_channel c)))"artifact changed";bytes)
let field=Yojson.Basic.Util.member
let string k j=field k j |> Yojson.Basic.Util.to_string
let items k j=field k j |> Yojson.Basic.Util.to_list
let json p=Yojson.Basic.from_string(read p)
let check_invocation p=let j=json p in
  require(field "exit_code" j=`Int 0 && field "failure" j=`Null) ("nonpassing invocation "^p);
  require(hash(string "output" j)=string "output_sha256" j)"invocation output changed";j
let pass_names output=String.split_on_char '\n' output |> List.filter_map(fun l->
  if String.starts_with ~prefix:"PASS " l then Some(String.sub l 5(String.length l-5))else None)
let jj args=Receipt_validator.run ~seconds:10. ~limit:4_194_304(root^"/toolchains/nix-profile/bin/jj")
  (["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace]@args)
let ()=
  require(jj["log";"-r";"commit_id(\""^revision^"\")";"--no-graph";"-T";"commit_id"]=revision)"composition candidate absent";
  require(jj["diff";"--from";"52e013cfe8c32d6c8d4353c27cfdf0a23f225124";"--to";revision;"--summary";"root:apps"]="")"Gleam source changed during evidence composition";
  require(jj["diff";"--from";"dc2beed684a2b2ae4e34f69c9fd96420e2ca0f93";"--to";revision;"--summary";"root:tools/ev_receipts"]="")"reviewed producer changed in composition"
let approved=[
  "transport-approval","/tmp/ev-transport-root-independent-1450/20260909-1522-transport-independent-approval.json","068e95c6b856f7870de0d40c11f8b87fef2d7c0fc9e6ee79c216afe1814af399";
  "sync-approval","/tmp/ev-sync-root-reorder-green-1508/20260909-1536-sync_status-independent-approval.json","287b419f76f5a1b1fbc2468d3b41b9d8acd319a5d8cbf35d1825276d7d87bc92";
  "recipe-approval","/tmp/ev-recipe-independent-20260909-1524/20260909-1528-final-approval.json","69d86f77e041c4ae311564ba80712031e11666d525136be1ef17d11e147ff7b8";
  "runner-fixture-approval","/tmp/ev-recovery-generator-independent-1535/20260909-1539-threefile-independent-approval.json","4e8d0a647de55cd1ded66e90d6cea65198d8dc1e5ae118c79246b1eb3bbf0f88";
  "test-discovery-approval","/tmp/ev-fault52-independent-discovery/20260909-1541-fivefile-independent-approval.json","d056e54e787a4cf260bc094eba7fc65f9db8a78d7ad65fe13a276533fdbf7ce1"]
let ()=List.iter(fun(_,p,h)->require(hash(read p)=h)"independent approval bytes changed")approved
let combined="/tmp/ev-transport-sync-composed-fixed-1527"
let runtime=check_invocation(combined^"/runtime.json")
let ()=let passes=pass_names(string "output" runtime)in require(List.length passes=115 && List.length(List.sort_uniq String.compare passes)=115)"combined115 label set";
  require(string "output"(check_invocation(combined^"/compile.json"))="")"private compilation warnings"
let recovery=check_invocation "/tmp/ev-recovery177-runtime-1532.json"
let enumeration=json "/tmp/ev-recovery-case-set-1522.json"
let ()=let expected=items "final_calls" enumeration |> List.map Yojson.Basic.Util.to_string in
  require(pass_names(string "output" recovery)=expected && List.length expected=177)"recovery177 ordered runtime set";
  ignore(check_invocation "/tmp/ev-recovery177-build-1530.json");
  require(field "checks_passed"(json "/tmp/ev-recovery-generator-controls-1529/verification.json")=`Int 15)"generator controls"
let live=check_invocation(combined^"/live.json")
let live_records=String.split_on_char '\n'(string "output" live) |> List.filter_map(fun l->
  if String.starts_with ~prefix:"{" l then Some(Yojson.Basic.from_string l)else None)
let one kind=match List.filter(fun j->string "kind" j=kind)live_records with[x]->x|_->failwith "live record cardinality"
let ()=
  require(string "run"(one "owned_run")="r1788967835332236-1")"composed live run identity";
  let wires=one "producer_consumer_equal_bytes" in require(string "producer_wire" wires=string "consumer_wire" wires)"composed wire mismatch";
  List.iter(fun key->require(field key(one "transport_stats")=`Int 3)"composed transport count") ["a_published";"b_published";"a_applied";"b_applied"];
  List.iter(fun key->require(field key(one "transport_stats")=`Int 0)"composed transport failure") ["a_failures";"b_failures"];
  require(List.length(List.filter(fun j->string "kind" j="broker_readback")live_records)=6)"six broker readbacks required"
let discovery=check_invocation "/tmp/ev-transport-discovery-green-1539/runtime.json"
let ()=require(pass_names(string "output" discovery)=["production_transport_test_discovery"])"normal EUnit discovery";
  require(try ignore(Str.search_forward(Str.regexp_string "Test passed.")(string "output" discovery)0);true with Not_found->false)"empty EUnit suite refused"
let now=Unix.gettimeofday()
let g=Unix.gmtime now
let stamp=Printf.sprintf "%04d%02d%02d-%02d%02d"(g.tm_year+1900)(g.tm_mon+1)g.tm_mday g.tm_hour g.tm_sec
let utc=Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"(g.tm_year+1900)(g.tm_mon+1)g.tm_mday g.tm_hour g.tm_min g.tm_sec
let copies=ref []
let copy label path=
  let bytes=read path in
  let relative="docs/reviews/"^stamp^"-ev-component-"^label^Filename.extension path in
  Ev_campaign.write(workspace^"/"^relative)bytes;
  copies:=`Assoc["path",`String relative;"original_locator",`String path;"sha256",`String(hash bytes);"bytes",`Int(String.length bytes)]::!copies
let ()=
  List.iter(fun(label,p,_)->copy label p)approved;
  List.iter(fun(label,p)->copy label p)[
    "combined-bindings",combined^"/bindings.json";"combined-additional-bindings",combined^"/composition-bindings.json";
    "combined-compile",combined^"/compile.json";"combined-runtime",combined^"/runtime.json";"combined-live",combined^"/live.json";
    "combined-ack-fixture-red","/tmp/ev-transport-sync-composed-1519/runtime.json";
    "recovery-enumeration","/tmp/ev-recovery-case-set-1522.json";
    "recovery-generator-red","/tmp/ev-recovery-generator-new-sync-red-1519.json";
    "recovery-generator-green","/tmp/ev-recovery-generator-new-sync-green-1522.json";
    "recovery-generator-controls","/tmp/ev-recovery-generator-controls-1529/verification.json";
    "recovery-build","/tmp/ev-recovery177-build-1530.json";"recovery-runtime","/tmp/ev-recovery177-runtime-1532.json";
    "recovery-dependencies","/tmp/ev-recovery177-dependencies-1530.json";
    "discovery-red-bindings","/tmp/ev-transport-discovery-red-1535/bindings.json";
    "discovery-red-compile","/tmp/ev-transport-discovery-red-1535/compile.json";
    "discovery-red-runtime","/tmp/ev-transport-discovery-red-1535/runtime.json";
    "discovery-green-bindings","/tmp/ev-transport-discovery-green-1539/bindings.json";
    "discovery-green-probe-binding","/tmp/ev-transport-discovery-green-1539/discovery-probe-binding.json";
    "discovery-green-compile","/tmp/ev-transport-discovery-green-1539/compile.json";
    "discovery-green-runtime","/tmp/ev-transport-discovery-green-1539/runtime.json";
    "http-independent-bindings","/tmp/ev-http-independent-1442/bindings.json";
    "http-independent-compile","/tmp/ev-http-independent-1442/compile.json";
    "http-independent-runtime","/tmp/ev-http-independent-1442/runtime.json";
    "task-sync-completed","/tmp/ev98-sync-status-completed-20260909-1543.json";
    "task-transport-completed","/tmp/ev-transport-component-completed.json";
    "root-composition","/tmp/ev-root-final-component-evidence-compose-1546.json";
    "root-workspace-fence","/tmp/ev-root-evidence-compose-fence-1546.json";
    "root-active","/tmp/ev-root-component-evidence-active-1547.json";
    "review-record-source","/tmp/ev_independent_reviews_record.ml";
    "composition-stager-source","/tmp/ev_transport_sync_stage.ml";
    "immutable-stager-source","/tmp/ev_composed_peer_stage.ml";
    "fault-stager-source","/tmp/ev_transport_independent_fault.ml";
    "generator-controls-source","/tmp/ev_recovery_generator_controls.ml";
    "generator-case-update-source","/tmp/ev_update_recovery_case_set.ml";
    "recovery-dependency-source","/tmp/ev_recovery_dependencies.ml";
    "http-probe-source","/tmp/ev_transport_independent_http.gleam";
    "sync-probe-source","/tmp/ev_sync_reorder_probe.gleam";
    "discovery-probe-source","/tmp/ev_transport_test_discovery.gleam";
    "discovery-stager-source","/tmp/ev_transport_discovery_stage.ml";
    "completion-record-source","/tmp/ev_completed_components_record.ml"];
  List.iter(fun variant->let d="/tmp/ev-transport-root-fault-"^variant^"-1511"in
    List.iter(fun(name,p)->copy("fault-"^variant^"-"^name)(d^"/"^p))
      (["baseline-bindings","bindings.json";"variant-bindings","fault-bindings.json";"compile","compile.json";
        "initial-runtime","runtime.json"] @ if variant="cleanup"then[]else["network-runtime","runtime-network-permitted.json"]))
    ["report";"cleanup";"receive";"quota"];
  let http_manifest=json "/tmp/ev-http-independent-1442/bindings.json" in
  require(List.length(items "files" http_manifest)=162)"HTTP closed input count";
  List.iter(fun j->require(hash(read(string "staged" j))=string "sha256" j)"HTTP staged input changed";
    let source=string "source" j in if String.starts_with ~prefix:"/" source then
      require(hash(read source)=string "sha256" j)"HTTP dependency changed") (items "files" http_manifest)
let manifest_path="docs/reviews/"^stamp^"-completed-mesh-components.json"
let manifest=`Assoc[
  "schema",`String "uos.completed-mesh-components.v1";"observed_at",`String utc;
  "composed_candidate_before_record",`String revision;"authority",`String "NONE";
  "admitted_ev_ceiling",`Int 93;"new_ev_admissions",`Int 0;
  "source_equivalence",`Assoc["apps_unchanged_from",`String "52e013cfe8c32d6c8d4353c27cfdf0a23f225124";
    "producer_unchanged_from",`String "dc2beed684a2b2ae4e34f69c9fd96420e2ca0f93";"method",`String "Exact immutable JJ diff is empty for each complete named subtree"];
  "completed_components",`List[
    `Assoc["plan",`String "uos/ev98-peer-loop/20260909";"task",`String "TRANSPORT";"attempt",`Int 2;"evidence",`String "ef1cfe3c71494d7696956abf66bdde5024d11723"];
    `Assoc["plan",`String "uos/ev98-sync-status/20260909";"task",`String "SYNC_STATUS";"attempt",`Int 2;"evidence",`String "fe3f6e4edc56edc7b31c3c909a5a4fedfdcfb68f"];
    `Assoc["plan",`String "uos/ev98-wire-codec/20260909";"task",`String "RECIPE_CODEC";"attempt",`Int 3;"evidence",`String "7a7c8ac0913f4a5b620a3c3c9dc4968f5debae92"]];
  "checks",`Assoc["composed_distinct_PASS_labels",`Int 115;"recovery_ordered_invocations",`Int 177;
    "legacy_recovery_calls_preserved",`Int 168;"new_causal_calls",`Int 9;"generator_control_groups",`Int 15;
    "normal_eunit_transport_cases",`Int 1;"normal_case_internal_groups",`Int 12;
    "private_fault_cases",`Int 4;"owned_broker_records",`Int 6;"owned_broker_run",`String "r1788967835332236-1"];
  "copies",`List(List.rev !copies);
  "limits",`List(List.map(fun s->`String s)[
    "Counts refer to distinct labels or invocations within each stated suite; properties overlap and counts are not added into EV admission credit.";
    "Two local actors used the real NAS broker. No cross-host peer execution, production supervisor cutover, or durable crash recovery is established.";
    "Frame/route identity and cooperative broker readback are not authentication or cross-VM atomic fencing.";
    "Broader formal refinement and authenticated sovereign admission remain open. Prior AGY review covers only its recorded component scope.";
    "Full package compilation succeeded with existing warnings;177 selected invocations ran. The complete global test suite was not run.";
    "Private immutable compiler profiles and existing dependency bytes are recorded; compiler caches are not imported as source and complete native/shared-library closure is unproved.";
    "HTTP total wire header bound is8194bytes. Cleanup failure halts I/O; immediate spawn-window owner-death cleanup is not proved.";
    "Old failed fixtures, sandbox EPERM, expired lease refusal and synthetic variants remain preserved; they are not passing production evidence."])]
let ()=Ev_campaign.write(workspace^"/"^manifest_path)(Yojson.Basic.pretty_to_string manifest^"\n")
let journal_path="docs/journal/"^stamp^"-completed-mesh-components.md"
let journal="# "^stamp^" Completed mesh components and integration repairs\n\nObserved UTC: **"^utc^"**. #fractal-l0 #fractal-l2 #fractal-l3 #fractal-l6 #zk-adr #zero-muda\n\n"
 ^"[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Provenance](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md). Private JJ evidence; live publication unverified.\n\n"
 ^{|## 1. Scope & Trigger

Continue all-EV verification using Gleam, OCaml or Mojo and no Bash. Close the bounded transport, causal synchronization and closed-recipe tasks, compose their evidence, and repair integration test coverage. The programme remains executing and EV94–109 remain NOT_ADMITTED.

## 2. Pre-State Assessment

The reviewed codec and peer layer lacked a network worker. Peer status could forget newer causal evidence. The recovery generator expected168 calls. Synthetic transport fault functions were named as normal EUnit tests, although their bodies required private mutated builds.

## 3. Execution Detail

The Gleam transport now performs bounded HTTP broker custody/readback and retained peer delivery. Independent checks covered framing, cancellation, delayed delivery replies, cleanup refusal, receive retries and publication quotas. Causal synchronization retains a monotone frontier for every registered peer. Root's unchanged stale-ACK and stale-Delta probes switched from failure to success. The closed OCaml recipe retains its original42 calls and adds25 codec plus9 causal cases; four designated compiled mutants fail as required. All three scoped tasks completed after independent reviews and current active observations.

Root composed the sources and ran115 distinct labels against an immutable private build. The timer fixture now checks that a stale ACK requiring recovery refuses at a full queue, while a covering ACK at the same old epoch cannot rearm a tripped heartbeat. A fresh real broker run observed six exact records, three publications and applications per actor, zero failures, and matching produced/consumed wire bytes. Both actors ran locally on NAS.

## 4. Root Cause Analysis

Successful socket publication and successful peer bookkeeping are separate transitions: retaining broker custody before a fallible report prevents cursor reuse. Causal clock equality alone forgets a previously observed remote frontier. Integration exposed a stale empty-clock ACK assumption and a fixed168-call generator. Actual EUnit discovery also selected four synthetic fault entrypoints, producing three failures; renaming those explicit entrypoints and adding a normal production test restored nonempty standard discovery. Initial evidence preparation refused relative filesets from another workspace before writing artifacts; explicitly rooted JJ filesets corrected that invocation.

## 5. Fix Taxonomy

Retained delivery state, queue-atomic causal observations, exact reviewed call-set hashing, regression-preserving fixture repair, ordinary test discovery, isolated fault entrypoints and immutable evidence composition. No runtime deployment or admission mutation occurred.

## 6. Patterns & Anti-Patterns Discovered

A final group count is not a proof of distinct properties. A normal test runner must be exercised in addition to manually selected mains. Fault-injected behavior requires explicit artifact identity. A same-length substitution or reordered test set must not silently pass a cardinality guard. A delayed approval does not extend a task lease; failed expiry transitions remain failures.

## 7. Verification Matrix

| Observation | Result | Boundary |
|---|---|---|
| Composed private build | Warning-free,115 labels passed | Peer, transport, codec, causal cases and independent probes |
| Fresh broker run | Six records; exact wire equality; zero failures | Two local actors, real NAS broker |
| Recovery runner | All177 ordered calls passed | Original168 plus9 reviewed causal calls |
| Generator controls |15 groups passed, independently repeated | Existing-path safety, links, exact membership/order and denominator refusal |
| Normal EUnit transport discovery | One production case passed | Its existing12-group main; nonempty discovery |
| Renamed fault fixtures | Four independently rebuilt cases passed | Explicit private synthetic variants |
| Closed producer recipe |76 positives, four designated mutants | Independently rebuilt OCaml producer and replayed bound ERTS artifacts |
| Full EV98 and all-EV admission | Not established | Formal refinement, multihost, production and sovereign requirements remain |

## 8. Files Modified

The composed author changes add the transport, causal peer frontier and closed recipe expansion. Root changes the recovery generator and generated main, the peer timer fixture, the ordinary transport test entrypoint and four OCaml fault staging callers. This record preserves exact approvals, invocation receipts, source/dependency bindings and executed probe/driver source. Historical and quarantined evidence remains unchanged.

## 9. Architectural Observations

Gleam owns state transitions, supervision and socket workers. OCaml owns bounded native execution and evidence processing. Native erlexec and ocamlrun avoid shell launcher wrappers. The finite health algebra proof and component reviews do not establish full distributed-system refinement. The live coordinator still requires its separate proven cutover; documentary claims do not replace observed runtime state.

## 10. Remaining Gaps

Cross-host identity and incarnation recovery, durable peer clocks/outboxes, full mesh formal refinement, production startup and actual sovereign EV admission remain open. Cooperative GET-before-PUT is not atomic CAS against external writers. Mailbox demand must be bounded by trusted callers. Newly identified digest-validation, graph-integrity and remediation-accounting defects are being handled in separate Sa-plan tasks. Other EV UI/performance fields still contain synthetic claims requiring observed producers.

## 11. Metrics Summary

Three bounded component tasks completed in this stage. Relevant suites reported115 composed labels,177 recovery invocations,15 generator control groups,76 recipe positives and four recipe mutants. These overlap and are not a combined assurance score. New EV admissions: zero. Policy ceiling:93.

## 12. STAMP & Constitutional Alignment

Exact routing/custody and causal coverage constrain unsafe provision; retry retention constrains omission; monotone freshness and current task attempts constrain wrong timing; quotas, deadlines and cleanup halt constrain excessive duration. Task completion is narrower than runtime effect authority. Component evidence and observed AGY commentary do not authenticate every producer or grant sovereign admission. Standalone JJ sibling integration remains separate from integration/main and runtime service ownership.

## 13. Conclusion

The reviewed transport, synchronization and closed-recipe components are completed and composed. The integration defects are repaired with preserved failures and independent checks. Broader EV work continues without changing the admitted ceiling or minting new EV numbers.

## Comprehensive verification checklist

<details><summary>Domain1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Synchronized active observations and host UTC retained.
- [x] CHK-02-TAIL — Full Tailnet links supplied; publication unverified.
- [x] CHK-03-FRACT — Applicable fractal layers tagged.
- [x] CHK-04-KM — Evidence and governing provenance linked.

</details>
<details><summary>Domain2 — Purity and storage</summary>

- [x] CHK-05-MUDA — New code and orchestration use Gleam/OCaml, without Bash.
- [ ] CHK-06-GRAPH — Fleet purity review remains outside this stage.
- [ ] CHK-07-DRIVE — No hardware operation or new interlock test.

</details>
<details><summary>Domain3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8 — Complete release categories remain open.
- [ ] CHK-09-MATH — Full distributed-model refinement remains open.
- [ ] CHK-10-9MOD — Whole-capability acceptance remains open.
- [x] CHK-11-REGR — Relevant runtime, failure and discovery checks executed.

</details>
<details><summary>Domain4 — Runtime and observability</summary>

- [x] CHK-12-GLEAM — Actual OTP peers and transport executed.
- [x] CHK-13-HERMES — Native OCaml evidence and recipe checks executed.
- [ ] CHK-14-ZIGVM — Kernel acceptance outside this stage.
- [ ] CHK-15-MAX — Inference acceptance remains open.
- [ ] CHK-16-OTEL — Production telemetry correlation remains open.

</details>
<details><summary>Domain5 — Governance and VCS</summary>

- [ ] CHK-17-SOV — No sovereign EV admission is claimed.
- [x] CHK-18-JJ — Private standalone JJ composition; no Git mutation.

</details>
<details><summary>Domain6 — Provenance</summary>

Source revisions, independent reviews, exact task outcomes and failures are retained. Legacy claims and synthetic variants never become positive EV admission evidence.

</details>
|}
 ^"\n[Component evidence](http://nas-1.tail55d152.ts.net:4100/files/"^manifest_path^"). UOS footer: programme executing; admission pending.\n"
let ()=Ev_campaign.write(workspace^"/"^journal_path)journal;
  print_endline(Yojson.Basic.to_string(`Assoc["journal",`String journal_path;"manifest",`String manifest_path;"copied_artifacts",`Int(List.length !copies)]))
