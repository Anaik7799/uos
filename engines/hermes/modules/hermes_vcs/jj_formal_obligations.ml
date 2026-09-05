type availability = Credited | Unavailable_observed
type credit_limit = No_formal_or_parity_credit

type obligation = {
  obligation_id : string;
  law_id : string;
  statement : string;
  negative_control_id : string;
  availability : availability;
  credit_limit : credit_limit;
}

let schema_id = "hermes.jj-formal-obligations.v1"

let obligation_of_law law =
  let law_id = Jj_algebra.law_id law in
  { obligation_id = "formal." ^ law_id;
    law_id;
    statement = Jj_algebra.law_statement law;
    negative_control_id = Jj_algebra.law_negative_control_id law;
    availability = Unavailable_observed;
    credit_limit = No_formal_or_parity_credit }

let obligations = List.map obligation_of_law Jj_algebra.laws

let obligation_id value = value.obligation_id
let law_id value = value.law_id
let statement value = value.statement
let negative_control_id value = value.negative_control_id
let availability value = value.availability
let credit_limit value = value.credit_limit

let unique values =
  List.length values = List.length (List.sort_uniq String.compare values)

let expected_rows () = List.map obligation_of_law Jj_algebra.laws

let validate_obligations rows =
  let gaps = ref [] in
  let add gap = gaps := gap :: !gaps in
  let expected = expected_rows () in
  if rows = [] then add "formal obligation denominator is empty";
  if List.map law_id rows <> List.map law_id expected then
    add "formal obligation denominator or order differs from the algebra";
  if not (unique (List.map obligation_id rows)) then
    add "formal obligation identities are not injective";
  if not (unique (List.map negative_control_id rows)) then
    add "formal negative-control identities are not injective";
  List.iter
    (fun row ->
      if String.trim row.obligation_id = ""
         || String.trim row.law_id = ""
         || String.trim row.statement = ""
      then add ("formal obligation has an empty field: " ^ row.law_id);
      if
        not
          (String.equal row.obligation_id ("formal." ^ row.law_id))
      then add ("formal obligation identity differs: " ^ row.law_id);
      if
        not
          (String.equal row.negative_control_id ("mutant." ^ row.law_id))
      then add ("formal negative control differs: " ^ row.law_id);
      if row.availability <> Unavailable_observed then
        add ("formal credit has no receipt: " ^ row.law_id);
      if row.credit_limit <> No_formal_or_parity_credit then
        add ("formal credit limit differs: " ^ row.law_id))
    rows;
  if rows <> expected then add "formal obligations differ from canonical derivation";
  List.rev !gaps

let validate () = validate_obligations obligations

let availability_key = function
  | Credited -> "credited"
  | Unavailable_observed -> "unavailable-observed"

let credit_limit_key = function
  | No_formal_or_parity_credit -> "no-formal-or-parity-credit"

let source_digest =
  let rows =
    obligations
    |> List.map (fun row ->
         Jj_id.length_frame
           [ row.obligation_id; row.law_id; row.statement;
             row.negative_control_id; availability_key row.availability;
             credit_limit_key row.credit_limit ])
  in
  Jj_id.length_frame (schema_id :: rows)
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

module For_test = struct
  type mutation =
    | Drop_obligation
    | Duplicate_obligation
    | Drop_negative_control
    | Invent_credit
    | Reorder_obligations

  let validate_with_mutation mutation =
    let mutated =
      match mutation, obligations with
      | Drop_obligation, _ :: rest -> rest
      | Drop_obligation, [] -> []
      | Duplicate_obligation, row :: _ -> row :: obligations
      | Duplicate_obligation, [] -> []
      | Drop_negative_control, row :: rest ->
          { row with negative_control_id = "" } :: rest
      | Drop_negative_control, [] -> []
      | Invent_credit, row :: rest ->
          { row with availability = Credited } :: rest
      | Invent_credit, [] -> []
      | Reorder_obligations, _ -> List.rev obligations
    in
    validate_obligations mutated
end
