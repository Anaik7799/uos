#!/usr/bin/env ocaml
#use "topfind";;
#require "bos,cmdliner,unix,yojson,cryptokit,mtime.clock.os";;

(* @agent_intent: Run the EV programme's realized native tools with argv-only
   process creation, explicit canonical database selection and bounded capture.
   @laws: no shell evaluation; failure propagates; receipts confer no authority.
   Filesystem reads and child startup assume a responsive cooperative local host.
   This adapter does not replace Sa-plan, workspace leases or effect fencing. *)
let root = "/home/an/NAS-setup/uos"
let require condition message = if not condition then failwith message
let mono () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9
let tc = root ^ "/toolchains"
let pinned name = match name with
  | "ocaml" | "dune" -> tc ^ "/opam-ocaml/bin/" ^ name
  | "jj" | "erl" -> tc ^ "/nix-profile/bin/" ^ name
  | "gleam" -> tc ^ "/gleam-1.16.0/bin/gleam"
  | "mojo" -> root ^ "/services/inference/max/.pixi/envs/default/bin/mojo"
  | _ -> failwith ("unknown native tool: " ^ name)
let env () =
  let inherited = ["HOME"; "XDG_RUNTIME_DIR"; "DBUS_SESSION_BUS_ADDRESS";
    "SSL_CERT_FILE"; "NIX_SSL_CERT_FILE"] |> List.filter_map (fun key ->
      Option.map (fun value -> key ^ "=" ^ value) (Sys.getenv_opt key)) in
  Array.of_list ([
    "PATH=" ^ tc ^ "/nix-profile/bin:" ^ tc ^ "/gleam-1.16.0/bin:"
      ^ tc ^ "/opam-ocaml/bin:/usr/bin:/bin";
    "OCAMLPATH=" ^ tc ^ "/opam-ocaml/lib";
    "LANG=C.UTF-8"; "DUNE_CACHE=disabled";
    "ERL_FLAGS=+S 2:2 +A 2"; "ERL_CRASH_DUMP=/dev/null";
    "MODULAR_HOME=" ^ root ^ "/services/inference/max/.pixi/envs/default/share/max";
    "UOS_SA_PLAN_DB=" ^ root ^ "/var/sa-plan/uos.sqlite3"
  ] @ inherited)
let ebin_paths directory excluded =
  Sys.readdir directory |> Array.to_list |> List.sort String.compare
  |> List.filter_map (fun name ->
    let path = directory ^ "/" ^ name ^ "/ebin" in
    if List.mem name excluded || not (Sys.file_exists path) then None
    else if (Unix.stat path).st_kind = Unix.S_DIR then Some path else None)
let command tool args = match tool, args with
  | "coordinator", _ ->
    let paths = ebin_paths (root ^ "/apps/uos_swarm/build/dev/erlang") [] in
    require (paths <> []) "compiled Gleam coordinator absent";
    pinned "erl", ["-noshell"; "-noinput"; "-pa"] @ paths
      @ ["-s"; "session_sync_cli"; "main"; "-s"; "init"; "stop";
         "-extra"; root ^ "/var/coordination/tri-agent"] @ args
  | "sa-plan", _ ->
    root ^ "/engines/hermes/_build/default/modules/sa_plan/test/sa_plan_main.exe", args
  | "risk", _ -> "/tmp/uos-ev-native-risk-20260909/default/validate.exe", args
  | "beam", [compiled; main] ->
    require (not (Filename.is_relative compiled)) "compiled directory must be absolute";
    require (main <> "" && String.for_all (function
      | 'a'..'z' | '0'..'9' | '_' -> true | _ -> false) main) "invalid Gleam main name";
    let paths = ebin_paths (root ^ "/apps/cepaf_gleam/build/dev/erlang")
      ["cepaf_gleam"; "uos_swarm"] in
    let output = compiled ^ "/ebin" in
    require (Sys.file_exists (output ^ "/" ^ main ^ ".beam")) "compiled main absent";
    pinned "erl", ["-noshell"; "-noinput"; "-pa"] @ paths
      @ ["-pa"; output; "-s"; main; "main"; "-s"; "init"; "stop"]
  | ("gleam" | "mojo" | "jj" | "dune"), _ -> pinned tool, args
  | "chronyc", _ -> "/usr/bin/chronyc", args
  | "native", executable :: rest ->
    require (not (Filename.is_relative executable)) "native executable must be absolute";
    let ic = open_in_bin executable in
    let magic = Fun.protect (fun () -> really_input_string ic 4)
      ~finally:(fun () -> close_in_noerr ic) in
    require (magic = "\127ELF") "native mode requires a compiled ELF executable";
    executable, rest
  | _ -> failwith "unsupported command or argument shape"
