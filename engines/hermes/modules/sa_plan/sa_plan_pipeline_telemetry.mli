type stage

val stage : name:string -> duration_ns:int64 -> stage
val measure : name:string -> (unit -> 'a) -> 'a * stage
val now_ns : unit -> int64
val server_timing : total_ns:int64 -> stage list -> string

val to_yojson :
  request_id:string -> command:string -> total_ns:int64 -> stage list ->
  Yojson.Safe.t

val log_line :
  request_id:string -> command:string -> total_ns:int64 -> stage list -> string
