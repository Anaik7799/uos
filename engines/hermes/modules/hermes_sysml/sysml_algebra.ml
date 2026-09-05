type ('src, 'dst) transition =
  | Id : ('a, 'a) transition
  | Step : ('a, 'b) transition * ('b, 'c) transition -> ('a, 'c) transition

let id = Id

let compose : type a b c. (b, c) transition -> (a, b) transition -> (a, c) transition =
  fun f g ->
    match f, g with
    | Id, x -> x
    | x, Id -> x
    | f', g' -> Step (g', f')

module type PORT = sig
  type msg
  type t
  val send : t -> msg -> unit
  val recv : t -> msg option
end

module Connect (P1 : PORT) (P2 : PORT with type msg = P1.msg) = struct
  let sync p1 p2 =
    match P1.recv p1 with
    | Some msg -> P2.send p2 msg
    | None -> ()
end
