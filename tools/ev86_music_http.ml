#use "topfind";;
#require "unix,yojson,cryptokit,str,mtime.clock.os";;

let require c s = if not c then failwith s
let write p b = let c = open_out_bin p in Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c b)
let sha b = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) b |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let monotonic_now () = Mtime_clock.now () |> Mtime.to_uint64_ns |> Int64.to_float |> fun ns -> ns /. 1_000_000_000.

type drain_state = {
  mutable total_read : int;
  mutable total_written : int;
  mutable truncated : bool;
  mutable log_closed : bool;
  mutable drain_error : string option;
}

let make_drain_state () = {
  total_read = 0;
  total_written = 0;
  truncated = false;
  log_closed = false;
  drain_error = None;
}

let max_log_quota = 1_048_576
let log_tmp = Bytes.create 65536

let rec write_all fd bytes off len =
  if len > 0 then (
    let n = Unix.write fd bytes off len in
    if n <= 0 then failwith "write returned 0"
    else write_all fd bytes (off + n) (len - n)
  )

let drain_step ?(max_chunks = 16) ~state ~log_r ~log_fd () =
  if not state.log_closed && state.drain_error = None then (
    let chunks_read = ref 0 in
    let rec loop () =
      if !chunks_read < max_chunks then (
        let n =
          try Unix.read log_r log_tmp 0 65536
          with
          | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> -1
          | Unix.Unix_error (e, _, _) ->
              state.drain_error <- Some ("read error: " ^ Unix.error_message e);
              -2
        in
        if n = 0 then (
          state.log_closed <- true
        ) else if n > 0 then (
          incr chunks_read;
          state.total_read <- state.total_read + n;
          let to_write =
            if state.total_written + n <= max_log_quota then n
            else (
              state.truncated <- true;
              max 0 (max_log_quota - state.total_written)
            )
          in
          if to_write > 0 then (
            try
              write_all log_fd log_tmp 0 to_write;
              state.total_written <- state.total_written + to_write
            with Unix.Unix_error _ | Failure _ ->
              state.drain_error <- Some "write error to http-server.log"
          );
          loop ()
        )
      )
    in
    loop ()
  )

let finish_drain ~deadline ~state ~log_r ~log_fd () =
  while not state.log_closed && monotonic_now () < deadline && state.drain_error = None do
    let remaining = max 0.01 (deadline -. monotonic_now ()) in
    let r, _, _ = Unix.select [log_r] [] [] (min remaining 0.05) in
    if r <> [] then drain_step ~max_chunks:16 ~state ~log_r ~log_fd ()
  done;
  (try Unix.close log_r with _ -> ());
  (try Unix.close log_fd with _ -> ());
  if state.drain_error <> None then
    failwith ("server log drain error: " ^ Option.get state.drain_error);
  if not state.log_closed then
    failwith "server log drain timed out before observing EOF"

let connect_with_drain ~until ~port ~state ~log_r ~log_fd =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.set_close_on_exec fd;
  Unix.set_nonblock fd;
  try
    Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
    fd
  with
  | Unix.Unix_error ((Unix.EINPROGRESS | Unix.EWOULDBLOCK), _, _) ->
      let rec wait_connect () =
        let now = monotonic_now () in
        if now >= until then (
          Unix.close fd;
          failwith "HTTP connect deadline"
        );
        let remaining = until -. now in
        let readers = if not state.log_closed then [log_r] else [] in
        let r_fds, ready_w, _ = Unix.select readers [fd] [] (min remaining 0.05) in
        if List.mem log_r r_fds then drain_step ~max_chunks:16 ~state ~log_r ~log_fd ();
        if ready_w <> [] then (
          match Unix.getsockopt_error fd with
          | None -> fd
          | Some err -> Unix.close fd; raise (Unix.Unix_error (err, "connect", ""))
        ) else wait_connect ()
      in
      wait_connect ()
  | e -> Unix.close fd; raise e

