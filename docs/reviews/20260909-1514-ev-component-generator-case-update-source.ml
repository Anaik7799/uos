#use "topfind";;
#require "unix,str,yojson,cryptokit";;
let workspace="/home/an/NAS-setup/uos/.uos-workspaces/codex-ev-admission-20260909-0210"
let require b why=if not b then failwith why
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->
  let n=in_channel_length c in require(n<=1_048_576)"bounded source";really_input_string c n)
let hash s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let write_new p b=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c b;flush c;Unix.fsync fd)
let matches expression bytes=
  let re=Str.regexp expression in
  let rec loop at acc=try ignore(Str.search_forward re bytes at);let value=Str.matched_group 1 bytes and next=Str.match_end()in loop next(value::acc)with Not_found->List.rev acc in loop 0 []
let replace_once bytes source replacement=
  let re=Str.regexp_string source in
  let at=try Str.search_forward re bytes 0 with Not_found->failwith "replacement anchor missing" in
  let next=at+String.length source in
  require((try ignore(Str.search_forward re bytes next);false with Not_found->true))"replacement anchor not unique";
  String.sub bytes 0 at ^ replacement ^ String.sub bytes next(String.length bytes-next)
let path=workspace^"/tools/generate_ev_recovery_runner.ml"
let original=read path
let old_runner=read(workspace^"/apps/cepaf_gleam/test/ev_recovery_runner.gleam")
let legacy=matches "^  \\([a-z_0-9]+_test\\.[a-z_0-9]+_test\\)()" old_runner
let modules=matches "\"\\([a-z_0-9]+_test\\)\"" original
let bindings=ref []
let calls=List.concat_map(fun m->let p="apps/cepaf_gleam/test/"^m^".gleam"in let bytes=read(workspace^"/"^p)in
  bindings:=`Assoc["path",`String p;"sha256",`String(hash bytes)]::!bindings;
  matches "^pub fn \\([a-z][a-z_0-9]*_test\\)()" bytes |> List.map(fun f->m^"."^f))modules
let additions=List.filter(fun c->not(List.mem c legacy))calls
let expected_new=List.map(fun f->"delta_mesh_engine_test."^f)[
  "digest_only_exchange_does_not_claim_remote_state_test";
  "local_mutation_invalidates_prior_peer_coverage_test";
  "stale_ack_cannot_restore_peer_coverage_after_local_change_test";
  "stale_ack_cannot_erase_a_newer_peer_frontier_test";
  "stale_delta_cannot_erase_a_newer_peer_frontier_test";
  "remote_ahead_ack_requests_the_missing_delta_test";
  "full_two_way_exchange_converges_only_after_remote_delta_test";
  "incoming_merge_invalidates_other_peer_coverage_test";
  "stale_ack_recovery_refuses_when_outbound_queue_is_full_test"]
let ()=require(List.length modules=16 && List.length legacy=168 && List.length calls=177)"reviewed denominators";
  require(List.length(List.sort_uniq String.compare calls)=177)"duplicate reviewed call";
  require(List.filter(fun c->List.mem c legacy)calls=legacy)"legacy 168 sequence changed";
  require(additions=expected_new)"unexpected synchronization additions"
let call_hash=hash(String.concat "\n" calls ^ "\n")
let replacement=Printf.sprintf {|let reviewed_call_count = 177
let reviewed_calls_sha256 = "%s"
let call_set_sha256 calls =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) (String.concat "\n" calls ^ "\n")
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let () = if List.length calls <> reviewed_call_count
    || call_set_sha256 calls <> reviewed_calls_sha256 then
  failwith (Printf.sprintf
    "Expected the exact %%d reviewed calls (%%s), found %%d calls (%%s)"
    reviewed_call_count reviewed_calls_sha256 (List.length calls) (call_set_sha256 calls))|} call_hash
let revised=original
  |> fun s->replace_once s "#require \"bos,str,unix\";;" "#require \"bos,str,unix,cryptokit\";;"
  |> fun s->replace_once s "let () = if List.length calls <> 168 then\n  failwith (Printf.sprintf \"Expected 168 reviewed tests, found %d\" (List.length calls))" replacement
  |> fun s->replace_once s "168 component checks passed; EV admission NOT_GRANTED" "177 component invocations passed; EV admission NOT_GRANTED"
let ()=
  let record=`Assoc["scope",`String "Extend exact recovery enumeration with reviewed causal synchronization cases";
    "authority",`String "NONE";"source_before_generator_change",`String "49897c6570c72f40dc697ee29b244e0173ed77ad";
    "old_generator_sha256",`String(hash original);"new_generator_sha256",`String(hash revised);
    "legacy_runner_sha256",`String(hash old_runner);"legacy_calls",`List(List.map(fun s->`String s)legacy);
    "added_calls",`List(List.map(fun s->`String s)additions);"final_calls",`List(List.map(fun s->`String s)calls);
    "final_call_set_sha256",`String call_hash;"source_bindings",`List(List.rev !bindings)]in
  write_new "/tmp/ev-recovery-case-set-1522.json"(Yojson.Basic.pretty_to_string record^"\n");
  write_new "/tmp/ev-recovery-generator-before-1522.ml" original;
  let temp,c=Filename.open_temp_file ~temp_dir:(Filename.dirname path)".recovery-generator-"".ml"in
  Fun.protect ~finally:(fun()->close_out_noerr c;if Sys.file_exists temp then Unix.unlink temp)(fun()->
    output_string c revised;flush c;Unix.fsync(Unix.descr_of_out_channel c);close_out c;
    require(read path=original)"generator changed concurrently";Unix.rename temp path);
  Printf.printf "Preserved all168 in order; added9 reviewed synchronization cases. Exact177-call SHA256=%s\n"call_hash
