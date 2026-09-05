type artifact = {
  path : string;
  kind : string;
  extension : string;
  bytes : int;
  title : string option;
}

type package = {
  name : string;
  manifest : string;
  dependencies : string list;
}

type t = {
  root : string;
  revision : string;
  tree : string;
  artifacts : artifact list;
  packages : package list;
}

let starts_with ~prefix value =
  String.length value >= String.length prefix
  && String.sub value 0 (String.length prefix) = prefix

let extension path =
  match Filename.extension path with
  | "" -> "(none)"
  | value -> String.sub value 1 (String.length value - 1)

let classify path =
  if starts_with ~prefix:"docs/" path then "documentation"
  else if Filename.basename path = "package.json" then "package-manifest"
  else if starts_with ~prefix:"browser_patches/" path then "browser-patch"
  else if starts_with ~prefix:"packages/playwright-core/src/protocol/" path then "wire-protocol"
  else if starts_with ~prefix:"packages/playwright-core/src/client/" path then "client-api"
  else if starts_with ~prefix:"packages/playwright-core/src/server/chromium/" path then "chromium-adapter"
  else if starts_with ~prefix:"packages/playwright-core/src/server/firefox/" path then "firefox-adapter"
  else if starts_with ~prefix:"packages/playwright-core/src/server/webkit/" path then "webkit-adapter"
  else if starts_with ~prefix:"packages/playwright-core/src/server/bidi/" path then "web-bidi-adapter"
  else if starts_with ~prefix:"packages/playwright-core/src/server/android/" path then "android-adapter"
  else if starts_with ~prefix:"packages/playwright-core/src/server/dispatchers/" path then "dispatcher"
  else if starts_with ~prefix:"packages/playwright-core/src/server/registry/" path then "browser-delivery"
  else if starts_with ~prefix:"packages/playwright-core/src/server/har/" path then "network-data"
  else if starts_with ~prefix:"packages/playwright-core/src/server/trace/" path then "trace-runtime"
  else if starts_with ~prefix:"packages/playwright-core/src/server/recorder/" path then "recorder-runtime"
  else if starts_with ~prefix:"packages/playwright-core/src/server/codegen/" path then "code-generation"
  else if starts_with ~prefix:"packages/playwright-core/src/server/electron/" path then "electron-adapter"
  else if starts_with ~prefix:"packages/playwright-core/src/server/injected" path
          || starts_with ~prefix:"packages/playwright-core/src/server/selectors" path
  then "page-semantics"
  else if starts_with ~prefix:"packages/playwright-core/src/server/" path then "browser-server"
  else if starts_with ~prefix:"packages/playwright-core/src/remote/" path then "remote-transport"
  else if starts_with ~prefix:"packages/playwright-core/src/tools/" path then "agent-tooling"
  else if starts_with ~prefix:"packages/playwright-core/src/cli/" path then "cli-tooling"
  else if starts_with ~prefix:"packages/playwright-core/src/utils/" path then "shared-utility"
  else if starts_with ~prefix:"packages/playwright/src/runner/" path
          || starts_with ~prefix:"packages/playwright-test/" path
  then "test-runner"
  else if starts_with ~prefix:"packages/playwright/src/common/" path then "test-model"
  else if starts_with ~prefix:"packages/playwright/src/matchers/" path then "assertion-runtime"
  else if starts_with ~prefix:"packages/playwright/src/reporters/" path then "reporter-runtime"
  else if starts_with ~prefix:"packages/playwright/src/worker/" path then "test-worker"
  else if starts_with ~prefix:"packages/playwright/src/loader/" path
          || starts_with ~prefix:"packages/playwright/src/transform/" path
  then "test-loading"
  else if starts_with ~prefix:"packages/playwright/src/plugins/" path then "test-plugin"
  else if starts_with ~prefix:"packages/playwright/src/agents/" path
          || starts_with ~prefix:"packages/playwright/src/mcp/" path
  then "agent-tooling"
  else if starts_with ~prefix:"packages/trace-viewer/" path then "trace-viewer"
  else if starts_with ~prefix:"packages/html-reporter/" path then "html-reporter"
  else if starts_with ~prefix:"packages/recorder/" path then "recorder-ui"
  else if starts_with ~prefix:"packages/web/" path || starts_with ~prefix:"packages/dashboard/" path
  then "web-ui"
  else if starts_with ~prefix:"packages/playwright-ct-" path then "component-testing"
  else if starts_with ~prefix:"packages/" path then "package-runtime"
  else if starts_with ~prefix:"tests/" path then "test-corpus"
  else if starts_with ~prefix:"examples/" path then "example-corpus"
  else if starts_with ~prefix:"utils/" path then "build-release-tooling"
  else if starts_with ~prefix:".github/" path || starts_with ~prefix:".azure-pipelines/" path
  then "ci-governance"
  else "repository-foundation"

