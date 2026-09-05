module Digest : sig
  type t
  type error = Invalid_digest
  val make : string -> (t, error) result
  val of_bytes : bytes -> t
  val to_string : t -> string
end

type file_mode = Regular | Executable | Symlink
type file
type range
type whole
type partition
type error = Invalid_file | Empty_manifest | Too_many_entries | Duplicate_path
  | Unknown_selection | Invalid_range | Duplicate_range | Overlap | Incomplete_partition
  | Stale_blob

val file : path:Jj_path.t -> base_blob:Digest.t -> current_blob:Digest.t ->
  base_mode:file_mode -> current_mode:file_mode -> (file, error) result
val range : start_offset:int -> end_offset:int -> (range, error) result
val whole : source_authority:Digest.t -> files:file list -> selected:Jj_path.t list ->
  (whole, error) result
val whole_selected : whole -> Jj_path.t list
val whole_remainder : whole -> Jj_path.t list
val whole_digest : whole -> string
val partition : source_authority:Digest.t -> path:Jj_path.t ->
  base_blob:Digest.t -> current_blob:Digest.t -> base_mode:file_mode ->
  current_mode:file_mode -> base_bytes:bytes -> current_bytes:bytes ->
  selected:range list -> remainder:range list -> (partition, error) result
val partition_reconstructs : partition -> bool
val partition_path : partition -> Jj_path.t
val partition_current_blob : partition -> Digest.t
val partition_current_mode : partition -> file_mode
val partition_selected_digest : partition -> Digest.t
val partition_remainder_digest : partition -> Digest.t
val partition_digest : partition -> string
val source_digest : string
