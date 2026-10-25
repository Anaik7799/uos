#use "topfind";;
#require "unix,yojson,cryptokit,str,mtime.clock.os";;
#directory "/tmp/ev-campaign-independent-direct-review-20260909/build/default/.ev_receipts.objs/byte";;
#load "/tmp/ev-campaign-independent-direct-review-20260909/build/default/ev_receipts.cma";;
let ws="/home/an/NAS-setup/uos/.uos-workspaces/ev98-health-formal-20260909"
let rev="1e2f28d24d9f8ac11f7461a81455a8d97560f331"
let stage="/tmp/ev02-successor-independent-2036"
let read p=let c=open_in_bin p in let s=really_input_string c(in_channel_length c)in close_in c;s
let write p s=let c=open_out_gen[Open_wronly;Open_creat;Open_excl]0o600 p in output_string c s;close_out c
let sha=Receipt_validator.sha
let jj="/nix/store/vzrnnii3369cn2a2bgdlkx9gh6m297fj-jujutsu-0.44.0/bin/jj"
let records=ref[]
let candidate p=let select="commit_id(\""^rev^"\")"in let run args=let r=Ev_campaign.process ~deadline:(Receipt_validator.mono()+.6.) ~cwd:ws ~environment:(Unix.environment()) ~seconds:5. ~limit:1048576 jj(["--ignore-working-copy";"--no-pager";"--color";"never"]@args)in if not(Ev_campaign.passed r)then failwith"candidate read";r in let id=run["log";"--no-graph";"-r";select;"-T";"commit_id"]in if id.stdout<>rev then failwith"commit mismatch";let r=run["file";"show";"-r";select;"root:"^p]in records:=`Assoc["path",`String p;"sha256",`String(sha r.stdout);"bytes",`Int(String.length r.stdout);"resolved_commit",`String id.stdout;"jj",`String jj;"elapsed",`Float r.elapsed]::!records;r.stdout
let prefix p marker=let b=read(stage^"/"^p)in let n=Str.search_forward(Str.regexp_string marker)b 0 in String.sub b 0 n
let ()=
 if Sys.getcwd()<>ws then failwith"explicit author cwd";
 Unix.mkdir stage 0o700;
 List.iter(fun p->write(stage^"/"^Filename.basename p)(candidate p))["tools/ev02_governance/run_checks.ml";"tools/ev02_governance/directive_mapping_gate.ml";"tools/ev02_governance/policy_surface_gate.ml";"governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json";"governance/agents/policy/superset.toml"];
 write(stage^"/bindings.json")(Yojson.Safe.pretty_to_string(`Assoc["candidate",`String rev;"source_reads",`List(List.rev!records)]));
 let hp=prefix"run_checks.ml""let () = match Array.to_list Sys.argv"in
 write(stage^"/lifecycle_probe.ml")(hp^{|
let fixture=Sys.argv.(1)
let child=fixture^"/child.ml"
let ()=write child {child|
#load "unix.cma";;
let write p=let c=open_out_bin p in output_string c "late";close_out c
let ()=match Sys.argv.(1)with
|"normal"->print_endline "normal"
|"close"->Unix.close Unix.stdout;Unix.close Unix.stderr;Unix.sleepf 0.7
|"descendant"->(match Unix.fork()with 0->Unix.sleepf 0.65;write Sys.argv.(2)|_->Unix.sleepf 1.)
|"normal-descendant"->(match Unix.fork()with 0->Unix.sleepf 0.65;write Sys.argv.(2)|_->exit 0)
|"both"->print_string(String.make 800000 'o');flush stdout;prerr_string(String.make 800000 'e');flush stderr
|"finite-writer"->for _=1 to 100 do print_string(String.make 8192 'w');flush stdout;Unix.sleepf 0.003 done
|"exact"->print_string(String.make 1048576 'x');flush stdout
|_->exit 2
|child}
let rows=ref[]
let add name c fields=rows:=`Assoc(["case",`String name;"termination",term_json c.termination;"elapsed",`Float c.elapsed;"stdout_bytes",`Int(String.length c.stdout);"stdout_sha256",`String(sha c.stdout);"stderr_bytes",`Int(String.length c.stderr);"stderr_sha256",`String(sha c.stderr)]@fields)::!rows
let call mode args seconds=run~seconds(script_argv child(mode::args))
let fdcount()=Array.length(Sys.readdir"/proc/self/fd")
let ()=
 let before=fdcount()in
 let normal=call"normal"[]1. in add"normal"normal[];
 let eof=call"close"[]0.1 in add"early-eof"eof[];
 let marker=fixture^"/late-timeout"in let timed=call"descendant"[marker]0.1 in add"descendant-timeout"timed[];
 let marker2=fixture^"/late-normal"in let normal_d=call"normal-descendant"[marker2]1. in add"normal-direct-descendant"normal_d[];
 Unix.sleepf 0.75;
 let both=call"both"[]2. in add"aggregate-output"both[];
 let writer=call"finite-writer"[]0.1 in add"continuing-writer-deadline"writer[];
 let exact=call"exact"[]2. in add"exact-per-stream"exact[];
 let after=fdcount()in
 let policy=run~seconds:0.5(script_argv(fixture^"/policy_surface_gate.ml")["--observe";fixture^"/fifo-root"])in add"retired-policy-fifo"policy["stdout",`String policy.stdout];
 let wrong=try ignore(bind_candidate "e11692afdd54e39b5d2232389bcdc64f93ed0a61");false with Failure _->true in
 let author_summary=let c=open_in_bin"/tmp/ev02-governance-harness-2024/summary.json"in let s=really_input_string c(in_channel_length c)in close_in c;s in
 let strict_json=try ignore(Yojson.Safe.from_string author_summary);true with Yojson.Json_error _->false in
 let checks=["normal",normal.termination=Exited 0;"earlyEOF",eof.termination=Timeout && eof.elapsed<0.5;"timeout-descendant",timed.termination=Timeout && not(Sys.file_exists marker);"normal-descendant",normal_d.termination=Exited 0 && not(Sys.file_exists marker2);"fd-cleanup",before=after;"aggregate",both.termination=Output_limit;"writer-deadline",writer.termination=Timeout && writer.elapsed<0.5;"exact-bound",exact.termination=Exited 0 && String.length exact.stdout=1048576;"retired-policy",policy.termination=Exited 1 && String.contains policy.stdout 'H';"candidate-mismatch",wrong;"strict-author-summary",strict_json]in
 write(fixture^"/lifecycle-results.json")(Yojson.Safe.pretty_to_string(`Assoc["source",`String"1e2f28d24d9f8ac11f7461a81455a8d97560f331";"fd_before",`Int before;"fd_after",`Int after;"timeout_marker_present",`Bool(Sys.file_exists marker);"normal_marker_present",`Bool(Sys.file_exists marker2);"checks",`Assoc(List.map(fun(k,v)->k,`Bool v)checks);"rows",`List(List.rev!rows);"authority",`String"NONE"]));
 List.iter(fun(k,v)->Printf.printf"%s=%b\n"k v)checks
