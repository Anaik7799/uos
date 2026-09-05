(** Immutable, referentially closed graph revisions. *)

type edit =
  | Add_node of Graph_intelligence.node
  | Add_edge of Graph_intelligence.edge
  | Rename_node of { node_id : string; label : string }
  | Merge_nodes of { source_ids : string list; target_id : string; target_label : string }
  | Remove_nodes of string list
  | Remove_edges of string list

type comparison_mode = Merge | Overlap | Difference_left | Difference_right | Difference_nodes

type t = {
  project_id : string;
  revision : int;
  parent_revision : int option;
  graph : Graph_intelligence.t;
  edits : edit list;
  statement_ids : string list;
}

type error =
  | Missing_node of string
  | Duplicate_node of string
  | Missing_edge_endpoint of string
  | Duplicate_edge of string
  | Blank_label
  | Empty_merge
  | Merge_target_collision of string

type frame = { revision : int; node_count : int; edge_count : int; statement_ids : string list }

val error_name : error -> string
val of_graph : ?statement_ids:string list -> project_id:string -> revision:int -> Graph_intelligence.t -> t
val node_ids : t -> string list
val node_label : t -> string -> string option
val apply : t -> edit -> (t, error) result
val visible : t -> Workspace_domain.filter -> t
val compare : comparison_mode -> t -> t -> t
val timeline : t list -> frame list
