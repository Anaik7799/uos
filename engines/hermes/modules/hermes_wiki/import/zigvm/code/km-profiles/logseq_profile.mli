type family =
  | Foundation
  | Linking
  | Productivity
  | Media
  | Tools
  | Customization
  | Formats
  | Database_graph
  | Ecosystem

type disposition =
  | Exact
  | Equivalent
  | Advisory
  | Unsupported of string
  | Unavailable of string

type feature = {
  id : string;
  family : family;
  disposition : disposition;
  wiki_mapping : string;
  zk_mapping : string;
  source : string;
}

type source_authority = Official_docs | Source_repository | Community_advisory
type source_row = {
  feature_id : string;
  coordinate : string;
  revision : string;
  family : family;
  authority : source_authority;
  executable_authority : bool;
}

type document
type edge
type property
type task

type disposition_counts = {
  total : int;
  exact : int;
  equivalent : int;
  advisory : int;
  unsupported : int;
  unavailable : int;
}

val all_families : family list
val catalog : feature list
val source_census : source_row list
val features_in_family : family -> feature list
val catalog_violations : feature list -> string list
val census_violations : feature list -> source_row list -> string list
val disposition_counts : feature list -> disposition_counts
val parse_document : string -> document
val render_document : document -> string
val page_references : document -> string list
val block_references : document -> string list
val properties : document -> property list
val tasks : document -> task list
val wiki_links : document -> string list
val zk_edges : document -> edge list
val edge_target : edge -> string
val catalog_to_yojson : feature list -> Yojson.Safe.t
val census_to_yojson : source_row list -> Yojson.Safe.t
