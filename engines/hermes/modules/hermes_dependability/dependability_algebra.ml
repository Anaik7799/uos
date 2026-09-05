type availability = Available | Unavailable_observed | Blocked | Indeterminate

type evidence_credit = Dependability_atlas.evidence_credit =
  | No_credit
  | Discovery_credit
  | Structural_credit
  | Differential_credit

type verdict =
  | Satisfied
  | Refuted
  | Evidence_unavailable
  | Not_executed
  | Verdict_indeterminate

type taint = Clean | Tainted
type criticality = int

type lifecycle = Declared | Admitted | Running | Terminal | Current | Stale
type coordinate = { level : string; path : string list }

type ooda_phase =
  | Observe of string
  | Orient of string
  | Decide of string
  | Act of string

type observation = {
  attempt_id : int;
  verdict : verdict;
  observation_digest : string;
}

type atlas_rollup = {
  row_ids : string list;
  maximum_source_credit : evidence_credit;
  maximum_projected_credit : evidence_credit;
}

type projected_topology = {
  topology_components : string list;
  topology_edges : (string * string * string * string) list;
}

let availability_rank = function
  | Available -> 3
  | Unavailable_observed -> 2
  | Blocked -> 1
  | Indeterminate -> 0

let meet_availability left right =
  if availability_rank left <= availability_rank right then left else right

let project_availability = function
  | Available -> Available
  | Unavailable_observed -> Unavailable_observed
  | Blocked -> Blocked
  | Indeterminate -> Indeterminate

let credit_rank = function
  | No_credit -> 0
  | Discovery_credit -> 1
  | Structural_credit -> 2
  | Differential_credit -> 3

let join_credit left right =
  if credit_rank left >= credit_rank right then left else right

let verdict_rank = function
  | Satisfied -> 0
  | Not_executed -> 1
  | Evidence_unavailable -> 2
  | Verdict_indeterminate -> 3
  | Refuted -> 4

let meet_verdict left right =
  if verdict_rank left >= verdict_rank right then left else right

let combine_taint left right =
  match left, right with
  | Clean, Clean -> Clean
  | Clean, Tainted | Tainted, Clean | Tainted, Tainted -> Tainted

let make_criticality value =
  if value < 0 || value > 100 then Error "criticality must be within 0..100"
  else Ok value

let criticality_value value = value
let max_criticality left right = if left >= right then left else right

let valid_segment segment =
  String.trim segment <> ""
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true
         | _ -> false)
       segment

let make_coordinate ~level ~path =
  if not (valid_segment level) then Error "coordinate level is invalid"
  else if path = [] || not (List.for_all valid_segment path) then
    Error "coordinate path must contain only nonempty stable segments"
  else Ok { level; path }

let rec is_prefix prefix values =
  match prefix, values with
  | [], _ -> true
  | _, [] -> false
  | left :: prefix_rest, right :: values_rest ->
      left = right && is_prefix prefix_rest values_rest

let refines ~parent ~child =
  parent.level = child.level && is_prefix parent.path child.path

let advance_lifecycle current requested =
  match current, requested with
  | Declared, Admitted
  | Admitted, Running
  | Running, Terminal
  | Terminal, Current
  | Current, Stale
  | Stale, Admitted -> Ok requested
  | left, right when left = right -> Ok current
  | _ -> Error "lifecycle transition is not admitted"

let compose_graph left right =
  let left_ids = List.map (fun (node : Dependability_graph.node) -> node.id) left in
  let right_ids = List.map (fun (node : Dependability_graph.node) -> node.id) right in
  match List.find_opt (fun id -> List.mem id right_ids) left_ids with
  | Some collision -> Error ("graph composition identity collision: " ^ collision)
  | None ->
      let composed = left @ right in
      if composed = [] then Ok []
      else
        match Dependability_graph.validate composed with
        | [] -> Ok composed
        | errors -> Error (String.concat "; " errors)

let is_hex_digit = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let valid_digest digest =
  String.length digest = 64 && String.for_all is_hex_digit digest

let make_observation ~attempt_id ~verdict ~observation_digest =
  if attempt_id < 0 then Error "attempt_id must be nonnegative"
  else if not (valid_digest observation_digest) then
    Error "observation_digest must be a SHA-256 identity"
  else Ok { attempt_id; verdict; observation_digest }

let normalize_observations ~expected_attempt_ids observations =
  let expected = List.sort Int.compare expected_attempt_ids in
  let actual_ids = List.map (fun observation -> observation.attempt_id) observations in
  if expected_attempt_ids = [] then Error "expected attempt identity set is empty"
  else if List.exists (fun id -> id < 0) expected_attempt_ids then
    Error "expected attempt identity is negative"
  else if List.length expected <> List.length (List.sort_uniq Int.compare expected) then
    Error "expected attempt identities are duplicated"
  else if List.length actual_ids <> List.length (List.sort_uniq Int.compare actual_ids) then
    Error "observation attempt identities are duplicated"
  else if List.sort Int.compare actual_ids <> expected then
    Error "observation attempt identities are incomplete or unknown"
  else if List.exists (fun observation -> not (valid_digest observation.observation_digest)) observations then
    Error "observation digest is malformed"
  else
    Ok
      (List.sort
         (fun left right -> Int.compare left.attempt_id right.attempt_id)
         observations)

let observations_equivalent ~expected_attempt_ids ~sequential ~parallel =
  match normalize_observations ~expected_attempt_ids sequential,
        normalize_observations ~expected_attempt_ids parallel with
  | Ok sequential, Ok parallel -> sequential = parallel
  | Error _, _ | _, Error _ -> false

