type plane = Control | Data | Event | Evidence | Lifecycle | Knowledge

type authority =
  | Typed_protocol
  | Ocaml_workflow
  | External_substrate
  | Knowledge_only
  | Gap

type layer =
  | Program
  | Harness
  | Binding
  | Driver
  | Browser
  | Context
  | Page
  | Frame
  | Locator
  | Artifact

type domain = {
  source_kind : string;
  authority : authority;
  planes : plane list;
  controller : string;
  boundary : string;
  inputs : string list;
  outputs : string list;
  laws : string list;
  residual : string;
}

type flow = {
  name : string;
  source : layer;
  target : layer;
  plane : plane;
  payload : string;
  law : string;
}

type workflow = {
  name : string;
  controller : string;
  layers : layer list;
  planes : plane list;
  laws : string list;
}

type violation =
  | Missing_source_domain of string
  | Duplicate_source_domain of string
  | Unknown_source_domain of string
  | Unclassified_source_domain of string
  | Wrong_authority of string
  | Missing_boundary of string
  | Runtime_boundary_gap of string
  | Missing_command_binding of string
  | Missing_event_binding of string

type t = {
  protocol : Playwright_ontology.t;
  source : Playwright_source_ontology.t;
  api : string;
  domains : domain list;
  flows : flow list;
  workflows : workflow list;
  missing_commands : string list;
  missing_events : string list;
}

let plane_name = function
  | Control -> "control"
  | Data -> "data"
  | Event -> "event"
  | Evidence -> "evidence"
  | Lifecycle -> "lifecycle"
  | Knowledge -> "knowledge"

let authority_name = function
  | Typed_protocol -> "typed-protocol"
  | Ocaml_workflow -> "ocaml-workflow"
  | External_substrate -> "external-substrate"
  | Knowledge_only -> "knowledge-only"
  | Gap -> "gap"

let layer_name = function
  | Program -> "L0-program"
  | Harness -> "L1-harness"
  | Binding -> "L2-ocaml-binding"
  | Driver -> "L3-playwright-driver"
  | Browser -> "L4-browser"
  | Context -> "L5-browser-context"
  | Page -> "L6-page"
  | Frame -> "L7-frame"
  | Locator -> "L8-locator"
  | Artifact -> "L9-artifact"

let expected_authority = function
  | "wire-protocol" | "client-api" -> Typed_protocol
  | "android-adapter" | "browser-delivery" | "browser-patch" | "browser-server"
  | "chromium-adapter" | "code-generation" | "dispatcher" | "electron-adapter"
  | "firefox-adapter" | "network-data" | "page-semantics" | "package-runtime"
  | "recorder-runtime" | "remote-transport" | "trace-runtime"
  | "web-bidi-adapter" | "webkit-adapter" -> External_substrate
  | "agent-tooling" | "assertion-runtime" | "cli-tooling" | "component-testing"
  | "html-reporter" | "recorder-ui" | "reporter-runtime" | "test-loading"
  | "test-model" | "test-plugin" | "test-runner" | "test-worker" | "trace-viewer"
  | "web-ui" -> Gap
  | "build-release-tooling" | "ci-governance" | "documentation" | "example-corpus"
  | "package-manifest" | "repository-foundation" | "shared-utility" | "test-corpus" ->
      Knowledge_only
  | _ -> Gap

let known_domain_kinds =
  [ "agent-tooling"; "android-adapter"; "assertion-runtime"; "browser-delivery";
    "browser-patch"; "browser-server"; "build-release-tooling";
    "chromium-adapter"; "ci-governance"; "cli-tooling"; "client-api";
    "code-generation"; "component-testing"; "dispatcher"; "documentation";
    "electron-adapter"; "example-corpus"; "firefox-adapter"; "html-reporter";
    "network-data"; "package-manifest"; "package-runtime"; "page-semantics";
    "recorder-runtime"; "recorder-ui"; "remote-transport"; "reporter-runtime";
    "repository-foundation"; "shared-utility"; "test-corpus"; "test-loading";
    "test-model"; "test-plugin"; "test-runner"; "test-worker"; "trace-runtime";
    "trace-viewer"; "web-bidi-adapter"; "web-ui"; "webkit-adapter";
    "wire-protocol" ]

