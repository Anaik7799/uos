#use "topfind";;
#require "yojson,cryptokit,unix,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
open Yojson.Basic.Util
let ws="/home/an/NAS-setup/uos/.uos-workspaces/ev98-wire-codec-20260909"
let own="/home/an/NAS-setup/uos/.uos-workspaces/ev98-peer-loop-20260909"
let stage="/tmp/ev107-independent-1625"
let rev="11eeca9df5c14961ed4b4b8fc990752ad7bccd46"
let evidence="725aa3d18813280554964885ddeba9820ac171a7"
let budget=Receipt_validator.make_budget ~seconds:180. ~bytes:268435456 ()
let read=Ev_campaign.read_file budget
let sha=Receipt_validator.sha
let require=Receipt_validator.require
let str k j=member k j|>to_string
let refs=ref []
let bind p b=refs:=Ev_campaign.reference p b::!refs
let ()=
 let manifest=Yojson.Basic.from_string(read(stage^"/author-manifest.json"))in
 let unique=Hashtbl.create 97 in
 List.iter(fun j->let p=str "path" j in
 if not(Hashtbl.mem unique p)then begin
 let b=Receipt_validator.candidate_bytes ws evidence p in require(sha b=str "sha256" j)"immutable archive digest";
 Hashtbl.add unique p b;bind p b end)(member "archived_bytes"manifest|>to_list);
 let campaign_entry=List.find(fun j->str "sha256" j=str "campaign_sha256" manifest)(member "archived_bytes"manifest|>to_list)in
 let campaign=Yojson.Basic.from_string(Hashtbl.find unique(str "path" campaign_entry))in
 let mismatches=ref []in
 List.iter(fun j->let p=str "path" j in let b=read(Unix.realpath p)in
 if sha b<>str "sha256" j then mismatches:=p::!mismatches;
 bind (Unix.realpath p)b)(member "bindings"campaign|>to_list);
 List.iter(fun j->let p=str "path" j in require(sha(read(Unix.realpath p))=str "sha256" j)"dependency post-observation drift")(member "dependencies_post_observation"manifest|>to_list);
 let native_receipts=ref 0 in
 List.iter(fun p->if Filename.check_suffix p ".json" && p<>"author-manifest.json" && p<>"bindings.json"then
 let b=read(stage^"/"^p)in let j=Yojson.Basic.from_string b in
 if member "schema"j=`String "uos.ev-native-invocation.v1"then begin
 require(member "exit_code"j=`Int 0 && member "failure"j=`Null)"independent native outcome";
 require(sha(str "output"j)=str "output_sha256"j)"independent output digest";
 incr native_receipts;bind(stage^"/"^p)b end)(Array.to_list(Sys.readdir stage));
 require(!native_receipts=13)"expected six builds six probes author18";
 let bindings=Yojson.Basic.from_string(read(stage^"/bindings.json"))|>to_list in
 List.iter(fun j->let p=str "path" j in if String.starts_with ~prefix:"/tmp/"p then require(sha(read p)=str "sha256"j)"independent artifact drift")bindings;
 let post_controls=List.map(fun p->let b=read p in bind p b;Ev_campaign.reference p b)["/tmp/ev107-review-preflight.json";"/tmp/ev107-review-claim.json";"/tmp/ev107-review-active.json";"/tmp/ev107_independent.ml";"/tmp/ev107_review_audit.ml"]in
 let report=`Assoc[
 "schema",`String "uos.ev107.independent-review.v1";"observed_at",`Float(Unix.gettimeofday());"source_candidate",`String rev;"author_evidence",`String evidence;
 "verdict",`String "APPROVED_BOUNDED_DIGEST_COMPARISON";"authority",`String "NONE";"ev_admission",`String "NOT_GRANTED";
 "review_plan",`String "uos/ev107-digest-review/20260909";"task",`String "REVIEW";"attempt",`Int 1;
 "independent_tests",`Assoc["author_tests_rebuilt",`Int 18;"independent_baseline_controls",`Int 14;"compiled_disagreement_mutants",`Int 4;"diagnostic_prose_variant_controls",`Int 14;"successful_native_invocations",`Int !native_receipts];
 "author_archive_unique_files_verified",`Int(Hashtbl.length unique);"author_bindings_checked",`Int(List.length(member "bindings"campaign|>to_list));
 "author_binding_current_mismatches",`List(List.map(fun p->`String p)!mismatches);
 "author_dependencies_rehashed",`Int 8;"independent_source_and_artifacts",`List bindings;"review_controls",`List post_controls;
 "findings",`List[];
 "limits",`List(List.map(fun s->`String s)[
 "Approval covers exact lowercase SHA-256 expectation and comparison of verdict kinds, rejection codes, and passing digests; Ok true can mean matching rejections.";
 "Caller scan found direct tests and driver only. No production MCP/Rete invocation, dispatch safety, SQL-injection completeness, or full EV107 runtime was established.";
 "Both implementations share digest and SQL helpers; independent known vectors support specific digest observations, not cryptographic proof.";
 "Historical bounded function name does not impose a payload-size bound; operations are linear in caller-provided payload. Largest independent fixture is one million bytes.";
 "Authored orchestration uses argv-only native OCaml/Dune/ELF executables. Dune trace inspected; transitive compiler/linker exec closure was not traced or authenticated.";
 "Campaign uses cooperative local JJ/source and mutable executable paths; tool hashing is observed evidence, not immutable tool execution or producer authentication.";
 "Eight dependency hashes are post-execution checks, not complete hermetic or shared-library release closure. Formal solver unavailable in this component scope; no admission.";
 "Reviewer fixtures run under 180-second outer and 60-second child deadlines with bounded captured output; local filesystem reads remain cooperative."
 ])]in
 let path=stage^"/20260909-1630-ev107-independent-approval.json"in Ev_campaign.write path(Yojson.Basic.pretty_to_string report);
 Ev_campaign.write(stage^"/audit-bindings.json")(Yojson.Basic.pretty_to_string(`List(List.rev !refs)));
 Printf.printf "%s SHA256 %s archives=%d mismatches=%d\n"path(sha(read path))(Hashtbl.length unique)(List.length !mismatches)
