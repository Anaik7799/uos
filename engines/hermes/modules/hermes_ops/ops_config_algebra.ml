type resolution = Supplied | Defaulted | Optional_unavailable | Required_blocked
type completion = Unmapped | Verified | Partial | Blocked

let resolve ~present necessity =
  if present then Supplied
  else
    match necessity with
    | Ops_config.Required -> Required_blocked
    | Optional_flag -> Optional_unavailable
    | Override -> Defaulted

let completion_of_resolution = function
  | Supplied | Defaulted -> Verified
  | Optional_unavailable -> Partial
  | Required_blocked -> Blocked

let rank = function Unmapped -> 0 | Verified -> 1 | Partial -> 2 | Blocked -> 3

let completion_of_rank = function
  | 0 -> Unmapped
  | 1 -> Verified
  | 2 -> Partial
  | _ -> Blocked

let combine left right = completion_of_rank (max (rank left) (rank right))
let roll_up values = List.fold_left combine Unmapped values

let schema_id = Ops_config.schema_id
let declaration_digest = Ops_config.declaration_digest_of

let valid_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let binds_execution_intent ~configuration_digest ~context_configuration_digest =
  valid_digest configuration_digest
  && String.equal configuration_digest context_configuration_digest

let ( let* ) value continuation =
  match value with Ok result -> continuation result | Error _ as error -> error

let validate () =
  let* () = Ops_config_ontology.validate () in
  let* () = Ops_config_atlas.validate () in
  let values = [ Unmapped; Verified; Partial; Blocked ] in
  let associative =
    List.for_all
      (fun left ->
        List.for_all
          (fun middle ->
            List.for_all
              (fun right ->
                combine (combine left middle) right
                = combine left (combine middle right))
              values)
          values)
      values
  in
  let commutative =
    List.for_all
      (fun left -> List.for_all (fun right -> combine left right = combine right left) values)
      values
  in
  let idempotent = List.for_all (fun value -> combine value value = value) values in
  let digest = declaration_digest Ops_config.elements in
  if not associative then Error "configuration completion join is not associative"
  else if not commutative then Error "configuration completion join is not commutative"
  else if not idempotent then Error "configuration completion join is not idempotent"
  else if roll_up [] <> Unmapped then Error "empty configuration roll-up is not Unmapped"
  else if not (valid_digest digest) then Error "configuration declaration digest is invalid"
  else if not (String.equal digest Ops_config.declaration_digest)
  then Error "configuration declaration digest projection drifted"
  else if not (String.equal schema_id Ops_config.schema_id)
  then Error "configuration schema identity projection drifted"
  else Ok ()
