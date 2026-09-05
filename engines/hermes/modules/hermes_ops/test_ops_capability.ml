let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop offset =
    offset + needle_length <= haystack_length
    && (String.sub haystack offset needle_length = needle || loop (offset + 1))
  in
  loop 0

let all_surfaces =
  [ Ops_capability.Ocaml_api; Ops_capability.Cli; Ops_capability.Mcp; Ops_capability.Zenoh ]

let read path = In_channel.with_open_bin path In_channel.input_all

let () =
  check "N1 registry is nonempty and has unique stable ids" (fun () ->
      let ids = List.map (fun (d : Ops_capability.declaration) -> d.id) Ops_capability.all in
      ids <> [] && List.length ids = List.length (List.sort_uniq compare ids));
  check "N2 all R1-R31 rules are OCaml declarations" (fun () ->
      Ops_capability.rule_ids () = List.init 31 (fun i -> Printf.sprintf "R%d" (i + 1)));
  check "N2b declaration digest is canonical, ordered, and source-bound" (fun () ->
      let digest = Ops_capability.declaration_digest Ops_capability.all in
      String.length digest = 64
      && digest = Ops_capability.source_digest
      && digest = Ops_capability.declaration_digest Ops_capability.all
      && digest
         <> Ops_capability.declaration_digest (List.rev Ops_capability.all));
  check "R15 distinguishes static wiki from the operations application" (fun () ->
      Ops_capability.rule_titles
      |> List.assoc_opt "R15"
      |> Option.map (fun title -> contains title "operations application")
      = Some true);
  check "R31 requires the controlled typed OCaml external-access layer" (fun () ->
      Ops_capability.rule_titles
      |> List.assoc_opt "R31"
      |> Option.map (fun title ->
             contains title "controlled typed OCaml API layer")
      = Some true);
  check "R31 projection binds declarative intent fractals FPP and the sole Swarm bridge" (fun () ->
      let body = In_channel.with_open_bin "docs/hermes/mandatory-rules.md" In_channel.input_all in
      List.for_all (contains body)
        [ "declarative-intent"; "fractal ontology"; "functional atlas";
          "functional algebra"; "FPP"; "Run_swarm_bridge";
          "whole-Dune no-bypass census" ]);
  check "N5b capability core exposes declarations without workspace effects" (fun () ->
      let interface = read "modules/hermes_ops/ops_capability.mli" in
      let implementation = read "modules/hermes_ops/ops_capability.ml" in
      List.for_all (fun forbidden -> not (contains interface forbidden))
        [ "tracked_skill_names"; "tracked_agent_names"; "projected_rule_ids";
          "projected_rule_titles"; "validate : root" ]
      && List.for_all (fun forbidden -> not (contains implementation forbidden))
           [ "Sys.readdir"; "Sys.file_exists"; "open_in"; "In_channel" ]);
  check "N5c Dune owns a pure core and a separate effectful capability gate" (fun () ->
      let dune = read "modules/hermes_ops/dune" in
      List.for_all (contains dune)
        [ "(name hermes_ops_capability_core)";
          "(modules ops_capability)";
          "(name hermes_ops_capability)";
          "(modules ops_capability_gate module_intent)" ]);
  check "N5d pure dependents use the core while dashboard retains the gate" (fun () ->
      let ops_dune = read "modules/hermes_ops/dune" in
      let dependability_dune = read "modules/hermes_dependability/dune" in
      let dashboard_dune = read "modules/hermes_ops_dashboard/dune" in
      List.for_all (contains ops_dune)
        [ "(libraries hermes_ops_capability_core digestif)";
          "(libraries hermes_ops_capability_core hermes_wiki_fpp digestif unix)";
          "(libraries hermes_ops_governance hermes_ops_capability_core" ]
      && contains dependability_dune
           "(libraries hermes_ops_capability_core digestif yojson)"
      && contains dashboard_dune
           "hermes_ops_capability hermes_ops_capability_core hermes_external_access hermes_debugging");
  check "N6 every requested authority kind has an OCaml declaration" (fun () ->
      [ Ops_capability.Rule; Ops_capability.Skill; Ops_capability.Superpower;
        Ops_capability.Agent; Ops_capability.Capability; Ops_capability.Sop;
        Ops_capability.Activity ]
      |> List.for_all (fun kind ->
             List.exists
               (fun (d : Ops_capability.declaration) -> d.kind = kind)
               Ops_capability.all));

  check "A1 executable entries carry a nonempty semantic fractal/OODA path" (fun () ->
      List.for_all
        (fun (d : Ops_capability.declaration) ->
          match d.implementation with
          | Ops_capability.Command _ -> d.path <> []
          | Ops_capability.Judgment_only reason -> String.trim reason <> "")
        Ops_capability.all);
  check "A2 every command declares all four surfaces explicitly" (fun () ->
      List.for_all
        (fun (d : Ops_capability.declaration) ->
          match d.implementation with
          | Ops_capability.Judgment_only _ -> true
          | Ops_capability.Command _ ->
              List.map fst d.surfaces |> List.sort_uniq compare
              = List.sort_uniq compare all_surfaces)
        Ops_capability.all);
  check "A2b every executable command is live on all four native surfaces" (fun () ->
      List.for_all
        (fun (d : Ops_capability.declaration) ->
          match d.implementation with
          | Ops_capability.Judgment_only _ -> true
          | Ops_capability.Command _ ->
              List.for_all
                (function _, Ops_capability.Applicable -> true | _ -> false)
                d.surfaces)
        Ops_capability.all);
  check "A3 not-applicable surfaces have substantive typed reasons" (fun () ->
      List.for_all
        (fun (d : Ops_capability.declaration) ->
          List.for_all
            (function
              | _, Ops_capability.Applicable -> true
              | _, Ops_capability.Not_applicable reason -> String.length (String.trim reason) >= 12)
            d.surfaces)
        Ops_capability.all);
  check "A4 only the canonical five RCA origins exist and render" (fun () ->
      List.map Ops_capability.string_of_rca_origin
        [ Ops_capability.Specification; Ops_capability.Implementation;
          Ops_capability.Environment; Ops_capability.Evidence; Ops_capability.Control ]
      = [ "Specification"; "Implementation"; "Environment"; "Evidence"; "Control" ]);
  check "A5 lifecycle is exactly declared/implemented/executed/current" (fun () ->
      List.map Ops_capability.string_of_lifecycle
        [ Ops_capability.Declared; Ops_capability.Implemented;
          Ops_capability.Executed; Ops_capability.Current ]
      = [ "declared"; "implemented"; "executed"; "current" ]);

  Printf.printf "ops_capability: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_capability" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_ops_capability_core ]);
  exit (Suite_telemetry.exit_code self)
