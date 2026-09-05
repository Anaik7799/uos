type family =
  | Foundation
  | Linking
  | Productivity
  | Media
  | Tools
  | Customization
  | Formats
  | Database_graph
  | Ecosystem

type disposition =
  | Exact
  | Equivalent
  | Advisory
  | Unsupported of string
  | Unavailable of string

type feature = {
  id : string;
  family : family;
  disposition : disposition;
  wiki_mapping : string;
  zk_mapping : string;
  source : string;
}

type source_authority = Official_docs | Source_repository | Community_advisory
type source_row = {
  feature_id : string;
  coordinate : string;
  revision : string;
  family : family;
  authority : source_authority;
  executable_authority : bool;
}

type property = { key : string; value : string }

type task = {
  state : string;
  priority : string option;
  content : string;
}

type edge_kind = Page_reference | Block_reference | Tag_reference
type edge = { kind : edge_kind; target : string }

type document = {
  source_text : string;
  page_refs : string list;
  block_refs : string list;
  property_values : property list;
  task_values : task list;
  tag_values : string list;
}

type disposition_counts = {
  total : int;
  exact : int;
  equivalent : int;
  advisory : int;
  unsupported : int;
  unavailable : int;
}

let all_families =
  [ Foundation; Linking; Productivity; Media; Tools; Customization; Formats;
    Database_graph; Ecosystem ]

let docs = "https://docs.logseq.com/#/page/contents"
let repo = "https://github.com/logseq/logseq"
let awesome = "https://github.com/logseq/awesome-logseq"
let upstream_revision = "9a11243d50b23afeb10bda5a2ca6cc77357eea38"

let feature ?(wiki = "registered observer") ?(zk = "registered edge/view")
    ?(source = docs) id family disposition =
  { id; family; disposition; wiki_mapping = wiki; zk_mapping = zk; source }