let planes_for = function
  | Typed_protocol -> [ Control; Data; Event; Lifecycle ]
  | Ocaml_workflow -> [ Control; Data; Event; Evidence; Lifecycle ]
  | External_substrate -> [ Control; Data; Event; Lifecycle ]
  | Knowledge_only -> [ Knowledge ]
  | Gap -> []

let controller_for = function
  | Typed_protocol -> "Playwright_control + generated Playwright.Api"
  | Ocaml_workflow -> "OCaml harness"
  | External_substrate -> "Playwright.Api typed channel boundary"
  | Knowledge_only -> "Playwright_source_ontology inventory"
  | Gap -> ""

let boundary_for _kind authority =
  match authority with
  | Typed_protocol -> "OCaml value -> typed channel command/event -> driver"
  | External_substrate ->
      "external Playwright/browser implementation; reachable only through typed OCaml protocol and OCaml process lifecycle"
  | Knowledge_only -> "pinned source/documentation oracle; never executed as project control code"
  | Gap -> "not represented by a native OCaml feature-parity implementation"
  | Ocaml_workflow -> "authored OCaml workflow"

let residual_for kind =
  match expected_authority kind with
  | Gap ->
      "upstream product surface is inventoried but does not have native OCaml feature parity"
  | External_substrate ->
      "implementation internals remain upstream; OCaml owns requests, observations, lifecycle, and evidence at the protocol boundary"
  | Typed_protocol -> "none at the admitted protocol version"
  | Knowledge_only -> "reference material is not a runtime control surface"
  | Ocaml_workflow -> "none"

let domain kind =
  let authority = expected_authority kind in
  {
    source_kind = kind;
    authority;
    planes = planes_for authority;
    controller = controller_for authority;
    boundary = boundary_for kind authority;
    inputs =
      (match authority with
      | Typed_protocol -> [ "typed OCaml values"; "timeouts"; "capabilities" ]
      | External_substrate -> [ "protocol commands"; "browser binaries"; "environment" ]
      | Knowledge_only -> [ "pinned upstream files" ]
      | Gap -> [ "upstream semantics" ]
      | Ocaml_workflow -> [ "harness intents" ]);
    outputs =
      (match authority with
      | Typed_protocol -> [ "typed results"; "typed events"; "protocol errors" ]
      | External_substrate -> [ "browser state"; "events"; "artifacts" ]
      | Knowledge_only -> [ "inventory facts"; "traceability" ]
      | Gap -> [ "coverage obligation" ]
      | Ocaml_workflow -> [ "verdicts"; "evidence" ]);
    laws =
      (match authority with
      | Typed_protocol -> [ "command-totality"; "event-totality"; "reference-closure" ]
      | External_substrate -> [ "protocol-mediation"; "resource-bracketing"; "observation-honesty" ]
      | Knowledge_only -> [ "pin-integrity"; "inventory-totality" ]
      | Gap -> [ "no-false-full-control" ]
      | Ocaml_workflow -> [ "deterministic-verdict"; "evidence-provenance" ]);
    residual = residual_for kind;
  }

