(* The MBSE spine — see feature_model.mli for the laws. *)

open Hermes_sysml

type verification = Probe | Declared

type element = {
  mid : string;
  feature_id : string;
  package : string;
  name : string;
  requirement : string;
  satisfied_after : string list;
  verification : verification;
  status : string;
}

(* A model id must be stable across renames and legal in all three
   surfaces at once — SysML v2 identifiers, OWL fragment names and MMS
   element ids share only [A-Za-z0-9_]. Deriving it from the feature id
   rather than the display name is what makes it stable: a feature may be
   renamed, but HW.3.5.2 is HW.3.5.2 forever. *)
let sanitize s =
  String.map (fun c -> if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                          || (c >= '0' && c <= '9') then c else '_') s

let mid_of id = "HWF_" ^ sanitize id

let package_of (a : Feature_register.area) =
  match a with
  | Feature_register.Corpus -> "Corpus"
  | Feature_register.Dialect -> "Dialect"
  | Feature_register.Address -> "Address"
  | Feature_register.Graph -> "Graph"
  | Feature_register.Query -> "Query"
  | Feature_register.Surface -> "Surface"
  | Feature_register.Present -> "Present"
  | Feature_register.Lifecycle -> "Lifecycle"
  | Feature_register.Source -> "Source"
  | Feature_register.Build -> "Build"

let packages =
  [ Feature_register.Corpus; Feature_register.Dialect; Feature_register.Address;
    Feature_register.Graph; Feature_register.Query; Feature_register.Surface;
    Feature_register.Present; Feature_register.Lifecycle; Feature_register.Source;
    Feature_register.Build ]

let element_of (f : Feature_register.feature) =
  { mid = mid_of f.Feature_register.id;
    feature_id = f.Feature_register.id;
    package = package_of f.Feature_register.area;
    name = f.Feature_register.name;
    requirement = f.Feature_register.law;
    satisfied_after = List.sort_uniq compare f.Feature_register.gates;
    (* the register's own probe IS the verification method; a row with
       none is verified by assertion, which is the gap *)
    verification = (match f.Feature_register.derived with Some _ -> Probe | None -> Declared);
    status = Feature_register.readiness_name (Feature_register.status f) }

let elements () =
  Feature_register.features
  |> List.map element_of
  |> List.sort (fun a b -> compare a.feature_id b.feature_id)

(* ---------------------------------------------------------- escaping

   Each surface has its own forbidden characters, and a law text is
   authored prose containing quotes, angle brackets and backslashes. The
   shared emitter in hermes_sysml has no escaping at all, so every
   surface here does its own rather than assume. *)

let escape_quoted s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> ()
      | '\t' -> Buffer.add_string b "\\t"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

(* ------------------------------------------------------- SysML v2 *)

let sysml_part e =
  let b = Buffer.create 512 in
  Buffer.add_string b (Printf.sprintf "    part def %s {\n" e.mid);
  Buffer.add_string b (Printf.sprintf "      doc /* %s */\n" (escape_quoted e.name));
  Buffer.add_string b
    (Printf.sprintf "      attribute featureId : String = \"%s\";\n" (escape_quoted e.feature_id));
  Buffer.add_string b
    (Printf.sprintf "      attribute status : String = \"%s\";\n" (escape_quoted e.status));
  Buffer.add_string b
    (Printf.sprintf "      attribute verification : String = \"%s\";\n"
       (match e.verification with Probe -> "probe" | Declared -> "declared"));
  Buffer.add_string b
    (Printf.sprintf "      requirement %s_req { doc /* %s */ }\n" e.mid (escape_quoted e.requirement));
  List.iter
    (fun g -> Buffer.add_string b (Printf.sprintf "      dependency from %s to %s;\n" e.mid (mid_of g)))
    e.satisfied_after;
  Buffer.add_string b "    }\n";
  Buffer.contents b

let sysml_v2 () =
  let es = elements () in
  let b = Buffer.create 65536 in
  Buffer.add_string b
    "// GENERATED from Feature_register — the model of record.\n\
     // Do not edit: edit the register and regenerate, or the model and the\n\
     // code disagree and the model is the one nobody believes.\n\n\
     package HermesWiki {\n";
  List.iter
    (fun a ->
      let pkg = package_of a in
      let mine = List.filter (fun e -> e.package = pkg) es in
      if mine <> [] then begin
        Buffer.add_string b (Printf.sprintf "\n  package %s {\n" pkg);
        List.iter (fun e -> Buffer.add_string b (sysml_part e)) mine;
        Buffer.add_string b "  }\n"
      end)
    packages;
  Buffer.add_string b "}\n";
  Buffer.contents b

(* ----------------------------------------------------------- OML *)