let catalog =
  [ feature "graph-from-existing-markdown" Foundation Equivalent
      ~wiki:"Docs_wiki corpus" ~zk:"plain-file graph";
    feature "journals" Foundation Equivalent ~wiki:"chronology view"
      ~zk:"journal source notes";
    feature "pages" Foundation Equivalent ~wiki:"wiki page"
      ~zk:"stable note node";
    feature "indented-blocks" Foundation Equivalent ~wiki:"nested list"
      ~zk:"block containment edge";
    feature "right-sidebar" Foundation (Unsupported "Logseq application UI")
      ~wiki:"multi-note neighborhood" ~zk:"two-hop neighborhood";
    feature "file-graph-sync" Foundation Advisory
      ~wiki:"external synchronization only" ~zk:"fixity/readback boundary";
    feature "backlinks" Linking Exact ~wiki:"backlink observer"
      ~zk:"reverse edge";
    feature "page-references" Linking Exact ~wiki:"wikilink"
      ~zk:"page-reference edge";
    feature "block-references" Linking Equivalent ~wiki:"block anchor link"
      ~zk:"block-reference edge";
    feature "page-embeds" Linking Equivalent ~wiki:"transclusion registration"
      ~zk:"page-embed edge";
    feature "block-embeds" Linking Equivalent ~wiki:"block transclusion registration"
      ~zk:"block-embed edge";
    feature "aliases" Linking Equivalent ~wiki:"alias resolution"
      ~zk:"same-identity observation";
    feature "external-links" Linking Exact ~wiki:"external anchor"
      ~zk:"external relation";
    feature "linked-reference-filter" Linking Equivalent
      ~wiki:"typed neighborhood filter" ~zk:"edge predicate";
    feature "unlinked-references" Linking Advisory
      ~wiki:"lexical suggestion only" ~zk:"candidate edge, never automatic";
    feature "namespaces" Linking Equivalent ~wiki:"hierarchical slug"
      ~zk:"namespace-parent edge";
    feature "page-properties" Productivity Equivalent ~wiki:"frontmatter/property view"
      ~zk:"typed metadata";
    feature "block-properties" Productivity Equivalent ~wiki:"block metadata"
      ~zk:"property edge";
    feature "tags" Productivity Exact ~wiki:"tag index" ~zk:"tag edge";
    feature "tasks" Productivity Equivalent ~wiki:"task state projection"
      ~zk:"workflow metadata";
    feature "priorities" Productivity Equivalent ~wiki:"task priority"
      ~zk:"priority property";
    feature "scheduled-deadline" Productivity Equivalent ~wiki:"temporal property"
      ~zk:"journal/date edge";
    feature "commands" Productivity (Unsupported "interactive slash-command UI")
      ~wiki:"typed operation registry" ~zk:"operation provenance";
    feature "advanced-commands" Productivity (Unsupported "interactive editor UI")
      ~wiki:"typed operation registry" ~zk:"operation provenance";
    feature "simple-queries" Productivity Equivalent ~wiki:"zkquery subset"
      ~zk:"query AST";
    feature "advanced-datalog-queries" Productivity
      (Unsupported "Logseq DataScript/DB query semantics are external")
      ~wiki:"unsupported query preserved verbatim" ~zk:"query source node";
    feature "query-builder" Productivity Equivalent ~wiki:"typed query form"
      ~zk:"query AST builder";
    feature "templates" Productivity Equivalent ~wiki:"versioned template expansion"
      ~zk:"template-source edge";
    feature "pdf-highlights" Media Advisory ~wiki:"declared annotation artifact"
      ~zk:"source/annotation edge";
    feature "whiteboards" Media (Unsupported "Logseq canvas runtime")
      ~wiki:"image/export artifact only" ~zk:"whiteboard source node";
    feature "audio-embed" Media Equivalent ~wiki:"HTML media reference"
      ~zk:"asset edge";
    feature "photo-embed" Media Equivalent ~wiki:"image artifact"
      ~zk:"asset edge";
    feature "video-embed" Media Equivalent ~wiki:"HTML media reference"
      ~zk:"asset edge";
    feature "draw-excalidraw" Media (Unsupported "external drawing runtime")
      ~wiki:"exported image only" ~zk:"asset/source edge";
    feature "zotero" Media (Unavailable "no configured Zotero connector")
      ~wiki:"citation projection" ~zk:"source/citation edge";
    feature "flashcards" Tools Advisory ~wiki:"card-tag view"
      ~zk:"card relation; no scheduler parity";
    feature "slides" Tools (Unsupported "removed/moved to plugin in DB profile")
      ~wiki:"presentation projection residual" ~zk:"source node";
    feature "calculator" Tools (Unsupported "Logseq expression evaluator")
      ~wiki:"literal expression only" ~zk:"calculation source";
    feature "tables" Tools Exact ~wiki:"Markdown table" ~zk:"structured observation";
    feature "publishing" Tools Equivalent ~wiki:"self-contained HTML/DIP"
      ~zk:"published-view edge";
    feature "knowledge-graph" Tools Equivalent ~wiki:"Docs_wiki graph"
      ~zk:"typed graph";
    feature "search" Tools Equivalent ~wiki:"full-text/index query"
      ~zk:"query observer";
    feature "user-configuration" Customization Advisory
      ~wiki:"versioned profile only" ~zk:"configuration source";
    feature "custom-themes" Customization Advisory ~source:awesome
      ~wiki:"design-token mapping" ~zk:"theme provenance";
    feature "plugins" Customization (Unsupported "untrusted JS/CLJS plugin runtime")
      ~source:awesome ~wiki:"catalog metadata only" ~zk:"plugin provenance";
    feature "plugin-api" Customization (Unsupported "external Logseq runtime API")
      ~source:repo ~wiki:"capability catalog" ~zk:"API source node";
    feature "markdown" Formats Exact ~wiki:"authoritative Markdown"
      ~zk:"authoritative note";
    feature "org-mode" Formats (Unsupported "DB graph no longer supports Org mode")
      ~wiki:"preserved source artifact" ~zk:"migration residual";
    feature "hiccup" Formats (Unsupported "Clojure/HTML expression runtime")
      ~wiki:"escaped literal" ~zk:"source node";
    feature "graph-export" Formats Equivalent ~wiki:"HTML/JSON projection"
      ~zk:"AIP/DIP export";
    feature "graph-import" Formats Equivalent ~wiki:"validated Markdown ingest"
      ~zk:"SIP ingest";
    feature "edn-data" Formats (Unsupported "EDN database encoding")
      ~wiki:"preserved external artifact" ~zk:"format residual";
    feature "db-nodes" Database_graph Equivalent ~source:repo
      ~wiki:"page/block carrier" ~zk:"node carrier";
    feature "typed-properties" Database_graph Equivalent ~source:repo
      ~wiki:"typed metadata projection" ~zk:"property carrier";
    feature "tag-based-features" Database_graph Equivalent ~source:repo
      ~wiki:"tag views" ~zk:"tag predicates";
    feature "cards" Database_graph Advisory ~source:repo
      ~wiki:"card-tag observer" ~zk:"card node";
    feature "assets-as-blocks" Database_graph Equivalent ~source:repo
      ~wiki:"artifact record" ~zk:"asset node/edge";
    feature "bulk-actions" Database_graph (Unsupported "interactive Logseq UI")
      ~source:repo ~wiki:"bounded batch operation only" ~zk:"operation trace";
    feature "table-views" Database_graph Equivalent ~source:repo
      ~wiki:"table observer" ~zk:"query view";
    feature "library" Database_graph Equivalent ~source:repo
      ~wiki:"index/MoC" ~zk:"corpus catalog";
    feature "mcp-server" Database_graph (Unavailable "no Logseq MCP endpoint configured")
      ~source:repo ~wiki:"external readback boundary" ~zk:"connector provenance";
    feature "rtc-sync" Database_graph (Unavailable "Logseq RTC alpha external service")
      ~source:repo ~wiki:"no authority" ~zk:"sync residual";
    feature "automated-backup" Database_graph Equivalent ~source:repo
      ~wiki:"AIP/fixity copy profile" ~zk:"snapshot provenance";
    feature "mobile-apps" Database_graph (Unavailable "external iOS/Android deployment")
      ~source:repo ~wiki:"responsive web DIP" ~zk:"deployment residual";
    feature "scripting" Database_graph (Unsupported "authored JS/CLJS prohibited")
      ~source:repo ~wiki:"OCaml typed operations only" ~zk:"operation provenance";
    feature "css-theme-catalog" Ecosystem Advisory ~source:awesome
      ~wiki:"token inspiration catalog" ~zk:"source provenance";
    feature "plugin-catalog" Ecosystem Advisory ~source:awesome
      ~wiki:"untrusted extension catalog" ~zk:"source provenance";
    feature "third-party-integrations" Ecosystem Advisory ~source:awesome
      ~wiki:"connector registry" ~zk:"external dependency edge";
    feature "guides-howtos" Ecosystem Advisory ~source:awesome
      ~wiki:"source catalog" ~zk:"source notes";
    feature "workflows" Ecosystem Advisory ~source:awesome
      ~wiki:"pattern catalog" ~zk:"workflow source";
    feature "bibliography-pdf-integrations" Ecosystem Advisory ~source:awesome
      ~wiki:"citation/profile catalog" ~zk:"source/citation edges";
    feature "community-gardens" Ecosystem Advisory ~source:awesome
      ~wiki:"external garden catalog" ~zk:"external relation" ]

