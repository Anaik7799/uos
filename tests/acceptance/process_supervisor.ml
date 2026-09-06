#use "topfind";;
#require "unix";;
#require "mtime.clock.os";;

(* Linux-only bounded subprocess supervisor for acceptance scripts.  It runs an
   argv directly, puts the child in a new session/process group, and only marks
   children reaped after /proc proves that the group is empty. *)

type process_limits = {
  timeout_ms : int;
  stdout_limit : int;
  stderr_limit : int;
  term_grace_ms : int;
}

type termination = Exited of int | Signaled of int | Timed_out | Output_limit

type process_result = {
  termination : termination;
  stdout : string;
  stderr : string;
  duration_ms : float;
  stdout_truncated : bool;
  stderr_truncated : bool;
  children_reaped : bool;
  pid : int;
}

let monotonic_now () = Int64.to_float (Mtime_clock.elapsed_ns ()) /. 1_000_000_000.

let safe_close fd =
  try Unix.close fd with Unix.Unix_error _ -> ()

let validate limits argv =
  if argv = [] then invalid_arg "process supervisor: argv must not be empty";
  if limits.timeout_ms <= 0 || limits.stdout_limit < 0 ||
     limits.stderr_limit < 0 || limits.term_grace_ms < 0
  then invalid_arg "process supervisor: invalid process limits"

let seconds milliseconds = float_of_int milliseconds /. 1000.

type proc_stat = Stat of int | Gone | Unknown

let proc_pgrp path =
  try
    let line = In_channel.with_open_text path (fun channel ->
      match In_channel.input_line channel with
      | Some line -> line
      | None -> raise End_of_file) in
    let close_paren = String.rindex line ')' in
    let after = String.sub line (close_paren + 1) (String.length line - close_paren - 1) in
    let fields = String.split_on_char ' ' after |> List.filter (fun s -> s <> "") in
    match fields with
    | _state :: _ppid :: pgrp :: _ ->
      begin match int_of_string_opt pgrp with Some value -> Stat value | None -> Unknown end
    | _ -> Unknown
  with
  | Sys_error _ | End_of_file | Not_found ->
    if Sys.file_exists path then Unknown else Gone
  | Invalid_argument _ -> Unknown

let group_members pgrp =
  try
    let entries = Sys.readdir "/proc" in
    let unknown = ref false in
    let members = ref [] in
    Array.iter (fun entry ->
      match int_of_string_opt entry with
      | None -> ()
      | Some pid ->
        match proc_pgrp (Filename.concat (Filename.concat "/proc" entry) "stat") with
        | Stat found when found = pgrp -> members := pid :: !members
        | Stat _ | Gone -> ()
        | Unknown -> unknown := true
    ) entries;
    if !unknown then None else Some !members
  with Sys_error _ -> None

let signal_group pgrp signal =
  try Unix.kill (-pgrp) signal with
  | Unix.Unix_error (Unix.ESRCH, _, _) -> ()
  | Unix.Unix_error _ -> ()

let rec group_empty_by deadline pgrp =
  match group_members pgrp with
  | Some [] -> true
  | None -> false
  | Some _ when monotonic_now () >= deadline -> false
  | Some _ ->
    ignore (Unix.select [] [] [] 0.02);
    group_empty_by deadline pgrp

let cleanup_group ~grace pgrp =
  match group_members pgrp with
  | Some [] -> true
  | None -> false
  | Some _ ->
    signal_group pgrp Sys.sigterm;
    if group_empty_by (monotonic_now () +. grace) pgrp then true
    else begin
      signal_group pgrp Sys.sigkill;
      group_empty_by (monotonic_now () +. max 0.10 grace) pgrp
    end

let status_to_termination = function
  | Unix.WEXITED code -> Exited code
  | Unix.WSIGNALED signal -> Signaled signal
  | Unix.WSTOPPED signal -> Signaled signal

