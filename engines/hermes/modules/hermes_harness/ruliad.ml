(* Multiway exploration with memoized states. BFS to a fixpoint over canonical
   state keys (the zigvm sm_reachable discipline; the HashLife lesson: paths are
   factorial, distinct states are not, so dedup by canonical key collapses the
   space). Path counts and depth come from a DP over the deduped graph, with
   tricolor cycle detection -- a cyclic system is an Error, never a hang. *)

type ('state, 'move) system = {
  initial : 'state;
  moves : 'state -> 'move list;
  apply : 'state -> 'move -> 'state;
  canonical : 'state -> string;
}

type 'state graph = {
  state_count : int;
  edge_count : int;
  terminals : 'state list;
  reachable : 'state list;
  confluent : bool;
  path_count : int;
  max_depth : int;
}

type 'state node = { state : 'state; successors : string list (* one per applicable move *) }

let explore ?(max_states = 100_000) system =
  let nodes : (string, 'state node) Hashtbl.t = Hashtbl.create 256 in
  let queue = Queue.create () in
  let overflow = ref false in
  let visit state =
    let key = system.canonical state in
    if (not (Hashtbl.mem nodes key)) && not !overflow then
      if Hashtbl.length nodes >= max_states then overflow := true
      else begin
        (* placeholder to claim the key; successors filled on expansion *)
        Hashtbl.replace nodes key { state; successors = [] };
        Queue.add key queue
      end
  in
  visit system.initial;
  while (not (Queue.is_empty queue)) && not !overflow do
    let key = Queue.pop queue in
    let node = Hashtbl.find nodes key in
    let successor_keys =
      List.map
        (fun move ->
          let next = system.apply node.state move in
          visit next;
          system.canonical next)
        (system.moves node.state)
    in
    Hashtbl.replace nodes key { node with successors = successor_keys }
  done;
  if !overflow then
    Error (Printf.sprintf "state cap (%d) exceeded: bounded exploration refuses, not truncates" max_states)
  else begin
    (* DP over the deduped graph: exact maximal-path counts and depth, with
       tricolor marking so a cycle is a detected Error rather than divergence. *)
    let color : (string, [ `On_stack | `Done_ ]) Hashtbl.t = Hashtbl.create 256 in
    let memo_paths : (string, int) Hashtbl.t = Hashtbl.create 256 in
    let memo_depth : (string, int) Hashtbl.t = Hashtbl.create 256 in
    let cyclic = ref false in
    let rec walk key =
      match Hashtbl.find_opt color key with
      | Some `On_stack -> cyclic := true; (0, 0)
      | Some `Done_ -> (Hashtbl.find memo_paths key, Hashtbl.find memo_depth key)
      | None ->
          Hashtbl.replace color key `On_stack;
          let node = Hashtbl.find nodes key in
          let paths, depth =
            match node.successors with
            | [] -> (1, 0)
            | successors ->
                List.fold_left
                  (fun (p, d) successor ->
                    let sp, sd = walk successor in
                    (p + sp, max d (sd + 1)))
                  (0, 0) successors
          in
          Hashtbl.replace color key `Done_;
          Hashtbl.replace memo_paths key paths;
          Hashtbl.replace memo_depth key depth;
          (paths, depth)
    in
    let root = system.canonical system.initial in
    let path_count, max_depth = walk root in
    if !cyclic then Error "cyclic system: the path DP would diverge; multiway moves must be monotone"
    else begin
      let terminals =
        Hashtbl.fold
          (fun _ node acc -> if node.successors = [] then node.state :: acc else acc)
          nodes []
      in
      let edge_count =
        Hashtbl.fold (fun _ node acc -> acc + List.length node.successors) nodes 0
      in
      Ok
        { state_count = Hashtbl.length nodes;
          edge_count;
          terminals;
          reachable = Hashtbl.fold (fun _ node acc -> node.state :: acc) nodes [];
          confluent = List.length terminals = 1;
          path_count;
          max_depth }
    end
  end