let first_heading path =
  let channel = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
      let rec loop metadata_title remaining =
        if remaining = 0 then metadata_title
        else
          match input_line channel with
          | line when starts_with ~prefix:"# " line ->
              Some (String.sub line 2 (String.length line - 2) |> String.trim)
          | line when starts_with ~prefix:"title:" line ->
              let title = String.sub line 6 (String.length line - 6) |> String.trim in
              loop (Some title) (remaining - 1)
          | _ -> loop metadata_title (remaining - 1)
          | exception End_of_file -> metadata_title
      in
      loop None 80)

let rec files root relative accumulator =
  let path = if relative = "" then root else Filename.concat root relative in
  Sys.readdir path |> Array.to_list |> List.sort String.compare
  |> List.fold_left
       (fun accumulator name ->
         if name = ".git" || name = "node_modules" then accumulator
         else
           let child_relative = if relative = "" then name else Filename.concat relative name in
           let child = Filename.concat root child_relative in
           match (Unix.lstat child).Unix.st_kind with
           | Unix.S_DIR -> files root child_relative accumulator
           | kind ->
               let bytes = if kind = Unix.S_REG then (Unix.stat child).Unix.st_size else 0 in
               let title =
                 if starts_with ~prefix:"docs/" child_relative
                    && extension child_relative = "md"
                 then first_heading child
                 else None
               in
               { path = child_relative; kind = classify child_relative;
                 extension = extension child_relative; bytes; title }
               :: accumulator)
       accumulator