let projection_preserves_credit rows =
  List.for_all
    (fun (row : Dependability_atlas.row) ->
      credit_rank row.projected_credit <= credit_rank row.source_credit)
    rows

let rollup_atlas rows =
  List.fold_left
    (fun rollup (row : Dependability_atlas.row) ->
      { row_ids = row.row_id :: rollup.row_ids;
        maximum_source_credit = join_credit rollup.maximum_source_credit row.source_credit;
        maximum_projected_credit =
          join_credit rollup.maximum_projected_credit row.projected_credit })
    { row_ids = []; maximum_source_credit = No_credit;
      maximum_projected_credit = No_credit }
    rows
  |> fun rollup ->
  { rollup with row_ids = List.sort_uniq String.compare rollup.row_ids }

let drill_down_atlas rollup rows =
  List.filter
    (fun (row : Dependability_atlas.row) -> List.mem row.row_id rollup.row_ids)
    rows

let rollup_roundtrip rows =
  let row_ids = List.map (fun (row : Dependability_atlas.row) -> row.row_id) rows in
  List.length row_ids = List.length (List.sort_uniq String.compare row_ids)
  && drill_down_atlas (rollup_atlas rows) rows = rows

let topology_is_closed topology =
  let components = List.sort String.compare topology.topology_components in
  let edges = List.sort compare topology.topology_edges in
  components <> [] && edges <> []
  && List.for_all (fun component -> String.trim component <> "") components
  && List.length components = List.length (List.sort_uniq String.compare components)
  && List.length edges = List.length (List.sort_uniq compare edges)
  && List.for_all
       (fun (from_component, from_port, to_component, to_port) ->
         List.mem from_component components && List.mem to_component components
         && String.trim from_port <> "" && String.trim to_port <> "")
       edges

let canonical_topology topology =
  ( List.sort String.compare topology.topology_components,
    List.sort compare topology.topology_edges )

let graph_fpp_topology_agreement ~graph ~atlas ~authority ~projection =
  let graph_ids = List.map (fun (node : Dependability_graph.node) -> node.id) graph in
  let referenced_units =
    atlas |> List.concat_map (fun (row : Dependability_atlas.row) -> row.graph_units)
    |> List.sort_uniq String.compare
  in
  let referenced_components =
    atlas |> List.concat_map (fun (row : Dependability_atlas.row) -> row.fpp_elements)
    |> List.sort_uniq String.compare
  in
  graph <> [] && atlas <> [] && Dependability_graph.validate graph = []
  && topology_is_closed authority && topology_is_closed projection
  && canonical_topology authority = canonical_topology projection
  && List.for_all (fun id -> List.mem id graph_ids) referenced_units
  && List.for_all
       (fun component -> List.mem component referenced_components)
       authority.topology_components
  && List.for_all
       (fun (row : Dependability_atlas.row) ->
         row.graph_units <> [] && row.fpp_elements <> []
         && List.exists
              (fun component -> List.mem component authority.topology_components)
              row.fpp_elements)
       atlas

let taint_closure ~edges seeds =
  let edges = List.sort_uniq compare edges in
  let rec fixpoint known =
    let expanded =
      List.fold_left
        (fun values (source, dependent) ->
          if List.mem source values then dependent :: values else values)
        known edges
      |> List.sort_uniq String.compare
    in
    if expanded = known then known else fixpoint expanded
  in
  seeds |> List.sort_uniq String.compare |> fixpoint

let closes_ooda = function
  | [ Observe before; Orient oriented; Decide decision; Act receipt;
      Observe observed_receipt ] ->
      String.trim before <> "" && String.trim oriented <> ""
      && String.trim decision <> "" && String.trim receipt <> ""
      && receipt = observed_receipt
  | _ -> false

let atlas_homomorphism ~ontology ~atlas =
  let ontology_ids =
    List.map (fun (node : Dependability_ontology.node) -> node.id) ontology
  in
  let row_ids = List.map (fun (row : Dependability_atlas.row) -> row.row_id) atlas in
  let unique values =
    List.length values = List.length (List.sort_uniq String.compare values)
  in
  let ontology_applies target (node : Dependability_ontology.node) =
    match node.applicability with
    | Dependability_ontology.Framework_wide -> true
    | Dependability_ontology.Targets targets -> List.mem target targets
  in
  let row_preserves (row : Dependability_atlas.row) =
    match
      List.find_opt
        (fun (node : Dependability_ontology.node) -> node.id = row.ontology_id)
        ontology
    with
    | None -> false
    | Some node ->
        node.coordinate = row.coordinate && ontology_applies row.target node
        && List.for_all (fun metric -> List.mem metric node.metric_ids) row.metric_ids
  in
  let capability_is_total (node : Dependability_ontology.node) =
    match node.scale, node.applicability with
    | (Dependability_ontology.Framework | Dependability_ontology.Target), _ -> true
    | Dependability_ontology.Capability, Dependability_ontology.Framework_wide ->
        List.exists (fun (row : Dependability_atlas.row) -> row.ontology_id = node.id) atlas
    | Dependability_ontology.Capability, Dependability_ontology.Targets targets ->
        List.for_all
          (fun target ->
            List.exists
              (fun (row : Dependability_atlas.row) ->
                row.ontology_id = node.id && row.target = target)
              atlas)
          targets
  in
  unique ontology_ids && unique row_ids
  && List.for_all row_preserves atlas
  && List.for_all capability_is_total ontology
