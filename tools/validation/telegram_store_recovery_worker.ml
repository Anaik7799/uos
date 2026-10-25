(* Unified Operational System (UOS)
 * telegram_store_recovery_worker.ml - TEST ONLY: Recovery Fault Injection Fixture
 * Spec: uos.telegram-durable-store-corrected-development-spec.v1
 * Plan: uos/telegram-runtime/20261001-1150
 *
 * TEST ONLY FIXTURE - Promoted from var/recovery-runtime/20261011-1501-store-recovery-fixtures-v3
 * NEVER used in production runtime. Used exclusively by in-tree test 31 and recovery tests.
 *)

let write_framed_response (resp_str : string) : unit =
  let len = String.length resp_str in
  let header = Bytes.create 4 in
  Bytes.set header 0 (Char.chr ((len lsr 24) land 0xff));
  Bytes.set header 1 (Char.chr ((len lsr 16) land 0xff));
  Bytes.set header 2 (Char.chr ((len lsr 8) land 0xff));
  Bytes.set header 3 (Char.chr (len land 0xff));
  output_bytes stdout header;
  output_string stdout resp_str;
  flush stdout

let write_error_and_exit (err : string) : unit =
  let err_json = Telegram_store.make_error_json err in
  write_framed_response err_json;
  exit 0

let rec really_read in_ch buf offset count =
  if count = 0 then true
  else
    let read_bytes = input in_ch buf offset count in
    if read_bytes = 0 then false
    else really_read in_ch buf (offset + read_bytes) (count - read_bytes)

let () =
  set_binary_mode_in stdin true;
  set_binary_mode_out stdout true;
  if Array.length Sys.argv <> 2 then
    write_error_and_exit "invalid_command_line_arguments"
  else
    let configured_db_path = Sys.argv.(1) in
    try
      let header_buf = Bytes.create 4 in
      if not (really_read stdin header_buf 0 4) then
        write_error_and_exit "invalid_frame"
      else
        let b0 = Char.code (Bytes.get header_buf 0) in
        let b1 = Char.code (Bytes.get header_buf 1) in
        let b2 = Char.code (Bytes.get header_buf 2) in
        let b3 = Char.code (Bytes.get header_buf 3) in
        let frame_len = (b0 lsl 24) lor (b1 lsl 16) lor (b2 lsl 8) lor b3 in
        if frame_len < 0 || frame_len > Telegram_store.max_request_json_bytes then
          write_error_and_exit "oversized_frame"
        else
          let payload_buf = Bytes.create frame_len in
          if not (really_read stdin payload_buf 0 frame_len) then
            write_error_and_exit "truncated_frame"
          else
            (* Check for trailing bytes after frame (probes for EOF) *)
            let trailing_buf = Bytes.create 1 in
            let trailing_bytes = input stdin trailing_buf 0 1 in
            if trailing_bytes > 0 then
              write_error_and_exit "trailing_bytes_after_frame"
            else
              let req_str = Bytes.to_string payload_buf in
              let op =
                try
                  let j = Yojson.Safe.from_string req_str in
                  if Yojson.Safe.Util.(j |> member "command" |> to_string) = "apply" then
                    Yojson.Safe.Util.(j |> member "operation_id" |> to_string)
                  else ""
                with _ -> ""
              in
              let marker tag =
                let c = open_out (configured_db_path ^ ".barrier") in
                Printf.fprintf c "%d %s\n" (Unix.getpid ()) tag;
                close_out c
              in
              Telegram_store.test_stage_hook := (fun stage ->
                match op, stage with
                | "fault-pre", Telegram_store.Apply_pre_commit ->
                    marker "pre";
                    Unix.sleepf 10.
                | "fault-post", Telegram_store.Apply_post_commit_pre_reply ->
                    marker "post";
                    Unix.sleepf 10.
                | _ -> ());
              if op = "fault-native-uncertain" then
                Telegram_store.test_hook_fail_apply_after_commit := true;
              let normal_resp =
                Telegram_store.run_command_json ~configured_db_path req_str
              in
              let resp_str =
                if op = "fault-domain" then begin
                  marker "domain";
                  "{}"
                end else if op = "fault-unknown-field" then begin
                  match Yojson.Safe.from_string normal_resp with
                  | `Assoc xs ->
                      Yojson.Safe.to_string (`Assoc (("unexpected", `Bool true) :: xs))
                  | _ -> normal_resp
                end else if op = "fault-receipt-field" then begin
                  match Yojson.Safe.from_string normal_resp with
                  | `Assoc xs ->
                      let altered =
                        List.map
                          (fun (k, v) ->
                            if k = "receipt" then
                              match v with
                              | `Assoc rs ->
                                  ( k,
                                    `Assoc
                                      (List.map
                                         (fun (rk, rv) ->
                                           if rk = "operation_id" then
                                             (rk, `String "different-op")
                                           else (rk, rv))
                                         rs) )
                              | _ -> (k, v)
                            else (k, v))
                          xs
                      in
                      Yojson.Safe.to_string (`Assoc altered)
                  | _ -> normal_resp
                end else normal_resp
              in
              if String.length resp_str > Telegram_store.max_response_json_bytes then
                write_error_and_exit "oversized_frame"
              else begin
                write_framed_response resp_str;
                exit 0
              end
    with _ ->
      write_error_and_exit "sqlite_error"