let flows =
  [
    { name = "intent"; source = Program; target = Harness; plane = Control;
      payload = "typed workflow request"; law = "intent is explicit and serializable" };
    { name = "api-call"; source = Harness; target = Binding; plane = Control;
      payload = "typed command and parameters"; law = "all protocol commands are bound" };
    { name = "wire-command"; source = Binding; target = Driver; plane = Control;
      payload = "Playwright channel message"; law = "request identity is preserved" };
    { name = "browser-command"; source = Driver; target = Browser; plane = Control;
      payload = "engine-specific operation"; law = "only admitted driver mediates browser internals" };
    { name = "context-create"; source = Browser; target = Context; plane = Lifecycle;
      payload = "isolated context options"; law = "contexts are bracketed" };
    { name = "page-create"; source = Context; target = Page; plane = Lifecycle;
      payload = "page lifecycle"; law = "pages close before context" };
    { name = "frame-route"; source = Page; target = Frame; plane = Control;
      payload = "navigation and frame operation"; law = "frame ownership is preserved" };
    { name = "locator-action"; source = Frame; target = Locator; plane = Control;
      payload = "selector, action, assertion observation"; law = "locator resolution is deferred" };
    { name = "page-data"; source = Locator; target = Binding; plane = Data;
      payload = "DOM values, geometry, accessibility, binary bodies"; law = "typed decoding is total or errors" };
    { name = "protocol-event"; source = Driver; target = Binding; plane = Event;
      payload = "console, request, response, dialog, download, worker, close";
      law = "all protocol events have typed subscriptions" };
    { name = "event-observe"; source = Binding; target = Harness; plane = Event;
      payload = "typed event stream"; law = "event order is observed, never fabricated" };
    { name = "artifact-capture"; source = Page; target = Artifact; plane = Evidence;
      payload = "screenshot, trace, video, HAR, download"; law = "artifact path and provenance are recorded" };
    { name = "verdict"; source = Artifact; target = Program; plane = Evidence;
      payload = "law results and evidence references"; law = "verdict derives only from observations" };
  ]

let workflows =
  [
    { name = "responsive-matrix"; controller = "Playwright_controller.run_matrix";
      layers = [ Harness; Binding; Browser; Context; Page; Locator; Artifact ];
      planes = [ Control; Data; Event; Evidence; Lifecycle ];
      laws = [ "window-classification"; "non-overlap"; "touch-target"; "console-clean" ] };
    { name = "protocol-ontology"; controller = "Playwright_ontology";
      layers = [ Harness; Binding; Driver ]; planes = [ Knowledge; Control; Event; Data ];
      laws = [ "command-totality"; "event-totality"; "reference-closure" ] };
    { name = "source-ontology"; controller = "Playwright_source_ontology";
      layers = [ Harness; Driver; Browser ]; planes = [ Knowledge ];
      laws = [ "artifact-totality"; "revision-pin"; "classification-totality" ] };
    { name = "fast-ooda"; controller = "OCaml harness supervisor";
      layers = [ Program; Harness; Binding; Browser; Artifact ];
      planes = [ Control; Data; Event; Evidence ];
      laws = [ "observe-before-orient"; "decision-from-facts"; "act-through-typed-api"; "feedback-is-evidence" ] };
    { name = "resource-lifecycle"; controller = "Playwright_controller.with_resource";
      layers = [ Harness; Binding; Driver; Browser; Context; Page ];
      planes = [ Lifecycle; Control ];
      laws = [ "close-on-success"; "close-on-error"; "reverse-acquisition-order" ] };
    { name = "artifact-evidence"; controller = "Playwright_controller";
      layers = [ Page; Artifact; Harness ]; planes = [ Data; Event; Evidence ];
      laws = [ "capture-provenance"; "observation-honesty"; "deterministic-orientation" ] };
  ]

let build ~protocol ~source ~api =
  let domains =
    Playwright_source_ontology.kind_counts source |> List.map (fun (kind, _) -> domain kind)
  in
  {
    protocol;
    source;
    api;
    domains;
    flows;
    workflows;
    missing_commands = Playwright_ontology.missing_command_bindings protocol api;
    missing_events = Playwright_ontology.missing_event_bindings protocol api;
  }

let source_kinds ontology =
  Playwright_source_ontology.kind_counts ontology.source |> List.map fst

