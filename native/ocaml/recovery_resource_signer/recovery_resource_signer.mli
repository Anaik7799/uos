(** Exact native detached-signature PREPARATION. Client holds no private key;
    managed custody and authenticated startup provider remain unavailable.
    A separately bound local provider must reconstruct the fixed four purposes.
    No key/path/raw-payload/transport constructor or callback is exported.
    Production remains Unavailable. Signature facts are not effect authority. *)
type request
type signature_fact
val request_of_json : string -> (request,string) result
val sign : request -> (signature_fact,string) result
val encode : (signature_fact,string) result -> string
val serve : unit -> unit
