(** Cooperative read-only interpreter. All native JJ calls share a five-second
    monotonic deadline and 64 KiB capture budget; filesystem calls require a
    responsive local filesystem. Empty .git directories are observations, not
    operational Git metadata. No admission or effect-time fencing is provided. *)
type marker = Absent of string | Empty_directory of string * int * float * float
type observation = {
  root : string;
  revision : string;
  facts : (Bootstrap_model.fact * bool) list;
  markers : marker list;
}
val observe : string -> (observation, string) result