let count_domain domains kind =
  List.fold_left (fun count domain -> count + Bool.to_int (domain.source_kind = kind)) 0 domains

let runtime_domains =
  [ "android-adapter"; "browser-delivery"; "browser-patch"; "browser-server";
    "chromium-adapter"; "client-api"; "code-generation"; "dispatcher";
    "electron-adapter"; "firefox-adapter"; "network-data"; "package-runtime";
    "page-semantics"; "recorder-runtime"; "remote-transport"; "trace-runtime";
    "web-bidi-adapter"; "webkit-adapter"; "wire-protocol" ]

let product_domains =
  [ "agent-tooling"; "assertion-runtime"; "cli-tooling"; "component-testing";
    "html-reporter"; "recorder-ui"; "reporter-runtime"; "test-loading";
    "test-model"; "test-plugin"; "test-runner"; "test-worker"; "trace-viewer";
    "web-ui" ]

let validate ontology =
  let known = source_kinds ontology in
  let violations = ref [] in
  List.iter
    (fun kind ->
      match count_domain ontology.domains kind with
      | 0 -> violations := Missing_source_domain kind :: !violations
      | 1 -> ()
      | _ -> violations := Duplicate_source_domain kind :: !violations)
    known;
  List.iter
    (fun row ->
      if not (List.mem row.source_kind known) then
        violations := Unknown_source_domain row.source_kind :: !violations;
      if not (List.mem row.source_kind known_domain_kinds) then
        violations := Unclassified_source_domain row.source_kind :: !violations;
      if row.authority <> expected_authority row.source_kind then
        violations := Wrong_authority row.source_kind :: !violations;
      (match row.authority with
      | Typed_protocol | Ocaml_workflow | External_substrate ->
          if row.controller = "" || row.boundary = "" then
            violations := Missing_boundary row.source_kind :: !violations
      | Knowledge_only | Gap -> ()))
    ontology.domains;
  List.iter
    (fun kind ->
      match List.find_opt (fun row -> row.source_kind = kind) ontology.domains with
      | Some { authority = Typed_protocol | External_substrate; _ } -> ()
      | Some _ | None -> violations := Runtime_boundary_gap kind :: !violations)
    runtime_domains;
  List.iter
    (fun name -> violations := Missing_command_binding name :: !violations)
    ontology.missing_commands;
  List.iter
    (fun name -> violations := Missing_event_binding name :: !violations)
    ontology.missing_events;
  List.rev !violations

let protocol_control_complete ontology =
  ontology.missing_commands = [] && ontology.missing_events = []

let runtime_boundary_complete ontology =
  protocol_control_complete ontology
  && List.for_all
       (fun kind ->
         match List.find_opt (fun row -> row.source_kind = kind) ontology.domains with
         | Some { authority = Typed_protocol | External_substrate; _ } -> true
         | Some _ | None -> false)
       runtime_domains

let product_gaps ontology =
  product_domains
  |> List.filter (fun kind ->
         match List.find_opt (fun row -> row.source_kind = kind) ontology.domains with
         | Some { authority = Gap; _ } | None -> true
         | Some _ -> false)

let product_parity_complete ontology = product_gaps ontology = []

let mutate_drop_domain ontology kind =
  { ontology with domains = List.filter (fun row -> row.source_kind <> kind) ontology.domains }

let mutate_authority ontology kind authority =
  {
    ontology with
    domains =
      List.map
        (fun row -> if row.source_kind = kind then { row with authority } else row)
        ontology.domains;
  }

let string_list_json values = `List (List.map (fun value -> `String value) values)

let domain_json (row : domain) =
  `Assoc
    [ ("source_kind", `String row.source_kind);
      ("authority", `String (authority_name row.authority));
      ("planes", string_list_json (List.map plane_name row.planes));
      ("controller", `String row.controller); ("boundary", `String row.boundary);
      ("inputs", string_list_json row.inputs); ("outputs", string_list_json row.outputs);
      ("laws", string_list_json row.laws); ("residual", `String row.residual) ]