let assoc_fields key fields =
  match List.assoc_opt key fields with Some (`Assoc values) -> values | _ -> []

let package_of_artifact root artifact =
  if artifact.kind <> "package-manifest" then None
  else
    match Yojson.Safe.from_file (Filename.concat root artifact.path) with
    | `Assoc fields ->
        let name =
          match List.assoc_opt "name" fields with
          | Some (`String value) -> value
          | _ -> Filename.dirname artifact.path
        in
        let dependencies =
          [ "dependencies"; "devDependencies"; "peerDependencies"; "optionalDependencies" ]
          |> List.concat_map (fun key -> assoc_fields key fields |> List.map fst)
          |> List.sort_uniq String.compare
        in
        Some { name; manifest = artifact.path; dependencies }
    | _ -> None
    | exception Yojson.Json_error _ -> None

let load ~root ~revision ~tree =
  let root = Unix.realpath root in
  let artifacts = files root "" [] |> List.sort (fun a b -> String.compare a.path b.path) in
  let packages = artifacts |> List.filter_map (package_of_artifact root) in
  { root; revision; tree; artifacts; packages }

let count_kind ontology kind =
  List.fold_left (fun count artifact -> count + Bool.to_int (artifact.kind = kind)) 0
    ontology.artifacts

let documentation_count ontology = count_kind ontology "documentation"

let kind_counts ontology =
  let counts = Hashtbl.create 32 in
  List.iter
    (fun artifact ->
      Hashtbl.replace counts artifact.kind
        (1 + Option.value (Hashtbl.find_opt counts artifact.kind) ~default:0))
    ontology.artifacts;
  Hashtbl.to_seq counts |> List.of_seq |> List.sort (fun (a, _) (b, _) -> String.compare a b)

let extension_counts ontology =
  let counts = Hashtbl.create 32 in
  List.iter
    (fun artifact ->
      Hashtbl.replace counts artifact.extension
        (1 + Option.value (Hashtbl.find_opt counts artifact.extension) ~default:0))
    ontology.artifacts;
  Hashtbl.to_seq counts |> List.of_seq
  |> List.sort (fun (a, ac) (b, bc) ->
         let order = Int.compare bc ac in if order = 0 then String.compare a b else order)

let artifact_json artifact =
  `Assoc
    [ ("path", `String artifact.path); ("kind", `String artifact.kind);
      ("extension", `String artifact.extension); ("bytes", `Int artifact.bytes);
      ("title", match artifact.title with Some value -> `String value | None -> `Null) ]

let package_json package =
  `Assoc
    [ ("name", `String package.name); ("manifest", `String package.manifest);
      ("dependencies", `List (List.map (fun value -> `String value) package.dependencies)) ]

let to_yojson ontology =
  `Assoc
    [ ("schema", `String "zigvm.playwright.upstream-source-ontology/v1");
      ("upstream", `String "https://github.com/microsoft/playwright");
      ("revision", `String ontology.revision); ("tree", `String ontology.tree);
      ("artifact_count", `Int (List.length ontology.artifacts));
      ("documentation_count", `Int (documentation_count ontology));
      ("package_count", `Int (List.length ontology.packages));
      ("kind_counts", `Assoc (List.map (fun (name, count) -> name, `Int count) (kind_counts ontology)));
      ("extension_counts", `Assoc (List.map (fun (name, count) -> name, `Int count) (extension_counts ontology)));
      ("packages", `List (List.map package_json ontology.packages));
      ("artifacts", `List (List.map artifact_json ontology.artifacts)) ]

let markdown_escape value =
  value |> String.split_on_char '|' |> String.concat "\\|"

let render_markdown ontology =
  let buffer = Buffer.create 524288 in
  Buffer.add_string buffer "# Microsoft Playwright v1.59.0 source and documentation inventory\n\n";
  Buffer.add_string buffer
    (Printf.sprintf
       "Pinned source: `%s` (tree `%s`). Inventory: **%d artifacts**, **%d documentation artifacts**, **%d package manifests**. This is an external source dependency; ZigVM authors no TypeScript/JavaScript from this tree.\n\n"
       ontology.revision ontology.tree (List.length ontology.artifacts)
       (documentation_count ontology) (List.length ontology.packages));
  Buffer.add_string buffer "## Control and data domains\n\n";
  Buffer.add_string buffer
    "| Domain | Files | Runtime role | OCaml authority |\n|---|---:|---|---|\n";
  kind_counts ontology
  |> List.iter (fun (kind, count) ->
         Buffer.add_string buffer
           (Printf.sprintf "| `%s` | %d | upstream implementation/data surface | classified here only; executable authority and gaps are defined in `PLAYWRIGHT_OCAML_AUTHORITY.md` |\n"
              kind count));
  Buffer.add_string buffer "\n## Packages and dependency edges\n\n";
  Buffer.add_string buffer "| Package | Manifest | Dependencies |\n|---|---|---|\n";
  List.iter
    (fun package ->
      Buffer.add_string buffer
        (Printf.sprintf "| `%s` | `%s` | %s |\n" (markdown_escape package.name)
           package.manifest
           (if package.dependencies = [] then "-"
            else package.dependencies |> List.map (Printf.sprintf "`%s`") |> String.concat ", ")))
    ontology.packages;
  Buffer.add_string buffer "\n## Complete documentation corpus\n\n";
  Buffer.add_string buffer "| Path | Title | Bytes |\n|---|---|---:|\n";
  ontology.artifacts
  |> List.filter (fun artifact -> artifact.kind = "documentation")
  |> List.iter (fun artifact ->
         Buffer.add_string buffer
           (Printf.sprintf "| `%s` | %s | %d |\n" artifact.path
              (artifact.title |> Option.value ~default:"-" |> markdown_escape)
              artifact.bytes));
  Buffer.add_string buffer "\n## Complete source artifact corpus\n\n";
  Buffer.add_string buffer "| Path | Domain | Extension | Bytes |\n|---|---|---|---:|\n";
  List.iter
    (fun artifact ->
      Buffer.add_string buffer
        (Printf.sprintf "| `%s` | `%s` | `%s` | %d |\n" artifact.path artifact.kind
           artifact.extension artifact.bytes))
    ontology.artifacts;
  Buffer.contents buffer

let xml_escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '&' -> Buffer.add_string buffer "&amp;" | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;" | '"' -> Buffer.add_string buffer "&quot;"
      | '\'' -> Buffer.add_string buffer "&apos;" | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let render_graphml ontology =
  let buffer = Buffer.create 524288 in
  Buffer.add_string buffer
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"kind\" for=\"node\" attr.name=\"kind\" attr.type=\"string\"/><key id=\"rel\" for=\"edge\" attr.name=\"relation\" attr.type=\"string\"/><graph id=\"microsoft-playwright-source\" edgedefault=\"directed\">\n<node id=\"system:playwright\"><data key=\"kind\">system</data></node>\n";
  kind_counts ontology
  |> List.iter (fun (kind, _) ->
         Buffer.add_string buffer
           (Printf.sprintf "<node id=\"domain:%s\"><data key=\"kind\">domain</data></node>\n<edge source=\"system:playwright\" target=\"domain:%s\"><data key=\"rel\">contains</data></edge>\n"
              (xml_escape kind) (xml_escape kind)));
  List.iter
    (fun artifact ->
      Buffer.add_string buffer
        (Printf.sprintf "<node id=\"artifact:%s\"><data key=\"kind\">%s</data></node>\n<edge source=\"domain:%s\" target=\"artifact:%s\"><data key=\"rel\">contains</data></edge>\n"
           (xml_escape artifact.path) (xml_escape artifact.kind)
           (xml_escape artifact.kind) (xml_escape artifact.path)))
    ontology.artifacts;
  let package_names =
    ontology.packages |> List.map (fun package -> package.name)
    |> List.sort_uniq String.compare
  in
  let dependency_names =
    ontology.packages |> List.concat_map (fun package -> package.dependencies)
    |> List.sort_uniq String.compare
  in
  List.sort_uniq String.compare (package_names @ dependency_names)
  |> List.iter (fun name ->
         Buffer.add_string buffer
           (Printf.sprintf "<node id=\"package:%s\"><data key=\"kind\">%s</data></node>\n"
              (xml_escape name)
              (if List.mem name package_names then "package" else "external-package")));
  List.iter
    (fun package ->
      let package_id = "package:" ^ package.name in
      Buffer.add_string buffer
        (Printf.sprintf "<edge source=\"%s\" target=\"artifact:%s\"><data key=\"rel\">declaredBy</data></edge>\n"
           (xml_escape package_id) (xml_escape package.manifest));
      List.iter
        (fun dependency ->
          let target = "package:" ^ dependency in
          Buffer.add_string buffer
            (Printf.sprintf "<edge source=\"%s\" target=\"%s\"><data key=\"rel\">dependsOn</data></edge>\n"
               (xml_escape package_id) (xml_escape target)))
        package.dependencies)
    ontology.packages;
  Buffer.add_string buffer "</graph></graphml>\n";
  Buffer.contents buffer
