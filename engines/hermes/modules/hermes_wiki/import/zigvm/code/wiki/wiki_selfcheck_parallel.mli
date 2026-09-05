(** Bounded guided self-scheduling for the independent wiki render frontier.

    The carrier preserves the input coordinate: every result is written at the
    same array index as its source item.  [visits] is executable exactly-once
    evidence; [worker_items] and [worker_ns] are report-only observations. *)
type 'a run = {
  values : 'a array;
  visits : int array;
  workers : int;
  worker_items : int array;
  worker_ns : int64 array;
}

val recommended_workers : unit -> int

val map_gss :
  workers:int -> ('a -> 'b) -> 'a array -> 'b run
(** [map_gss ~workers f xs] maps [f] over [xs] in bounded persistent Eio
    domains. Workers claim decreasing guided chunks. The returned value order is
    identical to [Array.map f xs]. *)
