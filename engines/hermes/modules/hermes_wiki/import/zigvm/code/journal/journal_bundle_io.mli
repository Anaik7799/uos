type disposition = Written | Unchanged

type publication = {
  path : string;
  disposition : disposition;
}

val materialize_image :
  Journal_bundle_core.Journal_bundle.image_artifact ->
  (unit, [ `Msg of string ]) result

val acquire_files :
  pool_size:int ->
  string list ->
  ((string * string) list, [ `Msg of string ]) result

val map_ordered : pool_size:int -> ('a -> 'b) -> 'a list -> 'b list

val publish :
  content:string ->
  outputs:string list ->
  (publication list, [ `Msg of string ]) result

val sha256_file : string -> (string, [ `Msg of string ]) result

val disposition_name : disposition -> string
