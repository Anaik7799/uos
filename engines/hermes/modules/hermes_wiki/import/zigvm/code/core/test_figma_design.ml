module Design = Zigvm_harness_support.Figma_design

let require condition message = if not condition then failwith message

let () =
  let initial = Design.Initial.default () in
  let final = Design.Final.default () in
  require
    (Design.observe_initial initial = Design.observe_final final)
    "initial/final Figma design homomorphism";
  let observation = Design.observe_final final in
  require (observation.modes = [ "light"; "dark" ]) "light/dark modes";
  require
    (observation.breakpoints =
     [ ("compact", 0); ("medium", 600); ("expanded", 840); ("large", 1200); ("extra-large", 1600) ])
    "responsive breakpoint contract";
  require (List.length observation.pages = 13) "Figma page topology";
  require (List.length observation.product_screens = 37) "P01-P37 screen totality";
  require (List.length observation.screens = 185)
    "every product screen has five responsive interpretations";
  let ui_component_names =
    Ui_component_contract.all
    |> List.map (fun component -> component.Ui_component_contract.name)
    |> List.sort String.compare
  in
  require (observation.components = ui_component_names)
    "OCaml component registry maps bijectively to Figma";
  let ui_component_variants =
    Ui_component_contract.all
    |> List.map (fun component ->
           (component.Ui_component_contract.name, component.variants))
    |> List.sort (fun (left, _) (right, _) -> String.compare left right)
  in
  require (observation.component_variants = ui_component_variants)
    "Figma variants preserve the Bonsai component algebra";
  let ui_page_ids =
    Ui_page_registry.all
    |> List.map (fun page -> page.Ui_page_registry.id)
    |> List.sort String.compare
  in
  require (observation.product_screens = ui_page_ids)
    "OCaml page registry maps bijectively to Figma screens";
  require (List.mem "Graph canvas" observation.components) "graph component missing";
  require (List.mem "Source inspector" observation.components) "inspector component missing";
  require (List.mem "Project inventory" observation.components)
    "project inventory component missing";
  List.iter
    (fun component ->
      require (List.mem component observation.components)
        (component ^ " component missing"))
    [ "Processing profile"; "Graph camera"; "Graph layout selector";
      "Graph playback"; "Graph comparison"; "Analytics grid";
      "Saved view editor"; "Note editor"; "Visibility control";
      "Export format"; "Import configuration"; "Provider state";
      "Intelligence shell"; "Host adapters" ];
  require (List.mem "Navigate P01 to P02" observation.transitions)
    "route navigation transition missing";
  require
    (List.exists
       (fun name -> String.starts_with ~prefix:"Scenario SCN-P17" name)
       observation.transitions)
    "graph interaction transitions missing";
  require (observation.minimum_target = 44) "minimum target must be 44px";
  let open Yojson.Safe.Util in
  let primitive_scopes =
    Design.to_yojson final |> member "tokens" |> to_list
    |> List.filter_map (fun token ->
         if token |> member "layer" |> to_string = "primitive" then
           Some
             ( token |> member "name" |> to_string,
               token |> member "scope" |> to_string )
         else None)
  in
  require
    (List.assoc_opt "motion/reduced" primitive_scopes = Some "HIDDEN")
    "motion/reduced must remain hidden from Figma property pickers";
  require
    (not (List.exists (fun (_, scope) -> scope = "ALL_SCOPES") primitive_scopes))
    "primitive variables must never expose ALL_SCOPES";
  (match Design.validate_final final with
  | Ok () -> ()
  | Error errors -> failwith (String.concat "; " errors));
  let json = Design.to_yojson final |> Yojson.Safe.to_string in
  require (String.length json > 500) "Figma projection must be non-vacuous";
  let mutant = Design.Final.with_minimum_target final 43 in
  require
    (match Design.validate_final mutant with Error _ -> true | Ok () -> false)
    "43px target mutant must be killed";
  print_endline "figma design laws: pass (seed=5500, deterministic)"
