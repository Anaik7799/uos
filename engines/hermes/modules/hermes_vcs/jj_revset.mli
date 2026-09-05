type t
type error = Empty_set | Too_many_terms | Too_complex | Invalid_limit

val working_copy : t
val commit : Jj_id.Commit.t -> t
val change : Jj_id.Change.t -> t
val bookmark : Jj_id.Bookmark.t -> t
val remote_bookmark : remote:Jj_id.Remote.t -> bookmark:Jj_id.Bookmark.t -> t
val parent : t -> (t, error) result
val ancestors : t -> (t, error) result
val descendants : t -> (t, error) result
val union : t list -> (t, error) result
val intersection : t list -> (t, error) result
val difference : t -> t -> (t, error) result
val limit : max_count:int -> t -> (t, error) result
val equal : t -> t -> bool
val digest : t -> string
val source_digest : string
