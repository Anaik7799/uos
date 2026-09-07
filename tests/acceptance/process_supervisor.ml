#use "topfind";;
#require "unix";;
#require "mtime.clock.os";;
#require "ctypes.foreign";;

(* Each invocation is supervised by a dedicated child process. That process is
   the only subreaper, so waitpid(-1) cannot consume runner-owned children. *)

type process_limits = { timeout_ms : int; stdout_limit : int; stderr_limit : int; term_grace_ms : int }
type termination = Exited of int | Signaled of int | Timed_out | Output_limit
type process_result = {
  termination : termination; stdout : string; stderr : string; duration_ms : float;
  stdout_truncated : bool; stderr_truncated : bool; children_reaped : bool; pid : int;
}

(* Operator task budget is 20 minutes. Callers reserve cleanup time from it. *)
let max_timeout_ms = 1_200_000
let max_stream_bytes = 16 * 1024 * 1024
let max_term_grace_ms = 60_000
let monotonic_now () = Int64.to_float (Mtime_clock.elapsed_ns ()) /. 1_000_000_000.
let seconds value = float_of_int value /. 1000.
let safe_close fd = try Unix.close fd with Unix.Unix_error _ -> ()

let failure started message = {
  termination = Exited 127; stdout = ""; stderr = message;
  duration_ms = (monotonic_now () -. started) *. 1000.;
  stdout_truncated = false; stderr_truncated = false; children_reaped = false; pid = 0;
}

let validate limits argv =
  if argv = [] then invalid_arg "process supervisor: argv must not be empty";
  let bounded name value maximum =
    if value <= 0 || value > maximum then invalid_arg ("process supervisor: invalid " ^ name)
  in
  bounded "timeout_ms" limits.timeout_ms max_timeout_ms;
  bounded "stdout_limit" limits.stdout_limit max_stream_bytes;
  bounded "stderr_limit" limits.stderr_limit max_stream_bytes;
  bounded "term_grace_ms" limits.term_grace_ms max_term_grace_ms

(* Linux prctl(2): PR_SET_CHILD_SUBREAPER / PR_GET_CHILD_SUBREAPER.  prctl's
   variadic value slots are C long (machine-word), not C int. *)
let prctl_set = Foreign.foreign "prctl"
  Ctypes.(int @-> long @-> long @-> long @-> long @-> returning int)
let prctl_get = Foreign.foreign "prctl"
  Ctypes.(int @-> ptr int @-> long @-> long @-> long @-> returning int)
let pr_set_child_subreaper = 36
let pr_get_child_subreaper = 37

let enable_subreaper () =
  try
    let value = Ctypes.allocate Ctypes.int 0 in
    let one = Signed.Long.of_int 1 and zero = Signed.Long.of_int 0 in
    prctl_set pr_set_child_subreaper one zero zero zero = 0 &&
    prctl_get pr_get_child_subreaper value zero zero zero = 0 &&
    let open Ctypes in !@value = 1
  with _ -> false

type proc_info = { ppid : int; pgrp : int }
type proc_stat = Stat of proc_info | Gone | Unknown

let proc_stat path =
  try
    let line = In_channel.with_open_text path (fun channel ->
      match In_channel.input_line channel with Some line -> line | None -> raise End_of_file) in
    let close_paren = String.rindex line ')' in
    let after = String.sub line (close_paren + 1) (String.length line - close_paren - 1) in
    match String.split_on_char ' ' after |> List.filter (fun field -> field <> "") with
    | _state :: ppid :: pgrp :: _ ->
      begin match int_of_string_opt ppid, int_of_string_opt pgrp with
      | Some ppid, Some pgrp -> Stat { ppid; pgrp }
      | _ -> Unknown
      end
    | _ -> Unknown
  with
  | Sys_error _ | End_of_file | Not_found -> if Sys.file_exists path then Unknown else Gone
  | Invalid_argument _ -> Unknown

let scan_proc predicate =
  try
    let unknown = ref false and values = ref [] in
    Array.iter (fun entry -> match int_of_string_opt entry with
      | None -> ()
      | Some pid -> match proc_stat (Filename.concat (Filename.concat "/proc" entry) "stat") with
        | Stat stat when predicate pid stat -> values := pid :: !values
        | Stat _ | Gone -> ()
        | Unknown -> unknown := true) (Sys.readdir "/proc");
    if !unknown then None else Some !values
  with Sys_error _ -> None

