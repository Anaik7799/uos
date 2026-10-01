(* Unified Operational System (UOS)
 * telegram_store_main.ml - Framing CLI entrypoint
 * Spec: uos.telegram-durable-store-corrected-development-spec.v1
 * Plan: uos/telegram-runtime/20261001-1150
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
          (* Check for trailing bytes after frame *)
          let trailing_buf = Bytes.create 1 in
          let trailing_bytes = input stdin trailing_buf 0 1 in
          if trailing_bytes > 0 then
            write_error_and_exit "trailing_bytes_after_frame"
          else
            let req_str = Bytes.to_string payload_buf in
            let resp_str = Telegram_store.run_command_json req_str in
            if String.length resp_str > Telegram_store.max_response_json_bytes then
              write_error_and_exit "oversized_frame"
            else
              write_framed_response resp_str
  with _ ->
    write_error_and_exit "sqlite_error"
