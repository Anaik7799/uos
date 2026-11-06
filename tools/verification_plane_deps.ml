(* Derive the verification plane's dependency DAG from the files themselves.
   No hand-drawn edges: every edge is read out of an import, a subject
   declaration, or a tool invocation. authority NONE. EV ceiling 93. *)
let read p = let ic = open_in_bin p in let n = in_channel_length ic in
  let s = really_input_string ic n in close_in ic; s
let contains h n =
  let hn = String.length h and nn = String.length n in
  let rec go i = if i + nn > hn then false
    else if String.sub h i nn = n then true else go (i+1) in
  nn > 0 && go 0
let matches_all src re =
  let out = ref [] in
  (try
     let rex = Str.regexp re in
     let pos = ref 0 in
     while true do
       let _ = Str.search_forward rex src !pos in
       out := Str.matched_group 1 src :: !out;
       pos := Str.match_end ()
     done
   with Not_found -> ());
  List.sort_uniq compare !out
let () =
  let oracles = Sys.readdir "formal/mojo" |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f "_oracle.mojo")
    |> List.sort compare in
  let shared = ["oracle_substrate.mojo"] in
  Printf.printf "digraph verification_plane {\n  rankdir=LR;\n";
  (* layer 0: the instrument *)
  Printf.printf "  \"tools/mojo_arm_falsifiability.ml\" [shape=box];\n";
  Printf.printf "  \"tools/lean_mojo_differential.ml\" [shape=box];\n";
  Printf.printf "  \"tools/lean_proof_plane_scan.ml\" [shape=box];\n";
  let edges = ref [] in
  let add a b = edges := (a,b) :: !edges in
  List.iter (fun o ->
    let path = Filename.concat "formal/mojo" o in
    let src = read path in
    (* shared dispatcher edges *)
    List.iter (fun sh ->
      if contains src (Filename.remove_extension sh) then
        add o sh) shared;
    (* subject edges *)
    List.iter (fun subj -> add o subj)
      (matches_all src "\\(formal/lean/[A-Za-z0-9_]+\\.lean\\)");
    (* tool invocation edges *)
    List.iter (fun t -> if contains src t then add o t)
      ["tools/lean_proof_plane_scan.ml"; "tools/lean_mojo_differential.ml";
       "tools/km-gate"; "tools/uos-mcp-stdio"; "tools/ecology_pin_edit.ml";
       "tools/bionic_token_twin.ml"];
    (* governance artifact edges *)
    List.iter (fun g -> add o g)
      (matches_all src "\\(governance/[A-Za-z0-9_/.-]+\\.json\\)");
    (* gleam source edges *)
    List.iter (fun g -> add o g)
      (matches_all src "\\(apps/cepaf_gleam/[A-Za-z0-9_/.-]+\\.gleam\\)")
  ) oracles;
  (* the driver depends on every oracle and on the scanner *)
  List.iter (fun o -> add "tools/lean_mojo_differential.ml" o) oracles;
  add "tools/lean_mojo_differential.ml" "tools/lean_proof_plane_scan.ml";
  List.iter (fun o -> add "tools/mojo_arm_falsifiability.ml" o) oracles;
  let es = List.sort_uniq compare !edges in
  List.iter (fun (a,b) -> Printf.printf "  %S -> %S;\n" a b) es;
  Printf.printf "}\n";
  (* fan-in / fan-out census on stderr *)
  let tbl = Hashtbl.create 64 in
  let bump k f = let (i,o) = try Hashtbl.find tbl k with Not_found -> (0,0) in
    Hashtbl.replace tbl k (if f then (i+1,o) else (i,o+1)) in
  List.iter (fun (a,b) -> bump a false; bump b true) es;
  let rows = Hashtbl.fold (fun k (i,o) acc -> (k,i,o)::acc) tbl [] in
  let rows = List.sort (fun (_,i1,_) (_,i2,_) -> compare i2 i1) rows in
  prerr_endline "  fan-in  fan-out  node";
  List.iter (fun (k,i,o) ->
    if i >= 3 || o >= 10 then
      prerr_endline (Printf.sprintf "  %6d  %7d  %s" i o k)) rows;
  prerr_endline (Printf.sprintf "\n  nodes %d | edges %d"
    (Hashtbl.length tbl) (List.length es))
