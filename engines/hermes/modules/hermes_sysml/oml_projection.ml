open Sysml_types

let escape_string s = s

let scalar_type_to_ttl = function
  | Real -> "xsd:double"
  | Integer -> "xsd:integer"
  | String -> "xsd:string"
  | Boolean -> "xsd:boolean"
  | Custom s -> ":" ^ s

let scalar_type_to_owl = function
  | Real -> "&xsd;double"
  | Integer -> "&xsd;integer"
  | String -> "&xsd;string"
  | Boolean -> "&xsd;boolean"
  | Custom s -> "#" ^ s

let multiplicity_to_ttl = function
  | Single -> "1"
  | Optional -> "0..1"
  | Collection -> "0..*"

let value_property_to_ttl block_id (vp : value_property) =
  Printf.sprintf ":%s a owl:DatatypeProperty ;\n  rdfs:label \"%s\" ;\n  rdfs:domain :%s ;\n  rdfs:range %s .\n"
    vp.id (escape_string vp.name) block_id (scalar_type_to_ttl vp.property_type)

let part_def_to_ttl block_id (part : part_def) =
  Printf.sprintf ":%s a owl:ObjectProperty ;\n  rdfs:label \"%s\" ;\n  rdfs:domain :%s ;\n  rdfs:range :%s .\n"
    part.id (escape_string part.name) block_id part.type_id

let block_to_ttl (block : block) =
  let b = Printf.sprintf ":%s a owl:Class ;\n" block.id in
  let b = b ^ Printf.sprintf "  rdfs:label \"%s\" " (escape_string block.name) in
  let supertypes = 
    if block.supertypes = [] then ""
    else 
      let st = List.map (fun s -> Printf.sprintf ":%s" s) block.supertypes |> String.concat ", " in
      Printf.sprintf ";\n  rdfs:subClassOf %s " st
  in
  let b = b ^ supertypes ^ ".\n\n" in
  let vps = List.map (value_property_to_ttl block.id) block.value_properties |> String.concat "\n" in
  let parts = List.map (part_def_to_ttl block.id) block.parts |> String.concat "\n" in
  b ^ vps ^ (if vps = "" then "" else "\n") ^ parts ^ (if parts = "" then "" else "\n")

let project_to_ttl (blocks : block list) =
  let prefix = "@prefix : <http://example.org/sysml#> .\n@prefix owl: <http://www.w3.org/2002/07/owl#> .\n@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n" in
  let body = List.map block_to_ttl blocks |> String.concat "" in
  prefix ^ body

let value_property_to_owl block_id (vp : value_property) =
  Printf.sprintf "  <owl:DatatypeProperty rdf:about=\"#%s\">\n    <rdfs:label>%s</rdfs:label>\n    <rdfs:domain rdf:resource=\"#%s\"/>\n    <rdfs:range rdf:resource=\"%s\"/>\n  </owl:DatatypeProperty>\n"
    vp.id (escape_string vp.name) block_id (scalar_type_to_owl vp.property_type)

let part_def_to_owl block_id (part : part_def) =
  Printf.sprintf "  <owl:ObjectProperty rdf:about=\"#%s\">\n    <rdfs:label>%s</rdfs:label>\n    <rdfs:domain rdf:resource=\"#%s\"/>\n    <rdfs:range rdf:resource=\"#%s\"/>\n  </owl:ObjectProperty>\n"
    part.id (escape_string part.name) block_id part.type_id

let block_to_owl (block : block) =
  let b = Printf.sprintf "  <owl:Class rdf:about=\"#%s\">\n" block.id in
  let b = b ^ Printf.sprintf "    <rdfs:label>%s</rdfs:label>\n" (escape_string block.name) in
  let supertypes = 
    List.map (fun s -> Printf.sprintf "    <rdfs:subClassOf rdf:resource=\"#%s\"/>\n" s) block.supertypes
    |> String.concat ""
  in
  let b = b ^ supertypes ^ "  </owl:Class>\n" in
  let vps = List.map (value_property_to_owl block.id) block.value_properties |> String.concat "" in
  let parts = List.map (part_def_to_owl block.id) block.parts |> String.concat "" in
  b ^ vps ^ parts

let project_to_owl (blocks : block list) =
  let header = "<?xml version=\"1.0\"?>\n<!DOCTYPE rdf:RDF [\n    <!ENTITY xsd \"http://www.w3.org/2001/XMLSchema#\" >\n]>\n<rdf:RDF xmlns=\"http://example.org/sysml#\"\n     xml:base=\"http://example.org/sysml\"\n     xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"\n     xmlns:owl=\"http://www.w3.org/2002/07/owl#\"\n     xmlns:rdfs=\"http://www.w3.org/2000/01/rdf-schema#\">\n\n" in
  let body = List.map block_to_owl blocks |> String.concat "\n" in
  let footer = "</rdf:RDF>\n" in
  header ^ body ^ footer
