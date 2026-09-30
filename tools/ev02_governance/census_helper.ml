#use "topfind";;
#require "yojson";;

type commit = {
  id : string;
  parents : string list;
  is_empty : bool;
  description : string;
}

type dag = commit list

let find_commit (dag : dag) (id : string) : commit option =
  List.find_opt (fun c -> c.id = id) dag

let ancestors (dag : dag) (root_ids : string list) : string list =
  let rec loop acc queue =
    match queue with
    | [] -> acc
    | id :: rest ->
        if List.mem id acc then loop acc rest
        else
          match find_commit dag id with
          | None -> loop acc rest
          | Some c -> loop (id :: acc) (c.parents @ rest)
  in
  loop [] root_ids

let diff (a : string list) (b : string list) : string list =
  List.filter (fun x -> not (List.mem x b)) a

let heads (dag : dag) (set : string list) : string list =
  List.filter (fun id ->
    not (List.exists (fun other_id ->
      if other_id = id then false
      else
        let anc = ancestors dag [other_id] in
        List.mem id anc
    ) set)
  ) set

let eval_naive_query (dag : dag) : string list =
  let all_ids = List.map (fun c -> c.id) dag in
  let all_heads = heads dag all_ids in
  List.filter (fun id ->
    match find_commit dag id with
    | Some c -> not c.is_empty
    | None -> false
  ) all_heads

let eval_robust_query (dag : dag) (target : string) : (string * string list) list =
  let all_ids = List.map (fun c -> c.id) dag in
  let target_ancestors = ancestors dag [target] in
  let unintegrated = diff all_ids target_ancestors in
  let non_empty_unintegrated =
    List.filter (fun id ->
      match find_commit dag id with
      | Some c -> not c.is_empty
      | None -> false
    ) unintegrated
  in
  let robust_heads = heads dag non_empty_unintegrated in
  List.map (fun h_id ->
    let unique = diff (ancestors dag [h_id]) target_ancestors in
    (h_id, unique)
  ) robust_heads

let make_synthetic_dag () : dag =
  [
    {
      id = "commit-A-target-base";
      parents = [];
      is_empty = false;
      description = "target baseline revision";
    };
    {
      id = "commit-B-historical-code";
      parents = ["commit-A-target-base"];
      is_empty = false;
      description = "historical unintegrated development code";
    };
    {
      id = "commit-C-empty-tip";
      parents = ["commit-B-historical-code"];
      is_empty = true;
      description = "empty workspace child";
    };
  ]

let run_selftest () : string =
  let dag = make_synthetic_dag () in
  let target = "commit-A-target-base" in
  let code_id = "commit-B-historical-code" in

  (* 1. Naive query: heads(all()) & ~empty() drops commit B *)
  let naive_results = eval_naive_query dag in
  let naive_missed = not (List.mem code_id naive_results) in

  (* 2. Robust query: heads(all() ~ ancestors(target) ~ empty()) discovers commit B *)
  let robust_results = eval_robust_query dag target in
  let robust_discovered = List.exists (fun (h, _) -> h = code_id) robust_results in
  let unique_count =
    match List.find_opt (fun (h, _) -> h = code_id) robust_results with
    | Some (_, unique) -> List.length unique
    | None -> 0
  in

  if not naive_missed then failwith "synthetic DAG failed: naive query should miss commit B";
  if not robust_discovered then failwith "synthetic DAG failed: robust query should discover commit B";
  if unique_count <> 1 then failwith "synthetic DAG failed: unique ancestor count should be 1";

  let report = `Assoc [
    "schema", `String "uos.census-helper/v1";
    "status", `String "PASS";
    "rca", `String "filtering heads first hid code below empty workspace children";
    "naive_query", `String "heads(all()) & ~empty()";
    "naive_missed_commit_b", `Bool naive_missed;
    "robust_query", `String "heads(all() ~ ancestors(target) ~ empty())";
    "robust_discovered_commit_b", `Bool robust_discovered;
    "unique_ancestors_count", `Int unique_count;
  ] in
  Yojson.Safe.to_string report

let print_witness () =
  let dag = make_synthetic_dag () in
  let target = "commit-A-target-base" in
  Printf.printf "=== Pure Bounded Synthetic DAG Revset Witness ===\n";
  Printf.printf "Topology:\n";
  List.iter (fun c ->
    Printf.printf "  %s [empty=%b, parents=[%s]] : %s\n"
      c.id c.is_empty (String.concat ", " c.parents) c.description
  ) dag;
  let naive = eval_naive_query dag in
  Printf.printf "\nNaive query 'heads(all()) & ~empty()':\n";
  Printf.printf "  Result: [%s] (commit-B hidden because empty head commit-C was filtered after heads)\n"
    (String.concat ", " naive);
  let robust = eval_robust_query dag target in
  Printf.printf "\nRobust query 'heads(all() ~ ancestors(target) ~ empty())':\n";
  List.iter (fun (h, u) ->
    Printf.printf "  Discovered Head: %s\n" h;
    Printf.printf "    Unique Ancestors: [%s]\n" (String.concat ", " u)
  ) robust;
  Printf.printf "\nVerdict: PASS (pure algebraic witness without subprocesses or side effects)\n"

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--selftest" then (
    let json = run_selftest () in
    print_endline json;
    exit 0
  ) else if Array.length Sys.argv > 1 && (Sys.argv.(1) = "--witness" || Sys.argv.(1) = "--explain") then (
    print_witness ();
    exit 0
  ) else (
    Printf.eprintf "Usage: %s --selftest | --witness\n" Sys.argv.(0);
    exit 2
  )
