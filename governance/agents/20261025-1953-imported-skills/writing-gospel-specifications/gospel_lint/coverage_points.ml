(** Report uncovered instrumentation points from a bisect_ppx coverage file.

    [bisect-ppx-report summary] gives a percentage and [html] marks a line as
    visited when *any* point on it was hit, so neither tells you which sub-line
    branch is missing. This does: it reads the raw coverage file and prints the
    source line of every point with a zero count.

    The coverage file is whitespace-separated text:

      BISECT-COVERAGE-<v> <file-count>
        (<name-length> <name> <point-count> <offset>... <count>...)...

    Offsets are byte offsets into the source. The format is not a published
    interface, so this validates the header and every length it reads, and
    fails loudly rather than mis-reporting coverage. *)

let fail message =
  prerr_endline ("coverage_points: " ^ message);
  exit 1

(** Split on any whitespace, dropping empties. *)
let tokenize text =
  String.split_on_char ' '
    (String.map (fun c -> if c = '\n' || c = '\t' || c = '\r' then ' ' else c) text)
  |> List.filter (fun token -> token <> "")

let read_file path =
  match open_in_bin path with
  | exception Sys_error message -> fail message
  | channel ->
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () -> really_input_string channel (in_channel_length channel))

type cursor = { tokens : string array; mutable index : int }

let next cursor =
  if cursor.index >= Array.length cursor.tokens then fail "coverage file ended early";
  let token = cursor.tokens.(cursor.index) in
  cursor.index <- cursor.index + 1;
  token

let next_int cursor what =
  let token = next cursor in
  match int_of_string_opt token with
  | Some value when value >= 0 -> value
  | _ -> fail (Printf.sprintf "expected %s, found %S" what token)

(** 1-based line number of a byte offset. *)
let line_of source offset =
  let count = ref 1 in
  let bound = min offset (String.length source) in
  for index = 0 to bound - 1 do
    if source.[index] = '\n' then incr count
  done;
  !count

let lines_of source = Array.of_list (String.split_on_char '\n' source)

let report ~coverage_file ~sources =
  let text = read_file coverage_file in
  let cursor = { tokens = Array.of_list (tokenize text); index = 0 } in
  let identifier = next cursor in
  if
    String.length identifier < 16
    || String.sub identifier 0 16 <> "BISECT-COVERAGE-"
  then fail (Printf.sprintf "not a bisect coverage file (header %S)" identifier);
  let file_count = next_int cursor "file count" in
  let total_points = ref 0 and total_covered = ref 0 in
  for _ = 1 to file_count do
    let name_length = next_int cursor "name length" in
    let name = next cursor in
    if String.length name <> name_length then
      fail
        (Printf.sprintf "name %S has length %d, header said %d" name
           (String.length name) name_length);
    let point_count = next_int cursor "point count" in
    let offsets = Array.init point_count (fun _ -> next_int cursor "offset") in
    let counts = Array.init point_count (fun _ -> next_int cursor "count") in
    let covered = Array.fold_left (fun acc c -> if c > 0 then acc + 1 else acc) 0 counts in
    total_points := !total_points + point_count;
    total_covered := !total_covered + covered;
    Printf.printf "%s: %d/%d points (%.2f%%)\n" name covered point_count
      (if point_count = 0 then 100.0
       else 100.0 *. float_of_int covered /. float_of_int point_count);
    let source =
      List.find_opt (fun path -> Filename.basename path = name) sources
      |> Option.map read_file
    in
    match source with
    | None ->
        if covered < point_count then
          Printf.printf "  (source not supplied; pass %s to see the lines)\n" name
    | Some source ->
        let lines = lines_of source in
        Array.iteri
          (fun index count ->
            if count = 0 then begin
              let line = line_of source offsets.(index) in
              let text =
                if line - 1 < Array.length lines then String.trim lines.(line - 1) else "?"
              in
              Printf.printf "  uncovered line %4d: %s\n" line text
            end)
          counts
  done;
  Printf.printf "total: %d/%d points\n" !total_covered !total_points;
  if !total_covered = !total_points then 0 else 1

let () =
  match Array.to_list Sys.argv with
  | _ :: coverage_file :: sources -> exit (report ~coverage_file ~sources)
  | _ ->
      prerr_endline "usage: coverage_points FILE.coverage [SOURCE.ml ...]";
      exit 64
