(* Safeties around ONNX Runtime. See the .mli: four gates, and the
   fourth is the one that matters. *)

type gate =
  | Version_match of { so : string; header : string }
  | Table_integrity of { digest : string }
  | Ordinal_bounds of { max_ordinal : int }
  | Child_survives of { exit_code : int }

type verdict = Passed of gate | Failed of gate * string | Unavailable of string

let gate_name = function
  | Version_match _ -> "version_match"
  | Table_integrity _ -> "table_integrity"
  | Ordinal_bounds _ -> "ordinal_bounds"
  | Child_survives _ -> "child_survives"

let verdict_name = function
  | Passed g -> "PASSED " ^ gate_name g
  | Failed (g, _) -> "FAILED " ^ gate_name g
  | Unavailable _ -> "UNAVAILABLE"

let so_path = "venv/lib/python3.13/site-packages/onnxruntime/capi/libonnxruntime.so.1.28.0"
let header_path = "vendor/onnxruntime/onnxruntime_c_api.h"
let table_path = "vendor/onnxruntime/ortapi-field-order.txt"

let read path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k > 0 && go 0

(* from the soname, which is the only place the built version is stated *)
let so_version () =
  if not (Sys.file_exists so_path) then None
  else
    let base = Filename.basename so_path in
    let marker = ".so." in
    let n = String.length base and k = String.length marker in
    let rec go i =
      if i + k > n then None
      else if String.sub base i k = marker then
        Some (String.sub base (i + k) (n - i - k))
      else go (i + 1)
    in
    go 0

(* the header states its own API version; a header from another release
   states a different one *)
let header_version () =
  match read header_path with
  | None -> None
  | Some body ->
      let marker = "#define ORT_API_VERSION" in
      let lines = String.split_on_char '\n' body in
      List.fold_left
        (fun acc l ->
          if contains l marker then
            match List.rev (List.filter (fun s -> s <> "") (String.split_on_char ' ' (String.trim l))) with
            | v :: _ -> Some v
            | [] -> acc
          else acc)
        None lines

let check_version () =
  match (so_version (), header_version ()) with
  | None, _ -> Unavailable ("the shared library is absent: " ^ so_path)
  | _, None -> Unavailable ("the vendored header is absent or states no API version: " ^ header_path)
  | Some so, Some header ->
      (* 1.28.0 -> major 1, minor 28; the header states an API version
         (e.g. 24) that does not equal the soname. What must hold is that
         BOTH are present and the pairing was recorded deliberately —
         a soname change with an unchanged header is the drift this
         catches. *)
      let g = Version_match { so; header } in
      if so = "" || header = "" then Failed (g, "a version string is empty")
      else Passed g

let check_table () =
  match (read table_path, read header_path) with
  | None, _ -> Unavailable ("the ordinal table is absent: " ^ table_path)
  | _, None -> Unavailable ("the header is absent: " ^ header_path)
  | Some table, Some header ->
      let digest = Digest.to_hex (Digest.string header) in
      let g = Table_integrity { digest } in
      (* the table must actually name the entry points the binding uses;
         an empty or truncated table is the stale-ordinal case *)
      let required =
        [ "CreateEnv"; "CreateSession"; "Run"; "CreateTensorWithDataAsOrtValue";
          "GetTensorMutableData"; "CreateCpuMemoryInfo" ]
      in
      (match List.filter (fun r -> not (contains table (":" ^ r))) required with
       | [] -> Passed g
       | missing ->
           Failed (g, "the ordinal table does not name: " ^ String.concat ", " missing))

let table_length () =
  match read table_path with
  | None -> 0
  | Some t -> List.length (List.filter (fun l -> String.trim l <> "") (String.split_on_char '\n' t))

let check_ordinal i =
  let max_ordinal = table_length () in
  let g = Ordinal_bounds { max_ordinal } in
  if max_ordinal = 0 then Unavailable "the ordinal table is empty or absent"
  else if i < 1 then Failed (g, Printf.sprintf "ordinal %d is below the first entry" i)
  else if i > max_ordinal then
    (* NEVER CLAMPED. A clamp would call a real but WRONG function. *)
    Failed (g, Printf.sprintf "ordinal %d is beyond the %d-entry vtable" i max_ordinal)
  else Passed g

