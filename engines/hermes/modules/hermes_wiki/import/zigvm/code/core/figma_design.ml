type token_kind = Color | Number | String | Boolean

type token =
  | Primitive of { name : string; kind : token_kind; value : string; scope : string }
  | Semantic of {
      name : string;
      kind : token_kind;
      light_alias : string;
      dark_alias : string;
      scope : string;
      css : string;
    }

type figma_page = { name : string; order : int; purpose : string }

type component = {
  name : string;
  figma_name : string;
  test_id_prefix : string;
  variants : string list;
  interactive : bool;
  minimum_width : int;
  minimum_height : int;
  accessible_role : string;
  event_ids : string list;
  token_names : string list;
}

type product_screen = {
  page_id : string;
  name : string;
  route : string;
  figma_page : string;
  states : string list;
  capability_ids : string list;
  component_names : string list;
  evidence : string;
}

type screen = {
  name : string;
  page_id : string;
  window_class : string;
  width : int;
  height : int;
  component_names : string list;
}

type transition = { name : string; source : string; target : string; trigger : string }

type operation =
  | Add_token of token
  | Add_page of figma_page
  | Add_component of component
  | Add_product_screen of product_screen
  | Add_screen of screen
  | Add_transition of transition

type catalog = {
  modes : string list;
  breakpoints : (string * int) list;
  tokens : token list;
  pages : figma_page list;
  components : component list;
  product_screens : product_screen list;
  screens : screen list;
  transitions : transition list;
  minimum_target : int;
}

type observation = {
  modes : string list;
  breakpoints : (string * int) list;
  tokens : string list;
  pages : string list;
  components : string list;
  component_variants : (string * string list) list;
  product_screens : string list;
  screens : string list;
  transitions : string list;
  minimum_target : int;
}

let token_name = function
  | Primitive value -> value.name
  | Semantic value -> value.name

let default_modes = [ "light"; "dark" ]

let default_breakpoints =
  [
    ("compact", 0);
    ("medium", 600);
    ("expanded", 840);
    ("large", 1200);
    ("extra-large", 1600);
  ]

let primitive name kind value scope =
  Add_token (Primitive { name; kind; value; scope })

let semantic name kind light_alias dark_alias scope css =
  Add_token (Semantic { name; kind; light_alias; dark_alias; scope; css })

