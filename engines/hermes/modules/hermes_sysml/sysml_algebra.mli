type ('src, 'dst) transition =
  | Id : ('a, 'a) transition
  | Step : ('a, 'b) transition * ('b, 'c) transition -> ('a, 'c) transition

val id : ('a, 'a) transition
(*@ pure *)

val compose : ('b, 'c) transition -> ('a, 'b) transition -> ('a, 'c) transition
(*@ pure *)

(*@ axiom compose_id_left: forall f: ('a, 'b) transition. compose id f = f *)
(*@ axiom compose_id_right: forall f: ('a, 'b) transition. compose f id = f *)
(*@ axiom compose_assoc: forall f: ('c, 'd) transition, g: ('b, 'c) transition, h: ('a, 'b) transition.
      compose f (compose g h) = compose (compose f g) h *)

module type PORT = sig
  type msg
  type t
  val send : t -> msg -> unit
  val recv : t -> msg option
end

module Connect (P1 : PORT) (P2 : PORT with type msg = P1.msg) : sig
  val sync : P1.t -> P2.t -> unit
end
