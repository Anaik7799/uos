(* Fractal algebra for the vision pipeline. See vision_algebra.mli. *)

open Vision_ontology

type segment = { first : stage; last : stage }

let segment a b = if stage_index a <= stage_index b then Some { first = a; last = b } else None

let stages_of s =
  List.filter
    (fun x -> stage_index x >= stage_index s.first && stage_index x <= stage_index s.last)
    stages

let compose a b =
  (* adjacency: b may start at a.last (overlap) or one past it. A larger
     jump leaves a stage unmeasured, and that is the gap this refuses. *)
  if stage_index b.first <= stage_index a.last + 1 && stage_index b.first >= stage_index a.first
  then
    let last = if stage_index a.last >= stage_index b.last then a.last else b.last in
    Some { first = a.first; last }
  else None

let identity s = { first = s; last = s }

let full = { first = Source; last = Observe }

let covers_pipeline s = s.first = Source && s.last = Observe

let coverage = function
  | [] -> Error "no segment was measured, so nothing is covered"
  | first :: rest ->
      (* sort by start so composition is order-independent: a caller must
         not be able to manufacture coverage by presenting evidence in a
         flattering order *)
      let sorted =
        List.sort
          (fun a b -> compare (stage_index a.first) (stage_index b.first))
          (first :: rest)
      in
      let rec fold acc = function
        | [] -> Ok acc
        | s :: tl -> (
            match compose acc s with
            | Some merged -> fold merged tl
            | None ->
                Error
                  (Printf.sprintf "gap: nothing measured between %s and %s"
                     (stage_name acc.last) (stage_name s.first)))
      in
      fold (List.hd sorted) (List.tl sorted)