let token_operations =
  [
    primitive "color/neutral/0" Color "#ffffff" "FRAME_FILL,SHAPE_FILL,TEXT_FILL";
    primitive "color/neutral/25" Color "#edf2f3" "TEXT_FILL";
    primitive "color/neutral/50" Color "#f5f7f8" "FRAME_FILL,SHAPE_FILL";
    primitive "color/neutral/200" Color "#dce2e5" "STROKE_COLOR";
    primitive "color/neutral/300" Color "#9eaaaf" "TEXT_FILL";
    primitive "color/neutral/500" Color "#65737b" "TEXT_FILL";
    primitive "color/neutral/700" Color "#344047" "STROKE_COLOR";
    primitive "color/neutral/850" Color "#1d2428" "FRAME_FILL,SHAPE_FILL";
    primitive "color/neutral/900" Color "#182126" "FRAME_FILL,SHAPE_FILL,TEXT_FILL";
    primitive "color/neutral/950" Color "#151a1d" "FRAME_FILL,SHAPE_FILL";
    primitive "color/green/300" Color "#3ecf9a" "ALL_FILLS,STROKE_COLOR";
    primitive "color/green/700" Color "#087f5b" "ALL_FILLS,STROKE_COLOR";
    primitive "color/amber/300" Color "#f0a14a" "ALL_FILLS,STROKE_COLOR";
    primitive "color/amber/700" Color "#b65d05" "ALL_FILLS,STROKE_COLOR";
    primitive "color/red/300" Color "#ff7474" "ALL_FILLS,STROKE_COLOR";
    primitive "color/red/700" Color "#bd2c2c" "ALL_FILLS,STROKE_COLOR";
    primitive "color/blue/500" Color "#2f6fbb" "ALL_FILLS,STROKE_COLOR";
    primitive "color/community/1" Color "#087f5b" "ALL_FILLS,STROKE_COLOR";
    primitive "color/community/2" Color "#d9485f" "ALL_FILLS,STROKE_COLOR";
    primitive "color/community/3" Color "#2f6fbb" "ALL_FILLS,STROKE_COLOR";
    primitive "color/community/4" Color "#9c6b16" "ALL_FILLS,STROKE_COLOR";
    primitive "space/1" Number "4" "GAP";
    primitive "space/2" Number "8" "GAP";
    primitive "space/3" Number "12" "GAP";
    primitive "space/4" Number "16" "GAP";
    primitive "space/6" Number "24" "GAP";
    primitive "space/8" Number "32" "GAP";
    primitive "space/12" Number "48" "GAP";
    primitive "space/16" Number "64" "GAP";
    primitive "radius/control" Number "4" "CORNER_RADIUS";
    primitive "radius/panel" Number "6" "CORNER_RADIUS";
    primitive "radius/dialog" Number "12" "CORNER_RADIUS";
    primitive "size/control-min" Number "44" "WIDTH_HEIGHT";
    primitive "size/content-max" Number "1440" "WIDTH";
    primitive "type/body" String "14/1.45 Inter" "FONT_FAMILY,FONT_SIZE,LINE_HEIGHT";
    primitive "type/title" String "28/1.2 Inter" "FONT_FAMILY,FONT_SIZE,LINE_HEIGHT";
    primitive "elevation/panel" String "0 4 16 rgba(0,0,0,.12)" "EFFECT";
    primitive "motion/reduced" Boolean "true" "HIDDEN";
    semantic "surface/background" Color "color/neutral/50" "color/neutral/950"
      "FRAME_FILL" "var(--bg)";
    semantic "surface/panel" Color "color/neutral/0" "color/neutral/850"
      "FRAME_FILL,SHAPE_FILL" "var(--panel)";
    semantic "content/primary" Color "color/neutral/900" "color/neutral/25"
      "TEXT_FILL" "var(--ink)";
    semantic "content/muted" Color "color/neutral/500" "color/neutral/300"
      "TEXT_FILL" "var(--muted)";
    semantic "border/default" Color "color/neutral/200" "color/neutral/700"
      "STROKE_COLOR" "var(--line)";
    semantic "status/accent" Color "color/green/700" "color/green/300"
      "ALL_FILLS,STROKE_COLOR" "var(--accent)";
    semantic "status/warning" Color "color/amber/700" "color/amber/300"
      "ALL_FILLS,STROKE_COLOR" "var(--warning)";
    semantic "status/error" Color "color/red/700" "color/red/300"
      "ALL_FILLS,STROKE_COLOR" "var(--error)";
    semantic "data/selected" Color "color/blue/500" "color/blue/500"
      "ALL_FILLS,STROKE_COLOR" "var(--selected)";
  ]

let page_specs =
  [
    ("00 Cover & Status", "Parity metrics, evidence boundary, and admitted cycle");
    ("01 Foundations", "Variables, modes, typography, spacing, radii, effects, and grids");
    ("02 Components", "Local components, properties, variants, and usage guidance");
    ("03 Public & Session", "P01-P07 responsive pages and states");
    ("04 Projects & Import", "P08-P16 pages, source selection, and import states");
    ("05 Graph Workspace", "P17-P18 graph and evidence states");
    ("06 Analytics & Research", "P19-P24 analytics and intelligence states");
    ("07 Share Export Integrations", "P25-P30 workspace and integration states");
    ("08 Settings & Account", "P31-P37 settings and evidence-gated account states");
    ("09 Responsive Matrix", "Five admitted responsive classes");
    ("10 Prototype Flows", "Route, wizard, overlay, and interaction journeys");
    ("11 Capture Oracles", "Browser capture comparison oracles with provenance");
    ("12 Parity Evidence", "Route, component, capability, scenario, and gap coverage");
  ]

let page_operations =
  List.mapi
    (fun order (name, purpose) -> Add_page { name; order; purpose })
    page_specs