let authority_of_source source =
  if String.equal source awesome then Community_advisory
  else if String.equal source repo then Source_repository
  else Official_docs

let source_census =
  List.map
    (fun feature ->
      let authority = authority_of_source feature.source in
      { feature_id = feature.id; coordinate = feature.source;
        revision = upstream_revision; family = feature.family; authority;
        executable_authority =
          (match authority with Community_advisory -> false | _ -> true) })
    catalog

let features_in_family family =
  List.filter (fun (feature : feature) -> feature.family = family) catalog

let duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop found = function
    | first :: (second :: _ as rest) when String.equal first second ->
        loop (first :: found) rest
    | _ :: rest -> loop found rest
    | [] -> List.sort_uniq String.compare found
  in
  loop [] sorted

let catalog_violations features =
  let duplicate_errors =
    features |> List.map (fun feature -> feature.id) |> duplicates
    |> List.map (fun id -> "duplicate-feature-id:" ^ id)
  in
  let field_errors =
    features
    |> List.concat_map (fun feature ->
         [ if String.trim feature.id = "" then Some "empty-feature-id" else None;
           if String.trim feature.wiki_mapping = "" then
             Some ("empty-wiki-mapping:" ^ feature.id) else None;
           if String.trim feature.zk_mapping = "" then
             Some ("empty-zk-mapping:" ^ feature.id) else None;
           if String.trim feature.source = "" then
             Some ("empty-source:" ^ feature.id) else None ]
         |> List.filter_map Fun.id)
  in
  duplicate_errors @ field_errors

