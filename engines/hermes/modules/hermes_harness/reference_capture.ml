(* Capture frozen-reference traces into digest-pinned fixtures.

   The harness owns this end to end. It chooses the interpreter, points it at
   the frozen snapshot, imposes a timeout, and validates everything that comes
   back; the Python adapter it drives makes no decisions and holds no
   expectations. Every judgement about what a trace means stays in OCaml.

   Pinning is what makes recorded traces as good as live ones. The reference is
   frozen, so its behaviour for a given scenario cannot change; a fixture
   records the snapshot digest it was captured under, and a capture taken under
   a different snapshot is a different fixture rather than a silent overwrite.

   Fail-closed at every step. A missing interpreter, a missing adapter, a
   timeout, a non-zero exit, unreadable output, or an adapter-reported error all
   produce an explicit Error. Nothing is defaulted, and an absent capture is
   never treated as a passing one. *)

type scenario = {
  id : string;
  model : string;
  messages : Yojson.Safe.t list;
  tools : Yojson.Safe.t option;
  params : (string * Yojson.Safe.t) list;
}

type capture = {
  scenario_id : string;
  snapshot_digest : string;
  reference_revision : string;
  trace : Yojson.Safe.t;
  (* Digest of the *normalized* trace: what a comparison actually rests on. *)
  normalized_digest : string;
  normalization : string;
}

type failure =
  | Interpreter_missing of string
  | Adapter_missing of string
  | Reference_missing of string
  | Timed_out
  | Exited of int * string
  | Unreadable of string
  | Reference_error of string

let describe = function
  | Interpreter_missing path -> "reference interpreter not found: " ^ path
  | Adapter_missing path -> "reference adapter not found: " ^ path
  | Reference_missing path -> "frozen reference not found: " ^ path
  | Timed_out -> "reference capture timed out"
  | Exited (code, output) ->
      Printf.sprintf "reference adapter exited %d: %s" code output
  | Unreadable reason -> "unreadable adapter output: " ^ reason
  | Reference_error reason -> "reference reported: " ^ reason

(* The adapter is selectable so a second capability (response decoding) can use
   its own faithful driver without disturbing the request-shaping path. Default
   preserves the original behaviour. *)
let adapter_path ?(basename = "build_kwargs_adapter.py") root =
  Filename.concat root ("modules/hermes_harness/reference_adapter/" ^ basename)

(* The interpreter is provisioned outside the repository, so it is named
   explicitly rather than discovered: a capture must not silently switch
   interpreters between runs. *)
let interpreter_path root =
  match Sys.getenv_opt "HERMES_REFERENCE_PYTHON" with
  | Some value when String.trim value <> "" -> String.trim value
  | _ -> Filename.concat root "state/reference_env/bin/python3"

let scenario_to_json scenario =
  `Assoc
    ([ ("model", `String scenario.model); ("messages", `List scenario.messages) ]
    @ (match scenario.tools with None -> [] | Some tools -> [ ("tools", tools) ])
    @ [ ("params", `Assoc scenario.params) ])

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun name -> remove_tree (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

let temp_directory () =
  let path = Filename.temp_file "hermes-reference-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let sha256 value =
  let path = Filename.temp_file "hermes-digest-" ".txt" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      write_file path value;
      match Inventory.sha256_file path with
      | Ok digest -> digest
      | Error message -> failwith message)

(* Wait with a deadline. A reference that hangs must not hang the harness, and
   the child is killed rather than left orphaned. *)
