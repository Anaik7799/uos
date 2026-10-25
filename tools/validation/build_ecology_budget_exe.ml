(* Builds the native ecology_budget.exe that telegram_budget_test_io expects at
   /home/an/NAS-setup/uos/var/recovery-runtime/test-fixtures/ecology_budget.exe,
   from the tracked script tools/ecology_budget.ml. That location is required:
   the production budget-source allowlist admits only var/releases and
   var/recovery-runtime executables. The script's toplevel directives (#!, #use,
   #require) are dropped; the packages they require are passed to ocamlfind.
   Usage: ocaml tools/validation/build_ecology_budget_exe.ml <repo_root> *)

let packages = "unix,sqlite3,yojson,mtime.clock"

let is_directive line =
  let t = String.trim line in
  String.length t > 0 && (t.[0] = '#')

let read_lines path =
  let ic = open_in_bin path in
  let rec loop acc =
    match input_line ic with
    | line -> loop (line :: acc)
    | exception End_of_file -> close_in ic; List.rev acc
  in
  loop []

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else Sys.getcwd () in
  let src = Filename.concat root "tools/ecology_budget.ml" in
  let out_dir = "/home/an/NAS-setup/uos/var/recovery-runtime/test-fixtures" in
  if not (Sys.file_exists out_dir) then Sys.mkdir out_dir 0o755;
  let work = Filename.temp_dir "ecology_budget" "" in
  let ml = Filename.concat work "ecology_budget.ml" in
  let lines = read_lines src in
  let rec drop_header = function
    | l :: rest when is_directive l -> drop_header rest
    | rest -> rest
  in
  let oc = open_out_bin ml in
  List.iter (fun l -> output_string oc l; output_char oc '\n') (drop_header lines);
  close_out oc;
  let exe = Filename.concat out_dir "ecology_budget.exe" in
  let cmd =
    Printf.sprintf "cd %s && ocamlfind ocamlopt -package %s -linkpkg ecology_budget.ml -o %s"
      (Filename.quote work) packages (Filename.quote exe)
  in
  match Sys.command cmd with
  | 0 -> print_endline ("built " ^ exe)
  | code -> prerr_endline ("ocamlfind failed: " ^ string_of_int code); exit code