let default_tokens =
  [
    "surface/background";
    "surface/panel";
    "content/primary";
    "content/muted";
    "border/default";
    "status/accent";
    "status/warning";
    "status/error";
    "data/selected";
    "size/control-min";
    "radius/control";
    "radius/panel";
  ]

let component_operations =
  Ui_component_contract.all
  |> List.map (fun contract ->
         Add_component
           {
             name = contract.Ui_component_contract.name;
             figma_name = contract.figma_name;
             test_id_prefix = contract.test_id_prefix;
             variants = contract.variants;
             interactive = contract.interactive;
             minimum_width = contract.minimum_width;
             minimum_height = contract.minimum_height;
             accessible_role = contract.accessible_role;
             event_ids = contract.event_ids;
             token_names = default_tokens;
           })

let figma_page_for page_id =
  let number = int_of_string (String.sub page_id 1 2) in
  if number <= 7 then "03 Public & Session"
  else if number <= 16 then "04 Projects & Import"
  else if number <= 18 then "05 Graph Workspace"
  else if number <= 24 then "06 Analytics & Research"
  else if number <= 30 then "07 Share Export Integrations"
  else "08 Settings & Account"

let evidence_name = function
  | Ui_page_registry.Observed -> "OBSERVED"
  | Ui_page_registry.Documented -> "DOCUMENTED"
  | Ui_page_registry.Composed -> "COMPOSED"
  | Ui_page_registry.Evidence_gated -> "EVIDENCE_GATED"
  | Ui_page_registry.Local_extension -> "LOCAL_EXTENSION"

let product_screen_operations =
  Ui_page_registry.all
  |> List.map (fun page ->
         Add_product_screen
           {
             page_id = page.Ui_page_registry.id;
             name = page.name;
             route = Ui_route.to_path page.route;
             figma_page = figma_page_for page.id;
             states = page.states;
             capability_ids = page.capability_ids;
             component_names = page.component_names;
             evidence = evidence_name page.evidence;
           })

let responsive_specs =
  [
    ("compact", 390, 844);
    ("medium", 768, 1024);
    ("expanded", 1024, 900);
    ("large", 1440, 900);
    ("extra-large", 1920, 1080);
  ]

let responsive_name page_id window_class =
  page_id ^ " / " ^ String.capitalize_ascii window_class

let responsive_screen_operations =
  Ui_page_registry.all
  |> List.concat_map (fun page ->
         List.map
           (fun (window_class, width, height) ->
             Add_screen
               {
                 name = responsive_name page.Ui_page_registry.id window_class;
                 page_id = page.id;
                 window_class;
                 width;
                 height;
                 component_names = page.component_names;
               })
           responsive_specs)

let large_screen page_id = responsive_name page_id "large"

let navigation_transitions =
  let rec loop = function
    | left :: (right :: _ as rest) ->
        Add_transition
          {
            name = "Navigate " ^ left.Ui_page_registry.id ^ " to " ^ right.id;
            source = large_screen left.id;
            target = large_screen right.id;
            trigger = "navigation.navigate";
          }
        :: loop rest
    | _ -> []
  in
  loop Ui_page_registry.all

let scenario_transitions =
  Ui_traceability.all
  |> List.filter_map (fun row ->
         match row.Ui_traceability.event_id with
         | None -> None
         | Some trigger ->
             Some
               (Add_transition
                  {
                    name = "Scenario " ^ row.scenario_id;
                    source = large_screen row.page_id;
                    target = large_screen row.page_id;
                    trigger;
                  }))

let source =
  token_operations @ page_operations @ component_operations
  @ product_screen_operations @ responsive_screen_operations
  @ navigation_transitions @ scenario_transitions

let empty_catalog minimum_target : catalog =
  {
    modes = default_modes;
    breakpoints = default_breakpoints;
    tokens = [];
    pages = [];
    components = [];
    product_screens = [];
    screens = [];
    transitions = [];
    minimum_target;
  }

