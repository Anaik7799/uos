(* R23 declarative-configuration ontology, atlas, algebra, and documentation.

   These tests deliberately begin at the one declaration authority,
   [Ops_config.elements].  Every other surface must be derived from it. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= haystack_length
    && (String.sub haystack index needle_length = needle || loop (index + 1))
  in
  needle_length > 0 && loop 0

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let ocaml_code_only source =
  let length = String.length source in
  let code = Bytes.make length ' ' in
  let rec normal index =
    if index >= length then ()
    else if index + 1 < length && source.[index] = '('
            && source.[index + 1] = '*' then
      comment 1 (index + 2)
    else if source.[index] = '"' then string_literal (index + 1)
    else (Bytes.set code index source.[index]; normal (index + 1))
  and comment depth index =
    if index >= length then ()
    else if index + 1 < length && source.[index] = '('
            && source.[index + 1] = '*' then
      comment (depth + 1) (index + 2)
    else if index + 1 < length && source.[index] = '*'
            && source.[index + 1] = ')' then
      if depth = 1 then normal (index + 2)
      else comment (depth - 1) (index + 2)
    else comment depth (index + 1)
  and string_literal index =
    if index >= length then ()
    else if source.[index] = '\\' then
      string_literal (min length (index + 2))
    else if source.[index] = '"' then normal (index + 1)
    else string_literal (index + 1)
  in
  normal 0;
  Bytes.to_string code

let source_is_pure body =
  let code = ocaml_code_only body in
  List.for_all (fun marker -> not (contains code marker))
    [ "Sys."; "Unix."; "Sqlite3"; "open_in"; "open_out";
      "create_process"; "getenv" ]

let strip_dune_comments body =
  body
  |> String.split_on_char '\n'
  |> List.map (fun line ->
         match String.index_opt line ';' with
         | None -> line
         | Some index -> String.sub line 0 index)
  |> String.concat "\n"

let words body =
  String.map
    (function '(' | ')' | '\n' | '\r' | '\t' -> ' ' | character -> character)
    body
  |> String.split_on_char ' '
  |> List.filter (fun word -> word <> "")

let before_executables body =
  let marker = "(executable" in
  let rec find index =
    if index + String.length marker > String.length body then body
    else if String.sub body index (String.length marker) = marker then
      String.sub body 0 index
    else find (index + 1)
  in
  find 0

let index_of value values =
  let rec loop index = function
    | [] -> None
    | item :: _ when String.equal item value -> Some index
    | _ :: rest -> loop (index + 1) rest
  in
  loop 0 values

let () =
  check "O1 ontology validates" (fun () -> Ops_config_ontology.validate () = Ok ());
  check "O2 every declaration has exactly one ontology node" (fun () ->
      let expected = List.length Ops_config.elements in
      let observed =
        Ops_config_ontology.all
        |> List.filter (fun node -> node.Ops_config_ontology.kind = Element)
        |> List.length
      in
      expected = observed);
  check "O3 ontology nodes retain the declared fractal layer" (fun () ->
      List.for_all
        (fun (element : Ops_config.element) ->
          match Ops_config_ontology.find (Ops_config_ontology.element_id element.key) with
          | Some node -> node.layer = Some element.layer
          | None -> false)
        Ops_config.elements);
  check "O4 bridge and scheduler authorities cannot be conflated" (fun () ->
      match
        ( Ops_config_ontology.find Ops_config_ontology.execution_bridge_id,
          Ops_config_ontology.find Ops_config_ontology.scheduler_id )
      with
      | Some bridge, Some scheduler ->
          bridge.authority = Execution && scheduler.authority = Scheduling
      | _ -> false);
  check "O5 ontology projects the sole declaration authority digest" (fun () ->
      String.equal Ops_config_ontology.declaration_digest
        Ops_config.declaration_digest
      && String.equal Ops_config_ontology.schema_id Ops_config.schema_id)

let () =
  check "A1 atlas validates" (fun () -> Ops_config_atlas.validate () = Ok ());
  check "A2 every declaration has a bounded path to a receipt" (fun () ->
      List.for_all
        (fun (element : Ops_config.element) ->
          Ops_config_atlas.paths_to_receipt
            (Ops_config_ontology.element_id element.key)
          <> [])
        Ops_config.elements);
  check "A3 assurance is the bridge's only predecessor" (fun () ->
      Ops_config_atlas.predecessors Ops_config_ontology.execution_bridge_id
      = [ Ops_config_ontology.assurance_id ]);
  check "A4 Run_swarm_bridge is the scheduler's only predecessor" (fun () ->
      Ops_config_atlas.predecessors Ops_config_ontology.scheduler_id
      = [ Ops_config_ontology.execution_bridge_id ]);
  check "A5 every declaration-to-receipt path crosses digest intent assurance and bridge"
    (fun () ->
      List.for_all
        (fun (element : Ops_config.element) ->
          Ops_config_atlas.paths_to_receipt
            (Ops_config_ontology.element_id element.key)
          |> List.for_all (fun path ->
                 match
                   ( index_of Ops_config_ontology.configuration_digest_id path,
                     index_of Ops_config_ontology.execution_intent_id path,
                     index_of Ops_config_ontology.assurance_id path,
                     index_of Ops_config_ontology.execution_bridge_id path,
                     index_of Ops_config_ontology.scheduler_id path )
                 with
                 | Some digest, Some intent, Some assurance, Some bridge, Some scheduler ->
                     digest < intent && intent < assurance && assurance < bridge
                     && bridge < scheduler
                 | _ -> false))
        Ops_config.elements);
  check "A6 atlas projects the sole declaration authority digest" (fun () ->
      String.equal Ops_config_atlas.declaration_digest
        Ops_config.declaration_digest
      && String.equal Ops_config_atlas.schema_id Ops_config.schema_id);
  check "A7 evidence and execution cannot point back into declaration authority"
    (fun () ->
      let forbidden_targets =
        Ops_config_ontology.registry_id
        :: List.map
             (fun (element : Ops_config.element) ->
               Ops_config_ontology.element_id element.key)
             Ops_config.elements
      in
      Ops_config_atlas.edges
      |> List.for_all (fun (edge : Ops_config_atlas.edge) ->
             not
               (List.mem edge.source
                  [ Ops_config_ontology.execution_bridge_id;
                    Ops_config_ontology.scheduler_id;
                    Ops_config_ontology.receipt_id ]
                && List.mem edge.target forbidden_targets)))

let completions =
  [ Ops_config_algebra.Unmapped; Verified; Partial; Blocked ]

let () =
  check "L1 completion join is associative" (fun () ->
      List.for_all
        (fun left ->
          List.for_all
            (fun middle ->
              List.for_all
                (fun right ->
                  Ops_config_algebra.combine
                    (Ops_config_algebra.combine left middle) right
                  = Ops_config_algebra.combine left
                      (Ops_config_algebra.combine middle right))
                completions)
            completions)
        completions);
  check "L2 completion join is commutative and idempotent" (fun () ->
      List.for_all
        (fun left ->
          Ops_config_algebra.combine left left = left
          && List.for_all
               (fun right ->
                 Ops_config_algebra.combine left right
                 = Ops_config_algebra.combine right left)
               completions)
        completions);
  check "L3 empty roll-up is unmapped" (fun () ->
      Ops_config_algebra.roll_up [] = Unmapped);
  check "L4 absent configuration is typed without false green" (fun () ->
      Ops_config_algebra.resolve ~present:false Ops_config.Required = Required_blocked
      && Ops_config_algebra.resolve ~present:false Optional_flag
         = Optional_unavailable
      && Ops_config_algebra.resolve ~present:false Override = Defaulted
      && Ops_config_algebra.resolve ~present:true Required = Supplied);
  check "L5 declaration digest is deterministic and permutation invariant" (fun () ->
      String.length Ops_config.declaration_digest = 64
      && String.equal
           (Ops_config.declaration_digest_of Ops_config.elements)
           (Ops_config.declaration_digest_of (List.rev Ops_config.elements)));
  check "L6 execution binding requires the exact configuration digest" (fun () ->
      let digest = Ops_config.declaration_digest in
      Ops_config_algebra.binds_execution_intent
        ~configuration_digest:digest ~context_configuration_digest:digest
      && not
           (Ops_config_algebra.binds_execution_intent
              ~configuration_digest:digest
              ~context_configuration_digest:(String.make 64 '0')));
  check "L7 algebra delegates to the sole declaration digest authority" (fun () ->
      String.equal
        (Ops_config_algebra.declaration_digest Ops_config.elements)
        Ops_config.declaration_digest);
  check "L8 declaration mutation changes the delegated digest projection" (fun () ->
      match Ops_config.elements with
      | [] -> false
      | first :: rest ->
          let changed =
            { first with purpose = first.purpose ^ "-negative-control" } :: rest
          in
          not
            (String.equal
               (Ops_config_algebra.declaration_digest Ops_config.elements)
               (Ops_config_algebra.declaration_digest changed)))

let () =
  check "P1 pure aggregate typed model validates" (fun () ->
      Ops_config_algebra.validate () = Ok ());
  check "P2 pure configuration authority quartet has no effectful source access"
    (fun () ->
      [ "ops_config.ml"; "ops_config_ontology.ml"; "ops_config_atlas.ml";
        "ops_config_algebra.ml" ]
      |> List.map (Filename.concat "modules/hermes_ops")
      |> List.for_all (fun path -> source_is_pure (read_file path))
      && not (source_is_pure "let _ = Sys.getenv_opt \"MUTANT\""));
  check "P3 dashboard production library has no aggregate hermes_ops reverse edge"
    (fun () ->
      let dashboard =
        read_file "modules/hermes_ops_dashboard/dune"
        |> before_executables |> strip_dune_comments
      in
      not (List.mem "hermes_ops" (words dashboard))
      && List.mem "hermes_ops"
           (words "(libraries hermes_ops_dashboard hermes_ops)"))

let () =
  Printf.printf "ops_config_fractal: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_config_fractal" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_ops_config_authority ]);
  exit (Suite_telemetry.exit_code self)
