(** Pure property-graph algebra for the native fractal intelligence workspace.

    The carrier is a finite node set and a finite directed edge set. [normalize]
    is the final encoding: node identifiers are unique, dangling edges are
    removed, and duplicate edges collapse. All observers are deterministic and
    representation-independent. *)

type node = {
  id : string;
  label : string;
  kind : string;
  layer : string;
  group : string;
  detail : string;
  weight : float;
}

type edge = {
  source : string;
  target : string;
  relation : string;
  weight : float;
}

type t = {
  id : string;
  title : string;
  kind : string;
  nodes : node list;
  edges : edge list;
}

type gap = {
  left_community : string;
  right_community : string;
  left_node : string;
  right_node : string;
  score : float;
}

type analytics = {
  node_count : int;
  edge_count : int;
  density : float;
  components : int;
  pagerank : (string * float) list;
  betweenness : (string * float) list;
  communities : (string * string) list;
  gaps : gap list;
}

type comparison = {
  left_id : string;
  right_id : string;
  common_nodes : string list;
  only_left_nodes : string list;
  only_right_nodes : string list;
  common_edges : string list;
  only_left_edges : string list;
  only_right_edges : string list;
}

val normalize : t -> t
val bounded : max_nodes:int -> t -> t
val degrees : t -> (string * int) list
val pagerank : ?iterations:int -> ?damping:float -> t -> (string * float) list
val betweenness : t -> (string * float) list
val communities : ?iterations:int -> t -> (string * string) list
val analyze : t -> analytics
val compare : t -> t -> comparison
val to_yojson : ?analytics:analytics -> t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> (t, string) result
val comparison_to_yojson : comparison -> Yojson.Safe.t
val to_graphml : t -> string
val to_dot : t -> string
