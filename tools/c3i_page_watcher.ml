(* tools/c3i_page_watcher.ml
 * =============================================================================
 * [C3I-SIL6-MSTS] C3I / UOS Native OCaml Dynamic Page Watcher & Hot-Reloader
 * =============================================================================
 * Zero Node.js | Zero Python | Zero Muda | Pure Native OCaml 5.5 + Linux Inotify
 * 
 * Functions:
 *   1. Monitors src/ trees in c3i/lib/cepaf_gleam and uos/apps/cepaf_gleam via inotify.
 *   2. On .gleam / .erl save, debounces 300ms.
 *   3. Synchronizes touched files between uos and c3i.
 *   4. Executes `gleam build` in 150ms - 300ms.
 *   5. Calls HTTP GET /api/v1/reload over raw Unix socket to hot-swap BEAM bytecode.
 *   6. BEAM soft-purges old bytecode and loads new module in < 5ms without restart!
 * 
 * STAMP: SC-GLM-UI-001, SC-HA-001, SC-HA-002, SC-MUDA-001, SC-NODE-001
 * Sanskrit: अविनाशि तु तद्विद्धि येन सर्वमिदं ततम् (Gita 2.17)
 * =============================================================================
 *)

open Unix

external inotify_init : unit -> int = "caml_c3i_inotify_init"
external inotify_add_watch : int -> string -> int -> int = "caml_c3i_inotify_add_watch"
external inotify_read_names : int -> string list = "caml_c3i_inotify_read_names"

let in_modify = 0x00000002
let in_close_write = 0x00000008
let in_moved_to = 0x00000080
let in_create = 0x00000100
let watch_mask = in_modify lor in_close_write lor in_moved_to lor in_create

let workspace_root = "/home/an/NAS-setup"
let c3i_gleam_src = Filename.concat workspace_root "c3i/lib/cepaf_gleam/src"
let uos_gleam_src = Filename.concat workspace_root "uos/apps/cepaf_gleam/src"
let c3i_gleam_dir = Filename.concat workspace_root "c3i/lib/cepaf_gleam"
let uos_gleam_dir = Filename.concat workspace_root "uos/apps/cepaf_gleam"

let running = ref true

let handle_signal _ =
  Printf.printf "\n[OCAML-WATCHER] Received termination signal. Exiting gracefully...\n%!";
  running := false

let has_matching_ext filename =
  Filename.check_suffix filename ".gleam" ||
  Filename.check_suffix filename ".erl" ||
  Filename.check_suffix filename ".hrl"

let rec walk_dirs base_dir acc =
  if not (Sys.file_exists base_dir && Sys.is_directory base_dir) then acc
  else
    let entries = Sys.readdir base_dir in
    let subdirs = ref acc in
    subdirs := base_dir :: !subdirs;
    Array.iter (fun entry ->
      if not (String.length entry > 0 && entry.[0] = '.') &&
         entry <> "build" && entry <> "priv" then
        let full = Filename.concat base_dir entry in
        if Sys.file_exists full && Sys.is_directory full then
          subdirs := walk_dirs full !subdirs
    ) entries;
    !subdirs

let read_file_bytes path =
  if Sys.file_exists path then
    let ic = open_in_bin path in
    let len = in_channel_length ic in
    let buf = Bytes.create len in
    really_input ic buf 0 len;
    close_in ic;
    Some (Bytes.to_string buf)
  else None

let write_file_bytes path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let sync_ui_file rel =
  let u_full = Filename.concat uos_gleam_src rel in
  let c_full = Filename.concat c3i_gleam_src rel in
  match read_file_bytes u_full, read_file_bytes c_full with
  | Some u_bytes, Some c_bytes when u_bytes <> c_bytes ->
      let u_stat = Unix.stat u_full in
      let c_stat = Unix.stat c_full in
      if u_stat.st_mtime > c_stat.st_mtime then (
        write_file_bytes c_full u_bytes;
        Printf.printf "[OCAML-WATCHER] [SYNC] uos -> c3i: %s\n%!" rel
      ) else (
        write_file_bytes u_full c_bytes;
        Printf.printf "[OCAML-WATCHER] [SYNC] c3i -> uos: %s\n%!" rel
      )
  | _ -> ()

let sync_directories () =
  let sync_targets = [
    "hot_reload_ffi.erl";
    "cepaf_gleam/ui/lustre";
    "cepaf_gleam/ui/wisp";
    "cepaf_gleam/ui/web";
    "cepaf_gleam/ui/tui";
  ] in
  List.iter (fun target ->
    let u_path = Filename.concat uos_gleam_src target in
    if Sys.file_exists u_path && not (Sys.is_directory u_path) then
      sync_ui_file target
    else if Sys.file_exists u_path && Sys.is_directory u_path then
      let entries = Sys.readdir u_path in
      Array.iter (fun e ->
        if has_matching_ext e then
          sync_ui_file (Filename.concat target e)
      ) entries
  ) sync_targets

