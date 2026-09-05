(* EXPLORATORY shape determination, not a gate.

   The question nobody has answered: of the declared PREDICTIVE cones, how
   many actually disagree with the dune graph, and by how much? Three cones
   were checked by hand — one wrong by 7x, two roughly right — and every
   argument about what to build has been resting on that.

   What this CAN decide mechanically: whether a declared name is a node in the
   library graph at all. An executable is a graph leaf and a bare directory is
   not a node, so neither can be a reverse dependency of anything.

   What this CANNOT decide: what a suite actually covers. It guesses that a
   suite covers the libraries declared in its own directory, which is a
   heuristic and is labelled as one everywhere it is used. A suite testing one
   module of a big library, or a cross-cutting property, will be misjudged by
   it — which is precisely the residue that types cannot reach. *)

let root = "modules"

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let rec ml_files directory =
  match Sys.readdir directory with
  | exception _ -> []
  | entries ->
      Array.to_list entries |> List.sort String.compare
      |> List.concat_map (fun entry ->
             let path = Filename.concat directory entry in
             if (try Sys.is_directory path with _ -> false) then ml_files path
             else if Filename.check_suffix entry ".ml" then [ path ]
             else [])

(* Every ~dependents:[ "a"; "b" ] occurrence, with its file. Deliberately
   literal: a computed list is reported as UNREADABLE rather than guessed. *)
let declarations path =
  let source = read_file path in
  let n = String.length source in
  let marker = "~dependents:" in
  let k = String.length marker in
  let rec find i acc =
    if i + k > n then List.rev acc
    else if String.sub source i k = marker then begin
      let j = ref (i + k) in
      while !j < n && (source.[!j] = ' ' || source.[!j] = '\n' || source.[!j] = '\t') do incr j done;
      if !j < n && source.[!j] = '[' then begin
        let close = ref !j in
        while !close < n && source.[!close] <> ']' do incr close done;
        if !close >= n then find (i + k) (`Unreadable :: acc)
        else begin
          let body = String.sub source (!j + 1) (!close - !j - 1) in
          (* atoms are the quoted strings; anything else means computed *)
          let names = ref [] and in_str = ref false and buf = Buffer.create 32 in
          String.iter
            (fun c ->
              if !in_str then
                if c = '"' then (names := Buffer.contents buf :: !names; Buffer.clear buf; in_str := false)
                else Buffer.add_char buf c
              else if c = '"' then in_str := true)
            body;
          find (!close + 1) (`Names (List.rev !names) :: acc)
        end
      end
      else find (i + k) (`Unreadable :: acc)
    end
    else find (i + 1) acc
  in
  find 0 []

let () =
  let graph =
    match Dune_graph.libraries ~root with
    | Error e ->
        prerr_endline ("REFUSED: " ^ Dune_graph.string_of_parse_error e);
        exit 1
    | Ok libs -> Dune_graph.of_libraries libs
  in
  let libs =
    match Dune_graph.libraries ~root with Ok l -> l | Error _ -> []
  in
  Printf.printf "=== graph ===\n";
  Printf.printf "libraries: %d\n" (List.length (Dune_graph.nodes graph));
  Printf.printf "internal edges: %d\n" (List.length (Dune_graph.edges graph));
  let cone_sizes =
    List.map (fun n -> List.length (Dune_graph.cone graph n)) (Dune_graph.nodes graph)
  in
  let sorted = List.sort compare cone_sizes in
  let nth i = List.nth sorted (min i (List.length sorted - 1)) in
  Printf.printf "cone size: min %d, median %d, p90 %d, max %d\n"
    (nth 0)
    (nth (List.length sorted / 2))
    (nth (List.length sorted * 9 / 10))
    (nth (List.length sorted - 1));
  Printf.printf "libraries with an EMPTY cone (nothing depends on them): %d\n"
    (List.length (List.filter (fun s -> s = 0) cone_sizes));

  (* which libraries live in a directory — the heuristic's basis *)
  let libs_in directory =
    List.filter_map
      (fun (l : Dune_graph.library) ->
        if Filename.dirname l.lib_file = directory then Some l.lib_name else None)
      libs
  in

  (* the formal artifact, for an independent solver run *)
  let smt_path = Filename.concat (Filename.get_temp_dir_name ()) "dune_graph_acyclic.smt2" in
  let oc = open_out smt_path in
  output_string oc (Dune_graph.smt2_acyclic graph);
  close_out oc;
  Printf.printf "smt2 acyclicity query: %s\n" smt_path;

  Printf.printf "\n=== declared PREDICTIVE cones ===\n";
  let total = ref 0 and unreadable = ref 0 in
  let non_nodes = ref 0 and nodes_ok = ref 0 in
  let understated = ref 0 and overstated = ref 0 and matched = ref 0
  and underivable = ref 0 in
  let worst = ref [] in
  List.iter
    (fun path ->
      List.iter
        (fun decl ->
          incr total;
          match decl with
          | `Unreadable -> incr unreadable
          | `Names declared ->
              List.iter
                (fun d -> if Dune_graph.is_node graph d then incr nodes_ok else incr non_nodes)
                declared;
              let directory = Filename.dirname path in
              (match libs_in directory with
               | [] -> incr underivable
               | owned ->
                   let derived = Dune_graph.cone_of_set graph owned in
                   let dn = List.length derived and cn = List.length declared in
                   if dn > cn then begin
                     incr understated;
                     worst := (dn - cn, path, cn, dn) :: !worst
                   end
                   else if dn < cn then incr overstated
                   else incr matched))
        (declarations path))
    (ml_files root);

  Printf.printf "declarations: %d (unreadable/computed: %d)\n" !total !unreadable;
  Printf.printf "declared names that ARE graph nodes: %d\n" !nodes_ok;
  Printf.printf "declared names that are NOT nodes:   %d   <-- type error\n" !non_nodes;
  Printf.printf "\nheuristic comparison (suite covers its directory's libraries):\n";
  Printf.printf "  understated (derived cone larger): %d\n" !understated;
  Printf.printf "  overstated  (derived cone smaller): %d\n" !overstated;
  Printf.printf "  same size:                          %d\n" !matched;
  Printf.printf "  underivable (no library in dir):    %d\n" !underivable;
  Printf.printf "\nlargest understatements (gap, file, declared, derived):\n";
  List.sort (fun (a, _, _, _) (b, _, _, _) -> compare b a) !worst
  |> List.filteri (fun i _ -> i < 12)
  |> List.iter (fun (gap, path, cn, dn) ->
         Printf.printf "  +%-4d %-64s %d -> %d\n" gap path cn dn)
