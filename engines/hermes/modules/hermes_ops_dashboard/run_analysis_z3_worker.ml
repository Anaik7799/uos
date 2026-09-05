open Ctypes
open Foreign

module Protocol = Run_analysis_z3_worker_protocol
module Linked_z3 = Smtml.Solver.Batch (Smtml.Z3_mappings)

let rlimit : [`rlimit] structure typ = structure "rlimit"
let rlim_cur = field rlimit "rlim_cur" ulong
let rlim_max = field rlimit "rlim_max" ulong
let () = seal rlimit

let c_getrlimit = foreign "getrlimit" (int @-> ptr rlimit @-> returning int)
let c_setrlimit = foreign "setrlimit" (int @-> ptr rlimit @-> returning int)
let c_setpgid = foreign "setpgid" (int @-> int @-> returning int)
let c_getpgrp = foreign "getpgrp" (void @-> returning int)

let rlimit_cpu = 0
let rlimit_as = 9

let limit_value value =
  if Unsigned.ULong.compare value Unsigned.ULong.max_int = 0 then
    Protocol.Infinite
  else Protocol.Finite (Unsigned.ULong.to_int64 value)

let observe_limit resource =
  let value = make rlimit in
  if c_getrlimit resource (addr value) <> 0 then
    Error "getrlimit failed"
  else
    Ok
      (Protocol.Worker_evidence.limit_observation
         ~current:(limit_value (getf value rlim_cur))
         ~maximum:(limit_value (getf value rlim_max)))

let target_limit requested (before : Protocol.limit_observation) =
  match before.maximum with
  | Protocol.Infinite -> requested
  | Protocol.Finite maximum -> Int64.min requested maximum

let apply_limit resource requested =
  match observe_limit resource with
  | Error _ as error -> error
  | Ok before ->
      let target = target_limit requested before in
      if Int64.compare target 0L <= 0 then Error "existing resource ceiling is zero"
      else
        let value = make rlimit in
        let encoded = Unsigned.ULong.of_int64 target in
        setf value rlim_cur encoded;
        setf value rlim_max encoded;
        if c_setrlimit resource (addr value) <> 0 then Error "setrlimit failed"
        else
          match observe_limit resource with
          | Error _ as error -> error
          | Ok after ->
              Ok
                (Protocol.Worker_evidence.applied_limit ~requested ~before ~after
                   ~applied:true)

let identity_of_stats (stats : Unix.stats) =
  Resource_envelope.{ device = stats.st_dev; inode = stats.st_ino }

let rec read_fd_digest descriptor buffer context bytes =
  match Unix.read descriptor buffer 0 (Bytes.length buffer) with
  | 0 ->
      Ok
        (bytes,
         Digestif.SHA256.get context |> Digestif.SHA256.to_hex)
  | count ->
      read_fd_digest descriptor buffer
        (Digestif.SHA256.feed_bytes context buffer ~off:0 ~len:count)
        (bytes + count)
  | exception Unix.Unix_error (Unix.EINTR, _, _) ->
      read_fd_digest descriptor buffer context bytes
  | exception exn -> Error (Printexc.to_string exn)

let executable_objects () =
  match Unix.openfile "/proc/self/exe" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 with
  | exception exn -> Error (Printexc.to_string exn)
  | descriptor ->
      Fun.protect ~finally:(fun () -> Unix.close descriptor) (fun () ->
        let before = Unix.fstat descriptor in
        match
          read_fd_digest descriptor (Bytes.create 65_536)
            (Digestif.SHA256.init ()) 0
        with
        | Error _ as error -> error
        | Ok (bytes, digest) ->
            let after = Unix.fstat descriptor in
            begin match Protocol.sha256_of_hex digest with
            | Error error -> Error (Protocol.render_error error)
            | Ok digest ->
                begin match
                  Protocol.Worker_evidence.worker_object
                    ~identity:(identity_of_stats before) ~bytes ~digest,
                  Protocol.Worker_evidence.worker_object
                    ~identity:(identity_of_stats after) ~bytes ~digest
                with
                | Ok before, Ok after -> Ok (before, after)
                | Error errors, _ | _, Error errors ->
                    Error (String.concat "; " errors)
                end
            end)

let write_all descriptor bytes =
  let rec loop offset =
    if offset = String.length bytes then Ok ()
    else
      match
        Unix.write_substring descriptor bytes offset
          (String.length bytes - offset)
      with
      | 0 -> Error "capture write made no progress"
      | count -> loop (offset + count)
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop offset
      | exception exn -> Error (Printexc.to_string exn)
  in
  loop 0

let read_stdin_bounded (request : Protocol.request) =
  let maximum = request.limits.maximum_query_bytes in
  let chunk = Bytes.create 4096 in
  let buffer = Buffer.create (min maximum 4096) in
  let rec loop observed =
    match input stdin chunk 0 (Bytes.length chunk) with
    | 0 -> Ok (Buffer.contents buffer)
    | count ->
        let observed = observed + count in
        if observed > maximum then Error "stdin exceeded maximum query bytes"
        else begin Buffer.add_subbytes buffer chunk 0 count; loop observed end
    | exception Sys_error detail -> Error detail
  in
  loop 0

let rec first_n count values =
  if count <= 0 then []
  else
    match values with
    | [] -> []
    | value :: rest -> value :: first_n (count - 1) rest

let bounded_symbol_name symbol =
  let name = Smtml.Symbol.to_string symbol in
  if String.length name <= 64 then name else String.sub name 0 64 ^ "..."

let unresolved_symbols assertions =
  Smtml.Expr.get_symbols assertions
  |> List.filter (fun symbol ->
       Smtml.Ty.equal Smtml.Ty.Ty_none (Smtml.Symbol.type_of symbol))
  |> first_n 8
  |> List.map bounded_symbol_name

let parse_and_solve path timeout_ms =
  match Smtml.Parse.Smtlib.from_file (Fpath.v path) with
  | Error (`Msg detail) -> Error ("SMT-LIB parse failed: " ^ detail)
  | Ok raw_script ->
      begin
        match Smtml.Rewrite.rewrite raw_script with
        | exception exn ->
            Error ("SMT-LIB rewrite failed: " ^ Printexc.to_string exn)
      | script ->
          let assertions = ref [] in
          let check_count = ref 0 in
          let declared_logic = ref None in
          let invalid = ref [] in
          List.iter
            (function
              | Smtml.Ast.Assert expression ->
                  assertions := expression :: !assertions
              | Smtml.Ast.Check_sat [] -> incr check_count
              | Smtml.Ast.Set_logic logic ->
                  begin
                    match !declared_logic with
                    | None -> declared_logic := Some logic
                    | Some _ -> invalid := "duplicate set-logic" :: !invalid
                  end
              | Smtml.Ast.Declare_const _
              | Smtml.Ast.Declare_fun _ -> ()
              | command ->
                  invalid := Smtml.Ast.to_string command :: !invalid)
            script;
          if !check_count <> 1 then
            Error "SMT-LIB query must contain exactly one unqualified check-sat"
          else if !invalid <> [] then
            Error
              ("SMT-LIB query contains unsupported commands: "
               ^ String.concat "," (List.rev !invalid))
          else if !assertions = [] then Error "SMT-LIB query has no assertions"
          else if Option.is_none !declared_logic then
            Error "SMT-LIB query must declare exactly one supported logic"
          else if unresolved_symbols !assertions <> [] then
            Error
              ("SMT-LIB query retains unresolved symbols after rewrite: "
               ^ String.concat "," (unresolved_symbols !assertions))
          else
            let params = Smtml.Params.(default () $ (Timeout, timeout_ms)) in
            let solver_calls_before = !(Linked_z3.solver_count) in
            match
              let solver =
                Linked_z3.create ~params ~logic:(Option.get !declared_logic) ()
              in
              Linked_z3.check solver (List.rev !assertions)
            with
            | answer ->
                let solver_calls_after = !(Linked_z3.solver_count) in
                let answer =
                  match answer with
                  | `Sat -> Protocol.Sat
                  | `Unsat -> Protocol.Unsat
                  | `Unknown -> Protocol.Unknown
                in
                Ok
                  ( answer,
                    List.length !assertions,
                    solver_calls_after - solver_calls_before )
            | exception exn -> Error (Printexc.to_string exn)
      end

let peak_rss_bytes () =
  match open_in "/proc/self/status" with
  | exception exn -> Error (Printexc.to_string exn)
  | channel ->
      Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
        let rec find () =
          match input_line channel with
          | line ->
              if String.length line >= 6 && String.sub line 0 6 = "VmHWM:" then
                begin match
                  String.split_on_char ' ' line
                  |> List.filter (fun value -> value <> "")
                with
                | [ _; kib; "kB" ] ->
                    begin match Int64.of_string_opt kib with
                    | Some value -> Ok (Int64.mul value 1024L)
                    | None -> Error "invalid VmHWM value"
                    end
                | _ -> Error "invalid VmHWM row"
                end
              else find ()
          | exception End_of_file -> Error "VmHWM is absent"
        in
        find ())

let remove_file path =
  match Sys.remove path with () -> true | exception Sys_error _ -> false

let remove_directory path =
  match Unix.rmdir path with () -> true | exception Unix.Unix_error _ -> false

let capture_and_solve (query : Protocol.admitted_query) timeout_ms =
  match Filename.temp_dir ~perms:0o700 "hermes-linked-z3-" ".capture" with
  | exception exn -> Error (Printexc.to_string exn)
  | directory ->
      let path = Filename.concat directory "query.smt2" in
      let descriptor = ref None in
      let cleaned = ref false in
      Fun.protect
        ~finally:(fun () ->
          Option.iter (fun fd -> try Unix.close fd with Unix.Unix_error _ -> ()) !descriptor;
          if not !cleaned then begin
            ignore (remove_file path);
            ignore (remove_directory directory)
          end)
        (fun () ->
          Unix.chmod directory 0o700;
          let directory_stats = Unix.stat directory in
          let fd =
            Unix.openfile path
              [ Unix.O_CREAT; Unix.O_EXCL; Unix.O_RDWR; Unix.O_CLOEXEC ] 0o600
          in
          descriptor := Some fd;
          Unix.fchmod fd 0o600;
          match write_all fd query.bytes with
          | Error _ as error -> error
          | Ok () ->
              let file_before = Unix.fstat fd in
              begin match parse_and_solve path timeout_ms with
              | Error _ as error -> error
              | Ok (answer, assertion_count, solver_call_delta) ->
                  ignore (Unix.LargeFile.lseek fd 0L Unix.SEEK_SET);
                  begin match
                    read_fd_digest fd (Bytes.create 4096)
                      (Digestif.SHA256.init ()) 0
                  with
                  | Error _ as error -> error
                  | Ok (readback_bytes, readback_digest) ->
                      let file_after = Unix.fstat fd in
                      Unix.close fd;
                      descriptor := None;
                      let file_removed = remove_file path in
                      let directory_removed = remove_directory directory in
                      cleaned := file_removed && directory_removed;
                      begin match Protocol.sha256_of_hex readback_digest with
                      | Error error -> Error (Protocol.render_error error)
                      | Ok readback_digest ->
                        begin match Protocol.Worker_evidence.capture
                          ~directory_object_before:
                            (identity_of_stats directory_stats)
                          ~directory_mode_before:directory_stats.st_perm
                          ~file_object_before:(identity_of_stats file_before)
                          ~file_object_after:(identity_of_stats file_after)
                          ~file_mode_before:file_before.st_perm ~readback_digest
                          ~readback_bytes ~file_removed ~directory_removed
                      with
                      | Ok capture ->
                          begin match peak_rss_bytes () with
                          | Ok peak_rss_bytes ->
                              Ok
                                (capture, answer, assertion_count,
                                 solver_call_delta, peak_rss_bytes)
                          | Error _ as error -> error
                          end
                      | Error errors -> Error (String.concat "; " errors)
                        end
                      end
                  end
              end)

let bounded_emit maximum encoded =
  if String.length encoded + 1 > maximum then Error "frame exceeds output bound"
  else begin print_endline encoded; flush stdout; Ok () end

let refuse ?request reason detail exit_kind =
  let request_digest =
    Option.map
      (fun (request : Protocol.request) -> request.Protocol.request_digest)
      request
  in
  let refusal = Protocol.make_refusal ~request_digest reason ~detail in
  let maximum =
    Option.fold ~none:4096
      ~some:(fun (request : Protocol.request) ->
        request.Protocol.limits.maximum_output_bytes)
      request
  in
  ignore (bounded_emit maximum (Protocol.encode_refusal refusal));
  exit (Protocol.exit_code exit_kind)

let establish_handshake request =
  let pid = Unix.getpid () in
  if c_setpgid 0 0 <> 0 then Error "setpgid failed"
  else if c_getpgrp () <> pid then Error "worker did not become process-group leader"
  else
    match executable_objects () with
    | Error _ as error -> error
    | Ok (object_before, object_after) ->
        if
          not
            (String.equal
               (Protocol.sha256_to_hex object_before.digest)
               (Protocol.sha256_to_hex request.Protocol.worker_executable_digest))
        then Error "worker executable digest differs from request"
        else
          match
            apply_limit rlimit_as request.limits.virtual_memory_bytes,
            apply_limit rlimit_cpu (Int64.of_int request.limits.cpu_seconds)
          with
          | Ok virtual_memory, Ok cpu ->
              begin match
                Protocol.Worker_evidence.handshake request ~object_before
                  ~object_after ~virtual_memory ~cpu ~process_id:pid
                  ~process_group_id:(c_getpgrp ())
              with
              | Ok handshake -> Ok handshake
              | Error errors -> Error (String.concat "; " errors)
              end
          | Error detail, _ | _, Error detail -> Error detail

let () =
  let arguments = Array.sub Sys.argv 1 (Array.length Sys.argv - 1) in
  match Protocol.decode_argv arguments with
  | Error error ->
      refuse Protocol.Invalid_request (Protocol.render_error error)
        Protocol.Rejected_exit
  | Ok request ->
      begin match establish_handshake request with
      | Error detail ->
          refuse ~request Protocol.Limit_application_failed detail
            Protocol.Unsupported_exit
      | Ok handshake ->
          let handshake_frame = Protocol.encode_handshake handshake in
          if String.length handshake_frame + 1 >= request.limits.maximum_output_bytes
          then
            refuse ~request Protocol.Output_limit_exceeded
              "handshake exceeds output bound" Protocol.Failed_exit
          else
            begin match bounded_emit request.limits.maximum_output_bytes handshake_frame with
            | Error detail ->
                refuse ~request Protocol.Output_limit_exceeded detail Protocol.Failed_exit
            | Ok () ->
                begin match read_stdin_bounded request with
                | Error detail ->
                    refuse ~request Protocol.Query_rejected detail Protocol.Rejected_exit
                | Ok bytes ->
                    begin match Protocol.admit_stdin request bytes with
                    | Error error ->
                        refuse ~request Protocol.Query_rejected
                          (Protocol.render_error error) Protocol.Rejected_exit
                    | Ok query ->
                        begin match
                          capture_and_solve query
                            (request.limits.cpu_seconds * 1000)
                        with
                        | Error detail ->
                            refuse ~request Protocol.Solver_failed detail Protocol.Failed_exit
                        | Ok (capture, answer, assertion_count,
                              solver_call_delta, peak_rss_bytes) ->
                            begin match
                              Protocol.Worker_evidence.result ~request ~query
                                ~handshake ~capture ~answer ~solver_id:"z3"
                                ~solver_version:Z3.Version.to_string
                                ~solver_call_delta ~assertion_count
                                ~peak_rss_bytes
                            with
                            | Error errors ->
                                refuse ~request Protocol.Solver_failed
                                  (String.concat "; " errors) Protocol.Failed_exit
                            | Ok result ->
                                let result_frame = Protocol.encode_result result in
                                if
                                  String.length handshake_frame + 1
                                  + String.length result_frame + 1
                                  > request.limits.maximum_output_bytes
                                then
                                  refuse ~request Protocol.Output_limit_exceeded
                                    "transcript exceeds output bound"
                                    Protocol.Failed_exit
                                else begin
                                  print_endline result_frame;
                                  flush stdout;
                                  exit (Protocol.exit_code Protocol.Completed_exit)
                                end
                            end
                        end
                    end
                end
            end
      end
