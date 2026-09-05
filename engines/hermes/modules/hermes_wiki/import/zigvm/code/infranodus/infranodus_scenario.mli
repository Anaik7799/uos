(** Pure scenario and evidence algebra for direct OCaml Playwright execution. *)

type viewport = { name : string; width : int; height : int }

type action =
  | Navigate of string
  | Click of string
  | Fill of { control : string; value : string }
  | Expect_ui of string
  | Expect_api of string
  | Screenshot of string
  | Video_chapter of string

type t

type evidence_state =
  | Declared
  | Executed_pass
  | Executed_fail of string list
  | Unavailable_observed of string

type evidence = {
  scenario_id : string;
  feature_id : string option;
  viewport : viewport;
  screenshot : string;
  video : string;
  trace : string;
  state : evidence_state;
}

val canonical_viewports : viewport list
val feature_scenarios : t list
val workflows : t list

val id : t -> string
val feature_id : t -> string
val viewports : t -> viewport list
val actions : t -> action list
val has_screenshot : t -> bool
val has_video : t -> bool
val has_state_expectation : t -> bool

val validate : t list -> (unit, string list) result
val validate_feature_coverage : t list -> (unit, string list) result
val evidence_manifest : t list -> evidence list
val validate_evidence : exists:(string -> bool) -> evidence list -> (unit, string list) result
val evidence_state_name : evidence_state -> string
val to_yojson : t -> Yojson.Safe.t
val evidence_to_yojson : evidence -> Yojson.Safe.t
