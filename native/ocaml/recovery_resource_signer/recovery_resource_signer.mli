(** Exact native detached-signature PREPARATION. No managed custody or effect
    authority is established. No key/path/raw-payload provider is exported. *)
type request
type signature_fact
val request_of_json : string -> (request,string) result
val sign : request -> (signature_fact,string) result
val encode : (signature_fact,string) result -> string
val serve : unit -> unit