let wait_with_timeout pid ~seconds =
  let deadline = Unix.gettimeofday () +. seconds in
  let rec loop () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
        if Unix.gettimeofday () > deadline then begin
          (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
          ignore (try Unix.waitpid [] pid with Unix.Unix_error _ -> (0, Unix.WEXITED 0));
          None
        end
        else begin
          ignore (Unix.select [] [] [] 0.02);
          loop ()
        end
    | _, status -> Some status
    | exception Unix.Unix_error _ -> Some (Unix.WEXITED 255)
  in
  loop ()

let run_adapter ~root ~interpreter ~adapter ~reference_root ~scenario =
  let staging = temp_directory () in
  Fun.protect
    ~finally:(fun () -> remove_tree staging)
    (fun () ->
      let input_path = Filename.concat staging "scenario.json" in
      let output_path = Filename.concat staging "trace.json" in
      write_file input_path (Yojson.Safe.to_string (scenario_to_json scenario));
      let input = Unix.openfile input_path [ Unix.O_RDONLY ] 0o400 in
      let output =
        Unix.openfile output_path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600
      in
      (* The frozen root must WIN, not merely appear: with duplicate entries in
         execve's environment, getenv takes the first occurrence, so appending
         our PYTHONPATH after an inherited one silently imports whatever the
         caller's environment pointed at -- a trace from an unpinned reference
         recorded under the frozen digest (hazard HZ-CAP-01, found by the fable
         design review and reproduced with a probe). Inherited PYTHONPATH and
         PYTHONSTARTUP are therefore stripped, never shadowed. *)
      let environment =
        let inherited =
          Array.to_list (Unix.environment ())
          |> List.filter (fun binding ->
                 not
                   (List.exists
                      (fun prefix -> String.starts_with ~prefix binding)
                      [ "PYTHONPATH="; "PYTHONSTARTUP="; "PYTHONHOME=" ]))
        in
        Array.of_list
          (inherited
          @ [ "PYTHONPATH=" ^ reference_root; "PYTHONDONTWRITEBYTECODE=1" ])
      in
      let pid =
        Unix.create_process_env interpreter [| interpreter; adapter |] environment
          input output output
      in
      Unix.close input;
      Unix.close output;
      ignore root;
      match wait_with_timeout pid ~seconds:120.0 with
      | None -> Error Timed_out
      | Some status ->
          let raw = try read_file output_path with Sys_error _ -> "" in
          let code =
            match status with
            | Unix.WEXITED code -> code
            | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal
          in
          if code <> 0 then Error (Exited (code, String.trim raw))
          else
            match Yojson.Safe.from_string raw with
            | exception Yojson.Json_error message -> Error (Unreadable message)
            | `Assoc fields -> (
                match List.assoc_opt "error" fields with
                | Some (`String reason) -> Error (Reference_error reason)
                | Some other -> Error (Reference_error (Yojson.Safe.to_string other))
                | None -> (
                    match List.assoc_opt "trace" fields with
                    | Some trace -> Ok trace
                    | None -> Error (Unreadable "no trace field")))
            | _ -> Error (Unreadable "adapter output was not an object"))

let capture ?adapter_basename ~root ~snapshot_digest ~reference_revision ~normalizer scenario =
  let reference_root = Bootstrap.reference_root root in
  let interpreter = interpreter_path root in
  let adapter = adapter_path ?basename:adapter_basename root in
  if not (Sys.file_exists reference_root) then Error (Reference_missing reference_root)
  else if not (Sys.file_exists adapter) then Error (Adapter_missing adapter)
  else if not (Sys.file_exists interpreter) then Error (Interpreter_missing interpreter)
  else
    match run_adapter ~root ~interpreter ~adapter ~reference_root ~scenario with
    | Error _ as error -> error
    | Ok trace ->
        let normalized = Parity_normalizer.render normalizer trace in
        Ok
          { scenario_id = scenario.id; snapshot_digest; reference_revision; trace;
            normalized_digest = sha256 normalized;
            normalization = Parity_normalizer.describe normalizer }

(* A fixture is keyed by scenario and snapshot: a capture under a different
   snapshot is a different fixture, never a silent overwrite of the old one. *)
let fixture_path ~root scenario_id ~snapshot_digest =
  let short = if String.length snapshot_digest >= 12 then String.sub snapshot_digest 0 12 else snapshot_digest in
  Filename.concat root
    (Printf.sprintf "modules/hermes_harness/fixtures/reference_traces/%s.%s.json" scenario_id short)