let group_members pgrp = scan_proc (fun _ stat -> stat.pgrp = pgrp)
let direct_children parent = scan_proc (fun _ stat -> stat.ppid = parent)
let signal_group pgrp signal = try Unix.kill (-pgrp) signal with Unix.Unix_error _ -> ()
let signal_pid pid signal = try Unix.kill pid signal with Unix.Unix_error _ -> ()

let rec group_empty_by deadline pgrp =
  match group_members pgrp with
  | Some [] -> true
  | None -> false
  | Some _ when monotonic_now () >= deadline -> false
  | Some _ -> ignore (Unix.select [] [] [] 0.02); group_empty_by deadline pgrp

let cleanup_group ~grace pgrp =
  match group_members pgrp with
  | Some [] -> true
  | Some _ | None ->
    (* Even uninspectable groups receive TERM then KILL; only proof is withheld. *)
    signal_group pgrp Sys.sigterm;
    if group_empty_by (monotonic_now () +. grace) pgrp then true
    else begin
      signal_group pgrp Sys.sigkill;
      group_empty_by (monotonic_now () +. max 0.10 grace) pgrp
    end

let rec wait_pid_until deadline pid =
  if monotonic_now () >= deadline then false else
    try
      let got, _ = Unix.waitpid [Unix.WNOHANG] pid in
      if got = 0 then begin ignore (Unix.select [] [] [] 0.01); wait_pid_until deadline pid end
      else true
    with Unix.Unix_error (Unix.ECHILD, _, _) -> true

let abort_target pid =
  signal_group pid Sys.sigterm; signal_pid pid Sys.sigterm;
  ignore (Unix.select [] [] [] 0.02);
  signal_group pid Sys.sigkill; signal_pid pid Sys.sigkill;
  ignore (wait_pid_until (monotonic_now () +. 0.25) pid)

let status_to_termination = function
  | Unix.WEXITED code -> Exited code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> Signaled signal

let reap_nonblocking_to_echild () =
  let rec loop () =
    try
      let got, _ = Unix.waitpid [Unix.WNOHANG] (-1) in
      if got = 0 then false else loop ()
    with Unix.Unix_error (Unix.ECHILD, _, _) -> true
  in loop ()

let signal_adopted_children supervisor signal =
  match direct_children supervisor with
  | None -> ()
  | Some pids -> List.iter (fun pid -> signal_group pid signal; signal_pid pid signal) pids

let reap_all_descendants ~grace supervisor =
  (* This proof covers ordinary fork descendants reparented to this subreaper;
     clone/ptrace and external cgroup containment are outside this interface. *)
  let rec until deadline signal =
    signal_adopted_children supervisor signal;
    if reap_nonblocking_to_echild () then true
    else if monotonic_now () >= deadline then false
    else begin ignore (Unix.select [] [] [] 0.02); until deadline signal end
  in
  if until (monotonic_now () +. grace) Sys.sigterm then true
  else until (monotonic_now () +. max 0.10 grace) Sys.sigkill

let spawn_target argv =
  let stdout_r, stdout_w = Unix.pipe ~cloexec:true () in
  let stderr_r, stderr_w =
    try Unix.pipe ~cloexec:true () with exn -> safe_close stdout_r; safe_close stdout_w; raise exn
  in
  let pid =
    try Unix.fork () with exn ->
      safe_close stdout_r; safe_close stdout_w; safe_close stderr_r; safe_close stderr_w; raise exn
  in
  if pid = 0 then begin
    safe_close stdout_r; safe_close stderr_r;
    try
      ignore (Unix.setsid ());
      Unix.dup2 stdout_w Unix.stdout; Unix.dup2 stderr_w Unix.stderr;
      safe_close stdout_w; safe_close stderr_w;
      Unix.execvp (List.hd argv) (Array.of_list argv)
    with exn ->
      safe_close stdout_w; safe_close stderr_w;
      prerr_endline ("process supervisor exec failure: " ^ Printexc.to_string exn);
      exit 127
  end else begin
    safe_close stdout_w; safe_close stderr_w;
    (pid, stdout_r, stderr_r)
  end