let census_violations features rows =
  let feature_ids = List.map (fun feature -> feature.id) features |> List.sort String.compare in
  let row_ids = List.map (fun row -> row.feature_id) rows |> List.sort String.compare in
  let errors = ref [] in
  let reject condition message = if condition then errors := message :: !errors in
  reject (duplicates row_ids <> []) "duplicate-source-feature-id";
  reject (feature_ids <> row_ids) "source-census-feature-coverage-differs";
  List.iter
    (fun row ->
      reject (String.trim row.coordinate = "") ("blank-source-coordinate:" ^ row.feature_id);
      reject (String.trim row.revision = "") ("blank-source-revision:" ^ row.feature_id);
      (match List.find_opt (fun feature -> String.equal feature.id row.feature_id) features with
       | None -> ()
       | Some feature ->
           reject (feature.family <> row.family) ("source-family-mismatch:" ^ row.feature_id));
      match row.authority with
      | Community_advisory ->
          reject row.executable_authority ("community-source-has-executable-authority:" ^ row.feature_id)
      | Official_docs | Source_repository -> ())
    rows;
  List.rev !errors

let disposition_counts features =
  List.fold_left
    (fun counts feature ->
      match feature.disposition with
      | Exact -> { counts with total = counts.total + 1; exact = counts.exact + 1 }
      | Equivalent ->
          { counts with total = counts.total + 1;
                        equivalent = counts.equivalent + 1 }
      | Advisory ->
          { counts with total = counts.total + 1;
                        advisory = counts.advisory + 1 }
      | Unsupported _ ->
          { counts with total = counts.total + 1;
                        unsupported = counts.unsupported + 1 }
      | Unavailable _ ->
          { counts with total = counts.total + 1;
                        unavailable = counts.unavailable + 1 })
    { total = 0; exact = 0; equivalent = 0; advisory = 0;
      unsupported = 0; unavailable = 0 }
    features

let extract_between ~left ~right text =
  let left_length = String.length left in
  let right_length = String.length right in
  let rec loop offset found =
    match String.index_from_opt text offset left.[0] with
    | None -> List.rev found
    | Some start when
        start + left_length <= String.length text &&
        String.sub text start left_length = left ->
        let content_start = start + left_length in
        let rec find_right cursor =
          if cursor + right_length > String.length text then None
          else if String.sub text cursor right_length = right then Some cursor
          else find_right (cursor + 1)
        in
        (match find_right content_start with
         | None -> List.rev found
         | Some finish ->
             let value = String.sub text content_start (finish - content_start) in
             loop (finish + right_length) (value :: found))
    | Some start -> loop (start + 1) found
  in
  if left = "" || right = "" then [] else loop 0 []

let unique_ordered values =
  List.fold_left
    (fun found value -> if List.mem value found then found else found @ [ value ])
    [] values

let parse_property line =
  match String.index_opt line ':' with
  | Some index when index + 1 < String.length line && line.[index + 1] = ':' ->
      let key = String.sub line 0 index |> String.trim in
      let value =
        String.sub line (index + 2) (String.length line - index - 2)
        |> String.trim
      in
      if key = "" then None else Some { key; value }
  | _ -> None

let strip_block_prefix line =
  let trimmed = String.trim line in
  if String.length trimmed >= 2 && String.sub trimmed 0 2 = "- " then
    String.sub trimmed 2 (String.length trimmed - 2)
  else trimmed

