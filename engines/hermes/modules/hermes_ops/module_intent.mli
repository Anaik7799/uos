(** Closed declarative-intent interfaces for every Dune-owning module area. *)

type stratum = Production | Generated | Verification | Tooling
type effect_posture = Pure | Read_only | Guarded_write | External_effect

type fpp_mapping =
  | Fpp_components of (Fpp_window_authority.owner * string list) list
  | Fpp_not_applicable of string

type mediation =
  | Direct_read
  | Run_swarm_bridge of string list
  | Unavailable_until_bridge_activity of string

type t = private {
  stable_id : string;
  owner_directory : string;
  purpose : string;
  stratum : stratum;
  libraries : Stanza.t list;
  plane : Ops_capability.plane;
  coordinate : Ops_capability.coordinate;
  effect_posture : effect_posture;
  configuration_ids : string list;
  capability_ids : string list;
  surfaces : (Ops_capability.surface * Ops_capability.applicability) list;
  fpp : fpp_mapping;
  mediation : mediation;
}

val all : t list
val find : string -> t option
val source_digest : string
val observed_dune_directories : root:string -> string list
val validate : root:string -> string list
val validate_configuration_references :
  known_ids:string list -> t list -> string list
val string_of_stratum : stratum -> string
val string_of_effect_posture : effect_posture -> string

module For_test : sig
  type mutation =
    | Drop_first
    | Duplicate_first_library
    | Erase_first_purpose
    | Force_direct_external_effect
    | Make_all_fpp_inapplicable
    | Add_unknown_configuration
    | Add_unknown_capability

  val mutate : mutation -> t list
  val validate_interfaces : root:string -> t list -> string list
  val validate_configuration_references :
    known_ids:string list -> t list -> string list
end