let apply (catalog : catalog) = function
  | Add_token value -> { catalog with tokens = value :: catalog.tokens }
  | Add_page value -> { catalog with pages = value :: catalog.pages }
  | Add_component value -> { catalog with components = value :: catalog.components }
  | Add_product_screen value ->
      { catalog with product_screens = value :: catalog.product_screens }
  | Add_screen value -> { catalog with screens = value :: catalog.screens }
  | Add_transition value -> { catalog with transitions = value :: catalog.transitions }

let canonical (catalog : catalog) =
  {
    catalog with
    tokens = List.sort (fun left right -> String.compare (token_name left) (token_name right)) catalog.tokens;
    pages =
      List.sort
        (fun (left : figma_page) (right : figma_page) -> String.compare left.name right.name)
        catalog.pages;
    components =
      List.sort
        (fun (left : component) (right : component) -> String.compare left.name right.name)
        catalog.components;
    product_screens =
      List.sort
        (fun (left : product_screen) (right : product_screen) ->
          String.compare left.page_id right.page_id)
        catalog.product_screens;
    screens =
      List.sort
        (fun (left : screen) (right : screen) -> String.compare left.name right.name)
        catalog.screens;
    transitions =
      List.sort
        (fun (left : transition) (right : transition) -> String.compare left.name right.name)
        catalog.transitions;
  }

module Initial = struct
  type t = operation list
  let default () = source
end

module Final = struct
  type t = catalog
  let default () = List.fold_left apply (empty_catalog 44) source |> canonical
  let with_minimum_target (value : t) minimum_target = { value with minimum_target }
end

let observe (catalog : catalog) =
  {
    modes = catalog.modes;
    breakpoints = catalog.breakpoints;
    tokens = List.map token_name catalog.tokens |> List.sort String.compare;
    pages =
      List.map (fun (value : figma_page) -> value.name) catalog.pages
      |> List.sort String.compare;
    components =
      List.map (fun (value : component) -> value.name) catalog.components
      |> List.sort String.compare;
    component_variants =
      List.map (fun (value : component) -> (value.name, value.variants)) catalog.components
      |> List.sort (fun (left, _) (right, _) -> String.compare left right);
    product_screens =
      List.map (fun (value : product_screen) -> value.page_id) catalog.product_screens
      |> List.sort String.compare;
    screens =
      List.map (fun (value : screen) -> value.name) catalog.screens
      |> List.sort String.compare;
    transitions =
      List.map (fun (value : transition) -> value.name) catalog.transitions
      |> List.sort String.compare;
    minimum_target = catalog.minimum_target;
  }

let observe_initial operations =
  List.fold_left apply (empty_catalog 44) operations |> canonical |> observe

let observe_final catalog = observe catalog

let duplicates values =
  values
  |> List.sort String.compare
  |> List.fold_left
       (fun (previous, found) value ->
         match previous with
         | Some prior when String.equal prior value -> (Some value, value :: found)
         | _ -> (Some value, found))
       (None, [])
  |> snd |> List.sort_uniq String.compare

