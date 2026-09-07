#!/usr/bin/env -S ocaml
#use "topfind";;
#require "digestif.c,yojson";;
#use "./tests/acceptance/process_supervisor.ml";;

(** Fixed-profile, read-only Solo5 toolchain acceptance. Reuses the existing
    monotonic, byte-bounded UOS process supervisor. Results describe this host
    and these artifact bytes; they grant no application or service admission. *)

let release = "0.13.0"
let root = "/home/an/NAS-setup/uos"
let prefix = root ^ "/var/toolchains/solo5/" ^ release
let source = root ^ "/var/quarantine/solo5-" ^ release ^ "/solo5-v" ^ release
let limits = { timeout_ms = 12_000; stdout_limit = 65_536;
  stderr_limit = 65_536; term_grace_ms = 100 }

let sha256 text = Digestif.SHA256.(to_hex (digest_string text))
let file_binding path =
  let maximum = 32 * 1024 * 1024 in
  let info = Unix.lstat path in
  if info.Unix.st_kind <> Unix.S_REG || info.Unix.st_size > maximum
  then failwith ("not a bounded regular artifact: " ^ path);
  let descriptor = Unix.openfile path [Unix.O_RDONLY; Unix.O_CLOEXEC; Unix.O_NONBLOCK] 0 in
  let bytes = Fun.protect ~finally:(fun () -> Unix.close descriptor) (fun () ->
    let same a b = a.Unix.st_dev = b.Unix.st_dev && a.Unix.st_ino = b.Unix.st_ino
      && a.Unix.st_kind = b.Unix.st_kind && a.Unix.st_size = b.Unix.st_size
      && a.Unix.st_mtime = b.Unix.st_mtime && a.Unix.st_ctime = b.Unix.st_ctime in
    if not (same info (Unix.fstat descriptor)) then failwith ("artifact changed: " ^ path);
    let buffer = Buffer.create (min maximum 65_536) and chunk = Bytes.create 65_536 in
    let rec read () =
      let remaining = maximum - Buffer.length buffer in
      match Unix.read descriptor chunk 0 (min (Bytes.length chunk) (remaining + 1)) with
      | 0 -> ()
      | count when count > remaining -> failwith ("artifact grew beyond quota: " ^ path)
      | count -> Buffer.add_subbytes buffer chunk 0 count; read () in
    read ();
    if not (same info (Unix.fstat descriptor) && same info (Unix.lstat path))
    then failwith ("artifact changed during read: " ^ path);
    Buffer.contents buffer) in
  `Assoc ["path", `String path; "size_bytes", `Int (String.length bytes);
    "sha256", `String (sha256 bytes)]

let lines text = String.split_on_char '\n' text |> List.map String.trim
let has text needle = List.mem needle (lines text)
let completed (result : process_result) = result.children_reaped
  && not result.stdout_truncated && not result.stderr_truncated

type profile = Hello | Timer | Stack_protection | Wrong_argument
let profile_name = function Hello -> "hello" | Timer -> "time"
  | Stack_protection -> "ssp" | Wrong_argument -> "hello_wrong_argument"
let test_name = function Hello | Wrong_argument -> "hello"
  | Timer -> "time" | Stack_protection -> "ssp"

let success exit output (result : process_result) =
  completed result && result.termination = Exited exit
  && has output "Solo5: Bindings version v0.13.0"
  && has output "SUCCESS"
  && has output "Solo5: solo5_exit(0) called"
  && not (List.exists (fun line -> String.starts_with ~prefix:"Solo5: ABORT:" line) (lines output))

let check_profile target profile result =
  let output = result.stdout ^ "\n" ^ result.stderr in
  let expected_exit = if target = "virtio" then 83 else 0 in
  match profile with
  | Hello | Timer -> success expected_exit output result
  | Stack_protection -> completed result
      && result.termination = Exited (if target = "virtio" then 83 else 255)
      && has output "Solo5: Bindings version v0.13.0"
      && has output "**** Solo5 standalone test_ssp ****"
      && has output "Solo5: ABORT: Stack corruption detected"
      && not (has output "SUCCESS")
  | Wrong_argument -> completed result && result.termination = Exited expected_exit
      && has output "**** Solo5 standalone test_hello ****"
      && not (has output "SUCCESS") && not (success expected_exit output result)

