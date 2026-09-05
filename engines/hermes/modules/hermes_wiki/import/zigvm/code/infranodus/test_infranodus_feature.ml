module Feature = Zigvm_harness_support.Infranodus_feature

let require condition message = if not condition then failwith message

let expected_family_counts =
  [
    (Feature.Workspace, 6);
    (Feature.Acquisition, 11);
    (Feature.Processing, 8);
    (Feature.Visualization, 12);
    (Feature.Analytics, 14);
    (Feature.Intelligence, 9);
    (Feature.Integration, 10);
  ]

let count_family family =
  Feature.all
  |> List.filter (fun feature -> Feature.family feature = family)
  |> List.length

let implemented_count () =
  Feature.all
  |> List.filter (fun feature -> Feature.status feature = Feature.Implemented)
  |> List.length

let capability_70_ids =
  [
    "F1.4"; "F1.5"; "F1.6";
    "F3.1"; "F3.2"; "F3.3"; "F3.4"; "F3.6"; "F3.7"; "F3.8";
    "F4.2"; "F4.6"; "F4.7"; "F4.8"; "F4.9"; "F4.10"; "F4.11";
    "F5.1"; "F5.2"; "F5.5"; "F5.6"; "F5.7"; "F5.9"; "F5.10";
    "F5.11"; "F5.12"; "F5.13"; "F5.14";
    "F7.2"; "F7.3"; "F7.5"; "F7.6"; "F7.7"; "F7.9"; "F7.10";
    "F2.2"; "F2.3"; "F2.4"; "F2.5"; "F2.6"; "F2.7"; "F2.8";
    "F2.9"; "F2.10"; "F2.11";
    "F6.1"; "F6.2"; "F6.3"; "F6.4"; "F6.5"; "F6.6"; "F6.7";
    "F6.8"; "F6.9"; "F7.8";
  ]

let () =
  require (List.length Feature.all = 70) "feature registry must totalize 70 IDs";
  require (implemented_count () = 70)
    "capability-70 tranche must admit every catalogued feature";
  List.iter
    (fun id ->
      require
        (match Feature.find id with
        | Some feature -> Feature.status feature = Feature.Implemented
        | None -> false)
        (id ^ " must be implemented in the capability-70 tranche"))
    capability_70_ids;
  require (Feature.find "F1.1" <> None) "F1.1 missing";
  require
    (match Feature.find "F1.3" with
    | Some feature -> Feature.status feature = Feature.Implemented
    | None -> false)
    "F1.3 inventory must remain promoted with concrete evidence";
  require (Feature.find "F7.10" <> None) "F7.10 missing";
  List.iter
    (fun (family, expected) ->
      require (count_family family = expected)
        (Printf.sprintf "wrong count for %s" (Feature.family_name family)))
    expected_family_counts;
  List.iter
    (fun feature ->
      require (Feature.scenario_ids feature <> [])
        (Feature.id feature ^ " lacks a Playwright scenario");
      require (Feature.ui_controls feature <> [])
        (Feature.id feature ^ " lacks an OCaml UI control");
      match Feature.status feature with
      | Feature.Implemented ->
          require (Feature.evidence feature <> [])
            (Feature.id feature ^ " claims implementation without evidence")
      | Feature.Adapter_ready | Feature.Planned | Feature.Unknown_not_claimed -> ())
    Feature.all;
  (match Feature.validate Feature.all with
  | Ok () -> ()
  | Error errors -> failwith (String.concat "; " errors));
  print_endline "infranodus feature laws: pass"