|});
 let mp=prefix"directive_mapping_gate.ml""let () =\n  match Array.to_list Sys.argv"in
 write(stage^"/mapping_probe.ml")(mp^{|
let ()=
 let root=Sys.argv.(1)in make_dir root;
 build_fixture root~all_surfaces:true~body:"# Anchor\nsynthetic only\n";
 let allids="DIR-TIME-001"::List.tl ids in
 let toml=String.concat"\n"(List.map(fun id->"[[directive]]\nid = \""^id^"\"\nstatus = \"REVOKED_SYNTHETIC\"\nformat_mandate = \"COUNTERFACTUAL\"\n")allids)in
 let sup=root^"/governance/agents/policy/superset.toml"in write sup toml;
 let m=root^"/mapping.json"in write m(mapping_text(List.map(fun id->id,"rule.md","# Anchor")allids));
 let o=observe root m in
 let expected=["status = \"REVOKED_SYNTHETIC\"";"format_mandate = \"COUNTERFACTUAL\""]in
 let exact=List.for_all(fun(_,cs)->cs=expected)o.directive_clauses in
 let obs=root^"/counterfactual-observation.json"in let fd=Unix.openfile obs[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let old=Unix.dup Unix.stdout in Unix.dup2 fd Unix.stdout;print o;flush stdout;Unix.dup2 old Unix.stdout;Unix.close old;Unix.close fd;
 write sup(toml^"\n[unrelated]\ndescription = \"UNRELATED_TABLE_ONLY\"\n");
 let scoped=observe root m in
 let last=List.assoc(List.hd(List.rev allids))scoped.directive_clauses in
 let other_table_misattributed=List.mem"description = \"UNRELATED_TABLE_ONLY\""last in
 write(root^"/mapping-results.json")(Yojson.Basic.pretty_to_string(`Assoc["counterfactual_exact",`Bool exact;"unrelated_table_misattributed",`Bool other_table_misattributed;"last_directive_clauses",`List(List.map(fun s->`String s)last);"authority",`String"NONE"]));
 Printf.printf"counterfactual_exact=%b\nunrelated_table_misattributed=%b\n"exact other_table_misattributed
|});
 Unix.mkdir(stage^"/fifo-root")0o700;
 List.iter(fun surface->Unix.mkdir(stage^"/fifo-root/"^Filename.dirname surface)0o700;Unix.mkdir(stage^"/fifo-root/"^surface)0o700;Unix.mkfifo(stage^"/fifo-root/"^surface^"/rule.md")0o600)[".agents/rules";".claude/rules";".gemini/rules";".codex/rules"];
 print_endline stage
