open Sysml_types

type harness_concept =
  | Component of string * string
  | Interface of string * string
  | Port of string * string

type harness_relation =
  | Connects of string * string * string * string
  | Contains of string * string * string * string

type harness_property =
  | ScalarProperty of string * string * string * scalar_type (* id, name, domain_id, type *)

type harness_element =
  | Concept of harness_concept
  | Relation of harness_relation
  | Property of harness_property

let to_oml_concept : harness_element -> oml_concept = function
  | Concept (Component (id, name)) -> `Concept (id, "Component:" ^ name)
  | Concept (Interface (id, name)) -> `Concept (id, "Interface:" ^ name)
  | Concept (Port (id, name)) -> `Concept (id, "Port:" ^ name)
  | Relation (Connects (id, name, src, tgt)) -> `Relation (id, "Connects:" ^ name, src, tgt)
  | Relation (Contains (id, name, src, tgt)) -> `Relation (id, "Contains:" ^ name, src, tgt)
  | Property (ScalarProperty (id, name, domain, t)) -> `ScalarProperty (id, "ScalarProperty:" ^ name, domain, t)

let harness_vocabulary iri prefix elements : oml_vocabulary =
  let concepts = List.map to_oml_concept elements in
  `Vocabulary (iri, prefix, concepts)
