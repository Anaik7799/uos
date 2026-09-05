(* SysML v2 Action and Activity Semantics *)

type 'a t =
  | Return of 'a
  | Action of string * (unit -> 'a t)
  | Fork of 'a t * 'a t * ('a * 'a -> 'a t)

let return x = Return x

let rec bind m f =
  match m with
  | Return x -> f x
  | Action (name, next) -> Action (name, fun () -> bind (next ()) f)
  | Fork (m1, m2, next) -> Fork (m1, m2, fun (r1, r2) -> bind (next (r1, r2)) f)

let action name = Action (name, fun () -> Return ())

let ( >>= ) = bind
let ( let* ) = bind

let rec run = function
  | Return x -> x
  | Action (_name, next) ->
      (* In a real execution engine, this would perform the action's behavior *)
      run (next ())
  | Fork (m1, m2, next) ->
      (* Parallel execution placeholder *)
      let r1 = run m1 in
      let r2 = run m2 in
      run (next (r1, r2))