let termination_json = function Exited n -> `Assoc ["exit_code", `Int n]
  | Signaled n -> `Assoc ["signal", `Int (Sys.signal_to_int n)]
  | Timed_out -> `String "timeout" | Output_limit -> `String "output_limit"

let observe target profile =
  let name = test_name profile in
  let guest = source ^ "/tests/test_" ^ name ^ "/test_" ^ name ^ "." ^ target in
  let binary = prefix ^ "/bin/solo5-" ^ (if target = "virtio" then "virtio-run" else target) in
  let args = match profile with Hello -> ["Hello_Solo5"]
    | Wrong_argument -> ["Deliberately_Wrong_Argument"] | _ -> [] in
  let argv = if target = "virtio" then [binary; "-H"; "kvm"; "-m"; "64"; guest; "--"] @ args
    else [binary; "--mem=64"; guest] @ args in
  let bound_paths = [binary; guest] @
    (if target = "virtio" then ["/usr/bin/qemu-system-x86_64"] else []) in
  let before = List.map file_binding bound_paths in
  let result = run_bounded limits argv in
  let unchanged = before = List.map file_binding bound_paths in
  let passed = unchanged && check_profile target profile result in
  let row = `Assoc ["target", `String target; "case", `String (profile_name profile);
    "argv", `List (List.map (fun s -> `String s) argv);
    "artifacts", `List before; "artifacts_unchanged", `Bool unchanged;
    "termination", termination_json result.termination;
    "duration_ms", `Float result.duration_ms; "children_reaped", `Bool result.children_reaped;
    "stdout_truncated", `Bool result.stdout_truncated; "stderr_truncated", `Bool result.stderr_truncated;
    "stdout", `String result.stdout; "stderr", `String result.stderr;
    "assertion_passed", `Bool passed;
    "guest_success", `Bool (success (if target = "virtio" then 83 else 0)
        (result.stdout ^ "\n" ^ result.stderr) result)] in
  Printf.eprintf "%s/%s: %s (%.1f ms)\n%!" target (profile_name profile)
    (if passed then "PASS" else "FAIL") result.duration_ms;
  passed, row

let now_utc () =
  let t = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec

let main () =
  (* The upstream VirtIO launcher invokes QEMU and coreutils by basename.
     Restrict resolution for every child to host system tools. *)
  Unix.putenv "PATH" "/usr/bin:/bin";
  let started = now_utc () in
  let profiles = [Hello; Timer; Stack_protection; Wrong_argument] in
  let observations = List.concat_map (fun target -> List.map (observe target) profiles)
    ["hvt"; "spt"; "virtio"] in
  let passed = List.for_all fst observations in
  let data = `Assoc ["schema", `String "uos.solo5-toolchain.acceptance.v1";
    "version", `String release; "host", `String (Unix.gethostname ());
    "boot_id", `String (String.trim (In_channel.with_open_text "/proc/sys/kernel/random/boot_id" In_channel.input_all));
    "started_at", `String started; "completed_at", `String (now_utc ());
    "supervisor", file_binding "tests/acceptance/process_supervisor.ml";
    "checker", file_binding "tools/verification/solo5_toolchain.ml";
    "source_archive", file_binding (root ^ "/var/quarantine/solo5-" ^ release ^ "/downloads/solo5-v" ^ release ^ ".tar.gz");
    "qemu", file_binding "/usr/bin/qemu-system-x86_64";
    "child_path", `String "/usr/bin:/bin";
    "timeout_ms", `Int limits.timeout_ms; "stream_limit_bytes", `Int limits.stdout_limit;
    "cases", `List (List.map snd observations); "all_assertions_passed", `Bool passed;
    "case_count", `Int (List.length observations);
    "application_admitted", `Bool false;
    "scope", `String "Linux x86_64 on this host; no network or block-device configuration; no migration or RAM-saving claim"] in
  print_endline (Yojson.Basic.pretty_to_string data);
  if passed then 0 else 1

let () = if Filename.basename Sys.argv.(0) = "solo5_toolchain.ml" then
  try exit (main ()) with exn -> prerr_endline (Printexc.to_string exn); exit 2
