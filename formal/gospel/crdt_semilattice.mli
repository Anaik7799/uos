(* Gospel Specification of Delta-State CRDT Semilattice Laws *)
(* STAMP: SC-CRDT-001, SC-GOSPEL-001, SC-SIL6-001 *)

type node_id = string
type counter = int
type dot = { node: node_id; count: counter }
type vector_clock = (node_id * counter) list

(*@ function get_clock (vc: vector_clock) (n: node_id) : counter *)

(*@ val merge_clocks : vector_clock -> vector_clock -> vector_clock
    ensures forall n: node_id.
      get_clock result n = max (get_clock a n) (get_clock b n)
    (* Algebraic Semilattice Laws *)
    ensures (* Commutativity *) merge_clocks a b = merge_clocks b a
    ensures (* Idempotence *)   merge_clocks a a = a
*)

type 'a lww_register = {
  value: 'a;
  timestamp_us: int;
  writer: node_id;
}

(*@ val merge_lww : 'a lww_register -> 'a lww_register -> 'a lww_register
    ensures (a.timestamp_us > b.timestamp_us -> result = a)
    ensures (b.timestamp_us > a.timestamp_us -> result = b)
    ensures (a.timestamp_us = b.timestamp_us ->
      (a.writer >= b.writer -> result = a) /\
      (b.writer > a.writer -> result = b))
*)

type 'a or_set = {
  elements: ('a * dot) list;
  tombstones: dot list;
}

(*@ val merge_orset : 'a or_set -> 'a or_set -> 'a or_set
    ensures (* Commutativity *) merge_orset a b = merge_orset b a
    ensures (* Idempotence *)   merge_orset a a = a
*)
