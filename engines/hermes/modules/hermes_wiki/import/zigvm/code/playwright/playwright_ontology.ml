type component_kind = Interface | Value

type component = {
  name : string;
  kind : component_kind;
  initializer_fields : string list;
  commands : string list;
  events : string list;
  references : string list;
}

type t = {
  source : string;
  components : component list;
}

let object_fields = function `O fields -> fields | _ -> []

let member_names key fields =
  match List.assoc_opt key fields with
  | Some (`O members) -> List.map fst members
  | _ -> []

let initializer_fields fields =
  match List.assoc_opt "initializer" fields with
  | Some (`O fields) -> member_names "properties" fields
  | _ -> []

let strip_optional name =
  let length = String.length name in
  if length > 0 && name.[length - 1] = '?' then String.sub name 0 (length - 1)
  else name

let references known value =
  let seen = Hashtbl.create 32 in
  let rec visit = function
    | `String raw ->
        let name = strip_optional raw in
        if Hashtbl.mem known name then Hashtbl.replace seen name ()
    | `A values -> List.iter visit values
    | `O fields -> List.iter (fun (_, value) -> visit value) fields
    | `Null | `Bool _ | `Float _ -> ()
  in
  visit value;
  Hashtbl.to_seq_keys seen |> List.of_seq |> List.sort String.compare

let load path =
  let channel = open_in_bin path in
  let length = in_channel_length channel in
  let source = really_input_string channel length in
  close_in channel;
  let document = Yaml.of_string_exn source in
  let entries = object_fields document in
  let known = Hashtbl.create (List.length entries) in
  List.iter (fun (name, _) -> Hashtbl.replace known name ()) entries;
  let components =
    entries
    |> List.map (fun (name, value) ->
           let fields = object_fields value in
           let commands = member_names "commands" fields in
           let events = member_names "events" fields in
           let initializer_fields = initializer_fields fields in
           let kind =
             if commands <> [] || events <> [] || List.mem_assoc "initializer" fields
             then Interface
             else Value
           in
           {
             name;
             kind;
             initializer_fields;
             commands;
             events;
             references = references known value;
           })
  in
  { source = path; components }

let command_count ontology =
  List.fold_left (fun count component -> count + List.length component.commands) 0
    ontology.components

let event_count ontology =
  List.fold_left (fun count component -> count + List.length component.events) 0
    ontology.components

let interface_count ontology =
  List.fold_left
    (fun count component ->
      match component.kind with Interface -> count + 1 | Value -> count)
    0 ontology.components

let snake_case name =
  let buffer = Buffer.create (String.length name + 8) in
  String.iteri
    (fun index character ->
      if character >= 'A' && character <= 'Z' then begin
        let previous_is_lower =
          index > 0
          && let previous = name.[index - 1] in
             (previous >= 'a' && previous <= 'z') || (previous >= '0' && previous <= '9')
        in
        let next_is_lower =
          index + 1 < String.length name
          && let next = name.[index + 1] in
             next >= 'a' && next <= 'z'
        in
        if index > 0 && (previous_is_lower || next_is_lower) then Buffer.add_char buffer '_';
        Buffer.add_char buffer (Char.lowercase_ascii character)
      end
      else Buffer.add_char buffer character)
    name;
  match Buffer.contents buffer with
  | ( "and" | "as" | "assert" | "begin" | "class" | "constraint" | "do"
    | "done" | "downto" | "else" | "end" | "exception" | "external"
    | "false" | "for" | "fun" | "function" | "functor" | "if" | "in"
    | "include" | "inherit" | "initializer" | "lazy" | "let" | "match"
    | "method" | "module" | "mutable" | "new" | "nonrec" | "object"
    | "of" | "open" | "or" | "private" | "rec" | "sig" | "struct"
    | "then" | "to" | "true" | "try" | "type" | "val" | "virtual"
    | "when" | "while" | "with" ) as keyword ->
      keyword ^ "_"
  | value -> value

let find_substring ?(offset = 0) text pattern =
  let rec search index =
    if index + String.length pattern > String.length text then None
    else if String.sub text index (String.length pattern) = pattern then Some index
    else search (index + 1)
  in
  search offset

let contains_symbol api symbol = Option.is_some (find_substring api symbol)

let component_api api name =
  let markers = [ "\nand " ^ name ^ " : sig"; "module rec " ^ name ^ " : sig" ] in
  match List.find_map (find_substring api) markers with
  | None -> ""
  | Some start ->
      let body_start = start + 1 in
      let body_end =
        find_substring ~offset:body_start api "\nend\nand "
        |> Option.value ~default:(String.length api)
      in
      String.sub api body_start (body_end - body_start)

let missing_bindings ~symbols members ontology api =
  ontology.components
  |> List.concat_map (fun component ->
         let api = component_api api component.name in
         members component
         |> List.filter_map (fun member ->
                let present =
                  symbols (snake_case member)
                  |> List.exists (fun name -> contains_symbol api ("val " ^ name ^ " :"))
                in
                if present then None
                else Some (component.name ^ "." ^ member)))

let missing_command_bindings ontology api =
  missing_bindings
    ~symbols:(fun name -> [ name; name ^ "_raw" ])
    (fun component -> component.commands) ontology api

let missing_event_bindings ontology api =
  missing_bindings
    ~symbols:(fun name -> [ "on_" ^ name ])
    (fun component -> component.events) ontology api

let kind_name = function Interface -> "interface" | Value -> "value"

let component_json component =
  `Assoc
    [
      ("name", `String component.name);
      ("kind", `String (kind_name component.kind));
      ("initializer_fields", `List (List.map (fun x -> `String x) component.initializer_fields));
      ("commands", `List (List.map (fun x -> `String x) component.commands));
      ("events", `List (List.map (fun x -> `String x) component.events));
      ("references", `List (List.map (fun x -> `String x) component.references));
    ]

