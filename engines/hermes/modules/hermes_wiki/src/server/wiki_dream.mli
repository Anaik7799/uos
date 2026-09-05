(* The Dream server over the typed routes.

   Every route in Wiki_routes.all is registered; the router is DERIVED
   from the type, so a constructor without a handler is a compile error
   rather than a silent 404. Read-only stays structural: only
   Dream.get is ever called, so no write route exists to be reached.

   R15 is unchanged: the caller gates on the Tailscale FQDN before this
   ever binds. *)

(* The pure part: which page (or asset) a target resolves to, and the
   status it should carry. Testable without a server. *)
type resolution =
  | Page of string * string   (* content-type, body *)
  | Not_found

val resolve :
  pages:(string * string) list -> model_json:string -> css:string ->
  target:string -> resolution

(* The security headers every response carries (CSP, nosniff, DENY,
   no-referrer, no-store). *)
val security_headers : (string * string) list

(* Build the Dream handler for a built site. *)
val handler :
  pages:(string * string) list -> model_json:string -> css:string -> Dream.handler

(* Serve. Binds all interfaces (R15); the caller has already gated. *)
val serve :
  pages:(string * string) list -> model_json:string -> css:string ->
  port:int -> unit