let to_json capture =
  `Assoc
    [ ("scenario_id", `String capture.scenario_id);
      ("snapshot_digest", `String capture.snapshot_digest);
      ("reference_revision", `String capture.reference_revision);
      ("normalization", `String capture.normalization);
      ("normalized_digest", `String capture.normalized_digest);
      ("trace", capture.trace) ]

let of_json (value : Yojson.Safe.t) =
  match value with
  | `Assoc fields -> (
      let text name =
        match List.assoc_opt name fields with Some (`String value) -> Some value | _ -> None
      in
      match
        ( text "scenario_id", text "snapshot_digest", text "reference_revision",
          text "normalization", text "normalized_digest",
          List.assoc_opt "trace" fields )
      with
      | Some scenario_id, Some snapshot_digest, Some reference_revision,
        Some normalization, Some normalized_digest, Some trace ->
          Ok { scenario_id; snapshot_digest; reference_revision; trace;
               normalized_digest; normalization }
      | _ -> Error (Unreadable "fixture is missing required fields"))
  | _ -> Error (Unreadable "fixture was not an object")

(* HZ-FIX-03. A trace whose payload is the stub template is well-formed,
   correctly digested and from the right snapshot -- valid in every respect the
   other capture checks test -- and reproduced by ANY implementation, including
   one that implements nothing. Pinning it creates an artifact that looks like
   evidence forever after.

   The check belongs HERE, at the moment a trace becomes a pinned artifact,
   rather than only downstream at record time. The 88 stub fixtures of
   2026-08-09 exist precisely because save accepted them: by the time the
   downstream guard sees one, it is already committed, already counted by
   Parity_dashboard.count_fixtures, and already named for a capability. Both
   checks are kept -- this one stops the artifact, the record guard stops the
   receipt. *)
let stub_payload_prefix = "stub for "

let is_stub_payload (json : Yojson.Safe.t) =
  let starts_with_prefix text =
    let n = String.length stub_payload_prefix in
    String.length text >= n && String.sub text 0 n = stub_payload_prefix
  in
  let rec walk (node : Yojson.Safe.t) =
    match node with
    | `String text -> starts_with_prefix text
    | `List items -> List.exists walk items
    | `Assoc fields -> List.exists (fun (_, value) -> walk value) fields
    | _ -> false
  in
  walk json

let save ~root capture =
  if is_stub_payload capture.trace then
    Error
      (Printf.sprintf
         "HZ-FIX-03: refusing to pin %s — its payload begins %S, so it exercises \
          no part of the capability it is named for and any implementation \
          reproduces it. Author a scenario that FAILS against a deliberately \
          wrong candidate, then capture that."
         capture.scenario_id stub_payload_prefix)
  else
  let path = fixture_path ~root capture.scenario_id ~snapshot_digest:capture.snapshot_digest in
  let directory = Filename.dirname path in
  let rec ensure path =
    if not (Sys.file_exists path) then begin
      ensure (Filename.dirname path);
      try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    end
  in
  ensure directory;
  write_file path (Yojson.Safe.pretty_to_string (to_json capture) ^ "\n");
  Ok path

(* Loading re-derives the digest instead of trusting the one on disk: a fixture
   whose recorded digest does not match its own trace has been edited, and an
   edited reference trace is worse than none. *)
let load ~root ~normalizer scenario_id ~snapshot_digest =
  let path = fixture_path ~root scenario_id ~snapshot_digest in
  if not (Sys.file_exists path) then Error (Unreadable ("no fixture at " ^ path))
  else
    match Yojson.Safe.from_string (read_file path) with
    | exception Yojson.Json_error message -> Error (Unreadable message)
    | value -> (
        match of_json value with
        | Error _ as error -> error
        | Ok capture ->
            let recomputed = sha256 (Parity_normalizer.render normalizer capture.trace) in
            if String.equal recomputed capture.normalized_digest then Ok capture
            else
              Error
                (Unreadable
                   (Printf.sprintf
                      "fixture digest mismatch for %s: recorded %s, recomputed %s"
                      scenario_id capture.normalized_digest recomputed)))
