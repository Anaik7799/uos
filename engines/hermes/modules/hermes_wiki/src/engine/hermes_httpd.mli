(* A minimal read-only static HTTP server over the built site: no
   dependency (Unix sockets only, R14 — Dream is not installed here), no
   writes, no filesystem traversal. GET/HEAD only; anything else is 405.
   The route table is the site's page list, so an unbuilt page 404s
   rather than reading the disk. *)

type response = { status : int; content_type : string; body : string }

(* Pure request routing: the whole server behavior, testable without a
   socket. [path] is the raw request target (may carry a query string). *)
val respond : pages:(string * string) list -> meth:string -> path:string -> response

(* Parse the request line of an HTTP request. None when malformed. *)
val parse_request_line : string -> (string * string) option

(* R15: this host on the Tailscale fabric. The FQDN (MagicDNS name) is
   the canonical handle -- an address can change, the name does not.
   None when no Tailscale fabric is present. *)
val tailscale_fqdn : unit -> string option
val tailscale_address : unit -> string option

(* Pure parsers, testable without a network: [parse_tailscale] over an
   "ip -4 addr" style listing, [parse_fqdn] over "tailscale status --json"
   output (the DNSName field, trailing dot stripped). *)
val parse_tailscale : string -> string option
val parse_fqdn : string -> string option

(* Serve until interrupted. Binds ALL interfaces so the surface is
   reachable over Tailscale (R15); [banner] is what the operator sees. *)
val banner : port:int -> string
val serve : pages:(string * string) list -> port:int -> unit
