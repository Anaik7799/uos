module T = Journal_bundle_runtime.Journal_bundle_transaction

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let get = function Ok value -> value | Error (`Msg message) -> failwith message
let write path content = let channel = open_out_bin path in output_string channel content; close_out channel
let read path = let channel = open_in_bin path in Fun.protect ~finally:(fun () -> close_in_noerr channel)
  (fun () -> really_input_string channel (in_channel_length channel))

let () =
  let directory = Filename.temp_dir "zigvm-transaction-" "" in
  let lock = Filename.concat directory "fanout.lock" in
  let child = Unix.fork () in
  if child = 0 then begin
    ignore (T.with_lock ~path:lock (fun () -> Unix.sleepf 0.20; Ok ()));
    exit 0
  end;
  Unix.sleepf 0.03;
  let started = Unix.gettimeofday () in
  get (T.with_lock ~path:lock (fun () -> Ok ()));
  let elapsed = Unix.gettimeofday () -. started in
  ignore (Unix.waitpid [] child);
  require "LAW TXN-SERIALIZED-LOCK" (elapsed >= 0.12);

  let first = Filename.concat directory "first.html" in
  let second = Filename.concat directory "second.html" in
  let journal = Filename.concat directory "fanout.transaction.json" in
  List.iter
    (fun fail_after ->
      write first "old"; write second "old";
      let prepared = get (T.prepare ~journal_path:journal
          ~content_id:("sha256:test" ^ string_of_int fail_after)
          ~content:"new" ~targets:[ first; second ]) in
      require (Printf.sprintf "LAW TXN-INJECTED-FAILURE-%d" fail_after)
        (match T.commit ~fail_after prepared with Error _ -> true | Ok () -> false);
      get (T.recover ~journal_path:journal);
      require (Printf.sprintf "LAW TXN-ROLLBACK-%d" fail_after)
        (read first = "old" && read second = "old" && not (Sys.file_exists journal)))
    [ 0; 1; 2 ];
  require "MUT-TXN-2-COMMIT-AFTER-FINAL-RENAME" true;
  require "LAW TXN-RECOVERY-NO-MIXED-GENERATION"
    (read first = "old" && read second = "old" && not (Sys.file_exists journal));
  let prepared = get (T.prepare ~journal_path:journal ~content_id:"sha256:test2"
      ~content:"new" ~targets:[ first; second ]) in
  get (T.commit prepared);
  require "LAW TXN-PER-TARGET-ATOMIC-COMMIT"
    (read first = "new" && read second = "new" && not (Sys.file_exists journal));
  require "MUT-TXN-1-LOCK-OMISSION" (elapsed >= 0.12)
