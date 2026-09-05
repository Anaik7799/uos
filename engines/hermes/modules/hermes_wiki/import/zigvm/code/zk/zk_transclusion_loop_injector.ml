(* ZK Transclusion Loop Injector — a REAL adversary + REAL cycle detector.

   Promoted from a phase-7 printf stub. A transclusion is `![[target]]`: a note
   embedding another note's body. If A embeds B embeds A the expander must not
   loop forever. This module (1) scans the live corpus for the real transclusion
   graph, (2) INJECTS a synthetic cycle A->B->C->A into that graph, and (3) runs
   a real DFS colour-marking cycle detector and reports the offending back-edges.

   The detector is the thing under test: it is a total, bounded DFS (white/grey/
   black colouring) — a grey->grey edge is a cycle. The injector's job is to
   guarantee the detector fires on a known-planted cycle (else the detector is a
   false-green), while also reporting any cycle already latent in the corpus.

   [N/A] The live docs/zk corpus uses ZERO `![[...]]` transclusions today, so the
   real transclusion graph is empty; the detector is exercised against the
   injected synthetic cycle (real algorithm, real back-edge output). *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let zk_files root =
  let dir = Filename.concat root "docs/zk" in
  let rec walk d acc =
    let entries = try Sys.readdir d with _ -> [||] in
    Array.fold_left (fun acc name ->
      let p = Filename.concat d name in
      if (try Sys.is_directory p with _ -> false) then walk p acc
      else if Filename.check_suffix name ".md" then p :: acc
      else acc) acc entries
  in List.sort compare (walk dir [])

let find_from s sub i =
  let ls = String.length s and lsub = String.length sub in
  let rec go i =
    if i + lsub > ls then None
    else if String.sub s i lsub = sub then Some i
    else go (i + 1)
  in if lsub = 0 then None else go i

(* real transclusion edges out of [src]: every ![[target]] occurrence *)
let transclusions_of src body =
  let rec go i acc =
    match find_from body "![[" i with
    | None -> List.rev acc
    | Some a ->
      (match find_from body "]]" (a + 3) with
       | None -> List.rev acc
       | Some b ->
         let inner = String.sub body (a + 3) (b - (a + 3)) in
         let target = match String.index_opt inner '|' with
           | Some p -> String.sub inner 0 p | None -> inner in
         go (b + 2) ((src, String.trim target) :: acc))
  in go 0 []

(* white=0 grey=1 black=2 DFS; returns list of back-edges (u,v) closing a cycle *)
let detect_cycles edges =
  let nodes = List.sort_uniq compare
    (List.concat_map (fun (a, b) -> [a; b]) edges) in
  let adj = Hashtbl.create 64 in
  List.iter (fun (a, b) ->
    Hashtbl.replace adj a (b :: (try Hashtbl.find adj a with Not_found -> []))) edges;
  let colour = Hashtbl.create 64 in
  List.iter (fun n -> Hashtbl.replace colour n 0) nodes;
  let back = ref [] in
  let rec dfs u =
    Hashtbl.replace colour u 1;
    List.iter (fun v ->
      match (try Hashtbl.find colour v with Not_found -> 0) with
      | 1 -> back := (u, v) :: !back           (* grey target => cycle *)
      | 0 -> dfs v
      | _ -> ()) (try Hashtbl.find adj u with Not_found -> []);
    Hashtbl.replace colour u 2
  in
  List.iter (fun n -> if Hashtbl.find colour n = 0 then dfs n) nodes;
  List.rev !back

let run (root : string) : unit =
  let files = zk_files root in
  let real_edges =
    List.concat_map (fun path ->
      let body = try read_file path with _ -> "" in
      transclusions_of (Filename.basename path) body) files in
  Printf.printf "[zk_transclusion_loop_injector] real transclusion edges in corpus: %d\n"
    (List.length real_edges);
  let real_cycles = detect_cycles real_edges in
  Printf.printf "  latent cycles in real corpus: %d\n" (List.length real_cycles);
  (* INJECT a known cycle A->B->C->A into the (possibly empty) real graph *)
  let injected = [("__inj_A", "__inj_B"); ("__inj_B", "__inj_C"); ("__inj_C", "__inj_A")] in
  let all = real_edges @ injected in
  let found = detect_cycles all in
  Printf.printf "  injected synthetic cycle A->B->C->A; detector back-edges: %d\n"
    (List.length found);
  List.iter (fun (u, v) -> Printf.printf "    back-edge %s -> %s\n" u v) found;
  if found <> [] then
    Printf.printf "  detector FIRED on the planted cycle (bounded DFS, not a hang)\n"
  else
    Printf.printf "  [WARNING] detector missed the planted cycle — would be a false-green\n";
  if real_edges = [] then
    Printf.printf "  [N/A] no ![[...]] transclusions exist in the live corpus (feature unused)\n"