let http_get_reload port =
  let t0 = Unix.gettimeofday () in
  try
    let s = socket PF_INET SOCK_STREAM 0 in
    let inet_addr = inet_addr_of_string "127.0.0.1" in
    connect s (ADDR_INET (inet_addr, port));
    let req = Printf.sprintf "GET /api/v1/reload HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\nUser-Agent: c3i-ocaml-watcher/1.0\r\n\r\n" port in
    let _ = send s (Bytes.of_string req) 0 (String.length req) [] in
    let buf = Bytes.create 4096 in
    let n = recv s buf 0 (Bytes.length buf) [] in
    close s;
    let resp = Bytes.sub_string buf 0 n in
    let elapsed_ms = (Unix.gettimeofday () -. t0) *. 1000.0 in
    let body =
      try
        if String.sub resp (String.length resp - 4) 4 = "\r\n\r\n" then resp
        else
          let rec find_body i =
            if i + 4 <= String.length resp && String.sub resp i 4 = "\r\n\r\n" then
              String.sub resp (i + 4) (String.length resp - i - 4)
            else if i + 1 < String.length resp then find_body (i + 1)
            else resp
          in find_body 0
      with _ -> resp
    in
    Printf.printf "[OCAML-WATCHER] [HOT-RELOAD] ✓ OK in %.1fms: %s\n%!" elapsed_ms (String.trim body);
    true
  with exn ->
    Printf.printf "[OCAML-WATCHER] [HOT-RELOAD WARNING] Could not ping 127.0.0.1:%d: %s\n%!" port (Printexc.to_string exn);
    false

let run_build () =
  let t0 = Unix.gettimeofday () in
  let cmd = Printf.sprintf "cd %s && gleam build 2>&1" c3i_gleam_dir in
  let code = Sys.command cmd in
  let elapsed_ms = (Unix.gettimeofday () -. t0) *. 1000.0 in
  if code = 0 then (
    Printf.printf "[OCAML-WATCHER] [BUILD] ✓ gleam build succeeded in %.1fms (cepaf_gleam)\n%!" elapsed_ms;
    true
  ) else (
    Printf.printf "[OCAML-WATCHER] [BUILD ERROR] gleam build exited with code %d\n%!" code;
    false
  )

let build_and_reload port =
  sync_directories ();
  if run_build () then (
    let _ = http_get_reload port in
    ()
  )

let main () =
  let once_mode = ref false in
  let port = ref 4100 in
  let debounce_ms = ref 300 in

  let speclist = [
    ("--once", Arg.Set once_mode, "Run a single compile & reload cycle, then exit");
    ("--port", Arg.Set_int port, "Target Gleam HTTP server port (default: 4100)");
    ("-p", Arg.Set_int port, "Target Gleam HTTP server port (default: 4100)");
    ("--debounce", Arg.Set_int debounce_ms, "Debounce delay in milliseconds (default: 300)");
  ] in
  Arg.parse speclist (fun _ -> ()) "c3i_page_watcher: Native OCaml Dynamic Page Watcher & Hot-Reloader";

  Printf.printf "═══════════════════════════════════════════════════════════════════════\n%!";
  Printf.printf "  C3I / UOS Native OCaml Dynamic Page Watcher & Hot-Reloader\n%!";
  Printf.printf "  अविनाशि तु तद्विद्धि येन सर्वमिदं ततम् (Gita 2.17)\n%!";
  Printf.printf "  Language: Pure Native OCaml 5.5 + Linux Inotify (0 Node.js, 0 Python)\n%!";
  Printf.printf "  Target Server: http://127.0.0.1:%d\n%!" !port;
  Printf.printf "═══════════════════════════════════════════════════════════════════════\n%!";

  if !once_mode then (
    Printf.printf "[OCAML-WATCHER] [ONCE] Executing immediate build & reload...\n%!";
    build_and_reload !port;
    exit 0
  );

  Sys.set_signal Sys.sigint (Sys.Signal_handle handle_signal);
  Sys.set_signal Sys.sigterm (Sys.Signal_handle handle_signal);

  let ifd = inotify_init () in
  let watched_dirs = walk_dirs c3i_gleam_src [] @ walk_dirs uos_gleam_src [] in
  let watch_count = ref 0 in
  List.iter (fun d ->
    try
      let wd = inotify_add_watch ifd d watch_mask in
      if wd >= 0 then incr watch_count
    with _ -> ()
  ) watched_dirs;

  Printf.printf "[OCAML-WATCHER] Inotify kernel watcher armed: %d directories watched across c3i and uos\n%!" !watch_count;

  let inotify_descr = Obj.magic ifd in
  let debounce_sec = float_of_int !debounce_ms /. 1000.0 in
  let pending_events = ref false in
  let last_event_t = ref 0.0 in

  while !running do
    let r, _, _ = Unix.select [inotify_descr] [] [] 0.1 in
    if r <> [] then (
      let names = inotify_read_names ifd in
      let matching = List.filter has_matching_ext names in
      if matching <> [] then (
        pending_events := true;
        last_event_t := Unix.gettimeofday ();
        List.iter (fun name ->
          Printf.printf "[OCAML-WATCHER] [EVENT] File changed: %s\n%!" name
        ) matching
      )
    );

    if !pending_events && (Unix.gettimeofday () -. !last_event_t >= debounce_sec) then (
      pending_events := false;
      Printf.printf "\n[OCAML-WATCHER] Debounce window elapsed (%.0fms). Triggering build & reload...\n%!" (debounce_sec *. 1000.0);
      build_and_reload !port
    )
  done;

  Unix.close inotify_descr;
  Printf.printf "[OCAML-WATCHER] Stopped.\n%!"

let () = main ()
