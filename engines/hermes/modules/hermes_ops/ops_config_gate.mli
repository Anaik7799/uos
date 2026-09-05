(** Effectful observation gate over the pure [Ops_config] authority. *)

(** Every literal environment read observed in the live module tree. *)
val observed : unit -> (string * string) list

(** Observed variables absent from [Ops_config.elements]. *)
val undeclared : unit -> (string * string) list

(** Environment declarations not observed in the live tree. *)
val unused : unit -> string list

(** [None] exactly when the on-disk template equals the pure projection. *)
val template_drifted : unit -> string option

(** Human report and fail-closed exit code. *)
val check : unit -> string * int