let run_selftest () =
  Printf.printf "=== ev86_music_http selftest ===\n";

  (* Falsifier 1: continuous log writer must not trap drain_step forever *)
  let (r1, w1) = Unix.pipe ~cloexec:true () in
  Unix.set_nonblock r1;
  let pid1 = Unix.fork () in
  if pid1 = 0 then (
    Unix.close r1;
    let chunk = Bytes.make 4096 'A' in
    let rec write_loop () =
      let _ = try Unix.write w1 chunk 0 4096 with _ -> -1 in
      write_loop ()
    in
    write_loop ()
  ) else (
    Unix.close w1;
    let st1 = make_drain_state () in
    let null_fd1 = Unix.openfile "/dev/null" [Unix.O_WRONLY; Unix.O_CLOEXEC] 0 in
    let _ = Unix.select [r1] [] [] 0.5 in
    let t0 = monotonic_now () in
    drain_step ~max_chunks:8 ~state:st1 ~log_r:r1 ~log_fd:null_fd1 ();
    let elapsed = monotonic_now () -. t0 in
    Unix.close null_fd1;
    (try Unix.kill pid1 Sys.sigkill with _ -> ());
    ignore (Unix.waitpid [] pid1);
    Unix.close r1;
    assert (st1.total_read > 0);
    assert (st1.total_read <= 8 * 65536);
    assert (elapsed < 0.5);
    Printf.printf "PASS: continuous log writer bounded per step (elapsed %.4fs, read %d bytes)\n"
      elapsed st1.total_read
  );

  (* Falsifier 2: finish_drain must refuse non-EOF incomplete drain *)
  let (r2, w2) = Unix.pipe ~cloexec:true () in
  Unix.set_nonblock r2;
  let st2 = make_drain_state () in
  let null_fd2 = Unix.openfile "/dev/null" [Unix.O_WRONLY; Unix.O_CLOEXEC] 0 in
  let eof_refused =
    try
      finish_drain ~deadline:(monotonic_now () +. 0.05) ~state:st2 ~log_r:r2 ~log_fd:null_fd2 ();
      false
    with Failure msg when (try ignore (Str.search_forward (Str.regexp_string "EOF") msg 0); true with Not_found -> false) -> true
  in
  Unix.close w2;
  (try Unix.close null_fd2 with _ -> ());
  assert eof_refused;
  Printf.printf "PASS: finish_drain refuses incomplete non-EOF drain\n";

  (* Falsifier 3: log-only select wakeup during connect must not cause early timeout *)
  let srv = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.set_close_on_exec srv;
  Unix.bind srv (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen srv 1;
  let test_port = match Unix.getsockname srv with Unix.ADDR_INET (_, p) -> p | _ -> assert false in
  let (log_r3, log_w3) = Unix.pipe ~cloexec:true () in
  Unix.set_nonblock log_r3;
  let _ = Unix.write_substring log_w3 "server booting log line\n" 0 24 in
  let st3 = make_drain_state () in
  let null_fd3 = Unix.openfile "/dev/null" [Unix.O_WRONLY; Unix.O_CLOEXEC] 0 in
  let until3 = monotonic_now () +. 1.0 in
  let client_fd =
    connect_with_drain ~until:until3 ~port:test_port ~state:st3 ~log_r:log_r3 ~log_fd:null_fd3
  in
  Unix.close client_fd;
  Unix.close srv;
  Unix.close log_w3;
  Unix.close log_r3;
  Unix.close null_fd3;
  assert (st3.total_read >= 24);
  Printf.printf "PASS: connect handles log-only select wakeup without aborting\n";

  Printf.printf "ALL ev86_music_http selftests passed\n";
  exit 0

let () =
  if Array.length Sys.argv >= 2 && Sys.argv.(1) = "--selftest" then
    run_selftest ()

let () =
  if Array.length Sys.argv <> 3 then (
    Printf.eprintf "Usage: %s <stage-dir> <content-dir> | --selftest\n" Sys.argv.(0);
    exit 1
  )

let stage = Sys.argv.(1) and content = Sys.argv.(2)
let () = require (String.starts_with ~prefix:"/tmp/" stage && String.starts_with ~prefix:"/tmp/" content) "private paths required"

let listen = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0
let () = Unix.bind listen (Unix.ADDR_INET (Unix.inet_addr_loopback, 0))
let port = match Unix.getsockname listen with Unix.ADDR_INET (_, p) -> p | _ -> assert false
let () = Unix.close listen

let resolve_elf () =
  let candidates = [
    Filename.concat (Sys.getcwd ()) "toolchains/nix-profile/bin/erl";
    "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl";
  ] in
  let erl_path =
    match List.find_opt Sys.file_exists candidates with
    | Some p -> p
    | None -> failwith "erl toolchain not found"
  in
  let real_erl = try Unix.realpath erl_path with _ -> erl_path in
  let dir = Filename.dirname (Filename.dirname real_erl) in
  let rec find_erts items =
    match items with
    | [] -> failwith "erts directory not found in erl toolchain"
    | item :: rest ->
      if String.starts_with ~prefix:"erts-" item then
        let bindir = Filename.concat (Filename.concat dir item) "bin" in
        let candidate = Filename.concat bindir "erlexec" in
        if Sys.file_exists candidate then (candidate, dir, bindir) else find_erts rest
      else find_erts rest
  in
  find_erts (Array.to_list (Sys.readdir dir))

let (elf, erl_rootdir, erl_bindir) = resolve_elf ()
let libs =
  Sys.readdir (stage ^ "/full-lib")
  |> Array.to_list
  |> List.sort String.compare
  |> List.map (fun n -> stage ^ "/full-lib/" ^ n ^ "/ebin")
  |> List.filter Sys.file_exists

let argv =
  Array.of_list ([elf; "-noshell"; "-noinput"; "-pa"] @ libs @ [
    stage ^ "/full-compiled/ebin"; "-s"; "music_http_probe"; "main"; "-s"; "init"; "stop";
  ])

let run = Filename.temp_dir "ev86-http-observation-" ""
let log_path = run ^ "/http-server.log"
let log_fd = Unix.openfile log_path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o600
let (log_r, log_w) = Unix.pipe ~cloexec:true ()
let () = Unix.set_nonblock log_r

let drain_st = make_drain_state ()
let drain_step_live () = drain_step ~max_chunks:16 ~state:drain_st ~log_r ~log_fd ()

let pid = Unix.fork ()
let public_base = "http://nas-1.tail55d152.ts.net:" ^ string_of_int port
let () =
  if pid = 0 then (
    try
      ignore (Unix.setsid ());
      Unix.chdir stage;
      Unix.dup2 log_w Unix.stdout;
      Unix.dup2 log_w Unix.stderr;
      Unix.close log_w;
      Unix.close log_r;
      Unix.close log_fd;
      Unix.execve elf argv (Array.append (Unix.environment ()) [|
        "ROOTDIR=" ^ erl_rootdir;
        "BINDIR=" ^ erl_bindir;
        "EMU=beam";
        "PROGNAME=erl";
        "UOS_MUSIC_ROOT=" ^ content;
        "UOS_MUSIC_TEST_PORT=" ^ string_of_int port;
        "UOS_MUSIC_PUBLIC_BASE=" ^ public_base;
      |])
    with _ -> Unix._exit 127
  ) else (
    Unix.close log_w
  )

let connect until = connect_with_drain ~until ~port ~state:drain_st ~log_r ~log_fd

let rec wait until =
  drain_step_live ();
  try
    let fd = connect until in Unix.close fd
  with Unix.Unix_error (Unix.ECONNREFUSED, _, _) ->
    require (monotonic_now () < until) "HTTP startup deadline";
    ignore (Unix.select [] [] [] 0.05);
    wait until

let request ~name method_ path =
  let until = monotonic_now () +. 5. in
  let b = Buffer.create 4096 in
  let tmp = Bytes.create 65536 in
  let failed = ref false in
  let record_failure ?(truncated = false) exn_str =
    if not !failed then (
      failed := true;
      let raw_prefix = Buffer.contents b in
      let prefix_path = run ^ "/failed-" ^ name ^ ".response" in
      write prefix_path raw_prefix;
      let err_meta = `Assoc [
        "case", `String name;
        "method", `String method_;
        "path", `String path;
        "error", `String exn_str;
        "prefix_path", `String prefix_path;
        "prefix_bytes", `Int (String.length raw_prefix);
        "prefix_sha256", `String (sha raw_prefix);
        "truncated", `Bool truncated;
      ] in
      write (run ^ "/failed-" ^ name ^ ".json") (Yojson.Safe.pretty_to_string err_meta)
    )
  in
  try
    let fd =
      try connect until
      with exn ->
        record_failure (Printf.sprintf "connect failed: %s" (Printexc.to_string exn));
        raise exn
    in
    Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      let text =
        method_ ^ " " ^ path ^ " HTTP/1.1\r\nHost: nas-1.tail55d152.ts.net:" ^
        string_of_int port ^ "\r\nConnection: close\r\n\r\n"
      in
      let rec send i =
        if i < String.length text then (
          let remaining = max 0. (until -. monotonic_now ()) in
          if remaining <= 0. then (
            record_failure "HTTP send deadline";
            failwith "HTTP send deadline"
          );
          let readers = if not drain_st.log_closed then [log_r] else [] in
          let r_fds, ready_w, _ = Unix.select readers [fd] [] (min remaining 0.05) in
          if List.mem log_r r_fds then drain_step_live ();
          if ready_w <> [] then (
            let n =
              try Unix.write_substring fd text i (String.length text - i)
              with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> 0
                 | exn ->
                     record_failure ("send error: " ^ Printexc.to_string exn);
                     raise exn
            in
            if n = 0 && monotonic_now () >= until then (
              record_failure "HTTP write closed or timed out";
              failwith "HTTP write closed"
            );
            send (i + n)
          ) else send i
        )
      in
      send 0;
      let check_complete () =
        let bytes = Buffer.contents b in
        match Str.search_forward (Str.regexp_string "\r\n\r\n") bytes 0 with
        | at ->
            let headers = String.sub bytes 0 at |> String.split_on_char '\n' in
            if method_ = "HEAD" then true
            else (
              match List.find_opt (fun l -> String.starts_with ~prefix:"content-length:" (String.lowercase_ascii l)) headers with
              | None -> false
              | Some line ->
                  let len_str = String.trim (String.sub line 15 (String.length line - 15)) in
                  (match int_of_string_opt len_str with
                   | Some length when length >= 0 ->
                       Buffer.length b >= at + 4 + length
                   | _ ->
                       record_failure ("malformed Content-Length: " ^ len_str);
                       failwith ("malformed Content-Length: " ^ len_str))
            )
        | exception Not_found -> false
      in
      let rec recv () =
        drain_step_live ();
        if not (check_complete ()) then (
          let now = monotonic_now () in
          if now >= until then (
            record_failure "HTTP receive deadline";
            failwith "HTTP receive deadline"
          );
          let remaining = until -. now in
          let readers = [fd] @ (if not drain_st.log_closed then [log_r] else []) in
          let ready, _, _ = Unix.select readers [] [] (min remaining 0.05) in
          if List.mem log_r ready then drain_step_live ();
          if List.mem fd ready then (
            let n =
              try Unix.read fd tmp 0 65536
              with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> -1
                 | exn ->
                     record_failure ("HTTP read error: " ^ Printexc.to_string exn);
                     raise exn
            in
            if n = 0 then (
              if not (check_complete ()) then (
                record_failure "premature EOF before response complete";
                failwith "premature EOF"
              )
            ) else if n > 0 then (
              if Buffer.length b + n > 16_777_216 then (
                record_failure ~truncated:true "HTTP output bound (16MB)";
                failwith "HTTP output bound"
              );
              Buffer.add_subbytes b tmp 0 n;
              recv ()
            ) else recv ()
          ) else recv ()
        )
      in
      recv ();
      Buffer.contents b
    )
  with exn ->
    record_failure (Printexc.to_string exn);
    raise exn

let check_response name method_ path expected mime raw =
  write (run ^ "/http-" ^ name ^ ".response") raw;
  let i = Str.search_forward (Str.regexp_string "\r\n\r\n") raw 0 in
  let head = String.sub raw 0 i and body = String.sub raw (i + 4) (String.length raw - i - 4) in
  let lines = String.split_on_char '\n' head |> List.map String.trim in
  let status = Scanf.sscanf (List.hd lines) "HTTP/1.1 %d" (fun x -> x) in
  require (status = expected) (name ^ " status");
  let header k =
    let prefix = String.lowercase_ascii k ^ ":" in
    List.find_map (fun l ->
      let low = String.lowercase_ascii l in
      if String.starts_with ~prefix low then
        Some (String.trim (String.sub l (String.length prefix) (String.length l - String.length prefix)))
      else None
    ) lines
  in
  Option.iter (fun m -> require (header "content-type" = Some m) (name ^ " MIME")) mime;
  let length =
    match header "content-length" with
    | None -> None
    | Some s ->
        match int_of_string_opt s with
        | Some n -> Some n
        | None -> failwith (name ^ " malformed Content-Length header")
  in
  if method_ <> "HEAD" then require (length = Some (String.length body)) (name ^ " length");
  if name = "player" || name = "studio" then (
    require (try ignore (Str.search_forward (Str.regexp_string "<audio controls") body 0); true with Not_found -> false) "audio missing";
    require (not (try ignore (Str.search_forward (Str.regexp_string "<script") body 0); true with Not_found -> false)) "script active";
    require (try ignore (Str.search_forward (Str.regexp_string ("src='" ^ public_base ^ "/media/music/")) body 0); true with Not_found -> false) "configured full same-origin media URL missing";
  );
  if method_ = "HEAD" then require (body = "") "HEAD returned body";
  if name = "mp3" then require (sha body = "d5e2e97ae5787b60bc0ec8adf3dbde0e2a08484d4e81a203130ef41da4f32d9a") "MP3 exact source bytes";
  if name = "wav" then require (sha body = "b281fc8bd0b681603de1c15a37e1d1b3fe863181214119b2f8d8238b5baa1ef6") "WAV exact source bytes";
  `Assoc [
    "case", `String name;
    "method", `String method_;
    "path", `String path;
    "status", `Int status;
    "content_type", (match header "content-type" with Some s -> `String s | None -> `Null);
    "body_bytes", `Int (String.length body);
    "body_sha256", `String (sha body);
    "raw_sha256", `String (sha raw);
  ]

let check name method_ path expected mime =
  let raw = request ~name method_ path in
  try check_response name method_ path expected mime raw
  with exn ->
    let err_meta = `Assoc [
      "case", `String name;
      "method", `String method_;
      "path", `String path;
      "error", `String (Printexc.to_string exn);
      "response_path", `String (run ^ "/http-" ^ name ^ ".response");
      "response_bytes", `Int (String.length raw);
      "response_sha256", `String (sha raw);
    ] in
    write (run ^ "/failed-" ^ name ^ ".json") (Yojson.Safe.pretty_to_string err_meta);
    raise exn

let stop_process_group pid =
  let child_reaped = ref false in
  let reap_nonblocking () =
    if not !child_reaped then
      match Unix.waitpid [Unix.WNOHANG] pid with
      | p, _ when p = pid -> child_reaped := true; true
      | _ -> false
    else true
  in
  let group_alive () =
    try Unix.kill (-pid) 0; true
    with Unix.Unix_error (Unix.ESRCH, _, _) -> false
       | Unix.Unix_error _ -> false
  in
  let rec bounded_wait until_deadline =
    drain_step_live ();
    if reap_nonblocking () && not (group_alive ()) then ()
    else if monotonic_now () >= until_deadline then ()
    else (
      ignore (Unix.select [] [] [] 0.02);
      bounded_wait until_deadline
    )
  in
  (try Unix.kill (-pid) Sys.sigterm with _ -> ());
  bounded_wait (monotonic_now () +. 0.5);
  if not !child_reaped || group_alive () then (
    (try Unix.kill (-pid) Sys.sigkill with _ -> ());
    bounded_wait (monotonic_now () +. 0.5)
  );
  if not !child_reaped then
    failwith (Printf.sprintf "unreaped child process %d survived SIGKILL" pid);
  if group_alive () then
    failwith (Printf.sprintf "process group %d descendants survived SIGKILL" pid)

let () =
  let execution_result = ref None in
  let cleanup_err = ref None in
  (try
     wait (monotonic_now () +. 5.);
     let cases = [
       "player", "GET", "/docs/music/player", 200, Some "text/html; charset=utf-8";
       "studio", "GET", "/docs/music/studio", 200, Some "text/html; charset=utf-8";
       "mp3", "GET", "/media/music/historical-enhanced.mp3", 200, Some "audio/mpeg";
       "wav", "GET", "/media/music/historical-mix.wav", 200, Some "audio/wav";
       "head", "HEAD", "/media/music/historical-enhanced.mp3", 200, Some "audio/mpeg";
       "missing", "GET", "/docs/music/absent", 404, None;
       "traversal", "GET", "/docs/music/../design/private", 404, None;
       "percent", "GET", "/docs/%6dusic/player", 404, None;
       "backslash", "GET", "/docs/music%5cplayer", 404, None;
       "method", "POST", "/docs/music/player", 405, None;
     ] in
     let cases = cases @ [
       "exact-path", "GET", "/docs/music/" ^ String.make 4084 'x', 404, None;
       "above-path", "GET", "/docs/music/" ^ String.make 4085 'x', 414, None;
       "long-normalized-music", "GET", "/" ^ String.make 4100 'x' ^ "/../docs/music/player", 414, None;
       "long-head", "HEAD", "/" ^ String.make 4096 'x', 414, None;
       "malformed-mixed", "GET", "/%zz/../%64ocs/%6dusic/player", 404, None;
     ] in
     let rows = List.map (fun (n, m, p, s, c) -> check n m p s c) cases in
     execution_result := Some rows
   with exn ->
     execution_result := None);

  (* Checked cleanup with bounded drain and mandatory EOF observation *)
  (try
     stop_process_group pid;
     finish_drain ~deadline:(monotonic_now () +. 1.0) ~state:drain_st ~log_r ~log_fd ();
   with exn ->
     cleanup_err := Some (Printexc.to_string exn));

  (* Publish durable verification only after cleanup has succeeded *)
  match !execution_result, !cleanup_err with
  | Some rows, None ->
      let j = `Assoc [
        "schema", `String "uos.ev86-http-verification/v1";
        "status", `String "PASS";
        "scope", `String "Private native HTTP bytes only; no playback/deploy/admission";
        "host", `String "nas-1.tail55d152.ts.net";
        "private_resolver_mapping", `String "127.0.0.1";
        "port", `Int port;
        "child_argv", `List (Array.to_list argv |> List.map (fun s -> `String s));
        "server_log", `Assoc [
          "path", `String log_path;
          "bytes_read", `Int drain_st.total_read;
          "bytes_written", `Int drain_st.total_written;
          "truncated", `Bool drain_st.truncated;
        ];
        "checks", `List rows;
      ] in
      write (run ^ "/http-verification.json") (Yojson.Safe.pretty_to_string j);
      print_endline ("PASS " ^ string_of_int (List.length rows) ^ " actual HTTP cases " ^ run)
  | Some rows, Some err ->
      let j = `Assoc [
        "schema", `String "uos.ev86-http-verification/v1";
        "status", `String "FAILED_CLEANUP";
        "cleanup_error", `String err;
        "checks_completed", `Int (List.length rows);
      ] in
      write (run ^ "/http-verification.json") (Yojson.Safe.pretty_to_string j);
      failwith ("cleanup failed after checks: " ^ err)
  | None, Some err ->
      let j = `Assoc [
        "schema", `String "uos.ev86-http-verification/v1";
        "status", `String "FAILED_EXECUTION_AND_CLEANUP";
        "cleanup_error", `String err;
      ] in
      write (run ^ "/http-verification.json") (Yojson.Safe.pretty_to_string j);
      failwith ("execution and cleanup both failed: " ^ err)
  | None, None ->
      let j = `Assoc [
        "schema", `String "uos.ev86-http-verification/v1";
        "status", `String "FAILED_EXECUTION";
      ] in
      write (run ^ "/http-verification.json") (Yojson.Safe.pretty_to_string j);
      failwith "HTTP checks execution failed"
