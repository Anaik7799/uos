(* Static import graph over the frozen Hermes reference. Reuses Hermes_analysis
   for the file list, extracts imports lexically (same honest-and-coarse style as
   Hermes_analysis's line/def counting -- no real parser), and reports which
   capability anchors are imported (referenced) versus orphaned -- the zigvm
   orphan/reachability framing. *)

type edge = { source : string; target : string }
type summary = { module_count : int; edges : edge list; internal_edge_count : int }

let has_suffix ~suffix value =
  String.length value >= String.length suffix
  && String.sub value (String.length value - String.length suffix) (String.length suffix)
     = suffix

let starts_with ~prefix value =
  String.length value >= String.length prefix
  && String.sub value 0 (String.length prefix) = prefix

let index_of ~needle hay =
  let hl = String.length hay and nl = String.length needle in
  let rec loop i = if i + nl > hl then None else if String.sub hay i nl = needle then Some i else loop (i + 1) in
  loop 0

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () -> Some (really_input_string channel (in_channel_length channel)))
  with Sys_error _ | End_of_file -> None

let module_of_path path =
  let no_ext =
    if has_suffix ~suffix:".py" path then String.sub path 0 (String.length path - 3) else path
  in
  let parts = String.split_on_char '/' no_ext in
  let parts = match List.rev parts with "__init__" :: rest -> List.rev rest | _ -> parts in
  String.concat "." parts

let imports_of_content content =
  String.split_on_char '\n' content
  |> List.concat_map (fun line ->
         let t = String.trim line in
         if starts_with ~prefix:"from " t then
           match index_of ~needle:" import " t with
           | Some i ->
               let x = String.trim (String.sub t 5 (i - 5)) in
               if x = "" then [] else [ x ]
           | None -> []
         else if starts_with ~prefix:"import " t then
           let rest = String.sub t 7 (String.length t - 7) in
           String.split_on_char ',' rest
           |> List.filter_map (fun token ->
                  let token = String.trim token in
                  let token =
                    match index_of ~needle:" as " token with
                    | Some j -> String.sub token 0 j
                    | None -> token
                  in
                  let name =
                    match String.index_opt token ' ' with
                    | Some k -> String.sub token 0 k
                    | None -> token
                  in
                  let name = String.trim name in
                  if name = "" then None else Some name)
         else [])

let analyze ~root =
  let base = Hermes_analysis.analyze ~root in
  let module_set =
    base.Hermes_analysis.modules
    |> List.map (fun (m : Hermes_analysis.module_stat) -> module_of_path m.Hermes_analysis.path)
    |> List.sort_uniq compare
  in
  let edges =
    base.Hermes_analysis.modules
    |> List.concat_map (fun (m : Hermes_analysis.module_stat) ->
           let source = module_of_path m.Hermes_analysis.path in
           match read_file (Filename.concat root m.Hermes_analysis.path) with
           | None -> []
           | Some content ->
               List.map (fun target -> { source; target }) (imports_of_content content))
    |> List.sort_uniq compare
  in
  let is_internal target =
    List.mem target module_set
    || List.exists (fun m -> starts_with ~prefix:(target ^ ".") m) module_set
  in
  { module_count = List.length module_set;
    edges;
    internal_edge_count = List.length (List.filter (fun edge -> is_internal edge.target) edges) }

type anchor_status = { anchor : string; module_name : string; referenced : bool }

let anchor_coverage summary ~anchors =
  let targets = List.sort_uniq compare (List.map (fun edge -> edge.target) summary.edges) in
  let is_target m = List.mem m targets in
  let parent m = match String.rindex_opt m '.' with Some i -> Some (String.sub m 0 i) | None -> None in
  List.map
    (fun anchor ->
      let module_name = module_of_path anchor in
      let referenced =
        is_target module_name || (match parent module_name with Some p -> is_target p | None -> false)
      in
      { anchor; module_name; referenced })
    anchors

let describe summary =
  Printf.sprintf "%d modules, %d import edges (%d internal)" summary.module_count
    (List.length summary.edges) summary.internal_edge_count
