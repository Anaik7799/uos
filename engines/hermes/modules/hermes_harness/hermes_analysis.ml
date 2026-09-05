(* Static analysis of the frozen Hermes reference: read-only, lexical structural
   metrics over its Python source. The static counterpart to Reference_capture
   (which runs the reference); together they let the harness reason about the
   surface it must reproduce both statically and at runtime. Lexical, not a full
   parse -- honest and coarse, a foundation the dashboard reports on. *)

type module_stat = { path : string; lines : int; defs : int; classes : int }

type summary = {
  files : int;
  lines : int;
  defs : int;
  classes : int;
  modules : module_stat list;
}

let skip_dirs = [ "__pycache__"; ".git" ]

let has_suffix ~suffix value =
  String.length value >= String.length suffix
  && String.sub value (String.length value - String.length suffix) (String.length suffix)
     = suffix

let starts_with ~prefix value =
  String.length value >= String.length prefix
  && String.sub value 0 (String.length prefix) = prefix

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () -> Some (really_input_string channel (in_channel_length channel)))
  with Sys_error _ | End_of_file -> None

(* Lines counted by newline; a def/async def/class at the start of a trimmed line
   is a definition/class. Coarse on purpose: no attempt to parse decorators,
   multi-line signatures, or nested strings. *)
let analyze_content content =
  let lines = ref 0 and defs = ref 0 and classes = ref 0 in
  String.iter (fun c -> if c = '\n' then incr lines) content;
  List.iter
    (fun line ->
      let trimmed = String.trim line in
      if starts_with ~prefix:"def " trimmed || starts_with ~prefix:"async def " trimmed then
        incr defs
      else if starts_with ~prefix:"class " trimmed then incr classes)
    (String.split_on_char '\n' content);
  (!lines, !defs, !classes)

let rec walk ~root relative accumulator =
  let absolute = if relative = "" then root else Filename.concat root relative in
  match Sys.readdir absolute with
  | exception Sys_error _ -> accumulator
  | entries ->
      Array.sort String.compare entries;
      Array.fold_left
        (fun accumulator name ->
          let child = if relative = "" then name else relative ^ "/" ^ name in
          let child_absolute = Filename.concat root child in
          if (try Sys.is_directory child_absolute with Sys_error _ -> false) then
            if List.mem name skip_dirs then accumulator else walk ~root child accumulator
          else if has_suffix ~suffix:".py" name then
            match read_file child_absolute with
            | None -> accumulator
            | Some content ->
                let lines, defs, classes = analyze_content content in
                { path = child; lines; defs; classes } :: accumulator
          else accumulator)
        accumulator entries

let analyze ~root =
  let modules =
    walk ~root "" [] |> List.sort (fun a b -> String.compare a.path b.path)
  in
  let sum select = List.fold_left (fun total m -> total + select m) 0 modules in
  { files = List.length modules;
    lines = sum (fun m -> m.lines);
    defs = sum (fun m -> m.defs);
    classes = sum (fun m -> m.classes);
    modules }

let describe summary =
  Printf.sprintf "%d files, %d lines, %d defs, %d classes" summary.files summary.lines
    summary.defs summary.classes