let validate_final (catalog : catalog) =
  let errors = ref [] in
  let add message = errors := message :: !errors in
  let reject condition message = if condition then add message in
  reject (catalog.minimum_target < 44) "minimum interactive target is below 44px";
  reject (catalog.modes <> default_modes) "design modes differ from light/dark contract";
  reject (catalog.breakpoints <> default_breakpoints)
    "breakpoints differ from mobile-first contract";
  reject (List.length catalog.pages <> 13) "Figma page topology is not total";
  reject (List.length catalog.product_screens <> 37) "P01-P37 screen registry is not total";
  reject (List.length catalog.screens <> 185) "responsive screen matrix is not 37 x 5";
  List.iter (fun name -> add ("duplicate token: " ^ name))
    (duplicates (List.map token_name catalog.tokens));
  List.iter (fun name -> add ("duplicate Figma page: " ^ name))
    (duplicates (List.map (fun (value : figma_page) -> value.name) catalog.pages));
  List.iter (fun name -> add ("duplicate component: " ^ name))
    (duplicates (List.map (fun (value : component) -> value.name) catalog.components));
  List.iter (fun name -> add ("duplicate product screen: " ^ name))
    (duplicates
       (List.map (fun (value : product_screen) -> value.page_id) catalog.product_screens));
  List.iter (fun name -> add ("duplicate responsive screen: " ^ name))
    (duplicates (List.map (fun (value : screen) -> value.name) catalog.screens));
  List.iter (fun name -> add ("duplicate transition: " ^ name))
    (duplicates (List.map (fun (value : transition) -> value.name) catalog.transitions));
  let token_names = List.map token_name catalog.tokens in
  let page_names = List.map (fun (value : figma_page) -> value.name) catalog.pages in
  let component_names =
    List.map (fun (value : component) -> value.name) catalog.components
  in
  let screen_names = List.map (fun (value : screen) -> value.name) catalog.screens in
  List.iter
    (function
      | Primitive value ->
          reject (String.trim value.value = "" || String.trim value.scope = "")
            (value.name ^ " has blank primitive metadata");
          reject (String.equal value.scope "ALL_SCOPES")
            (value.name ^ " exposes forbidden ALL_SCOPES")
      | Semantic value ->
          reject (not (List.mem value.light_alias token_names))
            (value.name ^ " has missing light alias");
          reject (not (List.mem value.dark_alias token_names))
            (value.name ^ " has missing dark alias");
          reject (String.length value.css < 6) (value.name ^ " has missing code syntax"))
    catalog.tokens;
  List.iter
    (fun (value : component) ->
      let contract = Ui_component_contract.by_name value.name in
      reject (Option.is_none contract) (value.name ^ " is not a Bonsai component");
      reject (value.variants = []) (value.name ^ " has no variants");
      reject
        (value.interactive
        && (value.minimum_width < catalog.minimum_target
           || value.minimum_height < catalog.minimum_target))
        (value.name ^ " violates minimum target");
      List.iter
        (fun token ->
          reject (not (List.mem token token_names))
            (value.name ^ " uses missing token " ^ token))
        value.token_names;
      match contract with
      | None -> ()
      | Some expected ->
          reject
            (value.figma_name <> expected.figma_name
            || value.test_id_prefix <> expected.test_id_prefix
            || value.variants <> expected.variants
            || value.interactive <> expected.interactive
            || value.minimum_width <> expected.minimum_width
            || value.minimum_height <> expected.minimum_height
            || value.accessible_role <> expected.accessible_role
            || value.event_ids <> expected.event_ids)
            (value.name ^ " differs from the Bonsai component contract"))
    catalog.components;
  List.iter
    (fun (value : product_screen) ->
      reject (not (List.mem value.figma_page page_names))
        (value.page_id ^ " uses an unknown Figma page");
      reject (value.states = []) (value.page_id ^ " has no states");
      List.iter
        (fun name ->
          reject (not (List.mem name component_names))
            (value.page_id ^ " uses missing component " ^ name))
        value.component_names)
    catalog.product_screens;
  List.iter
    (fun (value : screen) ->
      reject (value.width <= 0 || value.height <= 0)
        (value.name ^ " has invalid dimensions");
      reject (not (List.mem_assoc value.window_class catalog.breakpoints))
        (value.name ^ " has unknown window class");
      reject
        (not
           (List.exists
              (fun (product : product_screen) ->
                String.equal product.page_id value.page_id)
              catalog.product_screens))
        (value.name ^ " has no product screen");
      List.iter
        (fun name ->
          reject (not (List.mem name component_names))
            (value.name ^ " uses missing component " ^ name))
        value.component_names)
    catalog.screens;
  List.iter
    (fun (value : transition) ->
      reject (not (List.mem value.source screen_names))
        (value.name ^ " has missing source");
      reject (not (List.mem value.target screen_names))
        (value.name ^ " has missing target");
      reject (String.trim value.trigger = "") (value.name ^ " has blank trigger"))
    catalog.transitions;
  let expected_components =
    Ui_component_contract.all
    |> List.map (fun value -> value.Ui_component_contract.name)
    |> List.sort String.compare
  in
  let expected_pages =
    Ui_page_registry.all
    |> List.map (fun value -> value.Ui_page_registry.id)
    |> List.sort String.compare
  in
  reject (List.sort String.compare component_names <> expected_components)
    "Figma/Bonsai component mapping is not bijective";
  reject
    ((List.map (fun (value : product_screen) -> value.page_id) catalog.product_screens
      |> List.sort String.compare)
    <> expected_pages)
    "Figma/page registry mapping is not bijective";
  if !errors = [] then Ok () else Error (List.rev !errors)

