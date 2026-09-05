(* The typed read model for the web surface: one value projected from the
   store and the registries. Derived-not-asserted (the dashboard law at
   web scale) and read-only by construction — nothing here can write. *)

type parity = {
  verified : int;
  total : int;
  divergent : int;
  blocked : int;
  snapshot : string;
}

type t = {
  revision : string;
  components : int;
  edges : int;
  scenarios : int;
  usecase_names : string list;
  system_grade : int;
  grades : (string * int) list;        (* component -> coverage rank *)
  census : (string * int) list;
  levels : (string * int * int) list;  (* level, components, covered *)
  parity : parity option;              (* None when the store is absent *)
  wiki_pages : int;
  wiki_links : int;
  intent_drift : string list;
  gaps : string list;                  (* completeness gaps, [] when clean *)
}

val load : root:string -> t
val to_json : t -> Yojson.Safe.t
