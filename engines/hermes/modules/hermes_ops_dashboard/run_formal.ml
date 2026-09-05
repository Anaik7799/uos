type result = Sat | Unsat | Unknown | Timeout | Unavailable
type kind = Negated_law | False_control
type obligation = { stable_id : string; requirement_id : string; kind : kind;
  statement : string; smt2 : string; expected : result; solver_id : string;
  solver_version_constraint : string; timeout_ms : int; query_digest : string }

let digest_query query =
  query |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let contains text needle =
  let width = String.length needle and length = String.length text in
  let rec loop index =
    index + width <= length
    && (String.sub text index width = needle || loop (index + 1))
  in
  width > 0 && loop 0

let make ~stable_id ~requirement_id ~kind ~statement ~smt2 ~expected =
  { stable_id; requirement_id; kind; statement; smt2; expected;
    solver_id = "z3"; solver_version_constraint = ">=4.12,<5";
    timeout_ms = 5_000; query_digest = digest_query smt2 }

let obligations =
  List.map
    (fun (item : Run_formal_relation.query) ->
      let kind, expected =
        match item.polarity with
        | Run_formal_relation.Negated_law -> (Negated_law, Unsat)
        | Run_formal_relation.Fact_mutant_control _ -> (False_control, Sat)
      in
      make ~stable_id:item.stable_id ~requirement_id:item.requirement_id ~kind
        ~statement:item.statement ~smt2:item.smt2 ~expected)
    Run_formal_relation.canonical

(* The formal-nonvacuity requirement verifies this registry and therefore is
   not recursively encoded as a law about itself.  These are the seven model
   laws.  Each negation must occur exactly once; each law carries at least one
   fact-mutant control, and a law whose original formula was too weak carries
   several (REQ-OPS-ID-WINDOWS has eight, HZ-SQL-FIN-01 has thirteen). *)
let formal_requirement_ids =
  [ "REQ-OPS-FPP-VALID"; "REQ-OPS-METRIC-TOTAL"; "REQ-OPS-ID-WINDOWS";
    "REQ-OPS-EXECUTION-BRIDGE"; "REQ-OPS-UI-ISOLATION";
    "REQ-OPS-MBSE-CORRESPONDENCE"; "HZ-SQL-FIN-01" ]

let nonempty value = String.trim value <> ""

let validate_obligations declarations =
  let gaps = ref [] in
  let add value = gaps := value :: !gaps in
  if declarations = [] then add "formal obligation registry is empty";
  let ids = List.map (fun item -> item.stable_id) declarations in
  if List.length ids <> List.length (List.sort_uniq String.compare ids) then
    add "formal obligation stable ids are not unique";
  let digests = List.map (fun item -> item.query_digest) declarations in
  if List.length digests <> List.length (List.sort_uniq String.compare digests) then
    add "formal queries are not independently digestible";
  let requirement_ids =
    List.map
      (fun (item : Run_topology.requirement) -> item.stable_id)
      Run_topology.authority.requirements
  in
  List.iter
    (fun item ->
      if not (nonempty item.stable_id && nonempty item.requirement_id
              && nonempty item.statement && nonempty item.smt2
              && nonempty item.solver_id && nonempty item.solver_version_constraint)
      then add ("formal obligation has empty authority: " ^ item.stable_id);
      if not (List.mem item.requirement_id requirement_ids) then
        add ("formal obligation resolves unknown requirement: " ^ item.stable_id);
      if item.timeout_ms <= 0 || item.timeout_ms > 60_000 then
        add ("formal timeout is invalid: " ^ item.stable_id);
      if not (String.equal item.query_digest (digest_query item.smt2)) then
        add ("formal query digest differs: " ^ item.stable_id);
      if not (contains item.smt2 "(set-logic" && contains item.smt2 "(check-sat)") then
        add ("formal query is incomplete: " ^ item.stable_id);
      begin match List.find_opt
          (fun (expected : obligation) -> expected.stable_id = item.stable_id)
          obligations
      with
      | None -> add ("formal obligation is not canonical: " ^ item.stable_id)
      | Some expected when item <> expected ->
          add ("formal obligation differs from canonical derivation: " ^ item.stable_id)
      | Some _ -> ()
      end;
      begin match item.kind, item.expected with
      | Negated_law, Unsat | False_control, Sat -> ()
      | Negated_law, _ -> add ("negated law does not expect Unsat: " ^ item.stable_id)
      | False_control, _ -> add ("false control does not expect Sat: " ^ item.stable_id)
      end)
    declarations;
  let represented_requirements =
    declarations |> List.map (fun item -> item.requirement_id)
    |> List.sort_uniq String.compare
  in
  if List.sort String.compare represented_requirements
     <> List.sort String.compare formal_requirement_ids
  then add "formal requirement denominator differs";
  List.iter
    (fun requirement_id ->
      let negated = List.filter
          (fun item -> item.requirement_id = requirement_id && item.kind = Negated_law)
          declarations in
      let controls = List.filter
          (fun item -> item.requirement_id = requirement_id && item.kind = False_control)
          declarations in
      if List.length negated <> 1 || controls = [] then
        add (Printf.sprintf
          "requirement %s must have one negated law and at least one false control"
          requirement_id))
    represented_requirements;
  List.rev !gaps

let validate () =
  validate_obligations obligations
  @ Run_formal_relation.validate_campaign Run_formal_relation.canonical

let specification_digest =
  List.map2
    (fun (item : obligation) (relation : Run_formal_relation.query) ->
         `Assoc
           [ ("expected", `String (match item.expected with Sat -> "sat" | Unsat -> "unsat"
               | Unknown -> "unknown" | Timeout -> "timeout" | Unavailable -> "unavailable"));
             ("factsDigest", `String relation.facts_digest);
             ("queryDigest", `String item.query_digest);
             ("relationDigest", `String relation.relation_digest);
             ("requirementId", `String item.requirement_id);
             ("stableId", `String item.stable_id);
             ("timeoutMs", `Int item.timeout_ms) ])
    obligations Run_formal_relation.canonical
  |> fun values ->
       `Assoc
         [ ("campaignDigest", `String Run_formal_relation.campaign_digest);
           ("obligations", `List values) ]
  |> Yojson.Safe.to_string
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex
