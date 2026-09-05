(* SHA-256 as a DECLARED ORACLE (sha256sum), self-contained in the wiki
   folder so wiki_baseline carries no harness dependency. The harness's
   Inventory declares the same oracle for its own tree — two systems, one
   external tool, each declaring it at its own boundary (R13 shape). *)

let write_file path value =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc value)

let sha256_file path =
  let input = Unix.open_process_args_in "sha256sum" [| "sha256sum"; path |] in
  Fun.protect
    ~finally:(fun () -> ignore (Unix.close_process_in input))
    (fun () ->
      let line = input_line input in
      if String.length line < 64 then Error ("invalid sha256 output for " ^ path)
      else Ok (String.sub line 0 64))

let sha256 value =
  let path = Filename.temp_file "hermes-wiki-digest-" ".txt" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      write_file path value;
      match sha256_file path with Ok d -> d | Error m -> failwith m)