let oml_vocabulary () =
  let es = elements () in
  let package_concepts =
    List.map
      (fun a ->
        let p = package_of a in
        `Concept ("HWA_" ^ p, p ^ " area"))
      packages
  in
  let feature_concepts = List.map (fun e -> `Concept (e.mid, e.name)) es in
  let classification =
    List.map
      (fun e -> `Relation (e.mid ^ "_inArea", "inArea", e.mid, "HWA_" ^ e.package))
      es
  in
  let dependencies =
    List.concat_map
      (fun e ->
        List.map
          (fun g -> `Relation (e.mid ^ "_after_" ^ mid_of g, "satisfiedAfter", e.mid, mid_of g))
          e.satisfied_after)
      es
  in
  let properties =
    List.concat_map
      (fun e ->
        [ `ScalarProperty (e.mid ^ "_status", "status", e.mid, Sysml_types.String);
          `ScalarProperty (e.mid ^ "_verification", "verification", e.mid, Sysml_types.String) ])
      es
  in
  `Vocabulary
    ( "http://hermes.local/wiki/features#", "hwf",
      package_concepts @ feature_concepts @ classification @ dependencies @ properties )

let blocks () =
  let es = elements () in
  let area_blocks =
    List.map
      (fun a ->
        let p = package_of a in
        { Sysml_types.id = "HWA_" ^ p; name = p ^ " area"; supertypes = [];
          parts = []; value_properties = [] })
      packages
  in
  let feature_blocks =
    List.map
      (fun e ->
        { Sysml_types.id = e.mid; name = e.name;
          (* the area is a SUPERTYPE, not a field: it is what the feature
             IS, and subsumption is the whole reason to have an ontology *)
          supertypes = [ "HWA_" ^ e.package ];
          parts =
            List.map
              (fun g ->
                { Sysml_types.id = e.mid ^ "_after_" ^ mid_of g; name = "satisfiedAfter";
                  type_id = mid_of g; multiplicity = Sysml_types.Single })
              e.satisfied_after;
          value_properties =
            [ { Sysml_types.id = e.mid ^ "_status"; name = "status";
                property_type = Sysml_types.String; multiplicity = Sysml_types.Single };
              { Sysml_types.id = e.mid ^ "_verification"; name = "verification";
                property_type = Sysml_types.String; multiplicity = Sysml_types.Single } ] })
      es
  in
  area_blocks @ feature_blocks

let oml_ttl () = Oml_projection.project_to_ttl (blocks ())

(* -------------------------------------------------- OpenMBEE / MMS *)

(* MMS stores elements flat with an ownerId, so the area packages are
   emitted first and every feature is owned by its area. The payload is
   sorted and carries no timestamps: two runs over an unchanged register
   must produce byte-identical JSON, or every push looks like a change. *)
let field k v = Printf.sprintf "\"%s\":\"%s\"" k (escape_quoted v)

let mms_element e =
  Printf.sprintf "  {%s,%s,%s,%s,%s,%s,%s}" (field "id" e.mid) (field "type" "Class")
    (field "name" e.name)
    (field "ownerId" ("HWA_" ^ e.package))
    (field "documentation" e.requirement)
    (field "featureId" e.feature_id) (field "status" e.status)

let mms_json () =
  let es = elements () in
  let b = Buffer.create 65536 in
  Buffer.add_string b "{\"elements\":[\n";
  let rows =
    List.map
      (fun a ->
        let p = package_of a in
        Printf.sprintf "  {%s,%s,%s,%s}"
          (field "id" ("HWA_" ^ p)) (field "type" "Package") (field "name" (p ^ " area"))
          (field "ownerId" "HermesWiki"))
      packages
    @ List.map mms_element es
    @ List.concat_map
        (fun e ->
          List.map
            (fun g ->
              Printf.sprintf "  {%s,%s,%s,%s,%s}"
                (field "id" (e.mid ^ "_after_" ^ mid_of g))
                (field "type" "Dependency") (field "ownerId" e.mid)
                (field "sourceId" e.mid) (field "targetId" (mid_of g)))
            e.satisfied_after)
        es
  in
  Buffer.add_string b (String.concat ",\n" rows);
  Buffer.add_string b "\n]}\n";
  Buffer.contents b

(* ------------------------------------------------------------ gate *)

let model_gaps () =
  elements ()
  |> List.filter (fun e -> e.status = "built" && e.verification = Declared)
  |> List.map (fun e ->
         Printf.sprintf "%s (%s): built, but the model carries no verification method"
           e.feature_id e.name)
  |> List.sort compare

let dangling_dependencies () =
  let known = List.map (fun e -> e.feature_id) (elements ()) in
  elements ()
  |> List.concat_map (fun e ->
         List.filter_map
           (fun g ->
             if List.mem g known then None
             else Some (Printf.sprintf "%s depends on %s, which the model does not contain"
                          e.feature_id g))
           e.satisfied_after)
  |> List.sort_uniq compare

type coverage = { total : int; verified : int; declared_only : int; built : int }

let coverage () =
  let es = elements () in
  let built = List.filter (fun e -> e.status = "built") es in
  { total = List.length es;
    verified = List.length (List.filter (fun e -> e.verification = Probe) es);
    declared_only = List.length (List.filter (fun e -> e.verification = Declared) built);
    built = List.length built }
