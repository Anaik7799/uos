(* Runs `gospel check` against a temporary mirror of a contract interface.

   Gospel writes a sidecar next to its input, so an in-tree interface is never
   checked in place. When no `gospel` binary is on PATH the verdict is
   Unavailable — an honest observation, never a pass.

   Gospel is patched to build on this project's OCaml 5.5.0 switch and pinned
   there, so PATH lookup finds it directly. HERMES_GOSPEL and GOSPEL_BIN remain
   supported for the side-switch arrangement, where the switch's bin directory
   must NOT go on PATH: it carries an ocamlc that shadows the project compiler
   and breaks dune. See the writing-gospel-specifications skill for the patch. *)

type verdict = Checked | Rejected of int | Unavailable

let verdict_string = function
  | Checked -> "checked"
  | Rejected _ -> "rejected"
  | Unavailable -> "unavailable"

(* The verifier identity distinguishes "the tool ran" from "the tool was
   absent", so both observations can coexist at one harness revision. *)
let verifier = function
  | Checked | Rejected _ -> "gospel"
  | Unavailable -> "gospel-unavailable"

let configured_binary () =
  match Sys.getenv_opt "HERMES_GOSPEL" with
  | Some path when String.trim path <> "" ->
      (try Unix.access path [ Unix.X_OK ]; Some path with Unix.Unix_error _ -> None)
  | _ -> None

let path_binary name =
  match Sys.getenv_opt "PATH" with
  | None -> None
  | Some path ->
      String.split_on_char ':' path
      |> List.find_map (fun directory ->
             let candidate = Filename.concat directory name in
             try Unix.access candidate [ Unix.X_OK ]; Some candidate
             with Unix.Unix_error _ -> None)

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then (
      Sys.readdir path |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path)
    else Sys.remove path

let temp_directory () =
  let path = Filename.temp_file "hermes-gospel-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let copy source target =
  In_channel.with_open_bin source (fun input ->
      Out_channel.with_open_bin target (fun output ->
          let buffer = Bytes.create 4096 in
          let rec loop () =
            match In_channel.input input buffer 0 (Bytes.length buffer) with
            | 0 -> ()
            | count -> Out_channel.output output buffer 0 count; loop ()
          in
          loop ()))

(* Directories offered to gospel as a load path.

   hermes_harness itself comes first: a contract that mentions a sibling
   harness module resolves against that module's real interface, which is
   always preferable to a stub. gospel_stubs is the fallback for modules with
   no reachable interface -- see gospel_stubs/yojson.mli for why a stub must
   stay weaker than what it stands in for. *)
let stub_directories root =
  [ Filename.concat root "modules/hermes_harness";
    Filename.concat root "modules/hermes_harness/gospel_stubs" ]

let check ?(load_path = []) ~interface () =
  if not (Sys.file_exists interface) then Error ("missing contract interface: " ^ interface)
  else
    match
      match configured_binary () with Some path -> Some path | None -> path_binary "gospel"
    with
    | None -> Ok Unavailable
    | Some gospel ->
        let stage = temp_directory () in
        Fun.protect
          ~finally:(fun () -> remove_tree stage)
          (fun () ->
            let staged = Filename.concat stage (Filename.basename interface) in
            copy interface staged;
            let null = Unix.openfile Filename.null [ Unix.O_WRONLY ] 0o600 in
            let arguments =
              Array.of_list
                ([ gospel; "check" ]
                @ List.concat_map (fun directory -> [ "-L"; directory ]) load_path
                @ [ staged ])
            in
            let pid = Unix.create_process gospel arguments Unix.stdin null null in
            Unix.close null;
            let _, status = Unix.waitpid [] pid in
            match status with
            | Unix.WEXITED 0 -> Ok Checked
            | Unix.WEXITED code -> Ok (Rejected code)
            | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> Ok (Rejected signal))
