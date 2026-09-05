(** Independent list/event interpretation of {!Sa_plan_control_plane}. *)
type t
val create : domain:Sa_plan_control_plane.domain -> identity:Sa_plan_control_plane.identity -> t
val replay : t -> Sa_plan_control_plane.command list -> t
val observe : t -> Sa_plan_control_plane.observation