let flow_json (flow : flow) =
  `Assoc
    [ ("name", `String flow.name); ("source", `String (layer_name flow.source));
      ("target", `String (layer_name flow.target)); ("plane", `String (plane_name flow.plane));
      ("payload", `String flow.payload); ("law", `String flow.law) ]

let workflow_json (workflow : workflow) =
  `Assoc
    [ ("name", `String workflow.name); ("controller", `String workflow.controller);
      ("layers", string_list_json (List.map layer_name workflow.layers));
      ("planes", string_list_json (List.map plane_name workflow.planes));
      ("laws", string_list_json workflow.laws) ]

let violation_name = function
  | Missing_source_domain name -> "missing-source-domain:" ^ name
  | Duplicate_source_domain name -> "duplicate-source-domain:" ^ name
  | Unknown_source_domain name -> "unknown-source-domain:" ^ name
  | Unclassified_source_domain name -> "unclassified-source-domain:" ^ name
  | Wrong_authority name -> "wrong-authority:" ^ name
  | Missing_boundary name -> "missing-boundary:" ^ name
  | Runtime_boundary_gap name -> "runtime-boundary-gap:" ^ name
  | Missing_command_binding name -> "missing-command-binding:" ^ name
  | Missing_event_binding name -> "missing-event-binding:" ^ name

let to_yojson ontology =
  `Assoc
    [ ("schema", `String "zigvm.playwright.ocaml-authority/v1");
      ("protocol_control_complete", `Bool (protocol_control_complete ontology));
      ("runtime_boundary_complete", `Bool (runtime_boundary_complete ontology));
      ("product_parity_complete", `Bool (product_parity_complete ontology));
      ("commands", `Int (Playwright_ontology.command_count ontology.protocol));
      ("events", `Int (Playwright_ontology.event_count ontology.protocol));
      ("product_gaps", string_list_json (product_gaps ontology));
      ("violations", string_list_json (List.map violation_name (validate ontology)));
      ("domains", `List (List.map domain_json ontology.domains));
      ("flows", `List (List.map flow_json ontology.flows));
      ("workflows", `List (List.map workflow_json ontology.workflows)) ]

let join values = if values = [] then "-" else String.concat ", " values