let token_kind_name = function
  | Color -> "COLOR"
  | Number -> "FLOAT"
  | String -> "STRING"
  | Boolean -> "BOOLEAN"

let string_list values = `List (List.map (fun value -> `String value) values)

let token_to_yojson = function
  | Primitive value ->
      `Assoc
        [
          ("name", `String value.name);
          ("layer", `String "primitive");
          ("kind", `String (token_kind_name value.kind));
          ("value", `String value.value);
          ("scope", `String value.scope);
        ]
  | Semantic value ->
      `Assoc
        [
          ("name", `String value.name);
          ("layer", `String "semantic");
          ("kind", `String (token_kind_name value.kind));
          ("light_alias", `String value.light_alias);
          ("dark_alias", `String value.dark_alias);
          ("scope", `String value.scope);
          ("web_syntax", `String value.css);
        ]

let to_yojson (catalog : catalog) =
  `Assoc
    [
      ("schema", `String "zigvm.figma-design/v2");
      ("authority", `String "OCaml-owned; Figma is an external interpretation");
      ("modes", string_list catalog.modes);
      ("minimum_target", `Int catalog.minimum_target);
      ( "breakpoints",
        `List
          (List.map
             (fun (name, width) ->
               `Assoc [ ("name", `String name); ("min_width", `Int width) ])
             catalog.breakpoints) );
      ("tokens", `List (List.map token_to_yojson catalog.tokens));
      ( "pages",
        `List
          (List.map
             (fun (value : figma_page) ->
               `Assoc
                 [
                   ("name", `String value.name);
                   ("order", `Int value.order);
                   ("purpose", `String value.purpose);
                 ])
             catalog.pages) );
      ( "components",
        `List
          (List.map
             (fun (value : component) ->
               `Assoc
                 [
                   ("name", `String value.name);
                   ("figma_name", `String value.figma_name);
                   ("test_id_prefix", `String value.test_id_prefix);
                   ("variants", string_list value.variants);
                   ("interactive", `Bool value.interactive);
                   ("minimum_width", `Int value.minimum_width);
                   ("minimum_height", `Int value.minimum_height);
                   ("accessible_role", `String value.accessible_role);
                   ("event_ids", string_list value.event_ids);
                   ("tokens", string_list value.token_names);
                 ])
             catalog.components) );
      ( "product_screens",
        `List
          (List.map
             (fun (value : product_screen) ->
               `Assoc
                 [
                   ("page_id", `String value.page_id);
                   ("name", `String value.name);
                   ("route", `String value.route);
                   ("figma_page", `String value.figma_page);
                   ("states", string_list value.states);
                   ("capability_ids", string_list value.capability_ids);
                   ("components", string_list value.component_names);
                   ("evidence", `String value.evidence);
                 ])
             catalog.product_screens) );
      ( "screens",
        `List
          (List.map
             (fun (value : screen) ->
               `Assoc
                 [
                   ("name", `String value.name);
                   ("page_id", `String value.page_id);
                   ("window_class", `String value.window_class);
                   ("width", `Int value.width);
                   ("height", `Int value.height);
                   ("components", string_list value.component_names);
                 ])
             catalog.screens) );
      ( "transitions",
        `List
          (List.map
             (fun (value : transition) ->
               `Assoc
                 [
                   ("name", `String value.name);
                   ("source", `String value.source);
                   ("target", `String value.target);
                   ("trigger", `String value.trigger);
                 ])
             catalog.transitions) );
    ]