let supervise_target started limits argv abort_requested =
  let pid, stdout_r, stderr_r = spawn_target argv in
  let stdout_fd = ref (Some stdout_r) and stderr_fd = ref (Some stderr_r) in
  let finished = ref false in
  Fun.protect
    ~finally:(fun () ->
      if not !finished then begin
        abort_target pid;
        ignore (reap_all_descendants ~grace:(seconds limits.term_grace_ms) (Unix.getpid ()))
      end;
      Option.iter safe_close !stdout_fd; Option.iter safe_close !stderr_fd)
    (fun () ->
      Unix.set_nonblock stdout_r; Unix.set_nonblock stderr_r;
      let stdout = Buffer.create (min limits.stdout_limit 4096) in
      let stderr = Buffer.create (min limits.stderr_limit 4096) in
      let stdout_truncated = ref false and stderr_truncated = ref false in
      let reason = ref None and term_sent_at = ref None and kill_sent = ref false in
      let leader = ref None and leader_observed = ref true in
      let timeout_at = started +. seconds limits.timeout_ms and grace = seconds limits.term_grace_ms in
      let start_shutdown value = match !reason with
        | Some _ -> ()
        | None -> reason := Some value; term_sent_at := Some (monotonic_now ()); signal_group pid Sys.sigterm
      in
      let poll_leader () = if !leader = None then
        try let got, status = Unix.waitpid [Unix.WNOHANG] pid in if got <> 0 then leader := Some status
        with Unix.Unix_error (Unix.ECHILD, _, _) -> leader_observed := false; leader := Some (Unix.WEXITED 127)
      in
      let read_stream fd_slot buffer limit truncated = match !fd_slot with
        | None -> false
        | Some fd ->
          let remaining = limit - Buffer.length buffer in
          let bytes = Bytes.create (min 8192 (remaining + 1)) in
          try
            let got = Unix.read fd bytes 0 (Bytes.length bytes) in
            if got = 0 then begin safe_close fd; fd_slot := None; false end
            else begin
              let accepted = min got remaining in
              if accepted > 0 then Buffer.add_subbytes buffer bytes 0 accepted;
              if got > remaining then begin truncated := true; true end else false
            end
          with
          | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> false
          | Unix.Unix_error _ -> safe_close fd; fd_slot := None; false
      in
      let process_ready ready =
        let exceeded = ref false in
        begin match !stdout_fd with Some fd when List.mem fd ready ->
          if read_stream stdout_fd stdout limits.stdout_limit stdout_truncated then exceeded := true | _ -> () end;
        begin match !stderr_fd with Some fd when List.mem fd ready ->
          if read_stream stderr_fd stderr limits.stderr_limit stderr_truncated then exceeded := true | _ -> () end;
        if !exceeded then start_shutdown Output_limit
      in
      let rec supervise () =
        poll_leader ();
        begin match !reason, !term_sent_at with
        | None, _ when !abort_requested -> start_shutdown Timed_out
        | None, _ when !leader = None && monotonic_now () >= timeout_at -> start_shutdown Timed_out
        | Some _, Some sent when not !kill_sent && monotonic_now () >= sent +. grace -> signal_group pid Sys.sigkill; kill_sent := true
        | _ -> () end;
        match !leader with
        | Some _ -> ()
        | None ->
          let fds = List.filter_map Fun.id [!stdout_fd; !stderr_fd] in
          let now = monotonic_now () in
          let next = match !reason, !term_sent_at with
            | None, _ -> timeout_at | Some _, Some sent when not !kill_sent -> sent +. grace | _ -> now +. 0.02
          in
          let ready, _, _ = Unix.select fds [] [] (max 0. (min 0.02 (next -. now))) in
          process_ready ready; supervise ()
      in
      supervise ();
      ignore (cleanup_group ~grace pid);
      let descendants_reaped = reap_all_descendants ~grace (Unix.getpid ()) in
      let drain_deadline = monotonic_now () +. 0.10 in
      let rec drain () =
        let fds = List.filter_map Fun.id [!stdout_fd; !stderr_fd] in
        if fds <> [] && monotonic_now () < drain_deadline then begin
          let ready, _, _ = Unix.select fds [] [] 0.01 in process_ready ready; drain ()
        end
      in
      drain ();
      let result = {
        termination = (match !reason, !leader with
          | Some value, _ -> value | None, Some status -> status_to_termination status | None, None -> Exited 127);
        stdout = Buffer.contents stdout; stderr = Buffer.contents stderr;
        duration_ms = (monotonic_now () -. started) *. 1000.;
        stdout_truncated = !stdout_truncated; stderr_truncated = !stderr_truncated;
        children_reaped = !leader_observed && descendants_reaped && not !abort_requested; pid;
      } in
      finished := true; result)