let to_yojson ontology =
  `Assoc
    [
      ("schema", `String "zigvm.playwright.ontology/v1");
      ("source", `String ontology.source);
      ("component_count", `Int (List.length ontology.components));
      ("interface_count", `Int (interface_count ontology));
      ("command_count", `Int (command_count ontology));
      ("event_count", `Int (event_count ontology));
      ("components", `List (List.map component_json ontology.components));
    ]

let render_markdown ontology =
  let buffer = Buffer.create 32768 in
  Buffer.add_string buffer "# Playwright OCaml control-surface inventory\n\n";
  Buffer.add_string buffer
    (Printf.sprintf
       "Protocol-derived inventory: **%d components**, **%d interfaces**, **%d commands**, and **%d events**. Every command and event below is generated into the typed OCaml `playwright` library; project control code calls that library directly.\n\n"
       (List.length ontology.components) (interface_count ontology)
       (command_count ontology) (event_count ontology));
  Buffer.add_string buffer
    "| Component | Kind | Init | Commands | Events | References |\n|---|---:|---:|---|---|---|\n";
  List.iter
    (fun component ->
      let join values = if values = [] then "-" else String.concat ", " values in
      Buffer.add_string buffer
        (Printf.sprintf "| `%s` | %s | %d | %s | %s | %s |\n"
           component.name (kind_name component.kind)
           (List.length component.initializer_fields)
           (join component.commands) (join component.events)
           (join component.references)))
    ontology.components;
  Buffer.contents buffer

let xml_escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '&' -> Buffer.add_string buffer "&amp;"
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;"
      | '"' -> Buffer.add_string buffer "&quot;"
      | '\'' -> Buffer.add_string buffer "&apos;"
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let render_graphml ontology =
  let buffer = Buffer.create 65536 in
  Buffer.add_string buffer
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\">\n<key id=\"kind\" for=\"node\" attr.name=\"kind\" attr.type=\"string\"/>\n<key id=\"rel\" for=\"edge\" attr.name=\"relation\" attr.type=\"string\"/>\n<graph id=\"playwright-ocaml\" edgedefault=\"directed\">\n";
  List.iter
    (fun component ->
      Buffer.add_string buffer
        (Printf.sprintf "<node id=\"component:%s\"><data key=\"kind\">%s</data></node>\n"
           (xml_escape component.name) (kind_name component.kind));
      List.iter
        (fun command ->
          let id = component.name ^ ".command." ^ command in
          Buffer.add_string buffer
            (Printf.sprintf "<node id=\"%s\"><data key=\"kind\">command</data></node>\n<edge source=\"component:%s\" target=\"%s\"><data key=\"rel\">controls</data></edge>\n"
               (xml_escape id) (xml_escape component.name) (xml_escape id)))
        component.commands;
      List.iter
        (fun event ->
          let id = component.name ^ ".event." ^ event in
          Buffer.add_string buffer
            (Printf.sprintf "<node id=\"%s\"><data key=\"kind\">event</data></node>\n<edge source=\"%s\" target=\"component:%s\"><data key=\"rel\">observes</data></edge>\n"
               (xml_escape id) (xml_escape id) (xml_escape component.name)))
        component.events;
      List.iter
        (fun target ->
          if target <> component.name then
            Buffer.add_string buffer
              (Printf.sprintf "<edge source=\"component:%s\" target=\"component:%s\"><data key=\"rel\">references</data></edge>\n"
                 (xml_escape component.name) (xml_escape target)))
        component.references)
    ontology.components;
  Buffer.add_string buffer "</graph>\n</graphml>\n";
  Buffer.contents buffer
