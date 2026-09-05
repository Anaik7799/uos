module Store_path_set = Set.Make(struct
  type t = Nix_id.Store_path.t
  let compare a b = Nix_id.Store_path.compare a b
end)

module Closure_set = struct
  type t = Store_path_set.t
  let empty = Store_path_set.empty
  let singleton p = Store_path_set.singleton p
  let union a b = Store_path_set.union a b
  let inter a b = Store_path_set.inter a b
  let subset a b = Store_path_set.subset a b
  let equal a b = Store_path_set.equal a b
  let size a = Store_path_set.cardinal a
  let elements a = Store_path_set.elements a
end

module Flake_lock_composition = struct
  type node = { name : string; locked_rev : string; nar_hash : string }
  type t = node list

  let empty = []

  let rec upsert node = function
    | [] -> [ node ]
    | x :: xs ->
        if String.equal x.name node.name then node :: xs
        else x :: upsert node xs

  let combine a b =
    List.fold_left (fun acc n -> upsert n acc) a b

  let is_idempotent a =
    combine a a = a

  let is_commutative a b =
    let sort_nodes = List.sort (fun (x : node) y -> String.compare x.name y.name) in
    sort_nodes (combine a b) = sort_nodes (combine b a)
end

module Devenv_module_overlay = struct
  type layer = {
    env_vars : (string * string) list;
    packages : string list;
    services : string list;
  }
  type t = layer list

  let empty = { env_vars = []; packages = []; services = [] }

  let merge_env base override =
    let remove_key k list = List.filter (fun (k', _) -> not (String.equal k k')) list in
    let stripped = List.fold_left (fun acc (k, _) -> remove_key k acc) base override in
    stripped @ override

  let compose_layer base overlay =
    { env_vars = merge_env base.env_vars overlay.env_vars;
      packages = List.sort_uniq String.compare (base.packages @ overlay.packages);
      services = List.sort_uniq String.compare (base.services @ overlay.services) }

  let compose_all layers =
    List.fold_left compose_layer empty layers
end

module Laws = struct
  let verify_closure_join_semilattice a b c =
    let id_a = Closure_set.equal (Closure_set.union a Closure_set.empty) a in
    let comm = Closure_set.equal (Closure_set.union a b) (Closure_set.union b a) in
    let assoc =
      Closure_set.equal
        (Closure_set.union (Closure_set.union a b) c)
        (Closure_set.union a (Closure_set.union b c))
    in
    let idemp = Closure_set.equal (Closure_set.union a a) a in
    id_a && comm && assoc && idemp

  let verify_flake_lock_monoid a b =
    let left_id = Flake_lock_composition.combine Flake_lock_composition.empty a = a in
    let right_id = Flake_lock_composition.combine a Flake_lock_composition.empty = a in
    let comp = Flake_lock_composition.combine a b in
    left_id && right_id && (List.length comp >= List.length a)

  let verify_devenv_overlay_associativity a b c =
    let left = Devenv_module_overlay.compose_layer (Devenv_module_overlay.compose_layer a b) c in
    let right = Devenv_module_overlay.compose_layer a (Devenv_module_overlay.compose_layer b c) in
    left = right
end
