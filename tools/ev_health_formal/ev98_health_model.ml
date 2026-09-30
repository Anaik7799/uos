(** Bounded, independent model of the health-register merge ordering.
    It models only well-formed records: an equal ordering key denotes the same
    payload, and a map contains at most one record for each node. *)

type register = {
  sample : int;
  logical : int;
  writer : int;
  payload : int;
}

let compare_key left right =
  match Int.compare left.sample right.sample with
  | 0 ->
      (match Int.compare left.logical right.logical with
       | 0 -> Int.compare left.writer right.writer
       | relation -> relation)
  | relation -> relation

let same_key left right = compare_key left right = 0

let well_formed_pair left right =
  not (same_key left right) || left.payload = right.payload

let select left right =
  if compare_key left right >= 0 then left else right

let extensional_merge left right =
  match left, right with
  | Some a, Some b when well_formed_pair a b -> Some (select a b)
  | Some _, Some _ -> None
  | Some record, None | None, Some record -> Some record
  | None, None -> None

let raw_list_order_counterexample () =
  let left = [ (0, { sample = 0; logical = 0; writer = 0; payload = 0 }) ] in
  let right = [ (1, { sample = 0; logical = 0; writer = 0; payload = 0 }) ] in
  left @ right <> right @ left

let registers =
  let values = [ 0; 1; 2 ] in
  List.concat_map
    (fun sample ->
       List.concat_map
         (fun logical ->
            List.concat_map
              (fun writer ->
                 List.map (fun payload -> { sample; logical; writer; payload }) [ 0; 1 ])
              values)
         values)
    values

let all_well_formed_pairs () =
  List.concat_map
    (fun left ->
       List.filter_map
         (fun right -> if well_formed_pair left right then Some (left, right) else None)
         registers)
    registers

let all_well_formed_triples () =
  List.concat_map
    (fun (left, middle) ->
       List.filter_map
         (fun right ->
            if well_formed_pair left right && well_formed_pair middle right then
              Some (left, middle, right)
            else None)
         registers)
    (all_well_formed_pairs ())

let laws_hold_by_enumeration () =
  let pairs = all_well_formed_pairs () in
  let triples = all_well_formed_triples () in
  List.for_all
    (fun (left, right) ->
       select left right = select right left
       && select left left = left
       && ((left.sample <= right.sample) || select left right = left))
    pairs
  && List.for_all
       (fun (left, middle, right) ->
          select (select left middle) right = select left (select middle right))
       triples
