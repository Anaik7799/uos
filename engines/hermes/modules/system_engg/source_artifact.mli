module Id : sig
  type t = private string
  val make : string -> (t, string) result
  val to_string : t -> string
  val compare : t -> t -> int
end

module Sha256 : sig
  type t = private Digestif.SHA256.t
  val of_hex : string -> (t, string) result
  val digest_file : string -> (t, string) result
  val to_hex : t -> string
  val equal : t -> t -> bool
end

module Git_oid : sig
  type algorithm = Sha1 | Sha256
  type t = private { algorithm : algorithm; hex : string }
  val of_hex : algorithm:algorithm -> string -> (t, string) result
  val algorithm : t -> algorithm
  val to_hex : t -> string
end

module Relative_path : sig
  type t = private string
  val make : string -> (t, string) result
  val to_string : t -> string
end

type entry_kind = Regular | Executable | Symlink | Submodule | Lfs_pointer

type tree_entry = {
  path : Relative_path.t;
  kind : entry_kind;
  mode : int;
  blob_sha256 : Sha256.t option;
  symlink_target : string option;
  git_oid : Git_oid.t option;
}

type pin =
  | Blob_pin of { sha256 : Sha256.t; byte_count : int }
  | Git_tree_pin of {
      commit : Git_oid.t;
      tree_oid : Git_oid.t;
      canonical_tree_sha256 : Sha256.t;
      entry_count : int;
    }

type expected
type observation
type receipt

type verification_error =
  | Unknown_source_state of string
  | Digest_mismatch of { expected : string; observed : string }
  | Entry_count_mismatch of { expected : int; observed : int }
  | Type_mismatch of string
  | Path_error of string

val expect : id:Id.t -> locator:Uri.t -> pin:pin -> expected
val pin : expected -> pin
val canonical_tree : tree_entry list -> (string, verification_error list) result
val observe_blob : path:string -> (observation, string) result
val observe_git_tree : root:string -> (observation, string) result
val verify : expected -> observation ->
  (receipt, verification_error list) result
val receipt_digest : receipt -> Sha256.t
val canonical_receipt : receipt -> string