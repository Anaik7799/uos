(* See atlas_algebra.mli for why this exists and why it is pure. *)

type structure =
  | Intent_composition
  | Independent_operations
  | Capability_refinement
  | Authority_constraints
  | Evidence_refinement
  | State_projection
  | Replication
  | Release_migration
  | Resource_accounting

let all_structures =
  [ Intent_composition; Independent_operations; Capability_refinement;
    Authority_constraints; Evidence_refinement; State_projection;
    Replication; Release_migration; Resource_accounting ]

let structure_name = function
  | Intent_composition -> "intent_composition"
  | Independent_operations -> "independent_operations"
  | Capability_refinement -> "capability_refinement"
  | Authority_constraints -> "authority_constraints"
  | Evidence_refinement -> "evidence_refinement"
  | State_projection -> "state_projection"
  | Replication -> "replication"
  | Release_migration -> "release_migration"
  | Resource_accounting -> "resource_accounting"

(* Verbatim from formal spec section 3's "Required law" column. Kept here so a
   drift between spec and checker is a source diff, not a silent divergence. *)
let required_law = function
  | Intent_composition -> "identity and associativity"
  | Independent_operations ->
      "commute only with proven disjoint effects and compatible budgets"
  | Capability_refinement ->
      "implementations preserve the declared input/output relation"
  | Authority_constraints -> "intersection; denial dominates"
  | Evidence_refinement ->
      "UNKNOWN never becomes PASS without new applicable evidence"
  | State_projection -> "each projection preserves declared invariants"
  | Replication ->
      "replay of a committed prefix yields equivalent recoverable state"
  | Release_migration ->
      "candidate-bound relation between old and new state schemas"
  | Resource_accounting ->
      "nonnegative conserved reservations; serialized admission"

type obligation_status =
  | Holds
  | Not_applicable
  | Unknown
  | Violated

let status_name = function
  | Holds -> "HOLDS"
  | Not_applicable -> "NOT_APPLICABLE"
  | Unknown -> "UNKNOWN"
  | Violated -> "VIOLATED"

type obligation = {
  structure : structure;
  status : obligation_status;
  predicate : string;
  falsifier : string;
  oracle : string;
  independently_reviewed : bool;
}

type finding = {
  row_id : string;
  detail : string;
}

type verdict =
  | Conforms
  | Nonconforming of finding list

(* Conforms is the identity; Nonconforming absorbs. Findings concatenate in
   argument order so a report reads in the order the checks ran. *)
let meet a b =
  match a, b with
  | Conforms, v -> v
  | v, Conforms -> v
  | Nonconforming xs, Nonconforming ys -> Nonconforming (xs @ ys)

let meet_all vs = List.fold_left meet Conforms vs

let findings = function Conforms -> [] | Nonconforming fs -> fs
let is_conforming = function Conforms -> true | Nonconforming _ -> false

let fail row_id detail = Nonconforming [ { row_id; detail } ]

let blank s = String.trim s = ""

let check_obligation ~row_id o =
  let n = structure_name o.structure in
  match o.status with
  | Holds ->
      let a =
        if blank o.predicate then
          fail row_id (n ^ ": HOLDS with an empty predicate")
        else Conforms
      in
      let b =
        if blank o.falsifier then
          fail row_id
            (n
           ^ ": HOLDS with no falsifier -- an unfalsifiable pass is decoration, \
              not evidence")
        else Conforms
      in
      let d =
        if blank o.oracle then
          fail row_id
            (n
           ^ ": HOLDS with no oracle -- nothing in the repository would notice \
              if this stopped being true")
        else Conforms
      in
      let c =
        if not o.independently_reviewed then
          fail row_id
            (n
           ^ ": HOLDS but not independently reviewed -- a value derived \
              mechanically from the row's other fields cannot assert its own \
              pass")
        else Conforms
      in
      meet_all [ a; b; d; c ]
  | Violated ->
      if blank o.predicate then
        fail row_id (n ^ ": VIOLATED with an empty predicate -- say what failed")
      else Conforms
  | Not_applicable ->
      if blank o.predicate then
        fail row_id
          (n ^ ": NOT_APPLICABLE with no reason -- say why it cannot apply")
      else Conforms
  (* Not knowing is always well formed. This is the point: the type makes
     honesty free and claiming expensive. *)
  | Unknown -> Conforms

let check_row ~row_id obligations =
  let count s =
    List.length
      (List.filter (fun o -> o.structure = s) obligations)
  in
  let coverage =
    List.map
      (fun s ->
        match count s with
        | 1 -> Conforms
        | 0 ->
            fail row_id
              ("missing structure " ^ structure_name s ^ " (required law: "
             ^ required_law s ^ ")")
        | k ->
            fail row_id
              (Printf.sprintf "structure %s declared %d times; exactly one \
                               obligation per structure"
                 (structure_name s) k))
      all_structures
  in
  let wellformed =
    List.map (fun o -> check_obligation ~row_id o) obligations
  in
  meet_all (coverage @ wellformed)

let check_degeneracy ~total_rows ~max_repeat repeats =
  meet_all
    (List.map
       (fun (field, n) ->
         if n > max_repeat then
           fail "<atlas>"
             (Printf.sprintf
                "field %s carries one identical value on %d of %d rows (ceiling \
                 %d) -- a constant wearing a schema records nothing per row"
                field n total_rows max_repeat)
         else Conforms)
       repeats)

(* Adding a row that shares the existing value can only increase the count.
   Trivial as code; it exists so the law suite can state the property that makes
   the degeneracy check sound as the atlas grows. *)
let repeat_after_adding_same n = n + 1
