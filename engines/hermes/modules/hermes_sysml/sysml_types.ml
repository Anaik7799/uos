(* Foundational Types for SysML v2 and OML integration *)

type scalar_type =
  | Real
  | Integer
  | String
  | Boolean
  | Custom of string

type multiplicity =
  | Single
  | Optional
  | Collection

type value_property = {
  id : string;
  name : string;
  property_type : scalar_type;
  multiplicity : multiplicity;
}

type part_def = {
  id : string;
  name : string;
  type_id : string;
  multiplicity : multiplicity;
}

type block = {
  id : string;
  name : string;
  supertypes : string list;
  parts : part_def list;
  value_properties : value_property list;
}

(* OML Polymorphic Variants *)

type oml_concept = [
  | `Concept of string * string (* id, name *)
  | `Relation of string * string * string * string (* id, name, source_id, target_id *)
  | `ScalarProperty of string * string * string * scalar_type (* id, name, domain_id, scalar_type *)
]

type oml_vocabulary = [
  | `Vocabulary of string * string * oml_concept list (* iri, prefix, concepts *)
]
