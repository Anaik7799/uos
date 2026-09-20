exception Invalid of string
val require : bool -> string -> unit
val db_path : string
val schema : string
val ok : Sqlite3.Rc.t -> unit
val sha256 : string -> string
val open_db : unit -> Sqlite3.db
val text : Sqlite3.stmt -> int -> string
val num : Sqlite3.stmt -> int -> int
val head : Sqlite3.db -> int
val digest_at : Sqlite3.db -> int -> string
val canonical : seq:int -> cycle_id:string -> plan_id:string -> task_id:string ->
  kind:string -> title:string -> body:string -> observed:string -> evidence:string ->
  prev:string -> string
val append : Sqlite3.db -> cycle_id:string -> plan_id:string -> task_id:string ->
  kind:string -> title:string -> body:string -> observed:string -> evidence:string -> int * string
val verify : Sqlite3.db -> int * string list
val close : Sqlite3.db -> unit