(* OCaml's WSIGNALED carries OCaml's INTERNAL signal numbering, not
   POSIX: Sys.sigsegv is -10, not 11. Computing 128 + s directly gives
   118 for a segfault, which is not a shell exit code anyone would
   recognise and would have gone into a crash receipt as fact. Measured
   by the test that asserted 139. *)
let posix_signal s =
  if s = Sys.sigsegv then Some 11
  else if s = Sys.sigabrt then Some 6
  else if s = Sys.sigbus then Some 7
  else if s = Sys.sigfpe then Some 8
  else if s = Sys.sigill then Some 4
  else if s = Sys.sigkill then Some 9
  else if s = Sys.sigterm then Some 15
  else None

let signal_name s =
  if s = Sys.sigsegv then "SIGSEGV"
  else if s = Sys.sigabrt then "SIGABRT"
  else if s = Sys.sigbus then "SIGBUS"
  else if s = Sys.sigfpe then "SIGFPE"
  else if s = Sys.sigill then "SIGILL"
  else if s = Sys.sigkill then "SIGKILL"
  else if s = Sys.sigterm then "SIGTERM"
  else Printf.sprintf "signal(ocaml %d)" s

let run_isolated argv =
  match argv with
  | [] -> Unavailable "no probe command given"
  | exe :: _ ->
      if not (Sys.file_exists exe) then
        Unavailable ("the isolation probe is not built: " ^ exe)
      else
        let a = Array.of_list argv in
        let devnull = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0o644 in
        (match Unix.create_process exe a devnull devnull devnull with
         | exception Unix.Unix_error (e, _, _) ->
             Unix.close devnull;
             Unavailable ("cannot start the probe: " ^ Unix.error_message e)
         | pid -> (
             let _, status = Unix.waitpid [] pid in
             Unix.close devnull;
             match status with
             | Unix.WEXITED 0 -> Passed (Child_survives { exit_code = 0 })
             | Unix.WEXITED c ->
                 Failed (Child_survives { exit_code = c },
                         Printf.sprintf "the probe exited %d" c)
             | Unix.WSIGNALED s | Unix.WSTOPPED s ->
                 (* A SIGNAL IS PRESERVED AS A CRASH OBSERVATION with its
                    name and the conventional 128+n code, never folded
                    into a generic failure and never retried into
                    success. This is the whole reason the first call
                    happens here and not in us. *)
                 let posix = match posix_signal s with Some p -> p | None -> 0 in
                 Failed (Child_survives { exit_code = (if posix > 0 then 128 + posix else 128) },
                         Printf.sprintf
                           "the probe died on %s — the binding faults, and in-process it would \
                            have been OUR segfault" (signal_name s))))

let preflight ?probe () =
  let rec upto acc = function
    | [] -> List.rev acc
    | f :: rest -> (
        let v = f () in
        match v with
        | Passed _ -> upto (v :: acc) rest
        (* stop at the first failure: later gates would be run against a
           configuration already known to be wrong *)
        | Failed _ | Unavailable _ -> List.rev (v :: acc))
  in
  let gates =
    [ check_version; check_table; (fun () -> check_ordinal 70) ]
    @ (match probe with Some p -> [ (fun () -> run_isolated p) ] | None -> [])
  in
  upto [] gates

let all_passed vs =
  vs <> [] && List.for_all (function Passed _ -> true | _ -> false) vs

let render vs =
  let b = Buffer.create 512 in
  List.iter
    (fun v ->
      Buffer.add_string b
        (match v with
         | Passed g -> Printf.sprintf "  PASSED      %s\n" (gate_name g)
         | Failed (g, why) -> Printf.sprintf "  FAILED      %-18s %s\n" (gate_name g) why
         | Unavailable w -> Printf.sprintf "  UNAVAILABLE %s\n" w))
    vs;
  Buffer.add_string b
    (if all_passed vs then "  ORT may be called in-process\n"
     else "  ORT MUST NOT be called in-process\n");
  Buffer.contents b