let run_bounded limits argv =
  validate limits argv;
  let started = monotonic_now () in
  let stdout_r, stdout_w = Unix.pipe ~cloexec:true () in
  let stderr_r, stderr_w = Unix.pipe ~cloexec:true () in
  let pid =
    try Unix.fork () with exn ->
      safe_close stdout_r; safe_close stdout_w;
      safe_close stderr_r; safe_close stderr_w;
      raise exn
  in
  if pid = 0 then begin
    safe_close stdout_r;
    safe_close stderr_r;
    begin
      try
        ignore (Unix.setsid ());
        Unix.dup2 stdout_w Unix.stdout;
        Unix.dup2 stderr_w Unix.stderr;
        safe_close stdout_w;
        safe_close stderr_w;
        let program = List.hd argv in
        Unix.execvp program (Array.of_list argv)
      with exn ->
        safe_close stdout_w;
        safe_close stderr_w;
        prerr_endline ("process supervisor exec failure: " ^ Printexc.to_string exn);
        exit 127
    end
  end else begin
    safe_close stdout_w;
    safe_close stderr_w;
    Unix.set_nonblock stdout_r;
    Unix.set_nonblock stderr_r;
    let stdout_fd = ref (Some stdout_r) in
    let stderr_fd = ref (Some stderr_r) in
    let stdout = Buffer.create (min limits.stdout_limit 4096) in
    let stderr = Buffer.create (min limits.stderr_limit 4096) in
    let stdout_truncated = ref false in
    let stderr_truncated = ref false in
    let reason = ref None in
    let term_sent_at = ref None in
    let kill_sent = ref false in
    let leader = ref None in
    let leader_observed = ref true in
    let timeout_at = started +. seconds limits.timeout_ms in
    let grace = seconds limits.term_grace_ms in
    let start_shutdown value =
      match !reason with
      | Some _ -> ()
      | None ->
        reason := Some value;
        term_sent_at := Some (monotonic_now ());
        signal_group pid Sys.sigterm
    in
    let poll_leader () =
      if !leader = None then
        try
          let got, status = Unix.waitpid [Unix.WNOHANG] pid in
          if got <> 0 then leader := Some status
        with Unix.Unix_error (Unix.ECHILD, _, _) ->
          leader_observed := false;
          leader := Some (Unix.WEXITED 127)
    in
    let read_stream fd_slot buffer limit truncated =
      match !fd_slot with
      | None -> false
      | Some fd ->
        let remaining = limit - Buffer.length buffer in
        let requested = min 8192 (remaining + 1) in
        let bytes = Bytes.create requested in
        try
          let got = Unix.read fd bytes 0 requested in
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
      begin match !stdout_fd with
      | Some fd when List.mem fd ready ->
        if read_stream stdout_fd stdout limits.stdout_limit stdout_truncated then exceeded := true
      | _ -> ()
      end;
      begin match !stderr_fd with
      | Some fd when List.mem fd ready ->
        if read_stream stderr_fd stderr limits.stderr_limit stderr_truncated then exceeded := true
      | _ -> ()
      end;
      if !exceeded then start_shutdown Output_limit
    in
    let rec supervise () =
      poll_leader ();
      begin match !reason, !term_sent_at with
      | None, _ when !leader = None && monotonic_now () >= timeout_at -> start_shutdown Timed_out
      | Some _, Some sent when not !kill_sent && monotonic_now () >= sent +. grace ->
        signal_group pid Sys.sigkill;
        kill_sent := true
      | _ -> ()
      end;
      match !leader with
      | Some _ -> ()
      | None ->
        let fds = List.filter_map (fun value -> value) [!stdout_fd; !stderr_fd] in
        let now = monotonic_now () in
        let next =
          match !reason, !term_sent_at with
          | None, _ -> timeout_at
          | Some _, Some sent when not !kill_sent -> sent +. grace
          | _ -> now +. 0.02
        in
        let wait_for = max 0. (min 0.02 (next -. now)) in
        let ready, _, _ = Unix.select fds [] [] wait_for in
        process_ready ready;
        supervise ()
    in
    supervise ();
    (* The leader's exit is not proof that background children left its group.
       This sweep also covers a leader which exited normally and closed its FDs. *)
    let reaped = cleanup_group ~grace pid && !leader_observed in
    let drain_deadline = monotonic_now () +. 0.10 in
    let rec drain () =
      let fds = List.filter_map (fun value -> value) [!stdout_fd; !stderr_fd] in
      if fds <> [] && monotonic_now () < drain_deadline then begin
        let ready, _, _ = Unix.select fds [] [] 0.01 in
        process_ready ready;
        drain ()
      end
    in
    drain ();
    begin match !stdout_fd with Some fd -> safe_close fd | None -> () end;
    begin match !stderr_fd with Some fd -> safe_close fd | None -> () end;
    let termination =
      match !reason, !leader with
      | Some value, _ -> value
      | None, Some status -> status_to_termination status
      | None, None -> Exited 127
    in
    {
      termination;
      stdout = Buffer.contents stdout;
      stderr = Buffer.contents stderr;
      duration_ms = (monotonic_now () -. started) *. 1000.;
      stdout_truncated = !stdout_truncated;
      stderr_truncated = !stderr_truncated;
      children_reaped = reaped;
      pid;
    }
  end