let write_all fd bytes =
  let rec loop offset = if offset < Bytes.length bytes then
    try loop (offset + Unix.write fd bytes offset (Bytes.length bytes - offset))
    with Unix.Unix_error (Unix.EINTR, _, _) -> loop offset
  in loop 0

let supervisor_entry started limits argv control_w =
  let abort_requested = ref false in
  let previous = Sys.signal Sys.sigterm (Sys.Signal_handle (fun _ -> abort_requested := true)) in
  let result = Fun.protect ~finally:(fun () -> ignore (Sys.signal Sys.sigterm previous)) (fun () ->
    try
      ignore (Unix.setsid ());
      if enable_subreaper () then supervise_target started limits argv abort_requested
      else failure started "process supervisor: PR_SET_CHILD_SUBREAPER unavailable"
    with exn -> failure started ("process supervisor setup failure: " ^ Printexc.to_string exn))
  in
  try write_all control_w (Marshal.to_bytes result [Marshal.No_sharing]) with _ -> ()

let abort_supervisor ~grace pid =
  (* Normal cleanup can spend TERM+KILL grace in both group and adopted-child
     phases. Let the helper finish that bounded 4*grace protocol first. *)
  signal_pid pid Sys.sigterm;
  if not (wait_pid_until (monotonic_now () +. (4. *. grace) +. 0.50) pid) then begin
    signal_pid pid Sys.sigkill;
    ignore (wait_pid_until (monotonic_now () +. 0.25) pid)
  end

let run_bounded limits argv =
  validate limits argv;
  let started = monotonic_now () in
  try
    let control_r, control_w = Unix.pipe ~cloexec:true () in
    let supervisor =
      try Unix.fork () with exn -> safe_close control_r; safe_close control_w; raise exn
    in
    if supervisor = 0 then begin
      safe_close control_r;
      supervisor_entry started limits argv control_w;
      safe_close control_w;
      exit 0
    end else begin
      safe_close control_w;
      let control_open = ref true and completed = ref false and status = ref None in
      let data = Buffer.create 4096 in
      let maximum = limits.stdout_limit + limits.stderr_limit + 1_048_576 in
      let deadline = started +. seconds limits.timeout_ms +. (4. *. seconds limits.term_grace_ms) +. 2. in
      let poll_supervisor () = if !status = None then
        try let got, value = Unix.waitpid [Unix.WNOHANG] supervisor in if got <> 0 then status := Some value
        with Unix.Unix_error (Unix.ECHILD, _, _) -> status := Some (Unix.WEXITED 127)
      in
      let read_control () =
        let bytes = Bytes.create 8192 in
        try
          let got = Unix.read control_r bytes 0 (Bytes.length bytes) in
          if got = 0 then begin safe_close control_r; control_open := false end
          else if Buffer.length data + got > maximum then raise Exit
          else Buffer.add_subbytes data bytes 0 got
        with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
      in
      Fun.protect
        ~finally:(fun () ->
          if not !completed then abort_supervisor ~grace:(seconds limits.term_grace_ms) supervisor;
          if !control_open then safe_close control_r)
        (fun () ->
          Unix.set_nonblock control_r;
          let rec receive () =
            poll_supervisor ();
            if !status <> None && not !control_open then ()
            else if monotonic_now () >= deadline then raise Exit
            else begin
              let fds = if !control_open then [control_r] else [] in
              let ready, _, _ = Unix.select fds [] [] 0.02 in
              if ready <> [] then read_control ();
              receive ()
            end
          in
          try
            receive ();
            let result = Marshal.from_bytes (Bytes.of_string (Buffer.contents data)) 0 in
            completed := true;
            (result : process_result)
          with _ -> failure started "process supervisor: bounded authority proof failed")
    end
  with _ -> failure started "process supervisor: setup failure"
