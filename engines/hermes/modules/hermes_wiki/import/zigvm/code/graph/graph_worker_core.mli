(** Durable executor for graph workspace jobs admitted by [Graph_store]. *)

type outcome =
  | No_work
  | Finished of Graph_store.job

val run_one : Db.t -> outcome
val drain : ?limit:int -> Db.t -> int
