(* The typed route algebra: routes are a VARIANT, not strings.

   This is zigvm's route-algebra idea reconstructed (its
   `route_algebra_core` library was deleted from that tree). The payoff is
   structural: [all] enumerates every constructor, the server derives its
   Dream router from that list, and a test proves the enumeration is
   total — so a route that exists in the type but not in the router is a
   caught defect rather than a 404 nobody notices.

   The read-only law is in the TYPE: there is no constructor carrying a
   method other than GET/HEAD, so no write route can be expressed. *)

type t =
  | Index
  | Dashboard
  | Components
  | Component of string      (* :slug *)
  | Usecases
  | Operations
  | Analytics
  | Wiki_index
  | Wiki_page of string      (* :slug *)
  | Zk_graph
  | Atlas
  | Plan
  | Model_json               (* the machine-readable read model *)
  | Stylesheet

(* Every constructor with a concrete argument, for enumeration in tests
   and for deriving the router. Parameterized routes appear once with a
   sample argument; [pattern] gives their Dream path pattern. *)
val all : t list

(* The path a route serves, e.g. Index -> "/", Component "x" ->
   "/component-x.html". Total. *)
val to_path : t -> string

(* The Dream router pattern for a route, e.g. Component _ ->
   "/component-:slug.html". Total. *)
val pattern : t -> string

(* Parse a request target back to a route. None when nothing matches —
   the 404 case, decided without touching the filesystem. *)
val of_path : string -> t option

(* The page name this route resolves to in the built site's page list.
   None for routes served from something other than a page (Model_json,
   Stylesheet). *)
val page_name : t -> string option