let parse_task line =
  let content = strip_block_prefix line in
  let states = [ "TODO"; "DOING"; "DONE"; "NOW"; "LATER"; "WAITING"; "CANCELED" ] in
  match List.find_opt
          (fun state -> String.starts_with ~prefix:(state ^ " ") content)
          states
  with
  | None -> None
  | Some state ->
      let rest =
        String.sub content (String.length state + 1)
          (String.length content - String.length state - 1)
      in
      let priority, content =
        if String.length rest >= 5 && String.sub rest 0 2 = "[#" && rest.[3] = ']' && rest.[4] = ' '
        then
          Some (String.sub rest 2 1),
          String.sub rest 5 (String.length rest - 5)
        else None, rest
      in
      Some { state; priority; content }

let tags text =
  let length = String.length text in
  let is_tag_char = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '/' -> true
    | _ -> false
  in
  let rec loop index found =
    if index >= length then List.rev found
    else if text.[index] = '#' && (index = 0 || text.[index - 1] <> '[') then
      let rec finish cursor =
        if cursor < length && is_tag_char text.[cursor] then finish (cursor + 1)
        else cursor
      in
      let stop = finish (index + 1) in
      if stop = index + 1 then loop (index + 1) found
      else
        loop stop (String.sub text (index + 1) (stop - index - 1) :: found)
    else loop (index + 1) found
  in
  loop 0 [] |> unique_ordered

let parse_document source_text =
  let lines = String.split_on_char '\n' source_text in
  let property_values = List.filter_map parse_property lines in
  let task_values = List.filter_map parse_task lines in
  { source_text;
    page_refs = extract_between ~left:"[[" ~right:"]]" source_text |> unique_ordered;
    block_refs = extract_between ~left:"((" ~right:"))" source_text |> unique_ordered;
    property_values;
    task_values;
    tag_values = tags source_text }

let render_document document = document.source_text
let page_references document = document.page_refs
let block_references document = document.block_refs
let properties document = document.property_values
let tasks document = document.task_values
let wiki_links document = document.page_refs

let zk_edges document =
  List.map (fun target -> { kind = Page_reference; target }) document.page_refs @
  List.map (fun target -> { kind = Block_reference; target }) document.block_refs @
  List.map (fun target -> { kind = Tag_reference; target }) document.tag_values

let edge_target edge = edge.target

let family_name = function
  | Foundation -> "foundation"
  | Linking -> "linking"
  | Productivity -> "productivity"
  | Media -> "media"
  | Tools -> "tools"
  | Customization -> "customization"
  | Formats -> "formats"
  | Database_graph -> "database_graph"
  | Ecosystem -> "ecosystem"

let disposition_json = function
  | Exact -> `Assoc [ "class", `String "Exact" ]
  | Equivalent -> `Assoc [ "class", `String "Equivalent" ]
  | Advisory -> `Assoc [ "class", `String "Advisory" ]
  | Unsupported reason ->
      `Assoc [ "class", `String "Unsupported"; "reason", `String reason ]
  | Unavailable reason ->
      `Assoc [ "class", `String "Unavailable"; "reason", `String reason ]

let catalog_to_yojson features =
  `Assoc
    [ "schema_version", `Int 1;
      "upstream_repository", `String repo;
      "upstream_revision", `String upstream_revision;
      "observed_at", `String "2026-08-04-0859";
      "features",
      `List
        (List.map
           (fun feature ->
             `Assoc
               [ "id", `String feature.id;
                 "family", `String (family_name feature.family);
                 "disposition", disposition_json feature.disposition;
                 "wiki_mapping", `String feature.wiki_mapping;
                 "zk_mapping", `String feature.zk_mapping;
                 "source", `String feature.source ])
           features) ]

let source_authority_name = function
  | Official_docs -> "official_docs"
  | Source_repository -> "source_repository"
  | Community_advisory -> "community_advisory"

let census_to_yojson rows =
  `Assoc [ "schema_version", `Int 1;
    "upstream_revision", `String upstream_revision;
    "observed_at", `String "20260804-085900";
    "rows", `List (List.map (fun row ->
      `Assoc [ "feature_id", `String row.feature_id;
        "family", `String (family_name row.family);
        "coordinate", `String row.coordinate;
        "revision", `String row.revision;
        "authority", `String (source_authority_name row.authority);
        "executable_authority", `Bool row.executable_authority ]) rows) ]
