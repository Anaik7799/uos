(* Schema backfill — the converge loop's pure core. See backfill.mli.
   The rule everywhere: evidence or Ask, never a guess. *)

type evidence =
  | From_type of string
  | From_status of string
  | From_git of string
  | From_tags of string list
  | From_group of string

type proposal =
  | Set of { field : string; value : string; evidence : evidence }
  | Ask of { field : string; why : string }

type page_facts = {
  slug : string;
  group : string;
  authored : string list;  (* keys the DOCUMENT carries — see the mli *)
  ntype : string;
  status : string;
  tags : string list;
  first_add : string option;
  missing : string list;
}

let field_order = [ "ktype"; "maturity"; "domain"; "topics"; "created" ]

(* the spec §3 two-axis mapping, discourse type -> ktype *)
let ktype_of_ntype = function
  | "reference" -> Some "source"
  | "journal" -> Some "journal"
  | "note" | "claim" | "evidence" | "question" | "decision" -> Some "atomic"
  | _ -> None

(* maturity is proposed conservatively: evergreen is EARNED, never proposed *)
let maturity_of_status = function
  | "draft" -> Some "seed"
  | "published" -> Some "incubating"
  | "archived" -> Some "archived"
  | _ -> None

let propose_field f facts =
  match f with
  | "ktype" -> (
      (* the key must be AUTHORED: meta_of defaults type to "note", and a
         default cited as evidence is manufactured provenance *)
      match if List.mem "type" facts.authored then ktype_of_ntype facts.ntype else None with
      | Some v -> Set { field = f; value = v; evidence = From_type facts.ntype }
      | None ->
          Ask { field = f; why = "no discourse type to map (spec §3 axis)" })
  | "maturity" -> (
      match
        if List.mem "status" facts.authored then maturity_of_status facts.status else None
      with
      | Some v -> Set { field = f; value = v; evidence = From_status facts.status }
      | None -> Ask { field = f; why = "no status to map; evergreen is never proposed" })
  (* DOMAIN IS ALWAYS AN ASK. The group was offered as evidence and is
     not: a directory is a LOCATION, the domain is a SUBJECT drawn from a
     closed vocabulary, and the two coincide nowhere in this corpus —
     every human-authored value disagreed with the group. Proposing it
     would have written path fragments into a controlled field, which is
     the exact confusion "evidence or Ask" exists to prevent. *)
  | "domain" ->
      Ask
        { field = f;
          why =
            "domain is a controlled vocabulary (spec section 3); a directory group is a \
             location, not a subject — an author must choose" }
  | "topics" ->
      if facts.tags = [] then Ask { field = f; why = "the page carries no #tags" }
      else
        Set
          {
            field = f;
            value = "[" ^ String.concat ", " facts.tags ^ "]";
            evidence = From_tags facts.tags;
          }
  | "created" -> (
      match facts.first_add with
      | Some d -> Set { field = f; value = d; evidence = From_git d }
      | None -> Ask { field = f; why = "no git first-add date supplied (R16: never invented)" })
  | other -> Ask { field = other; why = "not one of the five required fields" }

let propose facts =
  List.filter_map
    (fun f -> if List.mem f facts.missing then Some (propose_field f facts) else None)
    field_order

let show_evidence = function
  | From_type t -> "type: " ^ t
  | From_status s -> "status: " ^ s
  | From_git d -> "git first-add " ^ d
  | From_tags ts -> "#" ^ String.concat " #" ts
  | From_group g -> "group " ^ g

let render ~slug = function
  | Set { field; value; evidence } ->
      Printf.sprintf "%-40s SET %-9s = %-24s (%s)" slug field value (show_evidence evidence)
  | Ask { field; why } -> Printf.sprintf "%-40s ASK %-9s — %s" slug field why
