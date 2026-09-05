type phase = Prepared | Committing of int | Committed
type target = { path : string; temporary : string; backup : string option }
type t = { version : int; journal_path : string; content_id : string; phase : phase; targets : target list }

val with_lock :
  path:string ->
  (unit -> ('a, [ `Msg of string ]) result) ->
  ('a, [ `Msg of string ]) result

val prepare :
  journal_path:string ->
  content_id:string ->
  content:string ->
  targets:string list ->
  (t, [ `Msg of string ]) result

val commit : ?fail_after:int -> t -> (unit, [ `Msg of string ]) result
val recover : journal_path:string -> (unit, [ `Msg of string ]) result
val same_filesystem : string list -> (bool, [ `Msg of string ]) result