let status_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal
let ignore_missing_process f = try f () with Unix.Unix_error (Unix.ESRCH, _, _) -> ()
let run cwd seconds input executable args =
  require (seconds > 0. && seconds <= 240.) "seconds must be within (0,240]";
  let cmd = Bos.Cmd.(v executable %% of_list args) |> Bos.Cmd.to_list in
  let r, w = Unix.pipe ~cloexec:true () in
  let started = mono () and utc_started = Unix.gettimeofday () in
  let pid = Unix.fork () in
  if pid = 0 then begin
    try
      ignore (Unix.setsid ()); Unix.chdir cwd; Unix.close r;
      Unix.dup2 w Unix.stdout; Unix.dup2 w Unix.stderr; Unix.close w;
      let source = Unix.openfile input [Unix.O_RDONLY] 0 in
      Unix.dup2 source Unix.stdin; Unix.close source;
      Unix.execve executable (Array.of_list cmd) (env ())
    with error ->
      prerr_endline (Printexc.to_string error); Unix._exit 127
  end;
  Unix.close w; Unix.set_nonblock r;
  let status = ref None and eof = ref false in
  let buffer = Buffer.create 4096 and bytes = Bytes.create 16384 in
  let terminate () =
    ignore_missing_process (fun () -> Unix.kill (-pid) Sys.sigkill);
    if !status = None then begin
      ignore_missing_process (fun () -> Unix.kill pid Sys.sigkill);
      let _, result = Unix.waitpid [] pid in status := Some result
    end in
  let reason = ref None in
  Fun.protect ~finally:(fun () -> Unix.close r) (fun () ->
    try
      while not !eof || !status = None do
        if mono () -. started > seconds then failwith "deadline exceeded";
        if !status = None then (match Unix.waitpid [Unix.WNOHANG] pid with
          | 0, _ -> () | _, result -> status := Some result);
        let ready, _, _ = Unix.select (if !eof then [] else [r]) [] [] 0.02 in
        if ready <> [] then
          try
            let n = Unix.read r bytes 0 (Bytes.length bytes) in
            if n = 0 then eof := true else begin
              require (Buffer.length buffer + n <= 4_194_304) "output limit exceeded";
              Buffer.add_subbytes buffer bytes 0 n
            end
          with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> ()
      done
    with error -> reason := Some (Printexc.to_string error); terminate ());
  let output = Buffer.contents buffer in
  let code = match !reason, !status with
    | Some _, _ -> 124 | None, Some result -> status_code result | _ -> 125 in
  let digest value = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) value
    |> Cryptokit.transform_string (Cryptokit.Hexa.encode ()) in
  let receipt = `Assoc [
    "schema", `String "uos.ev-native-invocation.v1"; "authority", `String "NONE";
    "cwd", `String cwd; "argv", `List (List.map (fun x -> `String x) cmd);
    "utc_started", `Float utc_started; "utc_finished", `Float (Unix.gettimeofday ());
    "elapsed_seconds", `Float (mono () -. started); "deadline_seconds", `Float seconds;
    "exit_code", `Int code; "output", `String output; "output_sha256", `String (digest output);
    "failure", (match !reason with None -> `Null | Some value -> `String value);
    "clock_synchronization", `String "NOT_CHECKED_BY_ADAPTER";
    "scope", `String "Invocation observation only; no candidate or producer authentication"] in
  code, output, receipt
let write_new path json =
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
  let channel = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () ->
    output_string channel (Yojson.Safe.pretty_to_string json ^ "\n");
    flush channel; Unix.fsync fd)
let execute cwd seconds receipt input tool args =
  try
    let executable, args = command tool args in
    let code, output, observation = run cwd seconds input executable args in
    Option.iter (fun path -> write_new path observation) receipt;
    print_string output; flush stdout;
    if code <> 0 then prerr_endline ("native invocation exited " ^ string_of_int code);
    code
  with error -> prerr_endline (Printexc.to_string error); 2
let () =
  let open Cmdliner in
  let cwd = Arg.(value & opt string root & info ["cwd"] ~doc:"Child working directory.") in
  let seconds = Arg.(value & opt float 30. & info ["seconds"] ~doc:"Monotonic child deadline.") in
  let receipt = Arg.(value & opt (some string) None & info ["receipt"] ~doc:"New JSON invocation receipt.") in
  let input = Arg.(value & opt string "/dev/null" & info ["stdin"] ~doc:"Input file, opened read-only.") in
  let tool = Arg.(required & pos 0 (some string) None & info [] ~docv:"TOOL") in
  let args = Arg.(value & pos_right 0 string [] & info [] ~docv:"ARG") in
  exit (Cmd.eval' (Cmd.v (Cmd.info "ev-native" ~doc:"Native EV verification and coordination adapter")
    Term.(const execute $ cwd $ seconds $ receipt $ input $ tool $ args)))