let render_markdown ontology =
  let buffer = Buffer.create 65536 in
  Buffer.add_string buffer "# Playwright OCaml authority and flow ontology\n\n";
  Buffer.add_string buffer
    (Printf.sprintf
       "**Admitted claim:** protocol control **%s** (%d commands, %d events); supported browser-runtime boundary **%s**; full upstream Playwright product parity **%s**. External browser and driver internals remain upstream substrates.\n\n"
       (if protocol_control_complete ontology then "COMPLETE" else "INCOMPLETE")
       (Playwright_ontology.command_count ontology.protocol)
       (Playwright_ontology.event_count ontology.protocol)
       (if runtime_boundary_complete ontology then "COMPLETE" else "INCOMPLETE")
       (if product_parity_complete ontology then "COMPLETE" else "PARTIAL"));
  Buffer.add_string buffer
    "`COMPLETE` means direct typed OCaml control at the pinned protocol boundary, not an OCaml rewrite of Chromium, Firefox, WebKit, the Playwright driver, or Playwright Test.\n\n";
  Buffer.add_string buffer "## Fractal authority matrix\n\n";
  Buffer.add_string buffer
    "| Upstream domain | Authority | Planes | OCaml controller/boundary | Residual |\n|---|---|---|---|---|\n";
  List.iter
    (fun (row : domain) ->
      let controller_boundary =
        if row.controller = "" then row.boundary
        else row.controller ^ "; " ^ row.boundary
      in
      Buffer.add_string buffer
        (Printf.sprintf "| `%s` | `%s` | %s | %s | %s |\n"
           row.source_kind (authority_name row.authority)
           (join (List.map plane_name row.planes)) controller_boundary row.residual))
    ontology.domains;
  Buffer.add_string buffer "\n## Nested runtime layers\n\n";
  [ Program; Harness; Binding; Driver; Browser; Context; Page; Frame; Locator; Artifact ]
  |> List.iter (fun layer -> Buffer.add_string buffer (Printf.sprintf "- `%s`\n" (layer_name layer)));
  Buffer.add_string buffer "\n## Control, data, event, lifecycle, and evidence flows\n\n";
  Buffer.add_string buffer "| Flow | From | To | Plane | Payload | Law |\n|---|---|---|---|---|---|\n";
  List.iter
    (fun (flow : flow) ->
      Buffer.add_string buffer
        (Printf.sprintf "| `%s` | `%s` | `%s` | `%s` | %s | %s |\n" flow.name
           (layer_name flow.source) (layer_name flow.target) (plane_name flow.plane)
           flow.payload flow.law))
    ontology.flows;
  Buffer.add_string buffer "\n## OCaml-owned workflows and Fast OODA\n\n";
  Buffer.add_string buffer "| Workflow | Controller | Layers | Planes | Laws |\n|---|---|---|---|---|---|\n";
  List.iter
    (fun (workflow : workflow) ->
      Buffer.add_string buffer
        (Printf.sprintf "| `%s` | `%s` | %s | %s | %s |\n" workflow.name workflow.controller
           (join (List.map layer_name workflow.layers))
           (join (List.map plane_name workflow.planes)) (join workflow.laws)))
    ontology.workflows;
  Buffer.add_string buffer "\n## Explicit product-parity gaps\n\n";
  List.iter
    (fun gap -> Buffer.add_string buffer (Printf.sprintf "- `%s`\n" gap))
    (product_gaps ontology);
  Buffer.add_string buffer "\n## Algebraic structures and laws\n\n";
  Buffer.add_string buffer
    "- Commands form a free sequential program whose interpretation is the typed Playwright channel.\n- Event subscriptions form observations; verdict equality is observational, never representation-based.\n- Resource acquisition is a stack discipline: release is total and reverse ordered.\n- Artifact accumulation is a provenance-preserving monoid under ordered concatenation.\n- Coverage authority is a total function from every upstream domain to exactly one authority class.\n- OODA is a guarded state machine: Observe -> Orient -> Decide -> Act -> Evidence -> Observe.\n- No-false-full-control: any product gap implies `product_parity_complete = false`.\n";
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
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"><key id=\"kind\" for=\"node\" attr.name=\"kind\" attr.type=\"string\"/><key id=\"rel\" for=\"edge\" attr.name=\"relation\" attr.type=\"string\"/><graph id=\"playwright-ocaml-authority\" edgedefault=\"directed\">\n";
  List.iter
    (fun layer ->
      Buffer.add_string buffer
        (Printf.sprintf "<node id=\"layer:%s\"><data key=\"kind\">layer</data></node>\n"
           (xml_escape (layer_name layer))))
    [ Program; Harness; Binding; Driver; Browser; Context; Page; Frame; Locator; Artifact ];
  List.iter
    (fun (row : domain) ->
      Buffer.add_string buffer
        (Printf.sprintf "<node id=\"domain:%s\"><data key=\"kind\">%s</data></node>\n"
           (xml_escape row.source_kind) (authority_name row.authority)))
    ontology.domains;
  List.iter
    (fun (flow : flow) ->
      Buffer.add_string buffer
        (Printf.sprintf "<edge source=\"layer:%s\" target=\"layer:%s\"><data key=\"rel\">%s:%s</data></edge>\n"
           (xml_escape (layer_name flow.source)) (xml_escape (layer_name flow.target))
           (plane_name flow.plane) (xml_escape flow.name)))
    ontology.flows;
  Buffer.add_string buffer "</graph></graphml>\n";
  Buffer.contents buffer
